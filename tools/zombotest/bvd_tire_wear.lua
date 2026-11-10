-- Replaces the non-driving half of the old Wheels.lua ("wheels" / "wheels_off"): tire wear lands on the vehicle PART
-- (not only the tire item), only on the rear wheels, only when the option is on, once per request interval, and a
-- wheel taken off afterwards keeps the condition the mechanics window showed.
-- Not ported (needs the gas pedal held): "three ordinary launches wear nothing" and the automatic slip path
-- (BVD.stuckSpeedKmh raised, car driven for 12 s).
local MOD_ID = "BetterVehicleDynamics"
local SPOT = { x = 10586, y = 11180, z = 0 }
local TIRES = { "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }
local REAR = { TireRearLeft = true, TireRearRight = true }

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


-- Fit a full set of good tires the way the game's own install does it. A debug-spawned car can come without tires or
-- with flat ones, and swapping the part's item is not enough: air, physics flag and wheel model have to be set too.
-- (Ported from the old BVDTestsFitTires.)
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

local function snap(v)
    local out = {}
    for _, id in ipairs(TIRES) do
        local part = v:getPartById(id)
        local item = part and part:getInventoryItem()
        out[id] = { part = part and part:getCondition(), item = item and item:getCondition() }
    end
    return out
end

local function fmt(s)
    local t = {}
    for _, id in ipairs(TIRES) do
        t[#t + 1] = string.format("%s part %s item %.1f", (id:gsub("Tire", "")), tostring(s[id].part), s[id].item or -1)
    end
    return table.concat(t, " | ")
end

-- every tire: part == want[id] (default: unchanged from `base`), and the item condition follows the part
local function expect(after, base, drops)
    local ok, detail = true, {}
    for _, id in ipairs(TIRES) do
        local want = base[id].part - (drops[id] or 0)
        if after[id].part ~= want then ok = false; detail[#detail + 1] = id .. " part " .. tostring(after[id].part) .. " want " .. want end
        if after[id].item == nil or math.abs(after[id].item - after[id].part) > 0.01 then ok = false; detail[#detail + 1] = id .. " item " .. tostring(after[id].item) .. " != part" end
    end
    return ok, table.concat(detail, "; ")
end

local car

ZomboTest.scenario{
    id = "bvd_tire_wear",
    description = "Tire slip wear changes the rear vehicle parts only, once per request, only with the option on; removed wheels keep that condition.",
    tags = {"bvd", "tire-wear", "v0.1.18"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("BVD.requestTireWear exists", type(BVD.requestTireWear) == "function")
        local p = S.player()
        p:setGodMod(true)
        p:setGhostMode(true)
        p:setPerkLevelDebug(Perks.Mechanics, 10)   -- 100% chance for the uninstall action
        clearCars(p, 200)
        local v, why = newCar(S, p)
        if not S.need("test car spawned, seated and engine running", v ~= nil and why == nil, tostring(why)) then return end
        fitTires(v)
        S.wait(1)
        local s = snap(v)
        local fresh = true
        for _, id in ipairs(TIRES) do if s[id].part ~= 100 or s[id].item == nil or math.abs(s[id].item - 100) > 0.01 then fresh = false end end
        S.need("all four tires fitted at condition 100", fresh, fmt(s))
        S.need("the player is the driver (the server only wears for the driver)", v:isDriver(p))
        car = v
    end,

    run = function(S)
        local p = S.player()
        local v = car
        local base = snap(v)
        S.observe("before: " .. fmt(base))

        -- option off (the shipped default): a wear request does nothing
        S.check("TireSlipWear ships off", BVD.cfg().TireSlipWear == false, tostring(BVD.cfg().TireSlipWear))
        BVD.requestTireWear(v, 5)
        BVD.requestTireWear(v, 5)
        S.wait(2)
        local off = snap(v)
        S.observe("option off, after a wear request: " .. fmt(off))
        local okOff, dOff = expect(off, base, {})
        S.check("with the option off a wear request changes nothing", okOff, dOff)

        -- option on: the request, sent twice at once (the second is inside the server's minimum interval)
        setOpt("TireSlipWear", true)
        S.check("TireSlipWear is on now", BVD.cfg().TireSlipWear == true)
        S.wait(1.2)
        BVD.requestTireWear(v, 5)
        BVD.requestTireWear(v, 5)
        S.wait(2)
        local on = snap(v)
        S.observe("option on, after a wear request: " .. fmt(on))
        local okOn, dOn = expect(on, base, { TireRearLeft = 5, TireRearRight = 5 })
        S.check("wear lands on the rear parts only, once, and the items follow", okOn, dOn)
        S.check("both rear tires wore the same", on.TireRearLeft.part == on.TireRearRight.part)

        -- get out and take every wheel off the way the game's uninstall action does
        ISVehicleMenu.onExit(p)
        S.waitFor(function() return p:getVehicle() == nil or nil end, 10)
        local removedOk, brokenCount, lowest, mismatch = 0, 0, 100, 0
        for _, id in ipairs(TIRES) do
            local part = v:getPartById(id)
            local item = part:getInventoryItem()
            local partCond = part:getCondition()
            ISUninstallVehiclePart:new(p, part, 100):complete()
            if part:getInventoryItem() == nil then removedOk = removedOk + 1 end
            local cond = item:getCondition()
            lowest = math.min(lowest, cond)
            if item:isBroken() then brokenCount = brokenCount + 1 end
            if math.abs(cond - partCond) > 0.01 then mismatch = mismatch + 1 end
            S.observe(string.format("removed %s: part showed %d, tire item in inventory %.1f, broken=%s", id, partCond, cond, tostring(item:isBroken())))
        end
        S.check("all four wheels came off", removedOk == 4, removedOk .. "/4")
        S.check("no removed wheel is broken", brokenCount == 0, string.format("%d broken, lowest condition %.1f", brokenCount, lowest))
        S.check("each removed wheel has the condition the mechanics window showed", mismatch == 0, mismatch .. " differ")
        S.check("ZombieBuddy layer survived", layerOn())
        setOpt("TireSlipWear", false)
    end,
}
