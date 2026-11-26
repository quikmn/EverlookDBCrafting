-- Plans: runs the planner for a profession of this character with what the addon knows (recipes you know, your skill,
-- today's prices, your stock) and keeps the result per character (EverlookCraftChar.routes), so the amounts don't
-- jump after a /reload. A kept route is used until the target or a switch changes, or you press Recalculate.
-- Pl.shopping turns a route into the one shopping list the planner and the guide show: every material still to get
-- (have / need, price, where: auction house, vendor or make it), the patterns and fees still to pay.
local _, ns = ...
local try, plain = ns.try, ns.plain

local Pl = {}
ns.plans = Pl

-- the switches a route depends on: a change means a new route
local function keyOf(s)
  return table.concat({ s.vendorPatterns and 1 or 0, s.ahPatterns and 1 or 0, s.noAlts and 1 or 0, s.buffer and 1 or 0,
    s.noOwn and 1 or 0 }, "")
end
Pl.keyOf = keyOf

function Pl.skillNow(skill)
  local p = ns.scan.mine(skill)
  return p and p.rank or nil, p and p.max or nil, p
end

-- the default target: the next rank's cap above your skill, else 300
function Pl.defaultTarget(skill)
  local rank, max = Pl.skillNow(skill)
  rank = rank or 1
  if max and max > rank and max < 300 then return max end
  for _, cap in ipairs({ 75, 150, 225, 300 }) do
    if cap > rank then return cap end
  end
  return 300
end

function Pl.saved(skill)
  return EverlookCraftChar and EverlookCraftChar.routes[skill]
end

-- the saved route, when it still fits the target and switches
function Pl.current(skill, target)
  local r = Pl.saved(skill)
  if not r then return nil end
  if target and r.to ~= target then return nil end
  if r.key ~= keyOf(ns.settings()) then return nil end
  return r
end

---------------------------------------------------------------------------------------------------------------------
-- Reputation: a vendor pattern behind a standing (the data's recipeItems[item].rep = { faction name, standing 0 Hated
-- .. 7 Exalted }) counts once you have it. Read from the reputation panel (by name); unknown counts as not met.

local function standingOf(name)
  local CR = C_Reputation
  if CR and CR.GetNumFactions and CR.GetFactionDataByIndex then
    for i = 1, plain(try(CR.GetNumFactions)) or 0 do
      local d = try(CR.GetFactionDataByIndex, i)
      if type(d) == "table" and plain(d.name) == name then return plain(d.reaction) end
    end
  end
  for i = 1, plain(try(GetNumFactions)) or 0 do
    local n, _, standing = try(GetFactionInfo, i)
    if plain(n) == name then return plain(standing) end
  end
end

function ns.repOk(r)
  local ri = r and r.item and r.item ~= 0 and ns.DATA.recipeItems[r.item]
  local rep = ri and ri.rep
  if not rep then return false end
  local standing = standingOf(rep[1])   -- 1 Hated .. 8 Exalted
  return type(standing) == "number" and standing - 1 >= rep[2]
end

-- the player's pick for a material that can be made: "buy", "craft" or nil (the cheaper way); shared with the
-- Crafting list
function Pl.choice(id)
  local c = EverlookCraftDB and EverlookCraftDB.craftBuy and EverlookCraftDB.craftBuy[id]
  return (c == "buy" or c == "craft") and c or nil
end

