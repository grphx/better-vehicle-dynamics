-- BVD_Shifter.lua  (client)
--
-- Manual clutch, driver side:
--   * reads the clutch key and hands it to the Java ("clutch" on the BetterVehicleDynamicsMod bridge table);
--   * shows a small H-pattern shifter while you drive a manual car with the Manual clutch option: the knob
--     slides to the gear you are in (R, N, 1..n), turns amber while the clutch is held, flashes red on a stall;
--   * stops the engine when the Java asks for a stall, through the game's own shut-off action, so the engine
--     state reaches every player the usual way.
-- Pure Lua; nothing here runs unless manual shifting and the Manual clutch option are both on.

require "ISUI/ISPanel"

BVD = BVD or {}

BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}

local W, H = 132, 120
local STALL_FLASH_MS = 1200

local function nowMs()
    return getTimestampMs and getTimestampMs() or 0
end

local function cfg()
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" then return c end
    end
    return nil
end

--- True while the local player drives a vehicle with the manual clutch active.
local function clutchActive(player)
    local mod = BetterVehicleDynamicsMod
    if not (player and mod.manualShift) then return false end
    local vehicle = player:getVehicle()
    if not (vehicle and vehicle:isDriver(player)) then return false end
    local c = cfg()
    return c ~= nil and c.ManualClutch == true
end

-- ---------------------------------------------------------------------------
-- the panel

BVDShifterPanel = ISPanel:derive("BVDShifterPanel")

function BVDShifterPanel:new(x, y)
    local o = ISPanel.new(self, x, y, W, H)
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.knobX, o.knobY = nil, nil
    o.stallUntil = 0
    return o
end

-- Gate geometry: forward gears go in pairs per column (odd on top, even below), reverse sits top right after the
-- last column, neutral is the channel between the rows.
local function slot(self, gear, count)
    local columns = math.ceil(count / 2) + 1   -- the last column carries reverse
    local left, right = 18, W - 18
    local step = (right - left) / math.max(1, columns - 1)
    local topY, midY, botY = 30, 62, 94
    local function colX(c) return left + (c - 1) * step end
    if gear == -1 then return colX(columns), topY end
    if gear == 0 then return colX(math.max(1, math.ceil(columns / 2))), midY end
    local c = math.ceil(gear / 2)
    return colX(c), (gear % 2 == 1) and topY or botY
end

function BVDShifterPanel:render()
    local mod = BetterVehicleDynamicsMod
    local count = math.max(3, math.min(8, tonumber(mod.gearCount) or 5))
    local gear = tonumber(mod.forceGear) or 0
    local held = mod.clutch == true
    local now = nowMs()
    local flashing = now < self.stallUntil

    -- plate
    self:drawRect(0, 0, W, H, 0.55, 0.05, 0.05, 0.06)
    self:drawRectBorder(0, 0, W, H, 0.7, 0.35, 0.35, 0.38)

    -- gate: a vertical slot per column and the horizontal channel
    local columns = math.ceil(count / 2) + 1
    local x1 = slot(self, 1, count)
    local xl = select(1, slot(self, -1, count))
    self:drawRect(x1 - 1, 62, xl - x1 + 2, 3, 0.9, 0.22, 0.22, 0.25)
    for c = 1, columns do
        local x = select(1, slot(self, c * 2 - 1, count))
        if c == columns then x = xl end
        self:drawRect(x - 1, 30, 3, 66, 0.9, 0.22, 0.22, 0.25)
    end

    -- labels
    for g = 1, count do
        local x, y = slot(self, g, count)
        self:drawTextCentre(tostring(g), x, (y < 62) and 10 or 100, 0.7, 0.7, 0.72, 1, UIFont.Small)
    end
    local rx = slot(self, -1, count)
    self:drawTextCentre("R", rx, 10, 0.7, 0.7, 0.72, 1, UIFont.Small)

    -- knob, eased toward its slot
    local tx, ty = slot(self, math.max(-1, math.min(gear, count)), count)
    if not self.knobX then self.knobX, self.knobY = tx, ty end
    self.knobX = self.knobX + (tx - self.knobX) * 0.35
    self.knobY = self.knobY + (ty - self.knobY) * 0.35
    local r, g, b = 0.35, 0.85, 0.45
    if held then r, g, b = 1.0, 0.75, 0.2 end
    if flashing then r, g, b = 0.95, 0.2, 0.2 end
    self:drawRect(self.knobX - 7, self.knobY - 7, 14, 14, 1, r, g, b)
    self:drawRectBorder(self.knobX - 7, self.knobY - 7, 14, 14, 1, 0, 0, 0)

    -- clutch light and stall text
    self:drawText(held and getText("IGUI_BVD_ShifterClutch") or "", 6, H - 16, 1.0, 0.75, 0.2, 1, UIFont.Small)
    if flashing then
        self:drawTextCentre(getText("IGUI_BVD_ShifterStalled"), W / 2, H - 16, 0.95, 0.25, 0.25, 1, UIFont.Small)
    end
end

-- ---------------------------------------------------------------------------
-- lifecycle

local panel = nil

local function hidePanel()
    if panel then
        panel:removeFromUIManager()
        panel = nil
    end
end

local function showPanel()
    if panel then return end
    local x = getCore():getScreenWidth() - W - 24
    local y = getCore():getScreenHeight() - H - 150
    panel = BVDShifterPanel:new(x, y)
    panel:initialise()
    panel:instantiate()
    panel.javaObject:setConsumeMouseEvents(false)   -- a readout, not a button: clicks pass through
    panel:addToUIManager()
end

local function onPlayerUpdate(player)
    if not player or not player.isLocalPlayer or not player:isLocalPlayer() then return end
    local mod = BetterVehicleDynamicsMod
    if not clutchActive(player) then
        mod.clutch = false
        hidePanel()
        return
    end

    -- the clutch pedal
    local bind = mod.clutchBind
    local key = bind and bind.getValue and bind:getValue()
    mod.clutch = (key ~= nil and isKeyDown(key)) or false
    if BVD and BVD.testClutch ~= nil then mod.clutch = BVD.testClutch end   -- test hook: hold the clutch without a keyboard

    showPanel()

    -- a stall asked for by the physics: stop the engine the way the game's own shut-off does
    if mod.stallRequested then
        mod.stallRequested = false
        local vehicle = player:getVehicle()
        if vehicle and vehicle:isEngineRunning() and ISShutOffVehicleEngine and ISTimedActionQueue then
            ISTimedActionQueue.add(ISShutOffVehicleEngine:new(player))
            if panel then panel.stallUntil = nowMs() + STALL_FLASH_MS end
        end
    end
end

--- Test hook: is the on-screen shifter up?
function BVD.shifterShown() return panel ~= nil end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end
if Events and Events.OnGameStop then Events.OnGameStop.Add(hidePanel) end
if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(hidePanel) end

return {}
