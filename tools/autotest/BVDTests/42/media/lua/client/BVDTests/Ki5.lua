-- How do modded (KI5) cars drive under BVD, on road and on grass, with the opt-in "reference power and weight"
-- option off ("ki5") and on ("ki5_real")? Measures, per car and surface: the mass and engine power the game uses,
-- and the speed after 3 s and 6 s of full throttle from a standstill. Needs the KI5 mods + damnlib in the mod
-- list (scratch config), so it is a measurement tool, not part of the regular suite.
require "PZAutotest/Runner"
require "BVDTests/Fix"

local T = PZAutotest
local CARS = { "Base.CarNormal", "Base.63beetle", "Base.91nissan240sx", "Base.78lamboCountachLP400", "Base.89fordBronco", "Base.89defender90", "Base.78amgeneralM35A2" }
local ROAD = { x = 10586, y = 11180 }
local LINE = 40   -- tiles of clear surface needed ahead of the start square

local function floorName(sq)
    local f = sq and sq:getFloor()
    return f and f:getSpriteName() or ""
end

-- a start square with LINE free tiles of the same surface type to its north
-- strict: the floor is the only object on every square (no vegetation or other ground cover that slows vehicles)
local function findLine(prefix, cx, cy, avoid, strict, line)
    local LINE = line or LINE
    for dy = -90, 90, 3 do
        for dx = -90, 90, 3 do
            local x, y = cx + dx, cy + dy
            local ok = true
            for k = 0, LINE, 2 do
                local sq = getCell():getGridSquare(x, y - k, 0)
                if not sq or not sq:isFree(false) or floorName(sq):find(prefix, 1, true) ~= 1 then ok = false break end
                if strict and sq:getObjects():size() > 1 then ok = false break end
            end
            for _, a in ipairs(avoid or {}) do
                if math.abs(x - a.x) < 30 and math.abs(y - a.y) < 30 then ok = false end
            end
            if ok then return x, y end
        end
    end
end

local function describe(x, y)
    local sq = getCell():getGridSquare(x, y - 10, 0)
    local names = {}
    for i = 0, sq:getObjects():size() - 1 do names[#names + 1] = tostring(sq:getObjects():get(i):getSpriteName()) end
    return table.concat(names, ", ")
end

local function enter(p, v)
    v:enter(0, p)
    v:setCharacterPosition(p, 0, "inside")
    v:playPassengerAnim(0, "idle")
    triggerEvent("OnEnterVehicle", p)
    return T.waitFor(function() return p:getVehicle() == v end, 6)
end

local function sameTires(v)
    local had = 0
    for _, id in ipairs({ "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }) do
        local part = v:getPartById(id)
        if part and part:getInventoryItem() then had = had + 1 end
    end
    BVDTestsFitTires(v)   -- full air, physics flag and wheel model too, not only the item (see Fix.lua)
    return had
end

local WAKE = false  -- wake a freshly spawned car's physics before the drive (mode others_nowake turns it off)

local function measureOnce(p, script, surface, x, y)
    -- the last car drove off and the map only exists near the player: stand at the start (3 tiles behind the
    -- spawn square, as the other tests do), let the chunks load, then spawn
    p:setX(x + 0.5); p:setY(y + 3.5); p:setZ(0)
    p:setLastX(x + 0.5); p:setLastY(y + 3.5); p:setLastZ(0)
    T.wait(3)
    local v
    for attempt = 1, 6 do
        v = addVehicleDebug(script, IsoDirections.N, nil, getCell():getGridSquare(x, y, 0))
        if v then break end
        T.wait(1.5)
    end
    if not v then T.log(string.format("%-28s %-5s could not spawn", script, surface)) return end
    T.wait(1.5)
    BVDTestsFix(v)
    local hadTires = sameTires(v)
    T.wait(0.5)
    if not enter(p, v) then T.log(string.format("%-28s %-5s could not enter", script, surface)) v:permanentlyRemove() return end
    v:tryStartEngine(true)
    local started = T.waitFor(function() return v:isEngineRunning() end, 8)
    if not started then T.log(string.format("%-28s %-5s engine would not start", script, surface)) pcall(ISVehicleMenu.onExit, p) v:permanentlyRemove() return end
    T.wait(1)
    local tireNote = {}
    for _, id in ipairs({ "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }) do
        local part = v:getPartById(id)
        local item = part and part:getInventoryItem()
        tireNote[#tireNote + 1] = string.format("%s=%s/%s", (id:gsub("Tire", "")), item and item:getType() or "none", part and tostring(part:getCondition()) or "nopart")
    end
    T.log(string.format("%-28s %-5s tires %s | at spawn %d of %d | id %s", script, surface, table.concat(tireNote, " "), hadTires, v:getScript():getWheelCount(), tostring(v:getId())))
    -- a freshly spawned car can still be physics-static when the harness enters it through the back door; wake it
    local woke = "n/a"
    pcall(function()
        local before = string.format("static=%s active=%s", tostring(v.isStatic), tostring(v.isActive))
        if WAKE then v:setPhysicsActive(true, true) end
        woke = before .. " -> " .. string.format("static=%s active=%s", tostring(v.isStatic), tostring(v.isActive))
    end)
    T.log(string.format("%-28s %-5s physics %s", script, surface, woke))
    T.wait(0.5)
    local x0, y0 = v:getX(), v:getY()
    local t0 = getTimestampMs()
    local v3, v6, t30
    local redline = (v:getScript():getEngineRPMType() == "firebird") and 6000 or 4500
    local samples, pinned, maxRpm = 0, 0, 0
    local midNote
    T.drive(true, true, 0)
    while getTimestampMs() - t0 < 5000 do
        local s = math.abs(v:getCurrentSpeedKmHour())
        local rpm = v:getEngineSpeed()
        samples = samples + 1
        if rpm > maxRpm then maxRpm = rpm end
        if rpm >= 0.95 * redline then pinned = pinned + 1 end
        local el = (getTimestampMs() - t0) / 1000
        if not t30 and s >= 30 then t30 = el end
        if not v3 and el >= 3 then v3 = s end
        if not midNote and el >= 2 then
            local c = BetterVehicleDynamicsMod and BetterVehicleDynamicsMod.computed or {}
            midNote = string.format("%s %.2f", tostring(c.tireFamily), tonumber(c.gripRoad) or -1)
        end
        coroutine.yield()
    end
    v6 = math.abs(v:getCurrentSpeedKmHour())
    local dist = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    local mass, power = v:getMass(), v:getEnginePower()
    local comp = BetterVehicleDynamicsMod and BetterVehicleDynamicsMod.computed or {}
    local gripNote = string.format("%s off %.2f eff %.2f", tostring(midNote), tonumber(comp.gripOffroad) or -1, v:getScript():getOffroadEfficiency())
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
    T.drive(false, false, 0)
    pcall(ISVehicleMenu.onExit, p)
    T.waitFor(function() return p:getVehicle() == nil end, 5)
    pcall(ISTimedActionQueue.clear, p)   -- a finished exit action must not stop() against a removed car
    T.wait(0.4)
    v:permanentlyRemove()
    T.log(string.format("%-28s %-5s mass %5.0f  power %6.0f  v@3s %5.1f  v@5s %5.1f  t->30 %s  dist %4.1f  rpm max %5.0f/%d pinned %3.0f%%  [%s]",
        script, surface, mass, power, v3 or -1, v6, t30 and string.format("%.1fs", t30) or "never", dist, maxRpm, redline, 100 * pinned / math.max(1, samples), gripNote))
    T.wait(1)
    return not (v3 and v3 > 1) and v6 < 1 and dist < 8   -- never got going
end

-- A debug-spawned car now and then never gets going, with BVD out of the mod list too (checked), so try again
-- once or twice before calling a result; the log keeps every attempt.
local function measure(p, script, surface, x, y)
    for attempt = 1, 3 do
        if not measureOnce(p, script, surface, x, y) then return end
        T.log(string.format("%-28s %-5s did not move (spawn quirk), attempt %d", script, surface, attempt))
    end
end

local function scriptValues()
    local out = {}
    for _, name in ipairs(CARS) do
        local sc = getScriptManager():getVehicle(name)
        if sc then out[name] = { force = sc:getEngineForce(), mass = sc:getMass() } end
    end
    return out
end

local function logValues(label, vals)
    for _, name in ipairs(CARS) do
        if vals[name] then T.log(string.format("  %-9s %-28s script engineForce %6.0f mass %5.0f", label, name, vals[name].force, vals[name].mass)) end
    end
end

local function sameValues(a, b)
    for name, va in pairs(a) do
        local vb = b[name]
        if not vb or math.abs(va.force - vb.force) > 1 or math.abs(va.mass - vb.mass) > 1 then return false, name end
    end
    return true
end

-- a second family of modded cars, from a different author with different engine and mass scales: box trucks,
-- an ambulance, an RV, a step van and a 5900-force muscle car (RVs_HeavyDuty_Trailers)
local OTHER_CARS = { "Base.CarNormal", "Base.isuzubox", "Base.80f350ambulance", "Base.86econolinerv", "Base.chevystepvan", "Base.generallee" }

local function makeBody(realism, unregistered, cars)
    return function(T)
        if cars then CARS = cars end
        T.wait(4)
        local p = getPlayer()
        p:setGodMod(true)
        p:setGhostMode(true)
        T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
        local originals = scriptValues()
        if realism then
            if unregistered then
                -- take the KI5 cars out of BVD's tables, and stop the packs putting them back
                local data = require("BVD_VehicleData")
                for _, name in ipairs(CARS) do
                    if name ~= "Base.CarNormal" then data[name] = nil end
                end
                BVD.Packs.applyAll = function() return 0 end
            end
            SandboxVars.BetterVehicleDynamics.RealismHPWeight = true
            getSandboxOptions():updateFromLua()
            BVD.invalidateConfigCache()
            triggerEvent("OnInitGlobalModData", true)   -- BVD applies the realism rules to every vehicle script
            T.wait(2)
            local once = scriptValues()
            logValues("original", originals)
            logValues("realism", once)
            triggerEvent("OnInitGlobalModData", true)   -- again: must not compound
            T.wait(1)
            local ok, bad = sameValues(once, scriptValues())
            T.check("applying the realism rules twice changes nothing", ok, tostring(bad))
            -- the same rules for every car: unregistered ones get the power gain and keep their mass; registered
            -- ones get at least that power, and a mass from their script up to the cap
            local ruleOk, ruleBad = true, {}
            for _, name in ipairs(CARS) do
                local o, n = originals[name], once[name]
                if o and n then
                    local registeredCar = (name == "Base.CarNormal") or not unregistered
                    if registeredCar then
                        if n.force < o.force - 1 or n.mass < o.mass - 1 or n.mass > 1700 + 1 then ruleOk = false; ruleBad[#ruleBad + 1] = name .. " (registered)" end
                    else
                        if math.abs(n.force - o.force) > 1 or math.abs(n.mass - o.mass) > 1 then ruleOk = false; ruleBad[#ruleBad + 1] = name .. " (unregistered)" end
                    end
                end
            end
            T.check("registered and unregistered cars follow the same realism rules", ruleOk, table.concat(ruleBad, ", "))
        end
        T.log("RealismHPWeight in effect: " .. tostring(BVD.cfg().RealismHPWeight))
        T.clearCars(p, 300)

        local rx, ry = findLine("blends_street", ROAD.x, ROAD.y)
        rx, ry = rx or ROAD.x, ry or ROAD.y
        local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry } }, true)
        local gx, gy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry }, { x = cx or -999, y = cy or -999 } }, false)
        T.log(string.format("road start %s,%s   clear grass %s,%s   overgrown grass %s,%s", tostring(rx), tostring(ry), tostring(cx), tostring(cy), tostring(gx), tostring(gy)))
        if cx then T.log("  clear grass objects: " .. describe(cx, cy)) end
        if gx then T.log("  overgrown grass objects: " .. describe(gx, gy)) end
        T.check("found a clear grass patch", cx ~= nil)
        if realism then measure(p, "Base.CarNormal", "warm", rx, ry) end   -- the first car after a script reload is not representative
        for _, script in ipairs(CARS) do
            if getScriptManager():getVehicle(script) then
                measure(p, script, "road", rx, ry)
                if cx then measure(p, script, "clear", cx, cy) end
            else
                T.log(script .. ": script not loaded")
            end
        end
        if realism then
            SandboxVars.BetterVehicleDynamics.RealismHPWeight = false
            getSandboxOptions():updateFromLua()
            BVD.invalidateConfigCache()
            triggerEvent("OnInitGlobalModData", true)
            T.wait(1)
            local ok, bad = sameValues(originals, scriptValues())
            T.check("switching the option off puts the original scripts back", ok, tostring(bad))
        end
    end
end

-- Which off-road factor costs the speed? Same cars on clear grass, changing one thing at a time.
local function setOpt(name, value)
    SandboxVars.BetterVehicleDynamics[name] = value
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
end

local SWEEP_CARS = { "Base.78lamboCountachLP400", "Base.91nissan240sx", "Base.63beetle" }
local SWEEP = {
    { "default",                 { RollResistanceOffroad = 1.8, OffroadGrip = 0.85 } },
    { "no off-road rolling drag", { RollResistanceOffroad = 0.0, OffroadGrip = 0.85 } },
    { "no off-road grip loss",    { RollResistanceOffroad = 1.8, OffroadGrip = 1.0 } },
    { "neither",                  { RollResistanceOffroad = 0.0, OffroadGrip = 1.0 } },
    { "neither + efficiency 1.0", { RollResistanceOffroad = 0.0, OffroadGrip = 1.0 }, true },
}

local function sweepBody(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true)
    p:setGhostMode(true)
    T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y)
    local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx or ROAD.x, y = ry or ROAD.y } }, true)
    T.log(string.format("clear grass %s,%s", tostring(cx), tostring(cy)))
    if not T.check("found a clear grass patch", cx ~= nil) then return end
    for _, cfg in ipairs(SWEEP) do
        for k, v in pairs(cfg[2]) do setOpt(k, v) end
        for _, script in ipairs(SWEEP_CARS) do
            if cfg[3] then getScriptManager():getVehicle(script):Load(script, "{ offRoadEfficiency = 1.0, }") end
            T.wait(2)   -- the Java side re-reads the options about once a second
            measure(p, script, cfg[1]:sub(1, 5) .. "|" .. (cfg[3] and "eff1" or "eff0"), cx, cy)
        end
    end
