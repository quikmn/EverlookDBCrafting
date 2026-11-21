-- Offline tests for the profession window colours (ProfessionColors.lua, formerly the CraftColors addon) against
-- wowmock.lua, in their own Lua state: the defaults, CraftColors' settings taken over once (and never over yours),
-- recolouring by difficulty (hover, off puts the game's colour back, no stale hover colour), the classic trade skill
-- and craft windows, the skill-up chance and "can make (n)" after the name (bags, bank and alts, the game's own [n],
-- a linked window, a narrow row), every chat command, the settings page and its search finding every setting, and
-- standing down for an older CraftColors (one line, once).
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
local function last() return MOCK.log[#MOCK.log] or "" end
local function logHas(s)
  for _, l in ipairs(MOCK.log) do if l:find(s, 1, true) then return true end end
  return false
end

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
IsShiftKeyDown = IsShiftKeyDown or function() return false end

-- the other addons the game says are loaded, with their version
MOCK.addons = {}
C_AddOns = {
  IsAddOnLoaded = function(name) return MOCK.addons[name] ~= nil end,
  GetAddOnMetadata = function(name, k)
    if k == "Version" then return name == ADDON and "v0.1.1" or MOCK.addons[name] end
  end,
}

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

local function loadToc()
  local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
      local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
      if not chunk then error("syntax: " .. err) end
      setfenv(chunk, addonEnv)
      chunk(ADDON, ns)
    end
  end
end

local M, app
local VEST, BOLT, THREAD = 2385, 2996, 2320 -- Brown Linen Vest: learn 10, yellow 45, green 57, gray 70; bolt + thread
local function DB() return EverlookCraftDB.profColors end

-- CraftColors v0.5.0 is enabled too, with its own saved settings
CraftColorsDB = { version = 1, enabled = true, hoverBoost = 0.35, showChance = false, showCount = true, countMore = true,
  colors = { orange = { 0, 0, 1 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, gray = { 0.6, 0.6, 0.6 } } }
MOCK.addons.CraftColors = "0.5.0"

step("loads in TOC order; CraftColors' saved settings are taken over once", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", "CraftColors")
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.log = {}
  MOCK.Fire("PLAYER_LOGIN")
  M, app = ns.profColors, ns.app
  check(M and app, "module missing")
  local db = DB()
  check(db and db.migrated, "not migrated")
  eq(db.colors.orange[3], 1, "orange from CraftColors")
  eq(db.colors.gray[1], 0.6, "gray from CraftColors")
  eq(db.hoverBoost, 0.35, "hover from CraftColors")
  eq(db.showChance, false, "chance from CraftColors")
  eq(db.countMore, true, "countMore from CraftColors")
  -- once: CraftColors' settings never overwrite what is here now
  db.colors.orange = { 1, 0, 0 }
  CraftColorsDB.colors.orange = { 0, 1, 0 }
  check(not M.migrate(), "migrated twice")
  eq(db.colors.orange[1], 1, "own colour overwritten")
end)

step("an older CraftColors still draws: we stand down and say so once", function()
  check(M.standDown, "not standing down for CraftColors 0.5.0")
  local n = 0
  for _, l in ipairs(MOCK.log) do
    if l:find("CraftColors is now part of EverlookDB Crafting; you can disable CraftColors", 1, true) then n = n + 1 end
  end
  eq(n, 1, "the line")
  check(not EverlookCraftAPI.professionColors(), "api says we draw while standing down")
  local color
  local row = {
    Label = { SetTextColor = function(_, r, g, b) color = { r, g, b } end },
    GetElementData = function() return { GetData = function() return { recipeInfo = { relativeDifficulty = Enum.TradeskillRelativeDifficulty.Optimal } } end } end,
  }
  M.recolor(row)
  check(color == nil, "drew while standing down")
  MOCK.log = {}
  MOCK.Fire("TRADE_SKILL_SHOW")
  check(not logHas("you can disable CraftColors"), "said twice")
  -- CraftColors v0.6.0 stands down by itself: we draw
  MOCK.addons.CraftColors = "0.6.0"
  M.checkStandDown()
  check(not M.standDown and EverlookCraftAPI.professionColors(), "stood down for CraftColors 0.6.0")
  -- a CraftColors that stands down marks its saved variables as it loads, whatever its TOC version says
  MOCK.addons.CraftColors = "0.5.0"
  CraftColorsDB.mergedInto = "EverlookDBCrafting"
  M.checkStandDown()
  check(not M.standDown, "stood down for a CraftColors that marked itself")
  CraftColorsDB.mergedInto = nil
  MOCK.addons.CraftColors = nil
  M.checkStandDown()
  check(not M.standDown, "stood down without CraftColors")
end)

step("defaults: the game's own colours, chance and count on, bank and alts off", function()
  local d = ns.DEFAULTS.profColors
  check(d.enabled == true and d.hoverBoost == 0.2 and d.showChance and d.showCount and not d.countMore, "defaults")
  check(d.colors.orange[1] == 1 and d.colors.orange[2] == 0.5 and d.colors.orange[3] == 0.25, "orange")
  check(d.colors.yellow[1] == 1 and d.colors.yellow[2] == 1 and d.colors.yellow[3] == 0, "yellow")
  check(d.colors.green[1] == 0.25 and d.colors.green[2] == 0.75, "green")
  check(d.colors.gray[1] == 0.5, "gray")
  -- the same colours the rest of the addon uses
  for k, c in pairs(ns.COLORS) do
    for i = 1, 3 do eq(d.colors[k][i], c[i], k .. " differs from ns.COLORS") end
  end
  -- back to the defaults for the rest
  local db = DB()
  db.colors = { orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, gray = { 0.5, 0.5, 0.5 } }
  db.hoverBoost, db.showChance, db.countMore = 0.2, true, false
end)

step("recolours a recipe row by difficulty, brighter on hover, not when off", function()
  local color
  local row = {
    Label = { SetTextColor = function(_, r, g, b) color = { r, g, b } end },
    GetElementData = function() return { GetData = function() return { recipeInfo = { relativeDifficulty = Enum.TradeskillRelativeDifficulty.Optimal } } end } end,
    IsMouseOver = function() return false end,
  }
  M.recolor(row)
  check(color and color[1] == 1 and color[2] == 0.5, "not orange")
  row.IsMouseOver = function() return true end
  M.recolor(row)
  check(math.abs(color[2] - 0.7) < 1e-9, "hover not brighter")
  color = nil
  DB().enabled = false
  M.recolor(row)
  check(color == nil, "recoloured while off")
  DB().enabled = true
end)

step("turning colouring off puts the label's own colour back", function()
  local color = { 0.9, 0.8, 0.1 }
  local row = {
    Label = { SetTextColor = function(_, r, g, b) color = { r, g, b } end, GetTextColor = function() return color[1], color[2], color[3] end },
    GetElementData = function() return { GetData = function() return { recipeInfo = { relativeDifficulty = Enum.TradeskillRelativeDifficulty.Easy } } end } end,
    IsMouseOver = function() return false end,
  }
  M.recolor(row)
  check(color[1] == 0.25 and color[2] == 0.75, "not green")
  DB().enabled = false
  M.recolor(row)
  check(color[1] == 0.9 and color[2] == 0.8 and color[3] == 0.1, "own colour not restored")
  DB().enabled = true
  M.recolor(row)
  check(color[1] == 0.25, "not recoloured after turning back on")
end)

step("turning colouring off never leaves a row in a stale hover colour", function()
  local NORMAL, HOVER = { 0.9, 0.8, 0.1 }, { 1, 1, 1 }
  local color = { NORMAL[1], NORMAL[2], NORMAL[3] }
  local over = false
  local row = {
    Label = { SetTextColor = function(_, r, g, b) color = { r, g, b } end, GetTextColor = function() return color[1], color[2], color[3] end },
    GetElementData = function() return { GetData = function() return { recipeInfo = { relativeDifficulty = Enum.TradeskillRelativeDifficulty.Easy } } end } end,
    IsMouseOver = function() return over end,
  }
  over = true
  color = { HOVER[1], HOVER[2], HOVER[3] }
  M.recolor(row)
  over = false
  color = { NORMAL[1], NORMAL[2], NORMAL[3] }
  M.recolor(row)
  check(color[1] == 0.25, "not tinted")
  DB().enabled = false
  M.recolor(row)
  check(color[1] == 0.9 and color[2] == 0.8 and color[3] == 0.1, "left in hover colour: " .. table.concat(color, ","))
  color = { HOVER[1], HOVER[2], HOVER[3] }
  M.recolor(row)
  check(color[1] == 1 and color[3] == 1, "touched the game's own hover colour while off")
  DB().enabled = true
end)

step("the profession window's scroll box is hooked when Blizzard_Professions loads", function()
  local painted = {}
  local rows = {}
  for i = 1, 2 do
    local diff = i == 1 and Enum.TradeskillRelativeDifficulty.Medium or Enum.TradeskillRelativeDifficulty.Trivial
    rows[i] = {
      Label = { SetTextColor = function(_, r, g, b) painted[i] = { r, g, b } end },
      GetElementData = function() return { GetData = function() return { recipeInfo = { relativeDifficulty = diff } } end } end,
    }
  end
  local updates = {}
  local box = { ForEachFrame = function(_, fn) for _, r in ipairs(rows) do fn(r) end end, Update = function() end,
    RegisterCallback = function() end }
  ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = box } }, IsShown = function() return true end }
  MOCK.Fire("ADDON_LOADED", "Blizzard_Professions")
  check(M.hooked(), "not hooked")
  check(painted[1] and painted[1][2] == 1 and painted[1][3] == 0, "medium not yellow")
  check(painted[2] and painted[2][1] == 0.5, "trivial not gray")
  painted = {}
  box:Update()
  check(painted[1], "not repainted after the list updates")
end)

