-- Offline tests for EverlookDB Crafting's game integrations (Tooltips.lua, Guild.lua, Capture.lua, Merchant.lua)
-- against wowmock.lua, in their own Lua state: the tooltip lines (materials, crafted items, recipe items, Shift
-- details, no line twice, each setting), guild sharing (encoding, throttle, GUILD only, nothing on disk, opt-out),
-- trainer and merchant capture (per realm, overriding the data) and "Buy what the route needs" (never more than
-- needed, one confirm, money check).
local ROOT = ...
local ADDON = "EverlookDBCrafting"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passes = passes + 1
    print("  ok   " .. name)
  else
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("  FAIL " .. name .. "\n         " .. tostring(err))
  end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

time = time or os.time
date = date or os.date
MOCK.secretsOn = false
MOCK.SetGroup(1)
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitLevel = function() return 30 end
Settings = { RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end, RegisterAddOnCategory = function() end }
MOCK.skills = { { "Professions", true }, { "Tailoring", false, 60, 75 } }
GetNumSkillLines = function() return #MOCK.skills end
GetSkillLineInfo = function(i) local s = MOCK.skills[i]; if s then return s[1], s[2], nil, s[3], nil, nil, s[4] end end
MOCK.realm = "Mock Realm"
GetRealmName = function() return MOCK.realm end
IsInGuild = function() return MOCK.guild end
MOCK.guild = true
MOCK.sent = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) MOCK.prefix = p; return true end,
  SendAddonMessage = function(prefix, msg, channel) table.insert(MOCK.sent, { prefix, msg, channel }); return true end,
}
Ambiguate = function(name) return (name:match("^([^%-]+)")) end
MOCK.money = 1000000
GetMoney = function() return MOCK.money end

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

local function loadToc()
  local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
      local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
      if not chunk then error("syntax: " .. err) end
      setfenv(chunk, addonEnv)
      chunk(ADDON, ns)
    end
  end
end

-- run queued timers until none are left (at most n rounds)
local function drain(n)
  for _ = 1, n or 50 do
    if #MOCK.timers == 0 then return end
    local t = MOCK.timers
    MOCK.timers = {}
    for _, fn in ipairs(t) do fn() end
  end
end

