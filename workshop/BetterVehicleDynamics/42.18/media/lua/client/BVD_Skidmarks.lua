local MIN_INTERVAL_MS = 380
local DEDUPE_MS       = 1500
local BURNOUT_SPEED   = 10
local SKID_SPEED      = 30

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

-- ---------------------------------------------------------------------------
-- Custom skid-squeal layer (probe).
--
-- We deliberately do NOT drive this from the Necroid Java side: the
-- emitter/playSoundImpl route was found unreliable for shipping a custom
-- file-clip on this build. Instead we try the Lua world-sound route
-- (getSoundManager():PlayWorldSound) here. This is an experiment -- if it
-- proves silent in-game the whole layer no-ops and we revisit.
--
-- SOUND_STATE: nil  = not probed yet
--              false = probed, API unusable -> permanent silent no-op
--              a function(square) = the cached caller that worked
local SOUND_NAME       = "BVD_Skid"
-- TIED TO THE CLIP: tools/gen_skid_audio.py emits a ~2000 ms loop-seamless
-- clip whose last 200 ms is an equal-power crossfade back into its head.
-- Re-trigger exactly as that crossfade tail begins (2000 - 200 = 1800) so a
-- sustained slide is one continuous squeal with no overlap and no gap. If the
-- script's DUR_S/XFADE_S change, set this to (clip_ms - XFADE_ms) to match.
local SOUND_COOLDOWN_MS = 1800
local SOUND_STATE      = nil
local lastSoundMs      = 0

-- PlayWorldSound has several B42 overloads and Kahlua red-logs every caught
-- Java exception, so we must NOT call-and-hope each tick. On first real use
-- we probe a small set of plausible signatures ONCE, against a live square,
-- keep the first that returns a usable (non-nil, non-zero) handle, and cache
-- that exact caller. Everything is wrapped in pcall; a total miss caches
-- `false` and we never touch the API again this session.
--
-- Signatures attempted (sm = getSoundManager(), sq = an IsoGridSquare):
--   A) sm:PlayWorldSound(name, sq, volMod, maxRadius, pitch, music)
--        floats; music=false. The common 6-arg world form.
--   B) sm:PlayWorldSound(name, sq, false, 0.0, 1.0, false)
--        same arity, the "flag/zeroed" variant some builds expect.
-- volMod ~1.0, maxRadius small (ground sound, ~a dozen tiles), pitch 1.0.
local SOUND_CANDIDATES = {
    function(sm, sq)
        return sm:PlayWorldSound(SOUND_NAME, sq, 1.0, 12.0, 1.0, false)
    end,
    function(sm, sq)
        return sm:PlayWorldSound(SOUND_NAME, sq, false, 0.0, 1.0, false)
    end,
}

local function soundUsable()
    return type(SOUND_STATE) == "function"
end

-- A handle is "usable" if the call returned something truthy that is not
-- the numeric 0 some overloads hand back on a no-op.
local function handleOk(h)
    if h == nil or h == false then return false end
    if type(h) == "number" and h == 0 then return false end
    return true
end

-- Resolve + cache the working caller. `sq` must be a real square so the
-- probe actually exercises the engine path (a nil square would let a
-- broken overload "succeed" trivially). Runs at most once per session;
-- after it, SOUND_STATE is either a cached caller fn or `false`.
local function probeSound(sq)
    if SOUND_STATE ~= nil then return end          -- already decided
    if not sq then return end                      -- wait for a real square
    local okMgr, sm = pcall(getSoundManager)
    if not okMgr or not sm or not sm.PlayWorldSound then
        SOUND_STATE = false
        print("[BVD.Skidmarks] world-sound API unavailable; custom skid muted")
        return
    end
    for i = 1, #SOUND_CANDIDATES do
        local cand = SOUND_CANDIDATES[i]
        local ok, handle = pcall(cand, sm, sq)
        if ok and handleOk(handle) then
            SOUND_STATE = cand
            print("[BVD.Skidmarks] custom skid sound active (PlayWorldSound sig #" .. i .. ")")
            return
        end
    end
    SOUND_STATE = false
    print("[BVD.Skidmarks] PlayWorldSound produced no handle; custom skid muted")
end

-- Fire the cached caller if (and only if) the cooldown has elapsed. Kept
-- pcall-wrapped: even a previously-good signature can throw on an odd
-- square, and we never want skid audio to spam the log mid-drive.
local function playSkidSound(v, player)
    if not soundUsable() then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if now - lastSoundMs < SOUND_COOLDOWN_MS then return end
    local sq = (v.getCurrentSquare and v:getCurrentSquare())
            or (player and player:getCurrentSquare())
    if not sq then return end
    local sm = getSoundManager()
    if not sm then return end
    local ok = pcall(SOUND_STATE, sm, sq)
    if ok then lastSoundMs = now end
end

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

local function dropMark(v, sq)
    if not sq then return end
    local chunk = sq.getChunk and sq:getChunk()
    if not chunk or not chunk.addBloodSplat then return end

    -- Vehicle world coords (floats). chunk:addBloodSplat treats them as
    -- the splat's render anchor inside the resolved tile.
    local vx = v:getX() or sq:getX()
    local vy = v:getY() or sq:getY()
    local vz = v:getZ() or sq:getZ()

    local key = math.floor(vx) .. "," .. math.floor(vy) .. "," .. math.floor(vz)
    local now = getTimestampMs and getTimestampMs() or 0
    if recentTiles[key] and (now - recentTiles[key]) < DEDUPE_MS then return end
    recentTiles[key] = now

    if (now % 8000) < 50 then
        for k, t in pairs(recentTiles) do
            if (now - t) > DEDUPE_MS * 4 then recentTiles[k] = nil end
        end
        -- Drop heading state for vehicles untouched for a while so the
        -- table can't accrete stale per-id entries on long sessions.
        for k, p in pairs(lastPos) do
            if p.ts and (now - p.ts) > 60000 then lastPos[k] = nil end
        end
    end

    chunk:addBloodSplat(vx, vy, vz, typeForVehicle(v))
end

local function onPlayerUpdate(player)
    if not player or player:isDead() then return end
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if sv and sv.SkidMarks == false then return end
    local v = player:getVehicle()
    if not v or v:getDriver() ~= player then return end
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

    -- Custom squeal layer. Same enable gate as the marks (no dedicated
    -- sound sandbox option exists, so reuse SkidMarks); probe once on the
    -- first real skidding square, then fire on cooldown while still
    -- skidding. Accepted for this probe: this may briefly overlap the
    -- vanilla Java skid loop during genuine wheel-slip -- layering/dedupe
    -- is a follow-up only if PlayWorldSound is confirmed audible.
    if SOUND_STATE == nil then
        probeSound((v.getCurrentSquare and v:getCurrentSquare())
                   or player:getCurrentSquare())
    end
    playSkidSound(v, player)
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
print("[BVD.Skidmarks] tire-mark decal hook installed (4 orientations)")
