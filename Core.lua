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

-- Realm names compared the way "Name-Realm" writes them: no spaces, hyphens or apostrophes, any case.
local function realmKey(s) return type(s) == "string" and (s:gsub("[%s%-']", ""):lower()) or nil end
ns.realmKey = realmKey

-- The realm you are on: key (its name, else "realm:6946"), name (nil while unknown), id. Realm.lua reads it (the game's
-- name, else the name saved for the realm ID in EverlookCraftDB.realmNames, else the ID from your GUID).
function ns.realm()
  local db = EverlookCraftDB
  if db and type(db.realmNames) ~= "table" then db.realmNames = {} end
  return ns.Realm.read(db and db.realmNames)
end
function ns.realmName() local _, name = ns.realm(); return name end

-- The realms whose characters can mail you: { names = { [realmKey] = true }, id = realm ID, named = your realm's name is
-- known }: yours and, on connected realms, the others in its group (the game's GetAutoCompleteRealms, when it has it).
-- nil while neither the game nor your GUID says which realm you are on.
local realmsFor, realmsSet
function ns.mailRealms()
  local _, name, id = ns.realm()
  if not name and not id then return nil end
  local tag = tostring(name) .. "#" .. tostring(id)
  if realmsFor == tag then return realmsSet end
  local set = { names = {}, id = id, named = name ~= nil }
  if name then set.names[realmKey(name)] = true end
  local list = try(GetAutoCompleteRealms)
  if type(list) == "table" then
    for _, r in ipairs(list) do
      local k = realmKey(plain(r))
      if k and k ~= "" then set.names[k] = true end
    end
  end
  realmsFor, realmsSet = tag, set
  return set
end

-- Can character record c send you things by mail (same or connected realm)? By realm name when both are known, else
-- by realm ID (from the character's GUID). A record that names no realm, or before anything names yours, counts: that
-- is how it was before realms were saved.
function ns.sameRealm(c, realms)
  realms = realms or ns.mailRealms()
  if not realms or not c then return true end
  local name = not ns.Realm.blank(c.realm) and c.realm or nil
  local id = type(c.realmID) == "number" and c.realmID > 0 and c.realmID or nil
  if realms.named and name then return realms.names[realmKey(name)] or false end
  if realms.id and id then return id == realms.id or (name ~= nil and realms.names[realmKey(name)]) or false end
  return true
end

-- Can this character mail you things? Same realm (or a connected one) and the same faction: mail doesn't cross
-- factions. A character saved before its faction was (no side), or a moment the game doesn't know yours yet, counts.
function ns.canMail(c, realms)
  if not ns.sameRealm(c, realms) then return false end
  local mine = ns.faction()
  if not mine or not c or not c.side then return true end
  return c.side == mine
end

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

-- your faction: "h", "a", or nil while the game doesn't know it yet
function ns.faction()
  local f = plain(try(UnitFactionGroup, "player"))
  return (f == "Horde" and "h") or (f == "Alliance" and "a") or nil
end

-- your side for recipe lists: Alliance when the game doesn't say
function ns.side() return ns.faction() or "a" end

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
  local _, realm, realmID = ns.realm()
  if realm then c.realm = realm elseif ns.Realm.blank(c.realm) then c.realm = nil end
  c.realmID = realmID or c.realmID
  c.side = ns.faction() or c.side   -- saved only when the game knows it (a guess would hide an alt's materials)
  local _, class = try(UnitClass, "player")
  c.class = plain(class) or c.class
  c.level = plain(try(UnitLevel, "player")) or c.level
  return c
end

---------------------------------------------------------------------------------------------------------------------
-- Data saved while the game didn't say the realm (v0.2.0 and older on client build 71037 saved every character with
-- realm "" and the trainer and merchant prices under the realm ""). At load and login, put right what is certain:
--   - each character's realm ID comes from its GUID (the key of EverlookCraftDB.chars); realm "" is dropped;
--   - a realm ID's name: the game's, else characters that saved both (when they agree), else, when every character
--     on this account is on one realm ID and everything saved names one realm, that one;
--   - prices saved under "" or "?" go to that realm when every character is on one realm ID (else they stay, and the
--     Trainers and merchants page says so); prices under "realm:6946" go to its name once known. Different realms are
--     never merged.

-- keep the newer of two saved records (t[at] is when it was seen)
local function keepNewer(dst, src, at)
  for k, v in pairs(src or {}) do
    local w = dst[k]
    if type(v) == "table" and (type(w) ~= "table" or (tonumber(v[at]) or 0) > (tonumber(w[at]) or 0)) then dst[k] = v end
  end
end

local function mergeCaptures(from, to)
  to.fees, to.prices, to.ranks = to.fees or {}, to.prices or {}, to.ranks or {}
  keepNewer(to.fees, from.fees, 4)
  keepNewer(to.prices, from.prices, 2)
  for skill, steps in pairs(from.ranks or {}) do
    if type(steps) == "table" then
      to.ranks[skill] = to.ranks[skill] or {}
      keepNewer(to.ranks[skill], steps, 4)
    end
  end
end

ns.realmUnfixed = 0  -- saved price sets whose realm can't be told (the Trainers and merchants page says so)

function ns.repairRealms()
  local db = EverlookCraftDB
  if type(db) ~= "table" or type(db.chars) ~= "table" then return end
  local R = ns.Realm
  if type(db.realmNames) ~= "table" then db.realmNames = {} end
  local names = db.realmNames
  ns.realm()   -- the game's name for this ID, when it says one
  local ids, nIDs, onlyID = {}, 0, nil
  for guid, c in pairs(db.chars) do
    if type(c) == "table" then
      if R.blank(c.realm) then c.realm = nil end
      if not (type(c.realmID) == "number" and c.realmID > 0) then c.realmID = R.idOf(guid) end
      if c.realmID and not ids[c.realmID] then ids[c.realmID], nIDs, onlyID = true, nIDs + 1, c.realmID end
    end
  end
  local here = R.id()
  if here and not ids[here] then nIDs, onlyID = nIDs + 1, here end
  -- a realm ID's name from characters that saved both
  local byID = {}
  for _, c in pairs(db.chars) do
    if type(c) == "table" and c.realm and c.realmID then
      local n = byID[c.realmID]
      if n == nil then byID[c.realmID] = c.realm elseif n ~= c.realm then byID[c.realmID] = false end
    end
  end
  for id, n in pairs(byID) do if n and not R.text(names[id]) then names[id] = n end end
  -- one realm ID on the whole account, and one realm name in everything saved: that is its name
  if nIDs == 1 and not R.text(names[onlyID]) then
    local named, nNames, only = {}, 0, nil
    local function see(n) if not R.blank(n) and not named[n] then named[n], nNames, only = true, nNames + 1, n end end
    for k in pairs(type(db.realms) == "table" and db.realms or {}) do see(k) end
    for _, c in pairs(db.chars) do if type(c) == "table" then see(c.realm) end end
    for id, n in pairs(names) do if id ~= onlyID then see(n) end end
    if nNames == 1 then names[onlyID] = only end
  end
  for _, c in pairs(db.chars) do
    if type(c) == "table" and not c.realm and c.realmID and R.text(names[c.realmID]) then c.realm = names[c.realmID] end
  end
  -- trainer and merchant prices saved without their realm's name
  ns.realmUnfixed = 0
  if type(db.realms) ~= "table" then return end
  local moves = {}
  for k, rec in pairs(db.realms) do
    if type(rec) == "table" then
      local id = R.keyID(k)
      local to
      if id then to = R.text(names[id])
      elseif R.blank(k) then
        if nIDs == 1 then to = R.text(names[onlyID]) or R.idKey(onlyID) end
        if not to then ns.realmUnfixed = ns.realmUnfixed + 1 end
      end
      if to and to ~= k then moves[#moves + 1] = { from = k, to = to } end
    end
  end
  for _, m in ipairs(moves) do
    local from = db.realms[m.from]
    db.realms[m.from] = nil
    if type(db.realms[m.to]) == "table" then mergeCaptures(from, db.realms[m.to]) else db.realms[m.to] = from end
  end
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
  ns.repairRealms()
  if ns.onLoaded then for _, fn in ipairs(ns.onLoaded) do fn() end end
end)
-- the realm is surely known (by GUID at least) once the character is in the world
ns.on("PLAYER_LOGIN", function() ns.repairRealms() end)
ns.onLoaded = {}
function ns.whenLoaded(fn) table.insert(ns.onLoaded, fn) end
