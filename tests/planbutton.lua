-- Offline tests for the Skill-up plan button under the profession window (PlanButton.lua) against wowmock.lua, in its
-- own Lua state: shown only for your own window of a profession the planner covers, beside Craft next; a click opens
-- the guide when a route is still to walk, else the planner on that profession; right-click always the planner; the
-- setting turns it off; the chat hint comes once per account and never again.
local ROOT = ...
local ADDON = "EverlookDBCrafting"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passes = passes + 1
    print("  ok   " .. name)
  else
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("  FAIL " .. name .. "\n         " .. tostring(err))
  end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

time = time or os.time
date = date or os.date
MOCK.secretsOn = false
MOCK.SetGroup(1)
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitLevel = function() return 30 end
Settings = { RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end, RegisterAddOnCategory = function() end }
MOCK.skills = { { "Professions", true }, { "Tailoring", false, 60, 75 } }
GetNumSkillLines = function() return #MOCK.skills end
GetSkillLineInfo = function(i) local s = MOCK.skills[i]; if s then return s[1], s[2], nil, s[3], nil, nil, s[4] end end
GetRealmName = function() return "Mock Realm" end

-- your bags, as the game counts them
BAGS = {}
C_Item = { GetItemCount = function(id) return BAGS[id] or 0 end }

local function loadToc()
  local env = setmetatable({}, { __index = _G, __newindex = function(_, k, v) _G[k] = v end })
  local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
      local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
      if not chunk then error("syntax: " .. err) end
      setfenv(chunk, env)
      chunk(ADDON, ns)
    end
  end
end

local Q, PB
local LINEN, BOLT_SPELL, CLOAK = 2589, 2963, 2387

step("loads in TOC order", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  Q, PB = ns.queueButton, ns.planButton
  check(Q and PB and ns.guide and ns.options, "modules missing")
  local me = ns.me()
  me.profs[197] = { rank = 60, max = 75, known = { [BOLT_SPELL] = true, [CLOAK] = true } }
  me.bags, me.bank = {}, {}
  check(ns.app:GetSetting("profwin.planbutton"), "the setting is registered")
end)

local prof = { name = "Tailoring", id = 197 }
local function professionWindow()
  ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
  ProfessionsFrame:Show()
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionName = prof.name, professionID = prof.id, skillLevel = 60, maxSkillLevel = 75 } end,
    IsTradeSkillLinked = function() return false end,
    IsTradeSkillGuild = function() return false end,
    IsNPCCrafting = function() return false end,
    CraftRecipe = function() end,
  }
end

step("covers the professions the planner has recipes for", function()
  check(PB.covered(197), "Tailoring")
  check(not PB.covered(nil), "nothing")
  check(not PB.covered(999999), "a skill the data doesn't have")
  for _, p in ipairs(ns.professionList()) do
    eq(PB.covered(p.id), #(ns.recipes(p.id) or {}) > 0, p.name)
  end
end)

step("the first covered window: a hint in chat, once per account", function()
  EverlookCraftDB.hints = {}
  MOCK.log = {}
  professionWindow()
  Q.refresh()
  local said = 0
  for _, line in ipairs(MOCK.log) do
    if line:find("/ecraft plan finds the cheapest way to level Tailoring", 1, true) then said = said + 1 end
  end
  eq(said, 1, "hint said once")
  check(EverlookCraftDB.hints.planner, "remembered on the account")
  MOCK.log = {}
  Q.refresh()
  ProfessionsFrame:Hide(); Q.refresh(); ProfessionsFrame:Show(); Q.refresh()
  for _, line in ipairs(MOCK.log) do check(not line:find("/ecraft plan", 1, true), "said again: " .. line) end
  check(not PB.hint(197), "hint() again")
end)

step("shown under your own window of a covered profession, beside Craft next when that shows", function()
  ns.craftList.clear()
  Q.refresh()
  local b = PB.button
  check(b and b:IsShown(), "not shown")
  eq(b:GetText(), "Skill-up plan", "label")
  local p = { b:GetPoint(1) }
  eq(p[1], "TOPLEFT", "under the window"); eq(p[3], "BOTTOMLEFT", "its bottom left")
  ns.craftList.add(BOLT_SPELL, 2)
  BAGS = { [LINEN] = 6 }
  Q.refresh()
  check(Q.button and Q.button:IsShown(), "Craft next shows")
  p = { b:GetPoint(1) }
  eq(p[1], "LEFT", "beside Craft next"); eq(p[2], Q.button, "anchored to Craft next"); eq(p[3], "RIGHT", "on its right")
  ns.craftList.clear()
  BAGS = {}
end)

step("hidden: window closed, someone else's window, a profession the planner doesn't cover", function()
  ProfessionsFrame:Hide()
  Q.refresh()
  check(not PB.button:IsShown(), "shown with the window closed")
  ProfessionsFrame:Show()
  C_TradeSkillUI.IsTradeSkillLinked = function() return true end
  Q.refresh()
  check(not PB.button:IsShown(), "shown for a linked profession")
  C_TradeSkillUI.IsTradeSkillLinked = function() return false end
  prof.name, prof.id = "Herbalism", 182
  check(not PB.covered(182), "Herbalism has no recipes")
  Q.refresh()
  check(not PB.button:IsShown(), "shown for Herbalism")
  prof.name, prof.id = "Tailoring", 197
  Q.refresh()
  check(PB.button:IsShown(), "back for Tailoring")
end)

step("the setting turns it off, and back on", function()
  local set = ns.app:GetSetting("profwin.planbutton")
  set.set(false); if set.after then set.after() end
  check(not PB.button:IsShown(), "shown while off")
  check(PB.state().hidden, "state while off")
  set.set(true); if set.after then set.after() end
  check(PB.button:IsShown(), "back on")
  eq(ns.settings().planButton, true, "saved")
end)

step("a click: the planner on this profession without a route; the guide with one; right-click the planner", function()
  EverlookCraftChar.routes[197] = nil
  ns.options.skill = 171
  local opened
  local realOpen = ns.app.Open
  ns.app.Open = function(_, id) opened = id end
  local b = PB.button
  b:GetScript("OnClick")(b, "LeftButton")
  eq(opened, "planner", "planner page"); eq(ns.options.selected(), 197, "preselected Tailoring")
  -- a route still to walk: the guide
  EverlookCraftChar.routes[197] = { from = 60, to = 75, steps = {}, at = time(), side = "a" }
  opened = nil
  eq(PB.state().action, "guide", "action")
  eq(PB.click("LeftButton"), "guide", "guide opens")
  check(ns.guide.frame and ns.guide.frame:IsShown(), "guide shown"); eq(ns.guide.skill, 197, "for Tailoring")
  check(opened == nil, "planner opened too")
  eq(PB.click("LeftButton"), "closed", "a second click closes the guide")
  check(not ns.guide.frame:IsShown(), "guide still shown")
  eq(PB.click("RightButton"), "planner", "right-click"); eq(opened, "planner", "right-click page")
  -- a route already walked: the planner again
  ns.me().profs[197].rank = 75
  eq(PB.state().action, "planner", "a finished route plans anew")
  ns.me().profs[197].rank = 60
  EverlookCraftChar.routes[197] = nil
  ns.app.Open = realOpen
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