end

-- Which forms of VehicleScript:Load take effect?
local function probeBody(T)
    T.wait(4)
    local sc = getScriptManager():getVehicle("Base.63beetle")
    local name = sc:getName()
    T.log(string.format("start: engineForce %.0f mass %.0f  (getName=%s fullName=%s)", sc:getEngineForce(), sc:getMass(), name, sc:getFullName()))
    local forms = {
        "{ engineForce = 7000 }",
        "{ engineForce = 7100, }",
        "{ engineForce = 7200, mass = 910 }",
        "{ mass = 920 }",
    }
    for _, body in ipairs(forms) do
        local ok, err = pcall(function() sc:Load(name, body) end)
        T.log(string.format("%-34s -> ok=%s err=%s  engineForce %.0f mass %.0f", body, tostring(ok), tostring(err), sc:getEngineForce(), sc:getMass()))
    end
    local again = getScriptManager():getVehicle("Base.63beetle")
    T.log("same object from getVehicle: " .. tostring(again == sc) .. "  engineForce there " .. tostring(again:getEngineForce()))
end

-- The realism rules are a pure function of a script's numbers, so check them across the whole range instead of
-- on a handful of cars: no driving, the question is only whether any plausible or absurd modded car can come
-- out weaker, lighter, runaway-strong or different the second time round.
local function rulesBody(T)
    T.wait(3)
    T.check("BVD.realismTarget exists", type(BVD.realismTarget) == "function")
    local forces = { 1, 400, 1500, 3000, 4000, 6150, 9000, 15000, 40000, 250000 }
    local masses = { 30, 300, 800, 1100, 1700, 2400, 6000, 20000 }
    local specs = { false, { hp = 90 }, { hp = 150, mass_kg = 1200 }, { hp = 700, mass_kg = 1500 }, { hp = 5000, mass_kg = 90000 }, { mass_kg = 900 } }
    local n, bad = 0, {}
    for _, f in ipairs(forces) do
        for _, m in ipairs(masses) do
            for si, spec in ipairs(specs) do
                spec = spec or nil
                local force, mass = BVD.realismTarget(f, m, spec)
                local force2, mass2 = BVD.realismTarget(f, m, spec)   -- same inputs, same outputs (no hidden state)
                n = n + 1
                local why
                if type(force) ~= "number" or force ~= force or force == math.huge then why = "force not a finite number"
                elseif force < f then why = "weaker than its script"
                elseif mass ~= nil and (type(mass) ~= "number" or mass ~= mass) then why = "mass not a number"
                elseif mass ~= nil and mass < m then why = "lighter than its script"
                elseif mass ~= nil and mass > math.max(1700, m) then why = "above the mass cap"
                elseif not spec and (mass ~= nil or force ~= f) then why = "unregistered car treated differently"
                elseif spec and spec.hp and force ~= math.max(spec.hp * 10, f) then why = "registered power is not max(researched, script)"
                elseif spec and not spec.hp and force ~= f then why = "registered car without hp changed power"
                elseif force ~= force2 or mass ~= mass2 then why = "not repeatable" end
                if why and #bad < 8 then bad[#bad + 1] = string.format("f=%s m=%s spec#%d: %s (-> %s, %s)", f, m, si, why, tostring(force), tostring(mass)) end
            end
        end
    end
    T.log(string.format("%d combinations of script force, mass and registration checked", n))
    T.check("realism rules hold for every combination", #bad == 0, table.concat(bad, " | "))
    local f, m = BVD.realismTarget(4000, 1000, nil)
    T.check("an ordinary unregistered car keeps its script force and its mass (the gain is in the Java)", f == 4000 and m == nil, tostring(f) .. "/" .. tostring(m))
    f = BVD.realismTarget(15000, 1000, nil)
    T.check("a strong engine's script force is left alone", f == 15000, tostring(f))
    f = BVD.realismTarget(1000, 1000, { hp = 200 })
    T.check("a registered car takes its researched power when that is higher (hp x 10)", f == 2000, tostring(f))
    local _, hm = BVD.realismTarget(4000, 2600, { hp = 200, mass_kg = 1500 })
    T.check("a registered heavy truck is not made lighter", hm == 2600, tostring(hm))
end

-- Engine braking (v0.2): lift off at speed and see how the car slows and where the revs go, with the option at
-- 0 (the old behaviour), 1 and 2. Also checks that full-throttle acceleration is untouched by the option.
local function coastRun(p, v, knob)
    SandboxVars.BetterVehicleDynamics.EngineBraking = knob
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
    T.wait(2)   -- the Java side re-reads the options about once a second
    local x0, y0 = v:getX(), v:getY()
    T.drive(true, true, 0)
    local t0, v3 = getTimestampMs(), nil
    local reached, peak = nil, 0
    while getTimestampMs() - t0 < 14000 do
        local s = math.abs(v:getCurrentSpeedKmHour())
        if s > peak then peak = s end
        if not v3 and getTimestampMs() - t0 >= 3000 then v3 = s end
        if s >= 30 then reached = s break end
        coroutine.yield()
    end
    if not reached then
        T.log(string.format("engine braking %.1f: never reached 30 km/h (peak %.1f, moved %.0f m, engine running %s, rpm %.0f)", knob, peak, math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2), tostring(v:isEngineRunning()), v:getEngineSpeed()))
        return nil, (peak < 12 and "stuck" or "slow")
    end
    local atRelease = math.abs(v:getCurrentSpeedKmHour())
    T.drive(false, false, 0)   -- lift off, no brake
    local rel = getTimestampMs()
    local at = {}
    local marks = { 0.3, 1.0, 2.0, 3.0 }
    local mi, rpmMax = 1, 0
    local brakeMax, followAt1, rpmAt1 = 0, nil, nil
    while getTimestampMs() - rel < 3100 do
        local el = (getTimestampMs() - rel) / 1000
        local rpm = v:getEngineSpeed()
        if rpm > rpmMax then rpmMax = rpm end
        local comp = BetterVehicleDynamicsMod and BetterVehicleDynamicsMod.computed or {}
        if el < 2.0 and (tonumber(comp.engineBrake) or 0) > brakeMax then brakeMax = tonumber(comp.engineBrake) end
        if not rpmAt1 and el >= 0.8 then rpmAt1 = rpm followAt1 = tonumber(comp.rpmFollow) or 0 end
        if mi <= #marks and el >= marks[mi] then
            at[mi] = { speed = math.abs(v:getCurrentSpeedKmHour()), rpm = rpm }
            mi = mi + 1
        end
        coroutine.yield()
    end
    local decel = (at[1] and at[4]) and ((at[1].speed - at[4].speed) / 3.6 / (marks[4] - marks[1])) or -1
    local dist = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    T.log(string.format("engine braking %.1f: released at %.0f km/h, accel to 3 s %s km/h; after lift-off speed %s km/h, rpm %s, rpm max %.0f; decel %.2f m/s2; run %.0f m",
        knob, atRelease, v3 and string.format("%.1f", v3) or "?",
        table.concat({ at[1] and string.format("%.0f", at[1].speed) or "?", at[2] and string.format("%.0f", at[2].speed) or "?", at[3] and string.format("%.0f", at[3].speed) or "?", at[4] and string.format("%.0f", at[4].speed) or "?" }, "/"),
        table.concat({ at[1] and string.format("%.0f", at[1].rpm) or "?", at[2] and string.format("%.0f", at[2].rpm) or "?", at[3] and string.format("%.0f", at[3].rpm) or "?", at[4] and string.format("%.0f", at[4].rpm) or "?" }, "/"),
        rpmMax, decel, dist))
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
    T.drive(false, false, 0)
    T.log(string.format("engine braking %.1f: controller braking torque max %.1f, rpm %.0f vs follow target %.0f at 0.8 s", knob, brakeMax, rpmAt1 or -1, followAt1 or 0))
    return { v3 = v3, decel = decel, brake = brakeMax, follow = followAt1 or 0, rpmAt1 = rpmAt1 or -1, rpm1 = at[2] and at[2].rpm or -1, rpmMax = rpmMax, speedEnd = at[4] and at[4].speed or -1, atRelease = atRelease }
