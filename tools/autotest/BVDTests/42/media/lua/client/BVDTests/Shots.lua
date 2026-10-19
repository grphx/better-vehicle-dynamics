-- Better Vehicle Dynamics review shots (PZ Media). Real in-game footage only: the script stages the scene and plays
-- it; every frame is the game rendering. Run: tools/ -> python3 ~/zomboid/pz-autotest/pzmedia.py shoot
require "PZAutotest/Media"
require "BVDTests/Fix"

local T = PZAutotest
local ROAD = { x = 10586, y = 11180, z = 0 }   -- open highway south of Muldraugh, heading east
local SCRIPT = "Base.CarNormal"

local function near(x, y, r)
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        if math.abs(v:getX() - x) < r and math.abs(v:getY() - y) < r then return v end
    end
end

-- a drivable car 4 tiles east of the player, with the player at the wheel and the engine running
local function car()
    local p = getPlayer()
    T.clearCars(p, 120)
    local x, y = math.floor(p:getX()) + 4, math.floor(p:getY())
    local v = addVehicleDebug(SCRIPT, IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
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
    return v
end

local function hold(sec, forward, steer)
    T.drive(true, forward, steer or 0)
    T.wait(sec)
end

local function stop(v)
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
    T.drive(false, false, 0)
end

PZMedia.shot("pull_away", function(M)
    local v = car()
    M.record("pull_away")
    hold(6, true)
    M.stop()
    stop(v)
end, { startLoc = ROAD, hour = 11, weather = "clear", zoom = 1,
       caption = "Torque-curve acceleration: the engine pulls through the gears instead of a flat push." })

PZMedia.shot("brake_marks", function(M)
    local v = car()
    hold(6, true)
    M.record("brake_marks")
    stop(v)
    T.wait(2.5)
    M.stop()
    M.still("brake_marks_still")
end, { startLoc = ROAD, hour = 11, weather = "clear", zoom = 1,
       caption = "Hard braking leaves tyre marks on the road; they fade out on their own." })

PZMedia.shot("corner", function(M)
    local v = car()
    hold(3, true)
    M.record("corner")
    hold(2.5, true, 1)
    hold(1.5, true, 0)
    M.stop()
    stop(v)
end, { startLoc = ROAD, hour = 11, weather = "clear", zoom = 1,
       caption = "Steering response blends from sharp at low speed to calm at speed." })

PZMedia.shot("info_panel", function(M)
    local v = car()
    stop(v)
    BVDCompanionPanel.pzMediaKeep = true
    ISVehicleMechanics.pzMediaKeep = true
    ISVehicleMenu.onMechanic(getPlayer(), v)
    T.wait(2)
    M.still("info_panel")
    local ui = getPlayerMechanicsUI and getPlayerMechanicsUI(0)
    if ui then ui:close() end
end, { startLoc = ROAD, hour = 11, weather = "clear", overlays = true, zoom = 1,
       caption = "The vehicle info panel docks beside the mechanics window: profile, per-surface grip, tyre type, load." })
