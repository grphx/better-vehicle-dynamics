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
local function findLine(prefix, cx, cy, avoid, strict)
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
    for _, id in ipairs({ "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }) do
        -- fit a tire on every wheel: the debug spawner sometimes leaves a car without tires, and such a car cannot
        -- move whatever the physics does
        local part = v:getPartById(id)
        if part then
            local item = instanceItem("Base.NormalTire2")
            item:setCondition(100)
            part:setInventoryItem(item)
            part:setCondition(100)
            v:transmitPartItem(part)   -- what the game's own install action does after changing a part's item
        end
    end
    pcall(function() v:updatePartStats() end)
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
                        if n.force < math.min(o.force * 4, 28000) - 1 or n.mass < o.mass - 1 or n.mass > 1700 + 1 then ruleOk = false; ruleBad[#ruleBad + 1] = name .. " (registered)" end
                    else
                        if math.abs(n.force - math.min(o.force * 4, 28000)) > 1 or math.abs(n.mass - o.mass) > 1 then ruleOk = false; ruleBad[#ruleBad + 1] = name .. " (unregistered)" end
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
                elseif force > math.max(28000, f) then why = "above the power ceiling"
                elseif mass ~= nil and (type(mass) ~= "number" or mass ~= mass) then why = "mass not a number"
                elseif mass ~= nil and mass < m then why = "lighter than its script"
                elseif mass ~= nil and mass > math.max(1700, m) then why = "above the mass cap"
                elseif not spec and (mass ~= nil or force ~= math.min(f * 4, 28000) and force ~= f) then why = "unregistered car treated differently"
                elseif force ~= force2 or mass ~= mass2 then why = "not repeatable" end
                if why and #bad < 8 then bad[#bad + 1] = string.format("f=%s m=%s spec#%d: %s (-> %s, %s)", f, m, si, why, tostring(force), tostring(mass)) end
            end
        end
    end
    T.log(string.format("%d combinations of script force, mass and registration checked", n))
    T.check("realism rules hold for every combination", #bad == 0, table.concat(bad, " | "))
    local f, m = BVD.realismTarget(4000, 1000, nil)
    T.check("an ordinary unregistered car gets the plain gain and keeps its mass", f == 16000 and m == nil, tostring(f) .. "/" .. tostring(m))
    f = BVD.realismTarget(15000, 1000, nil)
    T.check("an already strong engine is capped, not quadrupled", f == 28000, tostring(f))
    local _, hm = BVD.realismTarget(4000, 2600, { hp = 200, mass_kg = 1500 })
    T.check("a registered heavy truck is not made lighter", hm == 2600, tostring(hm))
end

local where = { startLoc = { x = ROAD.x, y = ROAD.y, z = 0 } }
T.register("rules", rulesBody, where)
T.register("ki5_probe", probeBody, where)
T.register("ki5_sweep", sweepBody, where)
T.register("ki5", makeBody(false), where)
T.register("ki5_real", makeBody(true, false), where)
T.register("ki5_unreg", makeBody(true, true), where)
T.register("others", makeBody(false, false, OTHER_CARS), where)
T.register("others_real", makeBody(true, true, OTHER_CARS), where)
T.register("others_nowake", function(T) WAKE = false; return makeBody(false, false, OTHER_CARS)(T) end, where)
T.register("others_vanilla", makeBody(false, false, OTHER_CARS), where)   -- run with BVD out of the mod list: the harness baseline
