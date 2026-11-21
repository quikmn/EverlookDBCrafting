-- Merchant's Favor: which Waylaid Crate gives the most Favor for the least gold. Pure Lua over the data and the price
-- and stock modules, so the tests run it offline.
--
-- A Waylaid Crate lists several bundles ("20 Peacebloom", "20 Silverleaf", ...); you fill it with ONE of them, and the
-- Sealed Crate goes to your faction's Inventory Intake clerk (Marcy Baker, Three Corners; Dokimi, west of the
-- Crossroads) for Merchant's Favor and a little money. So a crate costs:
--   the crate: its auction house price (crates aren't bound), free when you have one and "count my bags as free" is on
--   + the cheapest ONE bundle: per item the cheaper of buying it (vendor, then the auction house) or crafting it with a
--     recipe one of your characters knows (the planner's craft-or-buy costing), times the count. With "count my bags
--     as free" on, what you have on your characters (Stock.lua's rules, alts unless "don't count my alts") is free.
-- Prices come from EverlookDB Auctions, else Auctionator; nothing is guessed. A crate whose Favor or a price is
-- unknown sorts last and says why. The data (Data.lua's crates): the client (bundles, level), AllTheThings (Sealed
-- Crate, turn-in quest, Favor), EG Link (money; reputation: none seen on crate turn-ins).
local _, ns = ...

local F = {}
ns.favor = F

F.TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan" }
F.LIST_NAME = "Merchant's Favor"
-- each crate has its own list ("Favor: Apprentice Textiles"), so making one doesn't replace another
function F.listName(res)
  local name = res and res.c and ns.itemInfo(res.c.id)
  name = type(name) == "string" and name:gsub("^Waylaid Crate: ", "") or nil
  return name and name ~= "" and ("Favor: " .. name) or F.LIST_NAME
end
local INF = math.huge

ns.DEFAULTS.settings.favorBagsFree = false  -- materials and crates you have cost nothing
ns.DEFAULTS.settings.favorMyLevel = true    -- only crates your level can open
ns.DEFAULTS.settings.favorTier = 0          -- 0 all, else 1..4
ns.DEFAULTS.settings.favorSide = nil        -- "a" / "h"; nil: yours

local cratesCache
-- every crate in the data: { id, tier, crafted, level, sealed, quest, favor (nil unknown), money (nil unknown),
-- rep (nil unknown), bundles = { { id, n } } }
function F.crates()
  if cratesCache then return cratesCache end
  local out = {}
  for id, c in pairs(ns.DATA and ns.DATA.crates or {}) do
    local b = {}
    for i = 1, #c[9], 2 do b[#b + 1] = { id = c[9][i], n = c[9][i + 1] } end
    out[#out + 1] = { id = id, tier = c[1], crafted = c[2] == 1, level = c[3], sealed = c[4], quest = c[5],
      favor = c[6] > 0 and c[6] or nil, money = c[7] >= 0 and c[7] or nil, rep = c[8] >= 0 and c[8] or nil, bundles = b }
  end
  table.sort(out, function(x, y) return x.id < y.id end)
  out.byId = {}
  for _, c in ipairs(out) do out.byId[c.id] = c end
  cratesCache = out
  return out
end

function F.crate(id) return F.crates().byId[id] end

function F.tierName(c) return F.TIERS[c.tier] or "?" end

---------------------------------------------------------------------------------------------------------------------
-- What one unit costs: the cheaper of buying and crafting (a recipe one of your characters knows)

-- the recipes your characters know (any of them), as the planner's pool
local function knownPool()
  local spells = {}
  for _, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do
    for _, p in pairs(c.profs or {}) do
      for s, on in pairs(p.known or {}) do if on then spells[s] = true end end
    end
  end
  local pool = {}
  for _, p in ipairs(ns.professionList()) do
    local rs = ns.recipes(p.id) or {}
    for _, r in ipairs(rs) do
      if spells[r.spell] then pool[#pool + 1] = r end
    end
    for twin, spell in pairs((ns.DATA.profs[p.id] or {}).alias or {}) do
      if spells[twin] and rs.bySpell[spell] then pool[#pool + 1] = rs.bySpell[spell] end
    end
  end
  return pool
end

-- unitCost(id) -> copper or nil, how ("vendor" | "ah" | "craft"), the recipe when crafted
function F.unitCoster()
  local cost = ns.planner.costing(knownPool(), function(id)
    local p = ns.prices.unit(id)
    return { e = p or INF, gold = p or INF, est = p == nil }
  end, function(r) return (ns.matsOf(r)) end)
  return function(id)
    local x = cost(id)
    if not x or x.e == INF then return nil end
    if x.via then return x.e, "craft", x.via end
    local _, how = ns.prices.unit(id)
    return x.e, how
  end
end

---------------------------------------------------------------------------------------------------------------------
-- One crate: the cost of each bundle, the cheapest, and the gold per Favor

local function have(id) return ns.stock.usable(id) end

-- o = { bagsFree, unit (a unitCoster) }. Returns
--   { c, crate = { cost, how ("ah" | "owned"), have }, options = { { id, n, unit, how, via, have, buy, cost } } (cheapest
--     first, unpriced last), best (options[1] when priced), total, perFavor, perRep, why (nil when ranked) }
function F.evaluate(c, o)
  o = o or {}
  local unit = o.unit or F.unitCoster()
  local free = o.bagsFree
  local res = { c = c, options = {} }
  for _, b in ipairs(c.bundles) do
    local u, how, via = unit(b.id)
    local h = math.min(have(b.id), b.n)
    local buy = free and (b.n - h) or b.n
    local opt = { id = b.id, n = b.n, unit = u, how = how, via = via, have = h, buy = buy }
    if buy == 0 then opt.cost = 0 elseif u then opt.cost = u * buy end
    res.options[#res.options + 1] = opt
  end
  table.sort(res.options, function(x, y)
    if (x.cost ~= nil) ~= (y.cost ~= nil) then return x.cost ~= nil end
    if x.cost and x.cost ~= y.cost then return x.cost < y.cost end
    return x.id < y.id
  end)
  res.best = res.options[1] and res.options[1].cost and res.options[1] or nil
  -- the crate itself
  local hc = have(c.id)
  local ah = ns.prices.ah(c.id)
  if free and hc > 0 then res.crate = { cost = 0, how = "owned", have = hc }
  elseif ah then res.crate = { cost = ah, how = "ah", have = hc }
  elseif hc > 0 then res.crate = { cost = 0, how = "owned", have = hc }  -- yours, and no price to count it at
  else res.crate = { have = 0 } end
  if not c.favor then
    res.why = ("its Merchant's Favor isn't known yet (%s crates)"):format(F.tierName(c))
  elseif not res.best then
    res.why = "no price for any bundle"
  elseif not res.crate.cost then
    res.why = "the crate isn't on the auction house (it drops from monsters level 10 and up)"
  end
  if res.best and res.crate.cost then
    res.total = res.best.cost + res.crate.cost
    if c.favor then res.perFavor = res.total / c.favor end
    if c.rep and c.rep > 0 then res.perRep = res.total / c.rep end
  end
  return res
end

-- Every crate that passes the filters, ranked by gold per Favor; the ones that can't be ranked last, saying why.
-- o = { bagsFree, level (nil: any), tier (0/nil: all) }
function F.rank(o)
  o = o or {}
  local unit = F.unitCoster()
  local out = {}
  for _, c in ipairs(F.crates()) do
    if (not o.level or c.level <= o.level) and (not o.tier or o.tier == 0 or c.tier == o.tier) then
      out[#out + 1] = F.evaluate(c, { bagsFree = o.bagsFree, unit = unit })
    end
  end
  -- o.sort: "per" (gold per Favor, the default) or "total" (the cheapest crate plus fill, for a little Favor fast)
  local key = o.sort == "total" and "total" or "perFavor"
  table.sort(out, function(x, y)
    if (x.perFavor ~= nil) ~= (y.perFavor ~= nil) then return x.perFavor ~= nil end
    if x[key] and x[key] ~= y[key] then return x[key] < y[key] end
    if x.perFavor and x.perFavor ~= y.perFavor then return x.perFavor < y.perFavor end
    if x.c.tier ~= y.c.tier then return x.c.tier < y.c.tier end
    return x.c.id < y.c.id
  end)
  return out
end

-- the ranking with the saved filters
function F.current()
  local s = ns.settings()
  local level = s.favorMyLevel and (ns.plain(ns.try(UnitLevel, "player")) or nil) or nil
  return F.rank({ bagsFree = s.favorBagsFree, level = level, tier = s.favorTier, sort = s.favorSort })
end

function F.side() return ns.settings().favorSide or ns.side() end

-- the turn-in NPC of a side
function F.npc(side)
  local t = ns.DATA and ns.DATA.trade
  return t and t.npc[side or F.side()]
end

---------------------------------------------------------------------------------------------------------------------
-- Words

-- "20 Peacebloom"
function F.optionName(opt) return ("%d %s"):format(opt.n, (ns.itemInfo(opt.id))) end

-- how an option is paid: "auction house", "vendor", "craft: Bolt of Linen Cloth", "you have them"
function F.howText(opt)
  if opt.buy == 0 then return "you have them" end
  if opt.how == "craft" then return "craft: " .. opt.via.name end
  if opt.how == "vendor" then return "vendor" end
  if opt.how == "ah" then return "auction house" end
  return "no price"
end

-- "~1s 20c per Favor" or the reason it can't be ranked
function F.perFavorText(res, plainText)
  if res.perFavor then return "~" .. ns.money(res.perFavor, plainText) .. " per Favor" end
  return nil
end

---------------------------------------------------------------------------------------------------------------------
-- What to do with the cheapest bundle: what to buy (the crate when it is on the auction house, the bundle's items, or
-- the materials of the recipe that crafts it) and what to craft

-- { { itemID, count } } for the auction house (vendor goods left out), minus what you already have on your characters
-- (whatever "count my bags as free" says: that switch is about the ranking, a shopping list never buys what you have)
function F.shoppingItems(res)
  local items, add = {}, {}
  local function put(id, n)
    if n <= 0 then return end
    if add[id] then add[id][2] = add[id][2] + n return end
    add[id] = { id, n }
    items[#items + 1] = add[id]
  end
  -- no priced fill: nothing to shop for (a crate on its own fills nothing)
  local b = res.best
  if not b then return items end
  if res.crate and res.crate.how == "ah" and (res.crate.have or 0) == 0 then put(res.c.id, 1) end
  local short = b.n - math.min(have(b.id), b.n)
  if short > 0 then
    if b.how == "craft" then
      local crafts = math.ceil(short / (b.via.yield or 1) - 1e-6)
      for _, m in ipairs((ns.matsOf(b.via))) do
        if not ns.prices.vendor(m[1]) then
          local need = crafts * m[2]
          put(m[1], need - math.min(have(m[1]), need))
        end
      end
    elseif b.how == "ah" then
      put(b.id, short)
    end
  end
  return items
end

function F.craftNeed(res)
  local b = res.best
  if not b or b.how ~= "craft" or b.buy <= 0 then return nil end
  return b.via, math.ceil(b.buy / (b.via.yield or 1) - 1e-6)
end

function F.addToList(res)
  local r, n = F.craftNeed(res)
  if not r then return false, "the cheapest bundle is bought, not crafted." end
  ns.craftList.add(r.spell, n)
  return true, ("%s: %d on the Crafting list."):format(r.name, (ns.craftList.find(r.spell) or { n = n }).n)
end

-- Send what to buy for a crate to EverlookDB Auctions' shopping list "Merchant's Favor". true, or false and why.
function F.sendToAuctions(res, retry)
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  if not api or (api.version or 0) < 2 or type(api.addShoppingList) ~= "function" then
    return false, "EverlookDB Auctions (version with shopping lists) isn't installed."
  end
  if not res then return false, "pick a crate first." end
  local items = F.shoppingItems(res)
  if #items == 0 then return false, "nothing to buy at the auction house for this crate." end
  local listName = F.listName(res)
  local ok, done, why = pcall(api.addShoppingList, listName, items)
  if not ok then return false, "EverlookDB Auctions refused the list." end
  if done then return true, ("%d items are on the shopping list \"%s\" in EverlookDB Auctions."):format(#items, listName) end
  -- the game hasn't loaded every item's name yet (a crate you've never had): ask for them and try again shortly
  if why == "loading" and (retry or 0) < 5 and C_Timer and C_Timer.After then
    for _, it in ipairs(items) do
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it[1]) end
    end
    C_Timer.After(1, function()
      local ok2, msg = F.sendToAuctions(res, (retry or 0) + 1)
      if ok2 ~= nil then ns.print(ok2 and msg or ("couldn't make the list: " .. tostring(msg))) end
    end)
    return nil, "loading"
  end
  if why == "loading" then return false, "the game hasn't loaded some item names yet; try again in a moment." end
  return false, tostring(why or "unknown reason")
end

---------------------------------------------------------------------------------------------------------------------
-- The tooltip line on a crate: "Merchant's Favor  5, ~1s 20c per Favor" (worked out at most once a second)

local tipCache, tipAt = {}, nil
function F.tipInfo(id)
  local c = F.crate(id)
  if not c then return nil end
  local now = ns.plain(ns.try(GetTime)) or 0
  if not tipAt or now - tipAt >= 1 then tipCache, tipAt = {}, now end
  if tipCache[id] == nil then
    tipCache[id] = F.evaluate(c, { bagsFree = ns.settings().favorBagsFree })
  end
  return tipCache[id]
end

function F.tipLines(t, id)
  if ns.settings().tipFavor == false then return end
  local res = F.tipInfo(id)
  if not res then return end
  local c = res.c
  local value = c.favor and tostring(c.favor) or "unknown"
  if res.perFavor then value = value .. ", " .. F.perFavorText(res) end
  t:Line("Merchant's Favor", value, { note = F.tierName(c) .. (c.crafted and ", crafted" or ", gathered") })
  if res.best then t:Detail("Cheapest fill", F.optionName(res.best) .. "  " .. ns.money(res.best.cost)) end
  if res.why then t:Detail("No gold per Favor", res.why) end
end
ns.DEFAULTS.settings.tipFavor = true

function F.reset() cratesCache = nil end
