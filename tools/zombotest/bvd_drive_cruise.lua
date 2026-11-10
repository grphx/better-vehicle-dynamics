-- Restores Ki5.lua "cruise": vanilla cruise control (Left Shift + forward) as BVD runs it. Left Shift is also BVD's
-- default drift key. With the drift key = the cruise key (the default) holding both must NOT switch the cruise control
-- on and the car must not carry on by itself after letting go; with the drift key rebound the vanilla cruise control
-- still works and a tap on the brake switches it off. Keys are held with S.drive / S.shift / S.reverse;
-- BVD.testSharedKey is BVD's own test hook for "is the drift key the cruise key".
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry

ZomboTest.scenario{
    id = "bvd_drive_cruise",
    description = "Shift + forward does not switch cruise control on when Shift is the drift key, and does when the drift key is rebound.",
    tags = {"bvd", "driving", "cruise-control", "drift"},
    modes = {"sp"},
    startAt = {x = ROAD.x, y = ROAD.y, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        local p = S.player()
        S.clearVehicles(300)
        rx, ry = roadStart()
        if not S.need("found a long street", rx ~= nil) then return end
        S.need("a test car gets going under S.drive", withCar(S, p, rx, ry, function() end))
    end,

    run = function(S)
        local p = S.player()
        local res = {}
        for _, shared in ipairs({ true, false }) do
            local key = shared and "shared" or "rebound"
            BVD.testSharedKey = shared
            S.observe("== drift key " .. (shared and "is the cruise key (default)" or "rebound to another key"))
            local r = {}
            local ok = withCar(S, p, rx, ry, function(v)
                S.drive(false)
                S.wait(1)
                -- an ordinary start: forward only, up to about 25 km/h
                S.drive(true, true, 0)
                S.waitFor(function() return v:getCurrentSpeedKmHour() >= 25 or nil end, 12)
                -- now Left Shift is held as well, forward still down, for 5 s
                S.shift(true)
                r.held = watch(S, v, 5)
                r.regWhileHeld = v:isRegulator()
                -- let go of every key
                S.drive(false)
                S.shift(false)
                r.speedAtRelease = v:getCurrentSpeedKmHour()
                r.after = watch(S, v, 10)
                r.speedLater = v:getCurrentSpeedKmHour()
                r.regLater = v:isRegulator()
                -- a tap on the brake
                S.reverse(true, 0)
                S.wait(1.0)
                S.reverse(false)
                S.drive(false)
                r.regAfterBrake = v:isRegulator()
                watch(S, v, 4)
            end)
            S.shift(false)
            S.check("the test car ran (" .. key .. ")", ok)
            res[key] = r
        end
        BVD.testSharedKey = nil
        local s1, s2 = res.shared, res.rebound
        S.observe(string.format("shared key: cruise while held=%s; released at %.1f km/h, 10 s later %.1f km/h, cruise=%s", tostring(s1.regWhileHeld), s1.speedAtRelease or -1, s1.speedLater or -1, tostring(s1.regLater)))
        S.observe(string.format("rebound key: cruise while held=%s; released at %.1f km/h, 10 s later %.1f km/h, cruise=%s, after a brake tap cruise=%s", tostring(s2.regWhileHeld), s2.speedAtRelease or -1, s2.speedLater or -1, tostring(s2.regLater), tostring(s2.regAfterBrake)))
        S.check("drift key = cruise key: holding it with forward does NOT switch the cruise control on", s1.regWhileHeld == false and s1.regLater == false)
        S.check("drift key = cruise key: after the keys are released the car does not carry on by itself",
            (s1.speedLater or 99) < (s1.speedAtRelease or 0) - 3 or (s1.speedLater or 99) < 40, string.format("%.1f -> %.1f km/h", s1.speedAtRelease or -1, s1.speedLater or -1))
        S.check("drift key rebound: the vanilla cruise control still works (switches on while Shift+forward is held)", s2.regWhileHeld == true)
        S.check("drift key rebound: a tap on the brake switches the cruise control off", s2.regAfterBrake == false)
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
