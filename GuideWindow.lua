-- The Skill-Up guide: a small movable checklist that walks your route. The current step on top (its live skill bar,
-- the chance of a skill-up now in the recipe's colour, crafts left), then: what to buy at the auction house, what
-- to buy from vendors (Map: the nearest one for your side), what to make first, the materials still needed (shrinks as
-- you craft), and every step. A section ticks green when it is done; right-click a step to mark it done or not.
-- Crafting stays with the game: "Show recipe" selects the step's recipe in your profession window.
local _, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba
local try = ns.try

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

-- the rows of the checklist: { kind = "head" | "item" | "step" | "train" | "note", ... }
function G.rows(rt, skillNow)
  local rows = {}
  if not rt then return rows end
  local need = ns.plans.remaining(rt, skillNow)
  local makes = {}
  for _, c in ipairs(rt.crafted or {}) do makes[c.id] = c end
  local ah, vendor, made, all = {}, {}, {}, {}
  for id, n in pairs(need) do
    local have = ns.stock.usable(id)
    local e = { kind = "item", id = id, need = n, have = have, short = math.max(0, n - have) }
    all[#all + 1] = e
    if makes[id] then
      made[#made + 1] = e
    elseif e.short > 0 then
      if ns.prices.vendor(id) then vendor[#vendor + 1] = e else ah[#ah + 1] = e end
    end
  end
  local byName = function(x, y) return (ns.itemInfo(x.id)) < (ns.itemInfo(y.id)) end
  table.sort(ah, byName); table.sort(vendor, byName); table.sort(made, byName); table.sort(all, byName)

  local function section(title, list, emptyText, mode)
    local done = true
    for _, e in ipairs(list) do
      if mode == "have" then
        if e.have < e.need then done = false end
      else
        done = false
      end
    end
    rows[#rows + 1] = { kind = "head", text = title, done = done }
    if #list == 0 then rows[#rows + 1] = { kind = "note", text = emptyText } end
    for _, e in ipairs(list) do
      local copy = {}
      for k, v in pairs(e) do copy[k] = v end
      copy.mode = mode
      rows[#rows + 1] = copy
    end
  end
  section("Buy at the auction house", ah, "Nothing: you have it all.", "ah")
  section("Buy from vendors", vendor, "Nothing: you have it all.", "vendor")
  if #made > 0 then section("Make first", made, "", "make") end
  section("Materials still needed", all, "None: the route is done.", "have")

  -- the steps, with the rank trainings where they fall
  local done = EverlookCraftChar.done[rt.skill] or {}
  local allDone = true
  local cur = ns.plans.currentStep(rt, skillNow)
  local stepRows = {}
  local trs, ti = rt.trainings or {}, 1
  for i, st in ipairs(rt.steps) do
    while trs[ti] and trs[ti].cap <= st.from do
      local tr = trs[ti]
      stepRows[#stepRows + 1] = { kind = "train", tr = tr, passed = skillNow and skillNow > tr.cap or false }
      ti = ti + 1
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
  r.name = text(r, T.font, T.text)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
  r:SetScript("OnEnter", function(self)
    if self.row and (self.row.kind == "item" or self.row.kind == "step") then self.hl:Show() end
    local row = self.row
    if not row then return end
    if row.kind == "item" then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      pcall(GameTooltip.SetItemByID, GameTooltip, row.id)
      local h = ns.stock.have(row.id)
      GameTooltip:AddLine(("Need %d: %d in bags, %d in bank, %d on other characters"):format(row.need, h.bags, h.bank, h.alts), 1, 0.82, 0)
      for k, c in ipairs(h.byChar) do if k <= 4 then GameTooltip:AddLine(("  %d on %s"):format(c.n, c.name), 0.7, 0.7, 0.7) end end
      local p, how, src = ns.prices.unit(row.id)
      GameTooltip:AddLine(p and ("%s each (%s)"):format(ns.money(p), how == "vendor" and "vendor" or src) or "No price yet", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    elseif row.kind == "step" then
      local lines = ns.options.rowTooltip({ kind = "step", st = row.st }, skillOf())
      if lines then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        for li, l in ipairs(lines) do if li == 1 then GameTooltip:AddLine(l, 1, 1, 1) else GameTooltip:AddLine(l, nil, nil, nil, true) end end
        GameTooltip:AddLine("Click: show it in your profession window. Right-click: done / not done.", 0.55, 0.58, 0.64, true)
        GameTooltip:Show()
      end
    end
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self, button)
    local row = self.row
    if not row or row.kind ~= "step" then return end
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

local function paintRow(r, row, rt, skillNow)
  r.row = row
  r.map:Hide()
  r.map.npcs = nil
  r.tick:Hide()
  r.icon:Show()
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
    r.name:SetText(("|cff%s%s|r"):format(ns.qualityColor(q), name))
    if row.mode == "have" or row.mode == "make" then
      local ok = row.have >= row.need
      r.right:SetText(("%s%d / %d|r"):format(ok and "|cff62cf88" or "|cffe8eaef", math.min(row.have, row.need), row.need))
      r.tick:SetShown(ok)
      r.tick:SetVertexColor(rgba(T.ok))
      if row.mode == "make" then r.name:SetText(("Make %s"):format(r.name:GetText())) end
    else
      local p = ns.prices.unit(row.id)
      r.right:SetText(("x%d  %s"):format(row.short, p and ns.money(p * row.short) or ns.money(nil)))
      if row.mode == "vendor" then
        local it = ns.DATA.items[row.id]
        if it and #it[7] > 0 then
          r.map.npcs = it[7]
          r.map:Show()
          r.right:ClearAllPoints()
          r.right:SetPoint("RIGHT", r.map, "LEFT", -6, 0)
        end
      end
    end
    return
  end
  if row.kind == "train" then
    local tr = row.tr
    UI.SetIcon(r.icon, "book")
    r.icon:SetVertexColor(rgba(T.gold))
    r.name:SetText(("Train %s at %d"):format(ns.DATA.rankNames[tr.step] or "the next rank", tr.at))
    r.name:SetTextColor(rgba(row.passed and T.muted or T.gold))
    r.right:SetText(ns.money(tr.fee))
    local npcs = ns.options.rowNpcs({ kind = "train", tr = tr }, rt.skill)
    if npcs and not row.passed then
      r.map.npcs = npcs
      r.map:Show()
      r.right:ClearAllPoints()
      r.right:SetPoint("RIGHT", r.map, "LEFT", -6, 0)
    end
    r.tick:SetShown(row.passed)
    r.tick:SetVertexColor(rgba(T.ok))
    return
  end
  -- a step
  local st = row.st
  local rec = ns.plans.recipe(rt.skill, st.spell)
  r.icon:SetVertexColor(1, 1, 1)
  r.icon:SetTexture(ns.recipeIcon(rec))
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local col = rec and ns.widgets.colorCode(ns.colorAt(rec, math.max(st.from, skillNow or 0))) or "|cffffffff"
  r.name:SetText(("%s%d|r  %s"):format(col, st.from, rec and rec.name or "?"))
  if row.done then r.name:SetTextColor(rgba(T.muted)) end
  local left = ns.plans.craftsLeft(rt, st, skillNow)
  r.right:SetText(row.done and "done" or ("x%d"):format(left))
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
  f.hint:SetPoint("RIGHT", -PAD, 0)
  f.hint:SetText("Right-click a step: done / not done. Mouse wheel scrolls.")

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
    card.left:SetText(n90 > n and ("%d crafts left (%d at 90%%)"):format(n, n90) or ("%d crafts left"):format(n))
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
  f:SetHeight(-top + shown * ROW + 34)
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
