-- Stock across your characters: what each one has in its bags (the reagent bag too) and, from its last bank visit, in
-- its bank and reagent bank. Kept per character in EverlookCraftDB (this PC only, never uploaded). Bags are counted
-- again 2 seconds after they change; the bank while it is open.
-- With EverlookDB Auctions (API v7) loaded, its inventory is the one store for every EverlookDB addon: it also knows
-- each character's mail (and mail on its way from another of yours), auctions and guild bank. Then this file reads
-- from there (mail counts as having it) and doesn't count by itself; without it, everything works as before.
local _, ns = ...
local try, plain = ns.try, ns.plain

local St = {}
ns.stock = St

-- EverlookDB Auctions' inventory (EverlookDBAuctionsAPI.inventory), or nil
function St.shared()
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  if not api or (tonumber(api.version) or 0) < 7 then return nil end
  local inv = api.inventory
  return type(inv) == "table" and type(inv.count) == "function" and inv or nil
end

local BAGS = { 0, 1, 2, 3, 4, 5 }                         -- backpack, four bags, the reagent bag
local BANK = { -1, 6, 7, 8, 9, 10, 11, 12, -3 }           -- bank, bank bags, reagent bank

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return plain(try(C_Container.GetContainerNumSlots, bag)) or 0 end
  return plain(try(GetContainerNumSlots, bag)) or 0
end

local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = try(C_Container.GetContainerItemInfo, bag, slot)
    if info then return plain(info.itemID), plain(info.stackCount) end
    return nil
  end
  local _, count, _, _, _, _, _, _, _, id = try(GetContainerItemInfo, bag, slot)
  return plain(id), plain(count)
end

function St.count(bags)
  local out = {}
  for _, bag in ipairs(bags) do
    for slot = 1, numSlots(bag) do
      local id, n = slotItem(bag, slot)
      if id then out[id] = (out[id] or 0) + (n or 1) end
    end
  end
  return out
end

function St.readBags()
  if St.shared() then return end
  local me = ns.me()
  if not me then return end
  me.bags, me.bagsAt = St.count(BAGS), time()
  if ns.onStock then ns.onStock() end
end

function St.readBank()
  if St.shared() then return end
  local me = ns.me()
  if not me then return end
  me.bank, me.bankAt = St.count(BANK), time()
  if ns.onStock then ns.onStock() end
end

