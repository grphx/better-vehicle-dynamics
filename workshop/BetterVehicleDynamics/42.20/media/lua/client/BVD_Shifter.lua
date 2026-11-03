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

local W, H = 210, 160
local STALL_FLASH_MS = 1200

-- textures: a leather-wrapped knob and a soft halo (clutch amber, stall red); if either fails to load the panel falls
-- back to flat shapes
local tex = nil
local function textures()
    if tex == nil then
        tex = {
            knob = getTexture("media/textures/BVD_shifter_knob.png"),
            glow = getTexture("media/textures/BVD_shifter_glow.png"),
        }
    end
    return tex
end

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
local TOP_Y, MID_Y, BOT_Y = 40, 74, 108
local function slot(self, gear, count)
    local columns = math.ceil(count / 2) + 1   -- the last column carries reverse
    local left, right = 46, W - 46
    local step = (right - left) / math.max(1, columns - 1)
    local function colX(c) return left + (c - 1) * step end
    if gear == -1 then return colX(columns), TOP_Y end
    if gear == 0 then return colX(math.max(1, math.ceil(columns / 2))), MID_Y end
    local c = math.ceil(gear / 2)
    return colX(c), (gear % 2 == 1) and TOP_Y or BOT_Y
end

-- text with a one-pixel shadow so it reads on any road
local function label(self, str, x, y, a, r, g, b)
    self:drawTextCentre(str, x + 1, y + 1, 0, 0, 0, a * 0.8, UIFont.Small)
    self:drawTextCentre(str, x, y, r, g, b, a, UIFont.Small)
end

function BVDShifterPanel:render()
    local mod = BetterVehicleDynamicsMod
    local count = math.max(3, math.min(8, tonumber(mod.gearCount) or 5))
    local gear = tonumber(mod.forceGear) or 0
    local held = mod.clutch == true
    local now = nowMs()
    local flashing = now < self.stallUntil
    local t = textures()

    -- a faint backing, so the thin lines read on a light road
    self:drawRect(0, 0, W, H, 0.17, 0, 0, 0)

    -- gate: one thin line per column and the crossbar
    local columns = math.ceil(count / 2) + 1
    local x1 = slot(self, 1, count)
    local xl = select(1, slot(self, -1, count))
    self:drawRect(x1, MID_Y - 1, xl - x1 + 1, 2, 0.6, 1, 1, 1)
    for c = 1, columns do
        local x = select(1, slot(self, c * 2 - 1, count))
        if c == columns then x = xl end
        self:drawRect(x - 1, TOP_Y, 2, BOT_Y - TOP_Y, 0.6, 1, 1, 1)
    end

    -- small gear labels at the ends of the lines, the current one brighter
    for g = 1, count do
        local x, y = slot(self, g, count)
        label(self, tostring(g), x, (y < MID_Y) and (TOP_Y - 29) or (BOT_Y + 13), (g == gear) and 0.95 or 0.45, 1, 1, 1)
    end
    local rx = slot(self, -1, count)
    label(self, "R", rx, TOP_Y - 29, (gear == -1) and 0.95 or 0.45, 1, 1, 1)

    -- knob, eased toward its slot
    local tx, ty = slot(self, math.max(-1, math.min(gear, count)), count)
    if not self.knobX then self.knobX, self.knobY = tx, ty end
    self.knobX = self.knobX + (tx - self.knobX) * 0.35
    self.knobY = self.knobY + (ty - self.knobY) * 0.35
    local r, g, b, glowA = 0.35, 0.85, 0.45, 0.0
    if held then r, g, b, glowA = 1.0, 0.75, 0.2, 0.95 end
    if flashing then
        r, g, b = 0.95, 0.2, 0.2
        glowA = 0.65 + 0.35 * math.abs(math.sin(now / 140))
    end
    if t.knob then
        local K = 30
        if glowA > 0 and t.glow then self:drawTextureScaled(t.glow, self.knobX - 36, self.knobY - 36, 72, 72, glowA, r, g, b) end
        self:drawTextureScaled(t.knob, self.knobX - K / 2 + 2, self.knobY - K / 2 + 4, K, K, 0.5, 0, 0, 0)   -- shadow
        self:drawTextureScaled(t.knob, self.knobX - K / 2, self.knobY - K / 2, K, K, 1, 1, 1, 1)
    else
        if glowA <= 0 then r, g, b = 0.9, 0.9, 0.92 end
        self:drawRect(self.knobX - 7, self.knobY - 7, 14, 14, 1, r, g, b)
        self:drawRectBorder(self.knobX - 7, self.knobY - 7, 14, 14, 1, 0, 0, 0)
    end

    -- clutch light and stall text
    if flashing then
        label(self, getText("IGUI_BVD_ShifterStalled"), W / 2, H - 17, 1, 0.95, 0.25, 0.25)
    elseif held then
        label(self, getText("IGUI_BVD_ShifterClutch"), W / 2, H - 17, 1, 1.0, 0.75, 0.2)
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
    if player.getPlayerNum and player:getPlayerNum() ~= 0 then return end   -- the bridge is shared: player 1 drives the clutch
    local mod = BetterVehicleDynamicsMod
    if not clutchActive(player) then
        mod.clutch = false
        mod.stallRequested = false   -- a request left over from the tick the driver got out must not stop the next engine
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
        local queued = ISTimedActionQueue and ISTimedActionQueue.hasActionType and ISTimedActionQueue.hasActionType(player, "ISShutOffVehicleEngine")
        if vehicle and vehicle:isEngineRunning() and ISShutOffVehicleEngine and ISTimedActionQueue and not queued then
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
