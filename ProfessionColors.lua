-- Profession window colours (formerly the CraftColors addon): each recipe name in the profession window in its
-- skill-up colour (orange, yellow, green, gray, your own shades), and after the name the chance that one craft raises
-- your skill ("37%") and how many your bags make ("(4)", "(4 +5)" with your bank and other characters).
-- Works in the profession window (Enchanting included) and, should the client open one, the older-style trade skill
-- and craft windows. Settings: /ecraft > Profession window (EverlookCraftDB.profColors).
--
-- The row colour is the game's own difficulty for the row (relativeDifficulty, live from the server); the chance is
-- this addon's formula (ns.planner.chance, the same one the planner and the guide use), shown only on rows the game
-- colours yellow or green. Nothing here touches a protected frame: the recipe rows are plain buttons, and we only
-- recolour their label, narrow it, and add one font string after it.
--
-- If an older CraftColors (before v0.6.0, which stands down by itself) is enabled too, this module stands down so only
-- one draws, and says once that CraftColors can be disabled. CraftColors' own settings are taken over once.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")
local try, plain = ns.try, ns.plain

local M = {}
ns.profColors = M

ns.DEFAULTS.profColors = {
  enabled = true,
  hoverBoost = 0.2, -- brighten the hovered row this much so the highlight still reads
  showChance = true, -- "37%" after a yellow or green recipe
  showCount = true,  -- "(4)": how many you can make from your bags
  countMore = false, -- "(4 +5)": and how many more with your bank and other characters
  colors = {
    orange = { 1.00, 0.50, 0.25 }, -- Optimal
    yellow = { 1.00, 1.00, 0.00 }, -- Medium
    green  = { 0.25, 0.75, 0.25 }, -- Easy
    gray   = { 0.50, 0.50, 0.50 }, -- Trivial
  },
  -- migrated: CraftColors' settings were taken over, or you changed one here (then they never overwrite yours)
}
local ORDER = { "orange", "yellow", "green", "gray" }
M.ORDER = ORDER
local LABELS = {
  orange = "Orange: always a skill-up",
  yellow = "Yellow: usually a skill-up",
  green  = "Green: rarely a skill-up",
  gray   = "Gray: no skill-up",
}

function M.db() return EverlookCraftDB and EverlookCraftDB.profColors end

-- relativeDifficulty -> colour name. Prefer the live enum values in case the client numbers them differently.
local function names()
  local D = Enum and Enum.TradeskillRelativeDifficulty
  if D and D.Optimal ~= nil then
    return { [D.Optimal] = "orange", [D.Medium] = "yellow", [D.Easy] = "green", [D.Trivial] = "gray" }
  end
  return { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }
end
local NAMES = names()
M.NAMES = NAMES

function M.colorFor(difficulty)
  local db = M.db()
  local name = NAMES[difficulty]
  return name and db and db.colors[name], name
end

---------------------------------------------------------------------------------------------------------------------
-- Only one may draw: an older CraftColors (before v0.6.0) that is still enabled keeps drawing, and we stand down.

local function addonLoaded(name)
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  return f and try(f, name) and true or false
end

local function versionNumber(v)
  local a, b, c = tostring(v or ""):match("(%d+)%.(%d+)%.?(%d*)")
  if not a then return nil end
  return tonumber(a) * 10000 + tonumber(b) * 100 + (tonumber(c) or 0)
end

