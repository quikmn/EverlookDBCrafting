-- Small pieces for our windows on top of EverlookUI: cost tiles and the skill bar with the rank caps marked.
local _, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba

local W = {}
ns.widgets = W

-- A row of tiles: { { label, value } ... } in equal widths. tiles:Set(i, label, value[, note]).
function W.Tiles(parent, n, width, T)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 56)
  f.tiles = {}
  local gap = 8
  local w = math.floor((width - gap * (n - 1)) / n)
  for i = 1, n do
    local t = CreateFrame("Frame", nil, f)
    t:SetSize(w, 56)
    t:SetPoint("TOPLEFT", (i - 1) * (w + gap), 0)
    t.bg, t.edge = U.RoundBox(t, 6, T.surface, T.border)
    t.label = UI.Text(t, T.fontSmall, T.muted)
    t.label:SetPoint("TOPLEFT", 10, -9)
    t.label:SetPoint("RIGHT", -8, 0)
    t.label:SetWordWrap(false)
    t.value = UI.Text(t, T.fontTitle, T.text)
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -6)
    t.value:SetPoint("RIGHT", -8, 0)
    t.value:SetWordWrap(false)
    f.tiles[i] = t
  end
  function f:Set(i, label, value, tip)
    local t = self.tiles[i]
    t.label:SetText(label)
    t.value:SetText(value)
    t.tip = tip
  end
  for _, t in ipairs(f.tiles) do
    t:EnableMouse(true)
    t:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.label:GetText(), 1, 1, 1)
      GameTooltip:AddLine(self.tip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return f
end

-- The skill bar: 0 to `max`, filled to `value`, with thin marks at the rank caps (75, 150, 225) and labels under it.
function W.SkillBar(parent, width, T, height, bare)
  local f = CreateFrame("Frame", nil, parent)
  height = height or 10
  f:SetSize(width, height + 14)
  f.track = U.Round(f, height / 2, "BACKGROUND")
  f.track:SetPoint("TOPLEFT", 0, 0)
  f.track:SetSize(width, height)
  f.track:SetVertexColor(rgba(T.surface))
  f.fill = U.Round(f, height / 2, "ARTWORK")
  f.fill:SetPoint("TOPLEFT", 0, 0)
  f.fill:SetSize(1, height)
  f.fill:SetVertexColor(rgba(T.accentFill or T.accent))
  f.marks, f.labels = {}, {}
  for i, cap in ipairs({ 75, 150, 225 }) do
    local m = U.Solid(f, "OVERLAY", rgba(T.bg))
    m:SetSize(2, height)
    f.marks[i] = m
    local l = UI.Text(f, T.fontSmall, T.muted)
    l:SetText(tostring(cap))
    f.labels[i] = l
  end
  f.lo = UI.Text(f, T.fontSmall, T.muted)
  f.lo:SetPoint("TOPLEFT", 0, -(height + 3))
  f.hi = UI.Text(f, T.fontSmall, T.muted, "OVERLAY")
  f.hi:SetPoint("TOPRIGHT", 0, -(height + 3))
  f.hi:SetJustifyH("RIGHT")
  function f:Set(value, lo, hi)
    lo, hi = lo or 0, math.max((lo or 0) + 1, hi or 300)
    local w = self:GetWidth()
    local frac = math.max(0, math.min(1, ((value or lo) - lo) / (hi - lo)))
    self.fill:SetWidth(math.max(1, w * frac))
    self.fill:SetShown(frac > 0)
    self.lo:SetText(bare and "" or tostring(lo))
    self.hi:SetText(bare and "" or tostring(hi))
    for i, cap in ipairs({ 75, 150, 225 }) do
      local inside = cap > lo and cap < hi
      local x = w * (cap - lo) / (hi - lo)
      self.marks[i]:ClearAllPoints()
      self.marks[i]:SetPoint("TOPLEFT", x - 1, 0)
      self.marks[i]:SetShown(inside)
      self.labels[i]:ClearAllPoints()
      self.labels[i]:SetPoint("TOP", self, "TOPLEFT", x, -(self.track:GetHeight() + 3))
      self.labels[i]:SetShown(not bare and inside and x > 30 and x < w - 30)
    end
  end
  return f
end

-- the colour of a recipe at a skill, as a text colour code
function W.colorCode(name)
  local c = ns.COLORS[name] or ns.COLORS.gray
  return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

---------------------------------------------------------------------------------------------------------------------
-- The house look for our own windows (the guide, the Crafting list, the recipe browser): dark slate, a thin blue line
-- along the top, a line icon and title with one muted line under it, row cards, plain buttons and one filled primary
-- button in the footer. Every window moves on its own, never closes another, and remembers its place and size.

function W.theme() return UI.MakeTheme(ns.ACCENT) end

-- a colour t of the way from a to b, opaque (a see-through fill would show the rim drawn under it)
function W.mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1 }
end

