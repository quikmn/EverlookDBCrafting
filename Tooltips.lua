-- Item tooltips, through the shared EverlookTooltip layout (Libs\EverlookUI\EverlookTooltip.lua: one block under the
-- game's lines, the same order and look as every EverlookDB addon's lines, no line twice):
--   * a material: "Used in  4 of your recipes" and, when one of this character's skill-up routes still needs it,
--     "Skill-up route  15 more" (needed and what you have as finer print);
--   * something crafted: "You can make this  Tailoring 112" (in the recipe's colour at your skill), your alts who can
--     and, with guild sharing on, guild members who can;
--   * a recipe (pattern, plans, formula): which of your characters on this realm already know it, can learn it now,
--     or can learn it later (skill too low), and guild members who know it.
-- Finer print goes through t:Detail, so the shared "Tooltip details" setting (always, or only while Shift is held)
-- applies. Every part has its own setting. Names come from this addon's own saved variables (your characters) and
-- from memory (guild); nothing is sent anywhere.
local _, ns = ...

local Tip = LibStub and LibStub("EverlookTooltip-1", true)

local TT = {}
ns.tooltips = TT

local D = ns.DEFAULTS.settings
D.tipReagent = true    -- "Used in N of your recipes" and the route's need on materials
D.tipCrafted = true    -- "You / your alts can make this" on crafted items
D.tipRecipe = true     -- "Known by / learnable by" on recipe items
D.tipGuild = true      -- guild members in those lines (needs guild sharing)
D.tipDetail = "always" -- finer print always, or only with Shift (shared with the other EverlookDB addons)

local MAX_NAMES = 4

---------------------------------------------------------------------------------------------------------------------
-- Indexes over the recipe data: what an item is used in, what makes it, what a recipe item teaches

local index
function TT.index()
  if index then return index end
  local usedIn, makes, teaches = {}, {}, {}
  local function add(t, k, r)
    local l = t[k]
    if not l then l = {}; t[k] = l end
    for _, x in ipairs(l) do if x == r then return end end
    l[#l + 1] = r
  end
  for skill in pairs(ns.DATA and ns.DATA.profs or {}) do
    for _, r in ipairs(ns.recipes(skill) or {}) do
      for _, m in ipairs(r.mats or {}) do add(usedIn, m[1], r) end
      if r.creates and r.creates ~= 0 then add(makes, r.creates, r) end
      if r.item and r.item ~= 0 then add(teaches, r.item, r) end
    end
  end
  -- reagents the server uses instead of the client data's (a profession window showed them)
  for spell, fix in pairs(EverlookCraftDB and EverlookCraftDB.fixes or {}) do
    local r = ns.recipeBySpell(spell)
    if r then for i = 1, #fix, 2 do add(usedIn, fix[i], r) end end
  end
  index = { usedIn = usedIn, makes = makes, teaches = teaches }
  return index
end
function TT.resetIndex() index = nil end

---------------------------------------------------------------------------------------------------------------------
-- Pure parts (tested): what each line says


-- Does recipe r use item id (with the server's reagents where a window showed them)?
local function uses(r, id)
  for _, m in ipairs((ns.matsOf(r))) do if m[1] == id then return true end end
  return false
end

-- your characters (this realm or a connected one and your faction, when known), the current one first: { { guid, c, me } }
function TT.characters(sameRealm)
  local out, me, realms = {}, ns.guid(), ns.mailRealms()
  for g, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do
    if not sameRealm or ns.canMail(c, realms) then
      out[#out + 1] = { guid = g, c = c, me = g == me }
    end
  end
  table.sort(out, function(x, y)
    if x.me ~= y.me then return x.me end
    return (x.c.name or "") < (y.c.name or "")
  end)
  return out
end

local function knows(c, r)
  local p = c.profs and c.profs[r.skill]
  return p and p.known and p.known[r.spell] and true or false
end

-- "You" or the character's name, in their class colour (when the shared tooltip layout is there)
local function nameOf(e)
  local n = e.me and "You" or (e.c.name or "?")
  return Tip and Tip.ClassName and Tip.ClassName(n, e.c.class) or n
end

-- "Anna, Bob, Cid +2" (never "+1": that name is shown instead)
function TT.names(list, max)
  if Tip and Tip.Names then return Tip.Names(list, max or MAX_NAMES) end
  max = max or MAX_NAMES
  if #list == max + 1 then max = #list end
  local shown = {}
  for i = 1, math.min(#list, max) do shown[i] = list[i] end
  local s = table.concat(shown, ", ")
  if #list > max then s = s .. " +" .. (#list - max) end
  return s
end

-- A material: { recipes = { r, ... } known by any of your characters that use it, total = recipes in the data }
function TT.reagentInfo(id)
  local list = TT.index().usedIn[id]
  if not list then return nil end
  local mine, seen = {}, {}
  local chars = TT.characters(false)
  for _, r in ipairs(list) do
    if uses(r, id) and not seen[r] then
      for _, e in ipairs(chars) do
        if knows(e.c, r) then mine[#mine + 1] = r; seen[r] = true; break end
      end
    end
  end
  table.sort(mine, function(a, b) return a.name < b.name end)
  return { recipes = mine, total = #list }
end

-- What this character's skill-up routes still need of an item: { need, have, short, skills = { name, ... } } or nil.
function TT.routeNeed(id)
  local routes = EverlookCraftChar and EverlookCraftChar.routes
  if not routes or not ns.plans then return nil end
  local need, skills = 0, {}
  for skill, rt in pairs(routes) do
    local rank = ns.plans.skillNow(skill)
    if not (rank and rank >= rt.to) then
      local ok, rem = pcall(ns.plans.remaining, rt, rank)
      local n = ok and rem and rem[id]
      if n and n > 0 then
        need = need + n
        skills[#skills + 1] = ns.profName(skill)
      end
    end
  end
  if need == 0 then return nil end
  table.sort(skills)
  local have = ns.stock.usable(id)
  return { need = need, have = have, short = math.max(0, need - have), skills = skills }
end

-- Something crafted: { me = { r, rank } or nil, alts = { { name, skill name, rank } }, guild = { names } }
function TT.craftedInfo(id)
  local list = TT.index().makes[id]
  if not list then return nil end
  local res = { alts = {}, guild = {} }
  local altSeen, guildSeen = {}, {}
  for _, e in ipairs(TT.characters(true)) do
    for _, r in ipairs(list) do
      if knows(e.c, r) then
        local rank = e.c.profs[r.skill].rank
        if e.me then
          if not res.me then res.me = { r = r, rank = rank } end
        elseif not altSeen[e.guid] then
          altSeen[e.guid] = true
          res.alts[#res.alts + 1] = { name = e.c.name or "?", class = e.c.class, prof = ns.profName(r.skill), rank = rank }
        end
      end
    end
  end
  if ns.guild then
    for _, r in ipairs(list) do
      for _, n in ipairs(ns.guild.knows(r.spell)) do
        if not guildSeen[n] then guildSeen[n] = true; res.guild[#res.guild + 1] = n end
      end
    end
    table.sort(res.guild)
  end
  if not res.me and #res.alts == 0 and #res.guild == 0 then return nil end
  return res
end

-- A recipe item: { r, known = { names }, now = { names }, later = { { name, rank } }, guild = { names } }
function TT.recipeInfo(id)
  local list = TT.index().teaches[id]
  local r = list and list[1]
  if not r then return nil end
  local res = { r = r, known = {}, now = {}, later = {}, guild = {} }
  for _, e in ipairs(TT.characters(true)) do
    local p = e.c.profs and e.c.profs[r.skill]
    if p then
      if knows(e.c, r) then
        res.known[#res.known + 1] = nameOf(e)
      elseif (p.rank or 0) >= r.learn then
        res.now[#res.now + 1] = nameOf(e)
      else
        res.later[#res.later + 1] = { name = nameOf(e), rank = p.rank }
      end
    end
  end
  if ns.guild then res.guild = ns.guild.knows(r.spell) end
  return res
end

---------------------------------------------------------------------------------------------------------------------
-- The lines

local function on(key) return ns.settings()[key] ~= false end
local function guildOn() return on("tipGuild") and ns.guild and ns.guild.enabled() end

-- the recipe's colour at a skill, or nil when it is grey (no more skill-ups): grey text is hard to read on a tooltip
local function skillColor(r, rank)
  local key = rank and ns.colorAt(r, rank) or "gray"
  if key == "gray" or key == "grey" then return nil end
  return ns.COLORS[key]
end
local function colorCode(r, rank)
  local c = skillColor(r, rank)
  if not c then return "" end
  return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end
local function classed(name, class) return Tip and Tip.ClassName and Tip.ClassName(name, class) or name end

function TT.reagentLines(t, id)
  if not on("tipReagent") then return end
  local info = TT.reagentInfo(id)
  if info and #info.recipes > 0 then
    local profs, seen = {}, {}
    for _, r in ipairs(info.recipes) do
      local p = ns.profName(r.skill)
      if not seen[p] then seen[p] = true; profs[#profs + 1] = p end
    end
    table.sort(profs)
    local n = #info.recipes
    t:Line("Used in", n == 1 and "1 of your recipes" or (n .. " of your recipes"), { note = table.concat(profs, ", ") })
    -- the recipes, each in its colour at this character's skill (orange, yellow, green, grey); the profession on the
    -- right only when they are from more than one
    local me = ns.me and ns.me()
    local items = {}
    for i, r in ipairs(info.recipes) do
      local p = me and me.profs and me.profs[r.skill]
      local known = p and p.known and p.known[r.spell]
      items[i] = { r.name, #profs > 1 and ns.profName(r.skill) or nil, color = known and skillColor(r, p.rank) or nil }
    end
    if t.List then
      t:List(items, { max = MAX_NAMES, more = "more" })
    else
      for i = 1, math.min(n, MAX_NAMES) do t:Detail(items[i][1], items[i][2]) end
      if n > MAX_NAMES then t:Detail("and " .. (n - MAX_NAMES) .. " more") end
    end
  end
  local need = TT.routeNeed(id)
  if need then
    if need.short > 0 then
      t:Line("Skill-up route", need.short .. " more", { note = table.concat(need.skills, ", ") })
    else
      t:Line("Skill-up route", "you have enough", { note = table.concat(need.skills, ", "), stale = true })
    end
    t:Detail("Needed / you have", need.need .. " / " .. need.have)
  end
  local list = TT.listNeed(id)
  if list and list.short > 0 then
    t:Line("Crafting list", list.short .. " more")
  end
end

-- What the Crafting list (CraftList.lua, when it is there) still misses of an item: { need, have, short } or nil. The
-- tree is worked out at most once a second, since a tooltip can be drawn many times in a row.
local listCache, listAt
function TT.listNeed(id)
  local L = ns.craftList
  if not (L and L.tree and L.entries) then return nil end
  local okE, entries = pcall(L.entries)
  if not okE or not entries or #entries == 0 then return nil end
  local now = ns.plain(ns.try(GetTime)) or 0
  if not listCache or not listAt or now - listAt >= 1 then
    local ok, tree = pcall(L.tree)
    listCache, listAt = ok and tree or nil, now
  end
  return listCache and listCache.totals and listCache.totals[id] or nil
end

function TT.craftedLines(t, id)
  if not on("tipCrafted") then return end
  local info = TT.craftedInfo(id)
  if not info then return end
  if info.me then
    local code = colorCode(info.me.r, info.me.rank)
    t:Line("You can make this", code .. ns.profName(info.me.r.skill) .. " " .. (info.me.rank or "?") .. (code ~= "" and "|r" or ""))
  end
  if #info.alts > 0 then
    local names = {}
    for _, a in ipairs(info.alts) do names[#names + 1] = classed(a.name, a.class) end
    t:Line(#info.alts == 1 and "Your alt can make this" or "Your alts can make this", TT.names(names))
    for i = 1, math.min(#info.alts, MAX_NAMES) do
      local a = info.alts[i]
      t:Detail(classed(a.name, a.class), a.prof .. " " .. (a.rank or "?"))
    end
  end
  if guildOn() and #info.guild > 0 then
    t:Line("Guild can make this", TT.names(info.guild))
  end
end

function TT.recipeLines(t, id)
  if not on("tipRecipe") then return end
  local info = TT.recipeInfo(id)
  if not info then return end
  local r = info.r
  if #info.known > 0 then t:Line("Known by", TT.names(info.known)) end
  if #info.now > 0 then t:Line("Learnable by", TT.names(info.now)) end
  if #info.later > 0 then
    local names = {}
    for _, x in ipairs(info.later) do names[#names + 1] = x.name end
    t:Line("Learnable later by", TT.names(names), { note = "needs " .. r.learn, stale = true })
    for i = 1, math.min(#info.later, MAX_NAMES) do
      local x = info.later[i]
      t:Detail(x.name, ns.profName(r.skill) .. " " .. (x.rank or "?") .. " of " .. r.learn)
    end
  end
  if guildOn() and #info.guild > 0 then
    t:Line("Known in your guild", TT.names(info.guild))
  end
end

-- one contribution: a recipe item gets the recipe lines only (it is not also "crafted" or a material)
function TT.lines(t, id)
  if not id or not ns.DATA then return end
  if ns.favor and ns.favor.crate(id) then return ns.favor.tipLines(t, id) end
  local idx = TT.index()
  if idx.teaches[id] then return TT.recipeLines(t, id) end
  TT.craftedLines(t, id)
  TT.reagentLines(t, id)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings and registration

function TT.detail(mode)
  local s = ns.settings()
  if mode ~= nil then s.tipDetail = mode == "shift" and "shift" or "always" end
  if Tip then Tip:SetDetail(s.tipDetail) end
  return s.tipDetail
end

local function auctionsLoaded()
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  return f and ns.try(f, "EverlookDBAuctions") and true or false
end

ns.whenLoaded(function()
  if not Tip then return end
  -- EverlookDB Auctions keeps this setting too; when it is installed, its choice is the one already applied
  if not auctionsLoaded() then TT.detail() end
  if Tip.LoadSolid then Tip:LoadSolid(ns.settings()) end
  Tip:Register({ id = "EverlookDBCrafting.crafting", kind = "item", order = Tip.ORDER.crafting or (Tip.ORDER.source + 5),
    add = function(t, ctx) if ctx.id then TT.lines(t, ctx.id) end end })
end)

-- a new profession scan can change which recipes use what (server reagents)
local prevScanned = ns.onScanned
ns.onScanned = function(skill)
  if prevScanned then prevScanned(skill) end
  TT.resetIndex()
end

local app = ns.app
local function bool(key, field, label, desc, keywords)
  app:Setting({ key = key, type = "bool", label = label, desc = desc, keywords = keywords,
    get = function() return ns.settings()[field] ~= false end,
    set = function(v) ns.settings()[field] = v and true or false end, default = true })
end
bool("tip.reagent", "tipReagent", "Materials: your recipes and your route",
  "On a material: how many of your characters' recipes use it, and how many more this character's skill-up routes need.",
  { "tooltip", "reagent", "material", "used in", "route", "needed" })
bool("tip.crafted", "tipCrafted", "Crafted items: who of you can make it",
  "On something crafted: whether you or your alts on this realm know the recipe, with the skill.",
  { "tooltip", "crafted", "make", "alts", "twinks" })
bool("tip.recipe", "tipRecipe", "Recipes: known by and learnable by",
  "On a recipe, pattern, plans or formula: which of your characters on this realm know it, can learn it now, or later.",
  { "tooltip", "recipe", "pattern", "plans", "formula", "learn", "known", "alts", "twinks" })
bool("tip.favor", "tipFavor", "Waylaid Crates: Merchant's Favor and gold per Favor",
  "On a Waylaid Crate: the Favor it gives and what one Favor costs with its cheapest bundle.",
  { "tooltip", "crate", "waylaid", "favor", "merchant's favor" })
bool("tip.guild", "tipGuild", "Guild members in these lines",
  "Guild members who know the recipe (needs guild sharing, see Guild).", { "tooltip", "guild", "crafter" })
if Tip and Tip.SolidSetting then Tip:SolidSetting(app, function() return ns.settings() end) end
app:Setting({
  key = "tipdetail", type = "choice", label = "Tooltip details", width = 200,
  keywords = { "tooltip", "shift", "detail", "finer" },
  desc = "The finer print (which recipes, each alt's skill): always, or only while you hold Shift.",
  choices = { { value = "always", text = "Always" }, { value = "shift", text = "While Shift is held" } },
  get = function() return Tip and Tip:GetDetail() or ns.settings().tipDetail end,
  set = function(v) TT.detail(v) end,
})

app:Section("tooltips", "Tooltips", function(stack)
  local UI = LibStub("EverlookUI-1")
  UI.Header(stack, "Item tooltips", "Lines this addon adds under the game's, in the same block as the other EverlookDB addons.")
  app:Widget(stack, "tip.reagent")
  app:Widget(stack, "tip.crafted")
  app:Widget(stack, "tip.recipe")
  app:Widget(stack, "tip.favor")
  app:Widget(stack, "tip.guild")
  app:Widget(stack, "tipdetail")
  if app:GetSetting("tipsolid") then app:Widget(stack, "tipsolid") end
  UI.Note(stack, "Tooltip details and the solid background are shared by every EverlookDB addon's tooltip lines. Your characters' names come from this addon's own saved variables on this PC; guild members' names are only kept in memory until you log out.")
end, { icon = "tooltip", desc = "What this addon adds to item tooltips: materials, crafted items, recipes and Waylaid Crates." })
