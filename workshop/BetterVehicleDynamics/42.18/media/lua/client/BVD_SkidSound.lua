-- ===========================================================================
-- BVD_SkidSound.lua  (client; v0.1.3 - heartbeat-synced per-vehicle)
--
-- v0.1.2 and earlier started ONE sound on the driver's vehicle emitter and
-- relied on PZ's positional propagation. The bug: stopSound did not always
-- propagate, leaving the sound looping forever on remote clients. v0.1.3
-- refactors to a heartbeat model:
--   - Driver client computes skid intensity (existing math, unchanged).
--   - Driver sends "BVD-Skid" {Start, Tick, Stop} commands per-vehicle.
--   - Server relays (BVD_SkidSync_Server.lua) to all online clients.
--   - Every client (driver included) plays its OWN local sound on receipt
--     and stops it on a Stop command OR a watchdog timeout if heartbeats
--     stop arriving (defensive against driver disconnect mid-skid).
--
-- A per-vehicle (vid -> state) map replaces the single-active-sound globals
-- so multiple players can skid simultaneously.
-- ===========================================================================

local EVENT_NAME = "BVD_SkidLoop"
-- Clip length in ms. BVD_skid_loop.ogg is 2.0 s; script now declares
-- loop=false so each play is one short tile that expires naturally.
-- v0.1.4 left loop=true which caused N stacked permanent loops at each
-- re-arm world position. v0.1.5 fixes by switching to non-looping clip +
-- continuous re-arm.
local CLIP_MS    = 2000

-- Re-arm slightly before the clip ends so consecutive tiles butt
-- together without a perceptible gap or overlap.
local REFIRE_MS  = 1800

local START_AT      = 0.18
local STOP_AT       = 0.04
local MASTER_SCALE  = 0.95
local FADE_MS       = 600

local SLIDE_MIN_KPH = 14.0
local SLIDE_REF_KPH = 70.0
local BURNOUT_KPH   = 12.0

-- Heartbeat cadence (driver) and watchdog window (every client).
-- Watchdog must be wider than one clip so the last-fired clip can play
-- to completion if the driver disconnects mid-skid.
local TICK_SEND_MS  = 200
local WATCHDOG_MS   = 2200

-- ---------------------------------------------------------------------------
-- Probed caches (per session). Each branch is tested once; the verdict
-- sticks so we don't pay pcall cost every tick.
-- ---------------------------------------------------------------------------
local probedVolApi  = nil
local emitterMode   = nil     -- "vehicle" | "world" | "manager"

-- vid -> {
--   vehicle,        -- IsoVehicle reference (looked up on each command)
--   soundId,
--   heldEmitter,    -- "world" emitter handle when applicable
--   nextRefireMs,   -- manager fallback re-arm clock
--   lastTickMs,     -- last incoming heartbeat (for watchdog)
--   currentVol,
--   fading, fadeFromVol, fadeUntilMs,
-- }
local skids = {}

-- Driver-side state (tracks what we last broadcast for our own vehicle)
local lastDriverVid       = nil
local lastSentTickMs      = 0
local driverActive        = false

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function nowMs()
    return (getTimestampMs and getTimestampMs()) or 0
end

local function skidSoundEnabled()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    return not (sv and sv.SkidSound == false)
end

-- ---------------------------------------------------------------------------
-- intensity (unchanged from v0.1.2)
-- ---------------------------------------------------------------------------
local probedHandbrake = nil
local function vehicleHandbrakeOn(v)
    if probedHandbrake == false then return false end
    local ok, res = pcall(function()
        if v.getHandbrake then return v:getHandbrake() end
        return nil
    end)
    if ok and res ~= nil then
        probedHandbrake = true
        return res == true or (type(res) == "number" and res > 0.0)
    end
    if probedHandbrake == nil then probedHandbrake = false end
    return false
end

