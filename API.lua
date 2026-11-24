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
--   api.characters()     (v6) your characters who can trade with this one (this realm or a connected one, the same
--                        faction) and know recipes: { { key (the character's GUID, as this addon keys them), name,
--                        class (file name, "MAGE"), level, me (true for the one you're on), profs = { { skill (skill
--                        line), name ("Tailoring"), rank, max, known (recipes known) } } } }, you first, then by name
--   api.recipesOf(key)   (v6) the recipes a character from api.characters() knows that make an item: { { spell, name,
--                        skill (skill line), learn, creates, yield, mats = { { item, n } } } } (the server's reagents
--                        where a profession window showed others); nil for a character it doesn't list
--   api.bagsOf(key)      (v6) what that character had in its bags when last seen: { [item] = n }; nil as above
--   api.allRecipes()     (v7) every recipe in the data that makes an item and can be learned on your side: { { spell,
--                        name, skill (skill line), prof ("Tailoring"), learn, learnKnown, creates, yield, mats = { { item,
--                        n } }, item (the recipe item, or nil), fee (the trainer's fee in copper, or nil), price (what a
--                        vendor asks for the recipe item, copper, or nil), tier (0 trainer, 1 teacher or unlimited
--                        vendor, 2 limited vendor, 3 hard, 9 none), why ("drop", "quest", "rep", ... or ""), trained
--                        (a trainer teaches it), auto (taught with the rank) } }, by skill line then learn skill
--
-- Every call reads what is already saved: nothing is sent anywhere, and the tables returned are copies.
local _, ns = ...

local api = { version = 7 }

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
  return { bags = h.bags, bank = h.bank, mail = h.mail, alts = h.alts }
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

-- The saved record of a character api.characters() lists (this realm or a connected one, the same faction), or nil.
local function listed(key)
  local db = EverlookCraftDB
  local c = type(key) == "string" and db and type(db.chars) == "table" and db.chars[key]
  if type(c) ~= "table" or type(c.profs) ~= "table" then return nil end
  if key ~= ns.guid() and not ns.canMail(c) then return nil end
  return c
end

local function knownCount(p)
  local n = 0
  for _ in pairs(type(p) == "table" and type(p.known) == "table" and p.known or {}) do n = n + 1 end
  return n
end

function api.characters()
  local out = {}
  local db = EverlookCraftDB
  if not db or type(db.chars) ~= "table" then return out end
  if ns.me then pcall(ns.me) end   -- this character's name and class, before it is listed
  local mine = ns.guid()
  for key in pairs(db.chars) do
    local c = listed(key)
    if c then
      local profs = {}
      for skill, p in pairs(c.profs) do
        local n = knownCount(p)
        if n > 0 then
          profs[#profs + 1] = { skill = skill, name = ns.profName(skill) or tostring(skill), rank = tonumber(p.rank),
            max = tonumber(p.max), known = n }
        end
      end
      if #profs > 0 then
        table.sort(profs, function(a, b)
          if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
          return a.name < b.name
        end)
        out[#out + 1] = { key = key, name = c.name or "?", class = c.class, level = c.level, me = key == mine, profs = profs }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.me ~= b.me then return a.me end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

function api.recipesOf(key)
  local c = listed(key)
  if not c then return nil end
  local out = {}
  for skill, p in pairs(c.profs) do
    local rs = ns.recipes(skill)
    for spell in pairs(type(p) == "table" and type(p.known) == "table" and p.known or {}) do
      local r = rs and rs.bySpell[spell]
      if r and r.creates then
        local mats = {}
        for _, m in ipairs((ns.matsOf(r))) do mats[#mats + 1] = { m[1], m[2] } end
        out[#out + 1] = { spell = r.spell, name = r.name, skill = skill, learn = r.learn, creates = r.creates,
          yield = r.yield, mats = mats }
      end
    end
  end
  table.sort(out, function(a, b) return a.spell < b.spell end)
  return out
end

function api.bagsOf(key)
  local c = listed(key)
  if not c then return nil end
  return ns.stock.bagsOf(c)
end

function api.allRecipes()
  local out = {}
  local D = ns.DATA
  if not D then return out end
  local side = ns.side()
  for skill in pairs(D.profs) do
    local rs = ns.recipes(skill)
    for _, r in ipairs(rs or {}) do
      local skip = r.skip
      local why = r.why and r.why[side] or ""
      if r.creates and r.creates ~= 0 and why ~= "otherSide" and skip ~= "unavailable" and skip ~= "deprecated"
        and skip ~= "missing" and skip ~= "noMats" then
        local mats = {}
        for _, m in ipairs((ns.matsOf(r))) do mats[#mats + 1] = { m[1], m[2] } end
        local item = r.item and r.item ~= 0 and r.item or nil
        out[#out + 1] = { spell = r.spell, name = r.name, skill = skill, prof = ns.profName(skill), learn = r.learn,
          learnKnown = r.learnKnown, creates = r.creates, yield = r.yield, mats = mats, item = item,
          fee = (tonumber(r.fee) or 0) > 0 and r.fee or nil, price = item and ns.prices and ns.prices.pattern(r) or nil,
          tier = r.tier and r.tier[side] or 9, why = why or "", trained = r.trained, auto = r.auto }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.skill ~= b.skill then return a.skill < b.skill end
    if (a.learn or 0) ~= (b.learn or 0) then return (a.learn or 0) < (b.learn or 0) end
    return a.spell < b.spell
  end)
  return out
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
