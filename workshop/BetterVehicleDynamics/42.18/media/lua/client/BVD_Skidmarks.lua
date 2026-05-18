local MIN_INTERVAL_MS = 90     -- sample the path often so drift arcs are smooth
local DEDUPE_MS       = 1500
local BURNOUT_SPEED   = 10
local SKID_SPEED      = 30

-- The vehicle can travel several tiles between two drops, which used to
-- leave visible gaps between separate stamps. We now fill every tile
-- along the segment from the previous drop to the current one so the
-- skid reads as one continuous streak at any speed.
local STEP_TILES    = 0.5      -- interpolation granularity (tiles)
local MAX_FILL_DIST = 20.0     -- skip the fill past this (teleport/chunk load)

local TYPE_V, TYPE_H, TYPE_D1, TYPE_D2 = 21, 22, 23, 24

-- ---------------------------------------------------------------------------
-- Heading -> decal-orientation mapping.
--
-- KEY FACT: PZ blits a floor decal as a SCREEN-aligned quad at the tile's
-- screen position -- it does NOT iso-project the sprite per pixel. So the
-- decal's on-screen line orientation is just its image orientation, and the
-- four sprites are authored to the four distinct ON-SCREEN line angles:
--   _h  (TYPE_H)  : screen-horizontal
--   _v  (TYPE_V)  : screen-vertical
--   _d1 (TYPE_D1) : shallow iso diagonal  ( +atan(0.5) ~= +26.565 deg )
--   _d2 (TYPE_D2) : shallow iso diagonal  ( -atan(0.5), the mirror )
--
-- A vehicle's WORLD heading therefore has to be projected into screen space
-- before we can pick the matching sprite. PZ's iso projection of a world
-- delta (dx, dy) is, up to a uniform scale:
--     sx = dx - dy
--     sy = (dx + dy) * 0.5            (2:1 tile ratio)
-- A skid line is undirected, so we fold the screen angle into [0, 180) and
-- bucket to the nearest of the four authored screen angles
-- {0 (H), 26.565 (D1), 90 (V), 153.435 (D2)} using their midpoints as bin
-- edges. Consequences (these are the cases the old world-space code got
-- wrong): driving straight along a world-cardinal road moves on screen at
-- +-26.565 deg, so it now correctly picks a shallow diagonal sprite, not
-- H/V; driving a world-diagonal moves screen-vertical/horizontal -> V/H.
--
-- HEADING_OFFSET_DEG and SWAP_D1_D2 stay as escape hatches: only the d1<->d2
-- handedness and an overall mirror are convention-ambiguous from Lua; if the
-- user reports the diagonals look mirrored, flip SWAP_D1_D2.
local HEADING_OFFSET_DEG = 0      -- added to the SCREEN angle before bucketing
local SWAP_D1_D2         = false  -- flip if the two diagonals come out mirrored

local LAST_TICK_MS = 0
local recentTiles  = {}
local lastDrop     = nil   -- {x,y,z} last placed point in the CURRENT streak

-- Probe-and-cache (project Kahlua rule: Kahlua red-logs caught Java
-- exceptions, so probe each uncertain Java method ONCE and remember the
-- result instead of call-and-hope every tick).
local probedForward = nil   -- true once getForwardVector is known usable
local lastPos       = {}    -- per-vehicle last (x,y) for delta heading

