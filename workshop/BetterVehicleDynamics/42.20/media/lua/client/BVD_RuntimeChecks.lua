-- BVD_RuntimeChecks.lua  (client; v0.1.2)
--
-- Two per-tick observations on the local player's vehicle:
--   #3 stuck-but-revving diagnostic log - fires once per stuck event with
--      the multiplier stack (load%, surface, tyre family, current
--      engineForce). Data for triangulating "engine running but car
--      doesn't move" reports. NOT a fix - just a probe.
--   #4 tire-slip wear - when the engine is pushing harder than the surface
--      can grip (high throttle + low ground speed), decrement driven-tire
--      condition over time. Lets the player brute-force grass at the cost
--      of bald tires later.
--
-- Both share the same "driver + throttle + low speed" detection so they
-- live in one tick. Pure Lua; no Java install needed.

BVD = BVD or {}

local STUCK_SPEED_KMH = 3.0       -- below this we consider the vehicle "not moving"
local STUCK_DWELL_S   = 2.0       -- consecutive seconds before we log once
local STUCK_COOLDOWN  = 30.0      -- seconds between stuck-event log lines
local SLIP_SPEED_KMH  = 8.0       -- below this and on throttle = slip likely
local WEAR_PER_TICK   = 0.0010    -- per OnPlayerUpdate tick (~30 Hz), at rate=1.0

local _stuckStart = nil
local _lastStuckLogAt = -1e9

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

-- Walks vehicle tires safely and yields each tire item (the InventoryItem
-- that has setCondition / getCondition). Tries common B42 part names.
local function eachDrivenTire(vehicle, fn)
    local names = {
        "TireFrontLeft", "TireFrontRight",
        "TireRearLeft", "TireRearRight",
    }
    for i = 1, #names do
        local part = vehicle.getPartById and vehicle:getPartById(names[i])
        if part and part.getInventoryItem then
            local tire = part:getInventoryItem()
            if tire and tire.getCondition and tire.setCondition then
                fn(tire, names[i])
            end
        end
    end
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

local function onPlayerUpdate(player)
    if not player or not player.isLocalPlayer or not player:isLocalPlayer() then return end
    local vehicle = player.getVehicle and player:getVehicle() or nil
    if not vehicle then return end
    if vehicle.getDriver and vehicle:getDriver() ~= player then return end

    local cfg = readCfg()
    if not cfg then return end

    local speedKmh = math.abs(vehicle.getCurrentSpeedKmHour and vehicle:getCurrentSpeedKmHour() or 0)
    local gas = vehicle.isGasPedalPressed and vehicle:isGasPedalPressed() or false
    local engineRunning = vehicle.isEngineRunning and vehicle:isEngineRunning() or false

    -- ---- #3 stuck-but-revving diagnostic log ----
    if engineRunning and gas and speedKmh < STUCK_SPEED_KMH then
        local now = nowSec()
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

    -- ---- #4 tire-slip wear ----
    if cfg.TireSlipWear ~= false then
        local rate = tonumber(cfg.TireSlipWearRate) or 1.0
        if rate > 0 and engineRunning and gas and speedKmh < SLIP_SPEED_KMH then
            -- Slip condition: throttle pressed, engine running, car barely moving.
            -- Each tick decrements driven-tire condition slightly.
            local decrement = WEAR_PER_TICK * rate
            -- B42 tire condition is 0..100; setCondition clamps. Be defensive.
            local function applyWear(tire)
                local c = tire:getCondition()
                if type(c) ~= "number" then return end
                local newC = c - (decrement * 100.0)
                if newC < 0 then newC = 0 end
                if newC ~= c then
                    pcall(function() tire:setCondition(newC) end)
                end
            end
            pcall(function() eachDrivenTire(vehicle, applyWear) end)
        end
    end
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end

return {}
