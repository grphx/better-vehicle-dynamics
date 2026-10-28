-- Tire wear from wheel slip. Before v0.1.18 BVD wore the installed tire ITEMS on every frame the throttle was down
-- below 8 km/h, without touching the vehicle PARTS (the mechanics window and the grip model read the part), so
-- removed wheels came out broken. Now the server wears the rear PARTS, only for real slip, and the item follows.
-- Mode "wheels" runs with the option switched on; "wheels_off" runs with the shipped default.
require "PZAutotest/Runner"
require "BVDTests/Fix"

local T = PZAutotest
local TIRES = { "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }
local REAR = { TireRearLeft = true, TireRearRight = true }

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

-- total points the counter hands out over `seconds` of being stuck, called at `fps` times a second
local function simulate(fps, seconds, stuckFor, rate)
    local state, total = { accum = 0 }, 0
    for _ = 1, math.floor(fps * seconds) do
        total = total + BVD.slipWearPoints(state, 1 / fps, stuckFor, rate)
    end
    return total
end

local function makeBody(slipWear)
    return function(T)
        T.wait(4)
        local p = getPlayer()
        p:setGodMod(true)
        p:setGhostMode(true)
        T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
        if slipWear then
            SandboxVars.BetterVehicleDynamics.TireSlipWear = true
            BVD.invalidateConfigCache()
        end
        T.log("TireSlipWear in effect: " .. tostring(BVD.cfg().TireSlipWear))
        T.check("option default matches the mode", BVD.cfg().TireSlipWear == slipWear)

        -- the counter, no game needed
        local at60, at10, at240 = simulate(60, 60, 10, 1), simulate(10, 60, 10, 1), simulate(240, 60, 10, 1)
        T.check("a minute of slip is about 30 points at any frame rate", math.abs(at60 - 30) <= 1 and math.abs(at10 - 30) <= 1 and math.abs(at240 - 30) <= 1,
            string.format("10 fps %d, 60 fps %d, 240 fps %d", at10, at60, at240))
        T.check("nothing counts before the dwell", simulate(60, 10, 1.9, 1) == 0)
        T.check("rate 2 doubles it", math.abs(simulate(60, 60, 10, 2) - 60) <= 1)
        T.check("rate 0 is off", simulate(60, 60, 10, 0) == 0)

        p:setPerkLevelDebug(Perks.Mechanics, 10)
        T.clearCars(p, 200)
        local x, y = math.floor(p:getX()), math.floor(p:getY()) - 3
        local v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(x, y, 0))
        if not T.check("car spawned", v ~= nil) then return end
        T.wait(2)
        BVDTestsFix(v)
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
        T.check("engine starts", T.waitFor(function() return v:isEngineRunning() end, 10) ~= nil)
        T.wait(1)

        local before = snap(v)
        T.log("before driving: " .. fmt(before))

        -- ordinary launches from a standstill must not wear anything
        for _ = 1, 3 do
            T.drive(true, true, 0)
            T.wait(2.5)
            T.drive(true, false, 0)
            T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
        end
        T.drive(false, false, 0)
        T.wait(1)
        local afterLaunches = snap(v)
        T.log("after 3 launches: " .. fmt(afterLaunches))
        local same = true
        for _, id in ipairs(TIRES) do
            if afterLaunches[id].part ~= before[id].part or math.abs(afterLaunches[id].item - before[id].item) > 0.01 then same = false end
        end
        T.check("three ordinary launches wear nothing", same)

        -- the automatic path: with the stuck-speed threshold raised, a car driving normally counts as stuck, so the
        -- client counts slip after the 2 s dwell and asks the server, which wears the rear parts
        BVD.stuckSpeedKmh = 500
        T.drive(true, true, 0)
        T.wait(12)
        BVD.stuckSpeedKmh = nil
        T.drive(true, false, 0)
        T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
        T.drive(false, false, 0)
        T.wait(1)
        local afterAuto = snap(v)
        T.log("after 12 s of counted slip: " .. fmt(afterAuto))
        local autoOk, autoDetail = true, {}
        for _, id in ipairs(TIRES) do
            local drop = afterAuto[id].part - 0
            drop = (afterLaunches[id].part) - afterAuto[id].part
            if REAR[id] and slipWear then
                if drop < 3 or drop > 7 then autoOk = false; autoDetail[#autoDetail + 1] = id .. " dropped " .. drop .. " (want 3-7)" end
            elseif drop ~= 0 then
                autoOk = false; autoDetail[#autoDetail + 1] = id .. " dropped " .. drop .. " (want 0)"
            end
            if math.abs(afterAuto[id].item - afterAuto[id].part) > 0.01 then autoOk = false; autoDetail[#autoDetail + 1] = id .. " item != part" end
        end
        if slipWear then
            T.check("counted slip wears the rear parts by itself, the front untouched", autoOk, table.concat(autoDetail, "; "))
        else
            T.check("with the option off counted slip wears nothing", autoOk, table.concat(autoDetail, "; "))
        end
        local rearDrop = afterLaunches.TireRearLeft.part - afterAuto.TireRearLeft.part
        T.check("both rear tires wore the same", afterAuto.TireRearLeft.part == afterAuto.TireRearRight.part)

        -- a wear request from the driver, sent twice at once: the second is inside the server's minimum interval
        BVD.requestTireWear(v, 5)
        BVD.requestTireWear(v, 5)
        T.wait(2)
        local afterWear = snap(v)
        T.log("after a wear request: " .. fmt(afterWear))
        local ok, detail = true, {}
        for _, id in ipairs(TIRES) do
            local want = afterAuto[id].part
            if slipWear and REAR[id] then want = want - 5 end
            if afterWear[id].part ~= want then ok = false; detail[#detail + 1] = id .. " part " .. tostring(afterWear[id].part) .. " want " .. want end
            if math.abs(afterWear[id].item - afterWear[id].part) > 0.01 then ok = false; detail[#detail + 1] = id .. " item " .. tostring(afterWear[id].item) .. " != part" end
        end
        if slipWear then
            T.check("wear lands on the rear parts only, once, and the items follow", ok, table.concat(detail, "; "))
        else
            T.check("with the option off a wear request changes nothing", ok, table.concat(detail, "; "))
        end

        ISVehicleMenu.onExit(p)
        T.waitFor(function() return p:getVehicle() == nil end, 10)

        -- remove every wheel the way the game's uninstall action does (success chance is 100 at this skill)
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
            T.log(string.format("removed %s: part showed %d, tire item in inventory %.1f, broken=%s", id, partCond, cond, tostring(item:isBroken())))
        end
        T.check("all four wheels came off", removedOk == 4, tostring(removedOk) .. "/4")
        T.check("no removed wheel is broken", brokenCount == 0, string.format("%d broken, lowest condition %.1f", brokenCount, lowest))
        T.check("each removed wheel has the condition the mechanics window showed", mismatch == 0, tostring(mismatch) .. " differ")
    end
end

local where = { startLoc = { x = 10586, y = 11180, z = 0 } }
T.register("wheels", makeBody(true), where)
T.register("wheels_off", makeBody(false), where)