local Tip
-- the tooltip text for an item: { "label|value", ... } (colour codes and textures stripped)
local function tip(id, shift)
  local lines = Tip:Collect("item", { id = id, kind = "item" }, shift)
  local out = {}
  for _, l in ipairs(lines) do
    local s = (l[1] or "") .. (l[2] and ("|" .. l[2]) or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    out[#out + 1] = s
  end
  return out
end
local function has(lines, pat)
  for _, l in ipairs(lines) do if l:find(pat) then return l end end
end

local TAILORING = 197
local LINEN, BOLT, THREAD = 2589, 2996, 2320

step("loads in TOC order with the integrations, and the tooltip library", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  Tip = LibStub("EverlookTooltip-1", true)
  check(Tip, "EverlookTooltip not loaded")
  check(ns.tooltips and ns.guild and ns.capture and ns.merchant, "modules")
  eq(MOCK.prefix, "ECRAFT", "addon message prefix")
  for k in pairs(globalWrites) do
    check(k == "EverlookCraftDB" or k == "EverlookCraftChar" or k == "EverlookCraftAPI" or k:match("^SLASH_EVERLOOKCRAFT")
      or k:match("^EverlookCraft"), "unexpected global " .. k)
  end
  local reg
  for _, c in ipairs(Tip.contrib.item) do if c.id == "EverlookDBCrafting.crafting" then reg = c end end
  check(reg, "tooltip contribution not registered")
end)

-- your characters: you (Tailoring 60) and two alts on this realm, one on another realm
local recipeItem, recipeRow
step("setup: characters, known recipes, a recipe item from the data", function()
  local me = ns.me()
  me.profs[TAILORING] = { rank = 60, max = 75, known = { [2963] = true } } -- Bolt of Linen Cloth
  me.bags = { [LINEN] = 4 }
  EverlookCraftDB.chars["Player-1-Altie"] = { name = "Altie", realm = "Mock Realm", side = "a",
    profs = { [TAILORING] = { rank = 160, max = 225, known = { [2963] = true } } }, bags = {}, bank = {} }
  EverlookCraftDB.chars["Player-1-Lowbie"] = { name = "Lowbie", realm = "Mock Realm", side = "a",
    profs = { [TAILORING] = { rank = 10, max = 75, known = {} } }, bags = {}, bank = {} }
  EverlookCraftDB.chars["Player-2-Faraway"] = { name = "Faraway", realm = "Other Realm", side = "a",
    profs = { [TAILORING] = { rank = 300, max = 300, known = { [2963] = true } } }, bags = {}, bank = {} }
  -- a pattern with a learn skill between Lowbie's and Altie's, that nobody knows yet
  for _, r in ipairs(ns.recipes(TAILORING)) do
    if r.item and r.item ~= 0 and r.learn > 60 and r.learn <= 160 and not ns.tooltips.index().makes[r.item] then
      recipeItem, recipeRow = r.item, r
      break
    end
  end
  check(recipeItem, "no pattern in the data")
end)

step("tooltip, material: used in N of your recipes, with the recipes as details", function()
  local lines = tip(LINEN, false)
  local used = has(lines, "^Used in")
  check(used and used:find("1 of your recipes", 1, true), "Used in line: " .. table.concat(lines, " / "))
  check(used:find("Tailoring", 1, true), "profession note")
  check(has(lines, "Bolt of Linen Cloth"), "recipe detail missing")
  -- the other realm's character's recipes count too (materials can be mailed between realms? no, but recipes are
  -- yours): nothing doubled
  local seen = {}
  for _, l in ipairs(lines) do check(not seen[l], "line twice: " .. l); seen[l] = true end
end)

step("tooltip details: only with Shift when the shared setting says so", function()
  ns.tooltips.detail("shift")
  eq(Tip:GetDetail(), "shift", "shared setting")
  check(not has(tip(LINEN, false), "Bolt of Linen Cloth"), "detail shown without Shift")
  check(has(tip(LINEN, true), "Bolt of Linen Cloth"), "detail hidden with Shift")
  ns.tooltips.detail("always")
end)

step("tooltip, crafted: you can make this (skill, in colour), your alts on this realm can too", function()
  local lines = tip(BOLT, false)
  local you = has(lines, "^You can make this")
  check(you and you:find("Tailoring 60", 1, true), "you: " .. table.concat(lines, " / "))
  local alt = has(lines, "^Your alt can make this")
  check(alt and alt:find("Altie", 1, true), "alt: " .. table.concat(lines, " / "))
  check(not table.concat(lines, "\n"):find("Faraway", 1, true), "another realm's character listed")
  -- the raw line carries the recipe's colour at your skill
  local raw = Tip:Collect("item", { id = BOLT, kind = "item" }, false)
  local r = ns.recipes(TAILORING).bySpell[2963]
  local key = ns.colorAt(r, 60)
  local c = ns.COLORS[key]
  local code = ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
  local found = false
  for _, l in ipairs(raw) do if l[2] and l[2]:find(code, 1, true) then found = true end end
  -- grey (no more skill-ups) stays plain white: grey text is hard to read on a tooltip
  if key == "gray" then check(not found, "grey skill coloured") else check(found, "skill not in the recipe's colour") end
  -- at a skill where the recipe is orange, it is
  local low = r.learn or 1
  eq(ns.colorAt(r, low) ~= "gray", true, "orange at its learn skill")
end)

step("tooltip, recipe item: known by / learnable by / learnable later, and only these", function()
  EverlookCraftDB.chars["Player-1-Altie"].profs[TAILORING].known[recipeRow.spell] = nil
  local lines = tip(recipeItem, false)
  local now = has(lines, "^Learnable by")
  check(now and now:find("Altie", 1, true), "learnable by: " .. table.concat(lines, " / "))
  local later = has(lines, "^Learnable later by")
  check(later and later:find("You", 1, true) and later:find("Lowbie", 1, true), "later: " .. table.concat(lines, " / "))
  check(not has(lines, "^Known by"), "nobody knows it yet")
  check(not has(lines, "^Used in") and not has(lines, "can make this"), "a recipe item gets only the recipe lines")
  EverlookCraftDB.chars["Player-1-Altie"].profs[TAILORING].known[recipeRow.spell] = true
  lines = tip(recipeItem, false)
  local known = has(lines, "^Known by")
  check(known and known:find("Altie", 1, true), "known by: " .. table.concat(lines, " / "))
  check(not (has(lines, "^Learnable by") or ""):find("Altie", 1, true), "Altie both known and learnable")
end)

step("tooltip settings: each part can be turned off", function()
  local s = EverlookCraftDB.settings
  s.tipReagent = false
  check(not has(tip(LINEN, false), "^Used in"), "material lines still shown")
  s.tipReagent = true
  s.tipCrafted = false
  check(not has(tip(BOLT, false), "can make this"), "crafted lines still shown")
  s.tipCrafted = true
  s.tipRecipe = false
  eq(#tip(recipeItem, false), 0, "recipe lines still shown")
  s.tipRecipe = true
  SlashCmdList.EVERLOOKCRAFT("tip.reagent off")
  eq(s.tipReagent, false, "setting from chat")
  SlashCmdList.EVERLOOKCRAFT("tip.reagent on")
end)

step("tooltip, material on a route: how many more the route needs", function()
  -- a hand-made route: 6 crafts of Bolt of Linen Cloth (2 linen each) from 60
  EverlookCraftChar.routes[TAILORING] = { skill = TAILORING, from = 60, to = 70, key = "", steps = {
    { spell = 2963, from = 60, to = 70, n = 5, n90 = 6 } }, crafted = {}, raw = {}, trainings = {} }
  EverlookCraftChar.done[TAILORING] = {}
  local need = ns.tooltips.routeNeed(LINEN)
  check(need, "no route need")
  eq(need.need, 12, "needed (90% buffer: 6 crafts x 2)")
  local lines = tip(LINEN, false)
  local l = has(lines, "^Skill%-up route")
  check(l and l:find("more", 1, true), "route line: " .. table.concat(lines, " / "))
  check(has(lines, "Needed / you have"), "detail")
  -- you have enough: the line says so instead
  ns.me().bags[LINEN] = 400
  check((has(tip(LINEN, false), "^Skill%-up route") or ""):find("enough", 1, true), "enough")
  ns.me().bags[LINEN] = 4
end)

---------------------------------------------------------------------------------------------------------------------
-- Guild

local G
step("guild: recipe IDs encode in base 36 deltas and decode back, in messages of at most 250 bytes", function()
  G = ns.guild
  local ids = {}
  for i = 1, 300 do ids[i] = 2000 + i * 37 end
  local chunks = G.encode(ids)
  check(#chunks >= 2, "300 IDs should take more than one message")
  local back = {}
  for _, c in ipairs(chunks) do
    check(#("K1:197:10:10:" .. c) <= 250, "message too long: " .. #c)
    for _, id in ipairs(G.decode(c)) do back[#back + 1] = id end
  end
  eq(#back, #ids, "count")
  for i = 1, #ids do eq(back[i], ids[i], "id " .. i) end
  eq(G.decode("12,x"), nil, "malformed accepted")
  eq(G.decode(""), nil, "empty accepted")
end)

local function hear(sender, msgs, channel)
  for _, m in ipairs(msgs) do
    MOCK.Fire("CHAT_MSG_ADDON", "ECRAFT", m, channel or "GUILD", sender)
  end
end

step("guild: a member's lists are put together from their parts; who knows a recipe", function()
  local ids = { 2963 }
  for i = 1, 200 do ids[#ids + 1] = 30000 + i * 11 end
  table.sort(ids)
  local chunks = G.encode(ids)
  local msgs = {}
  for i, c in ipairs(chunks) do msgs[i] = ("K1:%d:%d:%d:%s"):format(TAILORING, i, #chunks, c) end
  hear("Anna-Mock Realm", { msgs[1] })
  eq(#G.knows(2963), 0, "known before the last part")
  local rest = {}
  for i = 2, #msgs do rest[#rest + 1] = msgs[i] end
  hear("Anna-Mock Realm", rest)
  local who = G.knows(2963)
  eq(#who, 1, "Anna knows Bolt of Linen Cloth")
  eq(who[1], "Anna", "short name")
  local api = EverlookCraftAPI.guildKnows(2963)
  eq(api[1], "Anna", "api.guildKnows")
  eq(EverlookCraftAPI.version, 5, "api version")
  check(has(tip(BOLT, false), "^Guild can make this"), "guild line on the crafted item")
end)

step("guild: only the GUILD channel, never yourself, nothing malformed", function()
  hear("Bob", { "K1:197:1:1:" .. G.encode({ 2963 })[1] }, "WHISPER")
  hear("Cid", { "K1:197:1:1:" .. G.encode({ 2963 })[1] }, "CHANNEL")
  hear("Tester-Mock Realm", { "K1:197:1:1:" .. G.encode({ 2963 })[1] })
  hear("Dan", { "K1:197:1:1:ZZ!!", "K1:999999:1:1:1a", "K1:197:2:1:1a", "nonsense" })
  eq(#G.knows(2963), 1, "only Anna")
end)

step("guild: half-sent lists are capped too (a flood can't grow memory), and dropped once complete", function()
  local max = G.MAX_MEMBERS
  G.MAX_MEMBERS = G.count() + 3
  local part = "K1:197:1:2:" .. G.encode({ 2963 })[1]
  for i = 1, 10 do hear("Flood" .. i, { part }) end
  eq(G.partial(), 3, "only 3 half-sent lists kept")
  hear("Flood1", { "K1:197:2:2:" .. G.encode({ 3000 })[1] })
  eq(G.partial(), 2, "a completed list leaves the half-sent ones")
  G.MAX_MEMBERS = max
end)

step("guild: names are kept in memory only, never in the saved variables", function()
  local function scan(t, depth, seen)
    if depth > 12 or seen[t] then return false end
    seen[t] = true
    for k, v in pairs(t) do
      if k == "Anna" or v == "Anna" or k == "Anna-Mock Realm" or v == "Anna-Mock Realm" then return true end
      if type(v) == "table" and scan(v, depth + 1, seen) then return true end
    end
    return false
  end
  check(not scan(EverlookCraftDB, 0, {}), "a guild member's name in EverlookCraftDB")
  check(not scan(EverlookCraftChar, 0, {}), "a guild member's name in EverlookCraftChar")
end)

step("guild: sending is throttled (one message per timer), GUILD only, and a request is answered once in a while", function()
  MOCK.sent = {}
  MOCK.timers = {}
  local n = G.shareAll(true)
  check(n >= 1, "nothing to share")
  check(#MOCK.sent == 0, "sent without waiting")
  MOCK.RunTimers()
  eq(#MOCK.sent, 1, "one message per tick")
  drain()
  eq(#MOCK.sent, n, "all sent")
  for _, s in ipairs(MOCK.sent) do
    eq(s[1], "ECRAFT", "prefix"); eq(s[3], "GUILD", "channel")
    check(#s[2] <= 250, "too long")
  end
  check(MOCK.sent[1][2]:find("^K1:197:"), "our Tailoring list: " .. MOCK.sent[1][2])
  -- unchanged: not sent again
  eq(G.share(TAILORING), 0, "an unchanged list sent again")
  -- a request: answered after a wait, then not again within 2 minutes
  MOCK.sent = {}
  hear("Eve", { "R1" })
  drain()
  check(#MOCK.sent >= 1, "request not answered")
  MOCK.sent = {}
  hear("Fay", { "R1" })
  drain()
  eq(#MOCK.sent, 0, "answered twice within 2 minutes")
  -- the queue has a cap
  for i = 1, 200 do G.enqueue("K1:197:1:1:" .. i) end
  check(G.queueSize() <= G.QUEUE_MAX, "queue over its cap")
  drain(400)
end)

step("guild: opt out stops sending and forgets what was heard", function()
  SlashCmdList.EVERLOOKCRAFT("guild.share off")
  eq(EverlookCraftDB.settings.guildShare, false, "setting")
  eq(#G.knows(2963), 0, "still knows after opting out")
  eq(#EverlookCraftAPI.guildKnows(2963), 0, "api after opting out")
  eq(G.enqueue("R1"), false, "queued while off")
  hear("Anna", { "K1:197:1:1:" .. G.encode({ 2963 })[1] })
  eq(#G.knows(2963), 0, "listening while off")
  check(not has(tip(BOLT, false), "^Guild"), "guild line while off")
  SlashCmdList.EVERLOOKCRAFT("guild.share on")
  drain(400)
  MOCK.guild = false
  eq(G.enqueue("R1"), false, "queued outside a guild")
  MOCK.guild = true
end)

---------------------------------------------------------------------------------------------------------------------
-- Capture

local function trainer(services)
  GetNumTrainerServices = function() return #services end
  GetTrainerServiceInfo = function(i) local s = services[i]; return s.name, s.sub, s.kind or "available", true end
  GetTrainerServiceCost = function(i) return services[i].cost end
  GetTrainerServiceSkillReq = function(i) local s = services[i]; return s.reqName or "Tailoring", s.req, true end
  GetTrainerServiceSkillLine = function(i) return services[i].line end
  GetTrainerServiceLevelReq = function(i) return services[i].level or 0 end
  GetTrainerServiceItemLink = function(i) local s = services[i]; return s.item and ("|cffffffff|Hitem:" .. s.item .. ":0|h[x]|h|r") end
end

step("trainer window: recipe fees and learn skills saved per realm and used instead of the data", function()
  local cloak = ns.recipes(TAILORING).bySpell[2387] -- Linen Cloak
  check(cloak, "Linen Cloak in the data")
  trainer({
    { name = "Linen Cloak", cost = 77, req = 1, line = "Tailoring" },
    { name = "Something Else", cost = 5, req = 1, line = "Tailoring", item = cloak.creates }, -- found by what it makes
    { name = "Tailoring", sub = "Journeyman", cost = 555, req = 50, level = 10 },
    { name = "Header", kind = "header" },
    { name = "Not A Recipe", cost = 9, req = 1, line = "Tailoring" },
  })
  local fees, ranks = ns.capture.readTrainer()
  eq(ranks, 1, "rank fees")
  eq(fees, 2, "recipe fees")
  local rec = EverlookCraftDB.realms["Mock Realm"]
  check(rec and rec.fees[2387], "not saved per realm")
  eq(cloak.fee, 5, "fee not used (the later service of the same recipe wins)")
  check(cloak.learnKnown, "learn skill still an estimate")
  eq(ns.DATA.ranks[TAILORING][2][4], 555, "rank fee not used")
  -- the event reads it too
  ns.capture.forget()
  MOCK.Fire("TRAINER_SHOW")
  drain()
  check(EverlookCraftDB.realms["Mock Realm"].fees[2387], "TRAINER_SHOW didn't read the window")
end)

local function merchant(rows)
  GetMerchantNumItems = function() return #rows end
  GetMerchantItemID = function(i) return rows[i].id end
  GetMerchantItemInfo = function(i)
    local r = rows[i]
    return "item", 1, r.price, r.qty or 1, r.avail or -1, true, true, r.ext or false
  end
  GetMerchantItemMaxStack = function(i) return rows[i].stack or 20 end
end

step("merchant window: material prices saved per realm, used before the data; limited and token goods left out", function()
  local idx = ns.tooltips.index()
  -- a reagent the data has no vendor for
  local noVendor
  for id in pairs(idx.usedIn) do
    local it = ns.DATA.items[id]
    if it and not it[4] then noVendor = id break end
  end
  merchant({
    { id = THREAD, price = 40, qty = 4 },           -- 10c each
    { id = noVendor, price = 300, avail = 2 },      -- limited: not a vendor good
    { id = 2604, price = 99, ext = true },          -- a token cost
    { id = 6948, price = 1 },                       -- not a material
  })
  local n = ns.capture.readMerchant()
  eq(n, 1, "saved")
  eq(ns.prices.vendor(THREAD), 10, "seen price per unit")
  eq(ns.capture.price(noVendor), nil, "limited stock saved as a vendor good")
  eq(ns.capture.price(2604), nil, "token good saved")
  -- unlimited: from now on a vendor good
  merchant({ { id = noVendor, price = 300 } })
  ns.capture.readMerchant()
  eq(ns.prices.vendor(noVendor), 300, "an unlimited merchant good")
  -- another realm: the data again
  MOCK.realm = "Other Realm"
  local data = ns.DATA.items[THREAD][4]
  eq(ns.prices.vendor(THREAD), EverlookCraftDB.seen[THREAD] or data, "another realm uses this realm's price")
  MOCK.realm = "Mock Realm"
  EverlookCraftDB.settings.capture = false
  merchant({ { id = THREAD, price = 80 } })
  ns.capture.readMerchant()
  eq(ns.prices.vendor(THREAD), 10, "saved while turned off")
  EverlookCraftDB.settings.capture = true
end)

---------------------------------------------------------------------------------------------------------------------
-- Merchant: buy what the route needs

step("merchant plan: never more than the route still needs, packs rounded up, limited stock respected", function()
  local M = ns.merchant
  local rows = {
    { id = 1, index = 1, price = 10, qty = 1, avail = -1, maxStack = 20 },
    { id = 2, index = 2, price = 50, qty = 5, avail = -1 },
    { id = 3, index = 3, price = 7, qty = 1, avail = 2 },
    { id = 4, index = 4, price = 1, qty = 1, avail = -1 },
    { id = 5, index = 5, price = 9, qty = 1, avail = -1, extended = true },
  }
  local list, total = M.plan(rows, { [1] = 45, [2] = 7, [3] = 9, [5] = 3 })
  local by = {}
  for _, e in ipairs(list) do by[e.id] = e end
  eq(by[1].n, 45, "single items: exactly the need")
  eq(by[2].packs, 2, "packs of 5 for 7")
  eq(by[3].n, 2, "only what the merchant has")
  eq(by[4], nil, "not needed")
  eq(by[5], nil, "token good")
  eq(total, 450 + 100 + 14, "total")
end)

step("merchant: the bar shows the route's vendor materials; first click asks, second buys, never twice", function()
  local M = ns.merchant
  MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
  MerchantFrame:SetSize(336, 444)
  MerchantFrame:Show()
  -- a route of Linen Cloaks: thread is a vendor good
  EverlookCraftChar.routes[TAILORING] = { skill = TAILORING, from = 60, to = 75, key = "", steps = {
    { spell = 2387, from = 60, to = 75, n = 8, n90 = 10 } }, crafted = {}, raw = {}, trainings = {} }
  ns.me().bags[THREAD] = 0
  local need = ns.plans.remaining(EverlookCraftChar.routes[TAILORING], 60)[THREAD]
  check(need and need > 0, "the route needs thread")
  merchant({ { id = THREAD, price = 10, qty = 1, stack = 20 }, { id = 6948, price = 1 } })
  MOCK.bought = {}
  BuyMerchantItem = function(i, n) table.insert(MOCK.bought, { i, n or 1 }) end
  MOCK.Fire("MERCHANT_SHOW")
  drain()
  local bar = EverlookCraftMerchantBar
  check(bar and bar:IsShown(), "bar not shown")
  check(bar.title:GetText():find("1 material", 1, true), "title: " .. tostring(bar.title:GetText()))
  bar.button:GetScript("OnClick")(bar.button)
  eq(#MOCK.bought, 0, "bought on the first click")
  check(bar.button:GetText():find("Buy for", 1, true), "no price on the confirm: " .. tostring(bar.button:GetText()))
  bar.button:GetScript("OnClick")(bar.button)
  local got = 0
  for _, b in ipairs(MOCK.bought) do eq(b[1], 1, "bought the wrong row"); check(b[2] <= 20, "more than a stack per call"); got = got + b[2] end
  eq(got, need - ns.stock.usable(THREAD), "bought more or less than the route needs")
  -- before the bags update, a second round buys nothing more
  MOCK.bought = {}
  local list = M.current()
  eq(#list, 0, "would buy the same again")
  bar.button:GetScript("OnClick")(bar.button)
  bar.button:GetScript("OnClick")(bar.button)
  eq(#MOCK.bought, 0, "bought twice")
end)

step("merchant: not enough money buys nothing; the setting hides the bar; closing hides it", function()
  local M = ns.merchant
  M.pending, M.boughtAt = {}, nil
  MOCK.money = 1
  local list, total = M.current()
  check(#list > 0, "nothing to buy")
  MOCK.bought = {}
  local calls, why = M.buy(list, total)
  eq(calls, nil, "bought without the money")
  check(why:find("money", 1, true), "why: " .. tostring(why))
  eq(#MOCK.bought, 0, "a purchase was made")
  MOCK.money = 1000000
  -- an old 8 s timer never cancels a newer confirm: arm, cancel, arm again, then the first timer runs
  local bar = EverlookCraftMerchantBar
  M.refresh()
  MOCK.timers = {}
  bar.button:GetScript("OnClick")(bar.button)
  local first = MOCK.timers[#MOCK.timers]
  bar.cancel:GetScript("OnClick")(bar.cancel)
  bar.button:GetScript("OnClick")(bar.button)
  first()
  check(bar.button:GetText():find("Buy for", 1, true), "the old timer disarmed the new confirm")
  MOCK.timers = {}
  bar.cancel:GetScript("OnClick")(bar.cancel)
  EverlookCraftDB.settings.merchantButton = false
  M.refresh()
  check(not EverlookCraftMerchantBar:IsShown(), "bar shown while turned off")
  EverlookCraftDB.settings.merchantButton = true
  M.refresh()
  check(EverlookCraftMerchantBar:IsShown(), "bar not back")
  MOCK.Fire("MERCHANT_CLOSED")
  check(not EverlookCraftMerchantBar:IsShown(), "bar after closing")
  eq(M.buy(list, total), nil, "bought with the merchant closed")
end)

step("merchant: one item for another window (buyItem), never more than asked, nothing at a closed merchant", function()
  local M = ns.merchant
  M.pending = {}
  merchant({ { id = THREAD, price = 10, qty = 1, stack = 20 }, { id = 2604, price = 50, qty = 5 } })
  MOCK.Fire("MERCHANT_SHOW")
  drain()
  check(M.sells(THREAD), "thread not found")
  eq(M.sells(12345), nil, "an item it doesn't sell")
  MOCK.bought = {}
  check(M.buyItem(THREAD, 25), "not bought")
  local got = 0
  for _, b in ipairs(MOCK.bought) do got = got + b[2] end
  eq(got, 25, "thread bought")
  MOCK.bought = {}
  M.buyItem(2604, 6)
  eq(#MOCK.bought, 2, "6 dyes in packs of 5: two packs")
  MOCK.Fire("MERCHANT_CLOSED")
  eq(M.buyItem(THREAD, 1), nil, "bought at a closed merchant")
end)

step("tooltip, material on the Crafting list: how many more the list needs (when the list is there)", function()
  local L = ns.craftList
  if not (L and L.add) then print("         (no Crafting list in this build: skipped)") return end
  L.add(2963, 10)
  local lines = tip(LINEN, false)
  local l = has(lines, "^Crafting list")
  check(l and l:find("more", 1, true), "list line: " .. table.concat(lines, " / "))
  L.clear()
  MOCK.time = MOCK.time + 2
  check(not has(tip(LINEN, false), "^Crafting list"), "list line with an empty list")
end)

step("settings pages build: Tooltips, Guild, Trainers and merchants", function()
  for _, id in ipairs({ "tooltips", "guild", "vendors" }) do
    ns.app:Open(id)
    check(ns.app:IsShown(), "window for " .. id)
  end
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
