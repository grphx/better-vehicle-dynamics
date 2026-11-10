-- Replaces Ki5.lua "power" (reference power & weight, v0.2.2 fix): a car's stored power decides what the drivetrain
-- uses, and a car that already carries the old 4x boost must not be boosted a second time (0.2.1 did, up to 28000).
-- The old test pressed the gas before reading the readout; here the readout is read with the engine idling, which relies
-- on BVD publishing BetterVehicleDynamicsMod.computed on every update (setup proves it does, or the run is not_set_up).
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


-- power the drivetrain reports using for a fresh car whose stored engine power is `stored`, with the option set
local function used(S, p, option, stored)
    setOpt("RealismHPWeight", option)
    S.wait(2)
    local v, why = newCar(S, p)
    if v == nil or why ~= nil then
        if v then dropCar(S, p, v) end
        return nil, "car: " .. tostring(why)
    end
    v:setEngineFeature(100, 30, stored)
    S.wait(0.5)
    local c = readout(S, 6)
    S.wait(0.5)
    c = BetterVehicleDynamicsMod.computed
    local got = c and tonumber(c.powerUsed)
    dropCar(S, p, v)
    return got
end

ZomboTest.scenario{
    id = "bvd_power_boost",
    description = "With reference power on, a normal or worn engine gets the 4x (capped), and a car that already carries the boost does not get it twice.",
    tags = {"bvd", "v0.2.2", "realism", "power"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("BVD sandbox options exist", SandboxVars.BetterVehicleDynamics ~= nil)
        local p = S.player()
        p:setGodMod(true)
        p:setGhostMode(true)
        clearCars(p, 200)
        local v, why = newCar(S, p)
        if not S.need("test car spawned, seated and engine running", v ~= nil and why == nil, tostring(why)) then return end
        local c = readout(S, 10)
        local ok = c ~= nil and type(c.powerUsed) == "number"
        dropCar(S, p, v)
        S.need("BVD publishes powerUsed for an idling, driven car", ok, ok and tostring(c.powerUsed) or "no readout")
    end,

    run = function(S)
        local p = S.player()
        local script = getScriptManager():getVehicle("Base.CarNormal")
        local base = script:getEngineForce()
        S.observe("Base.CarNormal script engine force " .. tostring(base))
        local cap = 28000
        local function want4x(x) return math.min(x * 4, cap) end

        local a, ea = used(S, p, false, base)
        S.check("option off: the stored power is used as it is", a == base, tostring(a) .. (ea and (" " .. ea) or ""))
        local b, eb = used(S, p, true, base)
        S.check("option on: a normal car gets the 4x (capped at 28000)", b == want4x(base), tostring(b) .. (eb and (" " .. eb) or ""))
        local worn = math.floor(base * 0.7)
        local c, ec = used(S, p, true, worn)
        S.check("option on: a worn engine (70% power) is boosted from its own value", c == want4x(worn), tostring(c) .. (ec and (" " .. ec) or ""))
        local old = want4x(base)
        local d, ed = used(S, p, true, old)
        S.check("option on: a car that spawned with the old boost already in its power is NOT boosted again", d == old, tostring(d) .. (ed and (" " .. ed) or ""))

        -- the bug itself, on the same build: switch the guard off (0.2.1 behaviour) and the same car is boosted twice
        BetterVehicleDynamicsMod.testNoBoostGuard = true
        local twice = used(S, p, true, old)
        BetterVehicleDynamicsMod.testNoBoostGuard = nil
        S.observe("the same car with the guard switched off (0.2.1 behaviour): power used " .. tostring(twice))
        S.check("without the guard the same car is boosted a second time (the reported bug)", twice == cap, tostring(twice))
        S.check("ZombieBuddy layer survived", layerOn())
        setOpt("RealismHPWeight", false)
    end,
}
