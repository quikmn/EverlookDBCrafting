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
