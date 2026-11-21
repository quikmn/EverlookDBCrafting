-- Guild sharing: who in your guild knows a recipe. Guild members who run this addon tell each other which recipes
-- the character they are playing knows, with addon messages on the GUILD channel only (no public or custom channel:
-- servers switch those off once many players join). Only the logged-in character's own recipes are sent: never your
-- alts, never names. What others send is kept in memory only, never in saved variables, and is gone after a logout
-- or /reload until they send it again. Turn "Share recipes with my guild" off and nothing is sent, answered or kept.
--
-- Messages (prefix ECRAFT, version 1), each at most 250 bytes:
--   R1                       "please send your lists" (sent once after login; each member answers at most every 2 min)
--   K1:<skill>:<i>:<n>:<ids> part i of n of one profession's known recipe IDs, sorted, in base 36, the first absolute
--                            and each next one as the difference from the one before, separated by "."
-- The queue sends one message every 0.4 s at most and holds 80 at most; it waits while you are in combat.
local _, ns = ...
local try, plain = ns.try, ns.plain

local G = {}
ns.guild = G

ns.DEFAULTS.settings.guildShare = true

G.PREFIX = "ECRAFT"
G.GAP = 0.4
G.QUEUE_MAX = 80
G.ANSWER_EVERY = 120
G.MAX_MEMBERS = 1000
local PAYLOAD = 230

-- in memory only: sender -> { profs = { [skill] = { [spell] = true } }, at }
local heard = {}
local parts = {}   -- sender -> skill -> { n, got = { [i] = { ids } }, count }
local queue = {}
local sending = false
local lastAnswer, lastSent = -1e9, {}

function G.enabled() return ns.settings().guildShare ~= false end

local function now() return plain(try(GetTime)) or 0 end
local function inGuild() return try(IsInGuild) and true or false end

-- "Name-Realm" -> "Name" for your own realm's members (the game's own rule when it has it)
local function short(name)
  local s = Ambiguate and plain(try(Ambiguate, name, "guild"))
  return s or (name:match("^([^%-]+)") or name)
end

local function myNames()
  local n = plain(try(UnitName, "player"))
  local full = n and plain(try(GetRealmName)) and (n .. "-" .. (plain(try(GetRealmName)):gsub("%s", "")))
  return n, full
end

local function isMe(sender)
  local n, full = myNames()
  return sender == n or sender == full or short(sender) == n
end

---------------------------------------------------------------------------------------------------------------------
-- Encoding

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end