local function skidIntensity(v)
    local speed = v:getCurrentSpeedKmHour() or 0
    if speed < 0 then speed = -speed end
    local gas    = v:isGasPedalPressed() == true
    local brake  = v:isBrakePedalPressed() == true
    local hand   = vehicleHandbrakeOn(v)
    local drift  = BetterVehicleDynamicsMod
                   and BetterVehicleDynamicsMod.driftActive == true
    if speed < BURNOUT_KPH and gas and (brake or hand) then
        return clamp01(0.55 + 0.35 * (1.0 - speed / BURNOUT_KPH))
    end
    if speed < SLIDE_MIN_KPH then return 0.0 end
    local spd = clamp01((speed - SLIDE_MIN_KPH)
                        / (SLIDE_REF_KPH - SLIDE_MIN_KPH))
    local cause = 0.0
    if hand  then cause = cause + 0.85 end
    if drift then cause = cause + 0.70 end
    if brake then cause = cause + 0.55 end
    if cause <= 0.0 then return 0.0 end
    cause = clamp01(cause)
    return clamp01(0.25 + 0.75 * spd * cause)
end

-- ---------------------------------------------------------------------------
-- emitter resolution (unchanged - probes once)
-- ---------------------------------------------------------------------------
local function tryVehicleEmitter(v)
    local ok, id = pcall(function()
        local em = v.getEmitter and v:getEmitter()
        if not em or not em.playSound then return nil end
        return em:playSound(EVENT_NAME)
    end)
    if ok and id and id ~= 0 then return id end
    return nil
end

local function tryWorldEmitter(v)
    local ok, id, em = pcall(function()
        local w = getWorld and getWorld()
        if not w then return nil end
        local x, y, z = v:getX(), v:getY(), v:getZ()
        local e
        if w.getFreeEmitter then
            e = w:getFreeEmitter(x, y, z)
        elseif w.addEmitter then
            e = w:addEmitter(x, y, z)
        end
        if not e or not e.playSound then return nil end
        return e:playSound(EVENT_NAME), e
    end)
    if ok and id and id ~= 0 then return id, em end
    return nil
end

local function tryManagerWorldSound(v)
    local ok, id = pcall(function()
        local sm = getSoundManager and getSoundManager()
        local sq = v:getCurrentSquare()
        if not sm or not sq or not sm.PlayWorldSound then return nil end
        return sm:PlayWorldSound(EVENT_NAME, sq, false, 1.0, 1.0, true)
    end)
    if ok and id and id ~= 0 then return id end
    if ok then return -1 end
    return nil
end

local function setVehicleEmitterVolume(v, id, vol, mode, heldEmitter)
    if probedVolApi == false or id == nil or id == -1 then return end
    local ok = pcall(function()
        local em
        if mode == "world" then
            em = heldEmitter
        end
        if em and em.setVolume then
            em:setVolume(id, vol)
            return true
        end
        return false
    end)
    if ok and probedVolApi == nil then probedVolApi = true
    elseif (not ok) and probedVolApi == nil then probedVolApi = false end
end

local function repositionWorldEmitterFor(state, v)
    if emitterMode ~= "world" or not state.heldEmitter then return end
    pcall(function()
        if state.heldEmitter.setPos then
            state.heldEmitter:setPos(v:getX(), v:getY(), v:getZ())
        end
    end)
end

-- ---------------------------------------------------------------------------
-- vehicle lookup by id (cell-walk; called on each command)
-- ---------------------------------------------------------------------------
local function findVehicleByVid(vid)
    local cell = getCell and getCell()
    if not cell or not cell.getVehicles then return nil end
    local list = cell:getVehicles()
    if not list then return nil end
    if list.iterator then
        local it = list:iterator()
        while it and it.hasNext and it:hasNext() do
            local v = it.next and it:next() or nil
            if v and v.getKeyId and v:getKeyId() == vid then return v end
        end
        return nil
    end
    if list.size and list.get then
        for i = 0, list:size() - 1 do
            local v = list:get(i)
            if v and v.getKeyId and v:getKeyId() == vid then return v end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- start / stop / refresh for a single vid
