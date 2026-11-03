-- Better Vehicle Dynamics 0.2 review shots (PZ Media). Real in-game footage only: the script stages the scene and plays
-- it; every frame is the game rendering. The clutch key is stood in for by BVD.testClutch, the same state the real
-- key sets. Run: tools/ -> python3 ~/zomboid/pz-autotest/pzmedia.py shoot --only shifter,stall,downshift,bush
require "PZAutotest/Media"
require "BVDTests/Fix"

local T = PZAutotest
local ROAD = { x = 10586, y = 11180, z = 0 }   -- open highway south of Muldraugh; it runs north-south here
local GRASS = { x = 10529, y = 11163, z = 0 }  -- clear grass, 40 free tiles to the north
local SCRIPT = "Base.CarNormal"

PZMedia.defaultOutfit = "Mechanic"

local function near(x, y, r)
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        if math.abs(v:getX() - x) < r and math.abs(v:getY() - y) < r then return v end
    end
end

local function car()
    local p = getPlayer()
    T.clearCars(p, 200)
    local x, y = math.floor(p:getX()), math.floor(p:getY()) - 3
    local v = addVehicleDebug(SCRIPT, IsoDirections.N, nil, getCell():getGridSquare(x, y, 0))
    v = v or T.waitFor(function() return near(x, y, 3) end, 10)
    BVDTestsFix(v)
    ISVehicleMenu.onEnter(p, v, 0)
    if not T.waitFor(function() return p:getVehicle() == v end, 15) then
        ISTimedActionQueue.clear(p)
        v:enter(0, p)
        v:setCharacterPosition(p, 0, "inside")
        v:playPassengerAnim(0, "idle")
        triggerEvent("OnEnterVehicle", p)
        T.waitFor(function() return p:getVehicle() == v end, 5)
    end
    v:tryStartEngine(true)
    T.waitFor(function() return v:isEngineRunning() end, 8)
    T.wait(1.5)
    pcall(function() v:setPhysicsActive(true, true) end)   -- a debug-spawned car sometimes starts asleep
    T.wait(0.5)
    return v
end

local function settle() T.wait(4) end

local function stopCar(v)
    BVD.testClutch = true
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
    T.drive(false, false, 0)
end

local function option(name, value)
    SandboxVars.BetterVehicleDynamics[name] = value
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
end

local function manualOn(stall)
    option("ManualClutch", true)
    option("ManualStall", stall)
    local mod = BetterVehicleDynamicsMod
    mod.manualShift = true
    mod.forceGear = 0
    BVD.testClutch = true
    BVDShifterPanel.pzMediaKeep = true
    T.wait(2)
end

local function manualOff()
    BVD.testClutch = nil
    option("ManualClutch", false)
    option("ManualStall", false)
    BetterVehicleDynamicsMod.manualShift = false
end

-- a gear change the way a driver does it: clutch in, new gear, clutch out
local function shiftTo(gear)
    BVD.testClutch = true
    T.wait(0.35)
    BetterVehicleDynamicsMod.forceGear = gear
    T.wait(0.45)
    BVD.testClutch = false
end

PZMedia.shot("shifter", function(M)
    local v = car()
    manualOn(false)
    BetterVehicleDynamicsMod.forceGear = 1
    T.wait(1.0)
    M.record("shifter")
    T.wait(0.6)
    T.drive(true, true, 0)
    BVD.testClutch = false      -- clutch out in first with the throttle down
    T.wait(2.2)
    shiftTo(2)
    T.wait(1.8)
    M.still("shifter_still")
    shiftTo(3)
    T.wait(2.0)
    M.stop()
    settle()
    stopCar(v)
    manualOff()
end, { startLoc = ROAD, hour = 11, weather = "clear", overlays = true, zoom = 1,
       caption = "Manual mode with the clutch: an H-pattern gate on the HUD shows R, N and the gears, and the knob follows your shifts. Amber means the clutch is in." })

PZMedia.shot("stall", function(M)
    local v = car()
    manualOn(true)
    BetterVehicleDynamicsMod.forceGear = 3
    T.wait(1.0)
    M.record("stall")
    T.wait(0.6)
    BVD.testClutch = false      -- clutch out in third gear, no throttle
    T.drive(false, false, 0)
    T.wait(0.9)
    M.still("stall_still")
    T.wait(2.5)
    M.stop()
    settle()
    manualOff()
end, { startLoc = ROAD, hour = 11, weather = "clear", overlays = true, zoom = 1,
       caption = "Let the clutch out in too high a gear without throttle and the engine stalls. Stalling is a separate sandbox option." })

PZMedia.shot("downshift", function(M)
    local v = car()
    manualOn(false)
    BetterVehicleDynamicsMod.forceGear = 1
    T.wait(0.6)
    T.drive(true, true, 0)
    BVD.testClutch = false
    T.wait(2.0)
    shiftTo(2)
    T.wait(1.6)
    shiftTo(3)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) > 36 end, 6)
    M.record("downshift")
    T.drive(false, false, 0)    -- lift off: no brake, no throttle
    T.wait(1.4)
    shiftTo(2)
    T.wait(1.8)
    shiftTo(1)
    T.wait(1.8)
    M.stop()
    settle()
    stopCar(v)
    manualOff()
end, { startLoc = ROAD, hour = 11, weather = "clear", overlays = true, zoom = 1,
       caption = "Engine braking: lift off in gear and the engine slows the car, harder in lower gears. No brake pedal in this clip." })

-- a hedge across the lane, and a car that is strong for its weight
local function bushSprite()
    for dy = -90, 90, 2 do
        for dx = -90, 90, 2 do
            local sq = getCell():getGridSquare(ROAD.x + dx, ROAD.y + dy, 0)
            local b = sq and sq:getBush()
            if b and b:getSprite() then return b:getSpriteName() end
        end
    end
end

PZMedia.shot("bush", function(M)
    local sc = getScriptManager():getVehicle(SCRIPT)
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    sc:Load("CarNormal", "{ engineForce = 12000, mass = 1300, }")
    local sprite = bushSprite()
    local p = getPlayer()
    local cx, cy = math.floor(p:getX()), math.floor(p:getY()) - 3
    local placed = {}
    if sprite then
        for dy = 14, 26 do
            for dx = -1, 1 do
                local sq = getCell():getGridSquare(cx + dx, cy - dy, 0)
                if sq then
                    local o = IsoObject.getNew(sq, sprite, nil, false)
                    sq:AddTileObject(o)
                    placed[#placed + 1] = { sq = sq, o = o }
                end
            end
        end
    end
    local v = car()
    T.drive(true, true, 0)
    T.wait(2.0)
    M.record("bush")
    T.wait(2.2)
    M.still("bush_still")
    T.wait(2.6)
    M.stop()
    settle()
    stopCar(v)
    for _, e in ipairs(placed) do pcall(function() e.sq:RemoveTileObject(e.o) end) end
    sc:Load("CarNormal", string.format("{ engineForce = %d, mass = %d, }", force0, mass0))
    BVD.testClutch = nil
end, { startLoc = GRASS, hour = 11, weather = "clear", zoom = 1,
       caption = "Bushes slow a car down but no longer stop a strong one: this one drives straight through the hedge." })
