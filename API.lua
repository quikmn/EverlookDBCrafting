-- EverlookDB Crafting: a small read-only API for other addons (EverlookDB Auctions, CraftColors).
--
--   local api = EverlookCraftAPI
--   if api and api.version >= 1 then
--     local r = api.recipe(spellID)
--   end
--
--   api.version          number: goes up by one whenever something is added; nothing is ever removed
--   api.recipe(spell)    { name, learn, yellow, green, gray, learnKnown, mats = { { item, n } }, creates, yield } or nil:
--                        the recipe's skill colours (learn is an estimate unless learnKnown) and its reagents (the
--                        server's, where a profession window showed others than the client data)
--   api.chance(spell, s) the chance (0-1) that one craft raises skill s, or nil when the recipe is unknown
--   api.stock(item)      { bags, bank, alts }: how many this character has and how many your other characters have
--                        (the totals only; names are not handed out)
--   api.knownBy(spell)   how many of your characters know the recipe (a number; names stay in this addon)
--   api.guildKnows(spell) (v2) { name, ... }: guild members who told this session (guild sharing) that they know the
--                        recipe, sorted; empty when sharing is off. In memory only: never saved anywhere
--   api.professionColors() (v3) true when this addon colours the profession window's recipe names (the module that
--                        was CraftColors): CraftColors v0.6.0+ then stands down, so only one draws
--   api.favorBest(n)     (v4) the n (default 3) best Waylaid Crates for Merchant's Favor, as the Merchant's Favor
--                        window ranks them with its saved filters: { { id, name, favor, total, perFavor,
--                        perFavorText ("~1s 20c per Favor"), fill ("fill: 20 Peacebloom, auction house") } }; only
--                        ranked crates (ones with a price and a known Favor)
--   api.openFavor()      (v4) opens the Merchant's Favor window
--   api.embedFavor(parent) (v5) shows the whole Merchant's Favor list (filters, crates, "Send missing to Auctions")
--                        inside parent: EverlookDB Auctions' main window has it as its Merchant's Favor page
--
-- Every call reads what is already saved: nothing is sent anywhere, and the tables returned are copies.
local _, ns = ...

local api = { version = 5 }

function api.recipe(spell)
  local r = type(spell) == "number" and ns.recipeBySpell(spell)
  if not r then return nil end
  local mats = {}
  for _, m in ipairs((ns.matsOf(r))) do mats[#mats + 1] = { m[1], m[2] } end
  return { name = r.name, learn = r.learn, yellow = r.yellow, green = r.green, gray = r.gray, learnKnown = r.learnKnown,
    mats = mats, creates = r.creates, yield = r.yield }
end

function api.chance(spell, s)
  local r = type(spell) == "number" and ns.recipeBySpell(spell)
  if not r or type(s) ~= "number" then return nil end
  return ns.planner.chance(r, s)
end

function api.stock(item)
  if type(item) ~= "number" or not EverlookCraftDB then return nil end
  local h = ns.stock.have(item)
  return { bags = h.bags, bank = h.bank, alts = h.alts }
end

function api.knownBy(spell)
  if type(spell) ~= "number" or not EverlookCraftDB then return 0 end
  return #ns.scan.knownBy(spell)
end

function api.guildKnows(spell)
  if type(spell) ~= "number" or not ns.guild then return {} end
  local out = {}
  for i, n in ipairs(ns.guild.knows(spell)) do out[i] = n end
  return out
end

function api.professionColors()
  return ns.profColors ~= nil and ns.profColors.active() and true or false
end

function api.favorBest(n)
  local F = ns.favor
  if not F then return {} end
  n = type(n) == "number" and n or 3
  local out = {}
  for _, res in ipairs(F.current()) do
    if #out >= n then break end
    if res.perFavor and res.best then
      out[#out + 1] = { id = res.c.id, name = (ns.itemInfo(res.c.id)), favor = res.c.favor, total = res.total,
        perFavor = res.perFavor, perFavorText = F.perFavorText(res),
        fill = "fill: " .. F.optionName(res.best) .. ", " .. F.howText(res.best) }
    end
  end
  return out
end

-- The top window under the mouse (the one whose button was just clicked), or nil.
local function opener()
  local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
  local w = focus
  while w and w.GetParent and w:GetParent() and w:GetParent() ~= UIParent do w = w:GetParent() end
  if w and w ~= UIParent and w.IsShown and w:IsShown() and w.GetLeft and w:GetLeft() then return w end
end

-- Puts win next to from: right of it if it fits on screen, else left; with no room for either, against the screen
-- edge on the roomier side, so it covers as little as it can. Always on top.
local function besides(win, from)
  local ws, fs = win:GetEffectiveScale(), from:GetEffectiveScale()
  local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale()
  local fl, fr, ft = from:GetLeft() * fs, from:GetRight() * fs, from:GetTop() * fs
  local w = win:GetWidth() * ws
  local x
  if fr + 8 + w <= sw then x = fr + 8
  elseif fl - 8 - w >= 0 then x = fl - 8 - w
  elseif sw - fr >= fl then x = math.max(0, sw - w)
  else x = 0 end
  win:ClearAllPoints()
  win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / ws, ft / ws)
  if win.Raise then win:Raise() end
end

function api.embedFavor(parent)
  if ns.favorWindow and parent then return ns.favorWindow.embed(parent) ~= nil end
end

-- Opened from another window (EverlookDB Auctions' main window): next to it, not under it.
function api.openFavor()
  if not ns.favorWindow then return end
  local from = opener()
  ns.favorWindow.open()
  local win = rawget(_G, "EverlookCraftFavor")
  if from and win and from ~= win then pcall(besides, win, from) end
end

-- Read-only: writes to the table are refused, so one addon can't break it for another.
EverlookCraftAPI = setmetatable({}, {
  __index = api,
  __newindex = function() error("EverlookCraftAPI is read-only", 2) end,
  __metatable = false,
})
