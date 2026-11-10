-- Replaces the stalling half of the old Ki5.lua "clutch" test (v0.2 manual clutch). The clutch key is replaced by
-- BVD.testClutch and the gear by BetterVehicleDynamicsMod.forceGear, both BVD's own test hooks.
-- Caveat: the old test drove the car for ~2.5 s before the gear step; here a fresh car gets the gear change right after
-- the engine start, so stall timing may differ (same assertion, different warm-up; confirm in game).
-- Not ported (needs the gas / back pedal held): neutral revs rise, clutch held in first keeps the car still,
-- letting the clutch out with the throttle down launches the car, the back key brakes in clutch mode, reverse gear
-- drives the car backwards.
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


local first

-- manual shifting on, clutch out, in `gear`, no pedals: true when the engine stops within `sec`
local function stallsIn(S, v, gear, sec)
    local mod = BetterVehicleDynamicsMod
    mod.manualShift = true
    mod.forceGear = gear
    BVD.testClutch = false
    return S.waitFor(function() return (not v:isEngineRunning()) or nil end, sec) ~= nil
end

local function releaseHooks()
    BetterVehicleDynamicsMod.manualShift = false
    BVD.testClutch = nil
end

ZomboTest.scenario{
    id = "bvd_clutch_stall",
    description = "With the manual clutch option, a start with the clutch out in third or first gear and no throttle stalls the engine; with stalling off it does not.",
    tags = {"bvd", "v0.2", "manual-clutch", "stall"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("BVD sandbox options and test hooks exist", SandboxVars.BetterVehicleDynamics ~= nil and type(BVD.invalidateConfigCache) == "function" and type(BVD.shifterShown) == "function")
        local p = S.player()
        p:setGodMod(true)
        p:setGhostMode(true)
        clearCars(p, 200)
        setOpt("ManualClutch", true)
        setOpt("ManualStall", true)
        S.wait(2)
        local v, why = newCar(S, p)
        if not S.need("test car spawned, seated and engine running", v ~= nil and why == nil, tostring(why)) then return end
        first = v
    end,

    run = function(S)
        local p = S.player()
        local mod = BetterVehicleDynamicsMod

        -- 1. third gear, clutch out, no throttle, from a standstill
        S.check("the engine runs before the start", first:isEngineRunning() == true)
        local s3 = stallsIn(S, first, 3, 5)
        S.check("a start in third gear with no throttle stalls the engine", s3)
        releaseHooks()
        dropCar(S, p, first)

        -- 2. first gear from a standstill with no throttle: the idle governor's own throttle must not hide the stall
        local v2, why2 = newCar(S, p)
        S.check("second test car ready", v2 ~= nil and why2 == nil, tostring(why2))
        if v2 == nil or why2 ~= nil then if v2 then dropCar(S, p, v2) end return end
        local s1 = stallsIn(S, v2, 1, 6)
        S.check("clutch out in first gear at a standstill with no throttle stalls the engine", s1)
        releaseHooks()
        dropCar(S, p, v2)

        -- 3. control: stalling off, the same start keeps the engine running; and the on-screen shifter follows manual mode
        setOpt("ManualStall", false)
        S.wait(2)
        local v3, why3 = newCar(S, p)
        S.check("third test car ready", v3 ~= nil and why3 == nil, tostring(why3))
        if v3 == nil or why3 ~= nil then if v3 then dropCar(S, p, v3) end return end
        local ran = v3:isEngineRunning()
        mod.manualShift = true
        mod.forceGear = 3
        BVD.testClutch = false
        S.wait(1.5)
        S.check("the on-screen shifter is up in manual mode with the clutch option", BVD.shifterShown() == true)
        S.wait(2.5)
        S.check("with stalling off the same start keeps the engine running", ran == true and v3:isEngineRunning() == true,
            "running before " .. tostring(ran) .. ", after " .. tostring(v3:isEngineRunning()))
        mod.manualShift = false
        S.wait(1.5)
        S.check("the shifter goes away in automatic mode", BVD.shifterShown() == false)
        S.check("ZombieBuddy layer survived", layerOn())
        releaseHooks()
        dropCar(S, p, v3)
        setOpt("ManualClutch", false)
    end,
}
