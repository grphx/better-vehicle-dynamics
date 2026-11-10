-- Restores Ki5.lua "reverse" (a Workshop report: "you cannot reverse"): the back key reverses the car from a standstill,
-- and after driving forward (it brakes first, then reverses), in automatic and in manual shifting without the clutch
-- option. Every case gets its own car at the start of the street.
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry

ZomboTest.scenario{
    id = "bvd_drive_reverse",
    description = "The back key reverses the car in the default drive modes, from a standstill and after driving forward.",
    tags = {"bvd", "driving", "reverse", "user-report"},
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
        local mod = BetterVehicleDynamicsMod
        local r = {}
        local function case(key, label, manual, forwardFirst, seconds)
            local ok = withCar(S, p, rx, ry, function(v)
                mod.manualShift = manual
                if forwardFirst then
                    S.drive(true, true, 0)
                    watch(S, v, 3)
                end
                local x0, y0 = v:getX(), v:getY()
                local minSigned = 0
                S.reverse(true, 0)
                watch(S, v, seconds, function(car) minSigned = math.min(minSigned, car:getCurrentSpeedKmHour()) end)
                local fv = v:getForwardVector(Vector3f.new())
                local dot = (v:getX() - x0) * fv:x() + (v:getY() - y0) * fv:z()
                S.observe(string.format("%s: min signed speed %.1f km/h, moved %.1f tiles along the car (negative = backwards), gear %s, manualShift=%s autoReverse=%s",
                    label, minSigned, dot, tostring(v:getTransmissionNumber()), tostring(mod.manualShift), tostring(mod.autoReverse)))
                r[key] = { speed = minSigned, dot = dot }
                S.drive(false)
                S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 20)
                mod.manualShift = false
            end)
            S.check(label .. ": the test car ran", ok)
        end
        case("auto", "automatic, standstill", false, false, 4)
        case("autoFwd", "automatic, after driving forward", false, true, 10)
        case("manual", "manual shift without the clutch option, standstill", true, false, 4)
        case("manualFwd", "manual shift without the clutch option, after driving forward", true, true, 10)
        local function backwards(k) return r[k] and r[k].speed or 0 end
        S.check("automatic: the back key reverses the car from a standstill", r.auto ~= nil and backwards("auto") < -3 and r.auto.dot < 0, string.format("%.1f km/h", backwards("auto")))
        S.check("automatic: after driving forward the back key brakes and then reverses", backwards("autoFwd") < -3, string.format("%.1f km/h", backwards("autoFwd")))
        S.check("manual shifting without the clutch option: the back key reverses from a standstill", r.manual ~= nil and backwards("manual") < -3 and r.manual.dot < 0, string.format("%.1f km/h", backwards("manual")))
        S.check("manual shifting without the clutch option: after driving forward the back key brakes and then reverses", backwards("manualFwd") < -3, string.format("%.1f km/h", backwards("manualFwd")))
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
