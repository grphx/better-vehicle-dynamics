-- In-game checks for Better Vehicle Dynamics' ZombieBuddy layer.
-- sp / mpA: spawn a car, prove BVD's Java (not vanilla) drives it, drive, steer, brake.
-- mpB: watch A's car move on the other client.
require "PZAutotest/Runner"

local T = PZAutotest
local SPOT = { x = 10586, y = 11180 }
local SCRIPT = "Base.CarNormal"

local function carNear(x, y, r)
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        if math.abs(v:getX() - x) < r and math.abs(v:getY() - y) < r then return v end
    end
end

local function spawnCar(p)
    local x, y = math.floor(p:getX()) + 4, math.floor(p:getY())
    if isClient() then
        sendClientCommand(p, "BVDTests", "spawn", { script = SCRIPT, x = x, y = y })
    else
        addVehicleDebug(SCRIPT, IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
    end
    return T.waitFor(function() return carNear(x, y, 3) end, 10)
end

local function driveBody(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true)
    p:setGhostMode(true)

    T.check("ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true,
        "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
    T.check("tyre-mark texture helper exposed", type(BVD_registerSharedTexture) == "function")

    T.clearCars(p, 40)
    local v = spawnCar(p)
    if not T.check("car spawned", v ~= nil) then return end
    T.check("BVD Java reports itself", BetterVehicleDynamicsMod.javaVersion == "3.4",
        tostring(BetterVehicleDynamicsMod.javaVersion))

    ISVehicleMenu.onEnter(p, v, 0)
    if not T.check("entered driver seat", T.waitFor(function() return p:getVehicle() == v end, 25) ~= nil) then return end
    v:tryStartEngine(true)
    T.check("engine starts", T.waitFor(function() return v:isEngineRunning() end, 10) ~= nil)
    T.wait(1)

    local z0 = v:getZ()
    local x0, y0 = v:getX(), v:getY()
    BetterVehicleDynamicsMod.computed = nil
    T.drive(true, true, 0)
    local top, tEnd = 0, getTimestampMs() + 15000
    while getTimestampMs() < tEnd do
        top = math.max(top, math.abs(v:getCurrentSpeedKmHour()))
        coroutine.yield()
    end
    local moved = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    T.check("car accelerates", top > 25, string.format("top %.1f km/h, moved %.1f tiles", top, moved))
    local c = BetterVehicleDynamicsMod.computed
    -- Only BVD's drivetrain publishes this readout; vanilla never does.
    T.check("BVD drivetrain drives the car", type(c) == "table" and type(c.gripRoad) == "number",
        c and string.format("gripRoad %s tire %s laden %s", tostring(c.gripRoad), tostring(c.tireFamily), tostring(c.ladenRatio)) or "no computed table")

    T.drive(true, true, 1)
    T.wait(1)
    local steer = v:getController():getVehicleSteering()
    T.check("steering responds", math.abs(steer) > 0.05, string.format("steering %.3f", steer))
    T.check("vanilla getters see BVD pedal state", v:getController():isGasPedalPressed() == true)

    T.drive(false, false, 0)
    p:getVehicle():getController().clientControls.brake = true
    local stopped = T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
    T.check("car brakes to a stop", stopped ~= nil, string.format("speed %.1f", v:getCurrentSpeedKmHour()))
    T.check("car did not sink", math.abs(v:getZ() - z0) < 0.5, string.format("z %.2f -> %.2f", z0, v:getZ()))
    ISVehicleMenu.onExit(p)
    T.waitFor(function() return p:getVehicle() == nil end, 10)
    T.log(string.format("drive done at %.0f,%.0f", v:getX(), v:getY()))
end

-- B: A's car must visibly move on this client too.
local function watchBody(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true)
    p:setGhostMode(true)
    T.check("ZombieBuddy layer active on B", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    local v = T.waitFor(function()
        local c = carNear(p:getX(), p:getY(), 30)
        return c and c:getDriver() ~= nil and c or nil
    end, 180)
    if not T.check("B sees A's car with a driver", v ~= nil) then return end
    local x0, y0 = v:getX(), v:getY()
    T.wait(8)
    local moved = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    T.check("B sees A's car move", moved > 5, string.format("moved %.1f tiles", moved))
    T.check("BVD readout stays local to the driver", BetterVehicleDynamicsMod.computed == nil)
end

T.register("sp", driveBody, { startLoc = { x = SPOT.x, y = SPOT.y, z = 0 } })
T.register("mpA", driveBody)
T.register("mpB", watchBody)