end

local function coastOnce(p, rx, ry, knob)
    -- a fresh car at the start for each run: the previous one is a long way up the road
    p:setX(rx + 0.5); p:setY(ry + 3.5); p:setZ(0)
    p:setLastX(rx + 0.5); p:setLastY(ry + 3.5); p:setLastZ(0)
    T.wait(3)
    local v
    for k = 1, 6 do
        v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
        if v then break end
        T.wait(1.5)
    end
    if not T.check("spawned the car for engine braking " .. knob, v ~= nil) then return nil, "nospawn" end
    T.wait(1.5)
    BVDTestsFix(v)
    sameTires(v)
    T.wait(0.5)
    if not enter(p, v) then T.log("could not enter") v:permanentlyRemove() return nil, "noenter" end
    v:tryStartEngine(true)
    T.waitFor(function() return v:isEngineRunning() end, 8)
    T.wait(1)
    pcall(function() v:setPhysicsActive(true, true) end)   -- a debug-spawned car often stays asleep; only the difference between runs matters here
    T.wait(0.5)
    local r, why = coastRun(p, v, knob)
    pcall(ISVehicleMenu.onExit, p)
    T.waitFor(function() return p:getVehicle() == nil end, 5)
    pcall(ISTimedActionQueue.clear, p)   -- a finished exit action must not stop() against a removed car
    T.wait(0.4)
    v:permanentlyRemove()
    T.wait(1)
    return r, why
end

local function coastBody(T)
    T.wait(4)
    local p = getPlayer()
    T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    T.log("road start " .. tostring(rx) .. "," .. tostring(ry))
    if not T.check("found a long road", rx ~= nil) then return end
    p:setX(rx + 0.5); p:setY(ry + 3.5); p:setZ(0)
    p:setLastX(rx + 0.5); p:setLastY(ry + 3.5); p:setLastZ(0)
    T.wait(3)
    local res = {}
    local CAR = "Base.CarNormal"
    for _, knob in ipairs({ 0.0, 1.0, 2.0 }) do
        for attempt = 1, 4 do
            local r, why = coastOnce(p, rx, ry, knob)
            if r then res[knob] = r break end
            if why ~= "stuck" then break end
            T.log("the car did not get going (spawn quirk), attempt " .. attempt)
        end
    end
    local a, b, c = res[0.0], res[1.0], res[2.0]
    if not T.check("all three runs reached 30 km/h", a and b and c) then return end
    T.check("engine braking off applies no braking torque", a.brake == 0, string.format("%.2f", a.brake))
    T.check("engine braking 1 brakes the engine side on lift-off", b.brake > 1, string.format("%.2f", b.brake))
    T.check("engine braking 2 brakes harder than 1", c.brake > b.brake * 1.3, string.format("%.2f vs %.2f", c.brake, b.brake))
    T.check("the revs follow the road after lift-off (within 30% of the target)", b.follow > 0 and math.abs(b.rpmAt1 - b.follow) < 0.3 * b.follow, string.format("%.0f vs %.0f rpm", b.rpmAt1, b.follow))
    T.check("the revs never pass 1.15 x redline", b.rpmMax < 4500 * 1.15 and c.rpmMax < 4500 * 1.15, string.format("%.0f / %.0f", b.rpmMax, c.rpmMax))
end

-- Control for the stuck-spawn quirk: the same launch, engine braking off and on, no retries, counting how often a
-- car never gets going. If only the "on" runs stick, the option is breaking launches.
local function coastCtlBody(T)
    T.wait(4)
    local p = getPlayer()
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60)
    T.log("road start " .. tostring(rx) .. "," .. tostring(ry))
    if not T.check("found a road", rx ~= nil) then return end
    local counts = {}
    for _, knob in ipairs({ 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0 }) do
        local r, why = coastOnce(p, rx, ry, knob)
        local c = counts[knob] or { ok = 0, stuck = 0, other = 0 }
        counts[knob] = c
        if r then c.ok = c.ok + 1 elseif why == "stuck" then c.stuck = c.stuck + 1 else c.other = c.other + 1 end
    end
    for _, knob in ipairs({ 0.0, 1.0 }) do
        local c = counts[knob]
        T.log(string.format("engine braking %.1f: %d reached 45 km/h, %d never got going, %d slow/other", knob, c.ok, c.stuck, c.other))
    end
end

-- Manual clutch, neutral, reverse gear, stalling and the on-screen shifter (v0.2). The clutch key is replaced by
-- BVD.testClutch, gears by BetterVehicleDynamicsMod.forceGear (-1 R, 0 N, 1..n).
local function setOpt2(name, value)
    SandboxVars.BetterVehicleDynamics[name] = value
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
end

-- spawn a car, make sure it can move at all (the harness quirk), then hand it to fn(v); false when it never got going
local function withCar(p, rx, ry, fn)
    for attempt = 1, 4 do
        p:setX(rx + 0.5); p:setY(ry + 3.5); p:setZ(0)
        p:setLastX(rx + 0.5); p:setLastY(ry + 3.5); p:setLastZ(0)
        T.wait(3)
        local v
        for k = 1, 6 do
            v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
            if v then break end
            T.wait(1.5)
        end
        if not v then return false end
        T.wait(1.5)
        BVDTestsFix(v)
        sameTires(v)
        T.wait(0.5)
        if not enter(p, v) then v:permanentlyRemove() return false end
        v:tryStartEngine(true)
        T.waitFor(function() return v:isEngineRunning() end, 8)
        T.wait(1)
        pcall(function() v:setPhysicsActive(true, true) end)
        T.wait(0.5)
        -- can it move? (automatic, no clutch option)
        local mod = BetterVehicleDynamicsMod
        mod.manualShift = false
        T.drive(true, true, 0)
        local peak, t0 = 0, getTimestampMs()
        while getTimestampMs() - t0 < 2500 do
            peak = math.max(peak, math.abs(v:getCurrentSpeedKmHour()))
            coroutine.yield()
        end
        T.drive(true, false, 0)
        T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
        T.drive(false, false, 0)
        local moved = peak > 8
        if moved then
            fn(v)
        end
        pcall(ISVehicleMenu.onExit, p)
        T.waitFor(function() return p:getVehicle() == nil end, 5)
        pcall(ISTimedActionQueue.clear, p)   -- a finished exit action must not stop() against a removed car
        T.wait(0.4)
        v:permanentlyRemove()
        T.wait(1)
        if moved then return true end
        T.log("the car did not get going (spawn quirk), attempt " .. attempt)
    end
    return false
end

local function runFor(v, seconds, sample)
    local t0, peakSpeed, peakRpm = getTimestampMs(), 0, 0
    while getTimestampMs() - t0 < seconds * 1000 do
        peakSpeed = math.max(peakSpeed, math.abs(v:getCurrentSpeedKmHour()))
        peakRpm = math.max(peakRpm, v:getEngineSpeed())
        if sample then sample(v) end
        coroutine.yield()
    end
    return peakSpeed, peakRpm
end

local function stopCar(v)
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
    T.drive(false, false, 0)
    T.wait(0.5)
end

