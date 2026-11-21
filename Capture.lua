-- What trainers and merchants really ask, saved per realm in this addon's own saved variables (EverlookCraftDB.realms,
-- this PC only) and used instead of the data:
--   * a trainer window: each recipe's fee and the skill it needs (the learn skill is then no longer an estimate), and
--     the fee, skill and level of each rank (Journeyman, Expert...);
--   * a merchant window: the price of every material (a reagent of any recipe, or a vendor good in the data). A
--     material the data didn't know a vendor for counts as a vendor good from then on, unless the merchant has only a
--     few (limited stock).
-- Only what the window shows is read: CraftColors-style filters are never changed, nothing is bought or learned.
local _, ns = ...
local try, plain = ns.try, ns.plain

local C = {}
ns.capture = C

ns.DEFAULTS.settings.capture = true

local function realmKey() return plain(try(GetRealmName)) or "?" end

-- this realm's record: { fees = { [spell] = { fee, learn, side, at } }, ranks = { [skill] = { [step] = { fee, req, level, at } } },
--   prices = { [item] = { price per unit, at } } }
function C.realm(create)
  local db = EverlookCraftDB
  if not db then return nil end
  db.realms = db.realms or {}
  local k = realmKey()
  local r = db.realms[k]
  if not r and create then
    r = { fees = {}, ranks = {}, prices = {} }
    db.realms[k] = r
  end
  return r
end

function C.enabled() return ns.settings().capture ~= false end

-- the price a merchant on this realm last asked for one, or nil
function C.price(id)
  local r = C.realm()
  local p = r and r.prices[id]
  return p and p[1] or nil
end

function C.fee(spell)
  local r = C.realm()
  return r and r.fees[spell]
end

---------------------------------------------------------------------------------------------------------------------
-- Overlay: seen fees and learn skills over the recipe tables, seen rank fees over the rank table

