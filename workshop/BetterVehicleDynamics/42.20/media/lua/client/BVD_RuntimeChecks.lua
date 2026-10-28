-- BVD_RuntimeChecks.lua  (client)
--
-- Two per-tick observations on the local player's vehicle:
--   #3 stuck-but-revving diagnostic log - fires once per stuck event with
--      the multiplier stack (load%, surface, tyre family, current
--      engineForce). Data for triangulating "engine running but car
--      doesn't move" reports. NOT a fix - just a probe.
--   #4 tire wear from wheel slip - while the driver is stuck or burning out
--      (throttle down, almost no ground speed for a couple of seconds) the
--      driven tires lose condition. Lets the player brute-force grass at the
--      cost of bald tires later. An ordinary launch never counts.
--
-- Both share the same "driver + throttle + low speed" detection so they
-- live in one tick. Pure Lua; no Java install needed.
--
-- The client only COUNTS the slip. The wear itself is applied to the vehicle
-- part by the server (server/BVD_TireWearServer.lua): a part's condition is
-- what the mechanics window shows and what the grip model reads, it follows
-- the tire item, and the server is the only side that can send it to other
-- players. Changing the tire item here instead (what v0.1.2 - v0.1.17 did)
-- left the part untouched, so the damage showed nowhere until the wheel was
-- removed and came out broken.

BVD = BVD or {}

local STUCK_SPEED_KMH = 3.0       -- below this we consider the vehicle "not moving" (BVD.stuckSpeedKmh overrides it, for tests)
local STUCK_DWELL_S   = 2.0       -- consecutive seconds before we log once / start counting wear
local STUCK_COOLDOWN  = 30.0      -- seconds between stuck-event log lines
local WEAR_POINTS_PER_S = 0.5     -- condition points per second of slip, per driven tire, at rate 1.0

local _stuckStart = nil
local _lastStuckLogAt = -1e9
local _lastTickAt = nil
local _slip = { accum = 0 }

local function nowSec()
    if getTimestampMs then return getTimestampMs() / 1000.0 end
    return 0
end

local function readCfg()
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" then return c end
    end
    return nil
end

--- Whole condition points to ask for this tick. `state.accum` carries the
--- fraction between calls, `dt` is real seconds since the last call and
--- `stuckFor` how long the car has been stuck. Nothing counts until the car
--- has been stuck for STUCK_DWELL_S; the result does not depend on how often
--- it is called.
function BVD.slipWearPoints(state, dt, stuckFor, rate)
    if rate <= 0 or stuckFor < STUCK_DWELL_S then return 0 end
    state.accum = state.accum + dt * rate * WEAR_POINTS_PER_S
    local points = math.floor(state.accum)
    state.accum = state.accum - points
    return points
end

--- Ask the server to wear the driven tires of this vehicle by `points`
--- condition points. The server checks the sender is the driver, that the
--- option is on, and caps how much one request can do.
function BVD.requestTireWear(vehicle, points)
    local player = getPlayer and getPlayer() or nil
    if not (player and vehicle and sendClientCommand) then return end
    sendClientCommand(player, "BetterVehicleDynamics", "tireWear", {
        vehicle = vehicle:getId(),
        points = points,
    })
end

local function detectSurface(vehicle)
    -- Best-effort surface read; PZ exposes IsoChunk:getSquare:getFloor:getProperties().
    -- Cheap heuristic: ask the vehicle's own square for terrain type if available.
    local sq = vehicle.getSquare and vehicle:getSquare() or nil
    if not sq then return "unknown" end
    if sq.getFloor and sq:getFloor() then
        local f = sq:getFloor()
        local n = f.getName and f:getName() or nil
        if n then return tostring(n) end
    end
    return "unknown"
end

local function stuckSpeed()
    return tonumber(BVD.stuckSpeedKmh) or STUCK_SPEED_KMH
end

local function resetState()
    _stuckStart = nil
    _lastTickAt = nil
    _slip.accum = 0
end

local function onPlayerUpdate(player)
    if not player or not player.isLocalPlayer or not player:isLocalPlayer() then return end
    local vehicle = player.getVehicle and player:getVehicle() or nil
    if not vehicle then resetState() return end
    if vehicle.getDriver and vehicle:getDriver() ~= player then resetState() return end

    local cfg = readCfg()
    if not cfg then return end

    -- Real time, so the wear does not depend on the frame rate.
    local now = nowSec()
    local dt = _lastTickAt and (now - _lastTickAt) or 0
    _lastTickAt = now
    if dt < 0 or dt > 0.5 then dt = 0 end

    local speedKmh = math.abs(vehicle.getCurrentSpeedKmHour and vehicle:getCurrentSpeedKmHour() or 0)
    local gas = vehicle.isGasPedalPressed and vehicle:isGasPedalPressed() or false
    local engineRunning = vehicle.isEngineRunning and vehicle:isEngineRunning() or false

    -- ---- #3 stuck-but-revving diagnostic log ----
    if engineRunning and gas and speedKmh < stuckSpeed() then
        if _stuckStart == nil then _stuckStart = now end
        if (now - _stuckStart) >= STUCK_DWELL_S and (now - _lastStuckLogAt) >= STUCK_COOLDOWN then
            _lastStuckLogAt = now
            local bvd = BetterVehicleDynamicsMod or {}
            local computed = bvd.computed or {}
            local load = computed.ladenRatio or computed.loadPenalty or "?"
            local force = computed.engineForce or "?"
            local fam = computed.tireFamily or "?"
            local surf = detectSurface(vehicle)
            print(string.format(
                "[BVD-DIAG] stuck: speed=%.1fkmh load=%s force=%s tyre=%s surface=%s",
                speedKmh, tostring(load), tostring(force), tostring(fam), surf
            ))
        end
    else
        _stuckStart = nil
    end

    -- ---- #4 tire wear from wheel slip ----
    if cfg.TireSlipWear == true then
        local rate = tonumber(cfg.TireSlipWearRate) or 1.0
        if _stuckStart ~= nil then
            local points = BVD.slipWearPoints(_slip, dt, now - _stuckStart, rate)
            if points > 0 then BVD.requestTireWear(vehicle, points) end
        end
    else
        _slip.accum = 0
    end
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end

return {}