-- How many of an item: { bags, bank, mail (this character), alts (your others on this realm or a connected one, same
-- faction: mail crosses neither realms nor factions, so those characters don't count), byChar = { { name, n } } }.
-- mail is only known with EverlookDB Auctions.
function St.have(id)
  local inv = St.shared()
  if inv then
    local r = try(inv.count, id)
    local res = { bags = 0, bank = 0, mail = 0, alts = 0, byChar = {} }
    for _, e in ipairs(type(r) == "table" and r.chars or {}) do
      if e.me then
        res.bags, res.bank, res.mail = e.bags or 0, e.bank or 0, e.mail or 0
      else
        local n = (e.bags or 0) + (e.bank or 0) + (e.mail or 0)
        if n > 0 then
          res.alts = res.alts + n
          res.byChar[#res.byChar + 1] = { name = e.name or "?", n = n }
        end
      end
    end
    table.sort(res.byChar, function(x, y) return x.n > y.n end)
    return res
  end
  local db = EverlookCraftDB
  local guid, realms = ns.guid(), ns.mailRealms()
  local res = { bags = 0, bank = 0, mail = 0, alts = 0, byChar = {} }
  for g, c in pairs(db and db.chars or {}) do
    local b, k = (c.bags or {})[id] or 0, (c.bank or {})[id] or 0
    if g == guid then
      res.bags, res.bank = b, k
    elseif b + k > 0 and ns.canMail(c, realms) then
      res.alts = res.alts + b + k
      res.byChar[#res.byChar + 1] = { name = c.name or "?", n = b + k }
    end
  end
  table.sort(res.byChar, function(x, y) return x.n > y.n end)
  return res
end

-- the amount that counts for planning: bags and bank, plus your alts' unless "don't count my alts" is on
function St.usable(id)
  local h = St.have(id)
  return h.bags + h.bank + (h.mail or 0) + (ns.settings().noAlts and 0 or h.alts)
end

-- What counts as "have" on a skill-up route: St.usable, or with "Buy everything for the route" (noOwn) only your
-- bags, where what you buy lands (nothing you already had is planned in, but what you buy now ticks off).
function St.forRoute(id)
  if ns.settings().noOwn then return St.have(id).bags end
  return St.usable(id)
end

-- every item you have, for the planner: { [id] = n } (your alts on this realm or a connected one, as St.have);
-- empty with "Buy everything for the route" on
function St.owned()
  local out = {}
  if ns.settings().noOwn then return out end
  local inv = St.shared()
  if inv then
    local t = try(inv.owned, not ns.settings().noAlts)
    return type(t) == "table" and t or out
  end
  local guid, noAlts, realms = ns.guid(), ns.settings().noAlts, ns.mailRealms()
  for g, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do
    if g == guid or (not noAlts and ns.canMail(c, realms)) then
      for _, t in ipairs({ c.bags or {}, c.bank or {} }) do
        for id, n in pairs(t) do out[id] = (out[id] or 0) + n end
      end
    end
  end
  return out
end

-- What a character had in its bags when last seen ({ [item] = n }, a copy), for Crafting profit's "can make it now".
function St.bagsOf(c)
  if type(c) ~= "table" then return nil end
  local inv = St.shared()
  if inv and c.name then
    local b = try(inv.bagsOf, c.name, c.realmID)
    if type(b) == "table" then return b end
  end
  local out = {}
  for id, n in pairs(type(c.bags) == "table" and c.bags or {}) do out[id] = n end
  return out
end

-- What one character carries, for the Characters list: { bags, bank, bankAt, seenAt, shared }. bags/bank are item
-- totals, nil when not known. With EverlookDB Auctions' inventory this addon stops counting, so its own saved counts
-- are old: the bags come from the inventory instead (when it has seen the character), and the bank, which the
-- inventory doesn't hand out per character, is left out rather than shown stale.
local function total(t)
  local n = 0
  for _, v in pairs(type(t) == "table" and t or {}) do n = n + (tonumber(v) or 0) end
  return n
end
function St.charCounts(c)
  if type(c) ~= "table" then return {} end
  local inv = St.shared()
  if not inv then
    return { bags = c.bags and total(c.bags) or nil, bank = c.bank and total(c.bank) or nil, bankAt = c.bankAt,
      seenAt = c.bagsAt }
  end
  local res = { shared = true }
  local b = c.name and try(inv.bagsOf, c.name, c.realmID)
  if type(b) == "table" then res.bags = total(b) end
  local list = type(inv.characters) == "function" and try(inv.characters)
  for _, e in ipairs(type(list) == "table" and list or {}) do
    if e.name == c.name then res.seenAt = tonumber(e.at); break end
  end
  return res
end

-- EverlookDB Auctions read new counts: the windows that show them follow
local listening = false
function St.listen()
  local inv = St.shared()
  if listening or not inv or type(inv.onChange) ~= "function" then return end
  listening = true
  pcall(inv.onChange, function() if ns.onStock then pcall(ns.onStock) end end)
end

local pending = false
ns.on("BAG_UPDATE_DELAYED", function()
  if not EverlookCraftDB or pending then return end
  pending = true
  C_Timer.After(2, function()
    pending = false
    St.readBags()
    if St.bankOpen then St.readBank() end
  end)
end)
ns.on("PLAYER_ENTERING_WORLD", function()
  St.listen()
  if EverlookCraftDB then C_Timer.After(3, St.readBags) end
end)
ns.on("BANKFRAME_OPENED", function()
  if not EverlookCraftDB then return end
  St.bankOpen = true
  C_Timer.After(0.5, St.readBank)
end)
ns.on("BANKFRAME_CLOSED", function() St.bankOpen = false end)
-- sorting the bank fires this once per slot: count it once things settle
local bankPending = false
ns.on("PLAYERBANKSLOTS_CHANGED", function()
  if not St.bankOpen or not EverlookCraftDB or bankPending then return end
  bankPending = true
  C_Timer.After(0.5, function()
    bankPending = false
    if St.bankOpen then St.readBank() end
  end)
end)
