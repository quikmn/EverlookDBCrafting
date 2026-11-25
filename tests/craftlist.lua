-- Offline tests for the Crafting list and the recipe browser (CraftList.lua, Browser.lua and their windows) against
-- wowmock.lua, in their own Lua state: the material tree (stock shared out across recipes, alts, "don't count my
-- alts"), craft or buy, a loop cut, vendor goods kept off the shopping list, sending to EverlookDB Auctions, a craft
-- taking one off the count, the browser's search by reagent and filters, how to learn a recipe (trainer, vendor,
-- Merchant's Favor, drops, source unknown), where a reagent comes from, the slash commands, both windows, and the
-- settings window's search box top centre.
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
IsShiftKeyDown = IsShiftKeyDown or function() return false end

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

local L, B
local LINEN, BOLT, THREAD = 2589, 2996, 2320
local BOLT_SPELL, CLOAK, VEST = 2963, 2387, 2385

step("loads in TOC order", function()
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  L, B = ns.craftList, ns.browser
  check(L and B and ns.listWindow and ns.browserWindow, "modules missing")
  -- a made-up pair of recipes that make each other (a transmute loop), added before the first lookup
  ns.DATA.items[990001] = { "Test Essence A", 2, 134400, nil, 1, "made", {} }
  ns.DATA.items[990002] = { "Test Essence B", 2, 134400, nil, 1, "made", {} }
  ns.DATA.profs[9999] = { name = "Loopcraft", alias = {}, recipes = {
    { 990011, "Make A", 990001, 1, 1, 10, 20, 30, { 990002, 1 }, 0, nil, 0, 0, 0, 0, 0, "t", 0, 0, 0 },
    { 990012, "Make B", 990002, 1, 1, 10, 20, 30, { 990001, 1 }, 0, nil, 0, 0, 0, 0, 0, "t", 0, 0, 0 },
  } }
end)

step("setup: you know Bolt of Linen Cloth and Linen Cloak; linen in your bags, bolts on an alt", function()
  local me = ns.me()
  me.profs[197] = { rank = 60, max = 75, known = { [BOLT_SPELL] = true, [CLOAK] = true } }
  me.profs[9999] = { rank = 30, max = 75, known = { [990011] = true, [990012] = true } }
  me.bags = { [LINEN] = 4 }
  me.bank = {}
  EverlookCraftDB.chars["Player-1-Alt"] = { name = "Bankalt", profs = {}, bags = {}, bank = { [BOLT] = 2 } }
  eq(L.knownMaker(BOLT).spell, BOLT_SPELL, "who makes bolts")
  eq(L.mode(BOLT), "craft", "a material you can make is crafted by default")
  eq(L.mode(THREAD), "buy", "vendor goods are bought by default")
end)

step("the material tree: bolts from the alt first, the rest crafted from linen; thread from a vendor", function()
  L.clear()
  check(L.add(CLOAK, 3), "add")
  local t = L.tree()
  eq(#t.roots, 1, "one recipe")
  local root = t.roots[1]
  eq(root.n, 3, "crafts")
  local bolt, thread
  for _, k in ipairs(root.kids) do
    if k.id == BOLT then bolt = k elseif k.id == THREAD then thread = k end
  end
  eq(bolt.need, 3, "bolts needed"); eq(bolt.have, 2, "bolts on the alt"); eq(bolt.short, 1, "bolts short")
  eq(bolt.mode, "craft", "bolts crafted"); eq(bolt.crafts, 1, "one bolt to make")
  eq(bolt.kids[1].id, LINEN, "bolt from linen"); eq(bolt.kids[1].need, 2, "linen for one bolt"); eq(bolt.kids[1].short, 0, "linen in bags")
  check(thread.vendor and thread.short == 3, "thread from a vendor")
  eq(#t.missing, 1, "only the thread is missing")
  check(t.missing[1].vendor, "missing thread marked vendor")
  eq(#L.shoppingItems(t), 0, "vendor goods never on the shopping list")
  check(L.whereText(BOLT):find("2 on Bankalt", 1, true), "where: " .. L.whereText(BOLT))
end)

step("what you own is shared out in list order: a second recipe gets what is left", function()
  L.add(VEST, 2)
  local t = L.tree()
  local vest = t.roots[2]
  local bolt = vest.kids[1].id == BOLT and vest.kids[1] or vest.kids[2]
  eq(bolt.have, 0, "the alt's bolts went to the cloak")
  eq(bolt.crafts, 2, "two bolts to make")
  local linen = bolt.kids[1]
  eq(linen.need, 4, "linen for two bolts"); eq(linen.have, 2, "linen left after the cloak's bolt"); eq(linen.short, 2, "linen short")
  local items = L.shoppingItems(t)
  eq(#items, 1, "linen to buy"); eq(items[1][1], LINEN, "linen"); eq(items[1][2], 2, "two linen")
end)

step("'don't count my alts' leaves the alt's bolts out", function()
  EverlookCraftDB.settings.noAlts = true
  local t = L.tree()
  local bolt = t.roots[1].kids[1].id == BOLT and t.roots[1].kids[1] or t.roots[1].kids[2]
  eq(bolt.have, 0, "alt counted")
  check(not L.whereText(BOLT):find("Bankalt", 1, true), "alt named with noAlts on")
  EverlookCraftDB.settings.noAlts = false
end)

step("an alt on another realm: its bolts can't be mailed, so they don't count and it isn't named", function()
  local alt = EverlookCraftDB.chars["Player-1-Alt"]
  alt.realm = "Other Realm"
  local t = L.tree()
  local bolt = t.roots[1].kids[1].id == BOLT and t.roots[1].kids[1] or t.roots[1].kids[2]
  eq(bolt.have, 0, "another realm's bolts counted")
  check(not L.whereText(BOLT):find("Bankalt", 1, true), "another realm's alt named: " .. L.whereText(BOLT))
  alt.realm = "Mock Realm"
  t = L.tree()
  bolt = t.roots[1].kids[1].id == BOLT and t.roots[1].kids[1] or t.roots[1].kids[2]
  check(bolt.have > 0, "an alt on your realm counts")
  check(L.whereText(BOLT):find("2 on Bankalt", 1, true), "where: " .. L.whereText(BOLT))
  alt.realm = nil
end)

step("craft or buy: a ticked material is bought, not broken down", function()
  L.setMode(BOLT, "buy")
  local t = L.tree()
  local bolt = t.roots[1].kids[1].id == BOLT and t.roots[1].kids[1] or t.roots[1].kids[2]
  eq(bolt.mode, "buy", "mode"); eq(bolt.kids, nil, "no breakdown")
  local got = {}
  for _, it in ipairs(L.shoppingItems(t)) do got[it[1]] = it[2] end
  eq(got[BOLT], 3, "1 bolt for the cloak + 2 for the vest")
  eq(got[LINEN], nil, "no linen when bolts are bought")
  L.setMode(BOLT, nil)
end)

step("a loop (A from B, B from A) is cut: bought where it would feed itself", function()
  L.clear()
  L.add(990011, 1)
  local t = L.tree()
  local b = t.roots[1].kids[1]
  eq(b.id, 990002, "B under A"); eq(b.mode, "craft", "B crafted")
  local a = b.kids[1]
  eq(a.id, 990001, "A under B"); check(a.cut, "loop not cut"); eq(a.mode, "buy", "A bought"); eq(a.kids, nil, "A not broken down again")
  eq(t.missing[1].id, 990001, "A on the list to buy")
  L.clear()
end)

step("each craft of a listed recipe takes one off; the last one takes it off the list", function()
  L.add(CLOAK, 2)
  MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", CLOAK)
  eq(L.find(CLOAK).n, 1, "one off")
  MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", CLOAK)
  eq(L.find(CLOAK).n, 1, "someone else's cast counted")
  MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", CLOAK)
  eq(L.find(CLOAK), nil, "still on the list at 0")
end)

step("send missing to EverlookDB Auctions: its shopping list, vendor goods left out; says why when it can't", function()
  L.clear()
  EverlookDBAuctionsAPI = nil
  local ok, why = L.sendToAuctions()
  check(ok == false and why:find("isn't installed", 1, true), "no Auctions: " .. tostring(why))
  local sent
  EverlookDBAuctionsAPI = { version = 2, addShoppingList = function(name, items) sent = { name = name, items = items }; return true, true end }
  L.add(VEST, 2)
  ns.me().bags = {}
  EverlookCraftDB.chars["Player-1-Alt"].bank = {}
  L.setMode(BOLT, "buy")
  ok = L.sendToAuctions()
  check(ok and sent, "not sent")
  eq(sent.name, "Crafting queue", "list name")
  eq(#sent.items, 1, "only the bolts (thread is a vendor good)")
  eq(sent.items[1][1], BOLT, "bolts"); eq(sent.items[1][2], 2, "two")
  -- item names still loading: it tries again by itself and only the last try speaks (never "couldn't send: loading")
  local tries = 0
  EverlookDBAuctionsAPI = { version = 2, addShoppingList = function(name, items)
    tries = tries + 1
    if tries < 3 then return false, "loading" end
    sent = { name = name, items = items }; return true, false end }
  sent = nil
  MOCK.timers, MOCK.log = {}, {}
  ok, why = L.sendToAuctions()
  check(ok == nil and why == "loading", "first try waits")
  MOCK.RunTimers()
  check(not sent and #MOCK.log == 0, "second try still loading, says nothing: " .. tostring(MOCK.log[1]))
  MOCK.RunTimers()
  check(sent and tries == 3, "sent on the third try")
  eq(#MOCK.log, 1, "one message")
  check(MOCK.log[1]:find("shopping list", 1, true) and not MOCK.log[1]:find("loading", 1, true), "message: " .. MOCK.log[1])
  L.setMode(BOLT, nil)
  EverlookDBAuctionsAPI = { version = 1 }
  ok, why = L.sendToAuctions()
  eq(ok, false, "version 1 has no shopping lists")
  EverlookDBAuctionsAPI = nil
  ns.me().bags = { [LINEN] = 4 }
  EverlookCraftDB.chars["Player-1-Alt"].bank = { [BOLT] = 2 }
  L.clear()
end)

step("browser: search by recipe name and by reagent; filters known, not known, favourites", function()
  local all = B.list(197, "", "all")
  check(#all > 50, "Tailoring has recipes")
  for i = 2, #all do check(all[i - 1].r.learn <= all[i].r.learn, "not sorted by learn skill") end
  local byName = B.list(197, "linen cloak", "all")
  eq(byName[1].r.spell, CLOAK, "by name")
  eq(byName[1].byReagent, false, "a name match")
  for _, e in ipairs(B.list(197, "silk cloth", "all")) do
    check(e.r.name:lower():find("silk cloth", 1, true) or e.byReagent, "\"silk cloth\" is a phrase: " .. e.r.name)
  end
  local byReagent = B.list(197, "coarse thread", "all")
  local found
  for _, e in ipairs(byReagent) do if e.r.spell == CLOAK then found = e end end
  check(found and found.byReagent, "Linen Cloak not found by its reagent")
  local known = B.list(197, "", "known")
  eq(#known, 2, "known"); check(known[1].known, "known flag")
  eq(#B.list(197, "", "unknown"), #all - 2, "not known")
  eq(#B.list(197, "", "favs"), 0, "no favourites")
  B.toggleFav(VEST)
  eq(#B.list(197, "", "favs"), 1, "a favourite"); eq(B.list(197, "", "favs")[1].r.spell, VEST, "the vest")
  B.toggleFav(VEST)
  eq(B.findByName("linen cloak").spell, CLOAK, "find by name")
  eq(B.findByName("Bolt of Linen").spell, BOLT_SPELL, "find by the start of a name")
  eq(B.findByName("no such recipe at all"), nil, "nothing found")
end)

step("browser: the other faction's recipes are hidden unless asked for", function()
  local total, other = 0, nil
  for _, p in ipairs(ns.professionList()) do
    for _, r in ipairs(ns.recipes(p.id) or {}) do
      if r.why.a == "otherSide" and not other then other = r end
    end
  end
  if not other then return end -- the data has none for the Alliance
  local function has(list) for _, e in ipairs(list) do if e.r == other then return true end end end
  check(not has(B.list(other.skill, "", "all")), "the other faction's recipe listed")
  check(has(B.list(other.skill, "", "all", true)), "not listed when asked for")
end)

-- the first recipe in the data that fits
local function find(fn)
  for _, p in ipairs(ns.professionList()) do
    for _, r in ipairs(ns.recipes(p.id) or {}) do
      if fn(r) then return r end
    end
  end
end
local function text(lines) local t = {} for _, l in ipairs(lines) do t[#t + 1] = l.text end return table.concat(t, " | ") end

step("how to learn: trainer with a Map, automatic, source unknown said plainly", function()
  local vest = ns.recipeBySpell(VEST)
  local lines = B.learnLines(vest, "a")
  check(lines[1].text:find("Trainer", 1, true) and lines[1].npcs and #lines[1].npcs > 0, "trainer line: " .. text(lines))
  eq(B.learnShort(vest, "a"), "trainer", "short")
  eq(B.learnLines(ns.recipeBySpell(BOLT_SPELL), "a")[1].text, "Learned automatically with the profession", "automatic")
  local unknown = find(function(r) return r.why.a == "unknown" and not r.trained and not r.auto
    and not (r.item ~= 0 and ns.DATA.recipeItems[r.item]) end)
  if unknown then
    local l = B.learnLines(unknown, "a")
    check(text(l):find("Source unknown", 1, true) and l[#l].warn, "unknown: " .. text(l))
    check(B.learnShort(unknown, "a"):find("source unknown", 1, true), "short unknown")
  end
end)

step("how to learn: vendor patterns, Merchant's Favor vendors and drops from the data", function()
  local vendor = find(function(r)
    local ri = r.item ~= 0 and ns.DATA.recipeItems[r.item]
    if not ri or #ri[2] == 0 then return false end
    for i = 1, #ri[2], 2 do local n = ns.DATA.npcs[ri[2][i]]; if n and ns.map.usable(n[2], "a") then return true end end
  end)
  check(vendor, "no vendor pattern in the data")
  local l = B.learnLines(vendor, "a")
  local sold
  for _, x in ipairs(l) do if x.text:find("^Sold by %d") then sold = x end end
  check(sold and sold.npcs, "vendor line with Map: " .. text(l))
  local favor = find(function(r)
    local ri = r.item ~= 0 and ns.DATA.recipeItems[r.item]
    if not (ri and ri.sold) then return false end
    for i = 1, #ri.sold, 6 do
      local n = ns.DATA.npcs[ri.sold[i]]
      if ri.sold[i + 1] == 3402 and n and ns.map.usable(n[2], "a") then return true end
    end
  end)
  if favor then check(text(B.learnLines(favor, "a")):find("Merchant's Favor", 1, true), "Favor: " .. text(B.learnLines(favor, "a"))) end
  local drop = find(function(r) local ri = r.item ~= 0 and ns.DATA.recipeItems[r.item]; return ri and ri.drop and #ri.drop > 0 end)
  check(drop, "no drop recipe in the data")
  local dl = B.learnLines(drop, "a")
  check(text(dl):find("Drops from", 1, true), "drop: " .. text(dl))
end)

step("where a reagent comes from: crafted by your character, vendors with a Map, the auction house", function()
  local bolt = B.reagentLines(BOLT, "a")
  check(bolt[1].text:find("Bolt of Linen Cloth", 1, true) and bolt[1].text:find("known by Tester", 1, true),
    "crafted: " .. text(bolt))
  local thread = B.reagentLines(THREAD, "a")
  local v
  for _, x in ipairs(thread) do if x.text:find("^Vendors") then v = x end end
  check(v and v.npcs and #v.npcs > 0, "vendors: " .. text(thread))
  check(text(thread):find("Auction house: no price yet", 1, true), "no AH price said plainly")
  local linen = B.reagentLines(LINEN, "a")
  check(text(linen):find("Looted from humanoids", 1, true), "gathered: " .. text(linen))
  eq(B.gatherText("Copper Ore"), "Mining", "ore")
  eq(B.gatherText("Light Leather"), "Skinning", "leather")
  check(B.gatherText("Peacebloom"):find("Gathered in the world", 1, true), "anything else")
end)

step("source unknown only when no trainer, vendor, Favor vendor, drop or quest is in the data", function()
  local n, wrong = 0, 0
  for _, p in ipairs(ns.professionList()) do
    for _, r in ipairs(ns.recipes(p.id) or {}) do
      local ri = r.item ~= 0 and ns.DATA.recipeItems[r.item]
      if r.why.a == "unknown" and ri and ((ri.sold and #ri.sold > 0) or (ri.drop and #ri.drop > 0)) then
        n = n + 1
        if not B.hasSource(r, "a") then wrong = wrong + 1 end
        local t = text(B.learnLines(r, "a"))
        check(not t:find("Source unknown", 1, true), r.name .. " has a source: " .. t)
      end
    end
  end
  eq(wrong, 0, "recipes with sources counted unknown")
  local r = find(function(x) return x.attLearn and not x.learnKnown and x.attLearn ~= x.learn end)
  if r then check(B.learnText(r):find("AllTheThings", 1, true), "AllTheThings learn skill not shown") end
  local hammer = find(function(x) return x.tools ~= nil end)
  if hammer then check(B.toolsText(hammer), "tool name") end
end)

step("can make with your bags", function()
  ns.me().bags = { [LINEN] = 5 }
  eq(B.canMake(ns.recipeBySpell(BOLT_SPELL)), 2, "5 linen, 2 per bolt")
  eq(B.canMake(ns.recipeBySpell(CLOAK)), 0, "no bolts")
end)

step("slash: list add, list, recipes with a search; both windows build and show", function()
  L.clear()
  SlashCmdList.EVERLOOKCRAFT("list add linen cloak 2")
  eq(L.find(CLOAK).n, 2, "added from chat")
  check(EverlookCraftList and EverlookCraftList:IsShown(), "list window not shown")
  local rows = ns.listWindow.rows()
  check(#rows >= 4, "rows: " .. #rows)
  SlashCmdList.EVERLOOKCRAFT("recipes coarse thread")
  check(EverlookCraftBrowser and EverlookCraftBrowser:IsShown(), "browser not shown")
  check(EverlookCraftList:IsShown(), "opening the browser closed the list")
  eq(ns.browserWindow.query, "coarse thread", "search from chat")
  check(ns.browserWindow.show(VEST), "show a recipe")
  eq(ns.browserWindow.selected, VEST, "selected")
  ns.browserWindow.renderDetail()
  SlashCmdList.EVERLOOKCRAFT("recipes")
  check(not EverlookCraftBrowser:IsShown(), "recipes toggles the browser")
  SlashCmdList.EVERLOOKCRAFT("list clear")
  eq(#L.entries(), 0, "cleared")
  ns.listWindow.render()
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

step("the settings window: search box top centre, one page each for recipes and the list", function()
  SlashCmdList.EVERLOOKCRAFT("")
  local f = ns.app.window
  check(f and f:IsShown(), "window")
  check(f.topBar and f.searchBox:GetParent() == f.topBar, "search box not in the top bar")
  local p = { f.searchBox:GetPoint(1) }
  eq(p[1], "TOP", "search box anchored top centre")
  check(ns.app.sections.recipes and ns.app.sections.list, "pages")
  ns.app:Open("recipes")
  ns.app:Open("list")
  check(#MOCK.errors == 0, "errors: " .. tostring(MOCK.errors[1]))
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
