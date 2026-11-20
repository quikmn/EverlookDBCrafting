-- The main window (/ecraft): the Skill-Up planner, your characters and their stock, where prices come from, the
-- guide's settings and the data's sources, on EverlookUI's settings window (search box at the top finds any setting).
-- Chat commands follow the one pattern of every EverlookDB addon (EverlookUI COMMANDS.md).
local ADDON, ns = ...

local UI = LibStub("EverlookUI-1")
local U = UI.Util
local rgba = U.rgba

local app = UI:NewApp({
  name = ns.NAME,
  addon = ADDON,
  slash = ns.SLASH,
  aliases = { "/eprof" },
  tagline = "Skill-up routes at today's prices, a live guide, and your materials on every character.",
  accent = { 1, 0.82, 0 },
  width = 760,
  height = 600,
  position = function() return EverlookCraftDB end,
  feedbackURL = "https://everlookdb.com/professions.html",
  siteURL = "https://everlookdb.com/professions.html",
  aiAbout = "EverlookDB Crafting plans the cheapest reliable way to level a profession (only recipes you can learn now for your faction), with prices from EverlookDB Auctions or Auctionator, shows a live guide window, and counts your materials on all your characters.",
})
ns.app = app
function ns.print(msg) app:Print(msg) end

local O = { skill = nil, target = nil }
ns.options = O

local function S() return ns.settings() end
local function setting(key, field, label, desc, keywords, after)
  app:Setting({ key = key, type = "bool", label = label, desc = desc, keywords = keywords,
    get = function() return S()[field] end, set = function(v) S()[field] = v and true or false end,
    default = ns.DEFAULTS.settings[field], after = after })
end

local function routeChanged() if O.refreshPlanner then O.refreshPlanner() end end

setting("vendorpatterns", "vendorPatterns", "Patterns from vendors",
  "Recipes whose pattern a vendor sells (the site's main route has them too). Off: trainer recipes only.",
  { "vendor", "recipe", "pattern", "plans", "schematic", "formula" }, routeChanged)
setting("ahpatterns", "ahPatterns", "Patterns from the auction house",
  "Also drop recipes whose pattern is for sale on the auction house right now (its price counts). Off: never a drop, quest or reputation recipe.",
  { "auction", "drop", "pattern", "buy recipe" }, routeChanged)
setting("noalts", "noAlts", "Don't count my alts' materials",
  "Only this character's bags and bank count as owned; materials on your other characters are bought.",
  { "alts", "twinks", "other characters", "bank", "stock" }, routeChanged)
setting("buffer", "buffer", "Shop for the 90% safety buffer",
  "Buy enough for 9 times out of 10, not just the expected number of crafts, so you don't run short on yellow recipes.",
  { "safety", "buffer", "extra", "spare" }, routeChanged)
setting("auctions", "useAuctions", "Prices from EverlookDB Auctions",
  "The lowest buyout from EverlookDB Auctions' scans for your realm and side, when that addon is installed.",
  { "price", "ah", "auction", "scan", "eah" }, routeChanged)
setting("auctionator", "useAuctionator", "Prices from Auctionator",
  "Auctionator's last scan, for materials EverlookDB Auctions has no price for (or when it isn't installed).",
  { "price", "ah", "auction", "scan" }, routeChanged)
app:Setting({ key = "guide.scale", type = "number", label = "Guide size", min = 0.6, max = 1.6, step = 0.05,
  fmt = "%.2f", desc = "How big the guide window is.", keywords = { "scale", "zoom", "size" }, default = 1,
  get = function() return S().guideScale end,
  set = function(v) S().guideScale = v end, after = function() if ns.guide then ns.guide.applyScale() end end })
app:Setting({ key = "guide.rows", type = "number", label = "Guide rows", min = 8, max = 40, step = 1,
  desc = "How many rows the guide shows before it scrolls.", keywords = { "height", "rows", "lines" }, default = 18,
  get = function() return S().guideRows end,
  set = function(v) S().guideRows = math.floor(v + 0.5) end, after = function() if ns.guide then ns.guide.render() end end })
setting("guide.lock", "guideLocked", "Lock the guide in place", "The guide window can't be dragged while locked.",
  { "lock", "move", "drag" })
