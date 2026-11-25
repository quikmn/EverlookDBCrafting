-- The crafting queue (once the Crafting list): what you plan to craft, account wide (EverlookCraftDB.list, this PC
-- only). EverlookDB Auctions reads and writes it through the API (EverlookCraftAPI v8: its Crafting profit queues here,
-- its Buy materials buys what the whole queue misses). Each entry is a recipe and how many times to craft it, and
-- optionally how many of its item to keep in stock (keep): such an entry's count is what is missing of the item
-- everywhere (bags, bank, mail, alts, your auctions) and refills itself. Each entry has a status (ready, need
-- materials, need skill, on cooldown); QueueButton.lua's "Craft next" crafts the first ready one. The material tree breaks every recipe into its materials and, for a material one of
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

-- the queue changed: this addon's windows, then whoever listens through the API (EverlookDB Auctions)
L.listeners = {}
local function changed()
  if ns.onList then ns.onList() end
  for _, fn in ipairs(L.listeners) do pcall(fn) end
end
L.changed = changed

-- add n crafts of a recipe (an entry that is there already grows; one kept in stock keeps n crafts' more);
-- false when the data has no such recipe
function L.add(spell, n)
  local r = type(spell) == "number" and ns.recipeBySpell(spell)
  if not r or not db() then return false end
  n = math.max(1, math.floor(tonumber(n) or 1))
  local e = L.find(r.spell)
  if e and e.keep then
    e.keep = e.keep + n * (r.yield or 1)
    L.restock()
  elseif e then
    e.n = e.n + n
  else
    table.insert(L.entries(), { spell = r.spell, n = n })
  end
  changed()
  return true, r
end

-- at least n crafts of a recipe (the skill-up route's steps: pressing it again doesn't add them twice)
function L.atLeast(spell, n)
  local r = type(spell) == "number" and ns.recipeBySpell(spell)
  if not r or not db() then return false end
  n = math.max(1, math.floor(tonumber(n) or 1))
  local e = L.find(r.spell)
  if e and e.n >= n then return true, r end
  if e then e.n = n else table.insert(L.entries(), { spell = r.spell, n = n }) end
  changed()
  return true, r
end

-- set the count; 0 or less takes the recipe off the list (one kept in stock stays, at 0, until it is removed)
function L.set(spell, n)
  local e, i = L.find(spell)
  if not e then return false end
  n = math.floor(tonumber(n) or 0)
  if n <= 0 and not e.keep then table.remove(L.entries(), i) else e.n = math.max(0, n) end
  changed()
  return true
end

function L.remove(spell)
  local e, i = L.find(spell)
  if not e then return false end
  table.remove(L.entries(), i)
  changed()
  return true
end

function L.clear()
  if db() then db().list = {} end
  changed()
end

---------------------------------------------------------------------------------------------------------------------
-- Keep N in stock

-- Everything you have of an item, for "keep in stock": bags, bank, mail (and mail on its way), your other characters
-- and your auctions. With EverlookDB Auctions its inventory (it knows mail and auctions), else this addon's count.
function L.stockOf(item)
  local inv = ns.stock.shared()
  if inv then
    local res = try(inv.count, item)
    local n = 0
    for _, c in ipairs(type(res) == "table" and type(res.chars) == "table" and res.chars or {}) do
      n = n + (tonumber(c.bags) or 0) + (tonumber(c.bank) or 0) + (tonumber(c.mail) or 0) + (tonumber(c.listed) or 0)
    end
    return n
  end
  local h = ns.stock.have(item)
  return h.bags + h.bank + (h.mail or 0) + h.alts
end

-- How many of a recipe's item to keep (nil or 0: off). A recipe that isn't queued yet is added. false for a recipe
-- that makes no item (an enchant) or isn't in the data.
function L.setKeep(spell, keep)
  local r = type(spell) == "number" and ns.recipeBySpell(spell)
  if not r or not db() then return false end
  keep = math.floor(tonumber(keep) or 0)
  local e, i = L.find(r.spell)
  if keep <= 0 then
    if e then
      e.keep = nil
      if e.n <= 0 then table.remove(L.entries(), i) end
    end
  else
    if not r.creates or r.creates == 0 then return false end
    if not e then
      e = { spell = r.spell, n = 0 }
      table.insert(L.entries(), e)
    end
    e.keep = keep
    L.restock()
  end
  changed()
  return true, r
end

-- Entries kept in stock: their count is what is missing, in crafts (the item's count over the recipe's yield). true
-- when a count changed. Runs when what you have changes, so a stale count puts itself right on the next read.
function L.restock()
  local moved = false
  for _, e in ipairs(L.entries()) do
    local r = e.keep and ns.recipeBySpell(e.spell)
    if r and r.creates and r.creates ~= 0 then
      local want = math.max(0, math.ceil((e.keep - L.stockOf(r.creates)) / (r.yield or 1) - 1e-6))
      if want ~= e.n then e.n, moved = want, true end
    end
  end
  return moved
end

---------------------------------------------------------------------------------------------------------------------
-- Status: ready, need materials, need skill, on cooldown

-- how many of an item are in your bags right now (the game's count, else this addon's last one)
local function bagCount(id)
  local f = (C_Item and C_Item.GetItemCount) or rawget(_G, "GetItemCount")
  local n = tonumber(plain(try(f, id)))
  if n then return n end
  return ns.stock.have(id).bags or 0
end
L.bagCount = bagCount

-- how many crafts the materials in your bags allow now
function L.canNow(r)
  local can = math.huge
  for _, m in ipairs((ns.matsOf(r))) do can = math.min(can, math.floor(bagCount(m[1]) / math.max(1, m[2] or 1))) end
  if can == math.huge then return 0 end
  return can
end

-- the recipe ID the profession window uses for it (a twin's, when the window listed that one)
function L.castID(r)
  local me = ns.me()
  local p = me and me.profs[r.skill]
  return p and type(p.ids) == "table" and p.ids[r.spell] or r.spell
end

function L.knowsMe(r)
  local me = ns.me()
  local p = me and me.profs[r.skill]
  return (p and p.known and p.known[r.spell]) and true or false
end

-- seconds left of a recipe's own cooldown (a transmute, Mooncloth), or nil; the global cooldown doesn't count, and a
-- cooldown the game hides (a secret value) counts as none
function L.cooldown(r)
  local id = L.castID(r)
  local start, dur
  local cd = C_Spell and C_Spell.GetSpellCooldown and try(C_Spell.GetSpellCooldown, id)
  if type(cd) == "table" then
    start, dur = plain(cd.startTime), plain(cd.duration)
  elseif rawget(_G, "GetSpellCooldown") then
    start, dur = try(GetSpellCooldown, id)
    start, dur = plain(start), plain(dur)
  end
  if type(start) ~= "number" or type(dur) ~= "number" or start <= 0 or dur <= 2 then return nil end
  local left = start + dur - ((GetTime and GetTime()) or 0)
  return left > 0 and left or nil
end

local function timeText(sec)
  if sec >= 86400 then return math.floor(sec / 86400 + 0.5) .. " d" end
  if sec >= 3600 then return math.floor(sec / 3600 + 0.5) .. " h" end
  return math.max(1, math.floor(sec / 60 + 0.5)) .. " min"
end

-- An entry's status: { key = "ready" | "materials" | "skill" | "cooldown" | "stocked", text, can (crafts now) }
function L.status(e, r)
  r = r or ns.recipeBySpell(e.spell)
  if not r then return { key = "skill", text = "not in the recipe data" } end
  if e.n <= 0 then
    return { key = "stocked", text = e.keep and ("in stock: %d of %d"):format(L.stockOf(r.creates), e.keep) or "done" }
  end
  if not L.knowsMe(r) then
    local by = ns.scan.knownBy(r.spell)
    local me = ns.me()
    local rank = me and me.profs[r.skill] and me.profs[r.skill].rank
    local text
    if #by > 0 then text = ("need skill: %s knows it"):format(by[1])
    elseif rank and r.learn and rank < r.learn then text = ("need skill: %s %d (you have %d)"):format(ns.profName(r.skill), r.learn, rank)
    else text = "need skill: you don't know it yet" end
    return { key = "skill", text = text, by = by }
  end
  local left = L.cooldown(r)
  if left then return { key = "cooldown", text = "on cooldown, " .. timeText(left), left = left } end
  local can = L.canNow(r)
  if can <= 0 then return { key = "materials", text = "need materials" } end
  can = math.min(can, e.n)
  return { key = "ready", text = can >= e.n and "ready" or ("ready: %d now"):format(can), can = can }
end

-- The next entry to craft, top to bottom: the first one ready (you know it, its materials are in your bags, no
-- cooldown) that makes an item, of profession skill when given. Returns entry, recipe, crafts (as many as the bags allow, up to its
-- count) and how many were skipped for want of materials.
function L.next(skill)
  local skipped = 0
  for _, e in ipairs(L.entries()) do
    local r = e.n > 0 and ns.recipeBySpell(e.spell)
    -- an enchant (it makes no item) needs an item to put it on: that one is cast by hand
    if r and r.creates and r.creates ~= 0 and (not skill or r.skill == skill) then
      local st = L.status(e, r)
      if st.key == "ready" then return e, r, st.can, skipped end
      if st.key == "materials" then skipped = skipped + 1 end
    end
  end
  return nil, nil, 0, skipped
end

-- What one craft earns at the auction house after its 5% cut, minus what the materials cost (the cheaper of vendor and
-- auction house for each); nil when the item or a material has no price.
function L.profitEach(r)
  if not r or not r.creates or r.creates == 0 then return nil end
  local sale = ns.prices.ah(r.creates)
  if not sale then return nil end
  local cost = 0
  for _, m in ipairs((ns.matsOf(r))) do
    local p = ns.prices.unit(m[1])
    if not p then return nil end
    cost = cost + p * m[2]
  end
  return math.floor(sale * (r.yield or 1) * 0.95 + 0.5) - cost
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

L.LIST_NAME = "Crafting queue"

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
-- Each craft of a queued recipe takes one off its count (a spell ID the game hides is skipped). An entry kept in stock
-- is counted again from your items once they change (bags, bank, mail, auctions).

ns.on("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spell)
  if unit ~= "player" or not db() then return end
  spell = plain(spell)
  if type(spell) ~= "number" then return end
  local e = L.find(spell)
  if e and e.n > 0 then L.set(e.spell, e.n - 1) end
end)

local prevStock = ns.onStock
ns.onStock = function()
  if prevStock then prevStock() end
  if db() and L.restock() then changed() end
end
ns.on("PLAYER_ENTERING_WORLD", function()
  if db() and C_Timer and C_Timer.After then C_Timer.After(4, function() if L.restock() then changed() end end) end
end)
