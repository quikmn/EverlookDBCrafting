-- Offline tests for EverlookDB Crafting against wowmock.lua: the planner (chance formula, a fixed route, rank
-- trainings, the 90% buffer, learn-tier filtering, one-time costs, owned materials), the kept route, the profession
-- scanner (a linked profession is refused, reagent fixes), stock across characters, the API, the slash command and
-- the window, and route parity with everlookdb.com's own route code (PARITY, from tests/parity.mjs).
local ROOT, PARITY = ...
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

-- the skill list (Classic style)
MOCK.skills = { { "Professions", true }, { "Tailoring", false, 112, 150 } }
GetNumSkillLines = function() return #MOCK.skills end
GetSkillLineInfo = function(i) local s = MOCK.skills[i]; if s then return s[1], s[2], nil, s[3], nil, nil, s[4] end end

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

step("loads in TOC order and sets up its saved variables", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  check(EverlookCraftDB and EverlookCraftDB.settings.vendorPatterns == true, "defaults")
  check(EverlookCraftChar and EverlookCraftChar.routes, "per character")
  check(SlashCmdList.EVERLOOKCRAFT, "no slash command")
  check(ns.DATA and ns.DATA.profs[197], "no data")
  for k in pairs(globalWrites) do
    check(k == "EverlookCraftDB" or k == "EverlookCraftChar" or k == "EverlookCraftAPI" or k:match("^SLASH_EVERLOOKCRAFT") or k == "EverlookCraftGuide",
      "unexpected global " .. k)
  end
end)

step("skill levels come from the skill list at login", function()
  local p = ns.scan.mine(197)
  check(p and p.rank == 112 and p.max == 150, "Tailoring 112/150 not read")
end)

local P
step("the classic skill-up chance: orange, yellow, green, gray and the edges", function()
  P = ns.planner
  local r = { learn = 10, yellow = 50, green = 60, gray = 70 }
  eq(P.chance(r, 9), 0, "below learn")
  eq(P.chance(r, 10), 1, "orange at learn")
  eq(P.chance(r, 49), 1, "orange")
  eq(P.chance(r, 50), 1, "yellow start: (70-50)/(70-50)")
  eq(P.chance(r, 60), 0.5, "green halfway")
  check(math.abs(P.chance(r, 69) - 0.05) < 1e-9, "one below gray")
  eq(P.chance(r, 70), 0, "gray")
end)

-- a small made-up profession: two trainer recipes, a vendor pattern, a dungeon recipe that would be cheapest,
-- an intermediate (a bolt) and a recipe needing a cooldown craft
local function R(o)
  o.tier = o.tier or { a = 0, h = 0 }
  o.why = o.why or { a = "", h = "" }
  o.yield = o.yield or 1
  o.item = o.item or 0
  o.skip = o.skip or ""
  o.trained = o.trained ~= false
  return o
end
local fixture = {
  R({ spell = 1, name = "Bolt", creates = 100, learn = 1, yellow = 25, green = 37, gray = 50, mats = { { 10, 2 } } }),
  R({ spell = 2, name = "Shirt", creates = 101, learn = 1, yellow = 35, green = 47, gray = 60, mats = { { 100, 1 }, { 11, 1 } } }),
  R({ spell = 3, name = "Cloak", creates = 102, learn = 40, yellow = 70, green = 85, gray = 100, mats = { { 100, 3 }, { 11, 2 } } }),
  R({ spell = 4, name = "Dungeon Hat", creates = 103, learn = 40, yellow = 70, green = 85, gray = 100, mats = { { 10, 1 } }, item = 901,
    tier = { a = 3, h = 3 }, why = { a = "dungeon", h = "dungeon" }, trained = false }),
  R({ spell = 5, name = "Vendor Gloves", creates = 104, learn = 60, yellow = 90, green = 105, gray = 120, mats = { { 100, 2 } },
    item = 900, tier = { a = 1, h = 9 }, why = { a = "", h = "otherSide" }, trained = false }),
  R({ spell = 6, name = "Moon Robe", creates = 105, learn = 60, yellow = 90, green = 105, gray = 120, mats = { { 10, 1 } }, needsCd = true }),
}
local prices = { [10] = 100, [11] = 10, [100] = 300 }
local function fixPlan(o)
  local base = { from = 1, to = 120, side = "a", known = {}, price = function(id) return prices[id] end,
    patternPrice = function() return 5000 end }
  for k, v in pairs(o or {}) do base[k] = v end
  return P.plan(fixture, base)
end