local function clutchBody(T)
    T.wait(4)
    local p = getPlayer()
    T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    local mod = BetterVehicleDynamicsMod
    setOpt2("ManualClutch", true)
    setOpt2("ManualStall", true)
    T.wait(2)
    local r = {}

    local ok = withCar(p, rx, ry, function(v)
        mod.manualShift = true
        -- 1. neutral: revs rise, the car does not go anywhere
        mod.forceGear = 0
        BVD.testClutch = false
        T.wait(0.5)
        T.drive(true, true, 0)
        r.neutralSpeed, r.neutralRpm = runFor(v, 2.5)
        stopCar(v)
        r.shifterShown = BVD.shifterShown and BVD.shifterShown() or false
        -- 2. first gear, clutch held: revs rise, the car does not go anywhere
        mod.forceGear = 1
        BVD.testClutch = true
        T.wait(0.8)
        T.drive(true, true, 0)
        r.heldSpeed, r.heldRpm = runFor(v, 2.5)
        -- 3. let the clutch out with the throttle still down: the car goes
        BVD.testClutch = false
        r.launchSpeed = runFor(v, 4)
        T.log(string.format("running: engine %s", tostring(v:isEngineRunning())))
        r.launchRunning = v:isEngineRunning()
        BVD.testClutch = true    -- a real driver presses the clutch to stop; braking with it out would stall the engine
        -- stop with a trace, once a second: when, and with what state, an engine dies on the way to a standstill
        T.drive(true, false, 0)
        local ts = getTimestampMs()
        local lastLog, wasRunning = 0, true
        while getTimestampMs() - ts < 15000 and math.abs(v:getCurrentSpeedKmHour()) >= 1 do
            local el = (getTimestampMs() - ts) / 1000
            local run = v:isEngineRunning()
            if run ~= wasRunning or el - lastLog >= 1.0 then
                lastLog = el
                T.log(string.format("  stopping %.1fs: speed %.1f, engine %s, clutch key %s (mod.clutch=%s), gear %s, rpm %.0f, brake %s",
                    el, v:getCurrentSpeedKmHour(), tostring(run), tostring(BVD.testClutch), tostring(mod.clutch), tostring(mod.forceGear), v:getEngineSpeed(), tostring(v:isBrakePedalPressed())))
                wasRunning = run
            end
            coroutine.yield()
        end
        T.drive(false, false, 0)
        BVD.testClutch = false
        -- 4. reverse gear
        mod.forceGear = -1
        T.wait(0.5)
        -- the car must really be at a standstill before the reverse is judged: a car still rolling forward from the launch
        -- would fool both the speed and the direction check (seen once, 0.2.3 regression run)
        local stopped = T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 25)
        if not stopped then T.log("the car was still rolling before the reverse step") end
        local x0, y0 = v:getX(), v:getY()
        local fx, fy = v:getForwardVector(Vector3f.new()):x(), 0
        T.log(string.format("before reverse: engine %s, speed %.1f, forceGear %s, clutch %s, rpm %.0f", tostring(v:isEngineRunning()), v:getCurrentSpeedKmHour(), tostring(mod.forceGear), tostring(mod.clutch), v:getEngineSpeed()))
        T.drive(true, true, 0)
        local minSigned = 0
        r.reverseSpeed = runFor(v, 3, function(car) minSigned = math.min(minSigned, car:getCurrentSpeedKmHour()) end)
        r.reverseSpeed = -minSigned   -- speed BACKWARDS: the signed speed is negative when the car moves in reverse
        T.log(string.format("after reverse: engine %s, speed %.1f, gear %s, rpm %.0f, throttle %.2f", tostring(v:isEngineRunning()), v:getCurrentSpeedKmHour(), tostring(v:getTransmissionNumber()), v:getEngineSpeed(), v.throttle or -1))
        local dx, dy = v:getX() - x0, v:getY() - y0
        local fv = v:getForwardVector(Vector3f.new())
        r.reverseDot = dx * fv:x() + dy * fv:z()   -- forward vector: x,z are the ground plane
        BVD.testClutch = true
        stopCar(v)
    end)
    T.check("the test car moved on its own first", ok)
    if not ok then BVD.testClutch = nil return end
    T.check("in neutral the car does not move (under 3 km/h)", (r.neutralSpeed or 99) < 3, string.format("%.1f km/h", r.neutralSpeed or -1))
    T.check("in neutral the revs rise freely", (r.neutralRpm or 0) > 2500, string.format("%.0f rpm", r.neutralRpm or -1))
    T.check("the on-screen shifter is up in manual mode with the clutch", r.shifterShown == true)
    T.check("clutch held in first: the car does not move (under 3 km/h)", (r.heldSpeed or 99) < 3, string.format("%.1f km/h", r.heldSpeed or -1))
    T.check("clutch held in first: the revs rise", (r.heldRpm or 0) > 2500, string.format("%.0f rpm", r.heldRpm or -1))
    T.check("letting the clutch out with the throttle down launches the car", (r.launchSpeed or 0) > 10, string.format("%.1f km/h", r.launchSpeed or -1))
    T.check("the launch does not stall the engine", r.launchRunning == true)
    T.check("reverse gear drives the car backwards", (r.reverseSpeed or 0) > 3 and (r.reverseDot or 0) < 0, string.format("%.1f km/h, dot %.2f", r.reverseSpeed or -1, r.reverseDot or 0))

    -- stalling: third gear, clutch out, no throttle, from a standstill
    local stalled, kept
    ok = withCar(p, rx, ry, function(v)
        mod.manualShift = true
        mod.forceGear = 3
        BVD.testClutch = false
        T.drive(false, false, 0)
        local t0 = getTimestampMs()
        while getTimestampMs() - t0 < 5000 and v:isEngineRunning() do coroutine.yield() end
        stalled = not v:isEngineRunning()
    end)
    T.check("a start in third gear with no throttle stalls the engine", ok and stalled == true)
    -- first gear from a standstill with no throttle: the idle governor's own throttle must not hide the stall
    local stalled1
    ok = withCar(p, rx, ry, function(v)
        mod.manualShift = true
        mod.forceGear = 1
        BVD.testClutch = false
        T.drive(false, false, 0)
        local t0 = getTimestampMs()
        while getTimestampMs() - t0 < 6000 and v:isEngineRunning() do coroutine.yield() end
        stalled1 = not v:isEngineRunning()
    end)
    T.check("clutch out in first gear at a standstill with no throttle stalls the engine", ok and stalled1 == true)
    setOpt2("ManualStall", false)
    T.wait(2)
    ok = withCar(p, rx, ry, function(v)
        mod.manualShift = true
        mod.forceGear = 3
        BVD.testClutch = false
        T.drive(false, false, 0)
        T.wait(4)
        kept = v:isEngineRunning()
    end)
    T.check("with stalling off the same start keeps the engine running", ok and kept == true)
    BVD.testClutch = nil
    setOpt2("ManualClutch", false)
end

