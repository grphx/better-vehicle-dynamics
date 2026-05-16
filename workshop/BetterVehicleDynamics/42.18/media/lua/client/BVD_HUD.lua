-- BVD_HUD.lua — driver-side HUD readout.
--
-- Shows speed (km/h + mph), RPM, vehicle mass, and engine on/off state
-- whenever the local player is in the driver seat. Hidden otherwise.
-- Sandbox option BetterVehicleDynamics.DriverHUD gates visibility.

require "ISUI/ISPanel"

BVD = BVD or {}

local PANEL_W, PANEL_H = 180, 86
local PADDING_X = 18
local PADDING_Y = 200

BVD_HUDPanel = ISPanel:derive("BVD_HUDPanel")

function BVD_HUDPanel:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor     = { r = 1, g = 1, b = 1, a = 0.25 }
    o:noBackground(false)
    o:setVisible(false)
    return o
end

function BVD_HUDPanel:prerender()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if sv and sv.DriverHUD == false then
        self:setVisible(false)
        return
    end

    local player = getSpecificPlayer(0)
    if not player then self:setVisible(false); return end

    local vehicle = player:getVehicle()
    if not vehicle or vehicle:getDriver() ~= player then
        self:setVisible(false); return
    end

    self.vehicle = vehicle
    self:setVisible(true)
    ISPanel.prerender(self)
end

local function safe(fn, fallback)
    local ok, val = pcall(fn)
    if ok then return val end
    return fallback
end

function BVD_HUDPanel:render()
    if not self.vehicle then return end
    local v = self.vehicle

    local kmh    = safe(function() return v:getCurrentSpeedKmHour() end, 0) or 0
    if kmh < 0 then kmh = -kmh end
    local mph    = kmh * 0.621371
    local rpm    = safe(function() return v:getEngineRPM() end, 0) or 0
    local mass   = safe(function() return v:getMass() end, 0) or 0
    local engine = safe(function() return v:isEngineRunning() end, false)

    local font  = UIFont.Small
    local lh    = 16
    local y     = 6
    local white = { 1, 1, 1, 1 }

    self:drawText(string.format("%3.0f km/h  (%3.0f mph)", kmh, mph),
        10, y, white[1], white[2], white[3], white[4], font); y = y + lh
    self:drawText(string.format("RPM:    %5.0f", rpm),
        10, y, 1, 1, 1, 1, font); y = y + lh
    self:drawText(string.format("Weight: %5.0f kg", mass),
        10, y, 1, 1, 1, 1, font); y = y + lh

    if engine then
        self:drawText("Engine: ON", 10, y, 0.4, 1, 0.4, 1, font)
    else
        self:drawText("Engine: OFF", 10, y, 1, 0.4, 0.4, 1, font)
    end
end

local _instance = nil

local function ensureHUD()
    if _instance then return end
    local screenW = getCore():getScreenWidth()
    local x = screenW - PANEL_W - PADDING_X
    local y = PADDING_Y
    _instance = BVD_HUDPanel:new(x, y, PANEL_W, PANEL_H)
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

function BVD.toggleHUD()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if not sv then return end
    sv.DriverHUD = not sv.DriverHUD
    if sv.DriverHUD then ensureHUD() else destroyHUD() end
end

Events.OnGameStart.Add(ensureHUD)
