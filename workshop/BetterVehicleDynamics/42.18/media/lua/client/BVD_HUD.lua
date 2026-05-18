-- BVD_HUD.lua — driver-side instrument readout.
--
-- A compact corner panel shown only while the local player occupies the
-- driver seat. It surfaces five things the predecessor never grouped this
-- way: travel speed, a derived gear indicator, an engine-revs bar, the
-- laden-vs-rated weight margin, and a one-line grip/surface verdict.
--
-- Display-only. This module never writes vehicle state, never touches
-- physics, and never calls into the Java overhaul. Every Java getter that
-- is not guaranteed to exist on B42.18 is probed exactly once through a
-- cached pcall (project Kahlua rule: probe-and-cache, no per-tick error
-- spam) and the row degrades gracefully — it shows whatever is available
-- and is simply omitted when the engine cannot supply it.
--
-- Visibility is gated by the SAME sandbox toggle the rest of BVD reads:
-- SandboxVars.BetterVehicleDynamics.DriverHUD (surfaced via BVD.cfg()).
--
-- In-panel strings are hard-coded EN, matching how the other BVD client
-- panels draw text (see BVD_VehicleSpawner.lua: literal "Filter:" etc.).
-- No IG_UI.json / no _EN.txt — that would diverge from the sibling
-- convention for live draw text.

require "ISUI/ISPanel"

BVD = BVD or {}

local PANEL_W   = 196
local PANEL_H   = 124
local EDGE_GAP  = 18
local TOP_GAP   = 196

local ROW_H     = 17
local PAD_L     = 12
local PAD_T     = 9
local BAR_H     = 7

-- Revs above this read as "redline" on the bar. Purely a display ceiling;
-- it scales nothing in the sim.
local RPM_FULLSCALE = 4200

-- Crude speed→gear bands (km/h). This is an indicator only — the sim has
-- its own transmission model and is not consulted or altered here.
local GEAR_BANDS = { 14, 32, 54, 80 }

-- One-time probe verdicts for Java getters whose presence we will not
-- assume on B42.18. nil = not yet probed; true/false = cached result.
local probed = {
    rpm     = nil,
    speed   = nil,
    mass    = nil,
    running = nil,
    square  = nil,
}

-- Probe a getter once, cache whether it is callable, return value-or-nil.
-- After the first failure the getter is never invoked again, so a missing
-- method costs one caught exception total, not one per frame.
local function probeGet(key, fn)
    if probed[key] == false then return nil end
    local ok, val = pcall(fn)
    if not ok then
        probed[key] = false
        return nil
    end
    probed[key] = true
    return val
end

BVD_DriverReadout = ISPanel:derive("BVD_DriverReadout")

function BVD_DriverReadout:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0.04, g = 0.05, b = 0.07, a = 0.62 }
    o.borderColor     = { r = 0.55, g = 0.62, b = 0.70, a = 0.30 }
    o:noBackground(false)
    o:setVisible(false)
    -- Cache the font handle once; do not resolve it per frame.
    o.font     = UIFont.Small
    o.fontH    = getTextManager():getFontHeight(o.font)
    o.vehicle  = nil
    return o
end

-- Decide whether the readout should be on-screen this frame. Gated by the
-- existing DriverHUD toggle via BVD.cfg() (falls back to a direct read if
-- the config layer is unavailable for any reason).
function BVD_DriverReadout:shouldShow()
    local enabled = true
    if BVD and BVD.cfg then
        local c = BVD.cfg()
        if c and c.DriverHUD == false then enabled = false end
    else
        local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
        if sv and sv.DriverHUD == false then enabled = false end
    end
    if not enabled then return false end

    local player = getSpecificPlayer(0)
    if not player then return false end

    local vehicle = player:getVehicle()
    if not vehicle then return false end
    if vehicle:getDriver() ~= player then return false end

    self.vehicle = vehicle
    return true
end

function BVD_DriverReadout:prerender()
    if not self:shouldShow() then
        self:setVisible(false)
        self.vehicle = nil
        return
    end
    self:setVisible(true)
    ISPanel.prerender(self)
end

-- Map an absolute speed to a small integer gear, or 0 to mean "no drive
-- band" (used as a neutral/idle marker). Display heuristic only.
local function speedToGear(absKmh)
    if absKmh < 1.5 then return 0 end
    local g = 1
    for i = 1, #GEAR_BANDS do
        if absKmh >= GEAR_BANDS[i] then g = i + 1 end
    end
    return g
end

-- Read the surface the vehicle currently sits on and return a short
-- traction verdict plus a tint. Defensive at every hop: a missing square
-- or properties API just yields the generic "Sealed road" line rather
-- than an error.
local function surfaceVerdict(vehicle)
    local sq = probeGet("square", function() return vehicle:getCurrentSquare() end)
    if not sq then
        return "Surface  --", 0.75, 0.78, 0.82
    end

    local floorWet, isWater = false, false
    pcall(function()
        if sq.getProperties then
            local p = sq:getProperties()
            if p then
                if p.Is and p:Is("WaterSource") then isWater = true end
            end
        end
        if sq.getFloor then
            local f = sq:getFloor()
            if f and f.getProperties then
                local fp = f:getProperties()
                if fp and fp.Is and fp:Is("Wet") then floorWet = true end
            end
        end
    end)

    local rain = false
    pcall(function()
        local cm = getClimateManager and getClimateManager()
        if cm and cm.getPrecipitationIntensity then
            rain = cm:getPrecipitationIntensity() > 0.05
        end
    end)

    if isWater then
        return "Grip  fording", 0.45, 0.70, 1.0
    elseif floorWet or rain then
        return "Grip  reduced (wet)", 1.0, 0.78, 0.35
    end
    return "Grip  firm", 0.55, 0.95, 0.6