step("classic trade skill and craft windows are coloured too, if the client has them", function()
  local colors, scripts = {}, {}
  local types = { [11] = "optimal", [12] = "trivial", [13] = "header" }
  local function button(name, id)
    local label = { SetTextColor = function(_, r, g, b) colors[name] = { r, g, b } end,
      GetTextColor = function() local c = colors[name] or { 1, 0.82, 0 }; return c[1], c[2], c[3] end }
    _G[name .. "Text"] = label
    _G[name] = { GetName = function() return name end, GetID = function() return id end, IsShown = function() return true end,
      IsMouseOver = function() return false end, HookScript = function(_, k, fn) scripts[name .. k] = fn end }
  end
  button("TradeSkillSkill1", 11); button("TradeSkillSkill2", 12); button("TradeSkillSkill3", 13)
  TRADE_SKILLS_DISPLAYED = 3
  GetTradeSkillInfo = function(i) return "Recipe " .. i, types[i] end
  TradeSkillFrame = { IsShown = function() return true end }
  local painted = 0
  TradeSkillFrame_Update = function() painted = painted + 1 end
  MOCK.Fire("ADDON_LOADED", "Blizzard_TradeSkillUI")
  TradeSkillFrame_Update()
  check(painted == 1, "game's own update not called")
  check(colors.TradeSkillSkill1 and colors.TradeSkillSkill1[2] == 0.5, "optimal not orange")
  check(colors.TradeSkillSkill2 and colors.TradeSkillSkill2[1] == 0.5 and colors.TradeSkillSkill2[3] == 0.5, "trivial not gray")
  check(colors.TradeSkillSkill3 == nil, "header row tinted")
  check(scripts.TradeSkillSkill1OnEnter and scripts.TradeSkillSkill1OnLeave, "hover not hooked")
  SlashCmdList.EVERLOOKCRAFT("colors off")
  check(colors.TradeSkillSkill1[1] == 1 and colors.TradeSkillSkill1[2] == 0.82, "own colour not back: " .. table.concat(colors.TradeSkillSkill1, ","))
  SlashCmdList.EVERLOOKCRAFT("colors on")
  check(colors.TradeSkillSkill1[2] == 0.5, "not tinted again after on")
  button("Craft1", 21)
  CRAFTS_DISPLAYED = 1
  GetCraftInfo = function() return "Enchant Bracer", "", "medium" end
  CraftFrame_Update = function() end
  MOCK.Fire("ADDON_LOADED", "Blizzard_CraftUI")
  CraftFrame_Update()
  check(colors.Craft1 and colors.Craft1[1] == 1 and colors.Craft1[2] == 1 and colors.Craft1[3] == 0, "craft medium not yellow")
  TradeSkillFrame, TradeSkillFrame_Update, GetTradeSkillInfo, CraftFrame_Update, GetCraftInfo = nil, nil, nil, nil, nil
  for _, n in ipairs({ "TradeSkillSkill1", "TradeSkillSkill2", "TradeSkillSkill3", "Craft1" }) do _G[n], _G[n .. "Text"] = nil, nil end
end)