-- sorted IDs -> payload strings, each at most PAYLOAD bytes
function G.encode(ids)
  local out, cur, prev = {}, {}, nil
  local len = 0
  for _, id in ipairs(ids) do
    local tok = b36(prev and (id - prev) or id)
    if len + #tok + 1 > PAYLOAD and #cur > 0 then
      out[#out + 1] = table.concat(cur, ".")
      cur, len, prev = {}, 0, nil
      tok = b36(id)
    end
    cur[#cur + 1] = tok
    len = len + #tok + 1
    prev = id
  end
  if #cur > 0 then out[#out + 1] = table.concat(cur, ".") end
  return out
end

-- payload -> IDs, or nil when it isn't well formed
function G.decode(s)
  if type(s) ~= "string" or s == "" or s:find("[^0-9a-z%.]") then return nil end
  local ids, prev = {}, nil
  for tok in s:gmatch("[^%.]+") do
    local n = tonumber(tok, 36)
    if not n then return nil end
    local id = prev and (prev + n) or n
    if id <= 0 or id > 10000000 then return nil end
    ids[#ids + 1] = id
    prev = id
    if #ids > 400 then return nil end
  end
  return ids
end

-- this character's known recipes of a profession, sorted
local function myKnown(skill)
  local p = ns.scan.mine(skill)
  local ids = {}
  for spell in pairs(p and p.known or {}) do
    if type(spell) == "number" then ids[#ids + 1] = spell end
  end
  table.sort(ids)
  return ids
end

-- the messages that tell the guild one profession: { "K1:...", ... }
function G.messages(skill)
  local ids = myKnown(skill)
  if #ids == 0 then return {} end
  local chunks = G.encode(ids)
  local out = {}
  for i, c in ipairs(chunks) do out[i] = ("K1:%d:%d:%d:%s"):format(skill, i, #chunks, c) end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- Sending (throttled)

local function send(msg)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    return try(C_ChatInfo.SendAddonMessage, G.PREFIX, msg, "GUILD")
  end
  return try(SendAddonMessage, G.PREFIX, msg, "GUILD")
end
G.send = send

local function pump()
  if #queue == 0 then sending = false return end
  if not G.enabled() or not inGuild() then queue = {}; sending = false return end
  if try(InCombatLockdown) then C_Timer.After(2, pump) return end
  send(table.remove(queue, 1))
  C_Timer.After(G.GAP, pump)
end

function G.enqueue(msg)
  if not G.enabled() or not inGuild() then return false end
  for _, q in ipairs(queue) do if q == msg then return true end end
  if #queue >= G.QUEUE_MAX then return false end
  queue[#queue + 1] = msg
  if not sending then
    sending = true
    C_Timer.After(G.GAP, pump)
  end
  return true
end
function G.queueSize() return #queue end

-- tell the guild one profession (only when it changed since the last time, unless force)
function G.share(skill, force)
  local msgs = G.messages(skill)
  local key = table.concat(msgs, "|")
  if not force and lastSent[skill] == key then return 0 end
  lastSent[skill] = key
  for _, m in ipairs(msgs) do G.enqueue(m) end
  return #msgs
end

function G.shareAll(force)
  local me = ns.me()
  local n = 0
  for skill in pairs(me and me.profs or {}) do
    if ns.DATA and ns.DATA.profs[skill] then n = n + G.share(skill, force) end
  end
  return n
end

---------------------------------------------------------------------------------------------------------------------
-- Receiving

local function members()
  local n = 0
  for _ in pairs(heard) do n = n + 1 end
  return n
end

local function partsCount()
  local n = 0
  for _ in pairs(parts) do n = n + 1 end
  return n
end

function G.receive(prefix, msg, channel, sender)
  if prefix ~= G.PREFIX or channel ~= "GUILD" or not G.enabled() then return end
  msg, sender = plain(msg), plain(sender)
  if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" or isMe(sender) then return end
  if msg == "R1" then
    -- answer once in a while, after a random wait, so many members don't answer all at once
    if now() - lastAnswer < G.ANSWER_EVERY then return end
    lastAnswer = now()
    C_Timer.After(3 + math.random() * 17, function() G.shareAll(true) end)
    return
  end
  local skill, i, n, payload = msg:match("^K1:(%d+):(%d+):(%d+):([0-9a-z%.]+)$")
  skill, i, n = tonumber(skill), tonumber(i), tonumber(n)
  if not skill or not ns.DATA or not ns.DATA.profs[skill] or i < 1 or n < 1 or i > n or n > 20 then return end
  local ids = G.decode(payload)
  if not ids then return end
  -- a cap on senders, half-sent lists included, so a flood can't grow memory
  if not heard[sender] and not parts[sender] and members() + partsCount() >= G.MAX_MEMBERS then return end
  local bySender = parts[sender] or {}
  parts[sender] = bySender
  local p = bySender[skill]
  if i == 1 or not p or p.n ~= n then p = { n = n, got = {}, count = 0 } end
  if not p.got[i] then p.got[i], p.count = ids, p.count + 1 end
  bySender[skill] = p
  if p.count < p.n then return end
  bySender[skill] = nil
  if next(bySender) == nil then parts[sender] = nil end
  local set = {}
  for k = 1, p.n do for _, id in ipairs(p.got[k]) do set[id] = true end end
  local h = heard[sender] or { profs = {} }
  h.profs[skill], h.at = set, time()
  heard[sender] = h
  if ns.onGuild then ns.onGuild(sender, skill) end
end

-- guild members who know a recipe (short names, sorted): what they told us this session
function G.knows(spell)
  local out = {}
  if not G.enabled() or type(spell) ~= "number" then return out end
  local r = ns.recipeBySpell(spell)
  local key = r and r.spell or spell
  local skill = r and r.skill
  for sender, h in pairs(heard) do
    local found = false
    if skill then
      local set = h.profs[skill]
      found = set and (set[key] or set[spell]) or false
    else
      for _, set in pairs(h.profs) do if set[spell] then found = true break end end
    end
    if found then out[#out + 1] = short(sender) end
  end
  table.sort(out)
  return out
end

function G.count() return members() end
function G.partial() return partsCount() end

function G.forget()
  heard, parts, queue, lastSent = {}, {}, {}, {}
end

---------------------------------------------------------------------------------------------------------------------
-- Events

local function start()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    try(C_ChatInfo.RegisterAddonMessagePrefix, G.PREFIX)
  elseif RegisterAddonMessagePrefix then
    try(RegisterAddonMessagePrefix, G.PREFIX)
  end
end
start()

ns.on("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
  if prefix ~= G.PREFIX then return end
  G.receive(prefix, msg, channel, sender)
end)

-- after login, with a random wait: ask the guild for their lists and tell ours
ns.on("PLAYER_LOGIN", function()
  if not EverlookCraftDB then return end
  C_Timer.After(15 + math.random() * 30, function()
    if not G.enabled() or not inGuild() then return end
    G.enqueue("R1")
    G.shareAll(true)
  end)
end)

-- left the guild: what its members told us goes
ns.on("PLAYER_GUILD_UPDATE", function()
  if not inGuild() then G.forget() end
end)

-- a profession window read: tell the guild if the list changed (a few seconds later, once)
local pendingShare = {}
local prevScanned = ns.onScanned
ns.onScanned = function(skill)
  if prevScanned then prevScanned(skill) end
  if not G.enabled() or pendingShare[skill] then return end
  pendingShare[skill] = true
  C_Timer.After(5, function()
    pendingShare[skill] = nil
    if inGuild() then G.share(skill) end
  end)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

local app = ns.app
app:Setting({ key = "guild.share", type = "bool", label = "Share recipes with my guild",
  desc = "Guild members with this addon see which recipes the character you play knows, and you see theirs.",
  keywords = { "guild", "share", "crafter", "who can craft", "privacy" }, default = true,
  get = function() return G.enabled() end,
  set = function(v)
    ns.settings().guildShare = v and true or false
    if not v then G.forget() elseif inGuild() then G.enqueue("R1"); G.shareAll(true) end
  end })

app:Section("guild", "Guild", function(stack)
  local UI = LibStub("EverlookUI-1")
  UI.Header(stack, "Guild crafters", "Who in your guild knows a recipe, from guild members who also run EverlookDB Crafting.")
  app:Widget(stack, "guild.share")
  UI.Stat(stack, "Guild members heard", function()
    if not G.enabled() then return "|cff8d94a3sharing is off|r" end
    if not inGuild() then return "|cff8d94a3not in a guild|r" end
    return tostring(members())
  end)
  UI.Note(stack, "Sent: which recipes the character you are playing knows, on the guild channel only. Not sent: your alts, your bags, prices, names. Received lists stay in memory until you log out; nothing about other players is written to disk. Switched off: nothing is sent, answered or kept.")
end, { icon = "share", desc = "\"Guild can make this\" in tooltips: who in your guild knows a recipe." })