-- true when an older CraftColors is drawing (it doesn't know to stand down). CraftColors v0.6.0 and later mark their
-- own saved variables (CraftColorsDB.mergedInto) as they load, and stand down while we draw; the version is the
-- fallback for a CraftColors whose variables aren't there.
function M.oldCraftColors()
  if not addonLoaded("CraftColors") then return false end
  local cc = rawget(_G, "CraftColorsDB")
  if type(cc) == "table" and cc.mergedInto then return false end
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local v = versionNumber(meta and try(meta, "CraftColors", "Version"))
  return v == nil or v < 600
end

local told = false
function M.checkStandDown()
  M.standDown = M.oldCraftColors()
  if M.standDown and not told then
    told = true
    ns.print("CraftColors is now part of EverlookDB Crafting; you can disable CraftColors.")
  end
  return M.standDown
end

-- drawing here (for EverlookCraftAPI.professionColors: CraftColors v0.6.0+ stands down when this is true)
function M.active() return not M.standDown end

---------------------------------------------------------------------------------------------------------------------
-- CraftColors' saved settings, taken over once (its SavedVariables global is there while CraftColors is enabled)

function M.migrate()
  local db = M.db()
  local old = rawget(_G, "CraftColorsDB")
  if not db or db.migrated or type(old) ~= "table" then return false end
  local function bool(k) if type(old[k]) == "boolean" then db[k] = old[k] end end
  bool("enabled"); bool("showChance"); bool("showCount"); bool("countMore")
  if type(old.hoverBoost) == "number" and old.hoverBoost >= 0 and old.hoverBoost <= 0.5 then db.hoverBoost = old.hoverBoost end
  for _, name in ipairs(ORDER) do
    local c = type(old.colors) == "table" and old.colors[name]
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
      db.colors[name] = { c[1], c[2], c[3] }
    end
  end
  db.migrated = true
  return true
end

---------------------------------------------------------------------------------------------------------------------
-- Recolouring a row. Per-row state lives here (weak keys), not on the game's frames.

local state = setmetatable({}, { __mode = "k" })
local function st(frame)
  local s = state[frame]
  if not s then s = {}; state[frame] = s end
  return s
end
M.state = st

local function recipeInfoOf(frame)
  if not frame.GetElementData then return end
  local node = frame:GetElementData()
  local data = node and node.GetData and node:GetData()
  return data and data.recipeInfo
end

local function same(c, r, g, b)
  return c and math.abs(c[1] - r) < 0.002 and math.abs(c[2] - g) < 0.002 and math.abs(c[3] - b) < 0.002
end

-- Remember the colour the game last painted the label (normal, hover or selected). Rows are recycled and the game
-- repaints on hover and selection, so a colour saved once goes stale; this runs after each repaint.
local function noteGameColor(frame, s)
  if not frame.Label.GetTextColor then return end
  local r, g, b = frame.Label:GetTextColor()
  r, g, b = plain(r), plain(g), plain(b)
  if not r or same(s.applied, r, g, b) then return end -- still our tint: the game didn't repaint
  s.gameColor = { r, g, b }
end

local function paint(frame, s, r, g, b)
  frame.Label:SetTextColor(r, g, b)
  s.applied = { r, g, b }
end

-- put the game's own look back (colour, width, no text of ours)
local function restore(frame, s)
  local o = s.gameColor
  if s.applied and o then frame.Label:SetTextColor(o[1], o[2], o[3]) end
  s.applied = nil
  if s.extra then s.extra:Hide() end
  M.restoreLabel(frame)
end

function M.recolor(frame)
  local db = M.db()
  if not db or not frame or not frame.Label then return end
  local s = st(frame)
  noteGameColor(frame, s)
  if not db.enabled or M.standDown then restore(frame, s) return end
  local c
  if s.colorName then
    local name = s.colorName()
    c = name and db.colors[name]
  else
    local info = recipeInfoOf(frame)
    c = info and M.colorFor(plain(info.relativeDifficulty))
  end
  if not c then s.applied = nil; return end
  if not s.colorName then M.extras(frame) end
  if frame.IsMouseOver and frame:IsMouseOver() then
    local b = db.hoverBoost or 0
    paint(frame, s, math.min(c[1] + b, 1), math.min(c[2] + b, 1), math.min(c[3] + b, 1))
  else
    paint(frame, s, c[1], c[2], c[3])
  end
end

local hooked = setmetatable({}, { __mode = "k" })
local function hookRow(frame)
  if hooked[frame] then return end
  hooked[frame] = true
  -- the game resets the label colour on init, hover and selection; recolour after each
  for _, method in ipairs({ "Init", "SetLabelFontColors", "OnEnter", "OnLeave", "SetSelected" }) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, M.recolor) end
  end
