-- Offline tests for the crafting queue (CraftList.lua's queue parts, QueueButton.lua, the guide's "Queue next steps"
-- and API v8) against wowmock.lua, in their own Lua state: keep N in stock (refills from bags, bank, mail, alts and
-- auctions, with and without EverlookDB Auctions' inventory), the status of each entry (ready, need materials, need
-- skill, on cooldown, in stock), Craft next (the first ready entry of the profession on screen, skipping those without
-- materials, as many as the bags allow; not while casting or in combat; hidden without entries here), right-click a
-- recipe to queue it, profit each, the API that EverlookDB Auctions uses, and a hidden spell ID never ticking off.
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

local L, Q
local LINEN, BOLT, THREAD = 2589, 2996, 2320
local BOLT_SPELL, CLOAK, VEST = 2963, 2387, 2385

step("loads in TOC order", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  L, Q = ns.craftList, ns.queueButton
  check(L and Q and ns.listWindow and ns.guide, "modules missing")
  local me = ns.me()
  me.profs[197] = { rank = 60, max = 75, known = { [BOLT_SPELL] = true, [CLOAK] = true } }
  me.bags, me.bank = {}, {}
end)

step("keep in stock: the count is what is missing (bags, bank, alts), and refills when you have less", function()
  L.clear()
  check(L.setKeep(BOLT_SPELL, 10), "keep")
  local e = L.find(BOLT_SPELL)
  eq(e.keep, 10, "keep saved"); eq(e.n, 10, "nothing on hand: 10 to craft")
  ns.me().bags = { [BOLT] = 3 }
  ns.me().bank = { [BOLT] = 2 }
  EverlookCraftDB.chars["Player-1-Alt"] = { name = "Bankalt", profs = {}, bags = { [BOLT] = 1 }, bank = {} }
  ns.onStock()
  eq(e.n, 4, "6 on hand: 4 to craft")
  ns.me().bags = { [BOLT] = 12 }
  ns.onStock()
  eq(e.n, 0, "enough: 0 to craft")
  check(L.find(BOLT_SPELL), "a kept entry stays at 0")
  eq(L.status(e).key, "stocked", "status in stock")
  check(L.status(e).text:find("in stock: 15 of 10", 1, true), "status: " .. L.status(e).text)
  L.set(BOLT_SPELL, 0)
  check(L.find(BOLT_SPELL), "setting 0 doesn't drop a kept entry")
  ns.me().bags = {}
  ns.onStock()
  eq(e.n, 7, "sold some: refills to 7")
  L.add(BOLT_SPELL, 2)
  eq(e.keep, 12, "+ on a kept entry keeps 2 more"); eq(e.n, 9, "and crafts 2 more")
  L.setKeep(BOLT_SPELL, 0)
  eq(e.keep, nil, "keep off")
  check(L.find(BOLT_SPELL), "off: the crafts still queued stay")
  L.clear()
  EverlookCraftDB.chars["Player-1-Alt"] = nil
  ns.me().bank = {}
end)

step("keep in stock with EverlookDB Auctions' inventory: mail and your auctions count too", function()
  local changeFn
  EverlookDBAuctionsAPI = { version = 7, inventory = {
    count = function(id)
      if id ~= BOLT then return nil end
      return { chars = { { me = true, name = "Tester", bags = 1, bank = 1, mail = 2, listed = 3 },
        { name = "Mara", bags = 1, bank = 0, mail = 0, listed = 0 } } }
    end,
    usable = function() return 0 end, owned = function() return {} end,
    onChange = function(fn) changeFn = fn end } }
  L.setKeep(BOLT_SPELL, 10)
  eq(L.stockOf(BOLT), 8, "bags, bank, mail, auctions and the alt")
  eq(L.find(BOLT_SPELL).n, 2, "2 to craft")
  ns.stock.listen()
  check(changeFn, "listens to the inventory")
  EverlookDBAuctionsAPI.inventory.count = function() return { chars = {} } end
  changeFn()
  eq(L.find(BOLT_SPELL).n, 10, "the inventory changed: refilled")
  EverlookDBAuctionsAPI = nil
  L.clear()
end)

