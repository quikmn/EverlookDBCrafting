-- Plans: runs the planner for a profession of this character with what the addon knows (recipes you know, your skill,
-- today's prices, your stock) and keeps the result per character (EverlookCraftChar.routes), so the amounts don't
-- jump after a /reload. A kept route is used until the target or a switch changes, or you press Recalculate.
local _, ns = ...
local try, plain = ns.try, ns.plain

local Pl = {}
ns.plans = Pl

-- the switches a route depends on: a change means a new route
local function keyOf(s)
  return table.concat({ s.vendorPatterns and 1 or 0, s.ahPatterns and 1 or 0, s.noAlts and 1 or 0, s.buffer and 1 or 0 }, "")
end

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

-- Calculate a route now and keep it. from defaults to your skill (1 when unknown), to to the default target.
function Pl.calculate(skill, to, from)
  local recipes = ns.recipes(skill)
  if not recipes then return nil, "no data for this profession" end
  local s = ns.settings()
  local rank, max, rec = Pl.skillNow(skill)
  from = math.max(1, from or rank or 1)
  to = math.min(300, to or Pl.defaultTarget(skill))
  if to <= from then return nil, "the target must be above your skill (" .. from .. ")" end
  local known = rec and rec.known or {}
  local P = ns.planner
  local ranks = ns.DATA.ranks[skill]
  local res = P.plan(recipes, {
    from = from, to = to, side = ns.side(), known = known,
    price = function(id) return (ns.prices.unit(id)) end,
    estimate = ns.prices.estimator(),
    patternPrice = ns.prices.pattern, ahPatternPrice = s.ahPatterns and ns.prices.patternAH or nil,
    vendorPatterns = s.vendorPatterns, ahPatterns = s.ahPatterns,
    owned = ns.stock.owned(), buffer = s.buffer, matsOf = ns.matsOf,
    ranks = ranks, maxSkill = max,
  })
  local out = {
    skill = skill, from = from, to = to, key = keyOf(s), at = time(), side = ns.side(), stall = res.stall,
    estimated = res.estimated, totals = res.totals, steps = {}, trainings = res.trainings, raw = {}, crafted = {},
  }
  local resale, resaleAny = 0, false
  for _, st in ipairs(res.steps) do
    out.steps[#out.steps + 1] = { spell = st.r.spell, from = st.from, to = st.to + 1, n = st.n, n90 = st.n90,
      each = st.each, est = st.est or nil, early = st.early or nil, patternPrice = st.patternPrice, fee = st.fee,
      known = known[st.r.spell] or nil, again = st.again or nil }
    if st.r.creates and st.r.creates ~= 0 then
      local p = ns.prices.ah(st.r.creates)
      if p then resale, resaleAny = resale + p * st.r.yield * st.n * 0.95, true end
    end
  end
  out.resale = resaleAny and resale or nil
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

-- the step your skill is in now (the first not marked done that you haven't passed), its index
function Pl.currentStep(route, skillNow)
  local done = EverlookCraftChar.done[route.skill] or {}
  for i, st in ipairs(route.steps) do
    local passed = skillNow and skillNow >= st.to
    if not passed and not done[i] then return i, st end
  end
  return nil
end

-- What the rest of the route still needs (from your skill now): { [id] = n } for direct materials of the remaining
-- crafts, intermediates broken down as the route planned them.
function Pl.remaining(route, skillNow)
  local need, makes, made = {}, {}, {}
  for _, c in ipairs(route.crafted or {}) do makes[c.id] = c end
  local done = EverlookCraftChar.done[route.skill] or {}
  local buffer = ns.settings().buffer
  local function take(id, n, guard)
    local m = makes[id]
    local r = m and Pl.recipe(route.skill, m.spell) or (m and ns.recipeBySpell(m.spell))
    if r and guard < 8 then
      local have = ns.stock.usable(id)
      local short = math.max(0, n - have)
      local crafts = math.ceil(short / (r.yield or 1) - 1e-6)
      need[id] = (need[id] or 0) + n
      for _, mm in ipairs(ns.matsOf(r)) do take(mm[1], crafts * mm[2], guard + 1) end
    else
      need[id] = (need[id] or 0) + n
    end
  end
  for i, st in ipairs(route.steps) do
    if not done[i] and not (skillNow and skillNow >= st.to) then
      local r = Pl.recipe(route.skill, st.spell)
      if r then
        local a = math.max(st.from, skillNow or st.from)
        local n, n90 = ns.planner.craftsBetween(r, a, st.to)
        if a == st.from then n, n90 = st.n, st.n90 end
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
  return need
end

-- crafts left in a step from skill s
function Pl.craftsLeft(route, st, s)
  local r = Pl.recipe(route.skill, st.spell)
  if not r then return st.n, st.n90 end
  if not s or s <= st.from then return st.n, st.n90 end
  return ns.planner.craftsBetween(r, s, st.to)
end
