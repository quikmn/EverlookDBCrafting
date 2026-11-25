-- The recipe browser: every recipe of a profession, learned or not, in its own window. Professions along the top,
-- filters (all, known, not known, favourites), a search box that finds a recipe by its name or a reagent's; the list on
-- the left (a quality edge, the learn skill, marks for you and your other characters, a star); the chosen recipe on the
-- right: its skill colours and your chance now, what you can make with your bags, each reagent with where it comes from
-- (Map to the nearest vendor), how to learn it ("source unknown" said plainly), and which of your characters know it.
-- One filled button: add it to the crafting queue.
local _, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba

local BW = { skill = nil, query = "", filter = "all" }
ns.browserWindow = BW

local LIST_W, ROW_H = 330, 40
local FILTERS = { { "all", "All", 44 }, { "known", "Known", 58 }, { "unknown", "Not known", 76 }, { "favs", "Favourites", 82 } }

local f, T

local function mineFirst()
  local me = ns.me()
  local out = {}
  for _, p in ipairs(ns.professionList()) do
    if #(ns.recipes(p.id) or {}) > 0 then
      out[#out + 1] = { id = p.id, name = p.name, mine = me and me.profs[p.id] and me.profs[p.id].rank and true or false }
    end
  end
  table.sort(out, function(x, y)
    if x.mine ~= y.mine then return x.mine end
    return x.name < y.name
  end)
  return out
end

-- the profession shown: the one picked, else the planner's last, else your highest, else Tailoring
function BW.selectedSkill()
  if BW.skill and ns.DATA.profs[BW.skill] then return BW.skill end
  local last = EverlookCraftChar and EverlookCraftChar.lastSkill
  local me = ns.me()
  if last and me and me.profs[last] and #(ns.recipes(last) or {}) > 0 then BW.skill = last return last end
  local best, bestRank
  for id, p in pairs(me and me.profs or {}) do
    if p.rank and #(ns.recipes(id) or {}) > 0 and (not bestRank or p.rank > bestRank) then best, bestRank = id, p.rank end
  end
  BW.skill = best or 197
  return BW.skill
end

-- the profession with the most recipes matching a search (yours first on a tie); nil when none matches
function BW.bestSkillFor(query)
  local best, bestN, bestMine
  for _, p in ipairs(mineFirst()) do
    local n = #ns.browser.list(p.id, query, "all", ns.settings().otherSide)
    if n > 0 and (not bestN or n > bestN or (n == bestN and p.mine and not bestMine)) then best, bestN, bestMine = p.id, n, p.mine end
  end
  return best
end

function BW.items()
  return ns.browser.list(BW.selectedSkill(), BW.query, BW.filter, ns.settings().otherSide)
end

---------------------------------------------------------------------------------------------------------------------
-- The list

local function buildRow(list, i)
  local r = ns.widgets.RowCard(list, T)
  r.edge = U.Solid(r, "ARTWORK", 1, 1, 1, 1)
  r.edge:SetWidth(2)
  r.edge:SetPoint("TOPLEFT", 0, -4)
  r.edge:SetPoint("BOTTOMLEFT", 0, 4)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(24, 24)
  r.icon:SetPoint("LEFT", 10, 0)
  r.learn = UI.Text(r, T.fontSmall + 1, T.muted)
  r.learn:SetPoint("TOPRIGHT", -10, -7)
  r.learn:SetJustifyH("RIGHT")
  r.learn:SetWordWrap(false)
  r.name = UI.Text(r, T.font, T.text)
  r.name:SetPoint("TOPLEFT", 42, -6)
  r.name:SetPoint("RIGHT", r.learn, "LEFT", -6, 0)
  r.name:SetWordWrap(false)
  r.marks = UI.Text(r, T.fontSmall + 1, T.muted)
  r.marks:SetPoint("BOTTOMRIGHT", -10, 7)
  r.marks:SetJustifyH("RIGHT")
  r.marks:SetWordWrap(false)
  r.detail = UI.Text(r, T.fontSmall + 1, T.muted)
  r.detail:SetPoint("BOTTOMLEFT", 42, 7)
  r.detail:SetPoint("RIGHT", r.marks, "LEFT", -6, 0)
  r.detail:SetWordWrap(false)
  r:SetScript("OnClick", function(self, button)
    local e = self.item
    if not e then return end
    if IsShiftKeyDown() then ns.browser.link(e.r) return end
    if button == "RightButton" then
      ns.browser.toggleFav(e.r.spell)
      BW.render()
      return
    end
    BW.selected = e.r.spell
    BW.render()
  end)
  r:HookScript("OnEnter", function(self)
    local e = self.item
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.r.creates and e.r.creates ~= 0 then pcall(GameTooltip.SetItemByID, GameTooltip, e.r.creates) else GameTooltip:AddLine(e.r.name, 1, 1, 1) end
    GameTooltip:AddLine("Click: details. Right-click: favourite. Shift-click: link it.", 0.55, 0.58, 0.64, true)
    GameTooltip:Show()
  end)
  r:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function hexColor(name) return ns.widgets.colorCode(name) end

local function paintRow(r, e)
  local rec = e.r
  local _, _, q = ns.itemInfo(rec.creates or 0)
  q = rec.creates and rec.creates ~= 0 and q or 1
  local c = ns.qualityColor(q)
  -- a quality edge for green and better; plain white items get none
  r.edge:SetShown(q >= 2)
  r.edge:SetVertexColor(tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255, 0.85)
  ns.widgets.SetAnyIcon(r.icon, ns.recipeIcon(rec), T)
  r.icon:SetDesaturated(not e.known)
  r.name:SetText(("|cff%s%s|r"):format(c, rec.name))
  local skillNow = ns.plans.skillNow(rec.skill)
  local col = skillNow and hexColor(ns.colorAt(rec, skillNow)) or "|cffe8eaef"
  if skillNow and skillNow < rec.learn then col = "|cffef5d5d" end
  r.learn:SetText(("%s%s%d|r"):format(col, rec.learnKnown and "" or "~", rec.learn))
  local how = ns.browser.learnShort(rec)
  r.detail:SetText(e.byReagent and ("%s  \194\183  |cff5aa9ffreagent match|r"):format(how) or how)
  local marks = {}
  if e.known then marks[#marks + 1] = "|cff62cf88you|r" end
  local alts = ns.browser.altsKnowing(rec)
  if #alts > 0 then marks[#marks + 1] = ("|cff5aa9ff%s|r"):format(#alts == 1 and alts[1] or (#alts .. " alts")) end
  if ns.browser.isFav(rec.spell) then marks[#marks + 1] = "|cffffd100\226\152\133|r" end
  r.marks:SetText(table.concat(marks, "  "))
  r:SetSelected(BW.selected == rec.spell)
end

---------------------------------------------------------------------------------------------------------------------
-- The detail pane: built again for each recipe from a pool of lines

local pane

local function poolGet(kind, make)
  pane.pools[kind] = pane.pools[kind] or { used = 0 }
  local p = pane.pools[kind]
  p.used = p.used + 1
  local x = p[p.used]
  if not x then x = make(); p[p.used] = x end
  x:Show()
  return x
end

local function newText()
  local h = CreateFrame("Frame", nil, pane.child)
  h.text = UI.Text(h, T.font, T.text)
  h.text:SetPoint("TOPLEFT")
  h.text:SetPoint("RIGHT")
  return h
end

-- a line: an optional line icon, wrapped text, an optional Map button
local function newLine()
  local l = CreateFrame("Frame", nil, pane.child)
  l.icon = l:CreateTexture(nil, "ARTWORK")
  l.icon:SetSize(12, 12)
  l.icon:SetPoint("TOPLEFT", 0, -2)
  l.text = UI.Text(l, T.fontSmall + 1, T.text)
  l.text:SetPoint("TOPLEFT", 20, -1)
  l.map = ns.widgets.SmallButton(l, "Map", function(self)
    if self.pin then ns.map.pin(self.pin) else ns.widgets.MapTo(self.npcs) end
  end, 46)
  l.map:SetPoint("TOPRIGHT", 0, 1)
  return l
end

local function newCard()
  local c = CreateFrame("Frame", nil, pane.child)
  c.bg = U.Round(c, 6, "BACKGROUND")
  c.bg:SetAllPoints(c)
  c.bg:SetVertexColor(rgba(T.surface))
  return c
end

local function newIcon()
  local i = CreateFrame("Frame", nil, pane.child)
  i.tex = i:CreateTexture(nil, "ARTWORK")
  i.tex:SetAllPoints(i)
  return i
end

local function heading(y, text, done)
  local h = poolGet("text", newText)
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 2, -y)
  h:SetPoint("RIGHT", pane.child, "RIGHT", 0, 0)
  h:SetHeight(14)
  U.SetFont(h.text, T.fontSmall + 1)
  h.text:SetTextColor(rgba(done and T.ok or T.gold))
  h.text:SetText(text:upper())
  return y + 22
end

-- a line at y, x from the left; returns the y under it
local function line(y, x, l0, right)
  local l = poolGet("line", newLine)
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", pane.child, "TOPLEFT", x, -y)
  l:SetPoint("RIGHT", pane.child, "RIGHT", -(right or 0), 0)
  if l0.icon and UI.SetIcon(l.icon, l0.icon) then
    l.icon:SetVertexColor(rgba(l0.warn and T.danger or T.muted))
  else
    l.icon:Hide()
  end
  l.text:SetTextColor(rgba(l0.warn and T.muted or T.text))
  l.map.npcs, l.map.pin = l0.npcs, l0.pin
  local mappable = l0.npcs ~= nil or l0.pin ~= nil
  l.map:SetShown(mappable)
  l.text:ClearAllPoints()
  l.text:SetPoint("TOPLEFT", 20, -1)
  l.text:SetPoint("RIGHT", l, "RIGHT", mappable and -54 or 0, 0)
  l.text:SetText(l0.text)
  local h = math.max(16, math.ceil(l.text:GetStringHeight() or 14) + 2, mappable and 22 or 0)
  l:SetHeight(h)
  return y + h + 4
end

function BW.renderDetail()
  if not pane then return end
  for _, p in pairs(pane.pools) do
    for i = 1, #p do p[i]:Hide() end
    p.used = 0
  end
  local W = pane.child:GetWidth()
  local r = BW.selected and ns.recipeBySpell(BW.selected)
  if not r then
    local t = poolGet("text", newText)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 4, -8)
    t:SetPoint("RIGHT", pane.child, "RIGHT", -4, 0)
    U.SetFont(t.text, T.font)
    t.text:SetTextColor(rgba(T.muted))
    t.text:SetText("Pick a recipe on the left to see its reagents, where they come from, how to learn it and who of your characters knows it.")
    t:SetHeight(40)
    pane.child:SetHeight(60)
    BW.paintPrimary(nil)
    return
  end
  local side = ns.side()

  -- the head card: icon, name, colours, your chance now
  local card = poolGet("card", newCard)
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 0, 0)
  card:SetPoint("RIGHT", pane.child, "RIGHT", 0, 0)
  local icon = poolGet("icon", newIcon)
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 12, -12)
  icon:SetSize(36, 36)
  ns.widgets.SetAnyIcon(icon.tex, ns.recipeIcon(r), T)
  icon:SetFrameLevel(card:GetFrameLevel() + 2)
  local _, _, q = ns.itemInfo(r.creates or 0)
  local title = poolGet("text", newText)
  title:ClearAllPoints()
  title:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 58, -12)
  title:SetPoint("RIGHT", pane.child, "RIGHT", -12, 0)
  title:SetHeight(18)
  U.SetFont(title.text, T.fontTitle + 1)
  title.text:SetTextColor(rgba(T.text))
  title.text:SetWordWrap(false)
  title.text:SetText(("|cff%s%s|r"):format(ns.qualityColor(r.creates and r.creates ~= 0 and q or 1), r.name))
  title:SetFrameLevel(card:GetFrameLevel() + 2)
  local sub = poolGet("text", newText)
  sub:ClearAllPoints()
  sub:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 58, -34)
  sub:SetPoint("RIGHT", pane.child, "RIGHT", -12, 0)
  sub:SetHeight(14)
  U.SetFont(sub.text, T.fontSmall + 1)
  sub.text:SetTextColor(rgba(T.muted))
  sub.text:SetWordWrap(false)
  local est = r.learnKnown and "" or "~"
  sub.text:SetText(("%s  \194\183  makes %d  \194\183  |cffff8040%s|r  |cffffff00%d|r  |cff40c040%d|r  |cff808080%d|r"):format(
    ns.profName(r.skill), r.yield or 1, ns.browser.learnText(r), r.yellow, r.green, r.gray))
  sub:SetFrameLevel(card:GetFrameLevel() + 2)
  local skillNow = ns.plans.skillNow(r.skill)
  local known = ns.browser.knownByMe(r)
  local status = poolGet("text", newText)
  status:ClearAllPoints()
  status:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 12, -58)
  status:SetPoint("RIGHT", pane.child, "RIGHT", -12, 0)
  U.SetFont(status.text, T.fontSmall + 1)
  status.text:SetTextColor(rgba(T.text))
  status.text:SetWordWrap(true)
  local parts = {}
  if skillNow then
    if skillNow < r.learn then
      parts[#parts + 1] = ("Your skill %d: |cffef5d5dneeds %s%d to learn|r"):format(skillNow, est, r.learn)
    else
      local cname = ns.colorAt(r, skillNow)
      local ch = ns.planner.chance(r, skillNow)
      parts[#parts + 1] = ("Your skill %d: %s%s, %d%% skill-up per craft|r"):format(skillNow, hexColor(cname), cname, math.floor(ch * 100 + 0.5))
    end
  else
    parts[#parts + 1] = ("|cff8d94a3You don't have %s (or haven't opened its window yet).|r"):format(ns.profName(r.skill))
  end
  if known then parts[#parts + 1] = ("you know it, %d with your bags now"):format(ns.browser.canMake(r))
  else parts[#parts + 1] = "|cff8d94a3not learned|r" end
  local tools = ns.browser.toolsText(r)
  if tools then parts[#parts + 1] = "needs " .. tools end
  status.text:SetText(table.concat(parts, "  \194\183  "))
  status:SetHeight(math.ceil(status.text:GetStringHeight() or 14) + 2)
  status:SetFrameLevel(card:GetFrameLevel() + 2)
  local cardH = 58 + status:GetHeight() + 12
  if not r.learnKnown then
    local note = poolGet("text", newText)
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 12, -cardH + 4)
    note:SetPoint("RIGHT", pane.child, "RIGHT", -12, 0)
    U.SetFont(note.text, T.fontSmall)
    note.text:SetTextColor(rgba(T.muted))
    note.text:SetWordWrap(true)
    note.text:SetText("~ the learn skill is an estimate: no trainer window has confirmed it yet.")
    note:SetHeight(math.ceil(note.text:GetStringHeight() or 12) + 2)
    note:SetFrameLevel(card:GetFrameLevel() + 2)
    cardH = cardH + note:GetHeight() + 4
  end
  card:SetHeight(cardH)
  local y = cardH + 16

  -- reagents
  local mats, fixed = ns.matsOf(r)
  y = heading(y, fixed and "Reagents (as the server's window showed them)" or "Reagents")
  for _, m in ipairs(mats) do
    local name, ico, mq = ns.itemInfo(m[1])
    local have = ns.stock.usable(m[1])
    local mi = poolGet("icon", newIcon)
    mi:ClearAllPoints()
    mi:SetPoint("TOPLEFT", pane.child, "TOPLEFT", 2, -y)
    mi:SetSize(18, 18)
    ns.widgets.SetAnyIcon(mi.tex, ico, T)
    local where = ns.craftList.whereText(m[1])
    y = line(y, 26, { text = ("%d x |cff%s%s|r   %s"):format(m[2], ns.qualityColor(mq), name,
      have >= m[2] and ("|cff62cf88have %d|r"):format(have) or ("|cff8d94a3have %d|r"):format(have)) .. (where ~= "" and ("  |cff8d94a3(" .. where .. ")|r") or "") })
    for _, l0 in ipairs(ns.browser.reagentLines(m[1], side)) do y = line(y - 2, 38, l0) end
    y = y + 6
  end
  if #mats == 0 then y = line(y, 2, { text = "No reagents in the data.", warn = true }) end

  -- how to learn it
  y = heading(y + 6, "How to learn it", known)
  for _, l0 in ipairs(ns.browser.learnLines(r, side)) do y = line(y, 2, l0) end

  -- who knows it
  local who = ns.scan.knownBy(r.spell)
  y = heading(y + 8, "Your characters who know it")
  y = line(y, 2, { text = #who > 0 and table.concat(who, ", ") or "None of your characters yet (each character's profession window must be opened once).", icon = "user", warn = #who == 0 })
  pane.child:SetHeight(y + 10)
  pane:UpdateBar()
  BW.paintPrimary(r)
end

function BW.paintPrimary(r)
  local p = f and f.primary
  if not p then return end
  local e = r and ns.craftList.find(r.spell)
  p:SetText(e and ("In the queue (x%d): add 1"):format(e.n) or "Add to queue")
  p:SetUsable(r ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- The window

local function make()
  if f then return f end
  f = ns.widgets.Window({ name = "EverlookCraftBrowser", posKey = "browser", title = "Recipes", icon = "book",
    width = 860, height = 600, minWidth = 760, minHeight = 420, point = "CENTER", x = 120, y = 20,
    hint = "Right-click: favourite. Shift-click: link in chat. ~ marks an estimated learn skill." })
  T = f.T

  -- professions (icons) and filters
  f.profs = {}
  local x = 0
  for i, p in ipairs(mineFirst()) do
    local b = CreateFrame("Button", nil, f.body)
    b:SetSize(28, 28)
    b:SetPoint("TOPLEFT", f.body, "TOPLEFT", x, 0)
    b.bg, b.edge = U.RoundBox(b, 5, T.surface, T.border)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(ns.profIcon(p.id))
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.skill = p.id
    b:SetScript("OnClick", function(self) BW.skill, BW.selected = self.skill, nil; BW.render() end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(ns.profName(self.skill), 1, 1, 1)
      local rank = ns.plans.skillNow(self.skill)
      GameTooltip:AddLine(rank and ("Your skill: %d"):format(rank) or "Not one of yours", 0.55, 0.58, 0.64)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.profs[i] = b
    x = x + 32
  end
  f.filters = {}
  local fx = 0
  for i = #FILTERS, 1, -1 do
    local d = FILTERS[i]
    local c = ns.widgets.Chip(f.body, d[2], function() BW.filter = d[1]; BW.render() end, d[3])
    c:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", -fx, -3)
    fx = fx + d[3] + 6
    c.value = d[1]
    f.filters[i] = c
  end

  -- search
  f.search = UI.EditBox(f.body, LIST_W, 26)
  f.search:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -40)
  f.search:SetTextInsets(26, 8, 0, 0)
  f.search.icon = ns.widgets.LineIcon(f.search, "search", 12, T.muted, "OVERLAY")
  f.search.icon:SetPoint("LEFT", 9, 0)
  f.search.hintText = UI.Text(f.search, T.font, T.muted)
  f.search.hintText:SetPoint("LEFT", 26, 0)
  f.search.hintText:SetText("Search a recipe or a reagent")
  f.search:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    self.hintText:SetShown(t == "")
    if t ~= BW.query then BW.query = t; BW.renderList() end
  end)
  f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  -- the list
  f.count = UI.Text(f.body, T.fontSmall, T.muted)
  f.count:SetPoint("TOPLEFT", f.body, "TOPLEFT", 2, -74)
  f.list = ns.widgets.VList(f.body, T, ROW_H, buildRow, paintRow, 3, "")
  f.list:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -90)
  f.list:SetPoint("BOTTOM", f.body, "BOTTOM", 0, 0)
  f.list:SetWidth(LIST_W)
  f.list.empty:SetWordWrap(true)
  f.list.emptyFn = function()
    if BW.query ~= "" then
      local other = BW.bestSkillFor(BW.query)
      if other and other ~= BW.selectedSkill() then
        return ("No %s recipe or reagent matches \"%s\". %s has some: pick it above."):format(ns.profName(BW.selectedSkill()), BW.query, ns.profName(other))
      end
      return ("No recipe or reagent matches \"%s\"."):format(BW.query)
    end
    if BW.filter == "favs" then return "No favourites yet: right-click a recipe to star it." end
    if BW.filter == "known" then return "You know none of these yet, or haven't opened this profession's window on this character." end
    return "No recipes."
  end

  -- the detail pane
  local holder = CreateFrame("Frame", nil, f.body)
  holder:SetPoint("TOPLEFT", f.body, "TOPLEFT", LIST_W + 18, -40)
  holder:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, 0)
  holder.eluiTheme = T
  pane = UI.ScrollPage(holder)
  pane.pools = {}
  pane.child:SetWidth(math.max(200, (f:GetWidth() or 860) - 32 - LIST_W - 18 - 18))
  f.pane = pane

  f:SetPrimary("Add to queue", function()
    local r = BW.selected and ns.recipeBySpell(BW.selected)
    if not r then return end
    ns.craftList.add(r.spell, 1)
    local e = ns.craftList.find(r.spell)
    ns.print(("%s: %d in the crafting queue."):format(r.name, e and e.n or 1))
    if ns.listWindow then ns.listWindow.open() end
    BW.paintPrimary(r)
  end, 190)
  f:SetScript("OnShow", function() BW.render() end)
  f:SetScript("OnSizeChanged", function()
    if not f:IsShown() then return end
    pane.child:SetWidth(math.max(200, f:GetWidth() - 32 - LIST_W - 18 - 18))
    f.list:Render()
    BW.renderDetail()
  end)
  return f
end

function BW.renderList()
  if not f or not f:IsShown() then return end
  local items = BW.items()
  local skill = BW.selectedSkill()
  local known = 0
  for _, r in ipairs(ns.recipes(skill) or {}) do if ns.browser.knownByMe(r) then known = known + 1 end end
  f.count:SetText(("%d shown  \194\183  you know %d of %d"):format(#items, known, #(ns.recipes(skill) or {})))
  f.list:SetItems(items)
end

function BW.render()
  if not f or not f:IsShown() then return end
  local skill = BW.selectedSkill()
  local rank = ns.plans.skillNow(skill)
  f.title:SetText(("Recipes: %s"):format(ns.profName(skill)))
  f.sub:SetText(rank and ("Your skill %d. Every recipe, learned or not, with where its reagents come from."):format(rank)
    or "Every recipe, learned or not, with where its reagents come from and how to learn it.")
  for _, b in ipairs(f.profs) do
    local on = b.skill == skill
    b.bg:SetVertexColor(rgba(on and ns.widgets.mix(T.surface, T.accent, 0.16) or T.surface))
    b.edge:SetColor(rgba(on and T.accent or T.border))
    b.icon:SetDesaturated(not on)
    b.icon:SetAlpha(on and 1 or 0.7)
  end
  for _, c in ipairs(f.filters) do c:SetActive(c.value == BW.filter) end
  local offset = f.list.offset
  BW.renderList()
  f.list.offset = offset
  f.list:Render()
  BW.renderDetail()
end

-- open, optionally at a profession and with a search
function BW.open(skill, query)
  make()
  if skill then BW.skill, BW.selected = skill, nil end
  if query then
    BW.query = query
    f.search:SetText(query)
    -- a search from chat goes to the profession that has the most matches
    if not skill and query ~= "" then
      local best = BW.bestSkillFor(query)
      if best then BW.skill, BW.selected = best, nil end
    end
  end
  f:Show()
  BW.render()
end

function BW.toggle()
  if f and f:IsShown() then f:Hide() else BW.open() end
end

-- show one recipe (selected, its profession picked, the list scrolled to it)
function BW.show(spell)
  local r = ns.recipeBySpell(spell)
  if not r then return false end
  BW.filter, BW.query = "all", ""
  BW.open(r.skill, "")
  BW.selected = r.spell
  for i, e in ipairs(f.list.items) do if e.r.spell == r.spell then f.list:ScrollTo(i) break end end
  BW.render()
  return true
end

function BW.applyScale() if f then f:SetScale(ns.settings().windowScale or 1) end end

local prevList, prevStock, prevScanned = ns.onList, ns.onStock, ns.onScanned
ns.onList = function() if prevList then prevList() end if f and f:IsShown() then BW.paintPrimary(BW.selected and ns.recipeBySpell(BW.selected)) end end
ns.onStock = function() if prevStock then prevStock() end if f and f:IsShown() then BW.render() end end
ns.onScanned = function(skill) if prevScanned then prevScanned(skill) end if f and f:IsShown() then BW.render() end end