setting("guide.auto", "autoGuide", "Open the guide with the profession window",
  "When you open a profession that has a route, its guide opens too.", { "automatic", "open", "show" })

app:Movable({ what = "the guide window", get = function() return S().guideLocked end,
  set = function(locked) S().guideLocked = locked and true or false end })

---------------------------------------------------------------------------------------------------------------------
-- Planner page

local function myProfs()
  local me = ns.me()
  local out = {}
  for id, p in pairs(me and me.profs or {}) do
    if ns.DATA.profs[id] and #(ns.recipes(id) or {}) > 0 then out[#out + 1] = { id = id, p = p } end
  end
  table.sort(out, function(x, y) return ns.profName(x.id) < ns.profName(y.id) end)
  return out
end

function O.selected()
  if O.skill and ns.DATA.profs[O.skill] then return O.skill end
  local last = EverlookCraftChar and EverlookCraftChar.lastSkill
  if last and ns.DATA.profs[last] then O.skill = last return last end
  local mine = myProfs()
  O.skill = mine[1] and mine[1].id or 197
  return O.skill
end

function O.targetOf(skill)
  if O.target and O.targetFor == skill then return O.target end
  local saved = ns.plans.saved(skill)
  return saved and saved.to or ns.plans.defaultTarget(skill)
end

local function learnText(r, st)
  if st.known then return "known" end
  if st.again then return "learned above" end
  if r.auto then return "taught with the rank" end
  local pattern = r.item and r.item ~= 0 and not r.trained
  if pattern then
    if (r.tier[ns.side()] or 9) <= 2 then
      return "vendor pattern " .. ns.money(st.patternPrice) .. ((r.tier[ns.side()] == 2) and " (limited stock)" or "")
    end
    return "pattern from the auction house " .. ns.money(st.patternPrice)
  end
  if r.trained then return "trainer " .. ns.money(st.fee) end
  return "teacher"
end