end

function BVD_DriverReadout:render()
    local v = self.vehicle
    if not v then return end

    local font  = self.font
    local x     = PAD_L
    local y     = PAD_T
    local labelC = { 0.78, 0.82, 0.88 }

    -- Speed -----------------------------------------------------------
    local kmh = probeGet("speed", function() return v:getCurrentSpeedKmHour() end) or 0
    local abs = kmh
    if abs < 0 then abs = -abs end
    local reversing = kmh < -0.5
    local mph = abs * 0.621371

    self:drawText("Speed", x, y, labelC[1], labelC[2], labelC[3], 1, font)
    local spdStr = string.format("%3.0f km/h  %3.0f mph", abs, mph)
    if reversing then spdStr = "R  " .. spdStr end
    self:drawTextRight(spdStr, self.width - PAD_L, y, 1, 1, 1, 1, font)
    y = y + ROW_H

    -- Gear ------------------------------------------------------------
    local gear = speedToGear(abs)
    local gearStr
    if reversing then
        gearStr = "R"
    elseif gear == 0 then
        gearStr = "N"
    else
        gearStr = tostring(gear)
    end
    self:drawText("Gear", x, y, labelC[1], labelC[2], labelC[3], 1, font)
    self:drawTextRight(gearStr, self.width - PAD_L, y, 0.85, 0.92, 1.0, 1, font)
    y = y + ROW_H

    -- RPM + bar -------------------------------------------------------
    local running = probeGet("running", function() return v:isEngineRunning() end)
    local rpm = probeGet("rpm", function() return v:getEngineRPM() end) or 0
    self:drawText("Revs", x, y, labelC[1], labelC[2], labelC[3], 1, font)
    if probed.rpm == false then
        self:drawTextRight("--", self.width - PAD_L, y, 0.7, 0.7, 0.7, 1, font)
        y = y + ROW_H
    else
        self:drawTextRight(string.format("%4.0f", rpm),
            self.width - PAD_L, y, 1, 1, 1, 1, font)
        y = y + ROW_H

        local barX = x
        local barW = self.width - (PAD_L * 2)
        local frac = rpm / RPM_FULLSCALE
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        -- track
        self:drawRect(barX, y, barW, BAR_H, 0.35, 0.10, 0.11, 0.13)
        -- fill: cool low, amber mid, hot near the top of the display scale
        local fr, fg, fb = 0.40, 0.80, 0.55
        if frac > 0.85 then
            fr, fg, fb = 0.95, 0.35, 0.30
        elseif frac > 0.65 then
            fr, fg, fb = 1.0, 0.75, 0.30
        end
        if running == false then
            fr, fg, fb = 0.45, 0.47, 0.50
        end
        self:drawRect(barX, y, barW * frac, BAR_H, 0.85, fr, fg, fb)
        self:drawRectBorder(barX, y, barW, BAR_H, 0.35, 0.55, 0.6, 0.65)
        y = y + BAR_H + 6
    end

    -- Laden weight vs rated -------------------------------------------
    local mass = probeGet("mass", function() return v:getMass() end)
    self:drawText("Laden", x, y, labelC[1], labelC[2], labelC[3], 1, font)
    if not mass then
        self:drawTextRight("--", self.width - PAD_L, y, 0.7, 0.7, 0.7, 1, font)
    else
        local rated
        pcall(function()
            local scr = v:getScript()
            if scr and scr.getMass then rated = scr:getMass() end
        end)
        local wr, wg, wb = 0.85, 0.90, 0.95
        local wStr
        if rated and rated > 0 then
            local ratio = mass / rated
            if ratio > 1.25 then
                wr, wg, wb = 1.0, 0.55, 0.45      -- heavily overladen
            elseif ratio > 1.05 then
                wr, wg, wb = 1.0, 0.82, 0.40      -- over rated
            end
            wStr = string.format("%d / %d kg", mass, rated)
        else
            wStr = string.format("%d kg", mass)
        end
        self:drawTextRight(wStr, self.width - PAD_L, y, wr, wg, wb, 1, font)
    end
    y = y + ROW_H

    -- Grip / surface --------------------------------------------------
    local gripStr, gr, gg, gb = surfaceVerdict(v)
    self:drawText(gripStr, x, y, gr, gg, gb, 1, font)
end

local _instance = nil

local function ensureHUD()
    if _instance then return end
    local screenW = getCore():getScreenWidth()
    local px = screenW - PANEL_W - EDGE_GAP
    _instance = BVD_DriverReadout:new(px, TOP_GAP, PANEL_W, PANEL_H)
    _instance:initialise()
    _instance:addToUIManager()
    BVD.HUD = _instance
end

local function destroyHUD()
    if _instance then
        _instance:removeFromUIManager()
        _instance = nil
        BVD.HUD = nil
    end
end

-- Flips the sandbox toggle and reflects it immediately. Kept for parity
-- with the previous module's public surface; still the same key.
function BVD.toggleHUD()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if not sv then return end
    sv.DriverHUD = not sv.DriverHUD
    if sv.DriverHUD then ensureHUD() else destroyHUD() end
end

Events.OnGameStart.Add(ensureHUD)
