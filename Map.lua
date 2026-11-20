-- Map: the nearest of some NPCs (trainers, vendors) for your side, and a pin on the world map (and in TomTom, when
-- installed) for it. Nearest by world distance when the client can tell it (same continent), else your zone first.
-- The pin helper follows EverlookDB Quests' DungeonQuests.lua (our own code).
local _, ns = ...
local try, plain = ns.try, ns.plain

local M = {}
ns.map = M

local function npc(id) return ns.DATA and ns.DATA.npcs[id] end

-- can `side` ("a"/"h") use an NPC on side s? ("n" both, "?" unknown counts as usable, "x" hostile to both)
function M.usable(s, side) return s ~= nil and s ~= "x" and (s == "n" or s == "?" or s == side) end

local function worldPos(map, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local cont, pos = try(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
  cont = plain(cont)
  if not cont or not pos then return nil end
  local px, py = try(pos.GetXY, pos)
  px, py = plain(px), plain(py)
  if not px then return nil end
  return cont, px, py
end

function M.here()
  local map = C_Map and plain(try(C_Map.GetBestMapForUnit, "player"))
  if not map then return nil end
  local pos = try(C_Map.GetPlayerMapPosition, map, "player")
  local x, y
  if pos then x, y = try(pos.GetXY, pos); x, y = plain(x), plain(y) end
  return map, x and x * 100 or nil, y and y * 100 or nil
end

-- the nearest usable NPC of `ids`: id, yards (nil when not known), zone name
function M.nearest(ids, side)
  side = side or ns.side()
  local map, x, y = M.here()
  local cont, wx, wy
  if map and x then cont, wx, wy = worldPos(map, x, y) end
  local myCont = map and ns.DATA.zones[map] and ns.DATA.zones[map][2]
  local best, bestD, bestRank
  for _, id in ipairs(ids or {}) do
    local n = npc(id)
    if n and M.usable(n[2], side) and n[6] ~= 1 and n[3] and n[3] ~= 0 then
      local d, rank
      if cont then
        local c2, x2, y2 = worldPos(n[3], n[4], n[5])
        if c2 == cont then d = math.sqrt((x2 - wx) ^ 2 + (y2 - wy) ^ 2) end
      end
      if d then rank = 0
      elseif n[3] == map then rank, d = 1, (x and math.sqrt((n[4] - x) ^ 2 + (n[5] - y) ^ 2) * 10 or 0)
      elseif myCont and ns.DATA.zones[n[3]] and ns.DATA.zones[n[3]][2] == myCont then rank, d = 2, 0
      else rank, d = 3, 0 end
      if not best or rank < bestRank or (rank == bestRank and d < bestD) then best, bestD, bestRank = id, d, rank end
    end
  end
  if not best then return nil end
  local n = npc(best)
  return best, bestRank == 0 and bestD or nil, ns.DATA.zones[n[3]] and ns.DATA.zones[n[3]][1] or "?"
end

function M.zoneName(map)
  local z = ns.DATA.zones[map]
  return z and z[1] or ("map " .. tostring(map))
end

-- Pin an NPC on the world map (followed on screen) and in TomTom, if installed. Prints where it is.
function M.pin(id)
  local n = npc(id)
  if not n or not n[3] or n[3] == 0 then
    ns.print("no known spot for that NPC.")
    return false
  end
  local map, x, y, label = n[3], n[4], n[5], n[1]
  local pinned = false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint
      and (not C_Map.CanSetUserWaypointOnMap or try(C_Map.CanSetUserWaypointOnMap, map)) then
    pinned = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
  end
  local tt = rawget(_G, "TomTom")
  if tt and tt.AddWaypoint then
    pinned = pcall(tt.AddWaypoint, tt, map, x / 100, y / 100, { title = label, from = ns.NAME }) or pinned
  end
  ns.print(("%s%s, %s %.1f %.1f"):format(pinned and "pinned " or "", label, M.zoneName(map), x, y))
  return pinned
end