-- Returns a continuous heading in degrees (atan2 convention, from +X CCW)
-- or nil if no source is reliably available this tick. Order of
-- preference: position-delta (same coord frame as decal placement, so
-- zero axis-convention risk) -> getForwardVector (physics ground plane is
-- .x/.z) -> getDir() coarse enum (last resort, never errors).
local function vehicleHeadingDeg(v)
    -- 1. Position delta in the exact getX()/getY() frame the decal uses.
    local id = v.getId and v:getId() or tostring(v)
    local x, y = v:getX(), v:getY()
    local prev = lastPos[id]
    lastPos[id] = { x = x, y = y, ts = (getTimestampMs and getTimestampMs() or 0) }
    if prev then
        local dx, dy = x - prev.x, y - prev.y
        if (dx * dx + dy * dy) > 0.0004 then   -- ~0.02 tile of motion
            return math.deg(math.atan2(dy, dx))
        end
    end

    -- 2. getForwardVector(Vector3f): physics ground plane is .x / .z
    --    (.y is the vertical/height axis in PZ's physics Vector3f).
    if probedForward ~= false and v.getForwardVector and Vector3f then
        local ok, hx, hz = pcall(function()
            local fv = Vector3f.new(0, 0, 0)
            v:getForwardVector(fv)
            return fv:x(), fv:z()
        end)
        if ok and hx and hz and (hx * hx + hz * hz) > 1e-6 then
            probedForward = true
            -- world ground frame: X<->x, Y<->z
            return math.deg(math.atan2(hz, hx))
        elseif probedForward == nil then
            probedForward = false   -- unusable here; stop trying
        end
    end

    -- 3. Coarse 8-way enum -- never errors, just imprecise.
    if v.getDir then
        local n = tostring(v:getDir())
        -- Degrees chosen to match atan2(dy, dx) in PZ's frame
        -- (X = east, Y = south, north = -Y) so this last-resort path
        -- folds/buckets identically to the two primary paths.
        if     n == "N"  then return 90
        elseif n == "S"  then return 270
        elseif n == "E"  then return 0
        elseif n == "W"  then return 180
        elseif n == "NE" then return 315
        elseif n == "NW" then return 225
        elseif n == "SE" then return 45
        elseif n == "SW" then return 135
        end
    end
    return nil
end

local function preloadTextures()
    local files = {
        bvd_tiremark_v  = "media/textures/Item_bvd_tiremark_v.png",
        bvd_tiremark_h  = "media/textures/Item_bvd_tiremark_h.png",
        bvd_tiremark_d1 = "media/textures/Item_bvd_tiremark_d1.png",
        bvd_tiremark_d2 = "media/textures/Item_bvd_tiremark_d2.png",
    }
    for name, path in pairs(files) do
        local t = getTexture(path)
        if t and Texture and Texture.BVD_registerSharedTexture then
            Texture.BVD_registerSharedTexture(name, t)
        end
    end
    -- Re-probe the forward-vector path each world load: a stale false
    -- from one odd vehicle must not permanently disable it.
    probedForward = nil
    print("[BVD.Skidmarks] 4 orientation sprites registered")
end

Events.OnGameBoot.Add(preloadTextures)

-- Last-resort default when no heading is available: keep V (matches the
-- previous code's fallback so behaviour is unchanged on total failure).
local LAST_TYPE = TYPE_V

local function typeForVehicle(v)
    local h = vehicleHeadingDeg(v)
    if not h then return LAST_TYPE end

    -- World heading -> world unit vector -> PZ iso projection -> the
    -- ON-SCREEN line angle the skid mark actually has (see header note).
    local r  = math.rad(h)
    local wx = math.cos(r)
    local wy = math.sin(r)
    local sx = wx - wy
    local sy = (wx + wy) * 0.5
    local a  = (math.deg(math.atan2(sy, sx)) + HEADING_OFFSET_DEG) % 180.0
    if a < 0 then a = a + 180.0 end

    -- Bucket to the nearest authored screen angle. Targets are
    -- 0 (H), 26.565 (D1), 90 (V), 153.435 (D2); bin edges are the
    -- midpoints between adjacent targets (13.28 / 58.28 / 121.72 / 166.72).
    local t
    if     a < 13.283  then t = TYPE_H
    elseif a < 58.283  then t = (SWAP_D1_D2 and TYPE_D2 or TYPE_D1)
    elseif a < 121.717 then t = TYPE_V
    elseif a < 166.717 then t = (SWAP_D1_D2 and TYPE_D1 or TYPE_D2)
    else                    t = TYPE_H   -- wraps back toward 180==0
    end

    LAST_TYPE = t
    return t
end

-- Place ONE decal at a world point, resolving its own square/chunk (an
-- interpolated point may fall in a different chunk than the vehicle's),
-- with per-tile dedupe so a tile is only stamped once per DEDUPE_MS.
local function placeSplatAt(wx, wy, wz, t, now)
    local key = math.floor(wx) .. "," .. math.floor(wy) .. "," .. math.floor(wz)
    if recentTiles[key] and (now - recentTiles[key]) < DEDUPE_MS then return end
    recentTiles[key] = now
    local cell  = getCell and getCell()
    local sq    = cell and cell:getGridSquare(math.floor(wx), math.floor(wy), math.floor(wz))
    local chunk = sq and sq.getChunk and sq:getChunk()
    if chunk and chunk.addBloodSplat then
        chunk:addBloodSplat(wx, wy, wz, t)
    end
end

local function dropMark(v, sq)
    if not sq then return end

    -- Vehicle world coords (floats). addBloodSplat treats them as the
    -- splat's render anchor inside the resolved tile.
    local vx = v:getX() or sq:getX()
    local vy = v:getY() or sq:getY()
    local vz = v:getZ() or sq:getZ()
    local t  = typeForVehicle(v)
    local now = getTimestampMs and getTimestampMs() or 0

    if (now % 8000) < 50 then
        for k, ts in pairs(recentTiles) do
            if (now - ts) > DEDUPE_MS * 4 then recentTiles[k] = nil end
        end
        -- Drop heading state for vehicles untouched for a while so the
        -- table can't accrete stale per-id entries on long sessions.
        for k, p in pairs(lastPos) do
            if p.ts and (now - p.ts) > 60000 then lastPos[k] = nil end
        end
    end

    -- Connect to the previous drop in this streak: fill every ~half-tile
    -- between them so there are no gaps even at high speed. A fresh streak
    -- (lastDrop == nil) or a level change just stamps the current point.
    if lastDrop and lastDrop.z == vz then
        local dx, dy = vx - lastDrop.x, vy - lastDrop.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 0.0 and dist <= MAX_FILL_DIST then
            local steps = math.ceil(dist / STEP_TILES)
            for i = 1, steps do
                local f = i / steps
                placeSplatAt(lastDrop.x + dx * f, lastDrop.y + dy * f, vz, t, now)
            end
        else
            placeSplatAt(vx, vy, vz, t, now)
        end
    else
        placeSplatAt(vx, vy, vz, t, now)
    end

    lastDrop = { x = vx, y = vy, z = vz }
end

local function onPlayerUpdate(player)
    if not player or player:isDead() then lastDrop = nil return end
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if sv and sv.SkidMarks == false then lastDrop = nil return end
    local v = player:getVehicle()
    if not v or v:getDriver() ~= player then lastDrop = nil return end
    local now = getTimestampMs and getTimestampMs() or 0
    if now - LAST_TICK_MS < MIN_INTERVAL_MS then return end

    local speed = v:getCurrentSpeedKmHour() or 0
    if speed < 0 then speed = -speed end
    local gas, brake = v:isGasPedalPressed(), v:isBrakePedalPressed()
    local drifting  = BetterVehicleDynamicsMod
                       and BetterVehicleDynamicsMod.driftActive == true
                       and speed > 15
    local isBurnout = speed < BURNOUT_SPEED and gas
    local isSkid    = speed > SKID_SPEED    and brake
    if not (isBurnout or isSkid or drifting) then return end

    dropMark(v, v:getCurrentSquare())
    LAST_TICK_MS = now
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
print("[BVD.Skidmarks] tire-mark decal hook installed (4 orientations)")