step("status: ready, ready for some, need materials, need skill (who knows it), on cooldown", function()
  L.clear()
  L.add(BOLT_SPELL, 5)
  local e = L.find(BOLT_SPELL)
  BAGS = { [LINEN] = 4 }
  local st = L.status(e)
  eq(st.key, "ready", "ready"); eq(st.can, 2, "4 linen make 2"); eq(st.text, "ready: 2 now", "text")
  BAGS = { [LINEN] = 20 }
  eq(L.status(e).text, "ready", "all 5 now")
  BAGS = {}
  eq(L.status(e).key, "materials", "no linen")
  L.add(VEST, 1)
  local v = L.status((L.find(VEST)))
  eq(v.key, "skill", "you don't know the vest")
  EverlookCraftDB.chars["Player-1-Mara"] = { name = "Mara", profs = { [197] = { rank = 80, known = { [VEST] = true } } }, bags = {}, bank = {} }
  check(L.status((L.find(VEST))).text:find("Mara knows it", 1, true), "who knows it: " .. L.status((L.find(VEST))).text)
  EverlookCraftDB.chars["Player-1-Mara"] = nil
  BAGS = { [LINEN] = 20 }
  C_Spell = { GetSpellCooldown = function(id) if id == BOLT_SPELL then return { startTime = GetTime() - 10, duration = 7200 } end end }
  st = L.status(e)
  eq(st.key, "cooldown", "on cooldown"); check(st.text:find("2 h", 1, true), "time left: " .. st.text)
  C_Spell = { GetSpellCooldown = function() return { startTime = GetTime(), duration = 1.5 } end }
  eq(L.status(e).key, "ready", "the global cooldown doesn't count")
  MOCK.secretsOn = true
  C_Spell = { GetSpellCooldown = function() return { startTime = MOCK.Secret(GetTime()), duration = MOCK.Secret(3600) } end }
  eq(L.status(e).key, "ready", "a hidden cooldown counts as none")
  MOCK.secretsOn = false
  C_Spell = nil
  L.clear()
end)

step("next: the first ready entry of the profession, skipping those without materials", function()
  L.clear()
  L.add(CLOAK, 2)       -- needs bolts: none in the bags
  L.add(VEST, 1)        -- not known
  L.add(BOLT_SPELL, 6)
  BAGS = { [LINEN] = 8 }
  local e, r, n, skipped = L.next(197)
  eq(r and r.spell, BOLT_SPELL, "the bolts"); eq(n, 4, "as many as the linen allows"); eq(skipped, 1, "the cloak skipped")
  eq(L.next(164), nil, "nothing for Blacksmithing")
  L.clear()
end)

step("profit each: the item's auction price after the 5% cut minus the materials", function()
  EverlookDBAuctionsAPI = { version = 7, price = function(id) local p = ({ [BOLT] = 200, [LINEN] = 30 })[id]; return p, 60 end }
  local r = ns.recipeBySpell(BOLT_SPELL)
  eq(L.profitEach(r), 190 - 60, "190 after the cut, 2 linen at 30")
  EverlookDBAuctionsAPI = { version = 7, price = function(id) if id == LINEN then return 30, 60 end end }
  eq(L.profitEach(r), nil, "no price for the bolt: no profit")
  EverlookDBAuctionsAPI = nil
end)

step("a craft ticks it off; a hidden spell ID ticks nothing", function()
  L.clear()
  L.add(BOLT_SPELL, 3)
  MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", BOLT_SPELL)
  eq(L.find(BOLT_SPELL).n, 2, "one off")
  MOCK.secretsOn = true
  MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", MOCK.Secret(BOLT_SPELL))
  MOCK.secretsOn = false
  eq(L.find(BOLT_SPELL).n, 2, "a secret spell ID counted")
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
  L.clear()
end)

-- a fake profession window: Tailoring, with a recipe list whose rows can be right-clicked
local CRAFTED = {}
local rows = {}
local function professionWindow(o)
  o = o or {}
  local box = CreateFrame("Frame")
  box.ForEachFrame = function(_, fn) for _, r in ipairs(rows) do fn(r) end end
  box.Update = function() end
  box.RegisterCallback = function() end
  ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame")
  ProfessionsFrame.CraftingPage = { RecipeList = { ScrollBox = box } }
  ProfessionsFrame:Show()
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionName = "Tailoring", professionID = 197, skillLevel = 60, maxSkillLevel = 75 } end,
    IsTradeSkillLinked = function() return o.linked end,
    IsTradeSkillGuild = function() return false end,
    IsNPCCrafting = function() return false end,
    CraftRecipe = function(id, n) CRAFTED[#CRAFTED + 1] = { id, n } end,
  }
  for i, spell in ipairs({ BOLT_SPELL, CLOAK }) do
    local row = CreateFrame("Button")
    row.Label = row:CreateFontString()
    row.GetElementData = function() return { GetData = function() return { recipeInfo = { recipeID = spell } } end } end
    rows[i] = row
  end
  MOCK.Fire("ADDON_LOADED", "Blizzard_Professions")