step("after the name: skill-up chance (this addon's formula) and how many you can make", function()
  local bags, bank = { [BOLT] = 9, [THREAD] = 2 }, { [BOLT] = 4, [THREAD] = 6 }
  C_Item = C_Item or {}
  local oldCount = C_Item.GetItemCount
  C_Item.GetItemCount = function(id, withBank) return (bags[id] or 0) + (withBank and (bank[id] or 0) or 0) end
  -- this character's bank and an alt's bags, as the stock module saved them
  local me = ns.me()
  me.bags, me.bank = { [BOLT] = 9, [THREAD] = 2 }, { [BOLT] = 4, [THREAD] = 6 }
  EverlookCraftDB.chars["Player-alt"] = { name = "Alt", realm = "Mock Realm", side = "a", profs = {}, bags = { [BOLT] = 20 }, bank = {} }
  local skill, linked = 60, false
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { skillLevel = skill } end,
    IsTradeSkillLinked = function() return linked end,
    GetRecipeSchematic = function(id)
      if id == 77 then return { reagentSlotSchematics = { { reagents = { { itemID = BOLT } }, quantityRequired = 3 } } } end
    end,
  }
  local E = Enum.TradeskillRelativeDifficulty
  local info = { recipeID = VEST, relativeDifficulty = E.Easy }
  -- green at 60 of 45..70 -> (70-60)/(70-45) = 40%, in the green colour; the scarcer reagent (2 thread) limits it
  local t = M.extraText(info, "Brown Linen Vest")
  check(t:find("40%", 1, true) and t:find("40bf40", 1, true), "chance in green: " .. t)
  eq(t:find("40%", 1, true) and ns.planner.chance(ns.recipeBySpell(VEST), 60), 0.4, "the planner's formula")
  check(t:find("(2)", 1, true), "count limited by the scarcer reagent: " .. t)
  check(not t:find("+", 1, true), "bank and alts counted while off: " .. t)
  DB().countMore = true
  t = M.extraText(info, "Brown Linen Vest")
  -- bolts (9 + 4 + 20) = 33, thread (2 + 6) = 8 -> 8, 6 more than the bags' 2
  check(t:find("(2 |cff8d94a3+6", 1, true), "bank and alts: " .. t)
  -- the game already shows "[2]" after the name: only the extra
  t = M.extraText(info, "Brown Linen Vest [2]")
  check(not t:find("(2", 1, true) and t:find("(+6)", 1, true), "count said twice: " .. t)
  DB().countMore = false
  -- yellow at 50: 80%, in yellow
  skill = 50
  info.relativeDifficulty = E.Medium
  t = M.extraText(info, "x")
  check(t:find("80%", 1, true) and t:find("ffff00", 1, true), "chance in yellow: " .. t)
  -- the game's colour decides: an orange or gray row shows no chance, whatever the data says
  info.relativeDifficulty = E.Optimal
  check(not (M.extraText(info, "x") or ""):find("%%"), "chance on a row the game colours orange")
  info.relativeDifficulty = E.Medium
  skill = 40
  check(not (M.extraText(info, "x") or ""):find("%%"), "chance on an orange recipe")
  skill = 70
  check(not (M.extraText(info, "x") or ""):find("%%"), "chance on a gray recipe")
  skill = 60
  info.relativeDifficulty = E.Easy
  -- a recipe the data doesn't know: no chance, the count from the window's reagents (9 / 3)
  check(M.extraText({ recipeID = 77, relativeDifficulty = E.Medium }, "x") == "|cffffffff(3)|r",
    "unknown recipe: " .. tostring(M.extraText({ recipeID = 77 }, "x")))
  -- settings off
  DB().showChance, DB().showCount = false, false
  check(M.extraText(info, "x") == nil, "shown while off")
  DB().showChance, DB().showCount = true, true
  -- someone else's window: nothing
  linked = true
  check(M.extraText(info, "x") == nil, "shown on a linked window")
  linked = false
  -- a row frame gets the text after its name, hidden when colouring is off
  local row = CreateFrame("Button", nil, UIParent)
  row.Label = row:CreateFontString(nil, "OVERLAY")
  row.Label:SetText("Brown Linen Vest")
  row.Label:SetWidth(200)
  row.GetElementData = function() return { GetData = function() return { recipeInfo = info } end } end
  M.recolor(row)
  local fs = M.extraOf(row)
  check(fs and fs:IsShown() and fs:GetText():find("40%", 1, true), "row text")
  check(row.ccExtra == nil and row.ccApplied == nil, "state written onto the game's frame")
  -- a narrow row: the name gives way so our text is never drawn over it (row 200 wide, our text 40)
  check(math.abs(row.Label:GetWidth() - 148) < 0.01, "name narrowed for our text: " .. tostring(row.Label:GetWidth()))
  M.recolor(row)
  check(math.abs(row.Label:GetWidth() - 148) < 0.01, "narrowed again on a second pass: " .. tostring(row.Label:GetWidth()))
  -- the game's own "[2]" after the name: we don't repeat the count, and sit after the game's
  row.Count = row:CreateFontString(nil, "OVERLAY")
  row.Count:SetText("[2]")
  row.Count:Show()
  M.recolor(row)
  check(not fs:GetText():find("(2)", 1, true), "count said twice next to the game's [2]: " .. fs:GetText())
  check(math.abs(row.Label:GetWidth() - 104) < 0.01, "room for the game's count too: " .. tostring(row.Label:GetWidth()))
  row.Count:Hide()
  SlashCmdList.EVERLOOKCRAFT("colors.chance off")
  check(DB().showChance == false, "chance from chat")
  SlashCmdList.EVERLOOKCRAFT("colors.chance on")
  DB().enabled = false
  M.recolor(row)
  check(not fs:IsShown(), "extra text while colouring is off")
  check(math.abs(row.Label:GetWidth() - 200) < 0.01, "the name's width given back: " .. tostring(row.Label:GetWidth()))
  DB().enabled = true
  C_TradeSkillUI = nil
  EverlookCraftDB.chars["Player-alt"] = nil
  C_Item.GetItemCount = oldCount