end

local function refreshAll(scrollBox)
  if not scrollBox or not scrollBox.ForEachFrame then return end
  scrollBox:ForEachFrame(function(frame)
    if recipeInfoOf(frame) then
      hookRow(frame)
      M.recolor(frame)
    end
  end)
end

local scrollBoxHooked = false
local function recipeScrollBox()
  local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
  return list and list.ScrollBox
end

function M.tryHookProfessions()
  if scrollBoxHooked then return true end
  local scrollBox = recipeScrollBox()
  if not scrollBox then return false end
  scrollBoxHooked = true
  hooksecurefunc(scrollBox, "Update", refreshAll)
  if ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnAcquiredFrame then
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, function(_, frame) hookRow(frame) end, M)
  end
  refreshAll(scrollBox)
  return true
end
function M.hooked() return scrollBoxHooked end

-- Classic-style windows, in case this client opens them for some professions: the trade skill window
-- (Blizzard_TradeSkillUI) and the craft window Enchanting uses in Classic (Blizzard_CraftUI). Their rows are fixed
-- buttons (TradeSkillSkill1.., Craft1..) and the difficulty comes as a word ("optimal", ...).
local SKILL_TYPES = { optimal = "orange", medium = "yellow", easy = "green", trivial = "gray" }
M.SKILL_TYPES = SKILL_TYPES
local CLASSIC = {
  {
    addon = "Blizzard_TradeSkillUI", frame = "TradeSkillFrame", update = "TradeSkillFrame_Update",
    prefix = "TradeSkillSkill", count = "TRADE_SKILLS_DISPLAYED",
    kind = function(index) local _, skillType = GetTradeSkillInfo(index); return skillType end,
  },
  {
    addon = "Blizzard_CraftUI", frame = "CraftFrame", update = "CraftFrame_Update",
    prefix = "Craft", count = "CRAFTS_DISPLAYED",
    kind = function(index) local _, _, craftType = GetCraftInfo(index); return craftType end,
  },
}
M.CLASSIC = CLASSIC
local classicRows = setmetatable({}, { __mode = "k" })

local function classicRow(win, button)
  local row = classicRows[button]
  if row then return row end
  local label = _G[button:GetName() .. "Text"] or (button.GetFontString and button:GetFontString())
  if not label then return end
  row = { Label = label, IsMouseOver = function() return button.IsMouseOver and button:IsMouseOver() end }
  st(row).colorName = function()
    local index = button.GetID and button:GetID()
    if not index or index < 1 then return end
    local ok, kind = pcall(win.kind, index)
    return ok and SKILL_TYPES[plain(kind)] or nil
  end
  classicRows[button] = row
  -- the game repaints the name on hover; tint again after it
  if button.HookScript then
    button:HookScript("OnEnter", function() M.recolor(row) end)
    button:HookScript("OnLeave", function() M.recolor(row) end)
  end
  return row
end

local function refreshClassic(win)
  for i = 1, tonumber(_G[win.count]) or 8 do
    local button = _G[win.prefix .. i]
    if button and button.IsShown and button:IsShown() then
      local row = classicRow(win, button)
      if row then M.recolor(row) end
    end
  end
end

function M.tryHookClassic()
  for _, win in ipairs(CLASSIC) do
    if not win.hooked and type(_G[win.update]) == "function" then
      win.hooked = true
      hooksecurefunc(win.update, function() refreshClassic(win) end)
    end
  end
end