local patched = {}  -- recipe table -> true (patched with this realm's captures)

local function patchRecipe(r, f)
  if not r or not f then return end
  if f[1] then r.fee = f[1] end
  if f[2] and f[2] > 0 then
    r.learn = f[2]
    r.learnKnown = true
  end
  r.trained = true
  -- a trainer teaches it: learnable for that side, whatever the data said
  if f[3] and r.tier and (r.tier[f[3]] or 9) > 0 then r.tier[f[3]] = 0 end
end

local baseRecipes = ns.recipes
ns.recipes = function(skill)
  local rs = baseRecipes(skill)
  if rs and not patched[rs] then
    patched[rs] = true
    local r = C.realm()
    for spell, f in pairs(r and r.fees or {}) do patchRecipe(rs.bySpell[spell], f) end
  end
  return rs
end

local function patchRank(skill, step, f)
  local ranks = ns.DATA and ns.DATA.ranks and ns.DATA.ranks[skill]
  local rk = ranks and ranks[step]
  if not rk then return end
  if f[1] then rk[4] = f[1] end
  if f[2] and f[2] > 0 then rk[2] = f[2] end
  if f[3] and f[3] > 0 then rk[3] = f[3] end
end

function C.applyRanks()
  local r = C.realm()
  for skill, steps in pairs(r and r.ranks or {}) do
    for step, f in pairs(steps) do patchRank(skill, step, f) end
  end
end
ns.whenLoaded(C.applyRanks)

---------------------------------------------------------------------------------------------------------------------
-- Trainer window

local function rankStep(subText, name, skill)
  local names = ns.DATA and ns.DATA.rankNames or {}
  for step, rn in ipairs(names) do
    if subText == rn or (name and name:find(rn, 1, true)) then return step end
  end
  -- the service is named after the profession itself, the rank in its sub text
  if name and skill and name == ns.profName(skill) and subText then
    for step, rn in ipairs(names) do if subText:find(rn, 1, true) then return step end end
  end
end

-- the recipe a trainer service teaches, in a profession: by what it makes, else by name
local function recipeFor(skill, name, itemID)
  local rs = skill and ns.recipes(skill)
  if not rs then return nil end
  if itemID then
    local hit
    for _, r in ipairs(rs) do
      if r.creates == itemID then
        if hit and hit ~= r then hit = false break end
        hit = r
      end
    end
    if hit then return hit end
  end
  for _, r in ipairs(rs) do if r.name == name then return r end end
end

local function itemIdOf(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Read the open trainer window. Returns how many recipe fees and rank fees were saved.
function C.readTrainer()
  if not C.enabled() or not EverlookCraftDB then return 0, 0 end
  local n = plain(try(GetNumTrainerServices)) or 0
  if n == 0 then return 0, 0 end
  local rec = C.realm(true)
  local side = ns.side()
  local fees, ranks = 0, 0
  local trainerSkill   -- the profession the trainer teaches (from any service that names it)
  local services = {}
  for i = 1, n do
    local name, sub, kind = try(GetTrainerServiceInfo, i)
    name, sub, kind = plain(name), plain(sub), plain(kind)
    if name and kind ~= "header" then
      local skillName = plain(try(GetTrainerServiceSkillLine, i))
      local reqName, reqRank = try(GetTrainerServiceSkillReq, i)
      reqName, reqRank = plain(reqName), plain(reqRank)
      local skill = ns.skillByName(skillName) or ns.skillByName(reqName) or ns.skillByName(name)
      trainerSkill = trainerSkill or skill
      services[#services + 1] = { i = i, name = name, sub = sub, skill = skill, req = reqRank,
        cost = plain(try(GetTrainerServiceCost, i)), level = plain(try(GetTrainerServiceLevelReq, i)),
        item = itemIdOf(plain(try(GetTrainerServiceItemLink, i))) }
    end
  end
  for _, s in ipairs(services) do
    local skill = s.skill or trainerSkill
    if skill and type(s.cost) == "number" then
      -- a rank: "Tailoring" with the sub text "Journeyman", or "Journeyman Tailoring"
      local step = s.name:find(ns.profName(skill), 1, true) and rankStep(s.sub, s.name, skill)
      if step then
        rec.ranks[skill] = rec.ranks[skill] or {}
        rec.ranks[skill][step] = { s.cost, s.req, s.level, time() }
        patchRank(skill, step, rec.ranks[skill][step])
        ranks = ranks + 1
      else
        local r = recipeFor(skill, s.name, s.item)
        if r then
          local f = { s.cost, (type(s.req) == "number" and s.req > 0) and s.req or nil, side, time() }
          rec.fees[r.spell] = f
          patchRecipe(r, f)
          fees = fees + 1
        end
      end
    end
  end
  return fees, ranks
end

---------------------------------------------------------------------------------------------------------------------
-- Merchant window

-- one merchant row: { id, price (whole purchase), qty (per purchase), avail (-1 unlimited), extended }
function C.merchantRow(i)
  local id = plain(try(GetMerchantItemID, i))
  if not id then return nil end
  local price, qty, avail, extended
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = try(C_MerchantFrame.GetItemInfo, i)
    if type(info) == "table" then
      price, qty, avail, extended = plain(info.price), plain(info.stackCount), plain(info.numAvailable), plain(info.hasExtendedCost)
    end
  end
  if price == nil then
    local _, _, p, q, a, _, _, ext = try(GetMerchantItemInfo, i)
    price, qty, avail, extended = plain(p), plain(q), plain(a), plain(ext)
  end
  return { id = id, index = i, price = price, qty = math.max(1, qty or 1), avail = avail or -1, extended = extended and true or false,
    maxStack = plain(try(GetMerchantItemMaxStack, i)) }
end

-- every row of the open merchant
function C.merchantRows()
  local out = {}
  local n = plain(try(GetMerchantNumItems)) or 0
  for i = 1, n do
    local row = C.merchantRow(i)
    if row then out[#out + 1] = row end
  end
  return out
end

local function isMaterial(id)
  local it = ns.DATA and ns.DATA.items[id]
  if it and it[4] then return true, true end
  local idx = ns.tooltips and ns.tooltips.index()
  return idx and idx.usedIn[id] ~= nil or false, false
end

-- Save the open merchant's prices of materials. Returns how many were saved.
function C.readMerchant()
  if not C.enabled() or not EverlookCraftDB then return 0 end
  local rec = C.realm(true)
  local saved = 0
  for _, row in ipairs(C.merchantRows()) do
    local mat, dataVendor = isMaterial(row.id)
    if mat and row.price and row.price > 0 and not row.extended and (dataVendor or row.avail < 0) then
      rec.prices[row.id] = { row.price / row.qty, time() }
      saved = saved + 1
    end
  end
  return saved
end

local trainerPending, merchantPending = false, false
local function later(flag, fn)
  if flag() then return end
  flag(true)
  C_Timer.After(0.3, function() flag(false); local ok, err = pcall(fn); if not ok and geterrorhandler then geterrorhandler()(err) end end)
end
local function tflag(v) if v == nil then return trainerPending end trainerPending = v end
local function mflag(v) if v == nil then return merchantPending end merchantPending = v end

for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do
  ns.on(e, function() if EverlookCraftDB then later(tflag, C.readTrainer) end end)
end
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
  ns.on(e, function() if EverlookCraftDB then later(mflag, C.readMerchant) end end)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings

local function counts()
  local r = C.realm()
  local f, p, k = 0, 0, 0
  for _ in pairs(r and r.fees or {}) do f = f + 1 end
  for _ in pairs(r and r.prices or {}) do p = p + 1 end
  for _, steps in pairs(r and r.ranks or {}) do for _ in pairs(steps) do k = k + 1 end end
  return f, k, p
end
C.counts = counts

local app = ns.app
app:Setting({ key = "capture", type = "bool", label = "Remember what trainers and merchants ask",
  desc = "A trainer window saves its recipe fees, learn skills and rank fees; a merchant window saves its material prices. They are used instead of the data, for this realm.",
  keywords = { "trainer", "fee", "merchant", "vendor", "price", "seen", "learn" }, default = true,
  get = function() return C.enabled() end, set = function(v) ns.settings().capture = v and true or false end })

function C.forget()
  if EverlookCraftDB and EverlookCraftDB.realms then EverlookCraftDB.realms[realmKey()] = nil end
end

app:Section("vendors", "Trainers and merchants", function(stack)
  local UI = LibStub("EverlookUI-1")
  UI.Header(stack, "Trainers and merchants", "What they really ask on your realm beats the data.")
  app:Widget(stack, "capture")
  UI.Stat(stack, "Saved on " .. realmKey(), function()
    local f, k, p = counts()
    return ("%d recipe fees, %d rank fees, %d material prices"):format(f, k, p)
  end)
  app:Widget(stack, "merchant.button")
  UI.ButtonRow(stack, {
    { label = "Forget this realm's prices", width = 210, confirm = true, onClick = function() C.forget(); app:Refresh() end,
      desc = "Forget the trainer fees and merchant prices saved on this realm; the addon's own data is used again after a /reload.",
      keywords = { "reset", "clear", "fees", "prices" } },
  })
  UI.Note(stack, "Fees and prices are saved only on this PC, in this addon's own saved variables. Learn skills a trainer showed are marked as known (no ~) in the planner.")
end, { icon = "scroll" })