end)

step("every colour setting and command works from chat", function()
  MOCK.log = {}
  SlashCmdList.EVERLOOKCRAFT("help")
  local all = table.concat(MOCK.log, "\n")
  check(all:find("/ecraft colors [on || off]", 1, true) and all:find("reset", 1, true), "help: " .. all)
  SlashCmdList.EVERLOOKCRAFT("colors off")
  check(DB().enabled == false and last():find("off", 1, true), "colors off: " .. last())
  SlashCmdList.EVERLOOKCRAFT("colors toggle")
  check(DB().enabled == true, "toggle")
  SlashCmdList.EVERLOOKCRAFT("colors.enabled off")
  check(DB().enabled == false, "colors.enabled off")
  SlashCmdList.EVERLOOKCRAFT("colors.enabled on")
  SlashCmdList.EVERLOOKCRAFT("colors.orange 00ff00")
  check(DB().colors.orange[2] == 1 and DB().colors.orange[1] == 0, "orange colour")
  check(last():find("#00ff00", 1, true), "colour reply: " .. last())
  SlashCmdList.EVERLOOKCRAFT("colors.gray purple")
  check(last():find("Example: /ecraft colors.gray", 1, true), "bad colour reply: " .. last())
  SlashCmdList.EVERLOOKCRAFT("colors.hover 0.3")
  check(math.abs(DB().hoverBoost - 0.3) < 1e-9, "hover")
  SlashCmdList.EVERLOOKCRAFT("colors.hover 2")
  check(math.abs(DB().hoverBoost - 0.3) < 1e-9 and last():find("0.00 to 0.50", 1, true), "hover range: " .. last())
  SlashCmdList.EVERLOOKCRAFT("set colors.hover 0.25")
  check(math.abs(DB().hoverBoost - 0.25) < 1e-9, "set")
  SlashCmdList.EVERLOOKCRAFT("get colors.hover")
  check(last():find("0.25", 1, true), "get: " .. last())
  SlashCmdList.EVERLOOKCRAFT("colors.count off")
  check(DB().showCount == false, "count off")
  SlashCmdList.EVERLOOKCRAFT("colors.count on")
  SlashCmdList.EVERLOOKCRAFT("colors.countmore on")
  check(DB().countMore == true, "countmore on")
  SlashCmdList.EVERLOOKCRAFT("colors.countmore off")
  local old = ProfessionsFrame
  ProfessionsFrame = nil
  SlashCmdList.EVERLOOKCRAFT("colors debug")
  check(last():find("select a recipe", 1, true), "debug without a profession: " .. last())
  ProfessionsFrame = { CraftingPage = { SchematicForm = { GetRecipeInfo = function() return { name = "Bolt|of Cloth", relativeDifficulty = Enum.TradeskillRelativeDifficulty.Medium, numSkillUps = 1, canSkillUp = true } end } } }
  SlashCmdList.EVERLOOKCRAFT("colors check")
  check(last():find("Bolt||of Cloth", 1, true) and last():find("yellow", 1, true), "check: " .. last())
  ProfessionsFrame = old
  SlashCmdList.EVERLOOKCRAFT("reset colors")
  check(DB().colors.orange[1] == 0 and last():find("again within 10 s", 1, true), "reset didn't ask first: " .. last())
  SlashCmdList.EVERLOOKCRAFT("reset colors")
  check(DB().colors.orange[1] == 1 and DB().colors.orange[2] == 0.5 and DB().hoverBoost == 0.2, "reset")
  SlashCmdList.EVERLOOKCRAFT("colors.oragne 00ff00")
  check(last():find("Did you mean /ecraft colors.orange", 1, true), "typo: " .. last())
  SlashCmdList.EVERLOOKCRAFT("craftcolors")
  check(app:IsShown() and app.current == "colors", "craftcolors opens the page")
  app.window:Hide()
end)

