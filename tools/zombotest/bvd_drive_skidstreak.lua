-- Restores Ki5.lua "skidstreak" (tire marks): a new skid must start at the car, not at the end of an earlier skid.
-- Launch, build speed, stop a few tiles on, launch again; the second skid's marks may not be drawn from the old spot to
-- the car. Run once with the old behaviour forced (BVD.skidStreakGapMs huge, BVD's own test hook) to show the test sees
-- the bug, and once as shipped. Change from the old test: the stop between the launches uses the back key (S.reverse)
-- instead of coasting, so the launches land 4-19 tiles apart more reliably; the pure rule is also in bvd_pure_logic.
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry

-- no pedal at all, until the car is still (the old test's stop: no brake marks)
local function coastStop(S, v)
    S.drive(true, false, 0)
    S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 12)
    S.drive(false)
end

-- one run with the given streak gap: returns the stats, or nil when the car never got going
local function skidRun(S, p, gap)
    BVD.skidStreakGapMs = gap
    local res
    local ok = withCar(S, p, rx, ry, function(v)
        -- first skid: a launch from a standstill drops marks while the car is under 10 km/h with the throttle down
        S.drive(false)
        S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 or nil end, 10)
        S.wait(0.6)
        local r = { ax = v:getX(), ay = v:getY() }
        S.drive(true, true, 0)
        S.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) >= 18 or nil end, 10)
        coastStop(S, v)                      -- stop again, a few tiles further on
        S.wait(0.8)                          -- well past the streak gap
        r.bx, r.by = v:getX(), v:getY()
        BVD.skidStats = { fresh = 0, fills = 0, maxFill = 0 }
        S.drive(true, true, 0)               -- second skid
        S.wait(1.0)
        local st = BVD.skidStats
        r.fresh, r.fills, r.maxFill, r.fx, r.fy = st.fresh, st.fills, st.maxFill, st.firstX, st.firstY
        stopCar(S, v)
        r.gap = math.sqrt((r.bx - r.ax) ^ 2 + (r.by - r.ay) ^ 2)
        res = r
    end)
    BVD.skidStreakGapMs = nil
    return ok and res or nil
end

-- the two launches must be 4 to 19 tiles apart (the old code only connects drops closer than 20): try again if not
local function inRange(S, p, gap)
    local r
    for _ = 1, 3 do
        r = skidRun(S, p, gap)
        if r and r.gap >= 4 and r.gap <= 19 then return r end
        S.observe(string.format("the launches were %s tiles apart, trying again", r and string.format("%.0f", r.gap) or "?"))
    end
    return r
end

local function report(S, tag, r)
    if not r then S.observe(tag .. ": the car never got going") return nil end
    local first = r.fx and math.sqrt((r.fx - r.bx) ^ 2 + (r.fy - r.by) ^ 2) or -1
    S.observe(string.format("%s (launches %.0f tiles apart): second skid started with %d fresh streak(s), %d fills, longest fill %.1f tiles, first mark %.1f tiles from the car where the second launch began",
        tag, r.gap or -1, r.fresh or -1, r.fills or -1, r.maxFill or -1, first))
    return first
end

ZomboTest.scenario{
    id = "bvd_drive_skidstreak",
    description = "A new skid starts a fresh streak at the car instead of being joined to the end of an earlier skid.",
    tags = {"bvd", "driving", "skidmarks"},
    modes = {"sp"},
    startAt = {x = ROAD.x, y = ROAD.y, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("the skid mark code is loaded", BVD.skidStats ~= nil and type(BVD.skidStreakContinues) == "function")
        local p = S.player()
        S.clearVehicles(300)
        rx, ry = roadStart()
        if not S.need("found a long street", rx ~= nil) then return end
        S.need("a test car gets going under S.drive", withCar(S, p, rx, ry, function() end))
    end,

    run = function(S)
        local p = S.player()
        local old = inRange(S, p, 1e9)
        report(S, "old behaviour (every earlier drop connects)", old)
        local new = inRange(S, p, nil)
        local newFirst = report(S, "as shipped", new)
        S.check("old behaviour reproduces the bug: a long fill from the earlier skid", old ~= nil and old.maxFill >= 6, old and string.format("%.1f tiles", old.maxFill) or "no run")
        S.check("as shipped: the new skid starts a fresh streak", new ~= nil and new.fresh >= 1, new and tostring(new.fresh) or "no run")
        S.check("as shipped: no long fill from the earlier skid (longest fill under 2 tiles)", new ~= nil and new.maxFill < 2.0, new and string.format("%.1f tiles", new.maxFill) or "no run")
        S.check("as shipped: the first mark of the skid is at the car (within 4 tiles of where the second launch began)", newFirst ~= nil and newFirst >= 0 and newFirst <= 4.0, newFirst and string.format("%.1f tiles", newFirst) or "no run")
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
