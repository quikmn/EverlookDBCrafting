-- Skill-up cards: "Hurray! Tailoring 151" at the top right of the screen whenever a profession or secondary skill
-- rises (crafting, gathering, Fishing, Cooking, First Aid, Lockpicking, Poisons; weapon and defense skills only when
-- switched on). The card has the profession's icon, a thin bar toward the rank's cap and, when it helps, a hint: the
-- rank to train when you hit the cap, or the next step of your route ("next: Bolt of Silk Cloth x12"). Several
-- skill-ups while the card is up add to it (+3). Every 25 points, a rank's cap and 300 get a short firework.
--
-- Where it comes from: the game's "Your skill in %s has increased to %d." (SKILL_RANK_UP, any language), and the skill
-- list compared with what it said before (SKILL_LINES_CHANGED), so a skill-up is never missed or shown twice. No
-- combat log; values the game keeps secret are skipped.
--
-- Same look and size as EverlookDB Auctions' loot cards, in the same column: when that addon is loaded the skill cards
-- sit right under its loot cards (EverlookCardColumn, a small table both addons share), else at the same spot. A spot
-- you drag them to (/ecraft skillcards move) is their own.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")
local try, plain = ns.try, ns.plain

local K = {}
ns.skillCards = K

local SHOW_FOR = 5      -- seconds on screen, then a fade of FADE
local FADE = 0.6
local MAX = 3           -- cards at once; the oldest goes first
local W, H, ICON, GAP = 300, 46, 34, 6   -- EverlookDB Auctions' loot cards
local SPARKS = 14
local GOLD = { 1, 0.82, 0 }
local SPARK_COLORS = { { 1, 0.82, 0.2 }, { 0.4, 0.75, 1 }, { 1, 0.45, 0.75 }, { 0.45, 1, 0.55 }, { 1, 1, 1 } }
local DASH, TIMES = " \226\128\148 ", "\195\151"

local D = ns.DEFAULTS.settings
D.skillCards = true        -- a card when a profession rises
D.skillFireworks = true    -- fireworks every 25 points, at a rank's cap and at 300
D.skillSound = false       -- a soft sound with each card
D.skillOther = false       -- weapon, defense and other skills too
-- D.skillPos: { x, y } of the newest card's top right corner from the screen's top right; nil = in the column

local function S() return ns.settings() end
local function enabled() return S().skillCards ~= false end

---------------------------------------------------------------------------------------------------------------------
-- The chat line, in any language: the game's own format string turned into a pattern. Handles "%s"/"%d", numbered
-- "%1$s"/"%2$d" (in any order) and the Korean grammar codes ("|1X;Y;").

local MAGIC = "[%(%)%.%%%+%-%*%?%[%]%^%$]"

