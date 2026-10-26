-- Compatibility check with Maskarad's Summer Car (MaskaradsSummerCar). Its Engine part carries an item container,
-- which vanilla cars do not, so this exercises BVD's engine-container code paths.
-- Run with a config whose "msc" mode lists both mods; see docs/verification/.
require "PZAutotest/Runner"
require "BVDTests/Fix"

local T = PZAutotest
local SCRIPT = "Base.CarNormal"

local function describe(v)
    local script = v:getScript()
    local eng = v:getPartById("Engine")
    local box = eng and eng:getItemContainer()
    local parts, weight = 0, 0
    for i = 0, v:getPartCount() - 1 do
        local item = v:getPartByIndex(i):getInventoryItem()
        if item then parts = parts + 1; weight = weight + item:getWeight() end
    end
    local msc = v:getModData().MSC
    T.log(string.format("car: script mass %.0f, total mass %.0f, %d parts with items (%.1f kg)",
        script:getMass(), v:getMass(), parts, weight))
    T.log(string.format("engine part: container %s, %s items; script engineForce %.0f, vehicle enginePower %.0f",
        tostring(box ~= nil), box and tostring(box:getItems():size()) or "-", script:getEngineForce(), v:getEnginePower()))
    T.log(string.format("MSC state: %s, traction multiplier %s", tostring(msc ~= nil),
        tostring(msc and msc.simulation and msc.simulation.continuousTractionMultiplier)))
    return box ~= nil
end

local function makeBody(expectMsc)
  return function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true)
    p:setGhostMode(true)
    if expectMsc then T.check("MSC is enabled", getActivatedMods():contains("MaskaradsSummerCar")) end
    T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)

    T.clearCars(p, 200)
    local x, y = math.floor(p:getX()) + 4, math.floor(p:getY())
    local v = addVehicleDebug(SCRIPT, IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
    if not T.check("car spawned", v ~= nil) then return end
    T.wait(3)   -- MSC initialises the car on OnSpawnVehicleEnd
    BVDTestsFix(v)
    local hasBox = describe(v)
    if expectMsc then T.check("car has an engine container (MSC)", hasBox) end

    ISVehicleMenu.onEnter(p, v, 0)
    local inCar = T.waitFor(function() return p:getVehicle() == v end, 15)
    if not inCar then
        ISTimedActionQueue.clear(p)
        v:enter(0, p)
        v:setCharacterPosition(p, 0, "inside")
        v:playPassengerAnim(0, "idle")
        triggerEvent("OnEnterVehicle", p)
        inCar = T.waitFor(function() return p:getVehicle() == v end, 5)
    end
    if not T.check("entered driver seat", inCar ~= nil) then return end

    v:tryStartEngine(true)
    local started = T.waitFor(function() return v:isEngineRunning() end, 10)
    T.log("engine running: " .. tostring(started ~= nil))
    T.wait(1)

    T.drive(true, true, 0)
    local top, tEnd = 0, getTimestampMs() + 6000
    while getTimestampMs() < tEnd do
        top = math.max(top, math.abs(v:getCurrentSpeedKmHour()))
        coroutine.yield()
    end
    T.log(string.format("top speed after 6 s: %.1f km/h", top))
    T.check("car moves", top > 10, string.format("%.1f km/h", top))

    -- the part-pack code would leave an MSC car with no steering, no drive force and weak brakes if it ran
    -- without its mod, so check the car really steers and brakes, not only that nothing threw
    local function travel(sec)
        local ax, ay = v:getX(), v:getY()
        T.wait(sec)
        local dx, dy = v:getX() - ax, v:getY() - ay
        return math.atan2(dy, dx), math.sqrt(dx * dx + dy * dy)
    end
    local h0, d0 = travel(0.5)
    T.drive(true, true, 1)
    T.wait(1.5)
    local h1, d1 = travel(0.5)
    local turned = math.abs(math.deg(h1 - h0)) % 360
    if turned > 180 then turned = 360 - turned end
    T.check("MSC car steers", d0 > 0.1 and d1 > 0.1 and turned > 10, string.format("%.1f deg", turned))
    T.drive(true, false, 0)
    local stopped = T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
    T.check("MSC car brakes to a stop", stopped ~= nil, string.format("%.1f km/h", v:getCurrentSpeedKmHour()))
    T.drive(false, false, 0)
    -- the ZombieBuddy layer switches itself off the first time a hooked call throws
    T.check("BVD ZombieBuddy layer survived driving the MSC car",
        type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    local c = BetterVehicleDynamicsMod.computed
    T.log("BVD readout: " .. (type(c) == "table" and string.format("gripRoad %s laden %s loadPenalty %s",
        tostring(c.gripRoad), tostring(c.ladenRatio), tostring(c.loadPenalty)) or "none"))
    ISVehicleMenu.onExit(p)
  end
end

local where = { startLoc = { x = 10586, y = 11180, z = 0 } }
T.register("msc", makeBody(true), where)
T.register("msc_base", makeBody(false), where)   -- same checks without MSC, for comparison
