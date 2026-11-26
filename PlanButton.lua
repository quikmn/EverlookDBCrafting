-- The way into the skill-up planner from the profession window:
--   Skill-up plan: a small plain button under the window, beside Craft next. A click opens the guide when this
--   profession has a route still to walk, else the planner on this profession; right-click always opens the planner.
--   It shows only for your own window of a profession the planner covers, and a setting turns it off
--   (/ecraft > Profession window, "Skill-up plan button").
--   A hint in chat, once per account, the first time a covered profession window opens: "New: /ecraft plan ...".
-- A plain button of our own, parented to the window: no protected frame is touched.
local _, ns = ...
local UI = LibStub("EverlookUI-1")

local PB = {}
ns.planButton = PB

local function Q() return ns.queueButton end
local function S() return ns.settings() end

-- the planner has recipes for this profession
function PB.covered(skill)
  if not (skill and ns.DATA and ns.DATA.profs[skill]) then return false end
  return #(ns.recipes(skill) or {}) > 0
end

-- the saved route of this profession, while there is still some of it to walk
function PB.route(skill)
  local route = ns.plans.saved(skill)
  if not route then return nil end
  local now = ns.plans.skillNow(skill)
  if now and route.to and now >= route.to then return nil end
  return route
end

-- What the button does now: { hidden } or { skill, action = "guide" | "planner" }
function PB.state()
  if not EverlookCraftDB then return { hidden = true } end
  local kind = Q().window()
  if not kind then return { hidden = true } end
  local skill = Q().skill()
  if not PB.covered(skill) then return { hidden = true } end
  if S().planButton == false then return { hidden = true, skill = skill } end
  return { skill = skill, action = PB.route(skill) and "guide" or "planner" }
end

-- the planner, on this profession
function PB.openPlanner(skill)
  local O = ns.options
  if O and skill then O.skill, O.target, O.targetFor = skill, nil, nil end
  ns.app:Open("planner")
  if O and O.refreshPlanner then O.refreshPlanner() end
end

function PB.click(which)
  local st = PB.state()
  if st.hidden then return nil end
  if which == "RightButton" or st.action == "planner" then
    PB.openPlanner(st.skill)
    return "planner"
  end
  local G = ns.guide
  if G.frame and G.frame:IsShown() and G.skill == st.skill then
    G.frame:Hide()
    return "closed"
  end
  G.open(st.skill)
  return "guide"
end

---------------------------------------------------------------------------------------------------------------------
-- The one-time hint (per account)

function PB.hint(skill, noButton)
  local db = EverlookCraftDB
  if not db or not PB.covered(skill) then return false end
  db.hints = db.hints or {}
  if db.hints.planner then return false end
  db.hints.planner = true
  ns.print(("New: /ecraft plan finds the cheapest way to level %s at your realm's prices.%s"):format(ns.profName(skill),
    noButton and "" or " Or click \"Skill-up plan\" under the profession window."))
  return true
end

---------------------------------------------------------------------------------------------------------------------
-- The button

local holder, button

local function make(parent)
  if button then
    if holder:GetParent() ~= parent then holder:SetParent(parent) end
    return button
  end
  holder = CreateFrame("Frame", "EverlookCraftPlanHolder", parent)
  holder:SetSize(1, 1)
  holder:SetPoint("TOPLEFT")
  holder.eluiTheme = ns.widgets.theme()
  local b = ns.widgets.SmallButton(holder, "Skill-up plan", nil, 110)
  b:SetHeight(24)
  b:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
  b:HookScript("OnEnter", function(self)
    local st = PB.state()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Skill-up plan", 1, 1, 1)
    local name = st.skill and ns.profName(st.skill) or "this profession"
    if st.action == "guide" then
      GameTooltip:AddLine(("Opens your %s route's guide: the next step, what to buy, a checklist while you craft."):format(name), nil, nil, nil, true)
    else
      GameTooltip:AddLine(("The cheapest way to level %s at your realm's prices, counting your alts' materials, with a shopping list."):format(name), nil, nil, nil, true)
    end
    GameTooltip:AddLine("Right-click: the planner.", 0.55, 0.58, 0.64, true)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, which) PB.click(which) end)
  button = b
  PB.button = b
  return b
end

function PB.refresh()
  local _, win = Q().window()
  local st = PB.state()
  if st.skill then PB.hint(st.skill, st.hidden) end
  if st.hidden then
    if button then button:Hide() end
    return
  end
  local b = make(win)
  b:ClearAllPoints()
  local craftNext = Q().button
  local bottom = win.GetBottom and win:GetBottom()
  if craftNext and craftNext:IsShown() and craftNext:GetParent() == win then
    b:SetPoint("LEFT", craftNext, "RIGHT", 4, 0)
  elseif bottom and bottom < 34 then
    b:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 4, 2)
  else
    b:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 4, -2)
  end
  b:Show()
end

-- Craft next refreshes on every change of the window; this button follows it (and sits beside it)
local prevRefresh = Q().refresh
Q().refresh = function(...)
  prevRefresh(...)
  PB.refresh()
end

---------------------------------------------------------------------------------------------------------------------
-- Setting: /ecraft > Profession window

ns.app:Setting({
  key = "profwin.planbutton", type = "bool", label = "Skill-up plan button",
  chatLabel = "Profession window: Skill-up plan button",
  keywords = { "skill-up plan", "planner", "plan", "route", "guide", "button", "profession window", "level", "leveling" },
  desc = "A small button under the profession window that opens the skill-up planner for that profession (or its guide, when you have a route).",
  get = function() return S().planButton ~= false end,
  set = function(v) S().planButton = v and true or false end,
  default = true, after = function() PB.refresh() end,
})
