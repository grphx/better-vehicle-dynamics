-- Restores the driving checks of the old BVDTests/Tests.lua (sp): the car accelerates, BVD's drivetrain drives it
-- (readout), vanilla's isGasPedalPressed() sees BVD's pedal state, steering turns the car, it brakes to a stop, it
-- does not sink. Pedals are held with S.drive / S.reverse (ZomboTest's Java helper, zombiebuddy = true).
-- Change from the old test: "brakes to a stop" now holds the back key (S.reverse, BVD's brake while rolling forward);
-- the old T.drive(true, false, 0) held neither pedal, so the car only coasted.
local MOD_ID = "BetterVehicleDynamics"
local SPOT = { x = 10586, y = 11180, z = 0 }

--#include _lib/common.lua

local car

ZomboTest.scenario{
    id = "bvd_drive_basics",
    description = "A seated car accelerates under BVD's drivetrain, steers, brakes to a stop and does not sink.",
    tags = {"bvd", "driving", "drivetrain"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        local p = S.player()
        S.observe("cleared " .. S.clearVehicles(120) .. " parked vehicle(s)")
        local v, why = newCar(S, p)
        if not S.need("test car spawned, seated and engine running", v ~= nil and why == nil, tostring(why)) then return end
        car = v
    end,

    run = function(S)
        local p = S.player()
        local v = car
        local z0 = v:getZ()
        local x0, y0 = v:getX(), v:getY()
        BetterVehicleDynamicsMod.computed = nil

        -- 3 s straight, 2 s on full lock (steering is measured while the car is surely rolling), then straight again
        local top = 0
        local function hold(sec, steer)
            S.drive(true, true, steer)
            S.waitFor(function()
                top = math.max(top, math.abs(v:getCurrentSpeedKmHour()))
                return nil
            end, sec)
        end
        local function travel(sec, steer)
            local ax, ay = v:getX(), v:getY()
            hold(sec, steer)
            local dx, dy = v:getX() - ax, v:getY() - ay
            return math.atan2(dy, dx), math.sqrt(dx * dx + dy * dy)
        end
        hold(2.5, 0)
        local h0, d0 = travel(0.5, 0)
        hold(1.5, 1)
        local h1, d1 = travel(0.5, 1)
        local turned = math.abs(math.deg(h1 - h0)) % 360
        if turned > 180 then turned = 360 - turned end
        hold(3, 0)
        local moved = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
        S.check("car accelerates", top > 20, string.format("top %.1f km/h, moved %.1f tiles", top, moved))
        local c = BetterVehicleDynamicsMod.computed
        S.check("BVD drivetrain drives the car (readout published)", type(c) == "table" and type(c.gripRoad) == "number",
            c and string.format("gripRoad %s tire %s laden %s", tostring(c.gripRoad), tostring(c.tireFamily), tostring(c.ladenRatio)) or "no computed table")
        -- vanilla's isGasPedalPressed() reads the fields BVD pushes back each tick
        S.check("vanilla getters see BVD pedal state", v:isGasPedalPressed() == true)
        S.check("steering turns the car", d0 > 0.1 and d1 > 0.1 and turned > 10,
            string.format("travel direction changed %.1f deg (moved %.2f / %.2f tiles per window)", turned, d0, d1))

        -- holding "backward" while rolling forward is BVD's brake
        S.reverse(true, 0)
        local stopped = S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 20)
        S.check("car brakes to a stop", stopped ~= nil, string.format("speed %.1f", v:getCurrentSpeedKmHour()))
        S.drive(false)
        S.check("car did not sink", math.abs(v:getZ() - z0) < 0.5, string.format("z %.2f -> %.2f", z0, v:getZ()))
        S.check("ZombieBuddy layer survived driving", layerOn())
        ISVehicleMenu.onExit(p)
        S.waitFor(function() return p:getVehicle() == nil or nil end, 10)
    end,
}