-- format -> pattern, { argument number of each capture }
function K.compile(f)
  if type(f) ~= "string" or f == "" then return nil end
  local parts, order, n, i = {}, {}, 0, 1
  while i <= #f do
    local pos, kind, after = f:match("^%%(%d)%$([sd])()", i)
    if not kind then kind, after = f:match("^%%([sd])()", i) end
    if kind then
      n = n + 1
      order[n] = tonumber(pos) or n
      parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
      i = after
    elseif f:sub(i, i + 1) == "%%" then
      parts[#parts + 1] = "%%"
      i = i + 2
    elseif f:find("^|1[^;]*;[^;]*;", i) then
      local _, e = f:find("^|1[^;]*;[^;]*;", i)
      parts[#parts + 1] = ".-"
      i = e + 1
    else
      local ch = f:sub(i, i)
      parts[#parts + 1] = ch:find(MAGIC) and ("%" .. ch) or ch
      i = i + 1
    end
  end
  return "^" .. table.concat(parts) .. "$", order
end

local compiled, compiledFrom
-- "Your skill in Tailoring has increased to 151." -> "Tailoring", 151 (nil when it is another line)
function K.parse(msg, format)
  msg = plain(msg)
  if type(msg) ~= "string" then return nil end
  local f = format or rawget(_G, "SKILL_RANK_UP") or "Your skill in %s has increased to %d."
  if compiledFrom ~= f then compiled, compiledFrom = { K.compile(f) }, f end
  local pat, order = compiled[1], compiled[2]
  if not pat then return nil end
  local caps = { msg:match(pat) }
  if #caps == 0 then return nil end
  local args = {}
  for k, v in ipairs(caps) do args[order[k] or k] = v end
  local name, rank = args[1], tonumber(args[2])
  if type(name) ~= "string" or name == "" or not rank then return nil end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return name, rank
end

---------------------------------------------------------------------------------------------------------------------
-- Which skills count, their skill line and icon

-- English names (the data's professions come on top), and the skill lines the data doesn't have
local EXTRA = { Herbalism = 182, Skinning = 393, Fishing = 356, Lockpicking = 633, Mining = 186, Poisons = 40,
  ["First Aid"] = 129, Cooking = 185 }
-- a profession's spells: their names in your language find the skill line too
local SPELLS = { [171] = 2259, [164] = 2018, [333] = 7411, [202] = 4036, [182] = 2366, [165] = 2108, [186] = 2575,
  [393] = 8613, [197] = 3908, [185] = 2550, [129] = 3273, [356] = 7620, [40] = 2842, [633] = 1804 }
local ICONS = { [182] = 136246, [393] = 134366, [356] = 136245, [633] = 136058 }
-- the skill list's headers that hold professions (Classic: "Professions" and "Secondary Skills")
local function profHeaders()
  local h = { professions = true, ["secondary skills"] = true, ["class skills"] = false }
  for _, g in ipairs({ "TRADE_SKILLS", "SECONDARY_SKILLS", "PROFESSIONS_HEADER", "PROFESSIONS" }) do
    local v = rawget(_G, g)
    if type(v) == "string" then h[(v:gsub(":%s*$", "")):lower()] = true end
  end
  return h
end

local byName
local function nameMap()
  if byName then return byName end
  byName = {}
  for name, id in pairs(EXTRA) do byName[name:lower()] = id end
  for id, p in pairs(ns.DATA and ns.DATA.profs or {}) do byName[p.name:lower()] = id end
  if C_Spell and C_Spell.GetSpellInfo then
    for id, spell in pairs(SPELLS) do
      local info = try(C_Spell.GetSpellInfo, spell)
      local n = info and plain(info.name)
      if type(n) == "string" and n ~= "" and not byName[n:lower()] then byName[n:lower()] = id end
    end
  end
  return byName
end

-- the skill line of a skill's name (nil: not a profession we know by name)
function K.skillOf(name)
  if type(name) ~= "string" then return nil end
  return nameMap()[name:lower()]
end

-- "prof" (a profession or secondary skill) or "other" (weapons, defense, languages, ...)
function K.kind(name, header)
  if K.skillOf(name) then return "prof" end
  if type(header) == "string" and profHeaders()[(header:gsub(":%s*$", "")):lower()] then return "prof" end
  return "other"
end

function K.icon(id, name)
  if id and ICONS[id] then return ICONS[id] end
  if id and ns.PROF_ICONS[id] then return ns.PROF_ICONS[id] end
  local tex = name and plain(try(C_Spell and C_Spell.GetSpellTexture, name))
  return tex or 136243
end

---------------------------------------------------------------------------------------------------------------------
-- The skill list now: name -> { rank, max, header }

function K.readList()
  local out = {}
  local n = plain(try(GetNumSkillLines)) or 0
  local header
  for i = 1, n do
    local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
    name, rank, maxRank = plain(name), plain(rank), plain(maxRank)
    if plain(isHeader) then
      header = name
    elseif type(name) == "string" and type(rank) == "number" then
      out[name] = { rank = rank, max = type(maxRank) == "number" and maxRank or nil, header = header }
    end
  end
  if next(out) == nil and GetProfessions and GetProfessionInfo then
    local list = { try(GetProfessions) }
    for i = 1, 6 do
      local idx = plain(list[i])
      if idx then
        local name, _, rank, maxRank = try(GetProfessionInfo, idx)
        name, rank, maxRank = plain(name), plain(rank), plain(maxRank)
        if type(name) == "string" and type(rank) == "number" then out[name] = { rank = rank, max = maxRank, header = "professions" } end
      end
    end
  end
  return out
end

local snap, ready = {}, false
K.JUMP = 5   -- the most points one craft or gather can give
K.snap = snap

---------------------------------------------------------------------------------------------------------------------
-- The hint under the title

-- the rank after a cap: its index (2 Journeyman .. 4 Artisan)
local function nextStep(max)
  if type(max) ~= "number" or max >= 300 or max % 75 ~= 0 then return nil end
  return max / 75 + 1
end

-- What helps right now: the rank to get when you hit the cap, else the next step of your route for it
function K.hint(e)
  local id = e.skill
  if K.kind(e.name, e.header) ~= "prof" then return nil end
  if e.max and e.rank >= e.max and e.max < 300 then
    local step = nextStep(e.max)
    local rankName = step and ns.DATA and ns.DATA.rankNames[step]
    local rk = step and id and ns.DATA and ns.DATA.ranks[id] and ns.DATA.ranks[id][step]
    local how
    if rk and #rk[5] == 0 and rk[6] and rk[6] ~= 0 then how = "read " .. (ns.itemInfo(rk[6]))
    elseif rk and #rk[5] == 0 and rk[8] and #rk[8] > 0 then how = "quest " .. tostring(rk[8][2] or "?")
    elseif rankName then how = "train " .. rankName
    else how = "train the next rank" end
    local lvl = rk and rk[3]
    local mine = plain(try(UnitLevel, "player"))
    if type(lvl) == "number" and type(mine) == "number" and mine < lvl then how = how .. (" at level %d"):format(lvl) end
    return ("rank cap at %d"):format(e.max) .. DASH .. how, true
  end
  local route = id and ns.plans and ns.plans.saved(id)
  if route and route.steps then
    local _, st = ns.plans.currentStep(route, e.rank)
    if st then
      local r = ns.plans.recipe(id, st.spell)
      local n = ns.plans.craftsLeft(route, st, e.rank)
      if r then return ("next: %s %s%d"):format(r.name, TIMES, n or st.n or 1) end
    elseif route.to and e.rank >= route.to then
      return "your route is done"
    end
  end
end

-- a milestone between two ranks: every 25, the rank's cap, 300
function K.milestone(from, to, max)
  if type(to) ~= "number" then return false end
  from = type(from) == "number" and from or to - 1
  if math.floor(from / 25) < math.floor(to / 25) then return true end
  if max and to >= max and from < max then return true end
  return to >= 300 and from < 300
end

-- the bar: how far into the rank (Apprentice 0-75, Journeyman 75-150, ...), else toward the cap
function K.progress(rank, max)
  if type(rank) ~= "number" or type(max) ~= "number" or max <= 0 then return 0 end
  local low = (max % 75 == 0 and max >= 75) and (max - 75) or 0
  return math.max(0, math.min(1, (rank - low) / (max - low)))
end

---------------------------------------------------------------------------------------------------------------------
-- Where the cards go. EverlookCardColumn = { stacks = { [name] = { order, anchor() -> x, y, height() -> px,
-- relayout() } } }: each EverlookDB addon with cards at the top right puts its stack in; a stack sits under the ones
-- with a lower order (EverlookDB Auctions' loot cards: 10, these: 20) and at the first one's spot.

local ME, ORDER = "crafting.skillups", 20
local cards, pool = {}, {}
K.cards = cards

local function column()
  local c = rawget(_G, "EverlookCardColumn")
  if type(c) ~= "table" then
    c = { stacks = {} }
    _G.EverlookCardColumn = c
  end
  if type(c.stacks) ~= "table" then c.stacks = {} end
  return c
end

local function defaultXY()
  return -math.floor((UIParent:GetWidth() or 0) * 0.17), -math.floor((UIParent:GetHeight() or 0) * 0.19)
end

local function auctionsHere() return rawget(_G, "EverlookDBAuctionsAPI") ~= nil end

-- the newest card's top right corner, from the screen's top right
function K.anchorXY()
  local p = S().skillPos
  if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then return p[1], p[2], "own" end
  local lead, above = nil, 0
  for name, st in pairs(column().stacks) do
    if name ~= ME and type(st) == "table" and (tonumber(st.order) or 0) < ORDER then
      if not lead or (tonumber(st.order) or 0) < (tonumber(lead.order) or 0) then lead = st end
      local ok, h = pcall(st.height)
      above = above + (ok and tonumber(h) or 0)
    end
  end
  if lead and type(lead.anchor) == "function" then
    local ok, x, y = pcall(lead.anchor)
    if ok and tonumber(x) and tonumber(y) then return x, y - above, "column" end
  end
  -- EverlookDB Auctions without the shared column: below the room its loot cards can take
  if auctionsHere() then
    local adb = rawget(_G, "EverlookAuctionsDB")
    local lp = type(adb) == "table" and adb.lootPos
    local x, y
    if type(lp) == "table" and tonumber(lp[1]) and tonumber(lp[2]) then x, y = lp[1], lp[2] else x, y = defaultXY() end
    if type(adb) == "table" and adb.lootCards == false then return x, y, "auctions" end
    return x, y - 5 * (H + GAP), "auctions"
  end
  local x, y = defaultXY()
  return x, y, "default"
end

local function layout()
  local x, y = K.anchorXY()
  for i, c in ipairs(cards) do
    c:ClearAllPoints()
    c:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y - (i - 1) * (H + GAP))
  end
end
K.layout = layout

local function notifyBelow()
  for name, st in pairs(column().stacks) do
    if name ~= ME and type(st) == "table" and (tonumber(st.order) or 0) > ORDER and type(st.relayout) == "function" then
      pcall(st.relayout)
    end
  end
end

column().stacks[ME] = {
  order = ORDER,
  anchor = function() local x, y = K.anchorXY(); return x, y end,
  height = function() return #cards > 0 and #cards * (H + GAP) or 0 end,
  relayout = function() layout() end,
}

---------------------------------------------------------------------------------------------------------------------
-- The cards

local function makeCard()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(W, H)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(false)
  local T = UI.MakeTheme(GOLD)
  f.eluiTheme = T
  UI.WindowChrome(f, T)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(ICON, ICON)
  f.icon:SetPoint("LEFT", 8, 0)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.iconBorder = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.iconBorder:SetPoint("TOPLEFT", f.icon, -1, 1)
  f.iconBorder:SetPoint("BOTTOMRIGHT", f.icon, 1, -1)
  f.iconBorder:SetColorTexture(0.75, 0.62, 0.15, 0.9)
  f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.count:SetPoint("TOPRIGHT", -10, -8)
  f.count:SetTextColor(0.62, 0.66, 0.72)
  f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.name:SetJustifyH("LEFT")
  f.name:SetWordWrap(false)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 10, 3)
  f.sub:SetPoint("RIGHT", -10, 0)
  f.sub:SetJustifyH("LEFT")
  f.sub:SetWordWrap(false)
  f.sub:SetTextColor(0.62, 0.66, 0.72)
  -- the thin bar toward the cap, along the bottom under the text
  f.barBg = f:CreateTexture(nil, "ARTWORK")
  f.barBg:SetColorTexture(1, 1, 1, 0.08)
  f.barBg:SetHeight(2)
  f.barBg:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 10, -3)
  f.barBg:SetPoint("RIGHT", -10, 0)
  f.bar = f:CreateTexture(nil, "OVERLAY")
  f.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
  f.bar:SetHeight(2)
  f.bar:SetPoint("LEFT", f.barBg, "LEFT", 0, 0)
  f.sparks = {}
  for i = 1, SPARKS * 3 do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Cooldown\\star4")
    t:SetBlendMode("ADD")
    t:SetSize(16, 16)
    t:Hide()
    f.sparks[i] = t
  end
  f:SetScript("OnUpdate", function(self, el)
    self.age = (self.age or 0) + el
    local a = self.age
    for _, sp in ipairs(self.sparks) do
      local t = sp.delay and (a - sp.delay) or -1
      if self.fireworks and t > 0 and t < 1.2 then
        local d = sp.speed * (1 - (1 - t / 1.2) ^ 2)
        sp:ClearAllPoints()
        sp:SetPoint("CENTER", self, "CENTER", sp.x + math.cos(sp.angle) * d, sp.y + math.sin(sp.angle) * d - 24 * t * t)
        sp:SetAlpha(1 - t / 1.2)
        sp:Show()
      else
        sp:Hide()
      end
    end
    self:SetAlpha(a < 0.2 and a / 0.2 or (a > SHOW_FOR and math.max(0, 1 - (a - SHOW_FOR) / FADE) or 1))
    if a > SHOW_FOR + FADE then K.drop(self) end
  end)
  return f
end

local function burst(f, from, delay)
  local cx, cy = ({ -W / 2 + 20, 0, W / 2 - 20 })[from], ({ 4, H / 2, 4 })[from]
  local c = SPARK_COLORS[math.random(#SPARK_COLORS)]
  for i = 1, SPARKS do
    local sp = f.sparks[(from - 1) * SPARKS + i]
    sp.delay = delay
    sp.angle = (i / SPARKS) * math.pi * 2 + math.random() * 0.3
    sp.speed = 34 + math.random() * 30
    sp.x, sp.y = cx, cy
    sp:SetVertexColor(c[1], c[2], c[3])
  end
end

function K.drop(card)
  for i, c in ipairs(cards) do
    if c == card then table.remove(cards, i); break end
  end
  card:Hide()
  card.key, card.fireworks = nil, nil
  pool[#pool + 1] = card
  layout()
  notifyBelow()
end

-- the card's text: "Hurray! Tailoring 151  +3", the rank and cap, the hint
function K.fill(card)
  local e = card.e
  card.icon:SetTexture(K.icon(e.skill, e.name))
  local gain = e.rank - (e.from or e.rank - 1)
  card.name:SetText(("Hurray! |cffffffff%s|r |cff62cf88%d|r  |cff62cf88+%d|r"):format(e.name, e.rank, math.max(gain, 1)))
  card.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  card.count:SetText(e.max and ("%d / %d"):format(e.rank, e.max) or "")
  local ok, hint, cap = pcall(K.hint, e)
  if not ok then hint, cap = nil, nil end
  card.hint = hint
  card.sub:SetText(hint or "")
  card.sub:SetTextColor(cap and 1 or 0.62, cap and 0.82 or 0.66, cap and 0 or 0.72)
  card.name:ClearAllPoints()
  if hint then card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1) else card.name:SetPoint("LEFT", card.icon, "RIGHT", 10, 2) end
  card.name:SetPoint("RIGHT", card.count, "LEFT", -6, 0)
  local p = K.progress(e.rank, e.max)
  card.barBg:SetShown(e.max ~= nil)
  card.bar:SetShown(e.max ~= nil and p > 0)
  card.bar:SetWidth(math.max(1, (W - ICON - 28) * p))
end

local function sound(big)
  if not S().skillSound or not PlaySound then return end
  local K2 = SOUNDKIT or {}
  try(PlaySound, big and (K2.UI_EPICLOOT_TOAST or 31578) or (K2.IG_QUEST_LIST_OPEN or 875), "SFX")
end

-- e = { name, rank, from, max, header, skill }: a card for it, or added to its card still up. Returns the card.
function K.show(e)
  if not enabled() or type(e) ~= "table" or type(e.name) ~= "string" or type(e.rank) ~= "number" then return end
  e.skill = e.skill or K.skillOf(e.name)
  if K.kind(e.name, e.header) == "other" and not S().skillOther then return end
  local card
  for _, c in ipairs(cards) do
    if c.key == e.name and (c.age or 0) < SHOW_FOR then card = c break end
  end
  local first = e.from or (e.rank - 1)
  if card then
    card.e.rank = math.max(card.e.rank, e.rank)
    card.e.max = e.max or card.e.max
    card.age = math.min(card.age or 0, 0.2)   -- stays another full 5 seconds
  else
    card = table.remove(pool) or makeCard()
    card.key, card.age, card.fireworks = e.name, 0, nil
    card.e = { name = e.name, rank = e.rank, from = first, max = e.max, skill = e.skill, header = e.header }
    table.insert(cards, 1, card)
    while #cards > MAX do K.drop(cards[#cards]) end
    card:SetAlpha(0)
  end
  local big = S().skillFireworks ~= false and K.kind(e.name, e.header) == "prof" and K.milestone(first, e.rank, card.e.max)
  if big then
    card.fireworks = true
    local base = card.age or 0
    for k = 1, 3 do burst(card, k, base + (k - 1) * 0.3) end
  end
  K.fill(card)
  card:Show()
  layout()
  notifyBelow()
  sound(big)
  return card
end

---------------------------------------------------------------------------------------------------------------------
-- A skill rose: from the chat line (name, rank) or the skill list. The same rank never gets a second card.

function K.rose(name, rank, cur)
  if type(name) ~= "string" or type(rank) ~= "number" then return end
  local prev = snap[name]
  if prev and type(prev.rank) == "number" and rank <= prev.rank then return end
  cur = cur or K.readList()[name]
  local max = cur and cur.max or (prev and prev.max)
  local header = cur and cur.header or (prev and prev.header)
  snap[name] = { rank = rank, max = max, header = header }
  -- a jump of more than JUMP points is not a skill-up we saw happen (the list was read stale at login, or the skill
  -- rose while it couldn't be read): count it as one point, no milestone fireworks for the points in between
  local from = prev and prev.rank or nil
  if from and rank - from > K.JUMP then from = rank - 1 end
  return K.show({ name = name, rank = rank, from = from, max = max, header = header })
end

-- the skill list changed: anything higher than before gets its card (the first read only remembers)
function K.compare()
  local list = K.readList()
  for name, cur in pairs(list) do
    local prev = snap[name]
    if ready and prev and type(prev.rank) == "number" and cur.rank > prev.rank then
      K.rose(name, cur.rank, cur)
    else
      snap[name] = cur
    end
  end
  if next(list) ~= nil then ready = true end
end

function K.reset()
  for k in pairs(snap) do snap[k] = nil end
  ready = false
end

ns.on("PLAYER_LOGIN", function() K.compare() end)
ns.on("SKILL_LINES_CHANGED", function() K.compare() end)
ns.on("CHAT_MSG_SKILL", function(_, msg)
  local name, rank = K.parse(msg)
  if name then K.rose(name, rank) end
end)

---------------------------------------------------------------------------------------------------------------------
-- Moving them: a card-sized handle to drag; the cards follow, the spot is saved (their own, out of the column)

local mover
function K.move(show)
  if not mover then
    mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    mover:SetSize(W, H)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetClampedToScreen(true)
    if mover.SetBackdrop then
      mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      mover:SetBackdropColor(0.2, 0.6, 0.3, 0.35)
      mover:SetBackdropBorderColor(0.3, 0.9, 0.4, 1)
    end
    local t = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER")
    t:SetText("Skill-up cards: drag me, right-click when done")
    mover:SetScript("OnDragStart", mover.StartMoving)
    mover:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      if self:GetRight() and UIParent:GetRight() then
        S().skillPos = { math.floor(self:GetRight() - UIParent:GetRight() + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
      end
      self:ClearAllPoints()
      local x, y = K.anchorXY()
      self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y)
      layout()
    end)
    mover:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then self:Hide() end end)
    mover:Hide()   -- a new frame is shown: hidden until asked for
  end
  if show == nil then show = not mover:IsShown() end
  if not show then mover:Hide() return false end
  local x, y = K.anchorXY()
  mover:ClearAllPoints()
  mover:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y)
  mover:Show()
  return true
end
function K.moving() return mover ~= nil and mover:IsShown() end

function K.resetPos()
  S().skillPos = nil
  layout()
  if K.moving() then K.move(true) end
end

-- two example cards: a skill-up with the route hint, and a rank's cap with fireworks
function K.test()
  local was = S().skillCards
  S().skillCards = true
  K.show({ name = ns.profName(197), rank = 151, from = 148, max = 225, skill = 197, header = "Professions" })
  K.show({ name = ns.profName(129), rank = 150, from = 149, max = 150, skill = 129, header = "Secondary Skills" })
  S().skillCards = was
end

---------------------------------------------------------------------------------------------------------------------
-- Settings, the settings page and /ecraft skillcards

local app = ns.app
local function setting(key, field, label, desc, keywords)
  app:Setting({ key = key, type = "bool", label = label, desc = desc, keywords = keywords,
    get = function() return S()[field] end, set = function(v) S()[field] = v and true or false end,
    default = D[field] })
end
setting("skillcards", "skillCards", "Skill-up cards",
  "A card at the top right when a profession rises: Hurray!, the new skill, a bar toward the rank's cap and what to do next.",
  { "skill up", "skillup", "hurray", "card", "toast", "level", "profession", "gathering", "fishing", "cooking", "first aid", "popup" })
setting("skillcards.fireworks", "skillFireworks", "Fireworks at milestones",
  "Every 25 points, a rank's cap and 300 get a short firework on the card.",
  { "milestone", "fireworks", "sparkle", "celebrate", "cap" })
setting("skillcards.sound", "skillSound", "Play a soft sound",
  "A quiet sound with each skill-up card (a brighter one at milestones).", { "sound", "audio", "noise", "chime" })
setting("skillcards.weapons", "skillOther", "Weapon and defense skills too",
  "Cards for weapon skills, Defense and other skills as well, not only professions.",
  { "weapon", "defense", "defence", "sword", "skills" })

app:Section("skillcards", "Skill-up cards", function(stack)
  UI.Header(stack, "Skill-up cards", "Every profession and secondary skill that rises gets a card at the top right, in the same column as EverlookDB Auctions' loot cards.")
  app:Widget(stack, "skillcards")
  app:Widget(stack, "skillcards.fireworks")
  app:Widget(stack, "skillcards.sound")
  app:Widget(stack, "skillcards.weapons")
  stack:Space(4)
  UI.ButtonRow(stack, {
    { label = "Show an example", width = 150, onClick = function() K.test() end,
      desc = "Two example cards.", keywords = { "test", "preview", "example" } },
    { label = "Move cards", width = 124, onClick = function() K.move() end,
      desc = "Drag the green box, right-click it when done.", keywords = { "move", "drag", "position", "place" } },
    { label = "Reset spot", width = 124, onClick = function() K.resetPos() end,
      desc = "Back to the top right, under the loot cards.", keywords = { "reset", "position", "default" } },
  })
  UI.Note(stack, "The hint says which rank to learn when you hit a cap, else the next step of your route for that profession. Several skill-ups while the card is up add to it.")
end, { icon = "sparkle", desc = "A Hurray! card at the top right whenever a profession rises." })

app:Command("skillcards", "skillcards [on | off | move | reset | test]",
  "the skill-up cards: their settings page, switch them on or off, move them, put them back, or show an example",
  function(rest)
    local w = UI.Util.Trim(rest or ""):lower()
    if w == "" then app:Open("skillcards") return end
    if w == "move" or w == "unlock" then
      local on = K.move(w == "unlock" and true or nil)
      app:Print(on and "drag the green box, right-click it (or /ecraft skillcards lock) when done." or "skill-up cards locked.")
      return
    end
    if w == "lock" then K.move(false); app:Print("skill-up cards locked.") return end
    if w == "reset" then K.resetPos(); app:Print("skill-up cards are back at the top right.") return end
    if w == "test" then K.test() return end
    app:SetFromText(app:GetSetting("skillcards"), w)
  end, { "skillcard", "skillups", "skillup" })
