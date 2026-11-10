-- Restores the driving half of the old Wheels.lua: ordinary launches wear nothing, and the automatic slip path (the
-- client counts slip after a 2 s dwell and asks the server) wears the REAR vehicle parts only when TireSlipWear is on,
-- with the tire items following the parts. The stuck-speed threshold is raised (BVD.stuckSpeedKmh = 500, BVD's own
-- test hook) so a car driving normally counts as stuck; the gas pedal is held with S.drive.
-- The non-driving half (wear request, wheel removal) is in bvd_tire_wear.lua.
local MOD_ID = "BetterVehicleDynamics"
local REAR = { TireRearLeft = true, TireRearRight = true }

--#include _lib/common.lua

local rx, ry

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

-- `sec` seconds of full throttle with every car counted as stuck, then stop
local function slip(S, v, sec)
    BVD.stuckSpeedKmh = 500
    S.drive(true, true, 0)
    S.wait(sec)
    BVD.stuckSpeedKmh = nil
    stopCar(S, v)
end

-- what the parts did between `from` and `to`; ok when the rear lost 3..7 points each (wear on) or everything held
local function judge(from, to, wearOn)
    local ok, detail = true, {}
    for _, id in ipairs(TIRES) do
        local drop = from[id].part - to[id].part
        if REAR[id] and wearOn then
            if drop < 3 or drop > 7 then ok = false; detail[#detail + 1] = id .. " dropped " .. drop .. " (want 3-7)" end
        elseif drop ~= 0 then
            ok = false; detail[#detail + 1] = id .. " dropped " .. drop .. " (want 0)"
        end
        if to[id].item == nil or math.abs(to[id].item - to[id].part) > 0.01 then ok = false; detail[#detail + 1] = id .. " item != part" end
    end
    return ok, table.concat(detail, "; ")
end

ZomboTest.scenario{
    id = "bvd_drive_tire_wear",
    description = "Ordinary launches wear no tire; counted slip wears the rear parts (not the front) only with TireSlipWear on.",
    tags = {"bvd", "driving", "tire-wear", "v0.1.18"},
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
        S.check("TireSlipWear ships off", BVD.cfg().TireSlipWear == false, tostring(BVD.cfg().TireSlipWear))

        -- option off (the shipped default): launches wear nothing, and so does counted slip
        local ran = withCar(S, p, rx, ry, function(v)
            local before = snap(v)
            S.observe("option off, before driving: " .. fmt(before))
            local launched = true
            for i = 1, 3 do
                S.drive(true, true, 0)
                local peak = watch(S, v, 2.5)
                if peak <= 8 then launched = false end
                stopCar(S, v)
            end
            S.check("the three launches really moved the car", launched)
            local afterLaunches = snap(v)
            S.observe("after 3 launches: " .. fmt(afterLaunches))
            local same = true
            for _, id in ipairs(TIRES) do
                if afterLaunches[id].part ~= before[id].part or math.abs(afterLaunches[id].item - before[id].item) > 0.01 then same = false end
            end
            S.check("three ordinary launches wear nothing", same, fmt(afterLaunches))
            slip(S, v, 11)
            S.wait(1)
            local afterSlip = snap(v)
            S.observe("option off, after 11 s of counted slip: " .. fmt(afterSlip))
            local ok, detail = judge(afterLaunches, afterSlip, false)
            S.check("with the option off counted slip wears nothing", ok, detail)
        end)
        S.check("option-off car ran", ran)

        -- option on: counted slip wears the rear parts by itself, the front untouched
        setOpt("TireSlipWear", true)
        S.wait(2)
        S.check("TireSlipWear is on now", BVD.cfg().TireSlipWear == true)
        ran = withCar(S, p, rx, ry, function(v)
            local before = snap(v)
            S.observe("option on, before slip: " .. fmt(before))
            slip(S, v, 11)
            S.wait(1)
            local after = snap(v)
            S.observe("option on, after 11 s of counted slip: " .. fmt(after))
            local ok, detail = judge(before, after, true)
            S.check("counted slip wears the rear parts by itself, the front untouched, items following", ok, detail)
            S.check("both rear tires wore the same", after.TireRearLeft.part == after.TireRearRight.part)
        end)
        S.check("option-on car ran", ran)
        S.check("ZombieBuddy layer survived", layerOn())
        setOpt("TireSlipWear", false)
    end,
}
