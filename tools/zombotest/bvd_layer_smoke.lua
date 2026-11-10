-- Replaces the non-driving checks of the old BVDTests/Tests.lua (sp) and Ki5.lua "install":
-- the ZombieBuddy layer is loaded and is the thing running the car, the car stays put on its wheels.
-- Not ported (they need the pedals held, which Lua cannot do): accelerates, steering turns the car,
-- brakes to a stop, vanilla isGasPedalPressed() sees BVD's pedal state.
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


local car

ZomboTest.scenario{
    id = "bvd_layer_smoke",
    description = "BVD's ZombieBuddy layer drives a seated, idling car: it publishes its readout, stays level, and survives.",
    tags = {"bvd", "zombiebuddy", "drivetrain", "smoke"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        local p = S.player()
        p:setGodMod(true)
        p:setGhostMode(true)
        S.observe("cleared " .. clearCars(p, 120) .. " parked vehicle(s)")
        local v, why = newCar(S, p)
        S.need("test car spawned, seated and engine running", v ~= nil and why == nil, tostring(why))
        car = v
    end,

    run = function(S)
        local p = S.player()
        local v = car
        local info = getModInfoByID(MOD_ID)
        S.observe("BVD loaded from " .. tostring(info and info:getDir()))

        S.check("tyre-mark texture helper exposed", type(BVD_registerSharedTexture) == "function")
        local jv = BetterVehicleDynamicsMod and BetterVehicleDynamicsMod.javaVersion
        S.check("BVD Java reports itself (version 3.7)", jv == "3.7", tostring(jv))

        -- only BVD's drivetrain publishes this readout; vanilla never does
        local c = readout(S, 10)
        S.check("BVD drivetrain drives the car (readout published)", c ~= nil,
            c and string.format("gripRoad %s tire %s laden %s", tostring(c.gripRoad), tostring(c.tireFamily), tostring(c.ladenRatio)) or "no computed table")

        -- the info panel names the Java part that is running
        local row
        local rows = BVD.buildInfoRows and BVD.buildInfoRows(v) or {}
        for _, r in ipairs(rows) do if r[1] == "Java part" then row = r end end
        S.check("the info panel has a Java part row saying ZombieBuddy", row ~= nil and row[2] == "ZombieBuddy", row and tostring(row[2]) or "no row")

        local z0 = v:getZ()
        S.wait(6)
        S.check("idling car did not sink", math.abs(v:getZ() - z0) < 0.5, string.format("z %.2f -> %.2f", z0, v:getZ()))
        S.check("engine still running after the idle", v:isEngineRunning() == true)
        S.check("ZombieBuddy layer survived (it switches itself off the first time a hooked call throws)", layerOn())

        ISVehicleMenu.onExit(p)
        local out = S.waitFor(function() return p:getVehicle() == nil or nil end, 10)
        S.check("the player gets out again", out ~= nil)
    end,
}