-- ---------------------------------------------------------------------------
local function startSkidFor(vid, vehicle)
    if skids[vid] then return end                       -- already playing
    if not skidSoundEnabled() then return end
    local v = vehicle or findVehicleByVid(vid)
    if not v then return end

    -- IMPORTANT: do NOT use vehicle:getEmitter() in the heartbeat model.
    -- It propagates positionally to nearby clients, so each client's call
    -- would broadcast a fresh sound to others -> N^2 duplication. World /
    -- manager emitters are local to the calling client only, which is what
    -- we want now that every client owns its own copy via heartbeats.
    local id, em
    if emitterMode == nil then
        id, em = tryWorldEmitter(v)
        if id then emitterMode = "world" end
        if not id then
            id = tryManagerWorldSound(v)
            if id then emitterMode = "manager" end
        end
    elseif emitterMode == "world" then
        id, em = tryWorldEmitter(v)
    else
        id = tryManagerWorldSound(v)
    end
    if not id then return end

    skids[vid] = {
        vehicle      = v,
        soundId      = id,
        heldEmitter  = em,
        nextRefireMs = nowMs() + REFIRE_MS,
        lastTickMs   = nowMs(),
        currentVol   = 0,
        fading       = false,
        fadeFromVol  = 0,
        fadeUntilMs  = 0,
    }
end

local function stopSkidFor(vid)
    local s = skids[vid]
    if not s then return end
    pcall(function()
        if emitterMode == "world" then
            if s.heldEmitter then
                if s.soundId and s.heldEmitter.stopSound then
                    s.heldEmitter:stopSound(s.soundId)
                elseif s.heldEmitter.stopOrTriggerSound then
                    s.heldEmitter:stopOrTriggerSound(s.soundId)
                end
            end
        elseif emitterMode == "manager" then
            local sm = getSoundManager and getSoundManager()
            if sm and s.soundId and s.soundId ~= -1 and sm.StopSound then
                sm:StopSound(s.soundId)
            end
        end
    end)
    skids[vid] = nil
end

local function tickSkidFor(vid, intensity)
    local s = skids[vid]
    if not s then return end
    s.lastTickMs = nowMs()
    local v = s.vehicle
    if not v then return end

    -- fade tail
    if intensity <= STOP_AT then
        if not s.fading then
            s.fading      = true
            s.fadeFromVol = (s.currentVol > 0) and s.currentVol
                             or (clamp01(intensity) * MASTER_SCALE)
            s.fadeUntilMs = nowMs() + FADE_MS
        end
        local remain = s.fadeUntilMs - nowMs()
        if remain <= 0 then
            stopSkidFor(vid)
            return
        end
        local vol = s.fadeFromVol * (remain / FADE_MS)
        s.currentVol = vol
        setVehicleEmitterVolume(v, s.soundId, vol, emitterMode, s.heldEmitter)
        repositionWorldEmitterFor(s, v)
        return
    end

    s.fading = false
    local vol = clamp01(intensity) * MASTER_SCALE
    s.currentVol = vol
    setVehicleEmitterVolume(v, s.soundId, vol, emitterMode, s.heldEmitter)
    repositionWorldEmitterFor(s, v)

    -- Non-looping clip model (loop=false in BVD_Sounds.txt). Re-arm at
    -- REFIRE_MS to tile consecutive clips with no audible seam. Old
    -- instances expire on their own ~CLIP_MS after they started, so we
    -- do NOT call stopSound on the previous id - that was the v0.1.4
    -- bug where stop didn't work for manager-mode and zero-id sentinels.
    local t = nowMs()
    if t >= s.nextRefireMs then
        local id
        if emitterMode == "world" then
            local nid, nem = tryWorldEmitter(v)
            id = nid
            if nid and nem then s.heldEmitter = nem end
        else
            id = tryManagerWorldSound(v)
        end
        if id then s.soundId = id end
        s.nextRefireMs = t + REFIRE_MS
    end
