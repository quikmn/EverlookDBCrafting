-- The Skill-Up guide: a small movable checklist that walks your route. The current step on top (its live skill bar,
-- the chance of a skill-up now in the recipe's colour, crafts left and what to buy for 9 times out of 10), then one
-- shopping list (every material: have / need on your characters, its cost, auction house, vendor with Map or Buy at
-- an open merchant, or make it; the patterns to learn), what the crafts take from your bags (shrinks as you craft),
-- and every step with the rank trainings and tools. A section ticks green when it is done; right-click a step to mark
-- it done or not. "Send to auction house" puts the auction house part on a shopping list there.
-- Crafting stays with the game: "Show recipe" selects the step's recipe in your profession window.
local _, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba
local try, plain = ns.try, ns.plain

local G = { offset = 0 }
ns.guide = G

local W, ROW, PAD = 380, 22, 14
local T

local function settings() return ns.settings() end

local function skillOf()
  return G.skill or (EverlookCraftChar and EverlookCraftChar.lastSkill)
end

local function route() local s = skillOf() return s and ns.plans.saved(s) end

---------------------------------------------------------------------------------------------------------------------
-- Rows

-- the rows of the checklist: { kind = "head" | "item" | "learn" | "step" | "train" | "tool" | "note", ... }
--   Shopping list: every material still to get (have / need on your characters, what the rest costs, where: auction
--     house, vendor with Map and Buy, or make it: click to buy it ready-made instead), the patterns to learn;
--   In your bags: what the steps take, bags / need (fetch the rest from the bank, mail it from your alts);
--   Steps: rank trainings, tools to make or buy, and the crafts.
function G.rows(rt, skillNow)
  local rows = {}
  if not rt then return rows end
  local shop = ns.plans.shopping(rt, skillNow)
  G.shop = shop
  local list, allHave = {}, true
  for _, e in ipairs(shop.items) do
    local row = { kind = "item", id = e.id, need = e.need, have = e.have, short = e.short, e = e,
      mode = e.make and "make" or (e.how or "none") }
    if e.short > 0 then allHave = false end
    list[#list + 1] = row
  end
  for _, l in ipairs(shop.learn) do
    list[#list + 1] = { kind = "learn", l = l, done = false }
    allHave = false
  end
  local total = ns.money(shop.total) .. (shop.unpriced > 0 and (" |cff8d94a3+ " .. shop.unpriced .. " ?|r") or "")
  rows[#rows + 1] = { kind = "head", text = "Shopping list", done = allHave, right = not allHave and total or nil }
  if #list == 0 then rows[#rows + 1] = { kind = "note", text = "Nothing: you have it all." } end
  for _, r in ipairs(list) do rows[#rows + 1] = r end

  -- what the crafts take from your bags
  local bags, bagsDone = {}, true
  for _, e in ipairs(shop.items) do
    local inBags = ns.stock.have(e.id).bags
    if inBags < e.need then bagsDone = false end
    bags[#bags + 1] = { kind = "item", id = e.id, need = e.need, have = math.min(inBags, e.need), mode = "bags", e = e }
  end
  table.sort(bags, function(x, y) return (ns.itemInfo(x.id)) < (ns.itemInfo(y.id)) end)
  rows[#rows + 1] = { kind = "head", text = "In your bags", done = bagsDone }
  if #bags == 0 then rows[#rows + 1] = { kind = "note", text = "None: the route is done." } end
  for _, r in ipairs(bags) do rows[#rows + 1] = r end

  -- the steps, with the rank trainings and tools where they fall
  local done = EverlookCraftChar.done[rt.skill] or {}
  local allDone = true
  local cur = ns.plans.currentStep(rt, skillNow)
  local stepRows = {}
  local trs, ti, tls, ki = rt.trainings or {}, 1, rt.tools or {}, 1
  for i, st in ipairs(rt.steps) do
    while trs[ti] and trs[ti].cap <= st.from do
      local tr = trs[ti]
      stepRows[#stepRows + 1] = { kind = "train", tr = tr, passed = skillNow and skillNow > tr.cap or false }
      ti = ti + 1
    end
    while tls[ki] and tls[ki].at <= st.from do
      stepRows[#stepRows + 1] = { kind = "tool", tl = tls[ki], have = not ns.plans.toolMissing(tls[ki]) }
      ki = ki + 1
    end
    local isDone = done[i] or (skillNow and skillNow >= st.to) or false
    if not isDone then allDone = false end
    stepRows[#stepRows + 1] = { kind = "step", i = i, st = st, done = isDone, current = i == cur }
  end
  rows[#rows + 1] = { kind = "head", text = "Steps", done = allDone }
  for _, r in ipairs(stepRows) do rows[#rows + 1] = r end
  if rt.stall then rows[#rows + 1] = { kind = "note", text = ("The route stops at %d: nothing you can learn reliably raises it."):format(rt.stall), warn = true } end
  return rows
end

-- switch an item between making it and buying it ready-made (the planner's choice, shared with the Crafting list)
function G.toggleMake(e)
  local mode = e.make and "buy" or "craft"
  if ns.craftList then ns.craftList.setMode(e.id, mode) end
  G.render()
  if ns.onRoute then ns.onRoute(skillOf()) end
end

-- send what the route still has to buy at the auction house to EverlookDB Auctions (else Auctionator)
function G.send()
  local rt = route()
  if not rt then return end
  local items = ns.plans.auctionItems(ns.plans.shopping(rt, ns.plans.skillNow(rt.skill)))
  local name = ns.profName(rt.skill) .. " skill-up"
  local function said(ok, msg)
    if ok then ns.print(("%d materials are on the shopping list \"%s\" in %s."):format(#items, name, msg))
    else ns.print("couldn't send the list: " .. tostring(msg)) end
  end
  local ok, msg = ns.craftList.sendList(name, items, said)
  if ok == nil then ns.print("loading item names, one moment...") else said(ok, msg) end
end

---------------------------------------------------------------------------------------------------------------------
-- The window

local function text(parent, size, color, justify)
  local fs = UI.Text(parent, size, color)
  fs:SetWordWrap(false)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function smallButton(parent, label, onClick, width)
  local b = UI.Button(parent, label, onClick, width or 44)
  b:SetHeight(18)
  U.SetFont(b.label, T.fontSmall)
  return b
end

-- the tooltip of a shopping or bags row: the item, where you have it, its price and where to buy it, the choice
local function itemTooltip(self, row)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  pcall(GameTooltip.SetItemByID, GameTooltip, row.id)
  local h = ns.stock.have(row.id)
  GameTooltip:AddLine(("Need %d: %d in bags, %d in bank%s, %d on other characters"):format(row.need, h.bags, h.bank,
    (h.mail or 0) > 0 and (", " .. h.mail .. " in the mail") or "", h.alts), 1, 0.82, 0)
  for k, c in ipairs(h.byChar) do if k <= 4 then GameTooltip:AddLine(("  %d on %s"):format(c.n, c.name), 0.7, 0.7, 0.7) end end
  if settings().noOwn then GameTooltip:AddLine("\"Buy everything for the route\" is on: only your bags count.", 0.7, 0.7, 0.7, true) end
  local e = row.e or {}
  if e.make then
    GameTooltip:AddLine(("Make it: %s. Crafted %s each%s."):format(e.make.name or "its recipe", ns.money(e.craftU),
      e.buyU and (", ready-made " .. ns.money(e.buyU)) or ""), 0.8, 0.8, 0.8, true)
    if e.buyU then GameTooltip:AddLine("Click: buy it ready-made instead.", 0.55, 0.58, 0.64, true) end
  else
    local p, how, src = ns.prices.unit(row.id)
    GameTooltip:AddLine(p and ("%s each (%s)"):format(ns.money(p), how == "vendor" and "vendor" or src)
      or "No price yet: not in the last auction house scan, and no vendor sells it.", 0.8, 0.8, 0.8, true)
    if how == "vendor" then
      local _, vname, zone = ns.plans.vendorOf(row.id)
      if vname then GameTooltip:AddLine(("Nearest vendor: %s, %s"):format(vname, zone), 0.8, 0.8, 0.8) end
    end
    if e.buying then GameTooltip:AddLine(("Click: make it again (crafted %s each)."):format(ns.money(e.craftU)), 0.55, 0.58, 0.64, true) end
  end
  GameTooltip:Show()
end

local function makeRow(f, i)
  local r = CreateFrame("Button", nil, f.list)
  r:SetHeight(ROW)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
  r:SetPoint("RIGHT", 0, 0)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.hl = U.Round(r, 4, "BACKGROUND")
  r.hl:SetAllPoints(r)
  r.hl:SetVertexColor(rgba(T.surface))
  r.hl:Hide()
  r.tick = r:CreateTexture(nil, "ARTWORK")
  r.tick:SetSize(12, 12)
  r.tick:SetPoint("LEFT", 2, 0)
  UI.SetIcon(r.tick, "check")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 18, 0)
  r.right = text(r, T.fontSmall + 1, T.text, "RIGHT")
  r.right:SetPoint("RIGHT", -4, 0)
  r.map = smallButton(r, "Map", function(self) if self.npcs then local id = ns.map.nearest(self.npcs); if id then ns.map.pin(id) else ns.print("no one for your side in the data.") end end end)
  r.map:SetPoint("RIGHT", -2, 0)
  -- "Buy" at an open merchant that sells it: what the route still lacks, in whole packs
  r.buy = smallButton(r, "Buy", function(self)
    if not self.id then return end
    local calls, why = ns.merchant.buyItem(self.id, self.n)
    if calls then ns.print(("bought %d %s."):format(self.n, (ns.itemInfo(self.id)))) else ns.print("nothing bought: " .. tostring(why) .. ".") end
    G.render()
  end)
  r.buy:SetPoint("RIGHT", -2, 0)
  r.name = text(r, T.font, T.text)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
  r:SetScript("OnEnter", function(self)
    local row = self.row
    if not row then return end
    if row.kind == "item" or row.kind == "step" or row.kind == "learn" then self.hl:Show() end
    if row.kind == "item" then
      itemTooltip(self, row)
    elseif row.kind == "learn" then
      local l = row.l
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if l.item then pcall(GameTooltip.SetItemByID, GameTooltip, l.item) else GameTooltip:AddLine(l.r.name, 1, 1, 1) end
      GameTooltip:AddLine(ns.options.learnLine(l), 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    elseif row.kind == "step" then
      local lines = ns.options.rowTooltip({ kind = "step", st = row.st }, skillOf())
      if lines then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        for li, l in ipairs(lines) do if li == 1 then GameTooltip:AddLine(l, 1, 1, 1) else GameTooltip:AddLine(l, nil, nil, nil, true) end end
        GameTooltip:AddLine("Click: show it in your profession window. Right-click: done / not done.", 0.55, 0.58, 0.64, true)
        GameTooltip:Show()
      end
    elseif row.kind == "train" or row.kind == "tool" then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(ns.options.rowTitle(row, skillOf()), 1, 1, 1)
      GameTooltip:AddLine(ns.options.rowDetail(row, skillOf()), nil, nil, nil, true)
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self, button)
    local row = self.row
    if not row then return end
    if row.kind == "item" then
      local e = row.e
      if button ~= "RightButton" and e and ((e.make and e.buyU) or e.buying) then G.toggleMake(e) end
      return
    end
    if row.kind ~= "step" then return end
    if button == "RightButton" then
      local d = EverlookCraftChar.done
      d[route().skill] = d[route().skill] or {}
      d[route().skill][row.i] = not d[route().skill][row.i] or nil
      G.render()
    else
      G.select(row.st)
    end
  end)
  return r
end

-- put the Map (or Buy) button on a row, the right text left of it
local function withButton(r, b)
  b:Show()
  r.right:ClearAllPoints()
  r.right:SetPoint("RIGHT", b, "LEFT", -6, 0)
end

local function paintRow(r, row, rt, skillNow)
  r.row = row
  r.map:Hide()
  r.map.npcs = nil
  r.buy:Hide()
  r.buy.id = nil
  r.tick:Hide()
  r.icon:Show()
  r.icon:SetVertexColor(1, 1, 1)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetTextColor(rgba(T.text))
  r.right:SetText("")
  r.right:ClearAllPoints()
  r.right:SetPoint("RIGHT", -4, 0)
  if row.kind == "head" then
    r.icon:Hide()
    r.name:SetPoint("LEFT", 18, 0)
    U.SetFont(r.name, T.fontSmall + 1)
    r.name:SetText(row.text:upper())
    r.name:SetTextColor(rgba(row.done and T.ok or T.gold))
    r.right:SetText(row.right or "")
    r.tick:SetShown(row.done)
    r.tick:SetVertexColor(rgba(T.ok))
    return
  end
  U.SetFont(r.name, T.font)
  if row.kind == "note" then
    r.icon:Hide()
    r.name:SetPoint("LEFT", 18, 0)
    r.name:SetText(row.text)
    r.name:SetTextColor(rgba(row.warn and T.danger or T.muted))
    return
  end
  if row.kind == "item" then
    local name, icon, q = ns.itemInfo(row.id)
    r.icon:SetTexture(icon)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ok = row.have >= row.need
    r.tick:SetShown(ok)
    r.tick:SetVertexColor(rgba(T.ok))
    local count = ("%s%d / %d|r"):format(ok and "|cff62cf88" or "|cffe8eaef", math.min(row.have, row.need), row.need)
    local label = ("|cff%s%s|r"):format(ns.qualityColor(q), name)
    if row.mode == "make" then
      r.name:SetText("Make " .. label)
      r.right:SetText(count)
    elseif row.mode == "bags" then
      r.name:SetText(label)
      r.right:SetText(count)
    else
      local e = row.e
      local where = row.mode == "ah" and "AH" or row.mode == "vendor" and "vendor" or "find"
      r.name:SetText(label .. "  |cff8d94a3" .. where .. "|r")
      r.right:SetText(ok and count or ("%s  %s"):format(count, e.price and ns.money(e.price * row.short) or ns.money(nil)))
      if not ok and row.mode == "vendor" then
        if ns.merchant and ns.merchant.sells(row.id) then
          r.buy.id, r.buy.n = row.id, row.short
          withButton(r, r.buy)
        else
          local it = ns.DATA.items[row.id]
          if it and #it[7] > 0 then r.map.npcs = it[7]; withButton(r, r.map) end
        end
      end
    end
    return
  end
  if row.kind == "learn" then
    local l = row.l
    UI.SetIcon(r.icon, "scroll")
    r.icon:SetVertexColor(rgba(T.gold))
    r.name:SetText(("Learn %s"):format(l.r.name))
    r.right:SetText(l.how == "teacher" and "" or ns.money(l.price))
    local npcs = ns.options.learnNpcs(l, rt.skill)
    if npcs then r.map.npcs = npcs; withButton(r, r.map) end
    return
  end
  if row.kind == "train" or row.kind == "tool" then
    local title = ns.options.rowTitle(row, rt.skill)
    if row.kind == "train" then
      UI.SetIcon(r.icon, "book")
      r.icon:SetVertexColor(rgba(T.gold))
      local lvl = row.tr.level and (plain(try(UnitLevel, "player")) or 0) < row.tr.level
      r.name:SetText(title .. ("  |cff8d94a3at %d|r"):format(row.tr.at) .. (lvl and ("  |cffe06060level %d|r"):format(row.tr.level) or ""))
      r.right:SetText(ns.money(row.tr.fee))
    else
      local _, icon = ns.itemInfo(row.tl.item or 0)
      r.icon:SetTexture(icon)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.name:SetText(title)
      r.right:SetText(row.tl.kind == "buy" and ns.money(row.tl.price) or "")
    end
    local passed = row.passed or row.have
    r.name:SetTextColor(rgba(passed and T.muted or T.gold))
    local npcs = not passed and ns.options.rowNpcs(row, rt.skill)
    if npcs then r.map.npcs = npcs; withButton(r, r.map) end
    r.tick:SetShown(passed and true or false)
    r.tick:SetVertexColor(rgba(T.ok))
    return
  end
  -- a step
  local st = row.st
  local rec = ns.plans.recipe(rt.skill, st.spell)
  r.icon:SetTexture(ns.recipeIcon(rec))
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local col = rec and ns.widgets.colorCode(ns.colorAt(rec, math.max(st.from, skillNow or 0))) or "|cffffffff"
  r.name:SetText(("%s%d|r  %s"):format(col, st.from, rec and rec.name or "?"))
  if row.done then r.name:SetTextColor(rgba(T.muted)) end
  local left, left90 = ns.plans.craftsLeft(rt, st, skillNow)
  r.right:SetText(row.done and "done" or (settings().buffer and left90 > left) and ("~%d, buy %d"):format(left, left90) or ("~%d"):format(left))
  r.tick:SetShown(row.done)
  r.tick:SetVertexColor(rgba(T.ok))
  if row.current then r.hl:Show() end
end

local function makeFrame()
  if G.frame then return G.frame end
  T = UI.MakeTheme(ns.ACCENT)
  local f = CreateFrame("Frame", "EverlookCraftGuide", UIParent)
  f.eluiTheme = T
  f:SetWidth(W)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not settings().guideLocked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    EverlookCraftDB.guidePos = { p, rp, x, y }
  end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    G.offset = math.max(0, G.offset - delta * 3)
    G.render()
  end)
  UI.WindowChrome(f, T)
  UI.CloseButton(f, T)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(16, 16)
  f.icon:SetPoint("TOPLEFT", PAD + 2, -16)
  if UI.SetIcon(f.icon, "hammer") then f.icon:SetVertexColor(rgba(T.accent)) end
  f.title = text(f, T.fontTitle + 1, T.text)
  f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  f.title:SetPoint("RIGHT", -70, 0)
  f.gear = CreateFrame("Button", nil, f)
  f.gear:SetSize(24, 24)
  f.gear:SetPoint("TOPRIGHT", -36, -10)
  f.gear.icon = f.gear:CreateTexture(nil, "ARTWORK")
  f.gear.icon:SetSize(13, 13)
  f.gear.icon:SetPoint("CENTER")
  UI.SetIcon(f.gear.icon, "gear")
  f.gear.icon:SetVertexColor(rgba(T.muted))
  f.gear:SetScript("OnClick", function() ns.app:Open("planner") end)
  UI.Tooltip(f.gear, "Planner", "The route, its costs and the guide's settings.")
  f.sub = text(f, T.fontSmall + 1, T.muted)
  f.sub:SetPoint("TOPLEFT", PAD + 2, -40)
  f.sub:SetPoint("RIGHT", -PAD, 0)
  f.bar = ns.widgets.SkillBar(f, W - 2 * PAD - 4, T, 8)
  f.bar:SetPoint("TOPLEFT", PAD + 2, -58)

  -- the current step card
  f.card = CreateFrame("Frame", nil, f)
  f.card:SetPoint("TOPLEFT", PAD, -86)
  f.card:SetPoint("RIGHT", -PAD, 0)
  f.card:SetHeight(92)
  f.card.fill, f.card.edge = U.RoundBox(f.card, 6, T.card, T.divider)
  f.card.icon = f.card:CreateTexture(nil, "ARTWORK")
  f.card.icon:SetSize(30, 30)
  f.card.icon:SetPoint("TOPLEFT", 10, -10)
  f.card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.card.name = text(f.card, T.font + 1, T.text)
  f.card.name:SetPoint("TOPLEFT", f.card.icon, "TOPRIGHT", 8, -1)
  f.card.name:SetPoint("RIGHT", -10, 0)
  f.card.info = text(f.card, T.fontSmall + 1, T.muted)
  f.card.info:SetPoint("TOPLEFT", f.card.name, "BOTTOMLEFT", 0, -4)
  f.card.info:SetPoint("RIGHT", -10, 0)
  f.card.bar = ns.widgets.SkillBar(f.card, W - 2 * PAD - 20, T, 6, true)
  f.card.bar:SetPoint("TOPLEFT", 10, -48)
  f.card.go = UI.Button(f.card, "Show recipe", function() local _, st = G.currentStep(); if st then G.select(st) end end, 120, "accent")
  f.card.go:SetHeight(22)
  f.card.go:SetPoint("BOTTOMRIGHT", -8, 8)
  UI.Tooltip(f.card.go, "Show recipe", "Selects this step's recipe in your profession window (opens it when the game allows). Then press the game's Create.")
  f.card.left = text(f.card, T.fontSmall + 1, T.text)
  f.card.left:SetPoint("LEFT", f.card, "BOTTOMLEFT", 10, 19)
  f.card.left:SetPoint("RIGHT", f.card.go, "LEFT", -8, 0)

  f.list = CreateFrame("Frame", nil, f)
  f.list:SetPoint("TOPLEFT", PAD, -188)
  f.list:SetPoint("RIGHT", -PAD, 0)
  f.rows = {}
  f.hint = text(f, T.fontSmall, T.muted)
  f.hint:SetPoint("BOTTOMLEFT", PAD + 2, 10)
  f.hint:SetPoint("RIGHT", -PAD - 150, 0)
  f.hint:SetText("Right-click a step: done / not done. Mouse wheel scrolls.")
  -- what is left to buy at the auction house, as a shopping list there (EverlookDB Auctions, else Auctionator)
  f.send = UI.Button(f, "Send to auction house", function() G.send() end, 146)
  f.send:SetHeight(20)
  U.SetFont(f.send.label, T.fontSmall)
  f.send:SetPoint("BOTTOMRIGHT", -PAD, 8)
  UI.Tooltip(f.send, "Send to auction house", "Puts what the route still needs from the auction house on a shopping list in EverlookDB Auctions (else Auctionator), with the amounts.")

  UI.CloseOnEscape(f)
  local pos = EverlookCraftDB and EverlookCraftDB.guidePos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40) end
  f:Hide()
  G.frame = f
  G.applyScale()
  return f
end

function G.applyScale()
  if G.frame then G.frame:SetScale(settings().guideScale or 1) end
end

function G.currentStep()
  local rt = route()
  if not rt then return nil end
  local skillNow = ns.plans.skillNow(rt.skill)
  local i, st = ns.plans.currentStep(rt, skillNow)
  return i, st, rt, skillNow
end

-- select a step's recipe in the profession window; say what to craft either way
function G.select(st)
  local rt = route()
  if not rt then return end
  local rec = ns.plans.recipe(rt.skill, st.spell)
  local name = rec and rec.name or ("spell " .. st.spell)
  local left = ns.plans.craftsLeft(rt, st, ns.plans.skillNow(rt.skill))
  local ok = false
  local TS = C_TradeSkillUI
  if TS and TS.OpenRecipe then ok = pcall(TS.OpenRecipe, st.spell) end
  if not ok and TS and TS.SetRecipeItemNameFilter and ProfessionsFrame and ProfessionsFrame:IsShown() then
    ok = pcall(TS.SetRecipeItemNameFilter, name)
  end
  ns.print(("craft %d x %s%s."):format(left, name, ok and "" or (" in your " .. ns.profName(rt.skill) .. " window")))
end

function G.render()
  local f = G.frame
  if not f or not f:IsShown() then return end
  local rt = route()
  if not rt then
    f.title:SetText("Skill-up guide")
    f.sub:SetText("No route yet: /ecraft plan")
    f.card:Hide()
    for _, r in ipairs(f.rows) do r:Hide() end
    f:SetHeight(120)
    return
  end
  local skillNow = ns.plans.skillNow(rt.skill)
  f.title:SetText(ns.profName(rt.skill) .. " guide")
  local ci, cst = ns.plans.currentStep(rt, skillNow)
  f.sub:SetText(("Skill %s / %d  \194\183  %s"):format(skillNow or "?", rt.to,
    ci and ("step %d of %d"):format(ci, #rt.steps) or (rt.stall and "route stops at " .. rt.stall or "done!")))
  f.bar:Set(skillNow or rt.from, 0, rt.to)

  -- the current step
  local card = f.card
  if cst then
    card:Show()
    local rec = ns.plans.recipe(rt.skill, cst.spell)
    card.icon:SetTexture(ns.recipeIcon(rec))
    card.name:SetText(rec and rec.name or "?")
    local s = math.max(cst.from, skillNow or cst.from)
    local chance = rec and ns.planner.chance(rec, s) or 0
    local cname = rec and ns.colorAt(rec, s) or "gray"
    card.info:SetText(("%d\226\128\147%d  \194\183  %s%d%% skill-up now (%s)|r%s"):format(cst.from, cst.to, ns.widgets.colorCode(cname),
      math.floor(chance * 100 + 0.5), cname, rec and not rec.learnKnown and "  \194\183  learn ~" .. rec.learn or ""))
    card.bar:Set(s, cst.from, cst.to)
    local n, n90 = ns.plans.craftsLeft(rt, cst, skillNow)
    card.left:SetText((n90 > n and settings().buffer) and ("~%d crafts left, buy for %d to be safe"):format(n, n90) or ("~%d crafts left"):format(n))
  else
    card:Hide()
  end

  local rows = G.rows(rt, skillNow)
  local max = settings().guideRows or 18
  G.offset = math.max(0, math.min(G.offset, #rows - max))
  local top = cst and -188 or -86
  f.list:ClearAllPoints()
  f.list:SetPoint("TOPLEFT", PAD, top)
  f.list:SetPoint("RIGHT", -PAD, 0)
  local shown = math.min(max, #rows)
  for i = 1, shown do
    local r = f.rows[i] or makeRow(f, i)
    f.rows[i] = r
    paintRow(r, rows[i + G.offset], rt, skillNow)
    r:Show()
  end
  for i = shown + 1, #f.rows do f.rows[i]:Hide() end
  f.list:SetHeight(shown * ROW)
  f:SetHeight(-top + shown * ROW + 38)
  local items = G.shop and ns.plans.auctionItems(G.shop) or {}
  f.send:SetShown(ns.craftList.shoppingTarget() ~= nil)
  f.send:SetUsable(#items > 0)
end

function G.open(skill)
  if skill then G.skill = skill end
  local f = makeFrame()
  f:Show()
  G.render()
end

function G.toggle()
  local f = makeFrame()
  if f:IsShown() then f:Hide() else G.open() end
end

-- keep it live: skill-ups, bags, scans
local function live()
  if G.frame and G.frame:IsShown() then G.render() end
end
local prevSkills, prevStock, prevRoute = ns.onSkills, ns.onStock, ns.onRoute
ns.onSkills = function() if prevSkills then prevSkills() end live() end
ns.onStock = function() if prevStock then prevStock() end live() end
ns.onRoute = function(skill) if prevRoute then prevRoute(skill) end G.skill = skill; live() end
local prevScanned = ns.onScanned
ns.onScanned = function(skill)
  if prevScanned then prevScanned(skill) end
  if settings().autoGuide and ns.plans.saved(skill) and not (G.frame and G.frame:IsShown()) then G.open(skill) end
  live()
end
ns.on("CHAT_MSG_SKILL", function()
  if not EverlookCraftDB then return end
  C_Timer.After(0.2, function() ns.scan.updateSkills(); live() end)
end)
-- a merchant opens or closes (the Buy buttons), a recipe is learned at a trainer (the Learn rows tick)
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED" }) do
  ns.on(e, function() if C_Timer and C_Timer.After then C_Timer.After(0.5, live) end end)
end