end

step("Craft next: one button under the profession window; a click crafts the first ready entry", function()
  L.clear()
  professionWindow()
  Q.refresh()
  check(not (Q.button and Q.button:IsShown()), "shown with nothing queued for Tailoring")
  L.add(CLOAK, 2)
  L.add(BOLT_SPELL, 5)
  BAGS = { [LINEN] = 6 }
  Q.refresh()
  local b = Q.button
  check(b and b:IsShown(), "not shown")
  eq(b:GetText(), "Craft next: 3 Bolt of Linen Cloth", "label")
  local p = { b:GetPoint(1) }
  eq(p[1], "TOPLEFT", "under the window"); eq(p[3], "BOTTOMLEFT", "its bottom left")
  MOCK.log = {}
  b:GetScript("OnClick")(b, "LeftButton")
  eq(#CRAFTED, 1, "crafted"); eq(CRAFTED[1][1], BOLT_SPELL, "the bolts"); eq(CRAFTED[1][2], 3, "three of them")
  check(MOCK.log[1] and MOCK.log[1]:find("1 queued recipe skipped: need materials", 1, true), "says what was skipped: " .. tostring(MOCK.log[1]))
  -- the twin's window ID is cast when the window listed that one
  ns.me().profs[197].ids = { [BOLT_SPELL] = 99963 }
  b:GetScript("OnClick")(b, "LeftButton")
  eq(CRAFTED[2][1], 99963, "the window's own ID")
  ns.me().profs[197].ids = nil
end)

step("Craft next: not while casting, not in combat, nothing ready said plainly", function()
  CRAFTED = {}
  UnitCastingInfo = function() return "Bolt of Linen Cloth" end
  Q.refresh()
  eq(Q.button:GetText(), "Crafting...", "while casting")
  check(not Q.click(), "clicked while casting")
  UnitCastingInfo = nil
  MOCK.combat = true
  Q.refresh()
  eq(Q.button:GetText(), "Craft next: after combat", "in combat")
  check(not Q.click() and #CRAFTED == 0, "crafted in combat")
  MOCK.combat = false
  BAGS = {}
  Q.refresh()
  eq(Q.button:GetText(), "Craft next: nothing ready", "nothing ready")
  check(Q.state().why:find("2 need materials", 1, true), "why: " .. tostring(Q.state().why))
  BAGS = { [LINEN] = 6 }
end)

step("Craft next hides for someone else's window and when the window closes", function()
  C_TradeSkillUI.IsTradeSkillLinked = function() return true end
  Q.refresh()
  check(not Q.button:IsShown(), "shown for a linked profession")
  C_TradeSkillUI.IsTradeSkillLinked = function() return false end
  Q.refresh()
  check(Q.button:IsShown(), "back for yours")
  ProfessionsFrame:Hide()
  Q.refresh()
  check(not Q.button:IsShown(), "shown with the window closed")
  ProfessionsFrame:Show()
end)

step("right-click a recipe in the profession window: queue 1, 5, 10 or all you can make", function()
  L.clear()
  local row = rows[1]
  row:GetScript("OnMouseUp")(row, "RightButton")
  local m = Q.menu
  check(m and m:IsShown(), "menu not shown")
  eq(m.title:GetText(), "Queue Bolt of Linen Cloth", "title")
  eq(m.buttons[2]:GetText(), "Queue 5", "queue 5")
  eq(m.buttons[4]:GetText(), "All I can make (3)", "all: 6 linen")
  m.buttons[2]:GetScript("OnClick")(m.buttons[2])
  eq(L.find(BOLT_SPELL).n, 5, "5 queued")
  check(not m:IsShown(), "menu closes")
  row:GetScript("OnMouseUp")(row, "RightButton")
  m.buttons[4]:GetScript("OnClick")(m.buttons[4])
  eq(L.find(BOLT_SPELL).n, 8, "3 more")
  row:GetScript("OnMouseUp")(row, "LeftButton")
  check(not m:IsShown(), "a left click opened the menu")
  L.clear()
end)

step("the guide: Queue next steps puts the current step and the next two in the queue, once", function()
  L.clear()
  EverlookCraftChar.routes[197] = { skill = 197, from = 1, to = 75, steps = {
    { spell = BOLT_SPELL, from = 1, to = 50, n = 30, n90 = 36 },
    { spell = CLOAK, from = 50, to = 60, n = 10, n90 = 12 },
    { spell = VEST, from = 60, to = 70, n = 8, n90 = 10 },
    { spell = 2386, from = 70, to = 75, n = 5, n90 = 6 } } }
  ns.me().profs[197].rank = 1
  EverlookCraftChar.lastSkill = 197
  ns.guide.open(197)
  eq(ns.guide.queueNext(3), 3, "three steps")
  eq(L.find(BOLT_SPELL).n, 36, "the safe number of bolts")
  eq(L.find(CLOAK).n, 12, "cloaks"); eq(L.find(VEST).n, 10, "vests"); eq(L.find(2386), nil, "only three")
  ns.guide.queueNext(3)
  eq(L.find(BOLT_SPELL).n, 36, "pressed again: not doubled")
  check(ns.guide.frame.queue and ns.guide.frame.queue:IsShown(), "the button")
  SlashCmdList.EVERLOOKCRAFT("queue next")
  eq(#L.entries(), 3, "/ecraft queue next")
  ns.me().profs[197].rank = 60
  L.clear()
end)

step("API v8: queue, count, add, set, keep, remove, missing, listeners; read-only", function()
  local api = EverlookCraftAPI
  eq(api.version, 8, "version")
  local heard = 0
  api.onQueue(function() heard = heard + 1 end)
  check(api.queueSet(CLOAK, 3), "set adds")
  eq(api.queueCount(CLOAK), 3, "count"); check(heard > 0, "listener")
  check(api.queueAdd(CLOAK, 2), "add"); eq(api.queueCount(CLOAK), 5, "grows")
  check(not api.queueAdd(123456789, 1), "unknown recipe")
  check(api.queueKeep(BOLT_SPELL, 4), "keep")
  local q = api.queue()
  eq(#q, 2, "two entries"); eq(q[1].spell, CLOAK, "in order"); eq(q[1].n, 5, "n"); eq(q[2].keep, 4, "keep")
  eq(q[1].creates, ns.recipeBySpell(CLOAK).creates, "what it makes"); eq(q[1].prof, "Tailoring", "profession")
  check(q[1].status and q[1].statusText, "status")
  q[1].n = 99
  eq(api.queueCount(CLOAK), 5, "a copy")
  ns.me().bags, BAGS = {}, {}
  local miss = api.queueMissing()
  local got = {}
  for _, m in ipairs(miss) do got[m[1]] = m end
  check(got[LINEN] and got[LINEN][2] > 0, "linen missing for the bolts")
  check(got[THREAD] and got[THREAD].vendor, "thread from a vendor, marked")
  check(api.queueSet(CLOAK, 0), "set 0"); eq(api.queueCount(CLOAK), 0, "off")
  check(api.queueRemove(BOLT_SPELL), "remove"); eq(#api.queue(), 0, "empty")
  api.queueAdd(CLOAK, 1); api.queueClear(); eq(#api.queue(), 0, "cleared")
  check(not pcall(function() api.queue = nil end), "writable")
end)

step("the queue window: status and profit on a recipe, a Keep box", function()
  L.clear()
  L.add(BOLT_SPELL, 2)
  BAGS = { [LINEN] = 6 }
  EverlookDBAuctionsAPI = { version = 7, price = function(id) local p = ({ [BOLT] = 200, [LINEN] = 30 })[id]; return p, 60 end }
  ns.listWindow.open()
  check(EverlookCraftList and EverlookCraftList:IsShown(), "window")
  eq(EverlookCraftList.title and EverlookCraftList.title:GetText() or "Crafting queue", "Crafting queue", "title")
  local root = ns.listWindow.rows()[1]
  local d = ns.listWindow.rootDetail(root)
  check(d:find("ready", 1, true) and d:find("profit", 1, true), "detail: " .. d)
  check(not d:find("makes", 1, true), "no \"makes 2\" beside a count of 2: " .. d)
  L.setKeep(BOLT_SPELL, 20)
  d = ns.listWindow.rootDetail(ns.listWindow.rows()[1])
  check(d:find("of 20 in stock", 1, true), "stock in the detail: " .. d)
  EverlookDBAuctionsAPI = nil
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
  L.clear()
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
