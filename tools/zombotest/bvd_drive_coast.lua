-- Restores Ki5.lua "coast" (v0.2 engine braking): lift off at 30 km/h and see how the controller brakes and where the
-- revs go, with the EngineBraking option at 0 (the old behaviour), 1 and 2. The throttle is held with S.drive and let
-- go with S.drive(false); BVD's per-tick readout (BetterVehicleDynamicsMod.computed) gives the braking torque.
-- Like the old test, each run uses a fresh car straight from the spawn (no proving drive, no back-key stop first), and a
-- car that never gets going or only crawls (the harness's spawn quirk; the first in-game run of the gated version had
-- two cars sit at 0 km/h with the gas held and peak at 22.8 km/h) is replaced up to 3 times.
-- The old "coast_ctl" (counting how often a spawn never gets going) is a diagnostic with no checks and is not ported.
local MOD_ID = "BetterVehicleDynamics"

--#include _lib/common.lua

local rx, ry

-- a fresh car at the start of the street, handed to fn(v); the old coastOnce flow
local function freshCar(S, p, fn)
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
    v:setPhysicsActive(true, true)   -- a debug-spawned car often stays asleep
    S.wait(0.5)
    BetterVehicleDynamicsMod.manualShift = false
    fn(v)
    S.drive(false)
    dropCar(S, p, v)
    return true
end

local function coastRun(S, v, knob)
    setOpt("EngineBraking", knob)
    S.wait(2)   -- the Java side re-reads the options about once a second
    S.drive(true, true, 0)
    local reached, peak = nil, 0
    local t0 = getTimestampMs()
    local v3
    S.waitFor(function()
        local s = math.abs(v:getCurrentSpeedKmHour())
        if s > peak then peak = s end
        if not v3 and getTimestampMs() - t0 >= 3000 then v3 = s end
        if s >= 30 then reached = s return true end
        return nil
    end, 14)
    if not reached then
        S.observe(string.format("engine braking %.1f: never reached 30 km/h (peak %.1f, engine running %s, rpm %.0f)", knob, peak, tostring(v:isEngineRunning()), v:getEngineSpeed()))
        S.drive(false)
        return nil
    end
    local atRelease = math.abs(v:getCurrentSpeedKmHour())
    S.drive(false)   -- lift off, no brake
    local rel = getTimestampMs()
    local at, marks, mi = {}, { 0.3, 1.0, 2.0, 3.0 }, 1
    local rpmMax, brakeMax, followAt1, rpmAt1 = 0, 0, nil, nil
    S.waitFor(function()
        local el = (getTimestampMs() - rel) / 1000
        if el >= 3.1 then return true end
        local rpm = v:getEngineSpeed()
        if rpm > rpmMax then rpmMax = rpm end
        local comp = BetterVehicleDynamicsMod.computed or {}
        if el < 2.0 and (tonumber(comp.engineBrake) or 0) > brakeMax then brakeMax = tonumber(comp.engineBrake) end
        if not rpmAt1 and el >= 0.8 then rpmAt1 = rpm followAt1 = tonumber(comp.rpmFollow) or 0 end
        if mi <= #marks and el >= marks[mi] then
            at[mi] = { speed = math.abs(v:getCurrentSpeedKmHour()), rpm = rpm }
            mi = mi + 1
        end
        return nil
    end, 5)
    local decel = (at[1] and at[4]) and ((at[1].speed - at[4].speed) / 3.6 / (marks[4] - marks[1])) or -1
    S.observe(string.format("engine braking %.1f: released at %.0f km/h, accel to 3 s %s km/h; after lift-off speed %s km/h; rpm max %.0f; decel %.2f m/s2; controller braking torque max %.1f, rpm %.0f vs follow target %.0f at 0.8 s",
        knob, atRelease, v3 and string.format("%.1f", v3) or "?", at[4] and string.format("%.0f", at[4].speed) or "?", rpmMax, decel, brakeMax, rpmAt1 or -1, followAt1 or 0))
    stopCar(S, v)
    return { v3 = v3, decel = decel, brake = brakeMax, follow = followAt1 or 0, rpmAt1 = rpmAt1 or -1, rpmMax = rpmMax, atRelease = atRelease }
end

ZomboTest.scenario{
    id = "bvd_drive_coast",
    description = "Engine braking 0 applies no braking torque on lift-off, 1 brakes the engine side, 2 brakes harder, and the revs follow the road.",
    tags = {"bvd", "driving", "v0.2", "engine-braking"},
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
        local res = {}
        for _, knob in ipairs({ 0.0, 1.0, 2.0 }) do
            for attempt = 1, 3 do
                freshCar(S, p, function(v) res[knob] = coastRun(S, v, knob) end)
                if res[knob] then break end
                S.observe("engine braking " .. knob .. ": the car did not get going, attempt " .. attempt)
            end
        end
        setOpt("EngineBraking", 1.0)   -- back to the shipped default
        local a, b, c = res[0.0], res[1.0], res[2.0]
        if not S.check("all three runs reached 30 km/h", a ~= nil and b ~= nil and c ~= nil) then return end
        S.check("engine braking off applies no braking torque", a.brake == 0, string.format("%.2f", a.brake))
        S.check("engine braking 1 brakes the engine side on lift-off", b.brake > 1, string.format("%.2f", b.brake))
        S.check("engine braking 2 brakes harder than 1", c.brake > b.brake * 1.3, string.format("%.2f vs %.2f", c.brake, b.brake))
        S.check("the revs follow the road after lift-off (within 30% of the target)", b.follow > 0 and math.abs(b.rpmAt1 - b.follow) < 0.3 * b.follow, string.format("%.0f vs %.0f rpm", b.rpmAt1, b.follow))
        S.check("the revs never pass 1.15 x redline", b.rpmMax < 4500 * 1.15 and c.rpmMax < 4500 * 1.15, string.format("%.0f / %.0f", b.rpmMax, c.rpmMax))
        S.check("ZombieBuddy layer survived", layerOn())
    end,
}
