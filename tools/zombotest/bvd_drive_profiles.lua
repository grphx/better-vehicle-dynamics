-- Restores Ki5.lua "profiles" (v0.2 engine-type shift points): the automatic gearbox's upshift revs, with the
-- EngineProfiles option off and on, over a 9 s full-throttle run each. Every upshift must happen between 40% and 105%
-- of redline, and the option must move the first upshift by at least 100 rpm.
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry

-- lib withCar, but the gate stops by coasting (no pedal) exactly as the old harness did, not with the back key
local function withCarCoast(S, p, fn)
    for attempt = 1, 4 do
        S.teleport(rx + 0.5, ry + 3.5, 0)
        S.wait(3)
        local v
        for _ = 1, 6 do
            v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
            if v then break end
            S.wait(1.5)
        end
        if not v then return false end
        S.wait(1.5)
        fixCar(v)
        fitTires(v)
        S.wait(0.5)
        if not seat(S, p, v) then v:permanentlyRemove() return false end
        v:tryStartEngine(true)
        S.waitFor(function() return v:isEngineRunning() or nil end, 8)
        S.wait(1)
        v:setPhysicsActive(true, true)
        S.wait(0.5)
        BetterVehicleDynamicsMod.manualShift = false
        S.drive(true, true, 0)
        local peak = watch(S, v, 2.5)
        S.drive(true, false, 0)
        S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 15)
        S.drive(false)
        local moved = peak > 8
        if moved then fn(v) end
        dropCar(S, p, v)
        if moved then return true end
        S.observe("the car did not get going (spawn quirk), attempt " .. attempt)
    end
    return false
end

ZomboTest.scenario{
    id = "bvd_drive_profiles",
    description = "The automatic gearbox upshifts between 40% and 105% of redline, and EngineProfiles moves the first upshift.",
    tags = {"bvd", "driving", "v0.2", "gearbox"},
    modes = {"sp"},
    startAt = {x = ROAD.x, y = ROAD.y, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("BVD sandbox options exist", SandboxVars.BetterVehicleDynamics ~= nil)
        local p = S.player()
        S.clearVehicles(300)
        rx, ry = roadStart()
        if not S.need("found a long street", rx ~= nil) then return end
        S.need("a test car gets going under S.drive", withCar(S, p, rx, ry, function() end))
    end,

    run = function(S)
        local p = S.player()
        local function run(on)
            setOpt("EngineProfiles", on)
            S.wait(2)
            local rec, ok = {}, false
            for attempt = 1, 3 do   -- a slow debug-spawned car never reaches the upshift revs (spawn quirk): fresh car
                rec = {}
                ok = withCarCoast(S, p, function(v)
                BetterVehicleDynamicsMod.manualShift = false
                S.observe("engine rpm type " .. tostring(v:getScript():getEngineRPMType()) .. ", maxSpeed " .. tostring(v:getMaxSpeed()))
                S.drive(true, true, 0)
                local last, top = v:getTransmissionNumber(), 0
                watch(S, v, 9, function(car)
                    local g, rpm = car:getTransmissionNumber(), car:getEngineSpeed()
                    if rpm > top then top = rpm end
                    if g ~= last then
                        if g > last and last >= 1 then rec[#rec + 1] = { from = last, rpm = top } end
                        top = 0
                        last = g
                    end
                end)
                S.drive(false)
                end)
                if ok and #rec >= 1 then break end
                S.observe("no upshift in 9 s, attempt " .. attempt)
            end
            local parts = {}
            for _, e in ipairs(rec) do parts[#parts + 1] = string.format("%d->%d at %.0f", e.from, e.from + 1, e.rpm) end
            S.observe(string.format("EngineProfiles %s: upshifts %s", tostring(on), table.concat(parts, ", ")))
            return rec, ok
        end
        local off, okOff = run(false)
        local on, okOn = run(true)
        setOpt("EngineProfiles", false)
        local both = S.check("both runs drove and shifted up", okOff and okOn and #off >= 1 and #on >= 1,
            string.format("drove off=%s on=%s, upshifts off=%d on=%d", tostring(okOff), tostring(okOn), #off, #on))
        if both then
            local inRange = true
            for _, list in ipairs({ off, on }) do
                for _, e in ipairs(list) do if e.rpm < 4500 * 0.4 or e.rpm > 4500 * 1.05 then inRange = false end end
            end
            S.check("every upshift happens between 40% and 105% of redline", inRange)
            S.check("the option moves the first upshift (by at least 100 rpm)", math.abs(on[1].rpm - off[1].rpm) >= 100, string.format("%.0f vs %.0f", on[1].rpm, off[1].rpm))
        end
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