-- Recolour an open profession window right away after a setting changes (off puts the game's own colours back).
function M.apply()
  local scrollBox = scrollBoxHooked and recipeScrollBox()
  if scrollBox then refreshAll(scrollBox) end
  for _, win in ipairs(CLASSIC) do
    local frame = _G[win.frame]
    if win.hooked and frame and frame:IsShown() then refreshClassic(win) end
  end
end

-- The recipe selected in the profession window, and what the game says about it (for bug reports)
function M.selectedRecipe()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local form = page and page.SchematicForm
  return form and form.GetRecipeInfo and form:GetRecipeInfo()
end

function M.checkText()
  local info = M.selectedRecipe()
  if not info then return "Open a profession and select a recipe first." end
  local diff = plain(info.relativeDifficulty)
  return ("%s: relativeDifficulty=%s (%s)  numSkillUps=%s  canSkillUp=%s  list hooked=%s"):format(
    UI.Util.Escape(tostring(plain(info.name))), tostring(diff), diff ~= nil and NAMES[diff] or "?",
    tostring(plain(info.numSkillUps)), tostring(plain(info.canSkillUp)), tostring(scrollBoxHooked))
end

---------------------------------------------------------------------------------------------------------------------
-- Skill-up chance and "can make (n)" after each recipe name

local function itemCount(id, bank)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not fn then return 0 end
  local ok, n = pcall(fn, id, bank and true or false)
  return ok and tonumber(plain(n)) or 0
end

-- the recipe's basic reagents: { { item, n } }, from the data (the server's where a window showed others), else the
-- window's schematic
function M.reagents(recipeID)
  local r = ns.recipeBySpell(recipeID)
  local mats = r and ns.matsOf(r)
  if mats and #mats > 0 then return mats end
  local T = C_TradeSkillUI
  if not (T and T.GetRecipeSchematic) then return nil end
  local okS, sch = pcall(T.GetRecipeSchematic, recipeID, false)
  if not okS or type(sch) ~= "table" then return nil end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  local out = {}
  for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
    local re = slot.reagents and slot.reagents[1]
    local item = re and plain(re.itemID)
    if item and (basic == nil or slot.reagentType == nil or slot.reagentType == basic) then
      out[#out + 1] = { item, plain(slot.quantityRequired) or 1 }
    end
  end
  return #out > 0 and out or nil
end

-- How many crafts the materials allow: from the bags (live), and with your bank and other characters (this addon's
-- saved stock). nil when the reagents are unknown.
function M.canMake(mats)
  if not mats then return nil end
  local bags, more = math.huge, math.huge
  for _, m in ipairs(mats) do
    local id, n = m[1], math.max(1, m[2] or 1)
    local b = itemCount(id, false)
    local h = EverlookCraftDB and ns.stock.have(id)
    local all = h and (b + (h.bank or 0) + (h.mail or 0) + (h.alts or 0)) or itemCount(id, true)
    bags = math.min(bags, math.floor(b / n))
    more = math.min(more, math.floor(math.max(all, b) / n))
  end
  if bags == math.huge then return nil end
  return bags, more
end

-- your skill in the profession the window shows; nil, true for someone else's window (a link, a guild list)
local function skillNow(recipeID)
  local T = C_TradeSkillUI
  if not T then return nil end
  for _, k in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
    if T[k] then
      local ok, v = pcall(T[k])
      if ok and plain(v) then return nil, true end
    end
  end
  if T.GetProfessionInfoByRecipeID then
    local ok, p = pcall(T.GetProfessionInfoByRecipeID, recipeID)
    local s = ok and type(p) == "table" and plain(p.skillLevel)
    if s and s > 0 then return s end
  end
  if T.GetBaseProfessionInfo then
    local ok, p = pcall(T.GetBaseProfessionInfo)
    return ok and type(p) == "table" and plain(p.skillLevel) or nil
  end
end

local function hex(c)
  return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- The text after a recipe name, or nil. info = the row's recipeInfo; label = the name as the game wrote it.
function M.extraText(info, label)
  local db = M.db()
  if not db or type(info) ~= "table" or plain(info.isHeader) then return nil end
  local id = plain(info.recipeID)
  if not id then return nil end
  local skill, notMine = skillNow(id)
  if notMine then return nil end
  local parts = {}
  local r = ns.recipeBySpell(id)
  if db.showChance and r and skill then
    -- the game's colour for the row decides whether a chance shows (yellow and green only); the number is ours
    local name = NAMES[plain(info.relativeDifficulty)]
    if name == nil then name = ns.colorAt(r, skill) end
    local chance = ns.planner.chance(r, skill)
    if (name == "yellow" or name == "green") and chance > 0 and chance < 1 then
      parts[#parts + 1] = hex(db.colors[name] or { 1, 1, 1 }) .. math.floor(chance * 100 + 0.5) .. "%|r"
    end
  end
  if db.showCount then
    local bags, more = M.canMake(M.reagents(id))
    if bags == nil then bags = tonumber(plain(info.numAvailable)) end
    -- the game already writes "[n]" after the name: don't say it twice
    local gameShows = type(label) == "string" and label:find("%[%d+%]%s*$") ~= nil
    local extra = (db.countMore and more and bags and more > bags) and (more - bags) or 0
    if bags and (bags > 0 or extra > 0) then
      local s
      if gameShows then
        s = extra > 0 and ("|cff8d94a3(+" .. extra .. ")|r") or nil
      else
        s = "|cffffffff(" .. bags .. (extra > 0 and (" |cff8d94a3+" .. extra .. "|cffffffff") or "") .. ")|r"
      end
      if s then parts[#parts + 1] = s end
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, " ")
end

-- The game's own "[n]" (how many you can make) is a separate text after the name: it when shown, else nil
local function gameCount(frame)
  local c = frame.Count
  if type(c) ~= "table" or not (c.IsShown and c:IsShown() and c.GetText) then return nil end
  local t = plain(c:GetText())
  return type(t) == "string" and t:find("%d") and c or nil
end

-- The label's width as the game set it, before we narrowed it (the game doesn't always set it again on reuse)
local function baseLabelWidth(frame, s)
  local cur = frame.Label.GetWidth and frame.Label:GetWidth() or 0
  if s.setW and math.abs(cur - s.setW) < 0.5 and s.baseW then return s.baseW end
  s.baseW = cur
  return cur
end

function M.restoreLabel(frame)
  local s = st(frame)
  if s.setW and s.baseW and frame.Label.GetWidth and math.abs(frame.Label:GetWidth() - s.setW) < 0.5 then
    frame.Label:SetWidth(s.baseW)
  end
  s.setW = nil
end

function M.extras(frame)
  if not frame.Label or not frame.CreateFontString then return end
  local s = st(frame)
  local info = recipeInfoOf(frame)
  local textOf = frame.Label.GetText and plain(frame.Label:GetText())
  local count = gameCount(frame)
  -- the game's "[n]" counts as the game showing the count, wherever it sits
  if count then textOf = (textOf or "") .. " [" .. (count:GetText():match("%d+") or "0") .. "]" end
  local ok, t = pcall(M.extraText, info, textOf)
  t = ok and t or nil
  if not t then
    if s.extra then s.extra:Hide() end
    M.restoreLabel(frame)
    return
  end
  local fs = s.extra
  if not fs then
    fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    s.extra = fs
  end
  fs:SetText(t)
  -- after the name and the game's "[n]"; when the row is too narrow, the name gives way (the game shortens it with
  -- "...") so nothing is drawn over it
  local base = baseLabelWidth(frame, s)
  local extraW = (fs.GetStringWidth and fs:GetStringWidth()) or 30
  local countW = count and count.GetStringWidth and (count:GetStringWidth() + 4) or 0
  local left, right = frame.Label.GetLeft and frame.Label:GetLeft(), frame.GetRight and frame:GetRight()
  local want = base
  if left and right and base > 0 then
    local room = right - left - 8 - countW - extraW - 4
    if room < base then want = math.max(40, room) end
  end
  if want ~= base then
    frame.Label:SetWidth(want)
    s.setW = want
  else
    M.restoreLabel(frame)
  end
  fs:ClearAllPoints()
  if count then
    fs:SetPoint("LEFT", count, "RIGHT", 4, 0)
  else
    -- the label may be wider than its text: right after the text, within the label
    local nameW = frame.Label.GetStringWidth and frame.Label:GetStringWidth() or 0
    local labelW = frame.Label.GetWidth and frame.Label:GetWidth() or nameW
    fs:SetPoint("LEFT", frame.Label, "LEFT", math.min(nameW, labelW > 0 and labelW or nameW) + 4, 0)
  end
  fs:Show()
