-- The crafting queue in the profession window:
--   Craft next: one button under the window, "Craft next: 5 Bolt of Silk Cloth". A click crafts the first entry of
--   the queue that is ready in the profession on screen (you know it, its materials are in your bags, no cooldown), as
--   many as the bags allow up to its count; entries without materials are skipped and said ("2 skipped: need
--   materials"). Each craft ticks the queue off (CraftList.lua counts finished casts). It is your click that crafts:
--   nothing happens by itself, and nothing in combat.
--   Right-click a recipe in the list: a small menu queues 1, 5, 10 or as many as your materials make.
-- Works in the profession window (C_TradeSkillUI.CraftRecipe) and, should the client open them, the older-style trade
-- skill window (DoTradeSkill) and Enchanting's craft window (DoCraft). Only plain buttons of our own and hooks after
-- the game's own scripts: no protected frame is touched.
local _, ns = ...
local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba
local try, plain = ns.try, ns.plain

local Q = {}
ns.queueButton = Q

local function L() return ns.craftList end

---------------------------------------------------------------------------------------------------------------------
-- Which window is open, and crafting in it

-- "professions" (the retail-style window), "tradeskill" or "craft" (the older ones), or nil
function Q.window()
  local pf = rawget(_G, "ProfessionsFrame")
  if pf and pf.IsShown and pf:IsShown() then return "professions", pf end
  local tf = rawget(_G, "TradeSkillFrame")
  if tf and tf.IsShown and tf:IsShown() then return "tradeskill", tf end
  local cf = rawget(_G, "CraftFrame")
  if cf and cf.IsShown and cf:IsShown() then return "craft", cf end
end

-- the profession on screen (our skill line): the retail-style window says it; the older ones by their name
function Q.skill()
  local kind = Q.window()
  if kind == "professions" then return ns.scan.openSkill() end
  if kind == "tradeskill" then return ns.skillByName(plain(try(rawget(_G, "GetTradeSkillLine")))) end
  if kind == "craft" then
    local name = plain(try(rawget(_G, "GetCraftDisplaySkillLine"))) or plain(try(rawget(_G, "GetCraftName")))
    return ns.skillByName(name)
  end
end

-- casting or channelling something (a batch of crafts in progress); a value the game hides counts as casting
local function busy(fn)
  local v = try(fn, "player")
  if issecretvalue and issecretvalue(v) then return true end
  return v ~= nil
end
local function casting()
  return busy(rawget(_G, "UnitCastingInfo")) or busy(rawget(_G, "UnitChannelInfo"))
end

-- the row of an older-style window that has a recipe (by its name): index, or nil
local function indexByName(count, info, name)
  for i = 1, plain(try(count)) or 0 do
    local n = plain((try(info, i)))
    if n == name then return i end
  end
end

-- Craft n of recipe r in the window on screen. true when the game was asked to.
function Q.craft(r, n)
  if not r or (n or 0) < 1 then return false end
  local kind = Q.window()
  local id = L().castID(r)
  if kind == "professions" then
    local T = C_TradeSkillUI
    if T and T.CraftRecipe then return (pcall(T.CraftRecipe, id, n)) end
  elseif kind == "tradeskill" then
    local i = indexByName(rawget(_G, "GetNumTradeSkills"), rawget(_G, "GetTradeSkillInfo"), r.name)
    if i and rawget(_G, "DoTradeSkill") then return (pcall(DoTradeSkill, i, n)) end
  elseif kind == "craft" then
    local i = indexByName(rawget(_G, "GetNumCrafts"), rawget(_G, "GetCraftInfo"), r.name)
    if i and rawget(_G, "DoCraft") then return (pcall(DoCraft, i)) end
  end
  return false
end

-- What the button says and does now: { text, usable, r, n, skipped, why }
function Q.state()
  local skill = Q.skill()
  if not skill or not EverlookCraftDB then return { hidden = true } end
  local any = false
  for _, e in ipairs(L().entries()) do
    local r = e.n > 0 and ns.recipeBySpell(e.spell)
    if r and r.skill == skill then any = true break end
  end
  if not any then return { hidden = true } end
  local e, r, n, skipped = L().next(skill)
  if not e then
    return { text = "Craft next: nothing ready", usable = false, skipped = skipped,
      why = skipped > 0 and ("%d need materials"):format(skipped) or "the queued recipes need skill or are on cooldown" }
  end
  if InCombatLockdown and InCombatLockdown() then
    return { text = "Craft next: after combat", usable = false, r = r, n = n, skipped = skipped }
  end
  if casting() then
    return { text = "Crafting...", usable = false, r = r, n = n, skipped = skipped }
  end
  return { text = ("Craft next: %d %s"):format(n, r.name), usable = true, r = r, n = n, skipped = skipped }
end

function Q.click()
  local st = Q.state()
  if not st.usable then return false end
  local ok = Q.craft(st.r, st.n)
  if ok and st.skipped > 0 then
    ns.print(("crafting %d %s; %d queued %s skipped: need materials."):format(st.n, st.r.name, st.skipped,
      st.skipped == 1 and "recipe" or "recipes"))
  elseif not ok then
    ns.print(("couldn't start %s here: pick it in the window and press Create."):format(st.r.name))
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, Q.refresh) end
  return ok
