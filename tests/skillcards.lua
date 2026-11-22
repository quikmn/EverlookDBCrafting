-- Offline tests for the skill-up cards (SkillCards.lua) against wowmock.lua, in their own Lua state: the chat line in
-- several languages (numbered arguments, the Korean grammar codes, secret values), the skill list compared with the
-- last one (the first read only remembers, the same rank never twice), merging while the card is up (+N), the cap
-- hint (train, read a book, the level), the route hint, milestones and fireworks, weapon skills off by default, the
-- column shared with EverlookDB Auctions' loot cards (and its old versions), moving, the settings, search and commands.
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
GetRealmName = function() return "Mock Realm" end
UIParent.GetWidth = function() return 1000 end
UIParent.GetHeight = function() return 600 end
UIParent.GetRight = function() return 1000 end
UIParent.GetTop = function() return 600 end
SKILL_RANK_UP = "Your skill in %s has increased to %d."
MOCK.sounds = {}
PlaySound = function(id) table.insert(MOCK.sounds, id) end

-- the skill list (Classic style): { name, isHeader, rank, max }
MOCK.skills = {
  { "Professions", true }, { "Tailoring", false, 148, 225 },
  { "Secondary Skills", true }, { "First Aid", false, 149, 150 }, { "Fishing", false, 1, 75 },
  { "Weapon Skills", true }, { "Swords", false, 40, 150 },
}
GetNumSkillLines = function() return #MOCK.skills end
GetSkillLineInfo = function(i) local s = MOCK.skills[i]; if s then return s[1], s[2], nil, s[3], nil, nil, s[4] end end
local function setSkill(name, rank, max)
  for _, s in ipairs(MOCK.skills) do if s[1] == name then s[3] = rank; s[4] = max or s[4] end end
end

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

local K, app
local function S() return EverlookCraftDB.settings end
local function clear()
  while #K.cards > 0 do K.drop(K.cards[1]) end
end
local function chat(name, rank) MOCK.Fire("CHAT_MSG_SKILL", SKILL_RANK_UP:format(name, rank)) end

