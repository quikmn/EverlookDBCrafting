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

local ROW_H = 82
local DOT = "  \194\183  "

local f, T

local function F() return ns.favor end
local function S() return ns.settings() end

-- the second and third line of a row
function FW.lines(res)
  local c = res.c
  local l2, l3 = {}, {}
  local b = res.best
  -- line 2: what goes in, and what you get back
  if b then
    l2[#l2 + 1] = ("Fill: |cffffffff%s|r (%s)"):format(F().optionName(b), F().howText(b))
    local n = 0
    for _, o in ipairs(res.options) do if o ~= b then n = n + 1 end end
    if n > 0 then l2[#l2 + 1] = ("%d other bundle%s"):format(n, n == 1 and "" or "s") end
  else
    -- the reason ("no price for any bundle") is on line 3: here only how many bundles there are
    local n = #res.options
    l2[#l2 + 1] = ("Fill: %d bundle%s, none with a price yet"):format(n, n == 1 and "" or "s")
  end
  if c.money then l2[#l2 + 1] = ns.money(c.money) .. " back" end
  if c.rep and c.rep > 0 then l2[#l2 + 1] = c.rep .. " reputation" end
  -- line 3: the cost, split: crate + fill = total
  local crate
  if res.crate.how == "owned" then crate = ("crate |cffffffff%s|r (you have %d)"):format(ns.money(0), res.crate.have)
  elseif res.crate.cost then crate = "crate |cffffffff" .. ns.money(res.crate.cost) .. "|r"
  else crate = "crate: no auction price" end
  local fill = b and b.cost and ("fill |cffffffff" .. ns.money(b.cost) .. "|r") or "fill: ?"
  l3[#l3 + 1] = crate .. "  +  " .. fill .. (res.total and ("  =  |cffffffff" .. ns.money(res.total) .. "|r") or "")
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
  r.rank:SetPoint("TOPLEFT", 8, -4)
  r.name = UI.Text(r, T.font, T.text)
  r.name:SetPoint("TOPLEFT", 50, -7)
  r.name:SetWordWrap(false)
  r.l2 = UI.Text(r, T.fontSmall + 1, T.muted)
  r.l2:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
  r.l2:SetWordWrap(false)
  r.l3 = UI.Text(r, T.fontSmall + 1, T.muted)
  r.l3:SetPoint("TOPLEFT", r.l2, "BOTTOMLEFT", 0, -4)
  r.l3:SetWordWrap(false)
  -- the right column: total cost, + Favor, gold per Favor (the buttons sit at the far right)
  r.tot = UI.Text(r, T.font, T.text)
  r.tot:SetJustifyH("RIGHT")
  r.fav = UI.Text(r, T.font, T.text)
  r.fav:SetJustifyH("RIGHT")
  r.per = UI.Text(r, T.font, T.text)
  r.per:SetJustifyH("RIGHT")
  r.map = ns.widgets.SmallButton(r, "Map", function() local id = F().npc(); if id then ns.map.pin(id) end end, 96)
  r.map:SetPoint("TOPRIGHT", -8, -10)
  r.add = ns.widgets.SmallButton(r, "Craft list", function()
    if not r.item then return end
    local _, msg = F().addToList(r.item)
    ns.print(msg)
  end, 84)
  -- this crate's shopping list: the crate (unless you have it) and its cheapest fill, to EverlookDB Auctions
  r.shop = ns.widgets.SmallButton(r, "Shopping list", function()
    if not r.item then return end
    local ok, msg = F().sendToAuctions(r.item)
    if ok == nil then ns.print("loading item names, one moment...")
    else ns.print(ok and msg or ("couldn't make the list: " .. tostring(msg))) end
  end, 96)
  r.shop:SetPoint("TOPRIGHT", r.map, "BOTTOMRIGHT", 0, -4)
  r.shop:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Shopping list", 1, 1, 1)
    GameTooltip:AddLine("Puts this crate and its cheapest fill on the shopping list \"" .. F().listName(r.item) ..
      "\" in EverlookDB Auctions, minus what you already have. Each crate has its own list. Buy them in its Shopping tab.",
      0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  r.shop:HookScript("OnLeave", function() GameTooltip:Hide() end)
  r.add:ClearAllPoints()
  r.add:SetWidth(96)
  r.add:SetPoint("TOPRIGHT", r.shop, "BOTTOMRIGHT", 0, -4)
  r.tot:SetPoint("TOPRIGHT", -114, -10)
  r.fav:SetPoint("TOPRIGHT", r.tot, "BOTTOMRIGHT", 0, -4)
  r.per:SetPoint("TOPRIGHT", r.fav, "BOTTOMRIGHT", 0, -4)
  for _, t in ipairs({ r.name, r.l2, r.l3 }) do t:SetPoint("RIGHT", r, "RIGHT", -280, 0) end
  r:SetScript("OnClick", function(self)
    if not self.item then return end
    FW.selected = self.item.c.id
    if IsShiftKeyDown() then
      local link = ns.itemLink(self.item.c.id)
      if link and ChatEdit_InsertLink then pcall(ChatEdit_InsertLink, link) end
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
  local byTotal = S().favorSort == "total"
  local MUTE, ON = "|cff8d94a3", "|cffffffff"
  -- what you sort by is white, the other grey
  r.tot:SetText((byTotal and ON or MUTE) .. "Total cost:|r " .. (res.total and ("~" .. ns.money(res.total)) or MUTE .. "?|r"))
  r.fav:SetText(c.favor and ("|cffffd100+%d Favor|r"):format(c.favor) or (MUTE .. "Favor unknown|r"))
  r.per:SetText(res.perFavor and ((byTotal and MUTE or ON) .. "per Favor:|r ~" .. ns.money(res.perFavor)) or (MUTE .. "per Favor: ?|r"))
  local canAdd = F().craftNeed(res) ~= nil
  r.add:SetShown(canAdd)
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  r.shop:SetUsable(api ~= nil and (api.version or 0) >= 2 and #F().shoppingItems(res) > 0)
  r:SetBase(T.surface)
  r:SetSelected(FW.selected == c.id)
end

local function chip(parent, label, onClick, width)
  return ns.widgets.Chip(parent, label, onClick, width)
end

-- Every place the crate list is shown: the window, and the Merchant's Favor page of EverlookDB Auctions' main window.
-- Each view v has: host (shown or not), tiers, alliance, horde, level, sortPer, sortTotal, bags, list, sub, hint and
-- primary.
local views = {}

-- The filter and sort bars at the top of host (y below its top), and the crate list in body.
local function buildControls(v, host, y, body)
  local bar = CreateFrame("Frame", nil, host)
  bar:SetPoint("TOPLEFT", 16, y)
  bar:SetPoint("RIGHT", host, "RIGHT", -16, 0)
  bar:SetHeight(26)
  v.tiers = {}
  local prev
  for t = 0, 4 do
    local b = chip(bar, t == 0 and "All" or ns.favor.TIERS[t], function() S().favorTier = t; FW.render() end, t == 0 and 40 or 80)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
    v.tiers[t] = b
    prev = b
  end
  v.bags = chip(bar, "My bags free", function() S().favorBagsFree = not S().favorBagsFree; FW.render() end, 100)
  v.bags:SetPoint("RIGHT", 0, 0)
  v.level = chip(bar, "My level", function() S().favorMyLevel = not S().favorMyLevel; FW.render() end, 72)
  v.level:SetPoint("RIGHT", v.bags, "LEFT", -4, 0)
  v.horde = chip(bar, "Horde", function() S().favorSide = "h"; FW.render() end, 58)
  v.horde:SetPoint("RIGHT", v.level, "LEFT", -12, 0)
  v.alliance = chip(bar, "Alliance", function() S().favorSide = "a"; FW.render() end, 66)
  v.alliance:SetPoint("RIGHT", v.horde, "LEFT", -4, 0)
  -- sort: gold per Favor, or the cheapest total (crate + fill)
  local sortBar = CreateFrame("Frame", nil, host)
  sortBar:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  sortBar:SetPoint("RIGHT", host, "RIGHT", -16, 0)
  sortBar:SetHeight(24)
  local lbl = UI.Text(sortBar, T.fontSmall + 1, T.muted)
  lbl:SetPoint("LEFT", 0, 0)
  lbl:SetText("Sort by")
  v.sortPer = chip(sortBar, "Cheapest per Favor", function() S().favorSort = "per"; FW.render() end, 140)
  v.sortPer:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
  v.sortTotal = chip(sortBar, "Cheapest total", function() S().favorSort = "total"; FW.render() end, 116)
  v.sortTotal:SetPoint("LEFT", v.sortPer, "RIGHT", 4, 0)
  v.list = ns.widgets.VList(body, T, ROW_H, buildRow, paintRow, 4, "No crate matches the filters.")
  v.list:SetAllPoints(body)
  v.list.emptyFn = FW.emptyText
  host:HookScript("OnShow", function() FW.render() end)
  host:HookScript("OnSizeChanged", function() if host:IsShown() then v.list:Render() end end)
  views[#views + 1] = v
  return v
end

local function make()
  if f then return f end
  f = ns.widgets.Window({ name = "EverlookCraftFavor", posKey = "favor", title = "Merchant's Favor", icon = "bag",
    width = 780, height = 600, minWidth = 760, minHeight = 380, point = "CENTER", x = 220, y = 20, top = 130,
    hint = "Hover a crate for every bundle. Fill it with one of them." })
  T = f.T
  local v = { host = f, sub = f.sub, hint = f.hint }
  buildControls(v, f, -62, f.body)
  v.primary = f:SetPrimary("Send missing to Auctions", function() FW.primary() end, 190)
  f.view, f.list = v, v.list
  return f
end

-- The crate list inside another addon's frame (EverlookDB Auctions' main window): filters, the list, a line about
-- prices and where to turn in, and the "Send missing to Auctions" button, all inside parent. Built once per parent.
local embedded = {}
function FW.embed(parent)
  if embedded[parent] then FW.render(); return embedded[parent] end
  T = T or ns.widgets.theme()
  local host = CreateFrame("Frame", nil, parent)
  host:SetAllPoints(parent)
  local v = { host = host }
  v.sub = UI.Text(host, T.fontSmall + 1, T.muted)
  v.sub:SetPoint("TOPLEFT", 16, 0)
  v.sub:SetPoint("RIGHT", host, "RIGHT", -16, 0)
  v.sub:SetWordWrap(false)
  local footer = CreateFrame("Frame", nil, host)
  footer:SetPoint("BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", 0, 0)
  footer:SetHeight(46)
  v.primary = UI.Button(footer, "Send missing to Auctions", function() FW.primary() end, 190, "accent")
  v.primary:SetPoint("RIGHT", -16, 0)
  v.hint = UI.Text(footer, T.fontSmall, T.muted)
  v.hint:SetPoint("LEFT", 16, 0)
  v.hint:SetPoint("RIGHT", v.primary, "LEFT", -12, 0)
  v.hint:SetWordWrap(false)
  local body = CreateFrame("Frame", nil, host)
  body:SetPoint("TOPLEFT", 16, -86)
  body:SetPoint("BOTTOMRIGHT", -16, 52)
  buildControls(v, host, -22, body)
  embedded[parent] = v
  FW.render()
  return v
end

-- what an empty list says: too low a level for any crate, else the filters
function FW.emptyText()
  local lowest
  for _, c in ipairs(ns.favor.crates()) do
    if (S().favorTier or 0) == 0 or c.tier == S().favorTier then lowest = math.min(lowest or c.level, c.level) end
  end
  local level = ns.plain(ns.try(UnitLevel, "player"))
  if S().favorMyLevel and lowest and level and level < lowest then
    return ("No crate for your level yet: these open at level %d. Click \"My level\" to see them all."):format(lowest)
  end
  return "No crate matches the filters."
end

-- the crate the primary button acts on: the one you picked, else the best ranked
function FW.pick(rows)
  for _, res in ipairs(rows) do if res.c.id == FW.selected then return res end end
  return rows[1] and rows[1].perFavor and rows[1] or nil
end

function FW.primary()
  local res = FW.pick(FW.rows or ns.favor.current())
  local ok, msg = ns.favor.sendToAuctions(res)
  if ok == nil then ns.print("loading item names, one moment...")
  else ns.print(ok and msg or ("couldn't send the list: " .. tostring(msg))) end
end

function FW.render()
  local s = S()
  local rows
  for _, v in ipairs(views) do
    if v.host:IsShown() then
      rows = rows or ns.favor.current()
      FW.renderView(v, rows, s)
    end
  end
  if rows then FW.rows = rows end
end

function FW.renderView(v, rows, s)
  for t, b in pairs(v.tiers) do b:SetActive((s.favorTier or 0) == t) end
  local side = ns.favor.side()
  v.alliance:SetActive(side == "a")
  v.horde:SetActive(side == "h")
  v.level:SetActive(s.favorMyLevel and true or false)
  v.sortPer:SetActive(s.favorSort ~= "total")
  v.sortTotal:SetActive(s.favorSort == "total")
  v.bags:SetActive(s.favorBagsFree and true or false)
  local ranked = 0
  for _, res in ipairs(rows) do if res.perFavor then ranked = ranked + 1 end end
  local src = ns.prices.auctionsLoaded() and "EverlookDB Auctions" or ns.prices.auctionatorLoaded() and "Auctionator" or nil
  v.sub:SetText(src and ("%d crates ranked by %s%sprices: %s%s"):format(ranked,
    s.favorSort == "total" and "total cost (crate + fill)" or "gold per Favor", DOT, src,
    s.favorBagsFree and (DOT .. "what you have counts as free") or "")
    or "|cffffd100No auction prices: install EverlookDB Auctions (or Auctionator) and scan the auction house.|r")
  local npc = ns.DATA.npcs[ns.favor.npc(side) or 0]
  v.hint:SetText(npc and ("Turn in: %s, %s. Fill each crate with ONE bundle."):format(npc[1], ns.map.zoneName(npc[3]))
    or "Hover a crate for every bundle. Fill it with one of them.")
  local pick = FW.pick(rows)
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  v.primary:SetUsable(api ~= nil and (api.version or 0) >= 2 and pick ~= nil and #ns.favor.shoppingItems(pick) > 0)
  if pick and not FW.selected then FW.selected = pick.c.id end
  v.list:SetItems(rows, true)
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
-- a profession window read: new recipes can make a bundle cheaper to craft
local prevScanned = ns.onScanned
ns.onScanned = function(skill) if prevScanned then prevScanned(skill) end FW.render() end