end

-- ---------------------------------------------------------------------------
-- network event handlers
-- ---------------------------------------------------------------------------
local function onServerCommand(module, command, args)
    if module ~= "BVD-Skid" then return end
    if not args or not args.vid then return end
    if command == "Start" then
        startSkidFor(args.vid, nil)
    elseif command == "Tick" then
        local intensity = tonumber(args.intensity) or 0
        if not skids[args.vid] then startSkidFor(args.vid, nil) end
        tickSkidFor(args.vid, intensity)
    elseif command == "Stop" then
        stopSkidFor(args.vid)
    end
end

-- ---------------------------------------------------------------------------
-- driver-side detector: send Start / Tick / Stop
-- ---------------------------------------------------------------------------
local function onPlayerUpdate(player)
    -- watchdog: per-tick check, gc stale receivers regardless of role
    local t = nowMs()
    for vid, s in pairs(skids) do
        if (t - s.lastTickMs) > WATCHDOG_MS then
            stopSkidFor(vid)
        end
    end

    if not player or player:isDead() then
        if driverActive and lastDriverVid then
            pcall(sendClientCommand, "BVD-Skid", "Stop", { vid = lastDriverVid })
            driverActive = false; lastDriverVid = nil
        end
        return
    end
    if not skidSoundEnabled() then
        if driverActive and lastDriverVid then
            pcall(sendClientCommand, "BVD-Skid", "Stop", { vid = lastDriverVid })
            driverActive = false; lastDriverVid = nil
        end
        return
    end

    local v = player:getVehicle()
    if not v or (v.getDriver and v:getDriver()) ~= player then
        if driverActive and lastDriverVid then
            pcall(sendClientCommand, "BVD-Skid", "Stop", { vid = lastDriverVid })
            driverActive = false; lastDriverVid = nil
        end
        return
    end

    local vid = v.getKeyId and v:getKeyId() or nil
    if not vid then return end

    -- swapped vehicles under us: stop the old, fall through
    if driverActive and lastDriverVid and lastDriverVid ~= vid then
        pcall(sendClientCommand, "BVD-Skid", "Stop", { vid = lastDriverVid })
        driverActive = false
    end

    local intensity = skidIntensity(v)
    if not driverActive then
        if intensity >= START_AT then
            pcall(sendClientCommand, "BVD-Skid", "Start", { vid = vid })
            driverActive = true
            lastDriverVid = vid
            lastSentTickMs = 0   -- force immediate Tick after Start
        end
    else
        -- Throttle Tick sends so we don't spam the network
        if (t - lastSentTickMs) >= TICK_SEND_MS then
            pcall(sendClientCommand, "BVD-Skid", "Tick",
                  { vid = vid, intensity = intensity })
            lastSentTickMs = t
        end
        -- End: send Stop once the fade has run its course locally
        if intensity <= STOP_AT then
            -- Let the fade run on the local copy; remote clients also fade
            -- once their own intensity goes below STOP_AT via the Tick they
            -- just received. The actual Stop is sent when fade is done.
            local s = skids[vid]
            if s and not s.fading then
                -- mark for stop after FADE_MS via the next-tick logic below
            end
            -- Defensive: if our local skid record is gone (fade completed),
            -- send the Stop so remote receivers don't have to wait for
            -- their watchdog to time out.
            if not skids[vid] then
                pcall(sendClientCommand, "BVD-Skid", "Stop", { vid = vid })
                driverActive = false
                lastDriverVid = nil
            end
        end
    end
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end
if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end

-- Clean up on world unload / game stop.
local function onGameStop()
    for vid, _ in pairs(skids) do stopSkidFor(vid) end
    driverActive = false
    lastDriverVid = nil
end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onGameStop) end
if Events.OnGameStop   then Events.OnGameStop.Add(onGameStop)   end