end
-- the row's text of ours (tests, the sandbox)
function M.extraOf(frame) return state[frame] and state[frame].extra end

---------------------------------------------------------------------------------------------------------------------
-- Events

-- counts change as bags do: refresh an open window (once per half second at most)
local bagsPending = false
ns.on("BAG_UPDATE_DELAYED", function()
  if bagsPending or not M.db() then return end
  bagsPending = true
  C_Timer.After(0.5, function()
    bagsPending = false
    if ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown() then M.apply() end
  end)
end)

ns.on("ADDON_LOADED", function(_, name)
  if name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" or name == ADDON then M.tryHookClassic() end
  if name == "CraftColors" then M.migrate() end
  if name == "Blizzard_Professions" or name == ADDON then M.tryHookProfessions() end
end)
ns.whenLoaded(function() M.migrate() end)
ns.on("PLAYER_LOGIN", function()
  M.migrate()
  M.checkStandDown()
  M.apply()
end)
local function shown()
  M.checkStandDown()
  if M.tryHookProfessions() then refreshAll(recipeScrollBox()) end
end
ns.on("TRADE_SKILL_SHOW", shown)
ns.on("TRADE_SKILL_LIST_UPDATE", shown)

---------------------------------------------------------------------------------------------------------------------
-- Settings: /ecraft > Profession window, and from chat (/ecraft colors on, /ecraft colors.orange ff8040, ...)

