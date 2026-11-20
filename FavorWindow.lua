-- The Merchant's Favor window (/ecraft favor): every Waylaid Crate ranked by gold per Favor at today's prices. Each row
-- shows the cheapest of the crate's bundles (you fill it with ONE), the other bundles as alternatives on hover, the
-- Favor and money it pays, what it costs in all and per Favor, a Map button to your side's Inventory Intake clerk and,
-- when the cheapest bundle is crafted, "Add" to put that recipe on the Crafting list. Filters: tier, your level, the
-- faction you turn in at, and "count my bags as free". One filled button: send what to buy for the picked crate to
-- EverlookDB Auctions' shopping list. It stays open on its own: no other window opens or closes it.
local _, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba

local FW = {}
ns.favorWindow = FW

local ROW_H = 60
local DOT = "  \194\183  "

local f, T

local function F() return ns.favor end
local function S() return ns.settings() end

-- the second and third line of a row
function FW.lines(res)
  local c = res.c
  local l2, l3 = {}, {}
  local b = res.best
  if b then
    l2[#l2 + 1] = ("Fill: |cffffffff%s|r"):format(F().optionName(b))
    l2[#l2 + 1] = F().howText(b)
    l2[#l2 + 1] = ns.money(b.cost)
    local n = 0
    for _, o in ipairs(res.options) do if o ~= b then n = n + 1 end end
    if n > 0 then l2[#l2 + 1] = ("%d other bundle%s"):format(n, n == 1 and "" or "s") end
  else
    l2[#l2 + 1] = "Fill: no price for any bundle"
  end
  l3[#l3 + 1] = c.favor and ("|cffffd100+%d Favor|r"):format(c.favor) or "Favor unknown"
  if c.money then l3[#l3 + 1] = ns.money(c.money) end
  l3[#l3 + 1] = c.rep == 0 and "no reputation" or c.rep and (c.rep .. " reputation") or "reputation unknown"
  if res.crate.how == "owned" then l3[#l3 + 1] = ("crate: you have %d"):format(res.crate.have)
  elseif res.crate.cost then l3[#l3 + 1] = "crate " .. ns.money(res.crate.cost)
  else l3[#l3 + 1] = "crate: no auction price" end
  if res.total then l3[#l3 + 1] = "total " .. ns.money(res.total) end
  if res.why then l3 = { "|cff8d94a3" .. "Not ranked: " .. res.why .. "|r" } end
  return table.concat(l2, DOT), table.concat(l3, DOT)
end

local function tooltip(owner, res)
  local c = res.c
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local name = ns.itemInfo(c.id)
  GameTooltip:AddLine(name, 1, 1, 1)
  GameTooltip:AddLine(("%s, %s crate, level %d."):format(F().tierName(c), c.crafted and "crafted" or "gathered", c.level), 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Fill it with ONE of these:", 1, 0.82, 0)
  for i, o in ipairs(res.options) do
    local left = (i == 1 and o.cost and "|cff62cf88cheapest|r  " or "") .. F().optionName(o) .. "  |cff8d94a3" .. F().howText(o) .. "|r"
    GameTooltip:AddDoubleLine(left, o.cost and ns.money(o.cost) or ns.money(nil), 1, 1, 1, 1, 1, 1)
  end
  local who = F().npc()
  local npc = who and ns.DATA.npcs[who]
  if npc then GameTooltip:AddLine(("Turn in: %s, %s"):format(npc[1], ns.map.zoneName(npc[3])), 0.55, 0.58, 0.64) end
  if res.why then GameTooltip:AddLine("Not ranked: " .. res.why, 1, 0.5, 0.5, true) end
  GameTooltip:AddLine("Click: pick it for \"Send missing to Auctions\".", 0.55, 0.58, 0.64, true)
  GameTooltip:Show()
end

local function buildRow(list)
  local r = ns.widgets.RowCard(list, T)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("LEFT", 12, 0)
  r.rank = UI.Text(r, T.fontSmall, T.muted)
  r.rank:SetPoint("TOPLEFT", 4, -4)
  r.name = UI.Text(r, T.font, T.text)
  r.name:SetPoint("TOPLEFT", 50, -7)
  r.name:SetWordWrap(false)
  r.l2 = UI.Text(r, T.fontSmall + 1, T.muted)
  r.l2:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
  r.l2:SetWordWrap(false)
  r.l3 = UI.Text(r, T.fontSmall + 1, T.muted)
  r.l3:SetPoint("TOPLEFT", r.l2, "BOTTOMLEFT", 0, -4)
  r.l3:SetWordWrap(false)
  r.per = UI.Text(r, T.fontTitle, T.text)
  r.per:SetJustifyH("RIGHT")
  r.map = ns.widgets.SmallButton(r, "Map", function() local id = F().npc(); if id then ns.map.pin(id) end end, 46)
  r.map:SetPoint("BOTTOMRIGHT", -8, 7)
  r.add = ns.widgets.SmallButton(r, "Add to list", function()
    if not r.item then return end
    local _, msg = F().addToList(r.item)
    ns.print(msg)
  end, 84)
  r.add:SetPoint("RIGHT", r.map, "LEFT", -6, 0)
  r.per:SetPoint("TOPRIGHT", -10, -8)
  for _, t in ipairs({ r.name, r.l2, r.l3 }) do t:SetPoint("RIGHT", r, "RIGHT", -150, 0) end
  r.l3:SetPoint("RIGHT", r.add, "LEFT", -8, 0)
  r:SetScript("OnClick", function(self)
    if not self.item then return end
    FW.selected = self.item.c.id
    if IsShiftKeyDown() then
      local _, link = ns.try(GetItemInfo, self.item.c.id)
      if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    end
    FW.render()
  end)
  r:HookScript("OnEnter", function(self) if self.item then tooltip(self, self.item) end end)
  r:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function paintRow(r, res, i)
  local c = res.c
  local name, icon, q = ns.itemInfo(c.id)
  ns.widgets.SetAnyIcon(r.icon, icon, T)
  r.rank:SetText(res.perFavor and tostring(i) or "")
  r.name:SetText(("|cff%s%s|r"):format(ns.qualityColor(q), (name:gsub("^Waylaid Crate: ", ""))))
  local l2, l3 = FW.lines(res)
  r.l2:SetText(l2)
  r.l3:SetText(l3)
  if res.perFavor then
    r.per:SetText(ns.money(res.perFavor) .. "|cff8d94a3 /Favor|r")
  else
    r.per:SetText("|cff8d94a3? /Favor|r")
  end
  local canAdd = F().craftNeed(res) ~= nil
  r.add:SetShown(canAdd)
  r:SetBase(T.surface)
  r:SetSelected(FW.selected == c.id)
end

local function chip(parent, label, onClick, width)
  return ns.widgets.Chip(parent, label, onClick, width)
end

local function make()
  if f then return f end
  f = ns.widgets.Window({ name = "EverlookCraftFavor", posKey = "favor", title = "Merchant's Favor", icon = "coins",
    width = 780, height = 600, minWidth = 760, minHeight = 380, point = "CENTER", x = 220, y = 20, top = 100,
    hint = "Hover a crate for every bundle. Fill it with one of them." })
  T = f.T
  -- filters: tier chips, then faction, level and bags
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 16, -62)
  bar:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  bar:SetHeight(26)
  f.tiers = {}
  local prev
  for t = 0, 4 do
    local b = chip(bar, t == 0 and "All" or ns.favor.TIERS[t], function() S().favorTier = t; FW.render() end, t == 0 and 40 or 80)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
    f.tiers[t] = b
    prev = b
  end
  f.bags = chip(bar, "My bags free", function() S().favorBagsFree = not S().favorBagsFree; FW.render() end, 100)
  f.bags:SetPoint("RIGHT", 0, 0)
  f.level = chip(bar, "My level", function() S().favorMyLevel = not S().favorMyLevel; FW.render() end, 72)
  f.level:SetPoint("RIGHT", f.bags, "LEFT", -4, 0)
  f.horde = chip(bar, "Horde", function() S().favorSide = "h"; FW.render() end, 58)
  f.horde:SetPoint("RIGHT", f.level, "LEFT", -12, 0)
  f.alliance = chip(bar, "Alliance", function() S().favorSide = "a"; FW.render() end, 66)
  f.alliance:SetPoint("RIGHT", f.horde, "LEFT", -4, 0)
  f.list = ns.widgets.VList(f.body, T, ROW_H, buildRow, paintRow, 4, "No crate matches the filters.")
  f.list:SetAllPoints(f.body)
  f:SetPrimary("Send missing to Auctions", function() FW.primary() end, 190)
  f:SetScript("OnShow", function() FW.render() end)
  f:SetScript("OnSizeChanged", function() if f:IsShown() then f.list:Render() end end)
  return f
end

-- the crate the primary button acts on: the one you picked, else the best ranked
function FW.pick(rows)
  for _, res in ipairs(rows) do if res.c.id == FW.selected then return res end end
  return rows[1] and rows[1].perFavor and rows[1] or nil
end

function FW.primary()
  local res = FW.pick(FW.rows or ns.favor.current())
  local ok, msg = ns.favor.sendToAuctions(res)
  ns.print(ok and msg or ("couldn't send the list: " .. tostring(msg)))
end

function FW.render()
  if not f or not f:IsShown() then return end
  local s = S()
  local rows = ns.favor.current()
  FW.rows = rows
  for t, b in pairs(f.tiers) do b:SetActive((s.favorTier or 0) == t) end
  local side = ns.favor.side()
  f.alliance:SetActive(side == "a")
  f.horde:SetActive(side == "h")
  f.level:SetActive(s.favorMyLevel and true or false)
  f.bags:SetActive(s.favorBagsFree and true or false)
  local ranked = 0
  for _, res in ipairs(rows) do if res.perFavor then ranked = ranked + 1 end end
  local src = ns.prices.auctionsLoaded() and "EverlookDB Auctions" or ns.prices.auctionatorLoaded() and "Auctionator" or nil
  f.sub:SetText(src and ("%d crates ranked by gold per Favor%sprices: %s%s"):format(ranked, DOT, src,
    s.favorBagsFree and (DOT .. "what you have counts as free") or "")
    or "|cffffd100No auction prices: install EverlookDB Auctions (or Auctionator) and scan the auction house.|r")
  local npc = ns.DATA.npcs[ns.favor.npc(side) or 0]
  f.hint:SetText(npc and ("Turn in: %s, %s. Fill each crate with ONE bundle."):format(npc[1], ns.map.zoneName(npc[3]))
    or "Hover a crate for every bundle. Fill it with one of them.")
  local pick = FW.pick(rows)
  local p = f.primary
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  p:SetUsable(api ~= nil and (api.version or 0) >= 2 and pick ~= nil and #ns.favor.shoppingItems(pick) > 0)
  if pick and not FW.selected then FW.selected = pick.c.id end
  f.list:SetItems(rows, true)
end

function FW.open()
  make():Show()
  FW.render()
end

function FW.toggle()
  if f and f:IsShown() then f:Hide() else FW.open() end
end

function FW.applyScale() if f then f:SetScale(ns.settings().windowScale or 1) end end

local prevStock = ns.onStock
ns.onStock = function() if prevStock then prevStock() end FW.render() end
