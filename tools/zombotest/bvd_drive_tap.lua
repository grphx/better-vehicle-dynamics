-- Restores the gas-tap half of the old Ki5.lua "noinput" (user report: "the car accelerates to its maximum speed on its
-- own, without touching the keyboard"): one short tap of the gas on a car that stands still, then nothing. The old test
-- only logged this half; the two checks here are NEW: the tap really moved the car, and after letting go the car never
-- got faster than it was at release (+3 km/h). Run for a stock script and two strong modded ones.
-- The no-input half is in bvd_no_input_still.lua.
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry
local CASES = {
    { "stock car 1100 kg / default force", nil, nil },
    { "strong modded car 1300 kg / 14000 force", 14000, 1300 },
    { "heavy strong 2000 kg / 16000 force", 16000, 2000 },
}

ZomboTest.scenario{
    id = "bvd_drive_tap",
    description = "After a 1 s tap of the gas and then no input, the car comes to rest within 14 seconds (no runaway).",
    tags = {"bvd", "driving", "runaway", "user-report"},
    modes = {"sp"},
    startAt = {x = ROAD.x, y = ROAD.y, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("Base.CarNormal script exists", getScriptManager():getVehicle("Base.CarNormal") ~= nil)
        local p = S.player()
        S.clearVehicles(300)
        rx, ry = roadStart()
        if not S.need("found a long street", rx ~= nil) then return end
        S.need("a test car gets going under S.drive", withCar(S, p, rx, ry, function() end))
    end,

    run = function(S)
        local p = S.player()
        local sc = getScriptManager():getVehicle("Base.CarNormal")
        local force0, mass0 = sc:getEngineForce(), sc:getMass()
        for _, c in ipairs(CASES) do
            local force, mass = c[2] or force0, c[3] or mass0
            sc:Load("CarNormal", string.format("{ engineForce = %d, mass = %d, }", force, mass))
            local res
            local ran = withCar(S, p, rx, ry, function(v)
                S.drive(false)
                S.wait(2)
                S.drive(true, true, 0)
                local tapPeak = watch(S, v, 1.0)
                S.drive(false)
                local atRelease = math.abs(v:getCurrentSpeedKmHour())
                local peak, last = watch(S, v, 14)
                res = { tapPeak = tapPeak, atRelease = atRelease, peak = peak, last = last }
                S.observe(string.format("%s: tap peak %.1f, at release %.1f, peak after %.1f, end %.1f km/h", c[1], tapPeak, atRelease, peak, last))
            end)
            S.check(c[1] .. ": the test car ran", ran)
            if res then
                S.check(c[1] .. ": the 1 s tap moved the car", res.tapPeak > 3, string.format("%.1f km/h", res.tapPeak))
                -- the throttle ramps down after release, so the car gains a few km/h first (2-5 km/h seen); a runaway
                -- would still be moving 14 s later
                S.check(c[1] .. ": with no input the car comes to rest (under 3 km/h after 14 s)", res.last < 3,
                    string.format("released at %.1f, peak after %.1f, end %.1f km/h", res.atRelease, res.peak, res.last))
            end
        end
        sc:Load("CarNormal", string.format("{ engineForce = %d, mass = %d, }", force0, mass0))
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