step("a fixed route: the cheapest reliable recipe per point, never the dungeon or cooldown one", function()
  local res = fixPlan({ oneTime = false })
  local names = {}
  for _, st in ipairs(res.steps) do names[#names + 1] = st.r.name .. " " .. st.from .. "-" .. st.to end
  local route = table.concat(names, ", ")
  eq(res.steps[1].r.name, "Bolt", "first step: " .. route)
  for _, st in ipairs(res.steps) do
    check(st.r.name ~= "Dungeon Hat", "dungeon recipe routed: " .. route)
    check(st.r.name ~= "Moon Robe", "cooldown recipe routed: " .. route)
  end
  check(res.stall == nil, "route stalls at " .. tostring(res.stall) .. ": " .. route)
  eq(res.steps[#res.steps].r.name, "Vendor Gloves", "last step: " .. route)
  -- the bolt is made, not bought: 2 cloth (200c) beat a 300c bolt
  local made = {}
  for _, c in ipairs(res.shop.crafted) do made[c.id] = c end
  check(made[100], "bolts not on the make-first list")
end)

step("Horde: the Alliance-only vendor pattern is never used", function()
  local res = fixPlan({ side = "h", oneTime = false })
  for _, st in ipairs(res.steps) do check(st.r.name ~= "Vendor Gloves", "other side's pattern routed") end
  check(res.stall ~= nil, "Horde should stall without the gloves")
end)

step("learn tiers: a drop pattern only with 'from the auction house' on and a price", function()
  local res = fixPlan({ oneTime = false, ahPatterns = true, ahPatternPrice = function(r) return r.spell == 4 and 100 or nil end })
  local used = false
  for _, st in ipairs(res.steps) do if st.r.name == "Dungeon Hat" then used = true end end
  check(used, "an auction-house pattern that is cheap should be used with the switch on")
  local off = fixPlan({ oneTime = false, ahPatterns = false, ahPatternPrice = function() return 100 end })
  for _, st in ipairs(off.steps) do check(st.r.name ~= "Dungeon Hat", "routed with the switch off") end
end)

step("known recipes are always usable, and cost nothing to learn", function()
  local res = fixPlan({ known = { [4] = true } })
  local used = false
  for _, st in ipairs(res.steps) do if st.r.name == "Dungeon Hat" then used = true end end
  check(used, "a dungeon recipe you know is fine")
  eq(res.totals.patterns, 5000, "only the gloves pattern is bought")
end)

step("one-time costs: an expensive pattern is dropped when the route can do without it", function()
  local cheap = fixPlan({ to = 100 })
  local dear = fixPlan({ to = 100, patternPrice = function() return 10000000 end })
  local function uses(res, name) for _, st in ipairs(res.steps) do if st.r.name == name then return true end end end
  check(uses(cheap, "Vendor Gloves"), "a 50s pattern for the last 20 points is worth it")
  check(not uses(dear, "Vendor Gloves"), "a 1000g pattern for a few points is not worth it")
  check(dear.stall == nil, "the route must still reach 100")
end)

step("the 90% buffer: mean plus 1.28 standard deviations of the geometric draws", function()
  local r = { learn = 1, yellow = 1, green = 1, gray = 3 } -- chance 1 at 1, 0.5 at 2
  local n, n90 = P.craftsBetween(r, 2, 3)
  eq(n, 2, "expected crafts at 50%")
  -- mean 2, variance (1-0.5)/0.25 = 2: 2 + 1.2816 * 1.414 = 3.81 -> 4
  eq(n90, 4, "90% crafts")
  local res = fixPlan({ oneTime = false })
  for _, st in ipairs(res.steps) do check(st.n90 >= st.n, "n90 below n") end
end)

step("the route's 90% buffer is shared out by variance: orange steps get none, the whole route ~90%", function()
  local res = fixPlan({ oneTime = false, buffer = true })
  local total, extra, own = 0, 0, 0
  for _, st in ipairs(res.steps) do
    total = total + st.var
    extra = extra + (st.n90 - st.crafts)
    if st.var == 0 then eq(st.n90, st.n, "an orange step got a buffer") end
    check(st.n90 >= st.n, "n90 below n")
    -- each step at its own 90% would need this much more
    own = own + (math.ceil(st.crafts + P.Z90 * math.sqrt(st.var) - 1e-6) - st.crafts)
  end
  local want = P.Z90 * math.sqrt(total)
  check(extra >= want - 1e-6, ("route buffer %.2f below the 90%% point %.2f"):format(extra, want))
  check(extra <= want + #res.steps, "more than rounding over the 90% point")
  check(extra < own, ("the shared buffer (%.1f) should be smaller than every step's own (%.1f)"):format(extra, own))
end)

step("buy or craft: your pick for an intermediate wins over the cheaper way", function()
  local made = function(res) for _, c in ipairs(res.shop.crafted) do if c.id == 100 then return true end end return false end
  check(made(fixPlan({ oneTime = false })), "bolts are made (cheaper)")
  local buy = fixPlan({ oneTime = false, choice = function(id) return id == 100 and "buy" or nil end })
  check(not made(buy), "bolts still made with 'buy' picked")
  local bought = false
  for _, x in ipairs(buy.shop.raw) do if x.id == 100 then bought = x.n > 0 end end
  check(bought, "bolts not on the shopping list")
  -- 'craft' makes them even when buying is cheaper
  prices[100] = 50
  check(not made(fixPlan({ oneTime = false })), "cheap bolts should be bought")
  check(made(fixPlan({ oneTime = false, choice = function(id) return id == 100 and "craft" or nil end })), "'craft' picked but bought")
  prices[100] = 300
end)

step("reputation: a vendor pattern behind a standing only once you have it", function()
  local fx = {
    R({ spell = 31, name = "Plain", creates = 130, learn = 1, yellow = 30, green = 40, gray = 50, mats = { { 10, 3 } } }),
    R({ spell = 32, name = "Rep Robe", creates = 131, learn = 1, yellow = 60, green = 70, gray = 80, mats = { { 10, 1 } }, item = 950,
      tier = { a = 3, h = 3 }, why = { a = "rep", h = "rep" }, trained = false }),
  }
  local function uses(res) for _, st in ipairs(res.steps) do if st.r.spell == 32 then return st end end end
  local base = { from = 1, to = 60, side = "a", known = {}, price = function() return 100 end, patternPrice = function() return 500 end }
  check(not uses(P.plan(fx, base)), "a reputation pattern without the standing")
  base.repOk = function(r) return r.spell == 32 end
  local res = P.plan(fx, base)
  local st = uses(res)
  check(st and st.rep, "a reputation pattern you can buy is not used")
  eq(res.totals.patterns, 500, "its price counts")
  -- the game's standing: Friendly (5) meets "friendly" (4 in the data, 0 Hated .. 7 Exalted), Neutral doesn't
  local r = ns.recipes(197)[1]
  local item
  for id, ri in pairs(ns.DATA.recipeItems) do if ri.rep then item = id; break end end
  check(item, "no reputation pattern in the data")
  local need = ns.DATA.recipeItems[item].rep
  local fake = { item = item }
  C_Reputation = { GetNumFactions = function() return 1 end,
    GetFactionDataByIndex = function() return { name = need[1], reaction = need[2] + 1 } end }
  check(ns.repOk(fake), "standing met")
  C_Reputation.GetFactionDataByIndex = function() return { name = need[1], reaction = need[2] } end
  check(not ns.repOk(fake), "one standing short")
  C_Reputation = nil
  check(not ns.repOk(fake), "an unknown standing counted as met")
  check(r, "recipes")
end)

step("prices: the cheaper of vendor and auction house, a tie to the vendor", function()
  local THREAD = 2320
  local v = ns.prices.vendor(THREAD)
  check(v, "thread has a vendor price")
  local ah
  EverlookDBAuctionsAPI = { version = 6, price = function(id) if id == THREAD then return ah, 600 end end }
  ah = v * 2
  local p, how = ns.prices.unit(THREAD)
  eq(how, "vendor", "dearer auction")
  ah = v
  p, how = ns.prices.unit(THREAD)
  eq(how, "vendor", "a tie")
  ah = math.max(1, v - 1)
  if ah < v then
    p, how = ns.prices.unit(THREAD)
    eq(how, "ah", "cheaper auction"); eq(p, ah, "its price")
    eq(ns.prices.where(THREAD), "ah", "where")
  end
  local newest, oldest, src = ns.prices.ages({ THREAD, 2589 })
  eq(newest, 600, "age"); eq(src, "EverlookDB Auctions", "source")
  eq(ns.prices.ageText(600), "10 min", "age text")
  EverlookDBAuctionsAPI = nil
end)

step("rank trainings at the caps you still have to raise", function()
  local ranks = { { 75, 1, 5, 10 }, { 150, 50, 10, 450 }, { 225, 125, 20, 4500 }, { 300, 200, 35, 50000 } }
  local tr = P.trainings(ranks, 1, 300, 75)
  eq(#tr, 3, "three trainings from Apprentice")
  eq(tr[1].step, 2, "Journeyman first")
  eq(tr[1].at, 50, "at 50")
  eq(tr[1].fee, 450, "fee")
  eq(#P.trainings(ranks, 112, 300, 150), 2, "Journeyman already trained")
  eq(#P.trainings(ranks, 112, 150, 150), 0, "target at the cap")
  local res = fixPlan({ to = 120, ranks = ranks, maxSkill = 75, oneTime = false })
  eq(#res.trainings, 1, "1-120 passes 75 only")
  eq(res.totals.fees, 450, "training fee in the totals")
end)

step("owned materials count as free and leave the shopping list", function()
  local res = fixPlan({ oneTime = false, owned = { [10] = 100000, [11] = 100000 } })
  eq(res.totals.mats, 0, "nothing to buy")
  local res2 = fixPlan({ oneTime = false })
  check(res2.totals.mats > 0, "something to buy without stock")
end)

step("unpriced materials: never in totals, counted, and the route says it estimated", function()
  local res = P.plan(fixture, { from = 1, to = 60, side = "a", known = {}, oneTime = false,
    price = function(id) if id == 10 then return nil end return prices[id] end, estimate = function() return 100 end })
  check(res.totals.matsUnpriced >= 1, "unpriced not counted")
  check(res.estimated, "route not marked as estimated")
  for _, x in ipairs(res.shop.raw) do if x.id == 10 then eq(x.price, nil, "a guessed price in the list") end end
end)

step("tools: make or buy the tool before the first step that needs it, unless you have one", function()
  local tools = { [162] = { "Blacksmith Hammer", { 500 } }, [373] = { "Runed Copper Rod", { 501 } } }
  local fx = {
    R({ spell = 21, name = "Hammered Bar", creates = 120, learn = 1, yellow = 40, green = 50, gray = 60, mats = { { 10, 1 } }, tools = { 162 } }),
    R({ spell = 22, name = "Rodded Bar", creates = 121, learn = 30, yellow = 70, green = 85, gray = 100, mats = { { 10, 1 } }, tools = { 373 } }),
    -- the rod: never a cheap skill-up (one point, dear), so the route does not make it on its own
    R({ spell = 23, name = "Runed Copper Rod", creates = 501, learn = 1, yellow = 1, green = 1, gray = 2, mats = { { 12, 1 } } }),
  }
  local pr = { [10] = 100, [12] = 5000, [500] = 1800 }
  local function plan(o)
    local base = { from = 1, to = 90, side = "a", known = {}, oneTime = false, tools = tools, price = function(id) return pr[id] end }
    for k, v in pairs(o or {}) do base[k] = v end
    return P.plan(fx, base)
  end
  local res = plan()
  eq(#res.tools, 2, "two tools")
  eq(res.tools[1].kind, "buy", "the hammer: no recipe makes it")
  eq(res.tools[1].item, 500, "hammer item")
  eq(res.tools[1].at, 1, "before the first step")
  eq(res.tools[2].kind, "make", "the rod: a recipe makes it")
  eq(res.tools[2].r.spell, 23, "the rod's recipe")
  local shop = {}
  for _, x in ipairs(res.shop.raw) do shop[x.id] = x.n end
  eq(shop[500], 1, "the hammer on the shopping list")
  eq(shop[12], 1, "the rod's material on the shopping list")
  check(res.totals.mats >= 1800 + 5000, "tools in the material total")
  local have = plan({ hasItem = function(id) return id == 500 or id == 501 end })
  eq(#have.tools, 0, "you have both")
  local none = P.plan(fx, { from = 1, to = 90, side = "a", known = {}, oneTime = false, price = function(id) return pr[id] end })
  eq(#none.tools, 0, "no tool data, no tool steps")
  eq(#none.steps, #res.steps, "tools never change the route")
end)

-- real data
step("real data: tools, rank fees and learn sources", function()
  local D = ns.DATA
  local hammer = D.tools[162]
  check(hammer and hammer[1] == "Blacksmith Hammer", "the Blacksmith Hammer tool")
  eq(hammer[2][1], 5956, "the plain hammer first")
  check(D.items[5956] and D.items[5956][4], "the hammer has a vendor price")
  check(#D.items[5956][7] > 0, "the hammer has vendors")
  local bs, needing = ns.recipes(164), 0
  for _, r in ipairs(bs) do if r.tools then needing = needing + 1 end end
  check(needing > 100, "Blacksmithing recipes that need the hammer: " .. needing)
  for _, sk in ipairs({ 129, 182, 186, 393 }) do
    check(D.ranks[sk][1][4] and D.ranks[sk][2][4], sk .. ": Apprentice and Journeyman fees")
  end
  -- a Merchant's Favor pattern with its vendor, and a pattern only AllTheThings names a dropper for
  local fav, attDrop = false, false
  for _, ri in pairs(D.recipeItems) do
    local s = ri.sold
    if s then for i = 1, #s, 6 do if D.currencies[s[i + 1]] == "Merchant's Favor" and s[i + 2] > 0 and D.npcs[s[i]] then fav = true end end end
    local d = ri.drop
    if d then for i = 1, #d, 3 do if d[i + 1] == -1 and D.sources[d[i + 2]] == "AllTheThings" then attDrop = true end end end
  end
  check(fav, "no Merchant's Favor pattern with a placed vendor")
  check(attDrop, "no AllTheThings dropper")
  local blacksmith = P.plan(bs, { from = 1, to = 75, side = "a", known = {}, oneTime = false, tools = D.tools,
    price = function(id) local it = D.items[id]; return it and (it[4] or it[5] * 100) or nil end })
  check(blacksmith.tools[1] and blacksmith.tools[1].key == 162, "Blacksmithing 1-75 starts with the hammer")
  eq(blacksmith.tools[1].kind, "buy", "the hammer is bought")
end)

local tailoring
step("Tailoring 1-300 with set prices gives a fixed route through the real data", function()
  tailoring = ns.recipes(197)
  check(#tailoring > 100, "Tailoring recipes")
  local function price(id)
    local it = ns.DATA.items[id]
    return it and (it[4] or it[5] * 100) or nil
  end
  local res = P.plan(tailoring, { from = 1, to = 300, side = "a", known = {}, price = price, oneTime = false,
    patternPrice = ns.prices.pattern })
  check(#res.steps > 5, "too few steps")
  eq(res.steps[1].r.name, "Bolt of Linen Cloth", "first step")
  for _, st in ipairs(res.steps) do
    check((st.r.tier.a or 9) <= 2, st.r.name .. " is not reliably learnable (tier " .. tostring(st.r.tier.a) .. ")")
    check(st.r.why.a ~= "dungeon", st.r.name .. " is a dungeon recipe")
  end
  local again = P.plan(tailoring, { from = 1, to = 300, side = "a", known = {}, price = price, oneTime = false,
    patternPrice = ns.prices.pattern })
  eq(#again.steps, #res.steps, "the same input gives the same route")
  for i, st in ipairs(res.steps) do eq(again.steps[i].r, st.r, "step " .. i) end
end)

step("parity with everlookdb.com's route: the same recipes, step by step (Tailoring, First Aid, Cooking; Alliance)", function()
  check(PARITY, "no parity data (node or the Quarry repo missing)")
  for _, skill in ipairs({ 197, 129, 185 }) do
    local site = PARITY[skill]
    check(site, "no site route for " .. skill)
    local recipes = ns.recipes(skill)
    local res = P.plan(recipes, { from = 1, to = 300, side = "a", known = {}, oneTime = false,
      price = function(id) local it = ns.DATA.items[id]; return it and it[5] or nil end,
      estimate = function() return 3 end })
    local mine = {}
    for _, st in ipairs(res.steps) do mine[#mine + 1] = st.from .. "-" .. st.to .. ":" .. st.r.spell .. "x" .. st.n end
    local theirs = {}
    for _, st in ipairs(site) do theirs[#theirs + 1] = st[1] .. "-" .. st[2] .. ":" .. st[3] .. "x" .. st[4] end
    eq(table.concat(mine, " "), table.concat(theirs, " "), ns.profName(skill) .. " route")
    eq(res.stall, PARITY[skill .. ":stall"], ns.profName(skill) .. " stall")
  end
end)

-- the profession window
local function tradeSkill(o)
  C_TradeSkillUI = {
    GetAllRecipeIDs = function() return o.ids end,
    GetRecipeInfo = function(id) return { name = "r" .. id, learned = true } end,
    GetBaseProfessionInfo = function() return { professionName = o.name, professionID = o.pid, skillLevel = o.rank, maxSkillLevel = o.max } end,
    IsTradeSkillLinked = function() return o.linked end,
    IsTradeSkillGuild = function() return false end,
    IsNPCCrafting = function() return false end,
    GetRecipeSchematic = function(id)
      local m = o.reagents and o.reagents[id]
      if not m then return nil end
      local slots = {}
      for i = 1, #m, 2 do slots[#slots + 1] = { reagents = { { itemID = m[i] } }, quantityRequired = m[i + 1] } end
      return { reagentSlotSchematics = slots, outputItemID = 1 }
    end,
  }
end

step("the scanner refuses a linked profession", function()
  tradeSkill({ ids = { 2963, 2387 }, name = "Tailoring", pid = 197, rank = 120, max = 150, linked = true })
  eq(ns.scan.scan(), false, "a linked window was read")
  local p = ns.scan.mine(197)
  check(not (p.known and p.known[2963]), "linked recipes saved as yours")
end)

step("the scanner refuses a profession the skill list says you don't have", function()
  tradeSkill({ ids = { 2259 }, name = "Alchemy", pid = 171, rank = 50, max = 75 })
  eq(ns.scan.scan(), false, "someone else's Alchemy saved")
end)

step("the scanner saves your recipes and skill, and a reagent the server changed", function()
  -- the server's Linen Cloak takes 2 bolts instead of 1
  tradeSkill({ ids = { 2963, 2387 }, name = "Tailoring", pid = 197, rank = 120, max = 150,
    reagents = { [2963] = { 2589, 2 }, [2387] = { 2996, 2, 2320, 1 } } })
  eq(ns.scan.scan(), true, "not saved")
  local p = ns.scan.mine(197)
  check(p.known[2963] and p.known[2387], "known recipes")
  eq(p.rank, 120, "skill from the window")
  local fix = EverlookCraftDB.fixes[2387]
  check(fix and fix[1] == 2996 and fix[2] == 2, "reagent fix not saved")
  eq(EverlookCraftDB.fixes[2963], nil, "an unchanged recipe got a fix")
  local mats, fixed = ns.matsOf(ns.recipes(197).bySpell[2387])
  check(fixed and mats[1][2] == 2, "the planner doesn't use the fix")
end)

step("stock: bags, bank and other characters; 'don't count my alts' leaves theirs out", function()
  local me = ns.me()
  me.bags = { [2589] = 20 }
  me.bank = { [2589] = 5 }
  EverlookCraftDB.chars["Player-1-Alt"] = { name = "Alt", profs = {}, bags = { [2589] = 7 }, bank = {} }
  local h = ns.stock.have(2589)
  eq(h.bags, 20, "bags"); eq(h.bank, 5, "bank"); eq(h.alts, 7, "alts")
  eq(ns.stock.usable(2589), 32, "all counted")
  EverlookCraftDB.settings.noAlts = true
  eq(ns.stock.usable(2589), 25, "alts left out")
  EverlookCraftDB.settings.noAlts = false
end)

step("stock: characters on another realm don't count (mail can't cross realms); connected realms do", function()
  local me = ns.me()
  me.bags = { [2589] = 20 }
  me.bank = { [2589] = 5 }
  EverlookCraftDB.chars["Player-1-Alt"] = { name = "Alt", realm = "Mock Realm", profs = {}, bags = { [2589] = 7 }, bank = {} }
  EverlookCraftDB.chars["Player-2-Far"] = { name = "Faraway", realm = "Other Realm", profs = {}, bags = { [2589] = 100 },
    bank = { [2589] = 50 } }
  local h = ns.stock.have(2589)
  eq(h.alts, 7, "another realm's character counted")
  eq(#h.byChar, 1, "another realm's character listed")
  eq(ns.stock.usable(2589), 32, "usable")
  eq(ns.stock.owned()[2589], 32, "the planner's stock")
  eq(EverlookCraftAPI.stock(2589).alts, 7, "API stock")
  -- connected realms: the game's GetAutoCompleteRealms names the group ("OtherRealm", no spaces)
  local realName, realAuto = GetRealmName, GetAutoCompleteRealms
  GetRealmName = function() return "Mock Realm Two" end
  GetAutoCompleteRealms = function() return { "MockRealmTwo", "OtherRealm" } end
  me.realm = "Mock Realm Two"
  eq(ns.stock.have(2589).alts, 150, "a connected realm's character left out")
  eq(ns.stock.usable(2589), 175, "connected realm usable")
  -- a game without the function (or one that errors): your own realm only
  GetRealmName = function() return "Third Realm" end
  GetAutoCompleteRealms = function() error("no") end
  me.realm = "Third Realm"
  eq(ns.stock.have(2589).alts, 0, "other realms counted without the connected list")
  GetRealmName, GetAutoCompleteRealms = realName, realAuto
  me.realm = "Mock Realm"
  -- a character saved before realms were (no realm) still counts
  EverlookCraftDB.chars["Player-2-Far"].realm = nil
  eq(ns.stock.have(2589).alts, 157, "a character without a realm")
  EverlookCraftDB.chars["Player-2-Far"] = nil
end)

step("stock: your characters on the other faction don't count (mail can't cross factions)", function()
  local me = ns.me()
  eq(me.side, "a", "your faction saved")
  me.bags, me.bank = { [2589] = 20 }, { [2589] = 5 }
  EverlookCraftDB.chars["Player-1-Alt"] = { name = "Alt", realm = "Mock Realm", side = "a", profs = {},
    bags = { [2589] = 7 }, bank = {} }
  EverlookCraftDB.chars["Player-1-Horde"] = { name = "Hordie", realm = "Mock Realm", side = "h", profs = {},
    bags = { [2589] = 40 }, bank = {} }
  local h = ns.stock.have(2589)
  eq(h.alts, 7, "the other faction's character counted")
  eq(#h.byChar, 1, "the other faction's character listed")
  eq(ns.stock.owned()[2589], 32, "the planner's stock")
  -- a character saved before factions were (no side) still counts
  EverlookCraftDB.chars["Player-1-Horde"].side = nil
  eq(ns.stock.have(2589).alts, 47, "a character without a faction")
  EverlookCraftDB.chars["Player-1-Horde"].side = "h"
  -- the game doesn't know your faction yet (early in loading): nobody is left out, and your saved side isn't guessed
  local real = UnitFactionGroup
  UnitFactionGroup = function() return nil end
  eq(ns.stock.have(2589).alts, 47, "left out while your faction is unknown")
  eq(ns.me().side, "a", "your saved faction overwritten by a guess")
  UnitFactionGroup = real
  EverlookCraftDB.chars["Player-1-Horde"] = nil
end)

step("realm on client build 71037: GetRealmName \"\" and GetRealmID 0, the realm ID from the GUID", function()
  local realName, realID = GetRealmName, GetRealmID
  GetRealmName = function() return "" end
  GetRealmID = function() return 0 end
  local db = EverlookCraftDB
  local savedChars, savedRealms, savedNames = db.chars, db.realms, db.realmNames
  db.chars, db.realms, db.realmNames = {}, {}, {}
  -- nothing saved names realm 1: the ID-only key, and no name is guessed
  local key, name, id = ns.realm()
  eq(key, "realm:1", "ID-only key"); eq(name, nil, "no name"); eq(id, 1, "ID from the GUID")
  local me = ns.me()
  eq(me.realm, nil, "no empty realm saved"); eq(me.realmID, 1, "realm ID saved")
  -- same realm by ID: an alt on realm 1 counts, one on realm 2 doesn't
  me.bags, me.bank = { [2589] = 20 }, {}
  db.chars["Player-1-Alt"] = { name = "Alt", realm = "Mock Realm", realmID = 1, side = "a", profs = {}, bags = { [2589] = 7 }, bank = {} }
  db.chars["Player-2-Far"] = { name = "Far", realmID = 2, side = "a", profs = {}, bags = { [2589] = 100 }, bank = {} }
  eq(ns.stock.have(2589).alts, 7, "other realm ID left out, same ID counted")
  -- the name saved for this ID is used, and a trainer price is saved under it
  db.realmNames[1] = "Mock Realm"
  eq((ns.realm()), "Mock Realm", "saved name for the ID")
  eq(ns.realmName(), "Mock Realm", "realmName")
  GetRealmName, GetRealmID = realName, realID
  db.chars, db.realms, db.realmNames = savedChars, savedRealms, savedNames
end)

step("realm repair: characters and prices saved with realm \"\" get this realm when certain, never another's", function()
  local realName, realID = GetRealmName, GetRealmID
  GetRealmName = function() return "" end
  GetRealmID = function() return 0 end
  local db = EverlookCraftDB
  local savedChars, savedRealms, savedNames = db.chars, db.realms, db.realmNames
  -- the user's own file after build 71037: every character realm "", prices under "" and under the old name
  db.chars = {
    ["Player-1-Tester"] = { name = "Tester", realm = "", side = "a", profs = {}, bags = {}, bank = {} },
    ["Player-1-Miy"] = { name = "Miy", realm = "", side = "a", profs = {}, bags = { [2589] = 4 }, bank = {} },
  }
  db.realms = {
    [""] = { fees = { [2665] = { 100, 40, "a", 200 }, [3319] = { 50, 20, "a", 200 } }, ranks = { [185] = { [3] = { 4500, 125, 20, 200 } } }, prices = { [2678] = { 4, 200 } } },
    ["Mock Realm"] = { fees = { [13485] = { 1500, 130, "a", 100 }, [2665] = { 90, 35, "a", 100 } }, ranks = {}, prices = {} },
  }
  db.realmNames = nil
  ns.repairRealms()
  eq(db.chars["Player-1-Miy"].realmID, 1, "realm ID from the GUID key")
  eq(db.chars["Player-1-Miy"].realm, "Mock Realm", "the one realm this account knows")
  eq(db.realmNames[1], "Mock Realm", "name remembered for the ID")
  check(db.realms[""] == nil, "the nameless prices left behind")
  local r = db.realms["Mock Realm"]
  eq(r.fees[2665][1], 100, "the newer fee kept"); eq(r.fees[13485][1], 1500, "the older realm's own fee kept")
  eq(r.ranks[185][3][1], 4500, "rank fee moved"); eq(r.prices[2678][1], 4, "price moved")
  eq(ns.realmUnfixed, 0, "nothing left unplaced")
  eq((ns.realm()), "Mock Realm", "this realm named again")
  eq(ns.capture.price(2678), 4, "the moved price is used")
  -- two realm IDs on the account: nothing is moved or named, and it is counted for the settings page
  db.chars = {
    ["Player-1-Tester"] = { name = "Tester", realm = "", side = "a", profs = {}, bags = {}, bank = {} },
    ["Player-2-Far"] = { name = "Far", realm = "", side = "a", profs = {}, bags = {}, bank = {} },
  }
  db.realms = { [""] = { fees = { [2665] = { 100, 40, "a", 200 } }, ranks = {}, prices = {} }, ["Mock Realm"] = { fees = {}, ranks = {}, prices = {} } }
  db.realmNames = {}
  ns.repairRealms()
  eq(db.chars["Player-1-Tester"].realm, nil, "no name guessed with two realms")
  eq(db.chars["Player-2-Far"].realmID, 2, "the other character's own realm ID")
  check(db.realms[""] ~= nil, "prices of an unknown realm left as they are")
  eq(ns.realmUnfixed, 1, "counted as unplaced")
  eq(db.realmNames[1], nil, "no name for realm 1")
  -- an ID-only key goes to the name once the game says it again; a character that saved both teaches the name
  db.chars = { ["Player-1-Tester"] = { name = "Tester", realm = "Mock Realm", realmID = 1, side = "a", profs = {}, bags = {}, bank = {} },
    ["Player-2-Far"] = { name = "Far", side = "a", profs = {}, bags = {}, bank = {} } }
  db.realms = { ["realm:1"] = { fees = { [2665] = { 100, 40, "a", 200 } }, ranks = {}, prices = {} } }
  db.realmNames = {}
  ns.repairRealms()
  eq(db.realmNames[1], "Mock Realm", "name from a character that saved both")
  check(db.realms["realm:1"] == nil and db.realms["Mock Realm"].fees[2665], "ID-only prices moved to the name")
  eq(db.chars["Player-2-Far"].realm, nil, "the other realm's character not named")
  GetRealmName, GetRealmID = realName, realID
  db.chars, db.realms, db.realmNames = savedChars, savedRealms, savedNames
  ns.repairRealms()
end)

step("a kept route: reused until the target or a switch changes", function()
  local route = ns.plans.calculate(197, 200)
  check(route and #route.steps > 0, "no route")
  eq(route.from, 120, "starts at your skill")
  check(ns.plans.current(197, 200) == route, "not kept")
  eq(ns.plans.current(197, 225), nil, "another target reuses the route")
  EverlookCraftDB.settings.buffer = false
  eq(ns.plans.current(197, 200), nil, "a switch change reuses the route")
  EverlookCraftDB.settings.buffer = true
  check(ns.plans.current(197, 200) == route, "back to the same switches")
  for _, st in ipairs(route.steps) do
    local r = ns.plans.recipe(197, st.spell)
    check(st.known or (r.tier.a or 9) <= 2, r.name .. " routed but not learnable")
  end
end)

step("API: recipe, chance, stock, knownBy; read-only", function()
  local r = EverlookCraftAPI.recipe(2963)
  check(r and r.yellow == 25 and r.gray == 50, "recipe")
  eq(EverlookCraftAPI.chance(2963, 10), 1, "orange")
  eq(EverlookCraftAPI.stock(2589).alts, 7, "stock")
  eq(EverlookCraftAPI.knownBy(2963), 1, "known by one character")
  check(not pcall(function() EverlookCraftAPI.x = 1 end), "writable")
end)

step("API v6: characters, recipesOf, bagsOf (this realm and faction only, copies)", function()
  local api = EverlookCraftAPI
  eq(api.version, 7, "version")
  local db = EverlookCraftDB
  local saved = db.chars
  local me = ns.guid()
  db.chars = {
    [me] = saved[me],
    ["Player-1-Alt"] = { name = "Alt", realm = "Mock Realm", realmID = 1, side = "a", class = "MAGE", level = 40,
      profs = { [197] = { rank = 210, max = 225, known = { [2963] = true } }, [333] = { rank = 150, max = 225, known = {} } },
      bags = { [2589] = 9 }, bank = {} },
    ["Player-1-Hordie"] = { name = "Hordie", realm = "Mock Realm", realmID = 1, side = "h", profs = { [197] = { rank = 5, known = { [2963] = true } } },
      bags = {}, bank = {} },
    ["Player-2-Far"] = { name = "Far", realm = "Other Realm", realmID = 2, side = "a", profs = { [197] = { rank = 5, known = { [2963] = true } } },
      bags = {}, bank = {} },
    ["Player-1-NoProf"] = { name = "Nobody", realm = "Mock Realm", side = "a", profs = {}, bags = {}, bank = {} },
  }
  local ok, err = pcall(function()
    local list = api.characters()
    eq(#list, 2, "you and Alt (not the other faction, another realm or no recipes)")
    check(list[1].me and list[1].key == me, "you first")
    eq(list[2].name, "Alt", "alt")
    eq(list[2].class, "MAGE", "class")
    eq(#list[2].profs, 1, "a profession without known recipes is left out")
    eq(list[2].profs[1].name, "Tailoring", "profession name")
    eq(list[2].profs[1].rank, 210, "rank")
    eq(list[2].profs[1].known, 1, "known count")
    local rs = api.recipesOf("Player-1-Alt")
    eq(#rs, 1, "one recipe")
    eq(rs[1].spell, 2963, "spell")
    check(rs[1].creates and rs[1].skill == 197 and #rs[1].mats > 0, "creates, skill, mats")
    rs[1].mats[1][2] = 999
    check(api.recipesOf("Player-1-Alt")[1].mats[1][2] ~= 999, "a copy")
    eq(api.recipesOf("Player-1-Hordie"), nil, "other faction refused")
    eq(api.recipesOf("Player-2-Far"), nil, "another realm refused")
    eq(api.recipesOf("nobody"), nil, "unknown key")
    eq(api.bagsOf("Player-1-Alt")[2589], 9, "bags")
    api.bagsOf("Player-1-Alt")[2589] = 1
    eq(db.chars["Player-1-Alt"].bags[2589], 9, "bags are a copy")
    eq(api.bagsOf("Player-2-Far"), nil, "bags of another realm refused")
  end)
  db.chars = saved
  if not ok then error(err, 0) end
end)

step("slash: bare opens the window, help lists plan and guide, status, a typo suggests", function()
  SlashCmdList.EVERLOOKCRAFT("")
  check(ns.app:IsShown(), "window not open")
  SlashCmdList.EVERLOOKCRAFT("")
  check(not ns.app:IsShown(), "window not closed")
  MOCK.log = {}
  SlashCmdList.EVERLOOKCRAFT("help")
  local all = table.concat(MOCK.log, "\n")
  check(all:find("/ecraft plan", 1, true) and all:find("/ecraft guide", 1, true), "help: " .. all)
  MOCK.log = {}
  SlashCmdList.EVERLOOKCRAFT("status")
  check(table.concat(MOCK.log, "\n"):find("Route: Tailoring", 1, true), "status")
  MOCK.log = {}
  SlashCmdList.EVERLOOKCRAFT("gide")
  check(table.concat(MOCK.log, "\n"):find("guide", 1, true), "no suggestion")
  SlashCmdList.EVERLOOKCRAFT("buffer off")
  eq(EverlookCraftDB.settings.buffer, false, "setting from chat")
  SlashCmdList.EVERLOOKCRAFT("buffer on")
end)

step("the planner page and the guide window build and show a route", function()
  SlashCmdList.EVERLOOKCRAFT("plan tail")
  check(ns.app:IsShown(), "planner not open")
  eq(ns.options.selected(), 197, "profession from the command")
  ns.guide.open(197)
  check(EverlookCraftGuide and EverlookCraftGuide:IsShown(), "guide not shown")
  local rows = ns.guide.rows(ns.plans.saved(197), 120)
  local heads = {}
  for _, r in ipairs(rows) do if r.kind == "head" then heads[#heads + 1] = r.text end end
  eq(table.concat(heads, "|"), "Shopping list|In your bags|Steps", "sections")
  -- right-click marks the first step done
  EverlookCraftChar.done[197] = { [1] = true }
  local i = ns.plans.currentStep(ns.plans.saved(197), 120)
  eq(i, 2, "the next step is current after marking the first done")
  EverlookCraftChar.done[197] = {}
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

step("the shopping list: have / need, cost of what is short, where; ticks off as it lands; patterns and fees", function()
  local rt = ns.plans.calculate(197, 200, 120)
  check(rt, "no route")
  local shop = ns.plans.shopping(rt, 120)
  check(#shop.items > 0, "no items")
  local sum = 0
  for _, e in ipairs(shop.items) do
    check(e.need > 0 and e.have <= e.need and e.short == e.need - e.have, "have / need / short of " .. e.id)
    if e.make then check(e.price == nil, "a made item priced as bought")
    elseif e.cost then eq(e.cost, e.price * e.short, "cost of the short part"); sum = sum + e.cost end
  end
  for _, l in ipairs(shop.learn) do sum = sum + (l.price or 0) end
  for _, t in ipairs(shop.train) do sum = sum + (t.fee or 0) end
  eq(shop.total, sum, "the total is the items, patterns and fees")
  -- buy what is short of the first bought item: it ticks off
  local e
  for _, x in ipairs(shop.items) do if not x.make and x.short > 0 then e = x break end end
  check(e, "nothing short")
  local me = ns.me()
  me.bags[e.id] = (me.bags[e.id] or 0) + e.short
  local after
  for _, x in ipairs(ns.plans.shopping(rt, 120).items) do if x.id == e.id then after = x end end
  eq(after.short, 0, "still short after buying")
  me.bags[e.id] = me.bags[e.id] - e.short
  -- vendor goods stay off the auction house list
  for _, it in ipairs(ns.plans.auctionItems(shop)) do
    check(ns.prices.where(it[1]) ~= "vendor", "a vendor good on the auction house list")
  end
  -- crafts left from mid-step: the buffer share shrinks, never below the expected crafts
  for _, st in ipairs(rt.steps) do
    if st.to - st.from > 3 then
      local n, n90 = ns.plans.craftsLeft(rt, st, st.from + 1)
      check(n90 >= n and n90 <= st.n90, "mid-step buffer")
      break
    end
  end
end)

step("buy everything for the route: nothing owned is planned in, only bags count as bought", function()
  local me = ns.me()
  me.bags[2589] = 500
  EverlookCraftDB.settings.noOwn = true
  check(next(ns.stock.owned()) == nil, "owned with the switch on")
  me.bank[2589] = 40
  eq(ns.stock.forRoute(2589), 500, "bags only")
  EverlookCraftDB.settings.noOwn = false
  check(ns.stock.forRoute(2589) >= 540, "bags and bank")
  me.bank[2589] = nil
  me.bags[2589] = 20
end)

step("buy or craft in the guide: a click switches an intermediate, the list follows", function()
  local rt = ns.plans.calculate(197, 200, 120)
  local made
  for _, e in ipairs(ns.plans.shopping(rt, 120).items) do if e.make then made = e break end end
  check(made, "the route makes nothing first (bolts)")
  ns.guide.toggleMake(made)
  eq(EverlookCraftDB.craftBuy[made.id], "buy", "the pick")
  local now
  for _, e in ipairs(ns.plans.shopping(rt, 120).items) do if e.id == made.id then now = e end end
  check(now and not now.make and now.buying, "still made after picking buy")
  ns.craftList.setMode(made.id, nil)
end)

step("send to the auction house: EverlookDB Auctions, else Auctionator, waiting for item names", function()
  local rt = ns.plans.calculate(197, 200, 120)
  ns.me().bags, ns.me().bank = {}, {}
  local sent
  EverlookDBAuctionsAPI = { version = 2, addShoppingList = function(name, items) sent = { name = name, items = items }; return true, true end }
  MOCK.log = {}
  ns.guide.send()
  check(sent and sent.name == "Tailoring skill-up" and #sent.items > 0, "not sent to Auctions")
  EverlookDBAuctionsAPI = nil
  -- Auctionator: by exact name with the amount; a name not loaded yet waits
  local terms, list
  local loaded = false
  C_Item = C_Item or {}
  local oldName = C_Item.GetItemNameByID
  C_Item.GetItemNameByID = function(id) return loaded and ("Item " .. id) or nil end
  Auctionator = { API = { v1 = {
    ConvertToSearchString = function(_, t) return t.searchString .. ";" .. t.quantity end,
    CreateShoppingList = function(_, name, t) list, terms = name, t end,
  } } }
  MOCK.timers, MOCK.log = {}, {}
  ns.guide.send()
  eq(list, nil, "sent before the names loaded")
  loaded = true
  MOCK.RunTimers()
  eq(list, "Tailoring skill-up", "Auctionator list")
  check(#terms == #sent.items and terms[1]:find(";%d+$"), "terms with amounts")
  Auctionator, C_Item.GetItemNameByID = nil, oldName
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

step("rank rows: a book to buy and read, or a quest, where no trainer teaches the rank", function()
  local skill, step
  for sk, ranks in pairs(ns.DATA.ranks) do
    for st, rk in pairs(ranks) do if #rk[5] == 0 and rk[6] ~= 0 then skill, step = sk, st end end
  end
  check(skill, "no book rank in the data")
  local title = ns.options.rowTitle({ kind = "train", tr = { step = step } }, skill)
  check(title:find("buy and read", 1, true), "title: " .. title)
end)

step("stock from EverlookDB Auctions' inventory (API v7): mail counts, alts follow 'don't count my alts', no own counting", function()
  local me = ns.me()
  me.bags, me.bank = { [2589] = 1 }, {}
  local owned
  EverlookDBAuctionsAPI = { version = 7, inventory = {
    count = function(id)
      if id ~= 2589 then return { chars = { { me = true, bags = 0, bank = 0, mail = 0 } } } end
      return { chars = { { me = true, name = "Me", bags = 20, bank = 5, mail = 3, listed = 40, worn = 0 },
        { name = "Mara", bags = 0, bank = 10, mail = 2, listed = 0, worn = 0 } } }
    end,
    owned = function(withAlts) owned = withAlts; return { [2589] = withAlts and 40 or 28 } end,
    bagsOf = function(name) if name == "Mara" then return { [2589] = 9 } end end,
    onChange = function() end,
  } }
  local h = ns.stock.have(2589)
  eq(h.bags, 20, "bags from the shared store"); eq(h.bank, 5, "bank"); eq(h.mail, 3, "mail"); eq(h.alts, 12, "Mara's bank and mail")
  eq(h.byChar[1].name, "Mara", "by character")
  eq(ns.stock.usable(2589), 40, "bags, bank, mail and alts; auctions left out")
  eq(ns.stock.owned()[2589], 40, "the planner's stock")
  eq(owned, true, "alts asked for")
  EverlookCraftDB.settings.noAlts = true
  eq(ns.stock.usable(2589), 28, "alts left out")
  eq(ns.stock.owned()[2589], 28, "planner without alts")
  eq(owned, false, "alts not asked for")
  EverlookCraftDB.settings.noAlts = false
  eq(ns.stock.bagsOf({ name = "Mara", realmID = 1 })[2589], 9, "an alt's bags for Crafting profit")
  eq(EverlookCraftAPI.stock(2589).mail, 3, "API stock has mail")
  ns.stock.readBags()
  eq(me.bags[2589], 1, "no own counting while the shared store is there")
  EverlookDBAuctionsAPI = nil
  eq(ns.stock.have(2589).bags, 1, "without it: the own counts again")
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