step("the settings page: after Recipes, and the search box finds every setting", function()
  local order = app.order
  local at
  for i, id in ipairs(order) do if id == "colors" then at = i end end
  check(at and order[at - 1] == "recipes", "page not after Recipes")
  SlashCmdList.EVERLOOKCRAFT("colors")
  check(app:IsShown() and app.current == "colors", "page not open")
  local keys = {}
  for _, def in ipairs(app.settingOrder) do
    if def.key:find("^colors%.") then keys[#keys + 1] = def end
  end
  eq(#keys, 9, "colour settings")
  for _, def in ipairs(keys) do
    local found = false
    for _, e in ipairs(app:Search(def.label)) do if e.entry.info.key == def.key then found = true end end
    check(found, "search doesn't find " .. def.key .. " by its label")
  end
  local function finds(q, key)
    for _, e in ipairs(app:Search(q)) do if e.entry.info.key == key then return true end end
  end
  check(finds("craftcolors", "colors.enabled"), "search 'craftcolors'")
  check(finds("grey", "colors.gray"), "search 'grey'")
  check(finds("skill-up chance", "colors.chance"), "search 'skill-up chance'")
  check(finds("bank", "colors.countmore"), "search 'bank'")
  app:Search("")
  app.window:Hide()
end)

step("no taint: only our own globals; no Blizzard popups", function()
  for k in pairs(globalWrites) do
    check(k == "EverlookCraftDB" or k == "EverlookCraftChar" or k == "EverlookCraftAPI" or k:match("^SLASH_EVERLOOKCRAFT") or k == "EverlookCraftGuide",
      "unexpected global " .. k)
  end
  check(StaticPopupDialogs == nil or next(StaticPopupDialogs) == nil, "StaticPopupDialogs used")
end)

step("no Lua errors reported", function()
  check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