-- a small plain button (lists, cards)
function W.SmallButton(parent, label, onClick, width, style)
  local T = UI.ThemeOf(parent)
  local b = UI.Button(parent, label, onClick, width or 52, style)
  b:SetHeight(20)
  U.SetFont(b.label, T.fontSmall + 1)
  return b
end

-- a filter chip or tab: plain, and while active a blue rim and text (never filled: the one filled button is the primary)
function W.Chip(parent, label, onClick, width)
  local T = UI.ThemeOf(parent)
  local b = UI.Button(parent, label, onClick, width or 70)
  b:SetHeight(22)
  U.SetFont(b.label, T.fontSmall + 1)
  function b:SetActive(on)
    self.active = on
    self.bg:SetVertexColor(rgba(on and W.mix(T.surface, T.accent, 0.16) or T.surface))
    self.border:SetColor(rgba(on and T.accent or T.border))
    self.label:SetTextColor(rgba(on and T.text or T.muted))
  end
  b:HookScript("OnLeave", function(self) self:SetActive(self.active) end)
  b:SetActive(false)
  return b
end

-- a line icon ("map", "hammer") in a colour
function W.LineIcon(parent, name, size, color, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetSize(size or 14, size or 14)
  if UI.SetIcon(t, name) and color then t:SetVertexColor(rgba(color)) end
  return t
end

local function savePos(f)
  local d = EverlookCraftDB
  if not d or not f.posKey then return end
  d.windows = d.windows or {}
  local p, _, rp, x, y = f:GetPoint()
  d.windows[f.posKey] = { p, rp, x, y, math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
end

-- W.Window{ name, posKey, title, icon, width, height, minWidth, minHeight, hint, top } -> f with f.T, f.title, f.sub,
-- f.body (the area between header and footer), f.footer, f.hint and f:SetPrimary(label, onClick, width)
function W.Window(o)
  local T = W.theme()
  local f = CreateFrame("Frame", o.name, UIParent)
  f.eluiTheme, f.T, f.posKey = T, T, o.posKey
  f:SetSize(o.width, o.height)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetResizable(true)
  local minW, minH = o.minWidth or o.width, o.minHeight or 360
  if f.SetResizeBounds then f:SetResizeBounds(minW, minH) elseif f.SetMinResize then f:SetMinResize(minW, minH) end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
  UI.WindowChrome(f, T)
  f.close = UI.CloseButton(f, T)

  f.icon = W.LineIcon(f, o.icon or "hammer", 16, T.accent)
  f.icon:SetPoint("TOPLEFT", 18, -18)
  f.title = UI.Text(f, T.fontTitle + 2, T.text)
  f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  f.title:SetPoint("RIGHT", f, "RIGHT", -48, 0)
  f.title:SetWordWrap(false)
  f.title:SetText(o.title or "")
  f.sub = UI.Text(f, T.fontSmall + 1, T.muted)
  f.sub:SetPoint("TOPLEFT", 18, -40)
  f.sub:SetPoint("RIGHT", f, "RIGHT", -18, 0)
  f.sub:SetWordWrap(false)

  f.footer = CreateFrame("Frame", nil, f)
  f.footer:SetPoint("BOTTOMLEFT", 1, 1)
  f.footer:SetPoint("BOTTOMRIGHT", -1, 1)
  f.footer:SetHeight(46)
  local line = U.Solid(f.footer, "ARTWORK", rgba(T.divider))
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", 0, 0)
  f.hint = UI.Text(f.footer, T.fontSmall, T.muted)
  f.hint:SetPoint("LEFT", 18, 0)
  f.hint:SetPoint("RIGHT", f.footer, "RIGHT", -26, 0)
  f.hint:SetWordWrap(false)
  f.hint:SetText(o.hint or "")

  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 16, -(o.top or 62))
  f.body:SetPoint("BOTTOMRIGHT", -16, 46 + 10)

  function f:SetPrimary(label, onClick, width)
    if not self.primary then
      self.primary = UI.Button(self.footer, label, onClick, width or 170, "accent")
      self.primary:SetPoint("RIGHT", -26, 0)
      self.hint:SetPoint("RIGHT", self.primary, "LEFT", -12, 0)
    end
    self.primary:SetText(label)
    return self.primary
  end

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  for i = 0, 2 do
    for j = 0, i do
      local d = U.Solid(grip, "ARTWORK", T.muted[1], T.muted[2], T.muted[3], 0.5)
      d:SetSize(2, 2)
      d:SetPoint("BOTTOMRIGHT", -(2 + j * 4), 2 + (i - j) * 4)
    end
  end
  grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); savePos(f) end)
  f.grip = grip

  UI.CloseOnEscape(f)
  local pos = EverlookCraftDB and EverlookCraftDB.windows and EverlookCraftDB.windows[o.posKey]
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    if pos[5] and pos[6] then f:SetSize(math.max(minW, pos[5]), math.max(minH, pos[6])) end
  else
    f:SetPoint(o.point or "CENTER", UIParent, o.point or "CENTER", o.x or 0, o.y or 0)
  end
  f:SetScale(ns.settings().windowScale or 1)
  f:Hide()
  return f