local app = ns.app
local function after() M.apply() end
local function D() return M.db() or ns.DEFAULTS.profColors end
-- a setting you change here is yours: CraftColors' old settings never overwrite it
local function touched() local db = M.db(); if db then db.migrated = true end end

app:Setting({
  key = "colors.enabled", type = "bool", label = "Colour recipe names",
  chatLabel = "Profession window: colour recipe names",
  keywords = { "color", "colour", "difficulty", "craftcolors", "profession window", "recipe colors", "on", "off" },
  desc = "Each recipe name in the profession window in its skill-up colour. Off: names keep the game's own colour.",
  get = function() return D().enabled end, set = function(v) D().enabled = v and true or false; touched() end,
  default = true, after = after,
})
for _, name in ipairs(ORDER) do
  app:Setting({
    key = "colors." .. name, type = "color", label = LABELS[name],
    keywords = { "colour", "color", "difficulty", "skill-up", "craftcolors", name, name == "gray" and "grey" or nil },
    get = function() return D().colors[name] end,
    set = function(v) D().colors[name] = { v[1], v[2], v[3] }; touched() end,
    disabled = function() return not D().enabled end, after = after,
  })
end
app:Setting({
  key = "colors.hover", type = "number", label = "Brighten the row under the mouse", min = 0, max = 0.5, step = 0.05,
  keywords = { "highlight", "mouseover", "brightness", "lighter", "hover", "craftcolors" },
  desc = "How much lighter a recipe name gets while the mouse is over it, so the highlight still reads.",
  get = function() return D().hoverBoost end, set = function(v) D().hoverBoost = v; touched() end,
  default = 0.2, disabled = function() return not D().enabled end, after = after,
})
app:Setting({
  key = "colors.chance", type = "bool", label = "Skill-up chance after yellow and green recipes",
  keywords = { "chance", "percent", "skill-up", "odds", "probability", "craftcolors" },
  desc = "\"37%\": the chance that one craft raises your skill, from each recipe's yellow and gray skill.",
  get = function() return D().showChance end, set = function(v) D().showChance = v and true or false; touched() end,
  default = true, after = after,
})
app:Setting({
  key = "colors.count", type = "bool", label = "How many you can make",
  keywords = { "count", "can make", "materials", "reagents", "bags", "number", "craftcolors" },
  desc = "\"(4)\": how many your bags have the materials for. Where the game already shows \"[4]\", only the extra from \"Also count\" is added.",
  get = function() return D().showCount end, set = function(v) D().showCount = v and true or false; touched() end,
  default = true, after = after,
})
app:Setting({
  key = "colors.countmore", type = "bool", label = "Also count my bank and other characters",
  keywords = { "bank", "alts", "twinks", "count", "more", "craftcolors" },
  desc = "\"(4 +5)\": 5 more with your bank and your other characters' materials (from your last visit to each bank).",
  get = function() return D().countMore end, set = function(v) D().countMore = v and true or false; touched() end,
  default = false, disabled = function() return not D().showCount end, after = after,
})

