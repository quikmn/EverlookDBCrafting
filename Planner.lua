-- The Skill-Up planner: the cheapest reliable route from your skill to a target. Pure Lua (no game calls), so the
-- tests run it offline and check it against the site's own route code (everlookdb.com/professions).
--
-- The route follows the site's rule for every professions guide, in this order (the site's web/route.js):
--   1. every step must reliably give its skill-ups: a recipe you know, or one you can learn now for your faction
--      (trainer, a one-off teacher outside a dungeon, a vendor pattern). Dungeon, drop, quest and unknown recipes are
--      never in it (with "Patterns from the auction house" on, a drop whose pattern is up for sale today is); a vendor
--      pattern behind a reputation only once you have that standing (o.repOk; the site, not knowing you, never does).
--      Orange recipes first (always a point), then yellow; a yellow one replaces an orange one only when the orange
--      one would cost more than P.ORANGE_WORTH times as much per point. Green only when nothing orange or yellow
--      exists at that skill, and the step says so (st.green);
--   2. then the cheapest per skill point, in gold at today's prices, less what the craft reliably gets back
--      (o.back: its vendor price, or selling a good that trades at the auction house);
--   3. two that cost about the same (within P.NEAR per point): the one whose product is worth more (o.worth);
--   4. a step sticks with the recipe in hand unless another of the same colour is clearly cheaper, so steps stay long.
-- The skill-up chance is the classic one: orange always, yellow to green (gray - skill) / (gray - yellow), gray never.
-- One-time costs (a pattern, a trainer fee) are then weighed by trying the route without each such recipe and keeping
-- whichever is cheaper, as long as it has no more yellow or green points.
local _, ns = ...
ns = ns or {}

local P = {}
ns.planner = P

P.CAP = 300
P.STRETCH = 30            -- nothing learnable yet: assume the trainer teaches the next recipe up to 30 points early
P.BREAKS = { [75] = true, [150] = true, [225] = true }
P.Z90 = 1.2816            -- the 90% point of the normal distribution
P.MAIN_TIER = 2
P.NEAR = 0.12             -- "about the same" cost per skill point
P.STICK = 0.15            -- a step keeps its recipe unless another of the same colour is more than this much cheaper
P.ORANGE_WORTH = 2        -- orange before yellow, up to this many times the yellow cost per point
local EPS = 1e-9
local COLORS = { "orange", "yellow", "green" }
local FACTOR = { [0] = 1, [1] = 1.1, [2] = 1.6, [3] = 4 }
local COOLDOWN = 1000
local INF = math.huge

function P.tierFactor(t) return FACTOR[t] or INF end

-- the chance that one craft of r raises skill s
function P.chance(r, s)
  if s < r.learn or s >= r.gray then return 0 end
  if s < r.yellow then return 1 end
  return math.min(1, math.max(0, (r.gray - s) / (r.gray - r.yellow)))
end

