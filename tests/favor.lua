-- Offline tests for Merchant's Favor (Favor.lua, FavorWindow.lua) against wowmock.lua and the real Data.lua: the
-- crates in the data (fill ONE bundle), the cost of a crate as the cheapest single bundle (never the sum), crafting
-- a bundle when one of your characters knows a cheaper recipe, "count my bags as free", crates that can't be ranked
-- (no Favor known, no price) sorting last with a reason, the filters, what goes to the shopping list and the Crafting
-- list, the tooltip line on a crate, /ecraft favor and the window.
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
GetRealmName = function() return "Mock Realm" end
IsShiftKeyDown = IsShiftKeyDown or function() return false end

local PRICES = {}
local sent
EverlookDBAuctionsAPI = {
  version = 2,
  price = function(id) local p = PRICES[id]; if p then return p, 600, 20, 3 end end,
  addShoppingList = function(name, items) sent = { name = name, items = items }; return true, true end,
}

local function loadToc()
  local env = setmetatable({}, { __index = _G, __newindex = function(_, k, v) _G[k] = v end })
  local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
      local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
      if not chunk then error("syntax: " .. err) end
      setfenv(chunk, env)
      chunk(ADDON, ns)
    end
  end
end

local F
local HERBS, FABRICS, ART_ORE, EXP_ORE = 248682, 248702, 248697, 248692
local PEACE, SILVER, EARTH, MAGE, BRIAR = 2447, 765, 2449, 785, 2450
local LINEN, BOLT, HIDE, BOLT_SPELL = 2589, 2996, 4231, 2963

local function find(rows, id) for i, r in ipairs(rows) do if r.c.id == id then return r, i end end end

