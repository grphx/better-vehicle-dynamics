-- Helpers shared by the bvd_drive_*.lua scenarios (pasted in with `--#include _lib/common.lua`).
-- Only function definitions and constants here: no game calls at load. Driving needs ZomboTest's Java helper
-- (zombiebuddy = true in the config): S.drive / S.reverse / S.shift.

local ROAD = { x = 10586, y = 11180 }
local TIRES = { "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }

-- Make a debug-spawned car drivable: debug spawns come in random condition (dead battery, empty tank, locked doors).
local function fixCar(v)
    v:repair()
    local tank = v:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(tank:getContainerCapacity())
        v:transmitPartModData(tank)
    end
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        local door = part:getDoor()
        if door and door:isLocked() then
            door:setLocked(false)
            v:transmitPartDoor(part)
        end
    end
    local bat = v:getPartById("Battery")
    if bat and bat:getInventoryItem() then
        bat:getInventoryItem():setUsedDelta(1.0)
        v:transmitPartUsedDelta(bat)
    end
end

-- Fit a full set of good tires the way the game's own install does it (a debug spawn can come without tires, or with
-- flat ones that explode above 10 km/h): item, condition, air, physics flag and wheel model.
local function fitTires(v)
    for _, id in ipairs(TIRES) do
        local part = v:getPartById(id)
        if part then
            local item = instanceItem("Base.NormalTire2")
            item:setCondition(100)
            part:setInventoryItem(item)
            part:setCondition(100)
            local cap = 0
            pcall(function() cap = part:getContainerCapacity() end)
            if cap > 0 then pcall(function() part:setContainerContentAmount(cap, false, true) end) end
            pcall(function() part:setModelVisible("InflatedTirePlusWheel", true) end)
            v:transmitPartItem(part)
            v:setTireRemoved(part:getWheelIndex(), false)
        end
    end
    pcall(function() v:updatePartStats() end)
end

local function setOpt(name, value)
    SandboxVars.BetterVehicleDynamics[name] = value
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
end

local function layerOn()
    return type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true
end

-- wait for BVD's per-tick readout (only BVD's own drivetrain publishes it; vanilla never does)
local function readout(S, sec)
    local mod = BetterVehicleDynamicsMod
    mod.computed = nil
    return S.waitFor(function()
        local c = mod.computed
        if type(c) == "table" and type(c.gripRoad) == "number" then return c end
        return nil
    end, sec or 10)
end

local function floorName(sq)
    local f = sq and sq:getFloor()
    return f and f:getSpriteName() or ""
end

-- a start square with `line` free tiles of the same surface (sprite name prefix) to its north; strict: the floor is
-- the only object on every square (no vegetation that slows vehicles)
local function findLine(prefix, cx, cy, strict, line)
    for dy = -90, 90, 3 do
        for dx = -90, 90, 3 do
            local x, y = cx + dx, cy + dy
            local ok = true
            for k = 0, line, 2 do
                local sq = getCell():getGridSquare(x, y - k, 0)
                if not sq or not sq:isFree(false) or floorName(sq):find(prefix, 1, true) ~= 1 then ok = false break end
                if strict and sq:getObjects():size() > 1 then ok = false break end
            end
            if ok then return x, y end
        end
    end
end

-- a long straight street near the start: its first square, or nil
local function roadStart()
    local x, y = findLine("blends_street", ROAD.x, ROAD.y, true, 90)
    if not x then x, y = findLine("blends_street", ROAD.x, ROAD.y, true, 60) end
    return x, y
end

local function seat(S, p, v)
    v:enter(0, p)
    v:setCharacterPosition(p, 0, "inside")
    v:transmitCharacterPosition(0, "inside")
    v:playPassengerAnim(0, "idle")
    triggerEvent("OnEnterVehicle", p)
    return S.waitFor(function() return p:getVehicle() == v or nil end, 6) ~= nil
end

local function dropCar(S, p, v)
    if p:getVehicle() ~= nil then
        ISVehicleMenu.onExit(p)
        S.waitFor(function() return p:getVehicle() == nil or nil end, 10)
    end
    ISTimedActionQueue.clear(p)   -- a finished exit action must not stop() against a removed car
    S.wait(0.4)
    v:permanentlyRemove()
    S.wait(1)
end

-- peak |speed| and the last |speed| over `sec` seconds; `each(v)` is called every tick
local function watch(S, v, sec, each)
    local peak = 0
    S.waitFor(function()
        local s = math.abs(v:getCurrentSpeedKmHour())
        if s > peak then peak = s end
        if each then each(v) end
        return nil
    end, sec)
    return peak, math.abs(v:getCurrentSpeedKmHour())
end

-- the back key (BVD's brake while rolling forward) until the car is still, then let go of every key
local function stopCar(S, v)
    S.reverse(true, 0)
    S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 15)
    S.drive(false)
    S.wait(0.5)
end

-- Spawn Base.CarNormal 4 tiles from the player (facing dir, default east), fix it, fit tires, seat the player, start
-- the engine. Returns the car, or nil and the step that failed; a car whose engine did not start comes back with "engine".
local function newCar(S, p, script, dir)
    local x, y = math.floor(p:getX()) + 4, math.floor(p:getY())
    local v
    for _ = 1, 6 do
        v = addVehicleDebug(script or "Base.CarNormal", dir or IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
        if v then break end
        S.wait(1.5)
    end
    if not v then return nil, "spawn" end
    S.wait(1.5)
    fixCar(v)
    fitTires(v)
    S.wait(0.5)
    if not seat(S, p, v) then v:permanentlyRemove() return nil, "seat" end
    v:tryStartEngine(true)
    if not S.waitFor(function() return v:isEngineRunning() or nil end, 10) then return v, "engine" end
    S.wait(1)
    v:setPhysicsActive(true, true)
    S.wait(0.5)
    return v
end

-- A fresh car at the start of the street, handed to fn(v) once it has proven it gets going under the held throttle
-- (a debug-spawned car now and then never gets going, with BVD out of the mod list too; the old harness retried, so
-- does this, up to 4 times). Leaves the car removed. Returns true when fn ran.
local function withCar(S, p, rx, ry, fn)
    for attempt = 1, 4 do
        S.teleport(rx + 0.5, ry + 3.5, 0)
        S.wait(3)
        local v
        for _ = 1, 6 do
            v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
            if v then break end
            S.wait(1.5)
        end
        if not v then return false end
        S.wait(1.5)
        fixCar(v)
        fitTires(v)
        S.wait(0.5)
        if not seat(S, p, v) then v:permanentlyRemove() return false end
        v:tryStartEngine(true)
        S.waitFor(function() return v:isEngineRunning() or nil end, 8)
        S.wait(1)
        v:setPhysicsActive(true, true)
        S.wait(0.5)
        BetterVehicleDynamicsMod.manualShift = false
        S.drive(true, true, 0)
        local peak = watch(S, v, 2.5)
        stopCar(S, v)
        local moved = peak > 8
        if moved then fn(v) end
        S.drive(false)
        dropCar(S, p, v)
        if moved then return true end
        S.observe("the car did not get going (spawn quirk), attempt " .. attempt)
    end
    return false
end