local where = { startLoc = { x = ROAD.x, y = ROAD.y, z = 0 } }
T.register("rules", rulesBody, where)
T.register("coast", coastBody, where)
T.register("clutch", clutchBody, where)
T.register("coast_ctl", coastCtlBody, where)
T.register("ki5_probe", probeBody, where)
T.register("ki5_sweep", sweepBody, where)
T.register("ki5", makeBody(false), where)
T.register("ki5_real", makeBody(true, false), where)
T.register("ki5_unreg", makeBody(true, true), where)
T.register("others", makeBody(false, false, OTHER_CARS), where)
T.register("others_real", makeBody(true, true, OTHER_CARS), where)
T.register("others_nowake", function(T) WAKE = false; return makeBody(false, false, OTHER_CARS)(T) end, where)
T.register("ki5_nobrake", function(T)   -- same as ki5 with engine braking at 0: separates the v0.2 option from the grass numbers
    SandboxVars.BetterVehicleDynamics.EngineBraking = 0
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
    return makeBody(false)(T)
end, where)
-- Heavy unregistered car: the same CarNormal with its script mass raised and its engine force left alone, on road and clear grass.
-- (A user report: a ~2000 kg modded sedan crawls at ~5 km/h on dirt while the road is fine.)
T.register("heavy", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y)
    rx, ry = rx or ROAD.x, ry or ROAD.y
    local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry } }, true)
    T.log(string.format("road start %s,%s   clear grass %s,%s", tostring(rx), tostring(ry), tostring(cx), tostring(cy)))
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    for _, cfg in ipairs({ { 1100, 1.0 }, { 1600, 1.0 }, { 2000, 1.0 }, { 2000, 2.0 } }) do
        sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", cfg[1], force0 * cfg[2]))
        T.log(string.format("script now mass %.0f force %.0f", sc:getMass(), sc:getEngineForce()))
        measure(p, "Base.CarNormal", "road", rx, ry)
        if cx then measure(p, "Base.CarNormal", "clear", cx, cy) end
    end
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", mass0, force0))
end, where)
-- Heavy car on clear grass at several off-road rolling-drag settings (same 2000 kg / 4000 force script).
T.register("heavy_drag", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y)
    rx, ry = rx or ROAD.x, ry or ROAD.y
    local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry } }, true)
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    sc:Load("CarNormal", "{ mass = 2000, engineForce = 4000, }")
    for _, rr in ipairs({ 1.8, 0.9, 0.4, 0.0 }) do
        SandboxVars.BetterVehicleDynamics.RollResistanceOffroad = rr
        getSandboxOptions():updateFromLua()
        BVD.invalidateConfigCache()
        T.wait(2)
        T.log("RollResistanceOffroad " .. rr)
        measure(p, "Base.CarNormal", "clear", cx, cy)
    end
    SandboxVars.BetterVehicleDynamics.RollResistanceOffroad = 1.8
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", mass0, force0))
end, where)
-- Heavy car (2000 kg script, 6000 force) at low / normal / high offRoadEfficiency, road and clear grass. Run it with BVD
-- ("heavy_eff") and with its Java part off ("heavy_eff_van") to see what vanilla's own off-road handling gives.
local function heavyEffBody(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.log("ZombieBuddy layer active: " .. tostring(type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true))
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y)
    rx, ry = rx or ROAD.x, ry or ROAD.y
    local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry } }, true)
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0, eff0 = sc:getEngineForce(), sc:getMass(), sc:getOffroadEfficiency()
    for _, eff in ipairs({ 0.4, 1.0, 2.0 }) do
        sc:Load("CarNormal", string.format("{ mass = 2000, engineForce = 6000, offRoadEfficiency = %.1f, }", eff))
        T.log(string.format("script now mass %.0f force %.0f offroadEfficiency %.1f", sc:getMass(), sc:getEngineForce(), sc:getOffroadEfficiency()))
        measure(p, "Base.CarNormal", "road", rx, ry)
        measure(p, "Base.CarNormal", "clear", cx, cy)
    end
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, offRoadEfficiency = %.1f, }", mass0, force0, eff0))
end
T.register("heavy_eff", heavyEffBody, where)
T.register("heavy_eff_van", heavyEffBody, where)
-- Heavy car on every kind of ground found near the start: which floor sprites exist, and how the car does on each.
T.register("heavy_surf", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.log("ZombieBuddy layer active: " .. tostring(type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true))
    T.clearCars(p, 300)
    local count, order = {}, {}
    for dy = -90, 90, 3 do
        for dx = -90, 90, 3 do
            local sq = getCell():getGridSquare(ROAD.x + dx, ROAD.y + dy, 0)
            local n = sq and floorName(sq) or ""
            local base = n:gsub("_%d+$", "")
            if n ~= "" then
                if not count[base] then count[base] = 0; order[#order + 1] = base end
                count[base] = count[base] + 1
            end
        end
    end
    for _, b in ipairs(order) do T.log(string.format("floor %-40s %d squares", b, count[b])) end
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    sc:Load("CarNormal", "{ mass = 2000, engineForce = 6000, }")
    local used = {}
    for _, b in ipairs(order) do
        if not b:find("blends_street", 1, true) and count[b] >= 8 then
            for _, strict in ipairs({ true, false }) do
                local x, y = findLine(b, ROAD.x, ROAD.y, nil, strict, 40)
                if x and not used[x .. "," .. y] then
                    used[x .. "," .. y] = true
                    T.log(string.format("surface %s strict=%s at %d,%d  objects: %s", b, tostring(strict), x, y, describe(x, y)))
                    measure(p, "Base.CarNormal", (strict and "S:" or "O:") .. b:sub(-12), x, y)
                end
            end
        end
    end
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", mass0, force0))
end, where)
-- The overgrown-ground patch that held a 2000 kg car at 0 km/h: is it the place, the weight or the harness?
T.register("heavy_over", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local x, y = findLine("blends_natural_01", ROAD.x, ROAD.y, nil, false, 40)
    local sx, sy = findLine("blends_natural_01", ROAD.x, ROAD.y, nil, true, 40)
    T.log(string.format("overgrown %s,%s (%s)   clear %s,%s", tostring(x), tostring(y), x and describe(x, y) or "-", tostring(sx), tostring(sy)))
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    for _, cfg in ipairs({ { 1100, 4000 }, { 2000, 6000 }, { 2000, 16000 } }) do
        sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", cfg[1], cfg[2]))
        for _, wake in ipairs({ false, true }) do
            WAKE = wake
            T.log(string.format("script mass %d force %d wake %s", cfg[1], cfg[2], tostring(wake)))
            if x then measure(p, "Base.CarNormal", "over", x, y) end
        end
    end
    WAKE = false
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", mass0, force0))
end, where)
-- Bushes: a line of real bush sprites across a clear patch, and how a light, a heavy and a heavy strong car do through it.
-- The vanilla game takes a fixed share of a car's speed off for every update it touches a bush.
local function findBushSprite()
    for dy = -90, 90, 2 do
        for dx = -90, 90, 2 do
            local sq = getCell():getGridSquare(ROAD.x + dx, ROAD.y + dy, 0)
            local b = sq and sq:getBush()
            if b and b:getSprite() then return b:getSpriteName() end
        end
    end
end

local function bushRun(p, x, y, label, bushes)
    p:setX(x + 0.5); p:setY(y + 3.5); p:setZ(0)
    p:setLastX(x + 0.5); p:setLastY(y + 3.5); p:setLastZ(0)
    T.wait(3)
    local v
    for attempt = 1, 6 do
        v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(x, y, 0))
        if v then break end
        T.wait(1.5)
    end
    if not v then T.log(label .. ": could not spawn") return end
    T.wait(1.5)
    BVDTestsFix(v)
    sameTires(v)
    T.wait(0.5)
    if not enter(p, v) then T.log(label .. ": could not enter") v:permanentlyRemove() return end
    v:tryStartEngine(true)
    T.waitFor(function() return v:isEngineRunning() end, 8)
    T.wait(1)
    local x0, y0 = v:getX(), v:getY()
    local t0 = getTimestampMs()
    local marks, mi, at, peak = { 2, 3, 4, 5, 6, 7, 8 }, 1, {}, 0
    T.drive(true, true, 0)
    while getTimestampMs() - t0 < 8100 do
        local el = (getTimestampMs() - t0) / 1000
        local s = math.abs(v:getCurrentSpeedKmHour())
        if s > peak then peak = s end
        if mi <= #marks and el >= marks[mi] then at[mi] = string.format("%.0f", s) mi = mi + 1 end
        coroutine.yield()
    end
    local dist = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    T.log(string.format("%-34s %s  speed at 2..8 s: %s  peak %.0f  moved %.0f m", label, bushes and "BUSHES" or "no bushes", table.concat(at, "/"), peak, dist))
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 15)
    T.drive(false, false, 0)
    pcall(ISVehicleMenu.onExit, p)
    T.waitFor(function() return p:getVehicle() == nil end, 5)
    pcall(ISTimedActionQueue.clear, p)   -- a finished exit action must not stop() against a removed car
    T.wait(0.4)
    v:permanentlyRemove()
    T.wait(1)
end

