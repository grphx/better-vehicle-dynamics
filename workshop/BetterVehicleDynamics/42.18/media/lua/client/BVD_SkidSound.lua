-- ===========================================================================
-- BVD_SkidSound.lua
--
-- A sustained tyre-slide sound that HOLDS one looping instance for as long
-- as the driver is sliding, instead of re-triggering a one-shot. The clip
-- (media/sound/BVD_skid_loop.ogg) is authored to loop natively and the
-- script event BVD_SkidLoop carries loop=true, so the right approach is to
-- start exactly ONE instance on a positional emitter that travels with the
-- vehicle, ride its volume per tick, and stop it when the slide ends.
--
-- This module is intentionally independent of the skid-MARK decal code:
-- the visual marks and the audio are separate concerns and must not share
-- state. It reuses the SAME sandbox switch the decals read so a player who
-- turns the feature off gets neither marks nor sound.
--
-- Java getters that may or may not exist on this exact build are probed
-- ONCE and the verdict cached (Kahlua re-logs every caught Java exception,
-- so call-and-hope every tick would spam the log and cost frames).
-- ===========================================================================

local EVENT_NAME = "BVD_SkidLoop"

-- Clip length in ms (gen_skid_loop.py emits exactly 2.0 s). Used only by
-- the world-sound fallback to re-arm a fresh instance the instant the old
-- one ends, so the tiles butt together with no gap and no overlap.
local CLIP_MS = 2000

-- Intensity gating.
local START_AT      = 0.18   -- rise above this (and silent) -> start
local STOP_AT       = 0.04   -- fall to/below this -> stop
local MASTER_SCALE  = 0.95   -- overall ceiling applied to per-tick volume

-- Speeds that shape the intensity curve (km/h).
local SLIDE_MIN_KPH = 14.0   -- below this, no meaningful slide noise
local SLIDE_REF_KPH = 70.0   -- speed at which the speed term saturates
local BURNOUT_KPH   = 12.0   -- standing-burnout band (low speed + throttle)

-- Per-session probe/cache state.
local probedVolApi  = nil    -- true once setVolume(id,vol) is known usable
local emitterMode   = nil    -- "vehicle" | "world" | "manager" once resolved
local announced     = false  -- one-shot "[BVD-SND] path ..." print done

-- Live playback state (only ever ONE instance held).
local active        = false
local soundId       = nil
local heldVehicle   = nil
local heldEmitter   = nil    -- for the world-emitter path: keep & reposition
local nextRefireMs  = 0      -- world-sound fallback re-arm clock

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function nowMs()
    return (getTimestampMs and getTimestampMs()) or 0
end

-- ---------------------------------------------------------------------------
-- Intensity: 0 (no slide) .. 1 (full slide). This deliberately does NOT try
-- to reconstruct engine-physics slip; it just has to track "the player is
-- sliding" robustly. Speed sets the ceiling; hard braking, the handbrake,
-- arcade drift, and a standing burnout each open that ceiling up.
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

    -- Standing burnout: barely moving, throttle pinned -> tyres spin.
    if speed < BURNOUT_KPH and gas and not brake then
        -- Stronger the closer to a dead stop (max scrub at 0 km/h).
        return clamp01(0.55 + 0.35 * (1.0 - speed / BURNOUT_KPH))
    end

    if speed < SLIDE_MIN_KPH then return 0.0 end

    -- Speed term: 0 at SLIDE_MIN_KPH, ~1 by SLIDE_REF_KPH.
    local spd = clamp01((speed - SLIDE_MIN_KPH)
                        / (SLIDE_REF_KPH - SLIDE_MIN_KPH))

    local cause = 0.0
    if hand  then cause = cause + 0.85 end   -- handbrake = strongest cue
    if drift then cause = cause + 0.70 end
    if brake then cause = cause + 0.55 end    -- hard braking -> lock-up scrub
    if cause <= 0.0 then return 0.0 end
    cause = clamp01(cause)

    -- Slide noise grows with how fast you are AND how hard you provoke it.
    return clamp01(0.25 + 0.75 * spd * cause)
end

-- ---------------------------------------------------------------------------
-- Emitter resolution. The first approach that actually returns a usable
-- sound id wins and is cached in emitterMode; subsequent ticks take that
-- branch directly. Every uncertain Java call is pcall-guarded.
--   "vehicle" : vehicle:getEmitter():playSound(EVENT) -- positional, rides
--               with the vehicle for free (preferred).
--   "world"   : getWorld():getFreeEmitter(x,y,z):playSound(EVENT) -- we
--               must reposition this emitter ourselves each tick.
--   "manager" : getSoundManager():PlayWorldSound(EVENT, square, ...) --
--               proven to emit audibly; no sustained handle, so it is
--               re-armed exactly every CLIP_MS to tile the loop.
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
        -- (event, square, loopOverride, volume, radius, fade)
        return sm:PlayWorldSound(EVENT_NAME, sq, false, 1.0, 1.0, true)
    end)
    if ok and id and id ~= 0 then return id end
    -- Some builds return 0/nil but still emit; treat the call succeeding
    -- as "this path works" and let the re-arm clock drive it.
    if ok then return -1 end
    return nil