step("loads in TOC order; 30 crates, each with its bundles", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  F = ns.favor
  check(F and ns.favorWindow, "modules missing")
  local cs = F.crates()
  eq(#cs, 30, "crates")
  local h = F.crate(HERBS)
  eq(#h.bundles, 5, "Apprentice Herbs bundles")
  eq(h.bundles[1].id, PEACE, "first bundle"); eq(h.bundles[1].n, 20, "20 Peacebloom")
  eq(h.favor, 5, "Favor"); eq(h.money, 250, "money"); eq(h.rep, 0, "no reputation"); eq(h.level, 10, "level")
  eq(F.crate(ART_ORE).favor, nil, "Artisan Favor unknown")
  eq(ns.DATA.trade.npc.a, 256390, "Marcy Baker")
end)

step("setup: you know Bolt of Linen Cloth; nothing in your bags", function()
  local me = ns.me()
  me.profs[197] = { rank = 60, max = 75, known = { [BOLT_SPELL] = true } }
  me.bags, me.bank = {}, {}
  EverlookCraftDB.settings.favorBagsFree = false
end)

step("a crate costs its cheapest ONE bundle plus the crate, never the sum", function()
  PRICES = { [PEACE] = 10, [SILVER] = 5, [EARTH] = 30, [MAGE] = 40, [BRIAR] = 50, [HERBS] = 50 }
  local res = F.evaluate(F.crate(HERBS))
  eq(res.best.id, SILVER, "cheapest bundle")
  eq(res.best.cost, 100, "20 Silverleaf at 5c")
  eq(res.crate.cost, 50, "crate on the AH")
  eq(res.total, 150, "total = crate + one bundle")
  eq(res.perFavor, 30, "per Favor")
  eq(#res.options, 5, "the other bundles stay as alternatives")
  eq(res.options[2].id, PEACE, "next cheapest second")
  check(res.why == nil, "ranked")
end)

step("a bundle you can craft cheaper is crafted (a known recipe); an unpriced bundle sorts after the priced", function()
  PRICES[LINEN] = 22
  PRICES[BOLT] = 120
  PRICES[FABRICS] = 100
  local res = F.evaluate(F.crate(FABRICS))
  eq(res.best.id, BOLT, "bolts")
  eq(res.best.how, "craft", "crafted, linen is cheaper")
  eq(res.best.unit, 44, "2 linen per bolt")
  eq(res.best.cost, 880, "20 bolts")
  eq(res.options[2].id, HIDE, "hide second"); check(res.options[2].cost == nil, "hide has no price")
  eq(F.howText(res.best), "craft: Bolt of Linen Cloth", "how")
  local r, n = F.craftNeed(res)
  eq(r.spell, BOLT_SPELL, "recipe"); eq(n, 20, "crafts")
  local items = F.shoppingItems(res)
  eq(#items, 2, "crate + linen"); eq(items[1][1], FABRICS, "the crate"); eq(items[2][1], LINEN, "linen"); eq(items[2][2], 40, "40 linen")
end)

step("count my bags as free: what you have costs nothing (off: at value)", function()
  local me = ns.me()
  me.bags = { [SILVER] = 15, [HERBS] = 1 }
  local res = F.evaluate(F.crate(HERBS))
  eq(res.total, 150, "off: owned counts at value")
  EverlookCraftDB.settings.favorBagsFree = true
  res = F.evaluate(F.crate(HERBS), { bagsFree = true })
  eq(res.best.id, SILVER, "silverleaf"); eq(res.best.buy, 5, "5 to buy"); eq(res.best.cost, 25, "5 x 5c")
  eq(res.crate.how, "owned", "the crate is yours"); eq(res.total, 25, "total")
  eq(#F.shoppingItems(res), 1, "only silverleaf to buy"); eq(F.shoppingItems(res)[1][2], 5, "5 silverleaf")
  EverlookCraftDB.settings.favorBagsFree = false
  me.bags = {}
end)

step("a crate not on the auction house, or with unknown Favor, sorts last and says why", function()
  PRICES[ART_ORE] = nil
  local rows = F.rank({})
  local herbs, hi = find(rows, HERBS)
  local art, ai = find(rows, ART_ORE)
  check(herbs.perFavor and not art.perFavor, "ranked / not ranked")
  check(ai > hi, "unranked after ranked")
  check(art.why:find("Favor isn't known", 1, true), "why: " .. tostring(art.why))
  local exp = find(rows, EXP_ORE)
  check(exp.why and exp.why:find("no price for any bundle", 1, true), "no bundle price: " .. tostring(exp.why))
  PRICES[2775] = 100; PRICES[3858] = 200 -- Gold Ore, Mithril Ore
  exp = find(F.rank({}), EXP_ORE)
  check(exp.why and exp.why:find("isn't on the auction house", 1, true), "crate price: " .. tostring(exp.why))
  for i = 2, #rows do
    if rows[i].perFavor and rows[i - 1].perFavor then check(rows[i].perFavor >= rows[i - 1].perFavor, "sorted by gold per Favor") end
  end
  -- sorted by the cheapest total (crate + fill) instead
  local byTotal = F.rank({ sort = "total" })
  local ranked = 0
  for i = 1, #byTotal do
    if byTotal[i].perFavor then
      ranked = ranked + 1
      eq(byTotal[i].total, byTotal[i].best.cost + byTotal[i].crate.cost, "total = crate + fill")
      if i > 1 and byTotal[i - 1].perFavor then check(byTotal[i].total >= byTotal[i - 1].total, "sorted by total") end
    end
  end
  check(ranked > 1, "ranked rows to sort by total")
end)

step("filters: your level, a tier", function()
  local rows = F.rank({ level = 15 })
  for _, r in ipairs(rows) do check(r.c.level <= 15, "level filter") end
  eq(#rows, 14, "Apprentice and Journeyman crates (all level 10)")
  rows = F.rank({ tier = 3 })
  for _, r in ipairs(rows) do eq(r.c.tier, 3, "tier filter") end
end)

step("Add to crafting list puts the bolt recipe on it", function()
  ns.craftList.clear()
  local ok = F.addToList(F.evaluate(F.crate(FABRICS)))
  check(ok, "added")
  eq(ns.craftList.find(BOLT_SPELL).n, 20, "20 bolts")
  local ok2, why = F.addToList(F.evaluate(F.crate(HERBS)))
  check(not ok2 and why:find("bought", 1, true), "a bought bundle has nothing to craft")
  ns.craftList.clear()
end)

step("the tooltip line on a crate", function()
  local lines = {}
  local t = { Line = function(_, a, b, o) lines[#lines + 1] = { a, b, o } end, Detail = function(_, a, b) lines[#lines + 1] = { a, b } end }
  ns.tooltips.lines(t, HERBS)
  eq(lines[1][1], "Merchant's Favor", "label")
  check(lines[1][2]:find("^5, ~"), "value: " .. lines[1][2])
  check(lines[1][2]:find("per Favor", 1, true), "per Favor")
  check(lines[2][1] == "Cheapest fill" and lines[2][2]:find("20 Silverleaf", 1, true), "cheapest fill line")
  lines = {}
  ns.tooltips.lines(t, ART_ORE)
  check(lines[1][2]:find("unknown", 1, true), "unknown Favor said plainly")
end)

step("/ecraft favor opens the window; the primary sends the picked crate's shopping list", function()
  SlashCmdList.EVERLOOKCRAFT("favor")
  check(EverlookCraftFavor and EverlookCraftFavor:IsShown(), "window not shown")
  local top = ns.favorWindow.rows[1]
  check(top and top.perFavor, "a ranked crate first")
  sent = nil
  ns.favorWindow.primary()
  check(sent and sent.name == "Merchant's Favor", "list sent")
  check(#sent.items >= 1, "items")
  ns.favorWindow.selected = FABRICS
  ns.favorWindow.render()
  ns.favorWindow.primary()
  eq(sent.items[1][1], FABRICS, "the picked crate")
  EverlookCraftDB.settings.favorTier = 1
  ns.favorWindow.render()
  for _, r in ipairs(ns.favorWindow.rows) do eq(r.c.tier, 1, "tier chip") end
  EverlookCraftDB.settings.favorTier = 0
  SlashCmdList.EVERLOOKCRAFT("favor")
  check(not EverlookCraftFavor:IsShown(), "favor toggles")
  ns.app:Open("favor")
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
