-- The crafting queue window (once the Crafting list): the recipes you plan to craft (with - and + for the count, a
-- Keep box for how many to keep in stock, and each one's status and profit), their material tree with what
-- you have on every character, a craft-or-buy switch on each material one of your characters can make, a Map button to
-- the nearest vendor for vendor goods, and "To buy" at the end. One filled button: send what is missing to EverlookDB
-- Auctions' shopping list (vendor goods stay off it). It stays open on its own: no other window opens or closes it.
local _, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba

local LW = {}
ns.listWindow = LW

local ROW_H = 38
local INDENT = 18

---------------------------------------------------------------------------------------------------------------------
-- What the rows show

-- the flat rows: a recipe, its materials (depth first), then "To buy"
function LW.rows(tree)
  tree = tree or ns.craftList.tree()
  local rows = {}
  local function walk(n)
    rows[#rows + 1] = n
    for _, k in ipairs(n.kids or {}) do walk(k) end
  end
  for _, root in ipairs(tree.roots) do walk(root) end
  if #tree.missing > 0 then
    rows[#rows + 1] = { head = true, text = "To buy" }
    for _, m in ipairs(tree.missing) do rows[#rows + 1] = { buy = true, id = m.id, n = m.n, vendor = m.vendor } end
  elseif #tree.roots > 0 then
    rows[#rows + 1] = { head = true, text = "To buy", done = true }
    rows[#rows + 1] = { note = true, text = "Nothing: you have every material on your characters." }
  end
  return rows
end

local STATUS_COLOR = { ready = "62cf88", stocked = "62cf88", materials = "ef5d5d", skill = "8d94a3", cooldown = "e0b453" }
LW.STATUS_COLOR = STATUS_COLOR

-- the second line of a recipe: profession, what it makes, its status (coloured), its profit each and the stock kept
function LW.rootDetail(n)
  local L = ns.craftList
  local e = L.find(n.spell) or { spell = n.spell, n = n.n }
  local st = L.status(e, n.r)
  local parts = { ns.profName(n.r.skill), ("makes %d"):format(n.makes) }
  parts[#parts + 1] = ("|cff%s%s|r"):format(STATUS_COLOR[st.key] or "8d94a3", st.text)
  local p = L.profitEach(n.r)
  if p then parts[#parts + 1] = (p >= 0 and "profit " or "loss ") .. ns.money(math.abs(p)) .. " each" end
  if e.keep and st.key ~= "stocked" then parts[#parts + 1] = ("%d of %d in stock"):format(L.stockOf(n.r.creates), e.keep) end
  return table.concat(parts, "  \194\183  ")
end

-- the muted second line of a material
function LW.detail(n)
  local parts = {}
  local where = ns.craftList.whereText(n.id)
  if n.have >= n.need then
    parts[#parts + 1] = ("need %d, you have it"):format(n.need)
  else
    parts[#parts + 1] = ("need %d, have %d"):format(n.need, n.have)
  end
  if where ~= "" then parts[#parts + 1] = where end
  if n.mode == "craft" and n.crafts then
    parts[#parts + 1] = ("craft %d x %s"):format(n.crafts, n.via.name)
  elseif n.cut then
    parts[#parts + 1] = "a loop: bought here"
  elseif n.vendor then
    parts[#parts + 1] = "vendor"
  end
  return table.concat(parts, "  \194\183  ")
end

---------------------------------------------------------------------------------------------------------------------
-- The window

local f, T

local function buildRow(list, i)
  local r = ns.widgets.RowCard(list, T)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.name = UI.Text(r, T.font, T.text)
  r.name:SetWordWrap(false)
  r.detail = UI.Text(r, T.fontSmall + 1, T.muted)
  r.detail:SetWordWrap(false)
  r.right = UI.Text(r, T.font, T.text)
  r.right:SetJustifyH("RIGHT")
  r.right:SetWordWrap(false)
  r.check = ns.widgets.LineIcon(r, "check", 12, T.ok)
  -- keep N in stock: the count then refills itself from what you have
  r.keep = UI.EditBox(r, 38, 20)
  r.keep:SetNumeric(true)
  r.keep:SetMaxLetters(4)
  r.keep:SetJustifyH("RIGHT")
  r.keep:SetTextInsets(4, 6, 0, 0)
  local function saveKeep(self)
    local n = r.item and r.item.root and r.item
    if not n then return end
    local v = tonumber(self:GetText()) or 0
    local e = ns.craftList.find(n.spell)
    if (e and e.keep or 0) ~= v then ns.craftList.setKeep(n.spell, v) end
  end
  r.keep:SetScript("OnEnterPressed", function(self) saveKeep(self); self:ClearFocus() end)
  r.keep:HookScript("OnEditFocusLost", saveKeep)
  r.keep:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Keep in stock", 1, 1, 1)
    GameTooltip:AddLine("How many of the item to keep. The queue then crafts what is missing by itself: it counts your bags, bank, mail, alts and auctions. Empty or 0: off.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  r.keep:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.keepLabel = UI.Text(r, T.fontSmall + 1, T.muted)
  r.keepLabel:SetText("keep")
  -- buttons, right to left: remove, show, +, count, -  (recipes) or craft/buy, map (materials)
  r.remove = CreateFrame("Button", nil, r)
  r.remove:SetSize(20, 20)
  r.remove.icon = ns.widgets.LineIcon(r.remove, "close", 9, T.muted)
  r.remove.icon:SetPoint("CENTER")
  r.remove:SetScript("OnClick", function() if r.item and r.item.root then ns.craftList.remove(r.item.spell) end end)
  r.remove:SetScript("OnEnter", function(self) self.icon:SetVertexColor(rgba(T.danger)) end)
  r.remove:SetScript("OnLeave", function(self) self.icon:SetVertexColor(rgba(T.muted)) end)
  r.show = ns.widgets.SmallButton(r, "Show", function() if r.item and r.item.r then ns.browser.showRecipe(r.item.r) end end, 52)
  r.plus = ns.widgets.SmallButton(r, "+", function() if r.item then ns.craftList.set(r.item.spell, r.item.n + (IsShiftKeyDown() and 5 or 1)) end end, 22)
  r.count = UI.Text(r, T.font, T.text)
  r.count:SetJustifyH("CENTER")
  r.count:SetWidth(30)
  r.minus = ns.widgets.SmallButton(r, "-", function() if r.item then ns.craftList.set(r.item.spell, r.item.n - (IsShiftKeyDown() and 5 or 1)) end end, 22)
  r.mode = ns.widgets.SmallButton(r, "Craft", function()
    local n = r.item
    if n and n.via and not n.cut then ns.craftList.setMode(n.id, n.mode == "craft" and "buy" or "craft") end
  end, 56)
  r.map = ns.widgets.SmallButton(r, "Map", function()
    local it = r.item and ns.DATA.items[r.item.id]
    ns.widgets.MapTo(it and it[7])
  end, 46)
  r:SetScript("OnClick", function(self, button)
    local n = self.item
    if not n then return end
    if n.root and IsShiftKeyDown() then ns.browser.link(n.r) return end
    if button == "RightButton" and n.via and not n.cut then ns.craftList.setMode(n.id, n.mode == "craft" and "buy" or "craft") end
  end)
  r:HookScript("OnEnter", function(self)
    local n = self.item
    if not n or n.head or n.note then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if n.root then
      GameTooltip:AddLine(n.r.name, 1, 1, 1)
      GameTooltip:AddLine(("%s, %d crafts, makes %d."):format(ns.profName(n.r.skill), n.n, n.makes), nil, nil, nil, true)
      local st = ns.craftList.status(ns.craftList.find(n.spell) or { spell = n.spell, n = n.n }, n.r)
      GameTooltip:AddLine("Status: " .. st.text, 1, 0.82, 0, true)
      if st.by and #st.by > 0 then GameTooltip:AddLine("Known by " .. table.concat(st.by, ", ") .. ".", 0.8, 0.8, 0.8, true) end
      GameTooltip:AddLine("- and + change the count (Shift: by 5). Each craft takes one off. Keep: how many to keep in stock (the count then refills itself). Shift-click: link it.", 0.55, 0.58, 0.64, true)
    else
      pcall(GameTooltip.SetItemByID, GameTooltip, n.id)
      local h = ns.stock.have(n.id)
      GameTooltip:AddLine(("%d in bags, %d in bank%s, %d on other characters"):format(h.bags, h.bank,
        (h.mail or 0) > 0 and (", " .. h.mail .. " in the mail") or "", h.alts), 1, 0.82, 0)
      local p, how, src = ns.prices.unit(n.id)
      GameTooltip:AddLine(p and ("%s each (%s)"):format(ns.money(p), how == "vendor" and "vendor" or src) or "No price yet", 0.8, 0.8, 0.8)
      if n.via and not n.cut then
        GameTooltip:AddLine(("Right-click: %s instead."):format(n.mode == "craft" and "buy it" or ("craft it (" .. n.via.name .. ")")), 0.55, 0.58, 0.64, true)
      end
    end
    GameTooltip:Show()
  end)
  r:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function hideAll(r)
  for _, k in ipairs({ "remove", "show", "plus", "count", "minus", "mode", "map", "check", "keep", "keepLabel" }) do r[k]:Hide() end
end

local function paintRow(r, n)
  hideAll(r)
  r:SetSelected(false)
  r.bg:SetShown(not (n.head or n.note))
  r:EnableMouse(not (n.head or n.note))
  r.icon:ClearAllPoints()
  r.name:ClearAllPoints()
  r.detail:ClearAllPoints()
  r.right:ClearAllPoints()
  r.detail:SetText("")
  r.right:SetText("")
  U.SetFont(r.name, T.font)
  r.name:SetTextColor(rgba(T.text))
  if n.head or n.note then
    r.icon:Hide()
    r.name:SetPoint("BOTTOMLEFT", 4, 8)
    r.name:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    if n.head then
      U.SetFont(r.name, T.fontSmall + 1)
      r.name:SetText(n.text:upper())
      r.name:SetTextColor(rgba(n.done and T.ok or T.gold))
    else
      r.name:SetPoint("BOTTOMLEFT", 4, 14)
      r.name:SetText(n.text)
      r.name:SetTextColor(rgba(T.muted))
    end
    return
  end
  r:SetBase(n.root and T.surface or ns.widgets.mix(T.card, T.surface, 0.3))
  local x = 10 + (n.depth or 0) * INDENT
  r.icon:SetPoint("LEFT", x, 0)
  r.icon:Show()
  r.name:SetPoint("TOPLEFT", x + 28, -6)
  r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
  local rightEdge
  if n.root then
    ns.widgets.SetAnyIcon(r.icon, ns.recipeIcon(n.r), T)
    local _, _, q = ns.itemInfo(n.r.creates or 0)
    r.name:SetText(("|cff%s%s|r"):format(ns.qualityColor(n.r.creates and n.r.creates ~= 0 and q or 1), n.r.name))
    r.detail:SetText(LW.rootDetail(n))
    r.remove:SetPoint("RIGHT", -6, 0); r.remove:Show()
    r.show:SetPoint("RIGHT", r.remove, "LEFT", -6, 0); r.show:Show()
    r.plus:SetPoint("RIGHT", r.show, "LEFT", -10, 0); r.plus:Show()
    r.count:SetPoint("RIGHT", r.plus, "LEFT", -2, 0); r.count:SetText(n.n); r.count:Show()
    r.minus:SetPoint("RIGHT", r.count, "LEFT", -2, 0); r.minus:Show()
    local e = ns.craftList.find(n.spell)
    if n.r.creates and n.r.creates ~= 0 then
      r.keep:ClearAllPoints()
      r.keep:SetPoint("RIGHT", r.minus, "LEFT", -10, 0)
      if not (r.keep.HasFocus and r.keep:HasFocus()) then r.keep:SetText(e and e.keep and tostring(e.keep) or "") end
      r.keep:Show()
      r.keepLabel:ClearAllPoints()
      r.keepLabel:SetPoint("RIGHT", r.keep, "LEFT", -4, 0)
      r.keepLabel:Show()
      rightEdge = r.keepLabel
    else
      rightEdge = r.minus
    end
  elseif n.buy then
    local name, icon, q = ns.itemInfo(n.id)
    ns.widgets.SetAnyIcon(r.icon, icon, T)
    r.name:SetText(("|cff%s%s|r"):format(ns.qualityColor(q), name))
    local p = ns.prices.unit(n.id)
    r.detail:SetText(n.vendor and "from a vendor (not on the shopping list)" or "at the auction house")
    r.right:SetText(("x%d  %s"):format(n.n, p and ns.money(p * n.n) or ns.money(nil)))
    if n.vendor then
      r.map:SetPoint("RIGHT", -8, 0); r.map:Show()
      r.right:SetPoint("RIGHT", r.map, "LEFT", -8, 0)
    else
      r.right:SetPoint("RIGHT", -10, 0)
    end
    rightEdge = r.right
  else
    local name, icon, q = ns.itemInfo(n.id)
    ns.widgets.SetAnyIcon(r.icon, icon, T)
    r.name:SetText(("|cff%s%s|r"):format(ns.qualityColor(q), name))
    r.detail:SetText(LW.detail(n))
    local anchor
    if n.via and not n.cut then
      r.mode:SetText(n.mode == "craft" and "Craft" or "Buy")
      r.mode:SetPoint("RIGHT", -8, 0); r.mode:Show()
      anchor = r.mode
    elseif n.vendor and n.short > 0 then
      r.map:SetPoint("RIGHT", -8, 0); r.map:Show()
      anchor = r.map
    end
    if n.short <= 0 then
      r.check:ClearAllPoints()
      if anchor then r.check:SetPoint("RIGHT", anchor, "LEFT", -10, 0) else r.check:SetPoint("RIGHT", -12, 0) end
      r.check:Show()
      rightEdge = r.check
    else
      r.right:SetText(("|cffef5d5d%d short|r"):format(n.short))
      if n.mode == "craft" then r.right:SetText(("%d to craft"):format(n.short)) end
      if anchor then r.right:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else r.right:SetPoint("RIGHT", -10, 0) end
      rightEdge = r.right
    end
  end
  r.name:SetPoint("RIGHT", rightEdge, "LEFT", -8, 0)
  r.detail:SetPoint("RIGHT", rightEdge, "LEFT", -8, 0)
end

local function make()
  if f then return f end
  f = ns.widgets.Window({ name = "EverlookCraftList", posKey = "list", title = "Crafting queue", icon = "list",
    width = 600, height = 560, minWidth = 520, minHeight = 360, point = "CENTER", x = -220, y = 20,
    hint = "Right-click a material: craft or buy. Craft next in your profession window goes top to bottom." })
  T = f.T
  f.list = ns.widgets.VList(f.body, T, ROW_H, buildRow, paintRow, 3,
    "Nothing queued yet. Open the recipe browser (/ecraft recipes) and press \"Add to queue\" on a recipe, or type /ecraft queue add <recipe name>.")
  f.list:SetAllPoints(f.body)
  f.list.empty:SetText("")
  -- the empty state: a line icon, a title and what to do, in the middle
  local e = CreateFrame("Frame", nil, f.body)
  e:SetSize(360, 120)
  e:SetPoint("CENTER", f.body, "CENTER", 0, 20)
  e.icon = ns.widgets.LineIcon(e, "list", 28, T.accent)
  e.icon:SetPoint("TOP", 0, 0)
  e.title = UI.Text(e, T.fontTitle + 1, T.text)
  e.title:SetPoint("TOP", e.icon, "BOTTOM", 0, -12)
  e.title:SetJustifyH("CENTER")
  e.title:SetText("Nothing queued yet")
  e.text = UI.Text(e, T.font, T.muted)
  e.text:SetPoint("TOP", e.title, "BOTTOM", 0, -8)
  e.text:SetWidth(360)
  e.text:SetJustifyH("CENTER")
  e.text:SetText("Queue a recipe: \"Add to queue\" in the recipe browser, right-click a recipe in your profession window, \"Queue next steps\" in the skill-up guide, or Crafting profit in EverlookDB Auctions. The queue shows every material, what you have on each character, and what is missing.")
  f.emptyState = e
  f:SetPrimary("Send missing to Auctions", function() LW.primary() end, 190)
  f:SetScript("OnShow", function() LW.render() end)
  f:SetScript("OnSizeChanged", function() if f:IsShown() then f.list:Render() end end)
  return f
end

function LW.primary()
  local tree = ns.craftList.tree()
  if #tree.roots == 0 then
    if ns.browserWindow then ns.browserWindow.open() end
    return
  end
  local ok, msg = ns.craftList.sendToAuctions()
  if ok then ns.print(ns.craftList.sentText(#ns.craftList.shoppingItems(tree), msg))
  elseif ok == nil then ns.print("loading item names, one moment...")
  else ns.print("couldn't send the list: " .. tostring(msg)) end
end

function LW.render()
  if not f or not f:IsShown() then return end
  local tree = ns.craftList.tree()
  local ah, vendor, unpriced = ns.craftList.cost(tree)
  local nMissing = #tree.missing
  if #tree.roots == 0 then
    f.sub:SetText("Queue what to craft: the materials, what you have on every character, and what is missing.")
  else
    local cost = ns.money(ah + vendor) .. (unpriced > 0 and (" |cff8d94a3+ " .. unpriced .. " without a price|r") or "")
    f.sub:SetText(("%d recipe%s  \194\183  %s"):format(#tree.roots, #tree.roots == 1 and "" or "s",
      nMissing == 0 and "|cff62cf88you have every material|r" or ("%d materials to buy, %s"):format(nMissing, cost)))
  end
  local p = f.primary
  if #tree.roots == 0 then
    p:SetText("Browse recipes")
    p:SetUsable(true)
  else
    p:SetText("Send missing to Auctions")
    p:SetUsable(ns.craftList.shoppingTarget() ~= nil and #ns.craftList.shoppingItems(tree) > 0)
  end
  f.emptyState:SetShown(#tree.roots == 0)
  f.hint:SetText(#tree.roots == 0 and "Also: /ecraft queue add <recipe name> [count]"
    or "Right-click a material: craft or buy. Craft next in your profession window goes top to bottom.")
  f.list:SetItems(LW.rows(tree), true)
end

function LW.open()
  make():Show()
  LW.render()
end

function LW.toggle()
  if f and f:IsShown() then f:Hide() else LW.open() end
end

function LW.applyScale() if f then f:SetScale(ns.settings().windowScale or 1) end end

local prevList, prevStock = ns.onList, ns.onStock
ns.onList = function() if prevList then prevList() end LW.render() end
ns.onStock = function() if prevStock then prevStock() end LW.render() end