-- route rows: trainings, steps, the stall
local function routeRows(route)
  local rows = {}
  if not route then return rows end
  local trs = {}
  for _, tr in ipairs(route.trainings or {}) do trs[#trs + 1] = tr end
  local ti = 1
  for _, st in ipairs(route.steps) do
    while trs[ti] and trs[ti].cap <= st.from do rows[#rows + 1] = { kind = "train", tr = trs[ti] }; ti = ti + 1 end
    rows[#rows + 1] = { kind = "step", st = st }
  end
  while trs[ti] do rows[#rows + 1] = { kind = "train", tr = trs[ti] }; ti = ti + 1 end
  if route.stall then rows[#rows + 1] = { kind = "stall", at = route.stall } end
  return rows
end
O.routeRows = routeRows

function O.rowTitle(row, skill)
  if row.kind == "train" then
    return ("Train %s"):format(ns.DATA.rankNames[row.tr.step] or "the next rank")
  elseif row.kind == "stall" then
    return ("The route stops at %d"):format(row.at)
  end
  local r = ns.plans.recipe(skill, row.st.spell)
  return r and r.name or ("spell " .. row.st.spell)
end

function O.rowDetail(row, skill)
  if row.kind == "train" then
    local tr = row.tr
    local parts = { ("at skill %d"):format(tr.at) }
    if tr.level then parts[#parts + 1] = ("level %d"):format(tr.level) end
    parts[#parts + 1] = "fee " .. ns.money(tr.fee)
    parts[#parts + 1] = ("raises the cap to %d"):format(tr.newCap)
    return table.concat(parts, "  \194\183  ")
  elseif row.kind == "stall" then
    return "Nothing you can learn reliably for your side raises it further. Turn on more pattern sources, or see the site's guide."
  end
  local st = row.st
  local r = ns.plans.recipe(skill, st.spell)
  local col = r and ns.widgets.colorCode(ns.colorAt(r, st.from)) or "|cffffffff"
  local crafts = st.n90 > st.n and ("%d crafts (%d at 90%%)"):format(st.n, st.n90) or ("%d crafts"):format(st.n)
  local each = (st.est and "\226\137\136 " or "") .. ns.money(st.each) .. " each"
  if st.est then each = "\226\137\136 price unknown" end
  return ("%s%d\226\128\147%d|r  \194\183  %s  \194\183  %s  \194\183  %s"):format(col, st.from, st.to, crafts, each,
    r and learnText(r, st) or "")
end

-- the NPCs a row's Map button looks among
function O.rowNpcs(row, skill)
  if row.kind == "train" then
    local rk = ns.DATA.ranks[skill] and ns.DATA.ranks[skill][row.tr.step]
    if not rk then return nil end
    if #rk[5] > 0 then return rk[5] end
    if #rk[7] > 0 then return rk[7] end
    return nil
  elseif row.kind == "step" and not row.st.known then
    local r = ns.plans.recipe(skill, row.st.spell)
    local ri = r and r.item ~= 0 and ns.DATA.recipeItems[r.item]
    if ri and #ri[2] > 0 and not r.trained then
      local ids = {}
      for i = 1, #ri[2], 2 do ids[#ids + 1] = ri[2][i] end
      return ids
    end
  end
end

function O.rowTooltip(row, skill)
  if row.kind ~= "step" then return nil end
  local r = ns.plans.recipe(skill, row.st.spell)
  if not r then return nil end
  local est = r.learnKnown and "" or "~"
  local lines = { r.name, ("learn %s%d  \194\183  |cffff8040%d|r  |cffffff00%d|r  |cff40c040%d|r  |cff808080%d|r"):format(est, r.learn, r.learn, r.yellow, r.green, r.gray) }
  if not r.learnKnown then lines[#lines + 1] = "~ the learn skill is an estimate (no trainer window has confirmed it yet)." end
  for _, m in ipairs(ns.matsOf(r)) do
    local name = ns.itemInfo(m[1])
    local have = ns.stock.usable(m[1])
    lines[#lines + 1] = ("%d x %s  (you have %d)"):format(m[2], name, have)
  end
  return lines
end

local function tilesText(route)
  local t = route.totals
  local function amount(v, unknown)
    if v == 0 and (unknown or 0) == 0 then return "|cff8d94a3none|r" end
    if unknown and unknown > 0 then return ns.money(v) .. " |cff8d94a3+ " .. unknown .. " ?|r" end
    return ns.money(v)
  end
  return amount(t.mats, t.matsUnpriced), amount(t.patterns, t.patternsUnknown), amount(t.fees, t.feesUnknown),
    amount(t.total, t.matsUnpriced + t.patternsUnknown + t.feesUnknown)
end

app:Section("planner", "Skill-up planner", function(stack)
  local T = stack.T
  UI.Header(stack, "Skill-up planner", "The cheapest way to your target at today's prices. Every step is a recipe you know or can learn now for your faction.")
  UI.Dropdown(stack, {
    label = "Profession", desc = "Your professions first. Open a profession window once so the planner knows your recipes.",
    keywords = { "profession", "tailoring", "alchemy", "blacksmithing" },
    items = function()
      local out, mine = {}, {}
      for _, m in ipairs(myProfs()) do
        mine[m.id] = true
        out[#out + 1] = { value = m.id, text = ("%s  %s/%s"):format(ns.profName(m.id), m.p.rank or "?", m.p.max or "?") }
      end
      for _, p in ipairs(ns.professionList()) do
        if not mine[p.id] and #(ns.recipes(p.id) or {}) > 0 then out[#out + 1] = { value = p.id, text = p.name .. "  (not yours)" } end
      end
      return out
    end,
    get = function() return O.selected() end,
    set = function(v) O.skill, O.target, O.targetFor = v, nil, nil end,
    after = function() routeChanged() end,
  })
  UI.Stat(stack, "Your skill", function()
    local skill = O.selected()
    local rank, max, rec = ns.plans.skillNow(skill)
    if not rank then return "|cff8d94a3not learned (or not read yet)|r" end
    local n = 0
    for _ in pairs(rec.known or {}) do n = n + 1 end
    return ("%d / %d  \194\183  %s"):format(rank, max or 0, n > 0 and (n .. " recipes known") or "|cff8d94a3open its window once to read your recipes|r")
  end)
  UI.Slider(stack, {
    label = "Target skill", desc = "Where the route ends. Default: the next rank's cap above your skill.",
    keywords = { "target", "goal", "skill", "level" }, min = 2, max = 300, step = 1,
    get = function() return O.targetOf(O.selected()) end,
    set = function(v) O.target, O.targetFor = math.floor(v + 0.5), O.selected() end,
  })
  UI.Header(stack, "Route choices")
  app:Widget(stack, "vendorpatterns")
  app:Widget(stack, "ahpatterns")
  app:Widget(stack, "noalts")
  app:Widget(stack, "buffer")
  local row = UI.ButtonRow(stack, {
    { label = "Calculate", width = 150, style = "accent", onClick = function()
      local skill = O.selected()
      local route, err = ns.plans.calculate(skill, O.targetOf(skill))
      if not route then app:Print(err) end
      O.refreshPlanner()
    end, desc = "Work out the cheapest route with today's prices and keep it for this character." },
    { label = "Open guide", width = 130, onClick = function() if ns.guide then ns.guide.open(O.selected()) end end,
      desc = "The small checklist window that walks the route as you craft." },
    refresh = function(f)
      local saved = ns.plans.current(O.selected(), O.targetOf(O.selected()))
      f.buttons[1]:SetText(saved and "Recalculate" or "Calculate")
      f.buttons[2]:SetUsable(ns.plans.saved(O.selected()) ~= nil)
    end,
  })
  O.buttons = row

  UI.Header(stack, "Route")
  local info = UI.Note(stack, function()
    local skill = O.selected()
    local route = ns.plans.saved(skill)
    if not route then return "No route yet. Pick a target and press Calculate." end
    local parts = { ("%s %d to %d, calculated %s for %s."):format(ns.profName(skill), route.from, route.to,
      date("%d %b %H:%M", route.at), route.side == "h" and "Horde" or "Alliance") }
    if route.to ~= O.targetOf(skill) or route.key ~= table.concat({ S().vendorPatterns and 1 or 0, S().ahPatterns and 1 or 0, S().noAlts and 1 or 0, S().buffer and 1 or 0 }, "") then
      parts[#parts + 1] = "|cffffd100The target or a switch changed: press Calculate for a new route.|r"
    end
    if route.estimated then
      parts[#parts + 1] = "\226\137\136 Some materials have no price: the route chose by an estimate, and totals count only real prices."
    end
    return table.concat(parts, " ")
  end)
  O.info = info

  -- tiles and the bar
  local box = CreateFrame("Frame")
  box:SetSize(stack.width, 104)
  box.tiles = ns.widgets.Tiles(box, 4, stack.width, T)
  box.tiles:SetPoint("TOPLEFT", 0, 0)
  box.resale = UI.Text(box, T.fontSmall + 1, T.muted)
  box.resale:SetPoint("TOPLEFT", 0, -62)
  box.resale:SetPoint("RIGHT", 0, 0)
  box.resale:SetWordWrap(false)
  box.bar = ns.widgets.SkillBar(box, stack.width, T, 8)
  box.bar:SetPoint("TOPLEFT", 0, -80)
  stack:Add(box, 104, 8)
  O.box = box

  local list = UI.List(stack, {
    rowHeight = 40, max = 80, icon = function(row)
      if row.kind == "train" then return ns.profIcon(O.selected()) end
      if row.kind == "stall" then return "Interface\Icons\INV_Misc_QuestionMark" end
      return ns.recipeIcon(ns.plans.recipe(O.selected(), row.st.spell))
    end,
    empty = "The steps show here once you press Calculate.",
    items = function() return routeRows(ns.plans.saved(O.selected())) end,
    title = function(row) return O.rowTitle(row, O.selected()) end,
    detail = function(row) return O.rowDetail(row, O.selected()) end,
    color = function(row)
      if row.kind == "train" then return T.gold end
      if row.kind == "stall" then return T.danger end
      if row.st.known then return T.text end
      return nil
    end,
    tooltip = function(row) return O.rowTooltip(row, O.selected()) end,
    buttons = { { label = "Map", width = 56, shown = function(row) return O.rowNpcs(row, O.selected()) ~= nil end,
      onClick = function(row)
        local id = ns.map.nearest(O.rowNpcs(row, O.selected()))
        if id then ns.map.pin(id) else app:Print("no one for your side in the data.") end
      end } },
  })
  O.list = list

  function O.refreshPlanner()
    local skill = O.selected()
    local route = ns.plans.saved(skill)
    if route then
      local a, b, c, d = tilesText(route)
      box.tiles:Set(1, "MATERIALS TO BUY", a, "What the materials you don't have yet cost. \"?\" counts materials with no price yet.")
      box.tiles:Set(2, "PATTERNS", b, "Vendor patterns (and auction house patterns, when that switch is on) for recipes you don't know yet.")
      box.tiles:Set(3, "TRAINER FEES", c, "Recipe fees and rank training. \"?\" where the fee isn't known.")
      box.tiles:Set(4, "TOTAL", d, "Materials, patterns and fees. Never a guessed price.")
      box.resale:SetText(route.resale and ("What the crafts would sell for at the auction house: %s (not counted)"):format(ns.money(route.resale)) or "")
      local rank = ns.plans.skillNow(skill)
      box.bar:Set(rank or route.from, 0, route.to)
    else
      for i, l in ipairs({ "MATERIALS TO BUY", "PATTERNS", "TRAINER FEES", "TOTAL" }) do box.tiles:Set(i, l, "\226\128\148") end
      box.resale:SetText("")
      box.bar:Set(ns.plans.skillNow(skill) or 0, 0, O.targetOf(skill))
    end
    stack:RefreshAll()
  end
  O.refreshPlanner()
end, { icon = "hammer", desc = "The cheapest reliable route to your target, at today's prices." })

---------------------------------------------------------------------------------------------------------------------
-- Characters and stock

local function ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
  if d < 86400 * 2 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " days ago"
end

local function charRows()
  local out = {}
  for guid, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do out[#out + 1] = { guid = guid, c = c } end
  table.sort(out, function(x, y) return (x.c.name or "") < (y.c.name or "") end)
  return out
end

local function countItems(t)
  local n = 0
  for _, v in pairs(t or {}) do n = n + v end
  return n
end

app:Section("characters", "Characters", function(stack)
  UI.Header(stack, "Characters", "Your characters this addon has seen, their professions and what they carry. Kept only on this PC, in this addon's own saved variables: never uploaded.")
  UI.List(stack, {
    rowHeight = 40,
    empty = "No characters yet. Log in and open your bags.",
    items = charRows,
    title = function(e)
      local c = e.c
      return ("%s%s|r  |cff8d94a3%s \194\183 %s|r"):format(e.guid == ns.guid() and "|cffffd100" or "|cffffffff", c.name or "?", c.realm or "?",
        c.side == "h" and "Horde" or "Alliance")
    end,
    detail = function(e)
      local c = e.c
      local profs = {}
      for id, p in pairs(c.profs or {}) do
        if ns.DATA.profs[id] then profs[#profs + 1] = ("%s %s"):format(ns.profName(id), p.rank or "?") end
      end
      table.sort(profs)
      return ("%s  \194\183  %d in bags, %d in bank (bank %s)"):format(#profs > 0 and table.concat(profs, ", ") or "no professions read",
        countItems(c.bags), countItems(c.bank), ago(c.bankAt))
    end,
    buttons = { { label = "Forget", width = 80, confirm = true, shown = function(e) return e.guid ~= ns.guid() end,
      onClick = function(e) EverlookCraftDB.chars[e.guid] = nil; app:Refresh() end } },
  })
  UI.Note(stack, "Open each character's bank once so its bank counts. Materials on other characters count as owned in the planner unless \"Don't count my alts' materials\" is on.")
end, { icon = "user" })

---------------------------------------------------------------------------------------------------------------------
-- Prices

app:Section("prices", "Prices", function(stack)
  UI.Header(stack, "Prices", "Where the planner's prices come from. A material with no price shows \"?\": it is never guessed in a total.")
  UI.Stat(stack, "EverlookDB Auctions", function()
    return ns.prices.auctionsLoaded() and "|cff62cf88found|r: lowest buyout of your realm's scans" or "|cff8d94a3not installed|r"
  end)
  UI.Stat(stack, "Auctionator", function()
    return ns.prices.auctionatorLoaded() and "|cff62cf88found|r: its last scan" or "|cff8d94a3not installed|r"
  end)
  app:Widget(stack, "auctions")
  app:Widget(stack, "auctionator")
  UI.Header(stack, "Vendors")
  UI.Note(stack, "Vendor goods (thread, dyes, vials, flux) cost what a merchant last showed you, else what WoW Forever's vendors charge in EverlookDB's data. Visiting a merchant updates them.")
end, { icon = "coins" })

---------------------------------------------------------------------------------------------------------------------
-- Guide

app:Section("guide", "Guide window", function(stack)
  UI.Header(stack, "Guide window", "A small checklist that walks your route: what to buy at the auction house and vendors, materials still needed, and the steps with your live skill.")
  app:Widget(stack, "guide.scale")
  app:Widget(stack, "guide.rows")
  app:Widget(stack, "guide.lock")
  app:Widget(stack, "guide.auto")
  UI.ButtonRow(stack, {
    { label = "Open guide", width = 140, onClick = function() if ns.guide then ns.guide.open() end end,
      desc = "Opens the guide of your last route.", keywords = { "show", "checklist" } },
  })
  UI.Note(stack, "Right-click a step in the guide to mark it done (or not). The guide selects the step's recipe in your profession window; crafting stays with the game's Create button.")
end, { icon = "list" })

---------------------------------------------------------------------------------------------------------------------
-- About

app:Section("about", "About", function(stack)
  UI.Header(stack, "About", "Data from everlookdb.com, the same rules as the site's professions guide.")
  UI.Note(stack, "Every step must reliably give its skill-ups: a recipe you know, or one you can learn now for your faction (a trainer, a teacher outside a dungeon, a vendor pattern). Dungeon, drop, quest, reputation and unknown recipes are never in the route. A learn skill marked ~ is an estimate.")
  UI.Header(stack, "Sources")
  UI.Note(stack, "Recipes, skill colours and materials: the WoW Forever client data. Trainers, vendors, rank fees and spawns: classic-db (CMaNGOS, GPL-3.0). What WoW Forever's vendors charge, server learn ranks and where its NPCs stand: Efficient Games' EG Link (CC BY 4.0), changed by EverlookDB. Prices: EverlookDB Auctions or Auctionator, on your PC.")
  UI.Stat(stack, "Data build", function() return ns.DATA and ns.DATA.build or "?" end)
  UI.Header(stack, "Chat commands")
  UI.Note(stack, "/ecraft  this window (also /eprof)\n/ecraft plan [profession]  the planner\n/ecraft guide  the guide window\n/ecraft status  what the addon knows\n/ecraft search <words>  find a setting\n/ecraft help  all of this in chat")
end, { icon = "info" })

---------------------------------------------------------------------------------------------------------------------
-- Commands

app:Command("plan", "plan [profession]", "the Skill-up planner, for a profession", function(rest)
  rest = U.Trim(rest or ""):lower()
  if rest ~= "" then
    for _, p in ipairs(ns.professionList()) do
      if p.name:lower():sub(1, #rest) == rest then O.skill, O.target, O.targetFor = p.id, nil, nil break end
    end
  end
  app:Open("planner")
  if O.refreshPlanner then O.refreshPlanner() end
end, { "planner", "route" })

app:Command("guide", "guide", "open or close the guide window", function()
  if ns.guide then ns.guide.toggle() end
end)

app:StatusLines(function()
  local chars, profs = 0, 0
  for _, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do
    chars = chars + 1
    for _ in pairs(c.profs or {}) do profs = profs + 1 end
  end
  local lines = { ("%d characters, %d professions read. Prices: %s."):format(chars, profs,
    ns.prices.auctionsLoaded() and "EverlookDB Auctions" or ns.prices.auctionatorLoaded() and "Auctionator" or "none (vendor goods only)") }
  for skill, r in pairs(EverlookCraftChar and EverlookCraftChar.routes or {}) do
    lines[#lines + 1] = ("Route: %s %d to %d, %d steps."):format(ns.profName(skill), r.from, r.to, #r.steps)
  end
  return lines
end)

ns.onRoute = function() if O.refreshPlanner and app:IsShown() then O.refreshPlanner() end end
ns.onSkills = function() if O.refreshPlanner and app:IsShown() then O.refreshPlanner() end end

app:RegisterSlash("EVERLOOKCRAFT") -- /ecraft, also /eprof