step("loads; on by default, the rest off but the fireworks", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  K, app = ns.skillCards, ns.app
  check(K and app, "module missing")
  eq(S().skillCards, true, "cards on")
  eq(S().skillFireworks, true, "fireworks on")
  eq(S().skillSound, false, "sound off")
  eq(S().skillOther, false, "weapon skills off")
  eq(#K.cards, 0, "the first read of the skill list shows nothing")
  check(K.snap.Tailoring and K.snap.Tailoring.rank == 148 and K.snap.Tailoring.header == "Professions", "snapshot")
end)

step("the chat line in several languages", function()
  local name, rank = K.parse("Your skill in Tailoring has increased to 151.")
  check(name == "Tailoring" and rank == 151, "enUS: " .. tostring(name) .. " " .. tostring(rank))
  name, rank = K.parse("Your skill in First Aid has increased to 75.")
  check(name == "First Aid" and rank == 75, "a name with a space")
  name, rank = K.parse("Eure Fertigkeit 'Schneiderei' hat sich auf 151 erhöht.", "Eure Fertigkeit '%1$s' hat sich auf %2$d erhöht.")
  check(name == "Schneiderei" and rank == 151, "deDE (numbered)")
  name, rank = K.parse("Votre compétence en Couture est maintenant de 151.", "Votre compétence en %s est maintenant de %d.")
  check(name == "Couture" and rank == 151, "frFR")
  name, rank = K.parse("Tu habilidad en Primeros auxilios ha aumentado a 76.", "Tu habilidad en %s ha aumentado a %d.")
  check(name == "Primeros auxilios" and rank == 76, "esES")
  name, rank = K.parse("Ваш навык \"Портняжное дело\" повысился до 151.", "Ваш навык \"%s\" повысился до %d.")
  check(name == "Портняжное дело" and rank == 151, "ruRU")
  name, rank = K.parse("재봉술 숙련도가 151로 올랐습니다.", "%s 숙련도가 %d|1으로;로; 올랐습니다.")
  check(name == "재봉술" and rank == 151, "koKR (grammar code): " .. tostring(name))
  name, rank = K.parse("151 : Tailoring", "%2$d : %1$s")
  check(name == "Tailoring" and rank == 151, "arguments the other way round")
  check(K.parse("You receive loot: [Linen Cloth].") == nil, "another line")
  check(K.parse(MOCK.Secret("Your skill in Tailoring has increased to 151.")) == nil, "a secret value is never read")
  check(K.parse(nil) == nil, "nil")
end)

step("which skills count", function()
  eq(K.kind("Tailoring"), "prof", "crafting")
  eq(K.kind("Herbalism"), "prof", "gathering")
  eq(K.kind("Fishing"), "prof", "fishing")
  eq(K.kind("Lockpicking"), "prof", "lockpicking")
  eq(K.kind("Poisons"), "prof", "poisons")
  eq(K.kind("Kochkunst", "Sekundäre Fertigkeiten"), "other", "an unknown name under an unknown header")
  SECONDARY_SKILLS = "Sekundäre Fertigkeiten:"
  eq(K.kind("Kochkunst", "Sekundäre Fertigkeiten"), "prof", "the game's localized header")
  SECONDARY_SKILLS = nil
  eq(K.kind("Swords", "Weapon Skills"), "other", "weapons")
  eq(K.skillOf("Skinning"), 393, "skinning's skill line")
  eq(K.icon(197), ns.PROF_ICONS[197], "tailoring icon")
  check(K.icon(182) ~= nil and K.icon(633) ~= nil, "herbalism and lockpicking icons")
end)

step("a skill-up from the skill list, then the chat line of the same rank: one card", function()
  clear()
  setSkill("Tailoring", 149)
  MOCK.Fire("SKILL_LINES_CHANGED")
  eq(#K.cards, 1, "one card")
  local c = K.cards[1]
  check(c:IsShown(), "shown")
  check(c.name:GetText():find("Hurray!", 1, true) and c.name:GetText():find("Tailoring 149", 1, true), "title: " .. c.name:GetText())
  check(not c.name:GetText():find("+", 1, true), "no +N for one point")
  eq(c.count:GetText(), "149 / 225", "rank and cap")
  check(c.barBg:IsShown(), "bar")
  chat("Tailoring", 149)
  eq(#K.cards, 1, "the chat line of the same rank adds nothing")
  check(not c.name:GetText():find("+", 1, true), "still no +N")
end)

step("more while the card is up: merged, +N, stays up", function()
  local c = K.cards[1]
  c.age = 3
  setSkill("Tailoring", 151)
  chat("Tailoring", 150)
  chat("Tailoring", 151)
  MOCK.Fire("SKILL_LINES_CHANGED")
  eq(#K.cards, 1, "one card for all of them")
  check(c.name:GetText():find("Tailoring 151", 1, true) and c.name:GetText():find("+3", 1, true), "merged: " .. c.name:GetText())
  check(c.age <= 0.2, "stays another 5 seconds")
  -- a card that is fading: a new one
  c.age = 5.3
  setSkill("Tailoring", 152)
  chat("Tailoring", 152)
  eq(#K.cards, 2, "a new card after the old one's time")
  eq(K.cards[1].e.rank, 152, "newest on top")
  -- another profession: its own card, three at most
  chat("First Aid", 150)
  chat("Fishing", 2)
  chat("Herbalism", 10)
  eq(#K.cards, 3, "three at most")
  check(K.cards[1].e.name == "Herbalism", "newest first")
  clear()
end)

step("the card fades and goes after 5 seconds", function()
  chat("Fishing", 3)
  local c = K.cards[1]
  c:GetScript("OnUpdate")(c, 0.1)
  check(c:GetAlpha() > 0 and c:GetAlpha() < 1, "fading in")
  c:GetScript("OnUpdate")(c, 2)
  eq(c:GetAlpha(), 1, "full")
  c:GetScript("OnUpdate")(c, 3.2)
  check(c:GetAlpha() < 1, "fading out")
  c:GetScript("OnUpdate")(c, 1)
  eq(#K.cards, 0, "gone")
  check(not c:IsShown(), "hidden")
end)

step("the cap hint: train the next rank, read the book, the level", function()
  local hint, cap = K.hint({ name = "Tailoring", skill = 197, rank = 150, max = 150 })
  check(cap and hint == "rank cap at 150 \226\128\148 train Expert", "train: " .. tostring(hint))
  hint = K.hint({ name = "Tailoring", skill = 197, rank = 75, max = 75 })
  eq(hint, "rank cap at 75 \226\128\148 train Journeyman", "journeyman")
  hint = K.hint({ name = "First Aid", skill = 129, rank = 150, max = 150 })
  check(hint and hint:find("read Expert First Aid", 1, true), "a book: " .. tostring(hint))
  UnitLevel = function() return 15 end
  hint = K.hint({ name = "Tailoring", skill = 197, rank = 150, max = 150 })
  check(hint and hint:find("train Expert at level 20", 1, true), "the level: " .. tostring(hint))
  UnitLevel = function() return 30 end
  check(K.hint({ name = "Tailoring", skill = 197, rank = 300, max = 300 }) == nil, "no hint at 300 without a route")
  check(K.hint({ name = "Swords", rank = 150, max = 150, header = "Weapon Skills" }) == nil, "no rank hint for weapons")
  -- on the card, in gold
  clear()
  setSkill("First Aid", 150)
  K.snap["First Aid"].rank = 149
  chat("First Aid", 150)
  check(K.cards[1].sub:GetText():find("rank cap at 150", 1, true), "card hint: " .. tostring(K.cards[1].sub:GetText()))
  clear()
end)

step("the route hint: the next step and how many", function()
  local r = ns.recipes(197)[1]
  EverlookCraftChar.routes[197] = { skill = 197, from = 140, to = 200, steps = {
    { spell = r.spell, from = 140, to = 155, n = 12, n90 = 14 },
    { spell = r.spell, from = 155, to = 200, n = 50, n90 = 55 },
  } }
  local hint = K.hint({ name = "Tailoring", skill = 197, rank = 152, max = 225 })
  check(hint and hint:find("next: " .. r.name .. " \195\151", 1, true), "next step: " .. tostring(hint))
  hint = K.hint({ name = "Tailoring", skill = 197, rank = 200, max = 225 })
  eq(hint, "your route is done", "done")
  -- the cap first
  hint = K.hint({ name = "Tailoring", skill = 197, rank = 150, max = 150 })
  check(hint:find("rank cap", 1, true), "the cap comes before the route")
  EverlookCraftChar.routes[197] = nil
end)

step("milestones: every 25, the cap, 300; fireworks on the card", function()
  check(K.milestone(149, 150, 225), "150")
  check(K.milestone(148, 151, 225), "crossing 150 in one go")
  check(not K.milestone(151, 152, 225), "152")
  check(K.milestone(73, 74, 74), "a cap that isn't a multiple of 25")
  check(K.milestone(299, 300, 300), "300")
  eq(K.progress(150, 225), 1 / 1 * 0 + (150 - 150) / 75, "bar at the rank's start")
  check(math.abs(K.progress(187, 225) - 37 / 75) < 1e-9, "bar inside the rank")
  eq(K.progress(10, nil), 0, "no cap known")
  clear()
  setSkill("Fishing", 25)
  chat("Fishing", 25)
  check(K.cards[1].fireworks, "fireworks at 25")
  local c = K.cards[1]
  c:GetScript("OnUpdate")(c, 0.5)
  local shown = 0
  for _, sp in ipairs(c.sparks) do if sp:IsShown() then shown = shown + 1 end end
  check(shown > 0, "sparks flying")
  chat("Herbalism", 11)
  check(not K.cards[1].fireworks, "no fireworks at 11")
  S().skillFireworks = false
  chat("Fishing", 50)
  check(not K.cards[2].fireworks and not K.cards[1].fireworks or K.cards[1].e.name ~= "Fishing", "fireworks off")
  S().skillFireworks = true
  clear()
end)

step("sound only when switched on", function()
  MOCK.sounds = {}
  chat("Fishing", 51)
  eq(#MOCK.sounds, 0, "silent by default")
  S().skillSound = true
  chat("Fishing", 52)
  eq(#MOCK.sounds, 1, "a sound")
  S().skillSound = false
  clear()
end)

step("weapon skills only when switched on; off means no cards", function()
  setSkill("Swords", 41)
  MOCK.Fire("SKILL_LINES_CHANGED")
  chat("Swords", 41)
  eq(#K.cards, 0, "no card for weapons by default")
  S().skillOther = true
  chat("Swords", 42)
  eq(#K.cards, 1, "a card when switched on")
  check(K.cards[1].sub:GetText() == "", "no rank hint for weapons")
  S().skillOther = false
  clear()
  S().skillCards = false
  chat("Fishing", 60)
  eq(#K.cards, 0, "off: no card")
  S().skillCards = true
end)

step("the column: under EverlookDB Auctions' loot cards, and its older versions", function()
  local x, y, how = K.anchorXY()
  check(x == -170 and y == -114 and how == "default", ("default spot %s %s %s"):format(x, y, tostring(how)))
  -- EverlookDB Auctions without the shared column: below the room for its five loot cards, at its spot
  EverlookDBAuctionsAPI = { version = 6 }
  EverlookAuctionsDB = { lootPos = { -200, -80 } }
  x, y, how = K.anchorXY()
  check(x == -200 and y == -80 - 5 * 52 and how == "auctions", ("old auctions %s %s"):format(x, y))
  EverlookAuctionsDB.lootCards = false
  x, y = K.anchorXY()
  check(y == -80, "loot cards off: their spot")
  -- the shared column: right under the loot cards shown now
  local lootShown = 2
  local relaid = 0
  EverlookCardColumn.stacks["auctions.loot"] = { order = 10, anchor = function() return -200, -80 end,
    height = function() return lootShown * 52 end, relayout = function() relaid = relaid + 1 end }
  x, y, how = K.anchorXY()
  check(x == -200 and y == -80 - 104 and how == "column", ("column %s %s %s"):format(x, y, tostring(how)))
  lootShown = 0
  x, y = K.anchorXY()
  eq(y, -80, "at the top when no loot card is up")
  chat("Fishing", 61)
  local _, _, _, px, py = K.cards[1]:GetPoint(1)
  check(px == -200 and py == -80, ("card placed %s %s"):format(tostring(px), tostring(py)))
  lootShown = 1
  EverlookCardColumn.stacks["crafting.skillups"].relayout()
  _, _, _, px, py = K.cards[1]:GetPoint(1)
  eq(py, -132, "moves down when a loot card comes")
  eq(EverlookCardColumn.stacks["crafting.skillups"].height(), 52, "our height for stacks below")
  eq(relaid, 0, "stacks above are never moved by ours")
  clear()
  EverlookCardColumn.stacks["auctions.loot"] = nil
  EverlookDBAuctionsAPI, EverlookAuctionsDB = nil, nil
end)

step("move, lock and reset", function()
  check(K.move(), "mover shown")
  check(K.moving(), "moving")
  local m
  for _, f in ipairs({ UIParent:GetChildren() }) do if f.__scripts and f.__scripts.OnDragStop and f:IsShown() and f.SetMovable then m = f end end
  check(m, "the mover")
  m:GetScript("OnDragStop")(m)
  check(S().skillPos and S().skillPos[1] == -700 and S().skillPos[2] == -100, "spot saved: " .. tostring(S().skillPos and S().skillPos[1]))
  local x, y, how = K.anchorXY()
  check(x == -700 and how == "own", "its own spot")
  SlashCmdList.EVERLOOKCRAFT("skillcards lock")
  check(not K.moving(), "locked")
  SlashCmdList.EVERLOOKCRAFT("skillcards move")
  check(K.moving(), "move from chat")
  SlashCmdList.EVERLOOKCRAFT("skillcards move")
  check(not K.moving(), "move again locks")
  SlashCmdList.EVERLOOKCRAFT("skillcards reset")
  check(S().skillPos == nil, "reset")
end)

step("commands, settings page and search", function()
  SlashCmdList.EVERLOOKCRAFT("skillcards off")
  eq(S().skillCards, false, "off from chat")
  SlashCmdList.EVERLOOKCRAFT("skillcards on")
  eq(S().skillCards, true, "on from chat")
  SlashCmdList.EVERLOOKCRAFT("skillcards.sound on")
  eq(S().skillSound, true, "sound from chat")
  SlashCmdList.EVERLOOKCRAFT("skillcards.sound off")
  SlashCmdList.EVERLOOKCRAFT("skillcards.weapons on")
  eq(S().skillOther, true, "weapons from chat")
  SlashCmdList.EVERLOOKCRAFT("skillcards.weapons off")
  SlashCmdList.EVERLOOKCRAFT("skillcards test")
  eq(#K.cards, 2, "two example cards")
  clear()
  MOCK.log = {}
  SlashCmdList.EVERLOOKCRAFT("help")
  local found = false
  for _, l in ipairs(MOCK.log) do if l:find("skillcards", 1, true) then found = true end end
  check(found, "help lists skillcards")
  SlashCmdList.EVERLOOKCRAFT("skillcards")
  check(app:IsShown() and app.current == "skillcards", "page open")
  local function finds(q, key)
    for _, e in ipairs(app:Search(q)) do if e.entry.info.key == key then return true end end
  end
  for _, def in ipairs(app.settingOrder) do
    if def.key:find("^skillcards") then check(finds(def.label, def.key), "search by label: " .. def.key) end
  end
  check(finds("hurray", "skillcards"), "search 'hurray'")
  check(finds("fishing", "skillcards"), "search 'fishing'")
  check(finds("milestone", "skillcards.fireworks"), "search 'milestone'")
  check(finds("defense", "skillcards.weapons"), "search 'defense'")
  app:Search("")
  app.window:Hide()
end)

step("in combat: secret values are skipped, nothing breaks", function()
  local old = GetSkillLineInfo
  GetSkillLineInfo = function(i)
    local s = MOCK.skills[i]
    if s then return MOCK.Secret(s[1]), s[2], nil, MOCK.Secret(s[3]), nil, nil, MOCK.Secret(s[4]) end
  end
  MOCK.secretsOn = true
  MOCK.Fire("SKILL_LINES_CHANGED")
  MOCK.Fire("CHAT_MSG_SKILL", MOCK.Secret("Your skill in Fishing has increased to 99."))
  eq(#K.cards, 0, "nothing read, nothing shown")
  GetSkillLineInfo = old
  MOCK.secretsOn = false
end)

step("no taint: only our own globals and the shared card column; no Lua errors", function()
  for k in pairs(globalWrites) do
    check(k == "EverlookCraftDB" or k == "EverlookCraftChar" or k == "EverlookCraftAPI" or k:match("^SLASH_EVERLOOKCRAFT")
      or k == "EverlookCraftGuide" or k == "EverlookCardColumn" or k == "SECONDARY_SKILLS", "unexpected global " .. k)
  end
  check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