end

-- A scrolling list of same-height rows that only builds the rows it shows. build(list, i) -> row;
-- paint(row, item, index). list:SetItems(items), list:Render(). The wheel scrolls; a slim bar shows where you are.
function W.VList(parent, T, rowH, build, paint, gap, emptyText)
  local v = CreateFrame("Frame", nil, parent)
  v.rows, v.items, v.offset, v.gap = {}, {}, 0, gap or 2
  v:EnableMouseWheel(true)
  v.bar = U.Round(v, 2, "ARTWORK")
  v.bar:SetWidth(4)
  v.bar:SetVertexColor(T.muted[1], T.muted[2], T.muted[3], 0.45)
  v.bar:Hide()
  v.empty = UI.Text(v, T.font, T.muted)
  v.empty:SetPoint("TOPLEFT", 6, -8)
  v.empty:SetPoint("RIGHT", v, "RIGHT", -12, 0)
  v.empty:SetText(emptyText or "Nothing here.")
  v.empty:Hide()
  function v:Visible()
    return math.max(1, math.floor(((self:GetHeight() or 0) + self.gap) / (rowH + self.gap)))
  end
  function v:Render()
    local items, n = self.items, self:Visible()
    self.offset = math.max(0, math.min(self.offset, #items - n))
    local scrolls = #items > n
    for i = 1, n do
      local item = items[i + self.offset]
      local row = self.rows[i]
      if not row and item ~= nil then
        row = build(self, i)
        row:SetHeight(rowH)
        self.rows[i] = row
      end
      if row then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * (rowH + self.gap))
        row:SetPoint("RIGHT", self, "RIGHT", scrolls and -10 or 0, 0)
        if item ~= nil then
          row.item = item
          paint(row, item, i + self.offset)
          row:Show()
        else
          row.item = nil
          row:Hide()
        end
      end
    end
    for i = n + 1, #self.rows do self.rows[i].item = nil; self.rows[i]:Hide() end
    if self.emptyFn then self.empty:SetText(self.emptyFn()) end
    self.empty:SetShown(#items == 0)
    if scrolls then
      local h = self:GetHeight()
      local bh = math.max(24, h * n / #items)
      self.bar:SetHeight(bh)
      self.bar:ClearAllPoints()
      self.bar:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -(h - bh) * self.offset / (#items - n))
      self.bar:Show()
    else
      self.bar:Hide()
    end
  end
  function v:SetItems(items, keepOffset)
    self.items = items or {}
    if not keepOffset then self.offset = 0 end
    self:Render()
  end
  function v:ScrollTo(index)
    local n = self:Visible()
    if index <= self.offset then self.offset = index - 1
    elseif index > self.offset + n then self.offset = index - n end
    self:Render()
  end
  v:SetScript("OnMouseWheel", function(self, delta)
    self.offset = self.offset - delta * 3
    self:Render()
  end)
  v:SetScript("OnSizeChanged", function(self) self:Render() end)
  return v
end

-- a row card: a rounded fill a shade lighter than the window, lit on hover, with a blue edge while selected
function W.RowCard(parent, T)
  local r = CreateFrame("Button", nil, parent)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.base = T.surface
  r.bg = U.Round(r, 5, "BACKGROUND")
  r.bg:SetAllPoints(r)
  r.bg:SetVertexColor(rgba(T.surface))
  -- the card's resting colour (a nested row sits a shade darker)
  function r:SetBase(c)
    self.base = c
    if not self.selected then self.bg:SetVertexColor(rgba(c)) end
  end
  r.sel = U.Solid(r, "ARTWORK", rgba(T.accent))
  r.sel:SetWidth(3)
  r.sel:SetPoint("TOPLEFT", 0, -6)
  r.sel:SetPoint("BOTTOMLEFT", 0, 6)
  r.sel:Hide()
  function r:SetSelected(on)
    self.selected = on
    self.sel:SetShown(on)
    self.bg:SetVertexColor(rgba(on and T.surfaceHi or self.base))
  end
  r:HookScript("OnEnter", function(self) self.bg:SetVertexColor(rgba(T.surfaceHi)) end)
  r:HookScript("OnLeave", function(self) if not self.selected then self.bg:SetVertexColor(rgba(self.base)) end end)
  return r
end

-- a game icon (trimmed) or a line icon name, on a texture
function W.SetAnyIcon(tex, icon, T)
  if UI.IsIconName(icon) then
    UI.SetIcon(tex, icon)
    tex:SetVertexColor(rgba(T.accent))
  else
    tex:SetTexture(icon or 134400)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetVertexColor(1, 1, 1)
    tex:Show()
  end
end

-- pin the nearest of some NPCs for your side (Map buttons)
function W.MapTo(npcs)
  local id = npcs and ns.map.nearest(npcs)
  if id then ns.map.pin(id) else ns.print("no one for your side in the data.") end
end
