-- EverlookDB Crafting: the shared pieces. Saved variables, the character, money text, and the recipe data turned
-- into tables the planner can use. Every game call is guarded: the WoW Forever client can withhold values (secret
-- values) or lack an older function.
--
-- EverlookCraftDB (account, this PC only, never uploaded): settings, your characters (name, realm, side, professions
-- with skill and known recipes, what is in their bags and bank), reagent fixes seen in profession windows, vendor
-- prices seen at merchants. EverlookCraftChar (per character): the Skill-Up routes and the steps you marked done.
local ADDON, ns = ...

ns.NAME = "EverlookDB Crafting"
ns.SLASH = "/ecraft"
-- the house accent: the blue line along each window's top, icons, the one filled button per screen
ns.ACCENT = { 0.353, 0.663, 1 }

local function pick(ok, ...)
  if ok then return ... end
end

-- call f(...) and return its results, or nothing if f is missing or errors
local function try(f, ...)
  if type(f) == "function" then return pick(pcall(f, ...)) end
end
ns.try = try

-- v itself, or nil when the game handed us a secret value we may not read
local function plain(v)
  if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
  return v
end
ns.plain = plain

ns.DEFAULTS = {
  settings = {
    vendorPatterns = true,   -- recipes whose pattern a vendor sells (the site's main route has them too)
    ahPatterns = false,      -- recipes whose pattern is on the auction house right now (a drop you can buy today)
    noAlts = false,          -- don't count materials on your other characters
    buffer = true,           -- shop for the 90% safety buffer, not the expected number of crafts
    useAuctions = true,      -- prices from EverlookDB Auctions' scans
    useAuctionator = true,   -- else Auctionator's
    guideScale = 1,
    guideLocked = false,
    guideRows = 18,
    autoGuide = false,       -- open the guide with the profession window, when that profession has a route
    windowScale = 1,         -- the Crafting list and the recipe browser
    otherSide = false,       -- the recipe browser lists the other faction's recipes too
  },
  chars = {},
  list = {},                 -- the Crafting list: { { spell, n (crafts) } }
  craftBuy = {},             -- per material you can make: "craft" or "buy" (unset: craft, buy for vendor goods)
  favs = {},                 -- recipe browser favourites: spell -> true
  fixes = {},
  seen = {},
}

function ns.db() return EverlookCraftDB end
function ns.settings() return EverlookCraftDB and EverlookCraftDB.settings or ns.DEFAULTS.settings end

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        local c = {}
        fill(c, v)
        dst[k] = c
      else
        dst[k] = v
      end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      fill(dst[k], v)
    end
  end
  return dst
end
ns.fill = fill

function ns.initDB()
  EverlookCraftDB = fill(type(EverlookCraftDB) == "table" and EverlookCraftDB or {}, ns.DEFAULTS)
  EverlookCraftChar = type(EverlookCraftChar) == "table" and EverlookCraftChar or {}
  EverlookCraftChar.routes = EverlookCraftChar.routes or {}
  EverlookCraftChar.done = EverlookCraftChar.done or {}
end

---------------------------------------------------------------------------------------------------------------------
-- The character (names stay in this addon's own saved variables, on this PC)

function ns.guid() return plain(try(UnitGUID, "player")) end

function ns.side()
  local f = plain(try(UnitFactionGroup, "player"))
  return f == "Horde" and "h" or "a"
end

-- this character's record, made on first use
function ns.me()
  local db, id = EverlookCraftDB, ns.guid()
  if not db or not id then return nil end
  local c = db.chars[id]
  if not c then
    c = { profs = {}, bags = {}, bank = {} }
    db.chars[id] = c
  end
  c.name = plain(try(UnitName, "player")) or c.name
  c.realm = plain(try(GetRealmName)) or c.realm
  c.side = ns.side()
  local _, class = try(UnitClass, "player")
  c.class = plain(class) or c.class
  c.level = plain(try(UnitLevel, "player")) or c.level
  return c
end

---------------------------------------------------------------------------------------------------------------------
-- Money: "1g 20s 5c" in coin colours; nil prints "?"

function ns.money(c, plainText)
  if c == nil then return plainText and "?" or "|cff8d94a3?|r" end
  c = math.floor(c + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  local G, S, C = "|cffffd100", "|cffc7c7cf", "|cffeda55f"
  if plainText then G, S, C = "", "", "" end
  local R = plainText and "" or "|r"
  if g > 0 then out[#out + 1] = G .. g .. "g" .. R end
  if s > 0 or (g > 0 and cp > 0) then out[#out + 1] = S .. s .. "s" .. R end
  if g == 0 and (cp > 0 or s == 0) then out[#out + 1] = C .. cp .. "c" .. R end
  return table.concat(out, " ")
end

---------------------------------------------------------------------------------------------------------------------
-- The recipe data (Data.lua, written by everlookdb.com's tools/craft_addon_data.py) as tables

local recipesCache = {}

-- skill line -> { recipe, ... } with readable fields; nil when the data has no such profession
function ns.recipes(skill)
  if recipesCache[skill] then return recipesCache[skill] end
  local D = ns.DATA
  local p = D and D.profs[skill]
  if not p then return nil end
  local out, bySpell = {}, {}
  for _, row in ipairs(p.recipes) do
    local mats = {}
    local m = row[9]
    for i = 1, #m, 2 do mats[#mats + 1] = { m[i], m[i + 1] } end
    local flags = row[17] or ""
    local r = {
      spell = row[1], name = row[2], creates = row[3], yield = row[4], learn = row[5],
      yellow = row[6], green = row[7], gray = row[8], mats = mats, item = row[10], fee = row[11],
      tier = { a = row[12], h = row[14] }, why = { a = D.why[row[13] + 1], h = D.why[row[15] + 1] },
      skip = D.skips[row[16] + 1], learnKnown = flags:find("k") ~= nil, needsCd = flags:find("c") ~= nil,
      auto = flags:find("a") ~= nil, trained = flags:find("t") ~= nil, skill = skill, icon = row[18] ~= 0 and row[18] or nil,
      -- the tools it needs (keys of DATA.tools), and AllTheThings' learn skill where `learn` is the site's estimate
      tools = type(row[19]) == "table" and row[19] or nil, attLearn = (row[20] or 0) ~= 0 and row[20] or nil,
    }
    out[#out + 1] = r
    bySpell[r.spell] = r
  end
  for twin, spell in pairs(p.alias or {}) do bySpell[twin] = bySpell[spell] end
  out.bySpell = bySpell
  recipesCache[skill] = out
  return out
end

-- the recipe of a spell in any profession (twins of other factions included)
function ns.recipeBySpell(spell)
  local D = ns.DATA
  if not D then return nil end
  for skill in pairs(D.profs) do
    local rs = ns.recipes(skill)
    if rs and rs.bySpell[spell] then return rs.bySpell[spell] end
  end
end

-- the reagents a recipe really takes: what a profession window showed (the server can differ from the client data)
function ns.matsOf(r)
  local fix = EverlookCraftDB and EverlookCraftDB.fixes[r.spell]
  if fix and #fix > 0 then
    local mats = {}
    for i = 1, #fix, 2 do mats[#mats + 1] = { fix[i], fix[i + 1] } end
    return mats, true
  end
  return r.mats, false
end

function ns.itemInfo(id)
  local it = ns.DATA and ns.DATA.items[id]
  local name = it and it[1]
  if not name then
    local n = try(C_Item and C_Item.GetItemNameByID, id) or try(GetItemInfo, id)
    name = plain(n)
  end
  local icon = it and it[3] ~= 0 and it[3] or plain(try(C_Item and C_Item.GetItemIconByID, id)) or 134400
  return name or ("item " .. id), icon, it and it[2] or 1
end

-- an item's chat link, or nil while the game hasn't loaded it (C_Item first: the global may be gone in this client)
function ns.itemLink(id)
  local link = select(2, try(C_Item and C_Item.GetItemInfo, id))
  if not link then link = select(2, try(GetItemInfo, id)) end
  link = plain(link)
  if not link and C_Item and C_Item.RequestLoadItemDataByID then try(C_Item.RequestLoadItemDataByID, id) end
  return type(link) == "string" and link or nil
end

-- the icon of a recipe: what it makes, else the profession's
function ns.recipeIcon(r)
  if not r then return 134400 end
  if r.icon then return r.icon end
  if r.creates and r.creates ~= 0 then return (select(2, ns.itemInfo(r.creates))) end
  return ns.profIcon(r.skill)
end

-- each profession's icon (the game's spell icons)
ns.PROF_ICONS = { [171] = 136240, [164] = 136241, [333] = 136244, [202] = 136243, [165] = 133611, [197] = 136249,
  [186] = 136248, [185] = 133971, [129] = 135966, [40] = 136242 }
function ns.profIcon(skill) return ns.PROF_ICONS[skill] or 136249 end

-- the profession names the data knows, sorted
function ns.professionList()
  local out = {}
  for id, p in pairs(ns.DATA and ns.DATA.profs or {}) do out[#out + 1] = { id = id, name = p.name } end
  table.sort(out, function(x, y) return x.name < y.name end)
  return out
end

function ns.profName(skill)
  local p = ns.DATA and ns.DATA.profs[skill]
  return p and p.name or ("skill " .. tostring(skill))
end

function ns.skillByName(name)
  if not name then return nil end
  local low = name:lower()
  for id, p in pairs(ns.DATA and ns.DATA.profs or {}) do
    if p.name:lower() == low then return id end
  end
end

-- quality colour of an item (0 poor .. 5 legendary)
local QCOL = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
function ns.qualityColor(q) return QCOL[q or 1] or "ffffff" end

-- the game's recipe colours
ns.COLORS = { orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, gray = { 0.5, 0.5, 0.5 } }
function ns.colorAt(r, s)
  if s < r.yellow then return "orange" end
  if s < r.green then return "yellow" end
  if s < r.gray then return "green" end
  return "gray"
end

---------------------------------------------------------------------------------------------------------------------
-- Events: modules register what they need; ADDON_LOADED sets up the saved variables first.

local handlers = {}
local events = CreateFrame("Frame")
ns.events = events
function ns.on(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    try(events.RegisterEvent, events, event)
  end
  table.insert(handlers[event], fn)
end
events:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, event, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end)

ns.on("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  ns.initDB()
  if ns.onLoaded then for _, fn in ipairs(ns.onLoaded) do fn() end end
end)
ns.onLoaded = {}
function ns.whenLoaded(fn) table.insert(ns.onLoaded, fn) end
