-- Replaces Ki5.lua "mechanics": the vehicle info panel next to the mechanics window ("Better Vehicle Dynamics": grips,
-- load penalty, Java part...) exists, is visible, has rows, and sits beside the window.
-- NEW, not in the old suite: the panel stays visible and on screen with the window pushed to either screen edge. That is
-- NOT the old "mechanics_narrow" case (no side fits, the overlap fallback must fire); that case needs a small game
-- window and is not ported (the pure geometry is covered in bvd_pure_logic).
-- Not ported: "mechanics_cleanui" (needs the CleanUI mods as dependencies) and the screenshot-only parts.
local MOD_ID = "BetterVehicleDynamics"
local SPOT = { x = 10586, y = 11180, z = 0 }

-- ---- helpers shared by the BVD scenarios (each scenario file is standalone, so they are copied into each) ----
-- Game calls only happen inside functions that setup / run call, never at file load.

-- Make a debug-spawned car drivable: debug spawns come in random condition (dead battery, empty tank, locked doors).
-- (Ported from the old BVDTests/shared/Fix.lua.)
local function fixCar(v)
    v:repair()
    local tank = v:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(tank:getContainerCapacity())
        v:transmitPartModData(tank)
    end
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        local door = part:getDoor()
        if door and door:isLocked() then
            door:setLocked(false)
            v:transmitPartDoor(part)
        end
    end
    local bat = v:getPartById("Battery")
    if bat and bat:getInventoryItem() then
        bat:getInventoryItem():setUsedDelta(1.0)
        v:transmitPartUsedDelta(bat)
    end
end

-- Remove every parked vehicle within radius of the player (singleplayer: directly).
local function clearCars(p, radius)
    local gone = {}
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        if math.abs(v:getX() - p:getX()) < radius and math.abs(v:getY() - p:getY()) < radius then gone[#gone + 1] = v end
    end
    for _, v in ipairs(gone) do v:permanentlyRemove() end
    return #gone
end

-- Put the player in the driver seat the way ISEnterVehicle ends up (start + perform), without the walk-up.
local function seat(S, p, v)
    v:enter(0, p)
    v:setCharacterPosition(p, 0, "inside")
    v:transmitCharacterPosition(0, "inside")
    v:playPassengerAnim(0, "idle")
    triggerEvent("OnEnterVehicle", p)
    return S.waitFor(function() return p:getVehicle() == v or nil end, 6) ~= nil
end

-- Spawn Base.CarNormal 4 tiles east of the player, fix it, seat the player, start the engine.
-- Returns the car, or nil and the step that failed.
local function newCar(S, p, script)
    local x, y = math.floor(p:getX()) + 4, math.floor(p:getY())
    local v
    for _ = 1, 6 do
        v = addVehicleDebug(script or "Base.CarNormal", IsoDirections.E, nil, getCell():getGridSquare(x, y, 0))
        if v then break end
        S.wait(1.5)
    end
    if not v then return nil, "spawn" end
    S.wait(1.5)
    fixCar(v)
    S.wait(0.5)
    if not seat(S, p, v) then v:permanentlyRemove() return nil, "seat" end
    v:tryStartEngine(true)
    if not S.waitFor(function() return v:isEngineRunning() or nil end, 10) then
        return v, "engine"
    end
    S.wait(1)
    v:setPhysicsActive(true, true)
    S.wait(0.5)
    return v
end

-- Get out and remove the car, so the next case starts clean.
local function dropCar(S, p, v)
    if p:getVehicle() ~= nil then
        ISVehicleMenu.onExit(p)
        S.waitFor(function() return p:getVehicle() == nil or nil end, 10)
    end
    ISTimedActionQueue.clear(p)   -- a finished exit action must not stop() against a removed car
    S.wait(0.4)
    v:permanentlyRemove()
    S.wait(1)
end

-- Set a BVD sandbox option the way a settings change does, and drop BVD's cached config.
local function setOpt(name, value)
    SandboxVars.BetterVehicleDynamics[name] = value
    getSandboxOptions():updateFromLua()
    BVD.invalidateConfigCache()
end

-- Wait until BVD's per-tick readout (published only by BVD's own drivetrain, never by vanilla) shows up.
local function readout(S, sec)
    local mod = BetterVehicleDynamicsMod
    mod.computed = nil
    return S.waitFor(function()
        local c = mod.computed
        if type(c) == "table" and type(c.gripRoad) == "number" then return c end
        return nil
    end, sec or 10)
