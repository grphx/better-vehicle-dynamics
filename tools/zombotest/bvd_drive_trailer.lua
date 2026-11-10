-- Restores Ki5.lua "trailer" for the vanilla Base.Trailer (user report: "with a trailer hitched the car runs up to its
-- top speed by itself, and the brake does not stop it"). Hitched from the driver's seat and from outside (then the
-- player gets in): no input keeps the car still, lifting off after a long drive does not keep accelerating, and the
-- back key slows the car. The old test also tried other trailer mods' scripts; those need extra dependencies and are
-- not ported. The 1 s gas tap and the long drive are logged as in the old test.
local MOD_ID = "BetterVehicleDynamics"
local TRAILER = "Base.Trailer"

--#include _lib/common.lua

local rx, ry

ZomboTest.scenario{
    id = "bvd_drive_trailer",
    description = "A car towing a trailer stays still with no input, does not keep accelerating after lift-off, and the back key slows it.",
    tags = {"bvd", "driving", "trailer", "user-report"},
    modes = {"sp"},
    startAt = {x = ROAD.x, y = ROAD.y, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need(TRAILER .. " script exists", getScriptManager():getVehicle(TRAILER) ~= nil)
        local p = S.player()
        S.clearVehicles(300)
        rx, ry = roadStart()
        if not S.need("found a long street", rx ~= nil) then return end
        S.need("a test car gets going under S.drive", withCar(S, p, rx, ry, function() end))
    end,

    run = function(S)
        local p = S.player()
        for caseIdx = 1, 2 do   -- a fresh car and road each: 1 = hitched from the driver's seat, 2 = from outside
            local label = TRAILER .. " cycle " .. caseIdx
            local outside = caseIdx == 2
            local ran = withCar(S, p, rx, ry, function(v)
                local tr
                for _ = 1, 6 do
                    tr = addVehicleDebug(TRAILER, IsoDirections.N, nil, getCell():getGridSquare(math.floor(v:getX()), math.floor(v:getY()) + 5, 0))
                    if tr then break end
                    S.wait(1.5)
                end
                S.check(label .. ": the trailer spawned", tr ~= nil)
                if tr == nil then return end
                S.wait(1.5)
                tr:setPhysicsActive(true, true)
                if outside then
                    ISVehicleMenu.onExit(p)
                    S.waitFor(function() return p:getVehicle() == nil or nil end, 5)
                    ISTimedActionQueue.clear(p)
                    S.wait(1)
                end
                v:addPointConstraint(p, tr, "trailer", "trailer")
                S.wait(2)
                if outside then
                    seat(S, p, v)
                    if not v:isEngineRunning() then
                        v:tryStartEngine(true)
                        S.waitFor(function() return v:isEngineRunning() or nil end, 8)
                    end
                    S.wait(1)
                end
                local hitched = v:getVehicleTowing() == tr
                S.check(label .. ": the trailer is hitched" .. (outside and " from outside" or " from the seat"), hitched)
                if hitched then
                    S.drive(false)
                    local pk = watch(S, v, 8)
                    S.check(label .. ": no input, the car stays still", pk < 3, string.format("%.1f km/h", pk))
                    S.drive(true, true, 0)
                    S.wait(1.0)
                    S.drive(false)
                    local pk2, last2 = watch(S, v, 10)
                    S.observe(string.format("%s tap: peak %.1f, end %.1f", label, pk2, last2))
                    -- a long drive, lift off, then watch whether it carries on
                    S.drive(true, true, 0)
                    watch(S, v, 8)
                    S.drive(false)
                    local atRelease = math.abs(v:getCurrentSpeedKmHour())
                    local pk4 = watch(S, v, 10)
                    S.check(label .. ": lifting off, the car does not keep accelerating", pk4 <= atRelease + 3, string.format("released at %.1f, peak after %.1f", atRelease, pk4))
                    -- the back key while moving forward is the brake: it must slow the car down
                    S.drive(true, true, 0)
                    watch(S, v, 6)
                    local fast = v:getCurrentSpeedKmHour()
                    S.reverse(true, 0)
                    watch(S, v, 3)
                    local slower = v:getCurrentSpeedKmHour()
                    S.reverse(false)
                    S.drive(false)
                    S.check(label .. ": the brake slows the car", slower < fast * 0.6, string.format("%.1f -> %.1f km/h", fast, slower))
                end
                v:breakConstraint(true, false)
                S.wait(2)
                tr:permanentlyRemove()
            end)
            S.check(label .. ": the test car ran", ran)
        end
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