function M.resetColors()
  local db = M.db()
  if not db then return end
  db.colors = UI.Util.CopyTable(ns.DEFAULTS.profColors.colors)
  db.hoverBoost = ns.DEFAULTS.profColors.hoverBoost
  db.migrated = true
  M.apply()
  app:Refresh()
end

app:Reset("colors", "the profession window colours", function() M.resetColors() end)
app:Command("colors", "colors [on | off]", "the profession window colours: their settings page, or switch them on or off",
  function(rest)
    local w = UI.Util.Trim(rest or ""):lower()
    if w == "" then app:Open("colors") return end
    if w == "debug" or w == "check" then app:Print(M.checkText()) return end
    app:SetFromText(app:GetSetting("colors.enabled"), w)
  end, { "colours", "craftcolors" })

app:Section("colors", "Profession window", function(stack)
  UI.Header(stack, "Recipe colours", "Open a profession: each recipe name shows how likely it is to raise your skill.")
  app:Widget(stack, "colors.enabled")
  stack:Space(4)
  for _, name in ipairs(ORDER) do app:Widget(stack, "colors." .. name) end
  app:Widget(stack, "colors.hover")
  UI.Header(stack, "After each recipe", "Skill-up chance and how many you can make, next to the name.")
  app:Widget(stack, "colors.chance")
  app:Widget(stack, "colors.count")
  app:Widget(stack, "colors.countmore")
  UI.Stat(stack, "CraftColors", function()
    if M.standDown then return "|cffffd100an older CraftColors is drawing|r: disable it (it's part of this addon now)" end
    if addonLoaded("CraftColors") then return "|cff8d94a3enabled, standing down|r: you can disable it" end
    return "|cff62cf88part of this addon|r"
  end)
  stack:Space(4)
  UI.ButtonRow(stack, {
    { label = "Back to default colours", width = 200, confirm = true, onClick = function() M.resetColors() end,
      desc = "The four colours and the mouse-over brightness back to the game's own.",
      keywords = { "reset", "defaults", "colors", "colours" } },
  })
  UI.Note(stack, "/ecraft colors off switches the colours off, /ecraft colors debug prints what the game says about the selected recipe (handy for bug reports). This was the CraftColors addon; its settings were taken over.")
end, { icon = "palette", desc = "Recipe names in their skill-up colour, the skill-up chance and how many you can make." })
-- the page sits after Recipes
do
  local order = app.order
  for i, id in ipairs(order) do
    if id == "colors" then table.remove(order, i) break end
  end
  local at = #order + 1
  for i, id in ipairs(order) do if id == "recipes" then at = i + 1 break end end
  table.insert(order, at, "colors")
end