end

local function layerOn()
    return type(BVD_zombieBuddyActive) == "function" and BVD_zombieBuddyActive() == true
end
-- ---- end of shared helpers ----


local car

ZomboTest.scenario{
    id = "bvd_info_panel",
    description = "The BVD info panel opens beside the mechanics window with its rows, and stays fully on screen when the window sits at either edge.",
    tags = {"bvd", "ui", "mechanics", "v0.2.2"},
    modes = {"sp"},
    startAt = SPOT,

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.wait(4)
        S.need("ZombieBuddy layer is active", layerOn(), "BVD_zombieBuddyActive = " .. tostring(BVD_zombieBuddyActive))
        S.need("mechanics UI exists", ISVehicleMechanics ~= nil and ISVehicleMenu ~= nil and type(getPlayerMechanicsUI) == "function")
        local p = S.player()
        p:setGodMod(true)
        p:setGhostMode(true)
        clearCars(p, 200)
        local v, why = newCar(S, p)
        if not S.need("test car spawned, seated and engine running", v ~= nil and why == nil, tostring(why)) then return end
        car = v
    end,

    run = function(S)
        local p = S.player()
        local v = car
        ISVehicleMechanics.cheat = true
        ISVehicleMenu.onMechanic(p, v)
        local ui
        local opened = S.waitFor(function()
            ui = getPlayerMechanicsUI(0)
            return ui and ui:isReallyVisible() or nil
        end, 10)
        S.check("the mechanics window opens", opened ~= nil)
        if opened == nil then ISVehicleMechanics.cheat = false return end
        S.wait(2.5)

        local panel = ui._bvdPanel
        S.check("BVD created its info panel for the window", panel ~= nil)
        S.check("the info panel is visible", panel ~= nil and panel:isVisible())
        local rows = panel and panel._rows
        S.check("the info panel has rows (grips, load, Java part)", rows ~= nil and #rows >= 5, rows and tostring(#rows) or "no rows")
        if rows then
            for _, r in ipairs(rows) do S.observe(string.format("row: %s = %s", tostring(r[1]), tostring(r[2]))) end
        end
        if panel then
            local beside = panel:getX() >= ui:getX() + ui:getWidth() - 1 or panel:getX() + panel:getWidth() <= ui:getX() + 1
            S.check("the panel sits beside the window, not over it", beside,
                string.format("window x %d..%d, panel x %d..%d", ui:getX(), ui:getX() + ui:getWidth(), panel:getX(), panel:getX() + panel:getWidth()))
        end
        S.still("bvd_info_panel")

        -- push the window to each screen edge in turn: the panel has to stay visible and fully on screen
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        S.observe(string.format("game window %dx%d, mechanics window %dx%d", sw, sh, ui:getWidth(), ui:getHeight()))
        for _, edge in ipairs({ "right", "left" }) do
            ui:setX(edge == "right" and (sw - ui:getWidth()) or 0)
            S.wait(2)
            local pn = ui._bvdPanel
            local vis = pn ~= nil and pn:isVisible()
            S.check("window at the " .. edge .. " edge: the panel is still visible", vis == true)
            if pn then
                local on = pn:getX() >= 0 and pn:getY() >= 0 and pn:getX() + pn:getWidth() <= sw and pn:getY() + pn:getHeight() <= sh
                S.check("window at the " .. edge .. " edge: the panel is fully on screen", on,
                    string.format("panel %d,%d %dx%d on %dx%d", pn:getX(), pn:getY(), pn:getWidth(), pn:getHeight(), sw, sh))
            end
        end
        S.check("ZombieBuddy layer survived", layerOn())
        ui:close()
        ISVehicleMechanics.cheat = false
    end,
}
