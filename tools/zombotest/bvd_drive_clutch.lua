-- Restores the driving steps of the old Ki5.lua "clutch" test (v0.2 manual clutch): neutral, clutch held in first,
-- clutch let out with the throttle down, the back key braking in clutch mode, and reverse gear. The clutch key is
-- replaced by BVD.testClutch and the gear by BetterVehicleDynamicsMod.forceGear (BVD's own test hooks); the pedals are
-- held with S.drive / S.reverse. The stall steps are in bvd_clutch_stall.lua.
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry

ZomboTest.scenario{
    id = "bvd_drive_clutch",
    description = "Manual clutch: neutral and a held clutch keep the car still, letting it out launches it, the back key brakes, reverse gear goes backwards.",
    tags = {"bvd", "driving", "v0.2", "manual-clutch"},
    modes = {"sp"},
    startAt = {x = ROAD.x, y = ROAD.y, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("BVD sandbox options and test hooks exist", SandboxVars.BetterVehicleDynamics ~= nil and type(BVD.shifterShown) == "function")
        local p = S.player()
        S.clearVehicles(300)
        rx, ry = roadStart()
        if not S.need("found a long street", rx ~= nil) then return end
        S.need("a test car gets going under S.drive", withCar(S, p, rx, ry, function() end))
    end,

    run = function(S)
        local p = S.player()
        local mod = BetterVehicleDynamicsMod
        setOpt("ManualClutch", true)
        setOpt("ManualStall", true)
        S.wait(2)
        local r = {}

        local ok = withCar(S, p, rx, ry, function(v)
            mod.manualShift = true
            -- 1. neutral: revs rise, the car does not go anywhere
            mod.forceGear = 0
            BVD.testClutch = false
            S.wait(0.5)
            S.drive(true, true, 0)
            local rpmMax = 0
            r.neutralSpeed = watch(S, v, 2.5, function(car) rpmMax = math.max(rpmMax, car:getEngineSpeed()) end)
            r.neutralRpm = rpmMax
            stopCar(S, v)
            r.shifterShown = BVD.shifterShown()
            -- 2. first gear, clutch held: revs rise, the car does not go anywhere
            mod.forceGear = 1
            BVD.testClutch = true
            S.wait(0.8)
            S.drive(true, true, 0)
            rpmMax = 0
            r.heldSpeed = watch(S, v, 2.5, function(car) rpmMax = math.max(rpmMax, car:getEngineSpeed()) end)
            r.heldRpm = rpmMax
            -- 3. let the clutch out with the throttle still down: the car goes
            BVD.testClutch = false
            r.launchSpeed = watch(S, v, 4)
            r.launchRunning = v:isEngineRunning()
            -- 4. a real driver presses the clutch to stop; the back key brakes in clutch mode
            BVD.testClutch = true
            r.brakeFrom = v:getCurrentSpeedKmHour()
            S.reverse(true, 0)
            local ts = getTimestampMs()
            S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 15)
            r.brakeSeconds = (getTimestampMs() - ts) / 1000
            S.drive(false)
            BVD.testClutch = false
            -- 5. reverse gear; the car must really be still first, or a forward roll would fool the direction check
            mod.forceGear = -1
            S.wait(0.5)
            r.stoppedBeforeReverse = S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 25) ~= nil
            local x0, y0 = v:getX(), v:getY()
            S.drive(true, true, 0)
            local minSigned = 0
            watch(S, v, 3, function(car) minSigned = math.min(minSigned, car:getCurrentSpeedKmHour()) end)
            r.reverseSpeed = -minSigned   -- speed BACKWARDS: the signed speed is negative when the car moves in reverse
            local dx, dy = v:getX() - x0, v:getY() - y0
            local fv = v:getForwardVector(Vector3f.new())
            r.reverseDot = dx * fv:x() + dy * fv:z()   -- forward vector: x, z are the ground plane
            BVD.testClutch = true
            stopCar(S, v)
        end)
        BVD.testClutch = nil
        mod.manualShift = false
        setOpt("ManualClutch", false)
        setOpt("ManualStall", false)

        S.check("the test car moved on its own first", ok)
        if not ok then return end
        S.check("in neutral the car does not move (under 3 km/h)", (r.neutralSpeed or 99) < 3, string.format("%.1f km/h", r.neutralSpeed or -1))
        S.check("in neutral the revs rise freely", (r.neutralRpm or 0) > 2500, string.format("%.0f rpm", r.neutralRpm or -1))
        S.check("the on-screen shifter is up in manual mode with the clutch", r.shifterShown == true)
        S.check("clutch held in first: the car does not move (under 3 km/h)", (r.heldSpeed or 99) < 3, string.format("%.1f km/h", r.heldSpeed or -1))
        S.check("clutch held in first: the revs rise", (r.heldRpm or 0) > 2500, string.format("%.0f rpm", r.heldRpm or -1))
        S.check("letting the clutch out with the throttle down launches the car", (r.launchSpeed or 0) > 10, string.format("%.1f km/h", r.launchSpeed or -1))
        S.check("the launch does not stall the engine", r.launchRunning == true)
        S.observe(string.format("back key in clutch mode: %.1f km/h to a standstill in %.1f s", r.brakeFrom or -1, r.brakeSeconds or -1))
        S.check("the back key brakes in clutch mode (standstill from speed in under 8 s, coasting needs 30+)", (r.brakeFrom or 0) > 15 and (r.brakeSeconds or 99) < 8,
            string.format("%.1f km/h in %.1f s", r.brakeFrom or -1, r.brakeSeconds or -1))
        S.check("the car was still before the reverse step", r.stoppedBeforeReverse == true)
        S.check("reverse gear drives the car backwards", (r.reverseSpeed or 0) > 3 and (r.reverseDot or 0) < 0, string.format("%.1f km/h, dot %.2f", r.reverseSpeed or -1, r.reverseDot or 0))
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
