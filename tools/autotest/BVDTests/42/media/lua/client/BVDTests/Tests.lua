-- In-game checks for Better Vehicle Dynamics' ZombieBuddy layer.
-- sp / mpA: spawn a car, prove BVD's Java (not vanilla) drives it, drive, steer, brake.
-- mpB: watch A's car move on the other client.
require "PZAutotest/Runner"
require "BVDTests/Fix"

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
        local v = addVehicleDebug(SCRIPT, IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
        if v then BVDTestsFix(v) end
    end
    return T.waitFor(function() return carNear(x, y, 3) end, 10)
end

local function driveBody(T)
    T.wait(4)
    local info = getModInfoByID("BetterVehicleDynamics")
    T.log("BVD loaded from " .. tostring(info and info:getDir()))
    local p = getPlayer()
    p:setGodMod(true)
    p:setGhostMode(true)

    T.check("ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true,
        "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
    T.check("tyre-mark texture helper exposed", type(BVD_registerSharedTexture) == "function")
    if isClient() then
        -- give client B time to join so it can watch this car move
        local both = T.waitFor(function() local ps = getOnlinePlayers(); return ps and ps:size() >= 2 or nil end, 300)
        T.log("players online: " .. tostring(both and getOnlinePlayers():size()))
    end

    T.clearCars(p, 120)
    local v = spawnCar(p)
    if not T.check("car spawned", v ~= nil) then return end
    T.check("BVD Java reports itself", BetterVehicleDynamicsMod.javaVersion == "3.4",
        tostring(BetterVehicleDynamicsMod.javaVersion))

    -- the walk-to-door path sometimes gives up next to a fresh spawn; then seat
    -- the player the way ISEnterVehicle does (start + perform)
    ISVehicleMenu.onEnter(p, v, 0)
    local inCar = T.waitFor(function() return p:getVehicle() == v end, 15)
    if not inCar then
        T.log(string.format("walk-up stalled (player %.1f,%.1f car %.1f,%.1f); seating directly", p:getX(), p:getY(), v:getX(), v:getY()))
        ISTimedActionQueue.clear(p)
        v:enter(0, p)
        v:setCharacterPosition(p, 0, "inside")
        v:transmitCharacterPosition(0, "inside")
        v:playPassengerAnim(0, "idle")
        triggerEvent("OnEnterVehicle", p)
        inCar = T.waitFor(function() return p:getVehicle() == v end, 5)
    end
    if not T.check("entered driver seat", inCar ~= nil) then return end
    -- engine state is the server's in MP (vanilla sends the same command)
    if isClient() then
        sendClientCommand(p, "vehicle", "startEngine", { haveKey = true })
    else
        v:tryStartEngine(true)
    end
    T.check("engine starts", T.waitFor(function() return v:isEngineRunning() end, 10) ~= nil)
    T.wait(1)

    local z0 = v:getZ()
    local x0, y0 = v:getX(), v:getY()
    BetterVehicleDynamicsMod.computed = nil
    -- 8 s pull: 3 s straight, 2.5 s on full lock (steering is measured here,
    -- while the car is surely rolling), then straight again
    local top = 0
    local function hold(sec, steer)
        T.drive(true, true, steer)
        local tEnd = getTimestampMs() + sec * 1000
        while getTimestampMs() < tEnd do
            top = math.max(top, math.abs(v:getCurrentSpeedKmHour()))
            coroutine.yield()
        end
    end
    local function travel(sec, steer)
        local ax, ay = v:getX(), v:getY()
        hold(sec, steer)
        local dx, dy = v:getX() - ax, v:getY() - ay
        return math.atan2(dy, dx), math.sqrt(dx * dx + dy * dy)
    end
    hold(2.5, 0)
    local h0, d0 = travel(0.5, 0)
    hold(1.5, 1)
    local h1, d1 = travel(0.5, 1)
    local turned = math.abs(math.deg(h1 - h0)) % 360
    if turned > 180 then turned = 360 - turned end
    hold(3, 0)
    local moved = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    T.check("car accelerates", top > 20, string.format("top %.1f km/h, moved %.1f tiles", top, moved))
    local c = BetterVehicleDynamicsMod.computed
    -- Only BVD's drivetrain publishes this readout; vanilla never does.
    T.check("BVD drivetrain drives the car", type(c) == "table" and type(c.gripRoad) == "number",
        c and string.format("gripRoad %s tire %s laden %s", tostring(c.gripRoad), tostring(c.tireFamily), tostring(c.ladenRatio)) or "no computed table")

    -- vanilla's isGasPedalPressed() reads the fields BVD pushes back each tick
    T.check("vanilla getters see BVD pedal state", v:isGasPedalPressed() == true)
    T.check("steering turns the car", d0 > 0.1 and d1 > 0.1 and turned > 10,
        string.format("travel direction changed %.1f deg (moved %.2f / %.2f tiles per window)", turned, d0, d1))
    -- holding "backward" while rolling forward is BVD's brake
    T.drive(true, false, 0)
    local stopped = T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
    T.check("car brakes to a stop", stopped ~= nil, string.format("speed %.1f", v:getCurrentSpeedKmHour()))
    if isClient() then
        -- keep circling so client B can watch it move
        T.drive(true, true, 0.4)
        T.wait(20)
        T.drive(true, false, 0)
        T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
    end
    T.drive(false, false, 0)
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
        local c = carNear(p:getX(), p:getY(), 100)
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
