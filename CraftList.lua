-- The Crafting list: what you plan to craft, account wide (EverlookCraftDB.list, this PC only). Each entry is a recipe
-- and how many times to craft it. The material tree breaks every recipe into its materials and, for a material one of
-- your characters can make (a bolt, a bar), into that recipe's materials, unless you tick it to buy. What you own on
-- every character is shared out in list order, so a stack counts once. A recipe that would feed itself (a transmute
-- loop) is cut. Vendor goods are marked, with the nearest vendor; the rest of what is missing can go to EverlookDB
-- Auctions' shopping list (vendor goods stay off it). Each craft of a listed recipe takes one off its count.
local _, ns = ...
local try, plain = ns.try, ns.plain

local L = {}
ns.craftList = L

local MAX_DEPTH = 6

local function db() return EverlookCraftDB end

function L.entries()
  local d = db()
  if not d then return {} end
  d.list = d.list or {}
  return d.list
end

-- the entry of a spell (its own or a twin's), its index
function L.find(spell)
  local r = ns.recipeBySpell(spell)
  local key = r and r.spell or spell
  for i, e in ipairs(L.entries()) do
    if e.spell == key then return e, i end
  end
end

-- add n crafts of a recipe (an entry that is there already grows); false when the data has no such recipe
function L.add(spell, n)
  local r = type(spell) == "number" and ns.recipeBySpell(spell)
  if not r or not db() then return false end
  n = math.max(1, math.floor(tonumber(n) or 1))
  local e = L.find(r.spell)
  if e then e.n = e.n + n else table.insert(L.entries(), { spell = r.spell, n = n }) end
  if ns.onList then ns.onList() end
  return true, r
end

-- set the count; 0 or less takes the recipe off the list
function L.set(spell, n)
  local e, i = L.find(spell)
  if not e then return false end
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then table.remove(L.entries(), i) else e.n = n end
  if ns.onList then ns.onList() end
  return true
end

function L.remove(spell) return L.set(spell, 0) end

function L.clear()
  if db() then db().list = {} end
  if ns.onList then ns.onList() end
end

---------------------------------------------------------------------------------------------------------------------
-- Who makes what

local makersCache
-- every recipe in the data that makes an item: { [item] = { recipe, ... } }
local function makersIndex()
  if makersCache then return makersCache end
  makersCache = {}
  for _, p in ipairs(ns.professionList()) do
    for _, r in ipairs(ns.recipes(p.id) or {}) do
      if r.creates and r.creates ~= 0 then
        local t = makersCache[r.creates] or {}
        t[#t + 1] = r
        makersCache[r.creates] = t
      end
    end
  end
  return makersCache
end

-- the recipes that make an item, those your characters know first, then by learn skill
function L.makers(item)
  local list = makersIndex()[item]
  if not list then return {} end
  local out = {}
  for _, r in ipairs(list) do out[#out + 1] = { r = r, by = ns.scan.knownBy(r.spell) } end
  table.sort(out, function(x, y)
    if (#x.by > 0) ~= (#y.by > 0) then return #x.by > 0 end
    if x.r.learn ~= y.r.learn then return x.r.learn < y.r.learn end
    return x.r.spell < y.r.spell
  end)
  return out
end

-- the recipe one of your characters knows that makes an item, and who knows it
function L.knownMaker(item)
  local m = L.makers(item)[1]
  if m and #m.by > 0 then return m.r, m.by end
end

-- craft or buy a material you can make: what you ticked, else craft (buy for goods a vendor sells)
function L.mode(item)
  local pick = db() and db().craftBuy and db().craftBuy[item]
  if pick then return pick end
  if ns.prices.vendor(item) then return "buy" end
  return "craft"
end

function L.setMode(item, mode)
  local d = db()
  if not d then return end
  d.craftBuy = d.craftBuy or {}
  d.craftBuy[item] = (mode == "buy" or mode == "craft") and mode or nil
  if ns.onList then ns.onList() end
end

---------------------------------------------------------------------------------------------------------------------
-- The material tree

-- where you have an item: "4 in bags, 10 in bank, 30 on Bankalt" (other characters left out with "don't count
-- my alts' materials" on)
function L.whereText(id)
  local h = ns.stock.have(id)
  local parts = {}
  if h.bags > 0 then parts[#parts + 1] = h.bags .. " in bags" end
  if h.bank > 0 then parts[#parts + 1] = h.bank .. " in bank" end
  if (h.mail or 0) > 0 then parts[#parts + 1] = h.mail .. " in the mail" end
  if not ns.settings().noAlts then
    for i, c in ipairs(h.byChar) do
      if i > 2 then parts[#parts + 1] = ("%d on %d more"):format(h.alts - (h.byChar[1].n + h.byChar[2].n), #h.byChar - 2) break end
      parts[#parts + 1] = ("%d on %s"):format(c.n, c.name)
    end
  end
  return table.concat(parts, ", ")
end

-- The tree of the whole list:
--   roots = { { spell, r, n (crafts), makes, kids = { node } } }
--   node = { id, need, have (counted for this row), short, depth, mode ("craft" | "buy"), via (recipe), by (who knows
--            it), crafts, vendor (a vendor sells it), cut (a loop was cut here), kids }
--   rows = the same nodes flat, in the order a window shows them (a root, then its materials, depth first)
--   totals = { [item] = { need, have, short } } for the materials you buy (leaves), missing = { { id, n, vendor } }
function L.tree()
  local pool = {}
  local function avail(id)
    if pool[id] == nil then pool[id] = ns.stock.usable(id) end
    return pool[id]
  end
  local out = { roots = {}, rows = {}, totals = {}, missing = {} }

  local function node(id, need, depth, path)
    local n = { id = id, need = need, depth = depth }
    local a = avail(id)
    n.have = math.min(a, need)
    pool[id] = a - n.have
    n.short = need - n.have
    n.vendor = ns.prices.where(id) == "vendor"
    local r, by = L.knownMaker(id)
    n.by = by
    n.mode = "buy"
    if r then
      n.via = r
      if path[r.spell] or depth >= MAX_DEPTH then
        n.cut = true
      else
        n.mode = L.mode(id)
      end
    end
    out.rows[#out.rows + 1] = n
    if n.mode == "craft" and n.short > 0 then
      n.crafts = math.ceil(n.short / (r.yield or 1) - 1e-6)
      n.kids = {}
      path[r.spell] = true
      for _, m in ipairs((ns.matsOf(r))) do n.kids[#n.kids + 1] = node(m[1], n.crafts * m[2], depth + 1, path) end
      path[r.spell] = nil
    else
      local t = out.totals[id] or { need = 0, have = 0, short = 0, vendor = n.vendor }
      t.need, t.have, t.short = t.need + need, t.have + n.have, t.short + n.short
      out.totals[id] = t
    end
    return n
  end

  for _, e in ipairs(L.entries()) do
    local r = ns.recipeBySpell(e.spell)
    if r then
      local root = { spell = r.spell, r = r, n = e.n, makes = e.n * (r.yield or 1), kids = {}, depth = 0, root = true }
      out.roots[#out.roots + 1] = root
      out.rows[#out.rows + 1] = root
      local path = { [r.spell] = true }
      for _, m in ipairs((ns.matsOf(r))) do root.kids[#root.kids + 1] = node(m[1], e.n * m[2], 1, path) end
    end
  end
  for id, t in pairs(out.totals) do
    if t.short > 0 then out.missing[#out.missing + 1] = { id = id, n = t.short, vendor = t.vendor } end
  end
  table.sort(out.missing, function(x, y) return (ns.itemInfo(x.id)) < (ns.itemInfo(y.id)) end)
  return out
end

-- What the missing materials cost: total of the priced ones, how many have no price, and the same for vendor goods
function L.cost(tree)
  local ah, vendor, unpriced = 0, 0, 0
  for _, m in ipairs(tree.missing) do
    local p = ns.prices.unit(m.id)
    if not p then unpriced = unpriced + 1
    elseif m.vendor then vendor = vendor + p * m.n
    else ah = ah + p * m.n end
  end
  return ah, vendor, unpriced
end

-- the missing materials to buy at the auction house: { { itemID, count } } (vendor goods left out)
function L.shoppingItems(tree)
  local items = {}
  for _, m in ipairs((tree or L.tree()).missing) do
    if not m.vendor then items[#items + 1] = { m.id, m.n } end
  end
  return items
end

L.LIST_NAME = "Crafting list"

-- Where a shopping list can go: "EverlookDB Auctions", "Auctionator" or nil
function L.shoppingTarget()
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  if api and (api.version or 0) >= 2 and type(api.addShoppingList) == "function" then return "EverlookDB Auctions" end
  local a = rawget(_G, "Auctionator")
  a = a and a.API and a.API.v1
  if a and type(a.CreateShoppingList) == "function" and type(a.ConvertToSearchString) == "function" then return "Auctionator" end
end

local function nameOf(id)
  local n = plain(try(C_Item and C_Item.GetItemNameByID, id))
  if not n then n = plain(try(C_Item and C_Item.GetItemInfo, id)) or plain(try(GetItemInfo, id)) end
  return type(n) == "string" and n or nil
end

local function toAuctionator(name, items)
  local a = Auctionator.API.v1
  local terms, missing = {}, 0
  for _, it in ipairs(items) do
    local n = nameOf(it[1])
    if n then
      local term = try(a.ConvertToSearchString, "EverlookDBCrafting", { searchString = n, isExact = true, quantity = it[2] })
      if term then terms[#terms + 1] = term end
    else
      missing = missing + 1
    end
  end
  if missing > 0 then return false, "loading" end
  if #terms == 0 then return false, "no items" end
  local ok = pcall(a.CreateShoppingList, "EverlookDBCrafting", name, terms)
  return ok, not ok and "refused" or nil
end

-- Send { { itemID, count } } as the shopping list `name` to EverlookDB Auctions, else Auctionator. true and where,
-- false and why (in words), or nil, "loading" while the game loads item names: then it tries again (up to 5 s) and
-- calls report(ok, where or why) once at the end.
function L.sendList(name, items, report, retry)
  local target = L.shoppingTarget()
  if not target then return false, "EverlookDB Auctions (version with shopping lists) isn't installed, nor Auctionator." end
  if #items == 0 then return false, "nothing to buy at the auction house: you have it all, or only vendor goods are missing." end
  local ok, res, why
  if target == "EverlookDB Auctions" then
    ok, res, why = pcall(EverlookDBAuctionsAPI.addShoppingList, name, items)
    if not ok then return false, "EverlookDB Auctions refused the list." end
  else
    ok, res, why = true, toAuctionator(name, items)
    if res then why = nil end
  end
  if res then return true, target end
  -- the game hasn't loaded every item's name yet: ask for them and try again shortly (only the last try speaks)
  if why == "loading" and (retry or 0) < 5 and C_Timer and C_Timer.After then
    for _, it in ipairs(items) do
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it[1]) end
    end
    C_Timer.After(1, function()
      local ok2, msg = L.sendList(name, items, report, (retry or 0) + 1)
      if ok2 ~= nil and report then report(ok2, msg) end
    end)
    return nil, "loading"
  end
  if why == "loading" then return false, "the game hasn't loaded some item names yet; try again in a moment." end
  return false, tostring(why or "unknown reason")
end

-- Send the missing materials to EverlookDB Auctions' shopping list (else Auctionator's). true, or false and why.
function L.sendToAuctions()
  local items = L.shoppingItems()
  local ok, why = L.sendList(L.LIST_NAME, items, function(ok2, msg)
    ns.print(ok2 and L.sentText(#items, msg) or ("couldn't send the list: " .. tostring(msg)))
  end)
  if ok then return true, why end
  return ok, why
end

function L.sentText(n, where)
  return ("%d materials are on the shopping list \"%s\" in %s (vendor goods left out)."):format(n, L.LIST_NAME, where or "EverlookDB Auctions")
end

---------------------------------------------------------------------------------------------------------------------
-- Each craft of a listed recipe takes one off its count

ns.on("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spell)
  if unit ~= "player" or not db() then return end
  spell = plain(spell)
  if not spell then return end
  local e = L.find(spell)
  if e then L.set(e.spell, e.n - 1) end
end)