-- The cost of one unit of each material: its price, or crafting it from a recipe of the pool when that is cheaper
-- (a recipe that needs a cooldown is bought, not made). base(id) -> { e = copper, gold = copper, est = bool }.
-- Same algorithm as the site's analyse(): the memo keeps only answers made outside a loop.
-- choice(id) (optional): "buy" never crafts it, "craft" crafts it even when buying is cheaper (the player's pick).
local function costing(pool, base, matsOf, choice)
  local makers = {}
  for _, r in ipairs(pool) do
    if r.creates and r.creates ~= 0 and r.skip ~= "unavailable" and r.skip ~= "missing" and #matsOf(r) > 0 then
      makers[r.creates] = makers[r.creates] or {}
      table.insert(makers[r.creates], r)
    end
  end
  local memo, stack, depth = {}, {}, 0
  local function cost(id)
    if memo[id] then return memo[id] end
    local b = base(id)
    local best = { e = b.e, gold = b.gold, est = b.est, via = nil }
    local pick = choice and choice(id)
    local forced = pick == "craft"
    if makers[id] and not stack[id] and pick ~= "buy" then
      stack[id], depth = true, depth + 1
      for _, r in ipairs(makers[id]) do
        if r.skip ~= "cooldown" then
          local e, gold, est = 0, 0, false
          for _, m in ipairs(matsOf(r)) do
            local x = cost(m[1])
            e, gold, est = e + x.e * m[2], gold + x.gold * m[2], est or x.est
          end
          e = e / r.yield
          if e < best.e or (forced and not best.via) then best = { e = e, gold = gold / r.yield, est = est, via = r } end
        end
      end
      stack[id], depth = nil, depth - 1
    end
    if depth == 0 then memo[id] = best end
    return best
  end
  return cost
end
P.costing = costing

function P.colorAt(r, s)
  return s < r.yellow and "orange" or s < r.green and "yellow" or "green"
end

-- The recipe for skill point s (the site's pickAt): recipe, colour, chance; nil when nothing gives a point.
function P.pickAt(usable, s, costOf, worthOf, prev)
  local by = { orange = {}, yellow = {}, green = {} }
  local low = { orange = INF, yellow = INF, green = INF }
  for _, r in ipairs(usable) do
    local c = P.chance(r, s)
    if c > 0 then
      local score, color = costOf(r) / c, P.colorAt(r, s)
      if score < INF then
        local l = by[color]
        l[#l + 1] = { r = r, c = c, score = score }
        if score < low[color] then low[color] = score end
      end
    end
  end
  for _, color in ipairs(COLORS) do
    local cands, best = by[color], low[color]
    -- orange comes first, but not at any price
    local skip = #cands == 0 or (color == "orange" and #by.yellow > 0 and best > low.yellow * P.ORANGE_WORTH + EPS)
    if not skip then
      if prev then
        for _, x in ipairs(cands) do
          if x.r == prev and x.score <= best * (1 + P.STICK) + EPS then return prev, color, x.c end
        end
      end
      local pick
      for _, x in ipairs(cands) do
        if x.score <= best * (1 + P.NEAR) + EPS then
          x.left = x.score - math.max(0, worthOf and worthOf(x.r) or 0) / x.c
          if not pick or x.left < pick.left - EPS
            or (math.abs(x.left - pick.left) <= EPS and (x.score < pick.score - EPS
              or (math.abs(x.score - pick.score) <= EPS and x.r.yellow > pick.r.yellow))) then
            pick = x
          end
        end
      end
      return pick.r, color, pick.c
    end
  end
  return nil
end

-- The site's buildGuide: steps, the skill the route stalls at (nil: it reaches `to`), and how many points of each
-- colour it has ({ orange, yellow, green }).
function P.guide(usable, costOf, from, to, worthOf)
  local points, prev, stall = {}, nil, nil
  local count = { orange = 0, yellow = 0, green = 0 }
  for s = from, to - 1 do
    local best, color, c = P.pickAt(usable, s, costOf, worthOf, prev)
    local early = false
    if not best then
      for _, r in ipairs(usable) do
        if not (s >= r.learn or s >= r.gray or r.yellow - s > P.STRETCH) then
          if not best or r.learn < best.learn or (r.learn == best.learn and costOf(r) < costOf(best)) then best = r end
        end
      end
      early = best ~= nil
      if best then color, c = P.colorAt(best, s), 1 end
    end
    if not best then stall = s break end
    points[#points + 1] = { s = s, r = best, chance = c, early = early, color = color }
    count[color] = count[color] + 1
    prev = best
  end
  local steps = {}
  for _, pt in ipairs(points) do
    local last = steps[#steps]
    if last and last.r == pt.r and not P.BREAKS[pt.s] then
      last.to = pt.s
      last.crafts = last.crafts + 1 / pt.chance
      last.var = last.var + (1 - pt.chance) / (pt.chance * pt.chance)
      last.early = last.early or pt.early
      last.green = last.green or pt.color == "green"
    else
      steps[#steps + 1] = { from = pt.s, to = pt.s, r = pt.r, crafts = 1 / pt.chance,
        var = (1 - pt.chance) / (pt.chance * pt.chance), early = pt.early, green = pt.color == "green" }
    end
  end
  for _, st in ipairs(steps) do
    st.n = math.ceil(st.crafts - 1e-6)
    st.n90 = math.max(st.n, math.ceil(st.crafts + P.Z90 * math.sqrt(st.var) - 1e-6))
  end
  return steps, stall, count
end

-- The expected crafts and their variance from skill a to b with recipe r (each skill point a geometric draw).
function P.meanVar(r, a, b)
  local mean, var = 0, 0
  for s = a, b - 1 do
    local p = P.chance(r, s)
    if p <= 0 then p = 1 end
    mean, var = mean + 1 / p, var + (1 - p) / (p * p)
  end
  return mean, var
end

-- Crafts expected (and at 90%) to go from skill a to b with recipe r, on its own: the remaining part of a step.
function P.craftsBetween(r, a, b)
  local mean, var = P.meanVar(r, a, b)
  return math.ceil(mean - 1e-6), math.max(math.ceil(mean - 1e-6), math.ceil(mean + P.Z90 * math.sqrt(var) - 1e-6))
end

-- The 90% buffer of a whole route: enough crafts to reach the target 9 times out of 10 (the sum of every step's
-- draws, normal approximation), shared out over the steps by their variance, so an orange step gets none and the
-- route doesn't pay for a 90% margin on every single step. Sets st.extra (crafts on top of the mean) and st.n90.
function P.spreadBuffer(steps)
  local total = 0
  for _, st in ipairs(steps) do total = total + (st.var or 0) end
  local buffer = P.Z90 * math.sqrt(total)
  for _, st in ipairs(steps) do
    st.extra = total > 0 and buffer * (st.var or 0) / total or 0
    st.n90 = math.max(st.n, math.ceil(st.crafts + st.extra - 1e-6))
  end
  return buffer
end

-- What a recipe takes to learn for this plan: nil when it can't be in the route at all.
-- Known recipes always can (and cost nothing more). Otherwise tier <= 2 for your side, a vendor pattern only with
-- that switch on, a tier-3 recipe only when its pattern is for sale on the auction house and that switch is on.
local function repPattern(r, o)
  return (r.tier[o.side] or 9) == 3 and r.why and r.why[o.side] == "rep" and r.item and r.item ~= 0
    and o.repOk and o.repOk(r) and o.patternPrice and o.patternPrice(r) or nil
end
P.repPattern = repPattern

local function learnable(r, o)
  if o.known and o.known[r.spell] then return 0, 0 end
  if r.needsCd then return nil end
  -- a vendor pattern behind a reputation you already have (o.repOk): as good as any vendor pattern
  local rp = repPattern(r, o)
  if rp then return 1, rp + (r.fee or 0) end
  local t = r.tier[o.side] or 9
  if t <= P.MAIN_TIER then
    local pattern = r.item and r.item ~= 0 and not r.trained and not r.auto
    if pattern and o.vendorPatterns == false then return nil end
    return t, (pattern and o.patternPrice and o.patternPrice(r) or 0) + (r.fee or 0), pattern and o.patternPrice and o.patternPrice(r) == nil
  end
  if t == 3 and o.ahPatterns and r.item and r.item ~= 0 and o.ahPatternPrice then
    local pr = o.ahPatternPrice(r)
    if pr then return 1, pr end
  end
  return nil
end
P.learnable = learnable

-- One route: the pool, its steps (never a recipe in `excluded`; those still count as ways to make a material), and
-- its cost in gold (materials per craft, less what the crafts reliably get back, plus one-time costs).
local function route(recipes, o, excluded, base)
  local pool, tierOf, once, onceUnknown = {}, {}, {}, {}
  for _, r in ipairs(recipes) do
    local t, cost, unknown = learnable(r, o)
    if t then
      pool[#pool + 1] = r
      tierOf[r], once[r], onceUnknown[r] = t, cost or 0, unknown
    end
  end
  local matsOf = o.matsOf or function(r) return r.mats end
  local cost = costing(pool, base, matsOf, o.choice)
  local rcost, est, net = {}, {}, {}
  for _, r in ipairs(pool) do
    local e, isEst = 0, false
    for _, m in ipairs(matsOf(r)) do
      local x = cost(m[1])
      e, isEst = e + x.e * m[2], isEst or x.est
    end
    rcost[r], est[r] = e, isEst
    net[r] = math.max(0, e - (o.back and o.back(r) or 0))
  end
  local function costOf(r)
    local fac = P.tierFactor(tierOf[r])
    return net[r] * fac + (fac - 1) * 0.01
  end
  local usable = {}
  for _, r in ipairs(pool) do
    if not excluded[r] and (r.skip == nil or r.skip == "") and costOf(r) < INF then usable[#usable + 1] = r end
  end
  local steps, stall, points = P.guide(usable, costOf, o.from, o.to, o.worth)
  local total, seen = 0, {}
  for _, st in ipairs(steps) do
    st.each, st.est = rcost[st.r], est[st.r]
    st.back = o.back and o.back(st.r) or nil
    total = total + st.n * net[st.r]
    if not seen[st.r] then
      seen[st.r] = true
      st.once, st.onceUnknown = once[st.r], onceUnknown[st.r]
      total = total + (once[st.r] or 0)
    end
  end
  return { steps = steps, stall = stall, total = total, cost = cost, once = once, pool = pool, points = points }
end

-- The shopping list of a route, the site's shopping(): each step's materials, expanded into what they are made of
-- wherever crafting them is cheaper. count(step) -> how many crafts to shop for.
function P.shopping(res, matsOf, count)
  matsOf = matsOf or function(r) return r.mats end
  local raw, crafted = {}, {}
  local function take(id, n, guard)
    local c = res.cost(id)
    if c.via and guard < 12 then
      -- n needed; each craft makes `yield` of them, and you can only craft whole times
      local crafts = math.ceil(n / c.via.yield - 1e-6)
      local cur = crafted[id]
      if cur then cur.crafts, cur.made = cur.crafts + crafts, cur.made + crafts * c.via.yield
      else crafted[id] = { crafts = crafts, made = crafts * c.via.yield, via = c.via } end
      for _, m in ipairs(matsOf(c.via)) do take(m[1], crafts * m[2], guard + 1) end
    else
      raw[id] = (raw[id] or 0) + n
    end
  end
  -- what earlier steps make is used by later ones before anything is bought (a step of bolts feeds the shirts)
  local made = {}
  for _, st in ipairs(res.steps) do
    for _, m in ipairs(matsOf(st.r)) do
      local n = count(st) * m[2]
      local use = math.min(n, made[m[1]] or 0)
      if use > 0 then made[m[1]] = made[m[1]] - use end
      if n - use > 0 then take(m[1], n - use, 0) end
    end
    if st.r.creates and st.r.creates ~= 0 then made[st.r.creates] = (made[st.r.creates] or 0) + count(st) * st.r.yield end
  end
  local rawList, craftedList = {}, {}
  for id, n in pairs(raw) do rawList[#rawList + 1] = { id = id, n = math.ceil(n - 1e-6) } end
  for id, v in pairs(crafted) do craftedList[#craftedList + 1] = { id = id, n = v.made, crafts = v.crafts, via = v.via } end
  table.sort(rawList, function(x, y) return x.id < y.id end)
  table.sort(craftedList, function(x, y) return x.id < y.id end)
  return rawList, craftedList
end

-- The rank trainings a route passes: at each cap you still have to raise (75, 150, 225), the next rank.
-- ranks[step] = { cap, req, level, fee }; maxSkill = your current maximum (75 for Apprentice ...).
function P.trainings(ranks, from, to, maxSkill)
  local out = {}
  if not ranks then return out end
  for step = 2, 4 do
    local prev, rk = ranks[step - 1], ranks[step]
    if prev and rk then
      local cap = prev[1]
      if cap < to and cap >= from and (not maxSkill or maxSkill <= cap) then
        out[#out + 1] = { step = step, at = rk[2], cap = cap, level = rk[3], fee = rk[4], newCap = rk[1] }
      end
    end
  end
  return out
end

-- The tools a route needs (a blacksmith hammer, a runed rod: DATA.tools, key -> { name, { items that count } }).
-- For each, before the first step that needs it: nothing when you have one (o.hasItem) or an earlier step makes one;
-- else make one, with the cheapest recipe of this profession you can learn by then (its own tools first), or buy the
-- cheapest one that has a price (o.price), or, with neither, a "get" step naming the tool. cost(id) prices materials.
function P.toolSteps(steps, recipes, o, cost)
  local out = {}
  if not o.tools then return out end
  local matsOf = o.matsOf or function(r) return r.mats end
  local handled, made = {}, {}
  local function need(key, at, guard)
    if handled[key] or guard > 4 then return end
    handled[key] = true
    local tool = o.tools[key]
    if not tool then return end
    local isItem = {}
    for _, id in ipairs(tool[2]) do
      if made[id] or (o.hasItem and o.hasItem(id)) then return end
      isItem[id] = true
    end
    local best, bestCost
    for _, r in ipairs(recipes) do
      if r.creates and isItem[r.creates] and r.learn <= at and (r.skip == nil or r.skip == "") and learnable(r, o) then
        local c = 0
        for _, m in ipairs(matsOf(r)) do c = c + cost(m[1]).e * m[2] end
        if not bestCost or c < bestCost then best, bestCost = r, c end
      end
    end
    local t = { key = key, name = tool[1], at = at }
    if best then
      for _, k in ipairs(best.tools or {}) do need(k, at, guard + 1) end
      t.kind, t.r, t.item = "make", best, best.creates
    else
      for _, id in ipairs(tool[2]) do
        local pr = o.price and o.price(id)
        if pr and (not t.price or pr < t.price) then t.kind, t.item, t.price = "buy", id, pr end
      end
      if not t.kind then t.kind, t.item = "get", tool[2][1] end
    end
    out[#out + 1] = t
  end
  for _, st in ipairs(steps) do
    for _, key in ipairs(st.r.tools or {}) do need(key, st.from, 0) end
    if st.r.creates and st.r.creates ~= 0 then made[st.r.creates] = true end
  end
  return out
end

--[[ The plan.
o = {
  from, to             skill now and the target (to <= 300)
  side                 "a" or "h"
  known                { [spell] = true }: recipes you know (always usable, nothing to learn)
  price(id)            copper per unit you would pay (vendor, auction house), or nil when unknown
  estimate(id)         copper per unit to choose by when there is no price (never shown in totals); default 1
  patternPrice(r)      what a vendor pattern costs (nil: unknown)
  vendorPatterns       false: leave out recipes that need a vendor pattern
  ahPatterns           true: also recipes whose pattern ahPatternPrice(r) finds on the auction house
  owned                { [id] = n }: materials you have; a second pass counts them as free where they cover the need
  buffer               true: shop for the 90% buffer (n90, P.spreadBuffer) instead of the expected crafts
  choice(id)           "buy" / "craft": the player's pick for a material that can be made (nil: the cheaper way)
  repOk(r)             true when you have the reputation a recipe's vendor pattern asks for
  oneTime              false: ignore pattern and fee costs (the site's route, for the parity tests)
  back(r)              copper one craft reliably gets back (its vendor price, a good that sells): taken off its cost
  worth(r)             copper one craft's product is worth beyond back(r), to choose between two that cost about the same
  matsOf(r)            the reagents of a recipe (the server's, where a profession window showed others)
  ranks, maxSkill      for the rank trainings (P.trainings)
  tools, hasItem(id)   DATA.tools and whether you have an item, for the tool steps (P.toolSteps)
}
returns { steps, stall, trainings, tools = { { key, name, at, kind = make|buy|get, r, item, price } },
  shop = { raw = { { id, n, price } }, crafted = { { id, n, crafts, via } } },
  totals = { mats, matsUnpriced, patterns, patternsUnknown, fees, feesUnknown, total }, estimated }
]]
function P.plan(recipes, o)
  local matsOf = o.matsOf or function(r) return r.mats end
  o.matsOf = matsOf
  local function makeBase(free)
    return function(id)
      if free and free[id] then return { e = 0, gold = 0 } end
      local pr = o.price and o.price(id)
      if pr then return { e = pr, gold = pr } end
      local est = o.estimate and o.estimate(id) or 1
      return { e = est, gold = est, est = true }
    end
  end
  local function best(base)
    local excluded = {}
    local res = route(recipes, o, excluded, base)
    if o.oneTime == false then return res end
    local reach = function(r) return r.stall or o.to end
    for _ = 1, 12 do
      local tried, improved = {}, false
      local cands = {}
      for _, st in ipairs(res.steps) do
        if (st.once or 0) > 0 and not tried[st.r] then tried[st.r] = true; cands[#cands + 1] = st end
      end
      table.sort(cands, function(x, y) return x.once > y.once end)
      for _, st in ipairs(cands) do
        excluded[st.r] = true
        local alt = route(recipes, o, excluded, base)
        -- never at the price of more yellow or green points (reliable skill-ups come before gold), unless the route
        -- then costs less than 1 / ORANGE_WORTH of the other; more green points never
        local asReliable = alt.points.green <= res.points.green
          and alt.points.green + alt.points.yellow <= res.points.green + res.points.yellow
        if reach(alt) >= reach(res) and alt.total < res.total - 1 and (asReliable
          or (alt.points.green <= res.points.green and alt.total * P.ORANGE_WORTH < res.total)) then
          res, improved = alt, true
          break
        end
        excluded[st.r] = nil
      end
      if not improved then break end
    end
    return res
  end
  local count = function(st) return o.buffer and st.n90 or st.n end
  local res = best(makeBase(nil))
  P.spreadBuffer(res.steps)
  -- second pass: materials you already have enough of cost nothing
  if o.owned then
    local raw = P.shopping(res, matsOf, count)
    local free, any = {}, false
    for _, x in ipairs(raw) do
      if (o.owned[x.id] or 0) >= x.n then free[x.id], any = true, true end
    end
    if any then res = best(makeBase(free)); P.spreadBuffer(res.steps) end
  end
  local raw, crafted = P.shopping(res, matsOf, count)
  -- the tools: one craft's materials, or the tool itself, join the shopping list
  local tools = P.toolSteps(res.steps, recipes, o, res.cost)
  local function add(id, n)
    for _, x in ipairs(raw) do if x.id == id then x.n = x.n + n return end end
    raw[#raw + 1] = { id = id, n = n }
  end
  for _, tl in ipairs(tools) do
    if tl.kind == "make" then
      for _, m in ipairs(matsOf(tl.r)) do add(m[1], m[2]) end
    elseif tl.kind == "buy" then
      add(tl.item, 1)
    end
  end
  table.sort(raw, function(x, y) return x.id < y.id end)
  local t = { mats = 0, matsUnpriced = 0, patterns = 0, patternsUnknown = 0, fees = 0, feesUnknown = 0 }
  local estimated = false
  for _, x in ipairs(raw) do
    local need = x.n - math.min(x.n, o.owned and o.owned[x.id] or 0)
    x.need = need
    x.price = o.price and o.price(x.id) or nil
    if need > 0 then
      if x.price then t.mats = t.mats + need * x.price else t.matsUnpriced = t.matsUnpriced + 1 end
    end
  end
  local seen = {}
  for _, st in ipairs(res.steps) do
    if st.est then estimated = true end
    local r = st.r
    if seen[r] then st.again = true end
    if not seen[r] and not (o.known and o.known[r.spell]) then
      seen[r] = true
      local pattern = r.item and r.item ~= 0 and not r.trained and not r.auto
      if pattern then
        local pr = (r.tier[o.side] or 9) <= P.MAIN_TIER and o.patternPrice and o.patternPrice(r)
          or repPattern(r, o) or (o.ahPatternPrice and o.ahPatternPrice(r))
        if repPattern(r, o) then st.rep = true end
        st.patternPrice = pr
        if pr then t.patterns = t.patterns + pr else t.patternsUnknown = t.patternsUnknown + 1 end
      elseif r.trained or r.fee then
        st.fee = r.fee
        if r.fee then t.fees = t.fees + r.fee else t.feesUnknown = t.feesUnknown + 1 end
      end
    end
  end
  local trainings = P.trainings(o.ranks, o.from, o.to, o.maxSkill)
  for _, tr in ipairs(trainings) do
    if tr.fee then t.fees = t.fees + tr.fee else t.feesUnknown = t.feesUnknown + 1 end
  end
  t.total = t.mats + t.patterns + t.fees
  return { steps = res.steps, stall = res.stall, trainings = trainings, tools = tools, shop = { raw = raw, crafted = crafted },
    totals = t, estimated = estimated, from = o.from, to = o.to }
end

return P
