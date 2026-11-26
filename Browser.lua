-- The recipe browser's facts (no frames here): every recipe of a profession, learned or not, searched by its name or a
-- reagent's; how to learn each one (the words of everlookdb.com's professions guide, "source unknown" said plainly);
-- where each reagent comes from; and which of your characters know it. Where the data has nothing, it says so.
local _, ns = ...

local B = {}
ns.browser = B

local function db() return EverlookCraftDB end

---------------------------------------------------------------------------------------------------------------------
-- The list

local function lower(s) return (tostring(s or "")):lower() end

-- the names a recipe is found by: its own and what it makes, and each reagent's
local wordsCache = {}
local function wordsOf(r)
  local w = wordsCache[r]
  if w then return w end
  local names = { lower(r.name) }
  if r.creates and r.creates ~= 0 then names[#names + 1] = lower((ns.itemInfo(r.creates))) end
  local reag = {}
  for _, m in ipairs((ns.matsOf(r))) do reag[#reag + 1] = lower((ns.itemInfo(m[1]))) end
  w = { names = names, reagents = reag }
  wordsCache[r] = w
  return w
end

-- Does the recipe match the query (as typed: "silk cloth" finds Silk Cloth, not every silky thing made of cloth)? It
-- matches by the recipe's name or what it makes, else by one reagent's name; the second result says it was a reagent.
function B.matches(r, query)
  local q = lower(query):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if q == "" then return true, false end
  local w = wordsOf(r)
  for _, n in ipairs(w.names) do if n:find(q, 1, true) then return true, false end end
  for _, n in ipairs(w.reagents) do if n:find(q, 1, true) then return true, true end end
  return false
end

function B.isFav(spell) return db() and db().favs and db().favs[spell] or false end
function B.toggleFav(spell)
  local d = db()
  if not d then return end
  d.favs = d.favs or {}
  d.favs[spell] = not d.favs[spell] or nil
end

-- this character knows it
function B.knownByMe(r)
  local p = ns.scan.mine(r.skill)
  return p and p.known and p.known[r.spell] or false
end

-- your other characters who know it: { name, ... }
function B.altsKnowing(r)
  local me = ns.me()
  local myName = me and me.name
  local out = {}
  for _, name in ipairs(ns.scan.knownBy(r.spell)) do
    if name ~= myName or not B.knownByMe(r) then out[#out + 1] = name end
  end
  return out
end

-- The recipes of a profession for the list, by learn skill then name. filter: "all", "known", "unknown", "favs".
-- Recipes only the other faction can learn are left out unless `otherSide`.
function B.list(skill, query, filter, otherSide)
  local out = {}
  local side = ns.side()
  for _, r in ipairs(ns.recipes(skill) or {}) do
    local ok, byReagent = B.matches(r, query)
    if ok and (otherSide or r.why[side] ~= "otherSide") then
      local known = B.knownByMe(r)
      local keep = filter == "known" and known or filter == "unknown" and not known
        or filter == "favs" and B.isFav(r.spell) or (filter == nil or filter == "all")
      if keep then out[#out + 1] = { r = r, known = known, byReagent = byReagent } end
    end
  end
  table.sort(out, function(x, y)
    if x.r.learn ~= y.r.learn then return x.r.learn < y.r.learn end
    return x.r.name < y.r.name
  end)
  return out
end

-- how many you can make with what is in your bags now (the game's own count does the same)
function B.canMake(r)
  local me = ns.me()
  local bags = me and me.bags or {}
  local n
  for _, m in ipairs((ns.matsOf(r))) do
    local k = math.floor((bags[m[1]] or 0) / m[2])
    n = n and math.min(n, k) or k
  end
  return n or 0
end

---------------------------------------------------------------------------------------------------------------------
-- How to learn it. Lines: { text, npcs = { ids } (Map: the nearest for your side), warn = true (a gap in the data) }

B.WHY = {
  limited = "limited vendor stock", dungeon = "taught in a dungeon", drop = "a drop", world = "a rare world drop",
  quest = "a quest reward", rep = "needs reputation", cur = "paid in a currency, not gold (such as Merchant's Favor)",
  object = "found in the world", fish = "fished up", container = "inside a container", chest = "in chests",
  otherSide = "the other faction only", unknown = "source unknown",
}

-- the rank whose trainers teach a recipe learned at `learn` (its trainers, or nil)
local function trainersFor(skill, learn)
  local ranks = ns.DATA.ranks[skill]
  if not ranks then return nil end
  local best
  for step, rk in pairs(ranks) do
    if rk[2] <= learn and #rk[5] > 0 and (not best or step > best) then best = step end
  end
  return best and ranks[best][5] or (ranks[1] and #ranks[1][5] > 0 and ranks[1][5]) or nil
end

local function usableIds(ids, side)
  local out = {}
  for _, id in ipairs(ids or {}) do
    local n = ns.DATA.npcs[id]
    if n and ns.map.usable(n[2], side) then out[#out + 1] = id end
  end
  return out
end

-- a dropper's or vendor's name with its dungeon, if it stands in one
local function npcLabel(id)
  local n = ns.DATA.npcs[id]
  if not n then return "npc " .. id end
  local dungeon = n[7] and n[7] ~= 0 and ns.DATA.dungeons and ns.DATA.dungeons[n[7]]
  if dungeon then return ("%s (%s)"):format(n[1], dungeon) end
  if n[6] == 1 then return ("%s (in a dungeon)"):format(n[1]) end
  local z = n[3] and n[3] ~= 0 and ns.DATA.zones[n[3]]
  return z and ("%s, %s"):format(n[1], z[1]) or n[1]
end

-- an NPC you can be led to on the map (outside dungeons, a known spot)
local function hasSpot(id)
  local n = ns.DATA.npcs[id]
  return n and n[3] and n[3] ~= 0 and n[6] ~= 1
end

-- what a vendor asks: gold, a currency (Merchant's Favor) or items; "?" amounts said plainly
local function costText(cur, amount)
  if cur == 0 then return amount and amount > 0 and ns.money(amount) or "a price not in the data" end
  if cur > 0 then
    local name = ns.DATA.currencies and ns.DATA.currencies[cur] or "a currency"
    return amount and amount > 0 and ("%d %s"):format(amount, name) or (name .. " (amount not in the data)")
  end
  local item = ns.itemInfo(-cur)
  return amount and amount > 0 and ("%d x %s"):format(amount, item) or item
end

-- the learn skill as text: "~30", or "~30 or 85" where a second source gives another figure (never names the source)
function B.learnText(r)
  if r.learnKnown then return tostring(r.learn) end
  if r.attLearn and r.attLearn ~= r.learn then return ("~%d or %d"):format(r.learn, r.attLearn) end
  return "~" .. r.learn
end

-- the tools a recipe needs, by name ("Blacksmith Hammer"), or nil
function B.toolsText(r)
  local names = {}
  for _, key in ipairs(r.tools or {}) do
    local t = ns.DATA.tools and ns.DATA.tools[key]
    if t then names[#names + 1] = t[1] end
  end
  return #names > 0 and table.concat(names, ", ") or nil
end

-- Is any way to learn the recipe in the data? (trainer, automatic, gold vendors, Favor or reputation vendors, drops,
-- quests, or a reason word). Only when none is there is it "source unknown".
function B.hasSource(r, side)
  side = side or ns.side()
  if r.auto or r.trained then return true end
  local ri = r.item and r.item ~= 0 and ns.DATA.recipeItems[r.item]
  if ri and (#ri[2] > 0 or (ri.sold and #ri.sold > 0) or (ri.drop and #ri.drop > 0) or (ri.q and #ri.q > 0)) then return true end
  local why = r.why[side]
  return why ~= nil and why ~= "" and why ~= "unknown"
end

function B.learnLines(r, side)
  side = side or ns.side()
  local lines = {}
  local est = r.learnKnown and "" or "~"
  local function add(text, extra)
    local l = { text = text }
    for k, v in pairs(extra or {}) do l[k] = v end
    lines[#lines + 1] = l
  end
  if r.auto then
    add("Learned automatically with the profession", { icon = "check" })
    return lines
  end
  local D = ns.DATA
  local sources = 0
  if r.trained then
    local fee = r.fee and r.fee > 0 and ns.money(r.fee) or (r.fee == 0 and "free" or "fee not in the data")
    add(("Trainer: %s, from skill %s"):format(fee, B.learnText(r)), { npcs = trainersFor(r.skill, r.learn), icon = "user" })
    sources = sources + 1
  end
  local ri = r.item and r.item ~= 0 and D.recipeItems[r.item]
  if r.item and r.item ~= 0 then
    local name, _, q = ns.itemInfo(r.item)
    add(("Recipe item: |cff%s%s|r, learn at %s"):format(ns.qualityColor(q), name, B.learnText(r)), { icon = "scroll" })
    if ri then
      -- gold vendors
      local vendors, limited = {}, false
      for i = 1, #ri[2], 2 do
        vendors[#vendors + 1] = ri[2][i]
        if ri[2][i + 1] == 1 then limited = true end
      end
      local mine = usableIds(vendors, side)
      if #mine > 0 then
        add(("Sold by %d vendor%s for your side, %s%s"):format(#mine, #mine == 1 and "" or "s",
          ri[1] and ri[1] > 0 and ns.money(ri[1]) or "price not in the data", limited and " (limited stock)" or ""), { npcs = mine, icon = "coins" })
        sources = sources + 1
      elseif #vendors > 0 then
        add("Sold only by the other faction's vendors", { icon = "coins", warn = true })
      end
      -- vendors asking a currency (Merchant's Favor), items or reputation
      local sold = ri.sold or {}
      local shown = 0
      for i = 1, #sold, 6 do
        local npc, cur, amount, fac, standing = sold[i], sold[i + 1], sold[i + 2], sold[i + 3], sold[i + 4]
        local n = D.npcs[npc]
        if shown < 3 then
          shown = shown + 1
          local gate = fac and fac ~= 0 and ("; needs %s %s"):format(D.factions and D.factions[fac] or "a faction",
            D.standings and D.standings[standing] or "") or ""
          local ok = not n or ns.map.usable(n[2], side)
          local whose = (n and (n[2] == "a" or n[2] == "h") and not ok) and " (the other faction's vendor)" or ""
          add(("Sold by %s for %s%s%s"):format(npcLabel(npc), costText(cur or 0, amount), gate, whose),
            { npcs = ok and hasSpot(npc) and { npc } or nil, icon = "coins", warn = whose ~= "" or nil })
          sources = sources + 1
        end
      end
      -- drops: the top droppers, with how many drop it in all
      local drop = ri.drop or {}
      local nDrop = 0
      for i = 1, #drop, 3 do
        if nDrop >= 3 then break end
        local npc, chance, src = drop[i], drop[i + 1], drop[i + 2]
        nDrop = nDrop + 1
        local how = chance and chance > 0 and (", %s%%"):format(chance >= 1 and ("%.0f"):format(chance) or ("%.2f"):format(chance))
          or ", chance unknown"
        add(("Drops from %s%s"):format(npcLabel(npc), how),
          { pin = hasSpot(npc) and npc or nil, icon = "sword" })
        sources = sources + 1
      end
      local more = (ri.dn or 0) - nDrop
      if more > 0 then add(("... and %d more creatures (everlookdb.com lists them all)"):format(more), { icon = "sword" }) end
      -- quests
      for _, qid in ipairs(ri.q or {}) do
        local qq = D.quests and D.quests[qid]
        if not qq or qq[2] == nil or qq[2] == side or qq[2] == "n" or qq[2] == "?" then
          add(("Quest reward: %s"):format(qq and qq[1] or ("quest " .. qid)), { icon = "scroll" })
          sources = sources + 1
        end
      end
      if ri.rep then
        add(("Its vendors need %s: %s"):format(ri.rep[1], D.standings and D.standings[ri.rep[2]] or "?"), { icon = "flag" })
      end
    end
  end
  local why = r.why[side]
  if why == "otherSide" then
    add("Only the other faction can learn it.", { warn = true, icon = "flag" })
  elseif sources == 0 and why and why ~= "" and why ~= "unknown" and why ~= "limited" then
    add(("How: %s"):format(B.WHY[why] or why), { icon = "info" })
    sources = sources + 1
  end
  if sources == 0 and why ~= "otherSide" then
    add("Source unknown: no trainer, vendor, drop or quest for this recipe is in our data yet.", { warn = true, icon = "info" })
  end
  return lines
end

-- one short line for the list: how it is learned
function B.learnShort(r, side)
  side = side or ns.side()
  if r.auto then return "automatic" end
  if r.trained then return "trainer" end
  local why = r.why[side]
  if why == "otherSide" then return "other faction" end
  local ri = r.item and r.item ~= 0 and ns.DATA.recipeItems[r.item]
  if ri then
    if #usableIds((function() local v = {} for i = 1, #ri[2], 2 do v[#v + 1] = ri[2][i] end return v end)(), side) > 0 then
      return why == "limited" and "vendor, limited stock" or "vendor"
    end
    local sold = ri.sold or {}
    for i = 1, #sold, 6 do
      local n = ns.DATA.npcs[sold[i]]
      if n and ns.map.usable(n[2], side) then
        local cur = sold[i + 1] or 0
        if cur > 0 then return (ns.DATA.currencies and ns.DATA.currencies[cur] or "currency") .. " vendor" end
        return (sold[i + 3] or 0) ~= 0 and "reputation vendor" or "vendor"
      end
    end
    if #sold > 0 then return "the other faction's vendor" end
    if ri.drop and #ri.drop > 0 then
      local n = ns.DATA.npcs[ri.drop[1]]
      return (n and n[6] == 1) and "dungeon drop" or "drop"
    end
    if ri.q and #ri.q > 0 then return "quest" end
  end
  if why and why ~= "" and why ~= "unknown" and why ~= "limited" then return ((B.WHY[why] or why):gsub(" %(.*%)", "")) end
  return "|cffef5d5dsource unknown|r"
end

---------------------------------------------------------------------------------------------------------------------
-- Where a reagent comes from. Lines: { text, npcs, icon, warn }

local KIND = {
  gather = "Gathered in the world: herbs, ore, skins, meat or cloth from humanoids",
  drop = "Drops from monsters (which ones: not in this addon's data yet)",
  rare = "A rare material: drops or special sources (not in this addon's data yet)",
  elemental = "From elementals and some gathering nodes (not in this addon's data yet)",
  enchant = "Disenchanting items (or bought)",
  cooldown = "Made with a cooldown craft (once every few days)",
}

-- a gathered material by its name: cloth is looted, ore and stone mined, leather and hides skinned
function B.gatherText(name)
  local n = lower(name)
  if n:find("cloth", 1, true) then return "Looted from humanoids (cloth)" end
  if n:find(" ore", 1, true) or n:find("^%a+ ore$") or n:find("stone", 1, true) then return "Mining" end
  if n:find("leather", 1, true) or n:find("hide", 1, true) or n:find("scale", 1, true) then return "Skinning" end
  return KIND.gather
end

function B.reagentLines(id, side)
  side = side or ns.side()
  local lines = {}
  local it = ns.DATA.items[id]
  for i, m in ipairs(ns.craftList.makers(id)) do
    if i > 2 then break end
    local who = #m.by > 0 and ("known by " .. table.concat(m.by, ", ")) or "none of your characters knows it"
    lines[#lines + 1] = { text = ("Crafted: %s (%s), %s"):format(m.r.name, ns.profName(m.r.skill), who), icon = "hammer", spell = m.r.spell }
  end
  if it and it[4] then
    local mine = usableIds(it[7], side)
    lines[#lines + 1] = { text = ("Vendors: %s each, %d sell it for your side"):format(ns.money(it[4]), #mine), icon = "coins",
      npcs = #mine > 0 and mine or nil }
  end
  local kind = it and it[6]
  if kind and KIND[kind] and not (kind == "made" or kind == "vendor") then
    lines[#lines + 1] = { text = kind == "gather" and B.gatherText(it[1]) or KIND[kind], icon = kind == "gather" and "map" or "sword",
      warn = kind ~= "gather" and kind ~= "enchant" }
  end
  local p, src = ns.prices.ah(id)
  lines[#lines + 1] = { text = p and ("Auction house: %s (%s)"):format(ns.money(p), src) or "Auction house: no price yet", icon = "coins" }
  if #lines == 1 and not p then
    lines[#lines + 1] = { text = "Where it comes from isn't in our data yet.", warn = true, icon = "info" }
  end
  return lines
end

---------------------------------------------------------------------------------------------------------------------
-- Acting on a recipe

-- select the recipe in your profession window (the game opens it when it can); crafting stays with the game's Create
function B.showRecipe(r)
  if not r then return end
  local TS = C_TradeSkillUI
  local ok = false
  if TS and TS.OpenRecipe then ok = pcall(TS.OpenRecipe, r.spell) end
  if not ok and TS and TS.SetRecipeItemNameFilter and ProfessionsFrame and ProfessionsFrame:IsShown() then
    ok = pcall(TS.SetRecipeItemNameFilter, r.name)
  end
  if not ok then ns.print(("open your %s window to craft %s."):format(ns.profName(r.skill), r.name)) end
end

-- put a link to the recipe (what it makes, else the spell) in the chat box
function B.link(r)
  if not r then return end
  local link
  if r.creates and r.creates ~= 0 then link = ns.itemLink(r.creates) end
  if not link then
    link = ns.try(C_Spell and C_Spell.GetSpellLink, r.spell) or ns.try(GetSpellLink, r.spell)
  end
  link = ns.plain(link)
  if link and ChatEdit_InsertLink then pcall(ChatEdit_InsertLink, link) end
end

-- a recipe by its name (any profession): exact first, then the start of a name, then anywhere in it
function B.findByName(text)
  local q = lower(text):gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then return nil end
  local starts, inside
  for _, p in ipairs(ns.professionList()) do
    for _, r in ipairs(ns.recipes(p.id) or {}) do
      local n = lower(r.name)
      if n == q then return r end
      if not starts and n:sub(1, #q) == q then starts = r end
      if not inside and n:find(q, 1, true) then inside = r end
    end
  end
  return starts or inside
end