end

---------------------------------------------------------------------------------------------------------------------
-- The button

local button

local function make(parent)
  if button then
    if button:GetParent() ~= parent then button:SetParent(parent) end
    return button
  end
  local b = CreateFrame("Button", "EverlookCraftNext", parent, "UIPanelButtonTemplate")
  b:SetSize(280, 24)
  b:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
  b:SetScript("OnEnter", function(self)
    local st = Q.state()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Craft next", 1, 1, 1)
    GameTooltip:AddLine("Crafts the first recipe of your crafting queue that is ready here: you know it and its materials are in your bags. Each craft ticks it off.", nil, nil, nil, true)
    if st.why then GameTooltip:AddLine("Nothing ready: " .. st.why .. ".", 1, 0.4, 0.4, true)
    elseif (st.skipped or 0) > 0 then GameTooltip:AddLine(("%d skipped: need materials."):format(st.skipped), 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine("Right-click: open the crafting queue.", 0.55, 0.58, 0.64, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, which)
    if which == "RightButton" then
      if ns.listWindow then ns.listWindow.open() end
      return
    end
    Q.click()
  end)
  button = b
  Q.button = b
  return b
end

function Q.refresh()
  local kind, win = Q.window()
  if not kind then
    if button then button:Hide() end
    return
  end
  local st = Q.state()
  if st.hidden then
    if button then button:Hide() end
    return
  end
  local b = make(win)
  b:ClearAllPoints()
  -- under the window's bottom left; above it when the window sits at the bottom of the screen
  local bottom = win.GetBottom and win:GetBottom()
  if bottom and bottom < 34 then b:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 4, 2) else b:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 4, -2) end
  b:SetText(st.text)
  if b.SetEnabled then b:SetEnabled(st.usable and true or false) end
  b:Show()
end

---------------------------------------------------------------------------------------------------------------------
-- Right-click a recipe: queue it

local menu

local function recipeOfRow(frame)
  if frame.GetElementData then
    local node = try(frame.GetElementData, frame)
    local data = node and node.GetData and try(node.GetData, node)
    local info = data and data.recipeInfo
    local id = info and plain(info.recipeID)
    if id and not plain(info.isHeader) then return ns.recipeBySpell(id), id end
    return nil
  end
  -- an older-style row: its recipe by name, in the profession on screen
  local skill = Q.skill()
  local id = frame.GetID and frame:GetID()
  local name
  if Q.window() == "tradeskill" then name = plain((try(rawget(_G, "GetTradeSkillInfo"), id)))
  elseif Q.window() == "craft" then name = plain((try(rawget(_G, "GetCraftInfo"), id))) end
  if not (skill and name) then return nil end
  for _, r in ipairs(ns.recipes(skill) or {}) do
    if r.name == name then return r, r.spell end
  end
end

local function makeMenu()
  if menu then return menu end
  local T = UI.MakeTheme(ns.ACCENT)
  local m = CreateFrame("Frame", "EverlookCraftQueueMenu", UIParent)
  m.eluiTheme = T
  m:SetSize(170, 10)
  m:SetFrameStrata("DIALOG")
  m:SetClampedToScreen(true)
  m:EnableMouse(true)
  m.fill, m.edge = U.RoundBox(m, 6, T.bg, T.divider)
  m.title = UI.Text(m, T.font, T.text)
  m.title:SetPoint("TOPLEFT", 10, -9)
  m.title:SetPoint("RIGHT", -10, 0)
  m.title:SetWordWrap(false)
  m.buttons = {}
  local y = -30
  for i, d in ipairs({ { 1 }, { 5 }, { 10 }, { "all" } }) do
    local b = ns.widgets.SmallButton(m, "", function()
      local n = m.counts[i]
      if m.r and n and n > 0 then
        local ok = L().add(m.r.spell, n)
        if ok then
          local e = L().find(m.r.spell)
          ns.print(("%s: %d in the crafting queue."):format(m.r.name, e and e.n or n))
        end
      end
      m:Hide()
    end, 150)
    b:SetPoint("TOPLEFT", 10, y)
    y = y - 24
    b.kind = d[1]
    m.buttons[i] = b
  end
  m.open = ns.widgets.SmallButton(m, "Open the queue", function()
    m:Hide()
    if ns.listWindow then ns.listWindow.open() end
  end, 150)
  m.open:SetPoint("TOPLEFT", 10, y - 4)
  m:SetHeight(-y + 32)
  m.counts = {}
  -- out of the way once the mouse has left it for a moment, or the window closes
  m:SetScript("OnUpdate", function(self, elapsed)
    if self:IsMouseOver() then self.away = 0 return end
    self.away = (self.away or 0) + (elapsed or 0)
    if self.away > 2 or not Q.window() then self:Hide() end
  end)
  UI.CloseOnEscape(m)
  m:Hide()
  menu = m
  Q.menu = m
  return m