local function bushBody(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.log("ZombieBuddy layer active: " .. tostring(type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true))
    T.clearCars(p, 300)
    local sprite = findBushSprite()
    T.log("bush sprite found: " .. tostring(sprite))
    local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, nil, true, 40)
    T.log(string.format("clear patch %s,%s", tostring(cx), tostring(cy)))
    if not (sprite and cx) then T.check("have a bush sprite and a clear patch", false) return end
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    local cars = { { "light 1100/4000", 1100, 4000 }, { "heavy 2000/6000", 2000, 6000 }, { "heavy strong 2000/16000", 2000, 16000 } }
    local function runAll(bushes)
        for _, c in ipairs(cars) do
            sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", c[2], c[3]))
            bushRun(p, cx, cy, c[1], bushes)
        end
    end
    runAll(false)
    -- bushes from 10 to 30 tiles ahead, on the car's column and the one beside it
    local placed = {}
    for dy = 8, 28 do
        for dx = -1, 1 do   -- three columns: the car does not stay on one line
            local sq = getCell():getGridSquare(cx + dx, cy - dy, 0)
            if sq then
                local o = IsoObject.getNew(sq, sprite, nil, false)
                sq:AddTileObject(o)
                placed[#placed + 1] = { sq = sq, o = o }
            end
        end
    end
    T.log(#placed .. " bushes placed; first one isBush=" .. tostring(placed[1] and placed[1].o:isBush()))
    runAll(true)
    for _, e in ipairs(placed) do pcall(function() e.sq:RemoveTileObject(e.o) end) end
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", mass0, force0))
end
-- Bushes only, at several ShoveFoliage values, for the cars that matter (light stock, heavy, heavy strong, stock-strength heavy x2).
T.register("bush_sweep", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local sprite = findBushSprite()
    local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, nil, true, 40)
    if not (sprite and cx) then T.check("have a bush sprite and a clear patch", false) return end
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0, mass0 = sc:getEngineForce(), sc:getMass()
    local placed = {}
    for dy = 8, 28 do
        local sq = getCell():getGridSquare(cx, cy - dy, 0)
        if sq then local o = IsoObject.getNew(sq, sprite, nil, false); sq:AddTileObject(o); placed[#placed + 1] = { sq = sq, o = o } end
    end
    local cars = { { "light 1100/4000", 1100, 4000 }, { "heavy 2000/6000", 2000, 6000 }, { "heavy 2000/10000", 2000, 10000 }, { "strong 2000/16000", 2000, 16000 } }
    for _, shove in ipairs({ 0.2, 0.1, 0.05 }) do
        SandboxVars.BetterVehicleDynamics.ShoveFoliage = shove
        getSandboxOptions():updateFromLua()
        BVD.invalidateConfigCache()
        T.wait(2)
        for _, c in ipairs(cars) do
            sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", c[2], c[3]))
            bushRun(p, cx, cy, string.format("shove %.2f  %s", shove, c[1]), true)
        end
    end
    for _, e in ipairs(placed) do pcall(function() e.sq:RemoveTileObject(e.o) end) end
    SandboxVars.BetterVehicleDynamics.ShoveFoliage = 1.0
    sc:Load("CarNormal", string.format("{ mass = %d, engineForce = %d, }", mass0, force0))
end, where)
T.register("bush", bushBody, where)
T.register("bush_van", bushBody, where)
local function shoveBody(v) return function(T)
    SandboxVars.BetterVehicleDynamics.ShoveFoliage = v
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
    T.log("ShoveFoliage " .. v)
    return bushBody(T)
end end
T.register("bush_s03", shoveBody(0.3), where)
T.register("bush_s0", shoveBody(0.0), where)
-- Engine-type shift points (v0.2): the automatic gearbox's upshift revs with the option off and on.
local function profilesBody(T)
    T.wait(4)
    local p = getPlayer()
    T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    local function run(on)
        setOpt2("EngineProfiles", on)
        T.wait(2)
        local rec = {}
        local ok = withCar(p, rx, ry, function(v)
            BetterVehicleDynamicsMod.manualShift = false
            T.log("engine rpm type " .. tostring(v:getScript():getEngineRPMType()))
            T.drive(true, true, 0)
            local last, top = v:getTransmissionNumber(), 0
            local t0 = getTimestampMs()
            while getTimestampMs() - t0 < 9000 do
                local g, r = v:getTransmissionNumber(), v:getEngineSpeed()
                if r > top then top = r end
                if g ~= last then
                    if g > last and last >= 1 then rec[#rec + 1] = { from = last, rpm = top } end
                    top = 0
                    last = g
                end
                coroutine.yield()
            end
            T.drive(true, false, 0)
        end)
        local parts = {}
        for _, e in ipairs(rec) do parts[#parts + 1] = string.format("%d->%d at %.0f", e.from, e.from + 1, e.rpm) end
        T.log(string.format("EngineProfiles %s: upshifts %s", tostring(on), table.concat(parts, ", ")))
        return rec, ok
    end
    local off, okOff = run(false)
    local on, okOn = run(true)
    setOpt2("EngineProfiles", false)
    if not T.check("both runs drove and shifted up", okOff and okOn and #off >= 1 and #on >= 1, string.format("drove off=%s on=%s, upshifts off=%d on=%d", tostring(okOff), tostring(okOn), #off, #on)) then return end
    local inRange = true
    for _, list in ipairs({ off, on }) do
        for _, e in ipairs(list) do if e.rpm < 4500 * 0.4 or e.rpm > 4500 * 1.05 then inRange = false end end
    end
    T.check("every upshift happens between 40% and 105% of redline", inRange)
    T.check("the option moves the first upshift (by at least 100 rpm)", math.abs(on[1].rpm - off[1].rpm) >= 100, string.format("%.0f vs %.0f", on[1].rpm, off[1].rpm))
end
T.register("profiles", profilesBody, where)

-- The info panel says which Java part is running.
T.register("install", function(T)
    T.wait(4)
    local p = getPlayer()
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60)
    if not T.check("found a road", rx ~= nil) then return end
    local row
    local ok = withCar(p, rx, ry, function(v)
        local rows = BVD.buildInfoRows and BVD.buildInfoRows(v) or {}
        for _, r in ipairs(rows) do if r[1] == "Java part" then row = r end end
    end)
    T.check("the info panel has a Java part row", ok and row ~= nil)
    T.check("it says ZombieBuddy when the ZombieBuddy layer is active", row and row[2] == "ZombieBuddy", row and tostring(row[2]) or "no row")
end, where)

-- Reference power & weight on: a car's stored power (script force x quality, saved with the world) decides what the
-- drivetrain uses. A car that spawned while 0.1.19 - 0.2.0 wrote the 4x into the scripts already carries it and must
-- not be boosted a second time (0.2.1 did, up to 28000: "modded cars feel extremely fast after the update").
T.register("power", function(T)
    T.wait(4)
    local p = getPlayer()
    T.check("BVD ZombieBuddy layer active", type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    local script = getScriptManager():getVehicle("Base.CarNormal")
    T.log("script engine force " .. tostring(script:getEngineForce()))
    local function used(option, stored)
        setOpt2("RealismHPWeight", option)
        T.wait(2)
        local got
        local ok = withCar(p, rx, ry, function(v)
            v:setEngineFeature(100, 30, stored)
            BetterVehicleDynamicsMod.computed = nil
            T.drive(true, true, 0)
            T.wait(1.5)
            local c = BetterVehicleDynamicsMod.computed
            got = c and tonumber(c.powerUsed)
            T.drive(true, false, 0)
        end)
        return ok and got or nil
    end
    local S = script:getEngineForce()
    T.check("option off: the stored power is used as it is", used(false, S) == S, tostring(used(false, S)))
    local normal = used(true, S)
    T.check("option on: a normal car gets the 4x (capped at 28000)", normal == math.min(S * 4, 28000), tostring(normal))
    local damaged = used(true, math.floor(S * 0.7))
    T.check("option on: a worn engine (70% power) is boosted from its own value", damaged == math.min(math.floor(S * 0.7) * 4, 28000), tostring(damaged))
    local old = used(true, math.min(S * 4, 28000))
    T.check("option on: a car that spawned with the old boost already in its power is NOT boosted again", old == math.min(S * 4, 28000), tostring(old))
    -- the bug itself, on the same build: switch the guard off (0.2.1 behaviour) and the same car is boosted twice
    BetterVehicleDynamicsMod.testNoBoostGuard = true
    local twice = used(true, math.min(S * 4, 28000))
    BetterVehicleDynamicsMod.testNoBoostGuard = nil
    T.log("the same car with the guard switched off (0.2.1 behaviour): power used " .. tostring(twice))
    T.check("without the guard the same car is boosted a second time (the reported bug)", twice == 28000, tostring(twice))
    setOpt2("RealismHPWeight", false)
end, where)

-- How fast does a plain car pull under the settings that could make a car "do 120 in 3 seconds"? Speed at 3 s from
-- a standstill for stored power x option x sandbox sliders.
T.register("accel_sweep", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    local S = getScriptManager():getVehicle("Base.CarNormal"):getEngineForce()
    -- { label, reference power option, stored power, EnginePower, GripLevel, AccelCeiling }
    local cases = {
        { "default sliders, option on, ceiling 4 (shipped)",   true, S,     1.0, 1.0, 4.0 },
        { "casual-like (power 1.4, grip 1.5), NO ceiling",      true, S,     1.4, 1.5, 0.0 },
        { "casual-like (power 1.4, grip 1.5), ceiling 4",       true, S,     1.4, 1.5, 4.0 },
        { "grip 2.0, NO ceiling",                               true, S,     1.0, 2.0, 0.0 },
        { "grip 2.0, ceiling 4",                                true, S,     1.0, 2.0, 4.0 },
        { "power 5 + grip 2.0 (slider maxima), ceiling 4",      true, S,     5.0, 2.0, 4.0 },
    }
    local function median(t) table.sort(t) return t[math.ceil(#t / 2)] end
    for _, c in ipairs(cases) do
        setOpt2("RealismHPWeight", c[2]); setOpt2("EnginePower", c[4]); setOpt2("GripLevel", c[5]); setOpt2("AccelCeiling", c[6])
        T.wait(2)
        local t50s, v3s, used, lim = {}, {}, nil, nil
        local attempts = 0
        while #t50s < 3 and attempts < 7 do
            attempts = attempts + 1
            local t50, v3
            withCar(p, rx, ry, function(v)
                BetterVehicleDynamicsMod.computed = nil
                local t0 = getTimestampMs()
                T.drive(true, true, 0)
                while getTimestampMs() - t0 < 7000 do
                    local el = (getTimestampMs() - t0) / 1000
                    local sp = math.abs(v:getCurrentSpeedKmHour())
                    if not t50 and sp >= 50 then t50 = el end
                    if not v3 and el >= 3 then v3 = sp end
                    local cc = BetterVehicleDynamicsMod.computed
                    if cc then used = cc.powerUsed or used; lim = cc.driveLimit or lim end
                    coroutine.yield()
                end
                T.drive(true, false, 0)
            end)
            if v3 and v3 > 5 then t50s[#t50s + 1] = t50 or 7.5; v3s[#v3s + 1] = v3 end
        end
        local list = {}
        for _, t in ipairs(t50s) do list[#list + 1] = string.format("%.1f", t) end
        T.log(string.format("%-52s power %6s, drive limit %4.2f/kg   0-50 km/h in %s s (runs %s)   v@3s median %.0f km/h",
            c[1], tostring(used), lim or -1, #t50s > 0 and string.format("%.1f", median(t50s)) or "?", table.concat(list, ", "), #v3s > 0 and median(v3s) or -1))
    end
    setOpt2("RealismHPWeight", false); setOpt2("EnginePower", 1.0); setOpt2("GripLevel", 1.0); setOpt2("AccelCeiling", 4.0)
end, where)

-- The vehicle info panel next to the mechanics window ("Better Vehicle Dynamics": grips, load penalty, Java part...).
-- Run alone and with CleanUI + NeatUI Framework loaded: the panel must exist, be visible, have rows, and sit beside the
-- window. A screenshot of the window is saved for the record.
local function mechBody(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    local cleanUI, rax = false, false
    pcall(function()
        local mods = getActivatedMods()
        for i = 0, mods:size() - 1 do
            local m = tostring(mods:get(i))
            if m:find("CleanUI", 1, true) then cleanUI = true end
            if m:find("RaxUnifiedUI", 1, true) then rax = true end
        end
    end)
    T.log("CleanUI loaded: " .. tostring(cleanUI) .. ", Rax Clean UI 2.0 loaded: " .. tostring(rax))
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60)
    if not T.check("found a road", rx ~= nil) then return end
    p:setX(rx + 0.5); p:setY(ry + 3.5); p:setZ(0)
    p:setLastX(rx + 0.5); p:setLastY(ry + 3.5); p:setLastZ(0)
    T.wait(3)
    local v
    for k = 1, 6 do
        v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
        if v then break end
        T.wait(1.5)
    end
    if not T.check("spawned a car", v ~= nil) then return end
    T.wait(1.5)
    BVDTestsFix(v)
    if not T.check("entered the car", enter(p, v)) then return end
    v:tryStartEngine(true)
    T.waitFor(function() return v:isEngineRunning() end, 8)
    T.wait(1)
    ISVehicleMechanics.cheat = true
    ISVehicleMenu.onMechanic(p, v)
    local ui
    T.check("the mechanics window opens", T.waitFor(function()
        ui = getPlayerMechanicsUI(0)
        return ui and ui:isReallyVisible() or nil
    end, 10) ~= nil)
    T.wait(2.5)
    T.log("mechanics window class: " .. tostring(ui and ui.Type) .. ", prerender is the one BVD wrapped: " .. tostring(ui ~= nil and ui.prerender == ISVehicleMechanics.prerender))
    local panel = ui and ui._bvdPanel
    T.check("BVD created its info panel for the window", panel ~= nil)
    T.check("the info panel is visible", panel ~= nil and panel:isVisible())
    local rows = panel and panel._rows
    T.check("the info panel has rows (grips, load, Java part)", rows ~= nil and #rows >= 5, rows and tostring(#rows) or "no rows")
    if rows then
        for _, r in ipairs(rows) do T.log(string.format("  row: %s = %s", tostring(r[1]), tostring(r[2]))) end
    end
    if panel and ui then
        local beside = panel:getX() >= ui:getX() + ui:getWidth() - 1 or panel:getX() + panel:getWidth() <= ui:getX() + 1
        T.check("the panel sits beside the window, not over it", beside, string.format("window x %d..%d, panel x %d..%d", ui:getX(), ui:getX() + ui:getWidth(), panel:getX(), panel:getX() + panel:getWidth()))
    end
    takeScreenshot(rax and "mechanics_with_rax_cleanui2.png" or (cleanUI and "mechanics_with_cleanui.png" or "mechanics_plain.png"))
    T.wait(1.5)
    if ui then pcall(function() ui:close() end) end
    ISVehicleMechanics.cheat = false
end
T.register("mechanics", mechBody, where)
T.register("mechanics_cleanui", mechBody, where)

-- Tire marks: a new skid must start at the car, not at the end of an earlier skid. Brake hard, move off, build speed
-- and brake again; the second skid's marks may not be drawn from the old spot to the car. Run once with the old
-- behaviour forced (BVD.skidStreakGapMs huge) to show the test sees the bug, and once as shipped.
T.register("skidstreak", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    T.check("the skid mark code is loaded", BVD.skidStats ~= nil and type(BVD.skidStreakContinues) == "function")
    local function scenario(gap)
        BVD.skidStreakGapMs = gap
        local res = {}
        local ok = withCar(p, rx, ry, function(v)
            local function where(tag) T.log(string.format("  %s: speed %.1f km/h, at %.0f,%.0f", tag, math.abs(v:getCurrentSpeedKmHour()), v:getX(), v:getY())) end
            -- first skid: a launch from a standstill drops marks while the car is under 10 km/h with the throttle down
            T.drive(false, false, 0)
            T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 10)
            T.wait(0.6)
            where("first launch")
            res.ax, res.ay = v:getX(), v:getY()
            T.drive(true, true, 0)
            T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) >= 18 end, 10)
            T.drive(true, false, 0)                                  -- stop again, a few tiles further on
            T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 12)
            T.drive(false, false, 0)
            T.wait(0.8)                                              -- well past the streak gap
            res.bx, res.by = v:getX(), v:getY()
            where("second launch")
            BVD.skidStats = { fresh = 0, fills = 0, maxFill = 0 }
            T.drive(true, true, 0)                                   -- second skid
            T.wait(1.0)
            local st = BVD.skidStats
            res.fresh, res.fills, res.maxFill, res.fx, res.fy = st.fresh, st.fills, st.maxFill, st.firstX, st.firstY
            T.drive(true, false, 0)
            T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 12)
            T.drive(false, false, 0)
        end)
        BVD.skidStreakGapMs = nil
        if ok and res.ax and res.bx then res.gap = math.sqrt((res.bx - res.ax) ^ 2 + (res.by - res.ay) ^ 2) end
        return ok and res or nil
    end
    -- the two launches must be 4 to 19 tiles apart (the old code only connects drops closer than 20): try again if not
    local function scenarioInRange(gap)
        local r
        for attempt = 1, 4 do
            r = scenario(gap)
            if r and r.gap and r.gap >= 4 and r.gap <= 19 then return r end
            T.log(string.format("  the launches were %s tiles apart, trying again", r and r.gap and string.format("%.0f", r.gap) or "?"))
        end
        return r
    end
    local function report(tag, r)
        if not r then T.log(tag .. ": the car never got going") return end
        local first = r.fx and math.sqrt((r.fx - r.bx) ^ 2 + (r.fy - r.by) ^ 2) or -1
        T.log(string.format("%s (launches %.0f tiles apart): second skid started with %d fresh streak(s), %d fills, longest fill %.1f tiles, first mark %.1f tiles from the car where the second launch began", tag, r.gap or -1, r.fresh or -1, r.fills or -1, r.maxFill or -1, first))
        return first
    end
    local old = scenarioInRange(1e9)
    local oldFirst = report("old behaviour (every earlier drop connects)", old)
    local new = scenarioInRange(nil)
    local newFirst = report("as shipped", new)
    T.check("old behaviour reproduces the bug: a long fill from the earlier skid", old ~= nil and old.maxFill >= 6, old and string.format("%.1f tiles", old.maxFill) or "no run")
    T.check("as shipped: the new skid starts a fresh streak", new ~= nil and new.fresh >= 1, new and tostring(new.fresh) or "no run")
    T.check("as shipped: no long fill from the earlier skid (longest fill under 2 tiles)", new ~= nil and new.maxFill < 2.0, new and string.format("%.1f tiles", new.maxFill) or "no run")
    T.check("as shipped: the first mark of the skid is at the car (within 4 tiles of where the second launch began)", newFirst ~= nil and newFirst >= 0 and newFirst <= 4.0, newFirst and string.format("%.1f tiles", newFirst) or "no run")
end, where)

-- The info panel when there is no room beside the mechanics window (a small game window, with CleanUI loaded): the
-- placement used before 0.2.2 hid the panel; the current one keeps it on screen. Both are measured in the same run.
T.register("mechanics_narrow", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    local cleanUI = false
    pcall(function()
        local mods = getActivatedMods()
        for i = 0, mods:size() - 1 do if tostring(mods:get(i)):find("CleanUI", 1, true) then cleanUI = true end end
    end)
    T.log(string.format("CleanUI loaded: %s, game window %dx%d", tostring(cleanUI), getCore():getScreenWidth(), getCore():getScreenHeight()))
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60)
    if not T.check("found a road", rx ~= nil) then return end
    p:setX(rx + 0.5); p:setY(ry + 3.5); p:setZ(0)
    p:setLastX(rx + 0.5); p:setLastY(ry + 3.5); p:setLastZ(0)
    T.wait(3)
    local v
    for k = 1, 6 do
        v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
        if v then break end
        T.wait(1.5)
    end
    if not T.check("spawned a car", v ~= nil) then return end
    T.wait(1.5)
    BVDTestsFix(v)
    if not T.check("entered the car", enter(p, v)) then return end
    v:tryStartEngine(true)
    T.waitFor(function() return v:isEngineRunning() end, 8)
    T.wait(1)
    ISVehicleMechanics.cheat = true
    ISVehicleMenu.onMechanic(p, v)
    local ui
    T.check("the mechanics window opens", T.waitFor(function()
        ui = getPlayerMechanicsUI(0)
        return ui and ui:isReallyVisible() or nil
    end, 10) ~= nil)
    local function state(tag)
        T.wait(2.0)
        local panel = ui and ui._bvdPanel
        local vis = panel ~= nil and panel:isVisible()
        T.log(string.format("  %s: window x %d..%d of %d, panel %s%s", tag, ui:getX(), ui:getX() + ui:getWidth(), getCore():getScreenWidth(),
            panel and "exists" or "missing", panel and string.format(", visible=%s at x %d..%d", tostring(vis), panel:getX(), panel:getX() + panel:getWidth()) or ""))
        return vis, panel
    end
    BVD.dockLegacy = true
    local legacyVisible = state("placement before 0.2.2")
    takeScreenshot("mechanics_narrow_before.png")
    T.wait(1)
    BVD.dockLegacy = nil
    local nowVisible, panel = state("placement now")
    takeScreenshot("mechanics_narrow_after.png")
    T.check("the old placement hides the panel when there is no room (the failure)", legacyVisible == false)
    T.check("the current placement keeps the panel visible", nowVisible == true)
    local rows = panel and panel._rows
    T.check("and it still has its rows", rows ~= nil and #rows >= 5)
    if panel then
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        T.check("and it is fully on screen", panel:getX() >= 0 and panel:getY() >= 0 and panel:getX() + panel:getWidth() <= sw and panel:getY() + panel:getHeight() <= sh)
    end
    T.wait(1)
    if ui then pcall(function() ui:close() end) end
    ISVehicleMechanics.cheat = false
end, where)

-- The most extreme launch the settings and mods allow: a modded race-tire profile (road grip 3), GripLevel 2, EnginePower 5,
-- reference power on. With the ceiling off, then as shipped. Median of 3 runs of the time to 50 and to 100 km/h.
T.register("accel_extreme", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    local function median(t) table.sort(t) return t[math.ceil(#t / 2)] end
    local race = { road = 3.0, wet = 3.0, snow = 3.0, offroad = 3.0 }
    local cases = {
        { "default sliders (reference power on)",                       1.0, 1.0, 4.0, false },
        { "EXTREME: race tires 3.0, grip 2.0, power 5, NO ceiling",     5.0, 2.0, 0.0, true },
        { "EXTREME: race tires 3.0, grip 2.0, power 5, ceiling 4",      5.0, 2.0, 4.0, true },
    }
    for _, c in ipairs(cases) do
        setOpt2("RealismHPWeight", true); setOpt2("EnginePower", c[2]); setOpt2("GripLevel", c[3]); setOpt2("AccelCeiling", c[4])
        T.wait(2)
        if c[5] then
            BetterVehicleDynamicsMod.tireProfiles = { NormalTire = race, ModernTire = race, OldTire = race }
        else
            if BVD.publishTireProfiles then BVD.publishTireProfiles() end
        end
        local t50s, t100s, v3s, lim = {}, {}, {}, nil
        local attempts = 0
        while #v3s < 3 and attempts < 7 do
            attempts = attempts + 1
            local t50, t100, v3
            withCar(p, rx, ry, function(v)
                BetterVehicleDynamicsMod.computed = nil
                local t0 = getTimestampMs()
                T.drive(true, true, 0)
                while getTimestampMs() - t0 < 9000 do
                    local el = (getTimestampMs() - t0) / 1000
                    local sp = math.abs(v:getCurrentSpeedKmHour())
                    if not t50 and sp >= 50 then t50 = el end
                    if not t100 and sp >= 100 then t100 = el end
                    if not v3 and el >= 3 then v3 = sp end
                    local cc = BetterVehicleDynamicsMod.computed
                    if cc then lim = cc.driveLimit or lim end
                    coroutine.yield()
                end
                T.drive(true, false, 0)
            end)
            if v3 and v3 > 5 then v3s[#v3s + 1] = v3; t50s[#t50s + 1] = t50 or 9.5; t100s[#t100s + 1] = t100 or 9.5 end
        end
        T.log(string.format("%-58s drive limit %5.2f/kg   0-50 in %.1f s, 0-100 in %.1f s (9.5 = not reached in 9 s), speed at 3 s %.0f km/h (3 runs)",
            c[1], lim or -1, #t50s > 0 and median(t50s) or -1, #t100s > 0 and median(t100s) or -1, #v3s > 0 and median(v3s) or -1))
    end
    setOpt2("RealismHPWeight", false); setOpt2("EnginePower", 1.0); setOpt2("GripLevel", 1.0); setOpt2("AccelCeiling", 4.0)
    if BVD.publishTireProfiles then BVD.publishTireProfiles() end
end, where)

-- A modded car whose own script ships a huge engine force (many do). Vehicle scripts are rewritten before the car is
-- spawned, so its stored power is that value. Time to 50 and to 100 km/h, median of 3 runs, option off and on, at the
-- shipped default ceiling and with the ceiling off.
T.register("accel_hugeforce", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 90)
    if not rx then rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60) end
    if not T.check("found a road", rx ~= nil) then return end
    local sc = getScriptManager():getVehicle("Base.CarNormal")
    local force0 = sc:getEngineForce()
    local function median(t) table.sort(t) return t[math.ceil(#t / 2)] end
    local race = { road = 3.0, wet = 3.0, snow = 3.0, offroad = 3.0 }
    -- { label, script force, reference power option, ceiling, EnginePower, GripLevel, race tires }
    local cases = {
        { "stock force, default sliders",                              force0,  false, 4.0, 1.0, 1.0, false },
        { "modded force 40000, Casual-like (power 1.4, grip 1.5), NO ceiling", 40000,  false, 0.0, 1.4, 1.5, false },
        { "modded force 40000, Casual-like, ceiling 4",                40000,  false, 4.0, 1.4, 1.5, false },
        { "modded force 120000, grip 2.0 + race tires, NO ceiling",    120000, false, 0.0, 1.0, 2.0, true },
        { "modded force 120000, grip 2.0 + race tires, ceiling 4",     120000, false, 4.0, 1.0, 2.0, true },
        { "modded force 120000, power 3, grip 2.0 + race tires, NO ceiling", 120000, false, 0.0, 3.0, 2.0, true },
        { "modded force 120000, power 3, grip 2.0 + race tires, ceiling 4",  120000, false, 4.0, 3.0, 2.0, true },
    }
    for _, c in ipairs(cases) do
        sc:Load("CarNormal", string.format("{ engineForce = %d, }", c[2]))
        setOpt2("RealismHPWeight", c[3]); setOpt2("AccelCeiling", c[4]); setOpt2("EnginePower", c[5]); setOpt2("GripLevel", c[6])
        T.wait(2)
        if c[7] then BetterVehicleDynamicsMod.tireProfiles = { NormalTire = race, ModernTire = race, OldTire = race }
        elseif BVD.publishTireProfiles then BVD.publishTireProfiles() end
        local t50s, t100s, v3s, used, lim = {}, {}, {}, nil, nil
        local attempts = 0
        while #v3s < 3 and attempts < 7 do
            attempts = attempts + 1
            local t50, t100, v3
            withCar(p, rx, ry, function(v)
                BetterVehicleDynamicsMod.computed = nil
                local t0 = getTimestampMs()
                T.drive(true, true, 0)
                while getTimestampMs() - t0 < 9000 do
                    local el = (getTimestampMs() - t0) / 1000
                    local sp = math.abs(v:getCurrentSpeedKmHour())
                    if not t50 and sp >= 50 then t50 = el end
                    if not t100 and sp >= 100 then t100 = el end
                    if not v3 and el >= 3 then v3 = sp end
                    local cc = BetterVehicleDynamicsMod.computed
                    if cc then used = cc.powerUsed or used; lim = cc.driveLimit or lim end
                    coroutine.yield()
                end
                T.drive(true, false, 0)
            end)
            if v3 and v3 > 5 then v3s[#v3s + 1] = v3; t50s[#t50s + 1] = t50 or 9.5; t100s[#t100s + 1] = t100 or 9.5 end
        end
        T.log(string.format("%-56s power %7s, limit %5.2f/kg   0-50 in %.1f s, 0-100 in %.1f s (9.5 = not in 9 s), %.0f km/h at 3 s",
            c[1], tostring(used), lim or -1, #t50s > 0 and median(t50s) or -1, #t100s > 0 and median(t100s) or -1, #v3s > 0 and median(v3s) or -1))
    end
    sc:Load("CarNormal", string.format("{ engineForce = %d, }", force0))
    setOpt2("RealismHPWeight", false); setOpt2("AccelCeiling", 4.0); setOpt2("EnginePower", 1.0); setOpt2("GripLevel", 1.0)
    if BVD.publishTireProfiles then BVD.publishTireProfiles() end
end, where)

-- Clean UI 2.0 (Rax's Reborn) opens its own mechanics window class (NR_VehicleMechanicsPanel, stored in its own table,
-- overriding update/prerender/close/setVisible). Before 0.2.2 BVD only hooked the vanilla class, so this window never got the
-- info panel. The test switch BVD.testNoSubclassWrap restores that behaviour for the "before" half of the run.
T.register("mechanics_rax", function(T)
    T.wait(4)
    local p = getPlayer()
    p:setGodMod(true); p:setGhostMode(true)
    local rax = false
    pcall(function()
        local mods = getActivatedMods()
        for i = 0, mods:size() - 1 do if tostring(mods:get(i)):find("RaxUnifiedUI", 1, true) then rax = true end end
    end)
    T.log("Clean UI 2.0 (Rax) loaded: " .. tostring(rax) .. ", window class NR_VehicleMechanicsPanel present: " .. tostring(NR_VehicleMechanicsPanel ~= nil))
    T.clearCars(p, 300)
    local rx, ry = findLine("blends_street", ROAD.x, ROAD.y, nil, true, 60)
    if not T.check("found a road", rx ~= nil) then return end
    p:setX(rx + 0.5); p:setY(ry + 3.5); p:setZ(0)
    p:setLastX(rx + 0.5); p:setLastY(ry + 3.5); p:setLastZ(0)
    T.wait(3)
    local v
    for k = 1, 6 do
        v = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, getCell():getGridSquare(rx, ry, 0))
        if v then break end
        T.wait(1.5)
    end
    if not T.check("spawned a car", v ~= nil) then return end
    T.wait(1.5)
    BVDTestsFix(v)
    if not T.check("entered the car", enter(p, v)) then return end
    v:tryStartEngine(true)
    T.waitFor(function() return v:isEngineRunning() end, 8)
    T.wait(1)
    local function window()
        local w = NR_VehicleMechanicsPanel and NR_VehicleMechanicsPanel.panels and NR_VehicleMechanicsPanel.panels[0]
        if w and w:isReallyVisible() then return w end
        local u = getPlayerMechanicsUI(0)
        if u and u:isReallyVisible() then return u end
    end
    BVD.testNoSubclassWrap = true      -- the "before": the derived window is not hooked
    ISVehicleMechanics.cheat = true
    ISVehicleMenu.onMechanic(p, v)
    local ui = T.waitFor(window, 12)
    T.check("the mechanics window opens", ui ~= nil)
    if not ui then return end
    T.log("window class: " .. tostring(ui.Type) .. " (a Rax window: " .. tostring(NR_VehicleMechanicsPanel ~= nil and ui == NR_VehicleMechanicsPanel.panels[0]) .. ")")
    T.wait(2.5)
    do
        local mt = getmetatable(NR_VehicleMechanicsPanel)
        T.log(string.format("diagnostic: metatable of the Rax class is ISVehicleMechanics: %s, class already wrapped: %s, _G is a table: %s",
            tostring(mt == ISVehicleMechanics), tostring(NR_VehicleMechanicsPanel.__bvdWrappedClass == NR_VehicleMechanicsPanel), tostring(type(_G))))
        local seen = 0
        local ok, err = pcall(function() for k, v in pairs(_G) do seen = seen + 1 end end)
        T.log("diagnostic: pairs(_G) ok=" .. tostring(ok) .. " entries=" .. tostring(seen) .. (ok and "" or (" error=" .. tostring(err))))
    end
    local before = ui._bvdPanel
    T.log("before (derived window not hooked): info panel " .. (before and ("exists, visible=" .. tostring(before:isVisible())) or "missing"))
    takeScreenshot("mechanics_rax_before.png")
    BVD.testNoSubclassWrap = nil       -- the "after": as shipped
    T.wait(2.5)
    T.log(string.format("diagnostic: isVisible=%s isCollapsed=%s vehicle=%s prerender is the class's own wrapped function: %s, _bvdPanel=%s, sectionEnabled cfg DriverHUD=%s",
        tostring(ui:isVisible()), tostring(ui.isCollapsed), tostring(ui.vehicle), tostring(ui.prerender ~= ISVehicleMechanics.prerender), tostring(ui._bvdPanel),
        tostring(BVD.cfg and BVD.cfg().DriverHUD)))
    local okp, errp = pcall(function() ui:prerender() end)
    T.log("diagnostic: direct prerender call ok=" .. tostring(okp) .. " err=" .. tostring(errp))
    T.log("diagnostic: after a direct prerender call _bvdPanel=" .. tostring(ui._bvdPanel) .. "; sectionEnabled via cfg: " .. tostring(BVD.cfg and BVD.cfg().DriverHUD))
    local panel = ui._bvdPanel
    local rows = panel and panel._rows
    T.log("after (as shipped): info panel " .. (panel and string.format("exists, visible=%s at x %d..%d, window x %d..%d of %d", tostring(panel:isVisible()), panel:getX(), panel:getX() + panel:getWidth(), ui:getX(), ui:getX() + ui:getWidth(), getCore():getScreenWidth()) or "missing"))
    takeScreenshot("mechanics_rax_after.png")
    T.check("before: the Rax window had no info panel (the reported failure)", before == nil or before:isVisible() == false)
    T.check("after: BVD created its info panel for the Rax window", panel ~= nil)
    T.check("after: the info panel is visible", panel ~= nil and panel:isVisible())
    T.check("after: the info panel has rows", rows ~= nil and #rows >= 5, rows and tostring(#rows) or "no rows")
    if panel then
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        T.check("after: it is fully on screen", panel:getX() >= 0 and panel:getY() >= 0 and panel:getX() + panel:getWidth() <= sw and panel:getY() + panel:getHeight() <= sh)
    end
    T.wait(1)
    pcall(function() ui:close() end)
    T.wait(1.5)
    T.check("closing the Rax window removes the info panel", ui._bvdPanel == nil)
    ISVehicleMechanics.cheat = false
end, where)

T.register("others_vanilla", makeBody(false, false, OTHER_CARS), where)   -- run with BVD out of the mod list: the harness baseline
