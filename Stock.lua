-- Stock across your characters: what each one has in its bags (the reagent bag too) and, from its last bank visit, in
-- its bank and reagent bank. Kept per character in EverlookCraftDB (this PC only, never uploaded). Bags are counted
-- again 2 seconds after they change; the bank while it is open.
local _, ns = ...
local try, plain = ns.try, ns.plain

local St = {}
ns.stock = St

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
  local me = ns.me()
  if not me then return end
  me.bags, me.bagsAt = St.count(BAGS), time()
  if ns.onStock then ns.onStock() end
end

function St.readBank()
  local me = ns.me()
  if not me then return end
  me.bank, me.bankAt = St.count(BANK), time()
  if ns.onStock then ns.onStock() end
end

-- How many of an item: { bags, bank (this character), alts (all others), byChar = { { name, n } } }.
function St.have(id)
  local db = EverlookCraftDB
  local guid = ns.guid()
  local res = { bags = 0, bank = 0, alts = 0, byChar = {} }
  for g, c in pairs(db and db.chars or {}) do
    local b, k = (c.bags or {})[id] or 0, (c.bank or {})[id] or 0
    if g == guid then
      res.bags, res.bank = b, k
    elseif b + k > 0 then
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
  return h.bags + h.bank + (ns.settings().noAlts and 0 or h.alts)
end

-- every item you have, for the planner: { [id] = n }
function St.owned()
  local out = {}
  local guid, noAlts = ns.guid(), ns.settings().noAlts
  for g, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do
    if g == guid or not noAlts then
      for _, t in ipairs({ c.bags or {}, c.bank or {} }) do
        for id, n in pairs(t) do out[id] = (out[id] or 0) + n end
      end
    end
  end
  return out
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
  if EverlookCraftDB then C_Timer.After(3, St.readBags) end
end)
ns.on("BANKFRAME_OPENED", function()
  if not EverlookCraftDB then return end
  St.bankOpen = true
  C_Timer.After(0.5, St.readBank)
end)
ns.on("BANKFRAME_CLOSED", function() St.bankOpen = false end)
ns.on("PLAYERBANKSLOTS_CHANGED", function() if St.bankOpen and EverlookCraftDB then St.readBank() end end)
