-- Vanilla-physics baseline (no BVD): how do these cars drive, on road and on grass, with the opt-in "reference power and weight"
-- option off ("ki5") and on ("ki5_real")? Measures, per car and surface: the mass and engine power the game uses,
-- and the speed after 3 s and 6 s of full throttle from a standstill. Needs the KI5 mods + damnlib in the mod
-- list (scratch config), so it is a measurement tool, not part of the regular suite.
require "PZAutotest/Runner"

local T = PZAutotest
local CARS = { "Base.CarNormal", "Base.63beetle", "Base.91nissan240sx", "Base.78lamboCountachLP400", "Base.89fordBronco" }
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

local function measure(p, script, surface, x, y)
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
    for _, id in ipairs({ "GasTank" }) do
        local part = v:getPartById(id)
        if part then part:setContainerContentAmount(part:getContainerCapacity()) end
    end
    v:repair()
    local bat = v:getPartById("Battery")
    if bat and bat:getInventoryItem() then bat:getInventoryItem():setUsedDelta(1.0) end
    if not enter(p, v) then T.log(string.format("%-28s %-5s could not enter", script, surface)) v:permanentlyRemove() return end
    v:tryStartEngine(true)
    local started = T.waitFor(function() return v:isEngineRunning() end, 8)
    if not started then T.log(string.format("%-28s %-5s engine would not start", script, surface)) ISVehicleMenu.onExit(p) v:permanentlyRemove() return end
    T.wait(1)
    local x0, y0 = v:getX(), v:getY()
    local t0 = getTimestampMs()
    local v3, v6, t30
    T.drive(true, true, 0)
    while getTimestampMs() - t0 < 5000 do
        local s = math.abs(v:getCurrentSpeedKmHour())
        local el = (getTimestampMs() - t0) / 1000
        if not t30 and s >= 30 then t30 = el end
        if not v3 and el >= 3 then v3 = s end
        coroutine.yield()
    end
    v6 = math.abs(v:getCurrentSpeedKmHour())
    local dist = math.sqrt((v:getX() - x0) ^ 2 + (v:getY() - y0) ^ 2)
    local mass, power = v:getMass(), v:getEnginePower()
    T.drive(true, false, 0)
    T.waitFor(function() return math.abs(v:getCurrentSpeedKmHour()) < 1 end, 20)
    T.drive(false, false, 0)
    ISVehicleMenu.onExit(p)
    T.waitFor(function() return p:getVehicle() == nil end, 5)
    v:permanentlyRemove()
    T.log(string.format("%-28s %-5s mass %5.0f  power %6.0f  v@3s %5.1f  v@6s %5.1f  t->30 %s  dist %4.1f",
        script, surface, mass, power, v3 or -1, v6, t30 and string.format("%.1fs", t30) or "never", dist))
    T.wait(1)
end

local function makeBody()
    return function(T)
        T.wait(4)
        local p = getPlayer()
        p:setGodMod(true)
        p:setGhostMode(true)
        T.log("vanilla physics: BVD loaded = " .. tostring(getActivatedMods():contains("BetterVehicleDynamics")))
        T.clearCars(p, 300)

        local rx, ry = findLine("blends_street", ROAD.x, ROAD.y)
        rx, ry = rx or ROAD.x, ry or ROAD.y
        local cx, cy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry } }, true)
        local gx, gy = findLine("blends_natural_01", ROAD.x, ROAD.y, { { x = rx, y = ry }, { x = cx or -999, y = cy or -999 } }, false)
        T.log(string.format("road start %s,%s   clear grass %s,%s   overgrown grass %s,%s", tostring(rx), tostring(ry), tostring(cx), tostring(cy), tostring(gx), tostring(gy)))
        if cx then T.log("  clear grass objects: " .. describe(cx, cy)) end
        if gx then T.log("  overgrown grass objects: " .. describe(gx, gy)) end
        T.check("found a clear grass patch", cx ~= nil)
        for _, script in ipairs(CARS) do
            if getScriptManager():getVehicle(script) then
                measure(p, script, "road", rx, ry)
                if cx then measure(p, script, "clear", cx, cy) end
                if gx then measure(p, script, "grass", gx, gy) end
            else
                T.log(script .. ": script not loaded")
            end
        end
    end
end

local where = { startLoc = { x = ROAD.x, y = ROAD.y, z = 0 } }
T.register("grass", makeBody(), where)