end

local function setEmitterVolume(v, id, vol)
    if probedVolApi == false or id == nil or id == -1 then return end
    local ok = pcall(function()
        local em
        if emitterMode == "vehicle" then
            em = v.getEmitter and v:getEmitter()
        elseif emitterMode == "world" then
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

local function repositionWorldEmitter(v)
    if emitterMode ~= "world" or not heldEmitter then return end
    pcall(function()
        if heldEmitter.setPos then
            heldEmitter:setPos(v:getX(), v:getY(), v:getZ())
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Start / stop. Exactly one instance is ever live; start/stop are one-shot
-- logged so a single test run is conclusive.
-- ---------------------------------------------------------------------------
local function startSkid(v)
    local id, em

    if emitterMode == nil then
        id = tryVehicleEmitter(v)
        if id then emitterMode = "vehicle" end
        if not id then
            id, em = tryWorldEmitter(v)
            if id then emitterMode = "world"; heldEmitter = em end
        end
        if not id then
            id = tryManagerWorldSound(v)
            if id then emitterMode = "manager" end
        end
        if id and not announced then
            announced = true
            print(string.format(
                "[BVD-SND] emitter path resolved: %s (sound id %s)",
                tostring(emitterMode), tostring(id)))
        end
    elseif emitterMode == "vehicle" then
        id = tryVehicleEmitter(v)
    elseif emitterMode == "world" then
        id, em = tryWorldEmitter(v)
        heldEmitter = em
    else -- "manager"
        id = tryManagerWorldSound(v)
    end

    if not id then return false end
    soundId      = id
    heldVehicle  = v
    active       = true
    nextRefireMs = nowMs() + CLIP_MS
    print("[BVD-SND] skid loop START")
    return true
end

local function stopSkid()
    if not active then return end
    local v = heldVehicle
    pcall(function()
        if emitterMode == "vehicle" then
            local em = v and v.getEmitter and v:getEmitter()
            if em then
                if soundId and em.stopSound then em:stopSound(soundId)
                elseif em.stopAll then em:stopAll() end
            end
        elseif emitterMode == "world" then
            if heldEmitter then
                if soundId and heldEmitter.stopSound then
                    heldEmitter:stopSound(soundId)
                elseif heldEmitter.stopOrTriggerSound then
                    heldEmitter:stopOrTriggerSound(soundId)
                end
            end
        elseif emitterMode == "manager" then
            local sm = getSoundManager and getSoundManager()
            if sm and soundId and soundId ~= -1 and sm.StopSound then
                sm:StopSound(soundId)
            end
        end
    end)
    active       = false
    soundId      = nil
    heldVehicle  = nil
    heldEmitter  = nil
    nextRefireMs = 0
    print("[BVD-SND] skid loop STOP")
end

-- ---------------------------------------------------------------------------
-- Per-tick driver.
-- ---------------------------------------------------------------------------
local function onPlayerUpdate(player)
    if not player or player:isDead() then
        if active then stopSkid() end
        return
    end

    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if sv and sv.SkidMarks == false then
        if active then stopSkid() end
        return
    end

    local v = player:getVehicle()
    if not v or v:getDriver() ~= player then
        if active then stopSkid() end
        return
    end

    -- Vehicle swapped under us (entered a different car without an
    -- intervening !driver tick) -> drop the old instance cleanly.
    if active and heldVehicle and heldVehicle ~= v then
        stopSkid()
    end

    local intensity = skidIntensity(v)

    if active then
        if intensity <= STOP_AT then
            stopSkid()
            return
        end
        local vol = clamp01(intensity) * MASTER_SCALE
        setEmitterVolume(v, soundId, vol)
        repositionWorldEmitter(v)

        -- World-sound fallback has no sustained handle: re-arm a fresh
        -- instance exactly when the previous clip ends so the loop tiles
        -- seamlessly (re-firing EARLY was the old "weird" stutter bug).
        if emitterMode == "manager" then
            local t = nowMs()
            if t >= nextRefireMs then
                local id = tryManagerWorldSound(v)
                if id then soundId = id end
                nextRefireMs = t + CLIP_MS
            end
        end
    else
        if intensity >= START_AT then
            startSkid(v)
        end
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)

-- Make sure nothing is left ringing on world unload / game stop.
local function onGameStop()
    if active then stopSkid() end
end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onGameStop) end
if Events.OnGameStop   then Events.OnGameStop.Add(onGameStop)   end

print("[BVD.SkidSound] persistent-emitter skid loop installed")
