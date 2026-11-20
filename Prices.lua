-- What a material costs you. In order: a vendor that sells it (the price you saw at a merchant, else what WoW Forever's
-- vendors charge in EverlookDB's data), then the auction house: EverlookDB Auctions' scans when installed, else
-- Auctionator's. Nothing else: no guesses in totals. A material with no price shows "?" and is counted as unpriced.
-- To choose between recipes when a material has no price, the planner may use an estimate (its effort times what one
-- gathered material sells for at your auction house); that estimate is never shown as a price.
local _, ns = ...
local try, plain = ns.try, ns.plain

local Pr = {}
ns.prices = Pr

local function item(id) return ns.DATA and ns.DATA.items[id] end

-- the vendor price per unit (seen at a merchant beats the data), or nil
function Pr.vendor(id)
  -- what a merchant on this realm asked (Capture.lua), else an older price saved before prices were kept per realm
  local seen = ns.capture and ns.capture.price(id) or (EverlookCraftDB and EverlookCraftDB.seen[id])
  if seen then return seen end
  local it = item(id)
  return it and it[4] or nil
end

function Pr.auctionsLoaded()
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  return api ~= nil and (api.version or 0) >= 1
end

function Pr.auctionatorLoaded()
  local a = rawget(_G, "Auctionator")
  return a and a.API and a.API.v1 and a.API.v1.GetAuctionPriceByItemID ~= nil
end

-- the auction house price per unit and where it came from ("EverlookDB Auctions" or "Auctionator"), or nil
function Pr.ah(id)
  local s = ns.settings()
  if s.useAuctions and Pr.auctionsLoaded() then
    local low, age = try(EverlookDBAuctionsAPI.price, id)
    low = plain(low)
    if low and low > 0 then return low, "EverlookDB Auctions", plain(age) end
  end
  if s.useAuctionator and Pr.auctionatorLoaded() then
    local p = plain(try(Auctionator.API.v1.GetAuctionPriceByItemID, "EverlookDBCrafting", id))
    if p and p > 0 then return p, "Auctionator" end
  end
  return nil
end

-- what you pay for one: { price, how = "vendor" | "ah", source } or nil
function Pr.unit(id)
  local v = Pr.vendor(id)
  if v then return v, "vendor", "vendor" end
  local p, src, age = Pr.ah(id)
  if p then return p, "ah", src, age end
  return nil
end

-- what a recipe's pattern costs at a vendor (from the data; nil: no gold vendor or unknown)
function Pr.pattern(r)
  local ri = ns.DATA and ns.DATA.recipeItems[r.item]
  if ri and ri[1] and ri[1] > 0 then return ri[1] end
  return nil
end

-- the pattern on the auction house today
function Pr.patternAH(r)
  if not r.item or r.item == 0 then return nil end
  return (Pr.ah(r.item))
end

-- copper per unit of effort: what one gathered material sells for at your auction house (the median), for estimates
function Pr.perEffort()
  local per = {}
  for id, it in pairs(ns.DATA and ns.DATA.items or {}) do
    if it[6] == "gather" and it[5] and it[5] > 0 then
      local p = Pr.ah(id)
      if p then per[#per + 1] = p / it[5] end
    end
  end
  table.sort(per)
  return per[math.floor(#per / 2) + 1] or 0
end

-- an estimate to choose by (never shown): effort x perEffort, or effort x 1 silver when the house has no prices
function Pr.estimator()
  local k = Pr.perEffort()
  if k <= 0 then k = 100 end
  return function(id)
    local it = item(id)
    return (it and it[5] or 3) * k
  end
end

-- A merchant's prices are saved per realm by Capture.lua.