end

-- the menu for recipe r, at the mouse
function Q.showMenu(r)
  if not r or not EverlookCraftDB then return end
  local m = makeMenu()
  m.r = r
  m.away = 0
  m.title:SetText("Queue " .. r.name)
  local all = L().knowsMe(r) and L().canNow(r) or 0
  for i, b in ipairs(m.buttons) do
    local n = b.kind == "all" and all or b.kind
    m.counts[i] = n
    if b.kind == "all" then
      b:SetText(all > 0 and ("All I can make (%d)"):format(all) or "All I can make (none)")
      b:SetUsable(all > 0)
    else
      b:SetText(("Queue %d"):format(n))
      b:SetUsable(true)
    end
  end
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s + 8)
  m:Show()
  if m.Raise then m:Raise() end
end

local hooked = setmetatable({}, { __mode = "k" })
function Q.hookRow(frame)
  if not frame or hooked[frame] or not frame.HookScript then return end
  hooked[frame] = true
  frame:HookScript("OnMouseUp", function(self, which)
    if which ~= "RightButton" then return end
    local r = recipeOfRow(self)
    if r then Q.showMenu(r) end
  end)
end

local listHooked = false
local function hookList()
  local pf = rawget(_G, "ProfessionsFrame")
  local box = pf and pf.CraftingPage and pf.CraftingPage.RecipeList and pf.CraftingPage.RecipeList.ScrollBox
  if listHooked or not box then return end
  listHooked = true
  local function each()
    if box.ForEachFrame then box:ForEachFrame(function(frame) Q.hookRow(frame) end) end
  end
  if box.Update then hooksecurefunc(box, "Update", each) end
  if ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnAcquiredFrame and box.RegisterCallback then
    box:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, function(_, frame) Q.hookRow(frame) end, Q)
  end
  each()
  if pf.HookScript then
    pf:HookScript("OnShow", function() if C_Timer then C_Timer.After(0.2, Q.refresh) end end)
    pf:HookScript("OnHide", function() Q.refresh(); if menu then menu:Hide() end end)
  end
end

-- the older-style windows' fixed rows
local function hookClassic()
  for _, d in ipairs({ { "TradeSkillSkill", "TRADE_SKILLS_DISPLAYED" }, { "Craft", "CRAFTS_DISPLAYED" } }) do
    for i = 1, tonumber(rawget(_G, d[2])) or 0 do
      local b = rawget(_G, d[1] .. i)
      if b then Q.hookRow(b) end
    end
  end
end

function Q.hook()
  hookList()
  hookClassic()
end
Q.hookList = hookList

---------------------------------------------------------------------------------------------------------------------
-- Events: the window opens and fills, bags change, a cast starts or ends, the queue changes

ns.on("ADDON_LOADED", function(_, name)
  if name == "Blizzard_Professions" or name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" then Q.hook() end
end)
local pending = false
local function soon()
  if pending or not (C_Timer and C_Timer.After) then return end
  pending = true
  C_Timer.After(0.25, function() pending = false; Q.refresh() end)
end
Q.soon = soon
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "CRAFT_SHOW", "CRAFT_CLOSE",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
  ns.on(e, function(ev)
    if not EverlookCraftDB then return end
    if ev == "TRADE_SKILL_SHOW" or ev == "CRAFT_SHOW" then Q.hook() end
    soon()
  end)
end
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_SUCCEEDED" }) do
  ns.on(e, function(_, unit)
    if unit == "player" and button and button:IsShown() then soon() end
  end)
end
local prevList = ns.onList
ns.onList = function() if prevList then prevList() end if button and button:IsShown() or Q.window() then soon() end end
