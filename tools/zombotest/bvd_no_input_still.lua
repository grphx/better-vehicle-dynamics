-- Replaces the "no input" half of Ki5.lua "noinput" (user report: "the car accelerates to its maximum speed on its own,
-- without touching the keyboard"): a seated, idling car with no pedal held stays still, for a stock script and for two
-- strong modded ones (VehicleScript:Load with a new engineForce / mass).
-- Not ported (needs the gas pedal held): the "after a 1 s tap of the gas" half.
-- A car standing still is also what a car that cannot move does, so this only catches a runaway; each case therefore
-- also checks the script numbers took effect and the engine kept running.
local MOD_ID = "BetterVehicleDynamics"
local SPOT = { x = 10586, y = 11180, z = 0 }

-- ---- helpers shared by the BVD scenarios (each scenario file is standalone, so they are copied into each) ----
-- Game calls only happen inside functions that setup / run call, never at file load.

-- Make a debug-spawned car drivable: debug spawns come in random condition (dead battery, empty tank, locked doors).
-- (Ported from the old BVDTests/shared/Fix.lua.)
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

-- Remove every parked vehicle within radius of the player (singleplayer: directly).
local function clearCars(p, radius)
    local gone = {}
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        if math.abs(v:getX() - p:getX()) < radius and math.abs(v:getY() - p:getY()) < radius then gone[#gone + 1] = v end
    end
    for _, v in ipairs(gone) do v:permanentlyRemove() end
    return #gone
end

-- Put the player in the driver seat the way ISEnterVehicle ends up (start + perform), without the walk-up.
local function seat(S, p, v)
    v:enter(0, p)
    v:setCharacterPosition(p, 0, "inside")
    v:transmitCharacterPosition(0, "inside")
    v:playPassengerAnim(0, "idle")
    triggerEvent("OnEnterVehicle", p)
    return S.waitFor(function() return p:getVehicle() == v or nil end, 6) ~= nil
end

-- Spawn Base.CarNormal 4 tiles east of the player, fix it, seat the player, start the engine.
-- Returns the car, or nil and the step that failed.
local function newCar(S, p, script)
    local x, y = math.floor(p:getX()) + 4, math.floor(p:getY())
    local v
    for _ = 1, 6 do
        v = addVehicleDebug(script or "Base.CarNormal", IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
        if v then break end
        S.wait(1.5)
    end
    if not v then return nil, "spawn" end
    S.wait(1.5)
    fixCar(v)
    S.wait(0.5)
    if not seat(S, p, v) then v:permanentlyRemove() return nil, "seat" end
    v:tryStartEngine(true)
    if not S.waitFor(function() return v:isEngineRunning() or nil end, 10) then
        return v, "engine"
    end
    S.wait(1)
    v:setPhysicsActive(true, true)
    S.wait(0.5)
    return v
end

-- Get out and remove the car, so the next case starts clean.
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

-- Set a BVD sandbox option the way a settings change does, and drop BVD's cached config.
local function setOpt(name, value)
    SandboxVars.BetterVehicleDynamics[name] = value
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
end

-- Wait until BVD's per-tick readout (published only by BVD's own drivetrain, never by vanilla) shows up.
local function readout(S, sec)
    local mod = BetterVehicleDynamicsMod
    mod.computed = nil
    return S.waitFor(function()
        local c = mod.computed
        if type(c) == "table" and type(c.gripRoad) == "number" then return c end
        return nil
    end, sec or 10)
end

local function layerOn()
    return type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true
end
-- ---- end of shared helpers ----


local CASES = {
    { "stock car 1100 kg / default force", nil, nil },
    { "strong modded car 1300 kg / 14000 force", 14000, 1300 },
    { "heavy strong 2000 kg / 16000 force", 16000, 2000 },
}

ZomboTest.scenario{
    id = "bvd_no_input_still",
    description = "With no pedal held, an idling car stays under 3 km/h for 12 s, stock or with a strong modded script.",
    tags = {"bvd", "runaway", "user-report"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        local sc = getScriptManager():getVehicle("Base.CarNormal")
        S.need("Base.CarNormal script exists", sc ~= nil)
        local p = S.player()
        p:setGodMod(true)
        p:setGhostMode(true)
        clearCars(p, 200)
    end,

    run = function(S)
        local p = S.player()
        local sc = getScriptManager():getVehicle("Base.CarNormal")
        local force0, mass0 = sc:getEngineForce(), sc:getMass()
        S.observe(string.format("stock script: engineForce %s, mass %s", tostring(force0), tostring(mass0)))
        for i, c in ipairs(CASES) do
            local force, mass = c[2] or force0, c[3] or mass0
            sc:Load("CarNormal", string.format("{ engineForce = %d, mass = %d, }", force, mass))
            local v, why = newCar(S, p)
            S.check(c[1] .. ": car ready", v ~= nil and why == nil, tostring(why))
            if v ~= nil and why == nil then
                S.check(c[1] .. ": the script numbers took effect", math.abs(v:getScript():getEngineForce() - force) < 1 and math.abs(v:getScript():getMass() - mass) < 1,
                    string.format("engineForce %s, mass %s", tostring(v:getScript():getEngineForce()), tostring(v:getScript():getMass())))
                local peak = 0
                S.waitFor(function()
                    peak = math.max(peak, math.abs(v:getCurrentSpeedKmHour()))
                    return nil
                end, 12)
                S.observe(string.format("%s: peak %.2f km/h, gear %s, rpm %.0f, throttle %.2f", c[1], peak, tostring(v:getTransmissionNumber()), v:getEngineSpeed(), v:getThrottle()))
                S.check(c[1] .. ": with no input the car stays still", peak < 3, string.format("%.1f km/h", peak))
                S.check(c[1] .. ": engine still running (the car was not simply dead)", v:isEngineRunning() == true)
                dropCar(S, p, v)
            elseif v ~= nil then
                dropCar(S, p, v)
            end
        end
        sc:Load("CarNormal", string.format("{ engineForce = %d, mass = %d, }", force0, mass0))
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