-- Calculate a route now and keep it. from defaults to your skill (1 when unknown), to to the default target.
function Pl.calculate(skill, to, from)
  local recipes = ns.recipes(skill)
  if not recipes then return nil, "no data for this profession" end
  local s = ns.settings()
  local rank, max, rec = Pl.skillNow(skill)
  from = math.max(1, from or rank or 1)
  to = math.min(300, to or Pl.defaultTarget(skill))
  if to <= from then return nil, "the target must be above the starting skill (" .. from .. ")" end
  local known = rec and rec.known or {}
  local P = ns.planner
  local ranks = ns.DATA.ranks[skill]
  -- what one craft reliably gets back (taken off its cost), and what its product is worth at best (for ties)
  local function back(r)
    if not r.creates or r.creates == 0 then return 0 end
    return (ns.prices.back(r.creates)) * r.yield
  end
  -- a material -> the highest gray skill of a recipe that uses it: a product is useful while that is still ahead
  local later = {}
  for _, r in ipairs(recipes) do
    if r.skip == nil or r.skip == "" then
      for _, m in ipairs(ns.matsOf(r)) do later[m[1]] = math.max(later[m[1]] or 0, r.gray) end
    end
  end
  local function worth(r)
    if not r.creates or r.creates == 0 then return 0 end
    local v = ns.prices.worth(r.creates)
    if (later[r.creates] or 0) > r.yellow then v = math.max(v, (ns.prices.unit(r.creates)) or 0) end
    return math.max(0, v * r.yield - back(r))
  end
  local res = P.plan(recipes, {
    from = from, to = to, side = ns.side(), known = known,
    price = function(id) return (ns.prices.unit(id)) end,
    estimate = ns.prices.estimator(),
    patternPrice = ns.prices.pattern, ahPatternPrice = s.ahPatterns and ns.prices.patternAH or nil,
    vendorPatterns = s.vendorPatterns, ahPatterns = s.ahPatterns,
    owned = ns.stock.owned(), buffer = s.buffer, matsOf = ns.matsOf,
    ranks = ranks, maxSkill = (from == (rank or from)) and max or nil,
    tools = ns.DATA.tools, hasItem = function(id) return (ns.stock.usable(id) or 0) > 0 end,
    choice = Pl.choice, repOk = s.vendorPatterns ~= false and ns.repOk or nil,
    back = back, worth = worth,
  })
  local out = {
    skill = skill, from = from, to = to, key = keyOf(s), at = time(), side = ns.side(), stall = res.stall,
    estimated = res.estimated, totals = res.totals, steps = {}, trainings = res.trainings, raw = {}, crafted = {},
    startSkill = from ~= rank and from or nil,
  }
  local resale, resaleAny, backSum = 0, false, 0
  for _, st in ipairs(res.steps) do
    out.steps[#out.steps + 1] = { spell = st.r.spell, from = st.from, to = st.to + 1, n = st.n, n90 = st.n90,
      crafts = st.crafts, var = st.var, extra = st.extra,
      each = st.each, est = st.est or nil, early = st.early or nil, patternPrice = st.patternPrice, fee = st.fee,
      known = known[st.r.spell] or nil, again = st.again or nil, rep = st.rep or nil, green = st.green or nil,
      back = st.back and st.back > 0 and st.back or nil }
    backSum = backSum + (st.back or 0) * st.n
    if st.r.creates and st.r.creates ~= 0 then
      local p = ns.prices.ah(st.r.creates)
      if p then resale, resaleAny = resale + p * st.r.yield * st.n * 0.95, true end
    end
  end
  out.resale = resaleAny and resale or nil
  -- what the crafts reliably get back (vendor prices, goods that sell): already taken off when the route was chosen
  out.back = backSum > 0 and backSum or nil
  -- the tools to make or buy first: { key, name, at (the skill of the first step that needs it), kind, spell, item, price }
  out.tools = {}
  for _, tl in ipairs(res.tools or {}) do
    out.tools[#out.tools + 1] = { key = tl.key, name = tl.name, at = tl.at, kind = tl.kind, spell = tl.r and tl.r.spell or nil,
      item = tl.item, price = tl.price }
  end
  for _, x in ipairs(res.shop.raw) do out.raw[#out.raw + 1] = { id = x.id, n = x.n, price = x.price } end
  for _, x in ipairs(res.shop.crafted) do out.crafted[#out.crafted + 1] = { id = x.id, n = x.n, crafts = x.crafts, spell = x.via.spell } end
  EverlookCraftChar.routes[skill] = out
  EverlookCraftChar.lastSkill = skill
  -- marks belong to the old route
  EverlookCraftChar.done[skill] = {}
  if ns.onRoute then ns.onRoute(skill) end
  return out
end

function Pl.recipe(skill, spell)
  local rs = ns.recipes(skill)
  return rs and rs.bySpell[spell]
end

-- do you know a recipe now: the last profession window, or the spell book (learned at a trainer since)
function Pl.knows(skill, spell)
  local _, _, rec = Pl.skillNow(skill)
  if rec and rec.known and rec.known[spell] then return true end
  return plain(try(IsPlayerSpell, spell)) == true
end

-- the step your skill is in now (the first not marked done that you haven't passed), its index
function Pl.currentStep(route, skillNow)
  local done = EverlookCraftChar.done[route.skill] or {}
  for i, st in ipairs(route.steps) do
    local passed = skillNow and skillNow >= st.to
    if not passed and not done[i] then return i, st end
  end
  return nil
end

-- Crafts left in a step from skill s: expected, and with its share of the route's 90% buffer (the share shrinks with
-- the variance still ahead). A route saved before the buffer was shared out falls back to the step's own 90%.
function Pl.craftsLeft(route, st, s)
  local r = Pl.recipe(route.skill, st.spell)
  if not s or s <= st.from or not r then return st.n, st.n90 end
  if not st.var then return ns.planner.craftsBetween(r, s, st.to) end
  local mean, var = ns.planner.meanVar(r, s, st.to)
  local n = math.ceil(mean - 1e-6)
  local extra = (st.extra or 0) * (st.var > 0 and var / st.var or 0)
  return n, math.max(n, math.ceil(mean + extra - 1e-6))
end

-- who makes an item for this route: nil (buy it), else the recipe. The player's pick (Pl.choice) first, then what the
-- route chose; "craft" on an item the route buys takes a recipe of this profession, else one your characters know.
function Pl.makerOf(route, id)
  local pick = Pl.choice(id)
  if pick == "buy" then return nil end
  for _, c in ipairs(route.crafted or {}) do
    if c.id == id then return Pl.recipe(route.skill, c.spell) or ns.recipeBySpell(c.spell) end
  end
  for _, tl in ipairs(route.tools or {}) do
    if tl.kind == "make" and tl.item == id and tl.spell then return Pl.recipe(route.skill, tl.spell) or ns.recipeBySpell(tl.spell) end
  end
  if pick == "craft" then return Pl.makerHere(route, id) or (ns.craftList and ns.craftList.knownMaker(id)) end
end

-- a recipe of the route's profession that makes an item and that you know or can learn reliably (the lowest first)
function Pl.makerHere(route, id)
  local best
  for _, r in ipairs(ns.recipes(route.skill) or {}) do
    if r.creates == id and (r.skip == nil or r.skip == "") and #r.mats > 0
        and (Pl.knows(route.skill, r.spell) or (r.tier[route.side or ns.side()] or 9) <= 2) then
      if not best or r.learn < best.learn then best = r end
    end
  end
  return best
end

-- does the route still need a tool: no item of it on any of your characters (tools are never used up)
local function toolMissing(tl)
  local tool = ns.DATA.tools and ns.DATA.tools[tl.key]
  for _, id in ipairs(tool and tool[2] or { tl.item }) do
    if (ns.stock.usable(id) or 0) > 0 then return false end
  end
  return true
end
Pl.toolMissing = toolMissing

-- What the rest of the route still needs (from your skill now): { [id] = n } for direct materials of the remaining
-- crafts, intermediates (made, as the route or your pick says) with their own materials for the part you don't have,
-- and a tool you have none of.
function Pl.remaining(route, skillNow)
  local need, made = {}, {}
  local done = EverlookCraftChar.done[route.skill] or {}
  local buffer = ns.settings().buffer
  local function take(id, n, guard)
    local r = guard < 8 and Pl.makerOf(route, id)
    need[id] = (need[id] or 0) + n
    if r then
      local have = ns.stock.forRoute(id)
      local short = math.max(0, n - have)
      local crafts = math.ceil(short / (r.yield or 1) - 1e-6)
      for _, mm in ipairs(ns.matsOf(r)) do take(mm[1], crafts * mm[2], guard + 1) end
    end
  end
  local lastTo
  for i, st in ipairs(route.steps) do
    if not done[i] and not (skillNow and skillNow >= st.to) then
      lastTo = st.to
      local r = Pl.recipe(route.skill, st.spell)
      if r then
        local n, n90 = Pl.craftsLeft(route, st, skillNow and math.max(st.from, skillNow) or st.from)
        local crafts = buffer and n90 or n
        for _, m in ipairs(ns.matsOf(r)) do
          -- what earlier steps make feeds later ones first
          local want = crafts * m[2]
          local use = math.min(want, made[m[1]] or 0)
          if use > 0 then made[m[1]] = made[m[1]] - use end
          if want - use > 0 then take(m[1], want - use, 0) end
        end
        if r.creates and r.creates ~= 0 then made[r.creates] = (made[r.creates] or 0) + crafts * (r.yield or 1) end
      end
    end
  end
  -- tools for the steps still ahead
  for _, tl in ipairs(route.tools or {}) do
    if lastTo and tl.item and (tl.kind == "make" or tl.kind == "buy") and toolMissing(tl) then take(tl.item, 1, 0) end
  end
  return need
end

---------------------------------------------------------------------------------------------------------------------
-- The shopping list

-- the nearest vendor of an item for your side: npc id, its name, zone
function Pl.vendorOf(id)
  local it = ns.DATA.items[id]
  if not (it and it[7] and #it[7] > 0) then return nil end
  local npc, _, zone = ns.map.nearest(it[7])
  if not npc then return nil end
  return npc, ns.DATA.npcs[npc][1], zone
end

-- what crafting one costs: its materials at today's prices / its yield; nil when a material has no price
function Pl.craftUnit(r)
  local c = 0
  for _, m in ipairs(ns.matsOf(r)) do
    local p = ns.prices.unit(m[1])
    if not p then return nil end
    c = c + p * m[2]
  end
  return c / (r.yield or 1)
end

--[[ The shopping list of a route from skill s on:
  items = { { id, need, have, short, price, how ("ah" | "vendor" | nil: no price), cost (of the short part),
              make (recipe: you make it), craftU, buyU (both prices of an item you can make or buy), buying (your pick) } }
          sorted: auction house, vendors, no price, then what you make; by name in each
  learn = { { spell, r, item (pattern), price, how ("vendor" | "ah" | "trainer" | "teacher"), at } }: recipes to learn
  train = { { tr, fee } }: ranks still to train
  total, unpriced (how many have no price), buyCount (items to buy) ]]
function Pl.shopping(route, s)
  local out = { items = {}, learn = {}, train = {}, total = 0, unpriced = 0, buyCount = 0 }
  if not route then return out end
  local need = Pl.remaining(route, s)
  for id, n in pairs(need) do
    local have = ns.stock.forRoute(id)
    local e = { id = id, need = n, have = math.min(have, n), short = math.max(0, n - have) }
    e.make = Pl.makerOf(route, id)
    local price, how = ns.prices.unit(id)
    if e.make then
      e.craftU = Pl.craftUnit(e.make)
      e.buyU = price
      e.buyHow = how
    else
      e.price, e.how = price, how
      if e.short > 0 then
        out.buyCount = out.buyCount + 1
        if price then e.cost = price * e.short; out.total = out.total + e.cost else out.unpriced = out.unpriced + 1 end
      end
    end
    out.items[#out.items + 1] = e
  end
  -- an item the route makes and that is for sale is a choice (e.buyU); one it buys but could make, too (e.buying)
  -- and an item bought that you could make in this profession: offered the other way round
  for _, e in ipairs(out.items) do
    if not e.make then
      local r = Pl.makerHere(route, e.id)
      if r then e.buying, e.craftU = true, Pl.craftUnit(r) end
    end
  end
  local order = { ah = 1, vendor = 2 }
  local function rank(e) return e.make and 4 or order[e.how] or 3 end
  table.sort(out.items, function(x, y)
    if rank(x) ~= rank(y) then return rank(x) < rank(y) end
    return (ns.itemInfo(x.id)) < (ns.itemInfo(y.id))
  end)
  -- recipes still to learn, once each, for the steps ahead
  local done, seen = EverlookCraftChar.done[route.skill] or {}, {}
  for i, st in ipairs(route.steps) do
    if not done[i] and not (s and s >= st.to) and not seen[st.spell] then
      seen[st.spell] = true
      local r = Pl.recipe(route.skill, st.spell)
      if r and not st.known and not Pl.knows(route.skill, st.spell) and not r.auto then
        local pattern = r.item and r.item ~= 0 and not r.trained
        local e = { spell = st.spell, r = r, at = st.from }
        if pattern then
          e.item = r.item
          e.price = st.patternPrice
          e.how = ((r.tier[route.side or ns.side()] or 9) <= 2 or st.rep) and "vendor" or "ah"
        elseif r.trained or r.fee then
          e.price, e.how = st.fee or r.fee, "trainer"
        else
          e.how = "teacher"
        end
        if e.price then out.total = out.total + e.price elseif e.how ~= "teacher" then out.unpriced = out.unpriced + 1 end
        out.learn[#out.learn + 1] = e
      end
    end
  end
  local _, max = Pl.skillNow(route.skill)
  for _, tr in ipairs(route.trainings or {}) do
    if not (max and max >= tr.newCap) then
      out.train[#out.train + 1] = { tr = tr, fee = tr.fee }
      if tr.fee then out.total = out.total + tr.fee else out.unpriced = out.unpriced + 1 end
    end
  end
  return out
end

-- the shopping list's items for the auction house: { { id, n } } (what you still have to buy there, plus what has no
-- price at all: a scan may find it)
function Pl.auctionItems(shop)
  local items = {}
  for _, e in ipairs(shop.items) do
    if not e.make and e.short > 0 and e.how ~= "vendor" then
      items[#items + 1] = { e.id, e.short }
    end
  end
  return items
end
