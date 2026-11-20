-- "Buy what the route needs": a slim bar under an open merchant window when that merchant sells vendor materials
-- your skill-up routes still need (the guide's "Buy from vendors" list). The first click shows what it will buy and
-- what it costs; a second click (the same button, "Buy for 1g 20s") buys it. It never buys more than the route still
-- needs after your bags, bank and (unless "don't count my alts' materials" is on) your alts are counted; an item the
-- merchant sells only in packs is bought in as few packs as cover the need. Nothing is bought without your click.
local _, ns = ...
local try, plain = ns.try, ns.plain

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba

local M = { pending = {} }
ns.merchant = M

ns.DEFAULTS.settings.merchantButton = true

local function open()
  return M.isOpen and true or false
end
function M.open() return open() end

---------------------------------------------------------------------------------------------------------------------
-- What to buy (pure apart from reading the merchant and the routes)

-- what this character's unfinished routes still need, beyond what you have: { [id] = n }, vendor goods only
function M.routeShort()
  local need, makes = {}, {}
  for skill, rt in pairs(EverlookCraftChar and EverlookCraftChar.routes or {}) do
    local rank = ns.plans.skillNow(skill)
    if not (rank and rank >= rt.to) then
      for _, c in ipairs(rt.crafted or {}) do makes[c.id] = true end
      local ok, rem = pcall(ns.plans.remaining, rt, rank)
      for id, n in pairs(ok and rem or {}) do need[id] = (need[id] or 0) + n end
    end
  end
  local out = {}
  for id, n in pairs(need) do
    if not makes[id] and ns.prices.vendor(id) then
      local short = n - ns.stock.usable(id) - (M.pending[id] or 0)
      if short > 0 then out[id] = short end
    end
  end
  return out
end

-- What this merchant would sell you for the route: { { id, n (items you get), packs, each (per pack), qty, index, cost, maxStack } },
-- total copper. rows: C.merchantRows() (the open merchant), short: M.routeShort().
function M.plan(rows, short)
  local list, total = {}, 0
  local seen = {}
  for _, row in ipairs(rows) do
    local want = short[row.id]
    if want and not seen[row.id] and row.price and row.price > 0 and not row.extended then
      seen[row.id] = true
      local packs = math.ceil(want / row.qty)
      if row.avail >= 0 then packs = math.min(packs, row.avail) end
      if packs > 0 then
        local e = { id = row.id, index = row.index, qty = row.qty, packs = packs, n = packs * row.qty, each = row.price,
          cost = packs * row.price, maxStack = row.maxStack, want = want }
        list[#list + 1] = e
        total = total + e.cost
      end
    end
  end
  table.sort(list, function(a, b) return (ns.itemInfo(a.id)) < (ns.itemInfo(b.id)) end)
  return list, total
end

function M.current()
  if not open() or not ns.capture then return {}, 0 end
  return M.plan(ns.capture.merchantRows(), M.routeShort())
end

-- For other windows (a Crafting list or guide row's "Buy"): does the open merchant sell this item for gold? Its row.
function M.sells(id)
  if not open() or not ns.capture then return nil end
  for _, row in ipairs(ns.capture.merchantRows()) do
    if row.id == id and row.price and row.price > 0 and not row.extended then return row end
  end
end

-- Buy n of one item from the open merchant (from a click): n rounded up to whole packs, never more than it has.
-- Returns how many purchases were made, or nil and why not.
function M.buyItem(id, n)
  local row = M.sells(id)
  if not row then return nil, "this merchant doesn't sell it" end
  local list, total = M.plan({ row }, { [id] = n })
  return M.buy(list, total)
end

-- Buy a plan (from a click). Never more than each row's packs; items sold one at a time go in stacks.
-- Returns how many purchases were made, or nil and why not.
function M.buy(list, total)
  if not open() then return nil, "the merchant is closed" end
  if #list == 0 then return nil, "nothing to buy" end
  local money = plain(try(GetMoney)) or 0
  if money < total then return nil, "not enough money (" .. ns.money(total, true) .. " needed)" end
  local calls = 0
  for _, e in ipairs(list) do
    if e.qty == 1 then
      local left = e.packs
      local stack = math.max(1, e.maxStack or 1)
      while left > 0 do
        local k = math.min(left, stack)
        try(BuyMerchantItem, e.index, k)
        calls, left = calls + 1, left - k
      end
    else
      -- sold in packs: one call per pack
      for _ = 1, e.packs do try(BuyMerchantItem, e.index); calls = calls + 1 end
    end
    M.pending[e.id] = (M.pending[e.id] or 0) + e.n
  end
  M.boughtAt = plain(try(GetTime)) or 0
  return calls
end

---------------------------------------------------------------------------------------------------------------------
-- The bar under the merchant window

local T, bar
local armed

local function text(parent, size, color)
  return UI.Text(parent, size, color)
end

local function describe(list)
  local parts = {}
  for _, e in ipairs(list) do
    local name = ns.itemInfo(e.id)
    parts[#parts + 1] = e.n .. " " .. name
  end
  return table.concat(parts, ", ")
end

local function disarm()
  armed = nil
  if bar then
    bar.button:SetText("Buy what the route needs")
    bar.cancel:Hide()
    bar.sum:Show()
  end
end

function M.refresh()
  if not bar then return end
  local parent = rawget(_G, "MerchantFrame")
  if not open() or not ns.settings().merchantButton or not parent or (parent.IsShown and not parent:IsShown()) then
    bar:Hide()
    disarm()
    return
  end
  local list, total = M.current()
  if #list == 0 then bar:Hide(); disarm(); return end
  bar.title:SetText(("Skill-up route: %d %s here"):format(#list, #list == 1 and "material" or "materials"))
  bar.detail:SetText(describe(list))
  bar.sum:SetText("Total " .. ns.money(total))
  -- the item list wraps: the bar grows with it
  local h = bar.detail.GetStringHeight and bar.detail:GetStringHeight() or 14
  bar:SetHeight(30 + math.max(14, h or 14) + 8 + 26 + 8)
  bar:Show()
end

local function onClick()
  if not armed then
    local list, total = M.current()
    if #list == 0 then M.refresh() return end
    armed = { list = list, total = total }
    bar.button:SetText("Buy for " .. ns.money(total, true))
    bar.cancel:Show()
    bar.sum:Hide()
    C_Timer.After(8, function() if armed then disarm() end end)
    return
  end
  local plan = armed
  disarm()
  local calls, why = M.buy(plan.list, plan.total)
  if calls then
    ns.print(("Bought %s for %s."):format(describe(plan.list), ns.money(plan.total, true)))
  else
    ns.print("Nothing bought: " .. why .. ".")
  end
  M.refresh()
end

function M.makeBar()
  if bar then return bar end
  local parent = rawget(_G, "MerchantFrame")
  if not parent then return nil end
  T = UI.MakeTheme(ns.ACCENT or { 1, 0.82, 0 })
  bar = CreateFrame("Frame", "EverlookCraftMerchantBar", parent)
  bar.eluiTheme = T
  bar:SetSize(parent.GetWidth and math.max(320, parent:GetWidth() or 0) or 340, 86)
  bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
  bar:SetFrameStrata("HIGH")
  bar:EnableMouse(true)
  bar.fill, bar.edge = U.RoundBox(bar, 6, T.bg, T.border)
  bar.accent = U.Solid(bar, "ARTWORK", rgba(T.accent))
  bar.accent:SetPoint("TOPLEFT", 6, 0)
  bar.accent:SetPoint("TOPRIGHT", -6, 0)
  bar.accent:SetHeight(2)
  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetSize(14, 14)
  bar.icon:SetPoint("TOPLEFT", 10, -11)
  if UI.SetIcon(bar.icon, "bag") then bar.icon:SetVertexColor(rgba(T.accent)) end
  bar.title = text(bar, T.font, T.text)
  bar.title:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)
  bar.title:SetPoint("RIGHT", -10, 0)
  bar.title:SetWordWrap(false)
  bar.detail = text(bar, T.fontSmall + 1, T.muted)
  bar.detail:SetPoint("TOPLEFT", 10, -30)
  bar.detail:SetPoint("RIGHT", -10, 0)
  bar.detail:SetJustifyH("LEFT")
  bar.detail:SetWordWrap(true)
  bar.sum = text(bar, T.font, T.text)
  bar.sum:SetPoint("BOTTOMLEFT", 10, 15)
  bar.button = UI.Button(bar, "Buy what the route needs", onClick, 180, "accent")
  bar.button:SetPoint("BOTTOMRIGHT", -8, 8)
  bar.cancel = UI.Button(bar, "Cancel", function() disarm() end, 70)
  bar.cancel:SetPoint("RIGHT", bar.button, "LEFT", -6, 0)
  bar.cancel:Hide()
  UI.Tooltip(bar.button, "Buy what the route needs",
    "Vendor materials your skill-up routes still need after your bags, bank and alts. The first click shows the price; click again to buy.")
  bar:SetScript("OnHide", disarm)
  bar:Hide()
  return bar
end

ns.on("MERCHANT_SHOW", function()
  M.isOpen = true
  if not EverlookCraftDB then return end
  M.makeBar()
  C_Timer.After(0.4, M.refresh)
end)
ns.on("MERCHANT_UPDATE", function() if M.isOpen then C_Timer.After(0.2, M.refresh) end end)
ns.on("MERCHANT_CLOSED", function()
  M.isOpen = false
  if bar then bar:Hide() end
  disarm()
end)

-- bags counted again: what was just bought is in them now
local prevStock = ns.onStock
ns.onStock = function()
  if prevStock then prevStock() end
  if M.boughtAt and (plain(try(GetTime)) or 0) - M.boughtAt >= 1 then
    M.pending, M.boughtAt = {}, nil
  end
  if M.isOpen then M.refresh() end
end
local prevRoute = ns.onRoute
ns.onRoute = function(skill)
  if prevRoute then prevRoute(skill) end
  if M.isOpen then M.refresh() end
end

ns.app:Setting({ key = "merchant.button", type = "bool", label = "\"Buy what the route needs\" at merchants",
  desc = "A bar under the merchant window when that merchant sells vendor materials your skill-up routes still need. It buys only after you click twice, and never more than needed.",
  keywords = { "merchant", "vendor", "buy", "shopping", "route" }, default = true,
  get = function() return ns.settings().merchantButton ~= false end,
  set = function(v) ns.settings().merchantButton = v and true or false; M.refresh() end })
