-- The profession scanner. The game lists your recipes only while a profession window is open, so each time you open
-- one, your skill and the recipes you know are saved for this character (EverlookCraftDB.chars, on this PC only).
-- Someone else's profession (a link in chat, a guild list) shows in the same window and is never saved as yours.
-- When the window shows other reagents than the data (the server changed a recipe), the window's version is saved and
-- used everywhere (EverlookCraftDB.fixes). Your skill levels are also read from the skill list at login, so the
-- planner knows them before you open a window. Based on EverlookDB Quests' Professions.lua (our own code).
local _, ns = ...
local try, plain = ns.try, ns.plain

local S = {}
ns.scan = S

-- the skill list (Classic style): profession name -> { rank, max }
function S.readSkills()
  local out = {}
  local n = plain(try(GetNumSkillLines)) or 0
  for i = 1, n do
    local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
    name, rank, maxRank = plain(name), plain(rank), plain(maxRank)
    if not isHeader and name and rank then out[name] = { rank = rank, max = maxRank } end
  end
  -- the retail-style list, where the client has it
  if next(out) == nil and GetProfessions and GetProfessionInfo then
    local list = { try(GetProfessions) }
    for i = 1, 6 do
      local idx = plain(list[i])
      if idx then
        local name, _, rank, maxRank = try(GetProfessionInfo, idx)
        name, rank, maxRank = plain(name), plain(rank), plain(maxRank)
        if name and rank then out[name] = { rank = rank, max = maxRank } end
      end
    end
  end
  return out
end

-- update this character's profession skill levels from the skill list
function S.updateSkills()
  local me = ns.me()
  if not me then return end
  for name, sk in pairs(S.readSkills()) do
    local id = ns.skillByName(name)
    if id then
      local p = me.profs[id] or { known = {} }
      p.rank, p.max = sk.rank, sk.max
      me.profs[id] = p
    end
  end
end

-- the profession the window shows: our skill line, from the game's profession ID or its name
local function professionOf(base)
  local id = plain(base.professionID)
  if id and ns.DATA and ns.DATA.profs[id] then return id end
  local pid = plain(base.parentProfessionID)
  if pid and ns.DATA and ns.DATA.profs[pid] then return pid end
  return ns.skillByName(plain(base.professionName)) or ns.skillByName(plain(base.parentProfessionName))
end

-- Is the window really yours? The skill list must have this profession (when the list can be read at all).
local function isMine(name)
  local skills = S.readSkills()
  if next(skills) == nil then return true end
  return skills[name] ~= nil
end

-- the reagents the window shows for a recipe: { item, n, ... } (basic reagents only)
local function windowReagents(T, id)
  local s = T.GetRecipeSchematic and try(T.GetRecipeSchematic, id, false)
  if not s then return nil end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  local out = {}
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    local re = slot.reagents and slot.reagents[1]
    local item = re and plain(re.itemID)
    if item and (basic == nil or slot.reagentType == nil or slot.reagentType == basic) then
      out[#out + 1] = item
      out[#out + 1] = plain(slot.quantityRequired) or 1
    end
  end
  return out
end

local function sameMats(list, mats)
  if #list ~= #mats * 2 then return false end
  local want = {}
  for _, m in ipairs(mats) do want[m[1]] = m[2] end
  for i = 1, #list, 2 do
    if want[list[i]] ~= list[i + 1] then return false end
  end
  return true
end

-- Read the open profession window. true = saved, false = nothing to save (not yours, or not a profession we know),
-- nil = not ready yet (try again).
function S.scan()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return false end
  if try(T.IsTradeSkillLinked) or try(T.IsTradeSkillGuild) or try(T.IsNPCCrafting) then return false end
  local base = try(T.GetBaseProfessionInfo)
  local name = base and plain(base.professionName)
  if not name or name == "" or not isMine(name) then return false end
  local skill = professionOf(base)
  if not skill then return false end
  local ids = try(T.GetAllRecipeIDs) or {}
  if #ids == 0 then return nil end
  -- right after switching windows the list can still hold the previous profession's recipes
  local p = T.GetProfessionInfoByRecipeID and try(T.GetProfessionInfoByRecipeID, ids[1])
  local a, b = p and plain(p.professionName), p and plain(p.parentProfessionName)
  if (a and a ~= "" or b and b ~= "") and a ~= name and b ~= name and not (a and a:find(name, 1, true)) then
    return nil
  end
  local rs = ns.recipes(skill)
  local known, n, twin = {}, 0, {}
  local fixes = EverlookCraftDB.fixes
  for _, id in ipairs(ids) do
    local info = try(T.GetRecipeInfo, id)
    if info and plain(info.learned) and not plain(info.isDummyRecipe) then
      local r = rs and rs.bySpell[id]
      local spell = r and r.spell or id
      known[spell], n = true, n + 1
      if spell ~= id then twin[spell] = id end   -- the window's own ID for a twin (Craft next casts that one)
      if r then
        local list = windowReagents(T, id)
        if list and #list > 0 then
          if sameMats(list, r.mats) then fixes[r.spell] = nil else fixes[r.spell] = list end
        end
      end
    end
  end
  if n == 0 then return false end
  local me = ns.me()
  if not me then return nil end
  local rec = me.profs[skill] or {}
  rec.known, rec.at = known, time()
  rec.ids = next(twin) and twin or nil
  rec.rank = plain(base.skillLevel) or rec.rank
  rec.max = plain(base.maxSkillLevel) or rec.max
  me.profs[skill] = rec
  S.lastSkill = skill
  if ns.onScanned then ns.onScanned(skill) end
  return true
end

-- the window fires several events while it fills: read it once things settle, and again if it was not ready
local pending, tries = false, 0
local function queue()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    if S.scan() == nil and tries < 4 then tries = tries + 1; queue() end
  end)
end
S.queue = queue

for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  ns.on(e, function(ev)
    if not EverlookCraftDB then return end
    if ev == "TRADE_SKILL_SHOW" then tries = 0 end
    queue()
  end)
end
for _, e in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED" }) do
  ns.on(e, function()
    if not EverlookCraftDB then return end
    S.updateSkills()
    if ns.onSkills then ns.onSkills() end
  end)
end

-- The profession your own window shows right now (its skill line), or nil: no window, or someone else's (a link, a
-- guild list, an NPC crafting for you).
function S.openSkill()
  local T = C_TradeSkillUI
  if not (T and T.GetBaseProfessionInfo) then return nil end
  local shown = rawget(_G, "ProfessionsFrame")
  if shown and shown.IsShown and not shown:IsShown() then return nil end
  if try(T.IsTradeSkillLinked) or try(T.IsTradeSkillGuild) or try(T.IsNPCCrafting) then return nil end
  local base = try(T.GetBaseProfessionInfo)
  if type(base) ~= "table" then return nil end
  local name = plain(base.professionName)
  if not name or name == "" or not isMine(name) then return nil end
  return professionOf(base)
end

-- the known recipes and skill of this character in a profession
function S.mine(skill)
  local me = ns.me()
  return me and me.profs[skill]
end

-- who of your characters knows a recipe: { name, ... }
function S.knownBy(spell)
  local out = {}
  local r = ns.recipeBySpell(spell)
  local key = r and r.spell or spell
  for _, c in pairs(EverlookCraftDB and EverlookCraftDB.chars or {}) do
    for _, p in pairs(c.profs or {}) do
      if p.known and p.known[key] then out[#out + 1] = c.name or "?" break end
    end
  end
  table.sort(out)
  return out
end
