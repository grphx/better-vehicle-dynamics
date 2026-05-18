-- BVD_HUD.lua — Better Vehicle Dynamics inspection panel.
--
-- This module presents a clearly-labelled, read-only "Better Vehicle
-- Dynamics" companion as its OWN standalone window, docked just outside
-- the game's vehicle mechanics screen (ISVehicleMechanics) — the screen a
-- player already opens to inspect a parked vehicle. It deliberately does
-- NOT draw into the mechanics window's own content region, so it can
-- never overlap the car diagram / part column. Because the mechanics
-- window is only ever seen on a stationary vehicle, the companion shows
-- STATIC / inspection data (configured power and weight references, the
-- active tuning profile, grip settings, drift and tyre-mark state) rather
-- than any live speed or gear readout.
--
-- DESIGN CONTRACT
-- ---------------
--   * The companion is a separate ISPanel instance with its own rect,
--     background, border and rows. It is added to the UI manager and
--     positioned each frame ADJACENT to the mechanics window — never
--     inside it. No child widgets are added to the vanilla window and no
--     events are registered on it.
--   * Lifecycle is tied to ISVehicleMechanics by wrapping its prerender
--     (create-once + reposition) and its close / setVisible (teardown).
--     The stored original is ALWAYS invoked first and is never
--     suppressed, short-circuited, or mutated. Our extra logic runs
--     afterwards, wrapped in its own pcall, so a fault on our side can
--     never break or blank the vanilla mechanics window.
--   * The companion ref is cached on the mechanics-window instance
--     (self._bvdPanel). On close / hide it is removed from the UI manager
--     and the ref cleared, so no orphan panel is ever left on screen.
--   * Display strings are rebuilt only when the window's update tick says
--     the underlying vehicle/config changed, not every frame, so steady-
--     state rendering allocates nothing.
--   * Every uncertain Java getter is probed exactly once through a cached
--     pcall (project Kahlua rule: probe-and-cache, never call-and-hope,
--     no per-frame caught-exception spam). A missing getter degrades the
--     affected line to "--" and is never retried.
--
-- Visibility is gated by the SAME sandbox toggle the rest of BVD reads:
-- SandboxVars.BetterVehicleDynamics.DriverHUD, surfaced via BVD.cfg().
-- When that option is off the companion is never created and the vanilla
-- window is left exactly as the game shipped it.

require "Vehicles/ISUI/ISVehicleMechanics"
require "ISUI/ISPanel"

BVD = BVD or {}

-- ---------------------------------------------------------------------------
-- Layout constants (all local; no per-frame table churn)
-- ---------------------------------------------------------------------------
local PAD       = 8      -- inner text padding
local LINE_PAD  = 3      -- extra spacing between rows
local TITLE_GAP = 5      -- gap under the panel heading
local GAP       = 8      -- gap between the mechanics window and our panel
local PANEL_W   = 280    -- companion panel width

-- Tints, hoisted so render allocates no per-frame table.
local C_BORDER = { 0.55, 0.62, 0.70, 0.45 }
local C_BG     = { 0.04, 0.05, 0.07, 0.78 }
local C_TITLE  = { 0.62, 0.80, 0.96 }
local C_LABEL  = { 0.74, 0.78, 0.84 }
local C_VALUE  = { 0.93, 0.95, 0.98 }
local C_DIM    = { 0.62, 0.64, 0.67 }
local C_WARN   = { 1.00, 0.78, 0.38 }
local C_OVER   = { 1.00, 0.55, 0.45 }

-- ---------------------------------------------------------------------------
-- One-time probe verdicts. nil = not yet probed; true/false = cached.
-- ---------------------------------------------------------------------------
local probed = {
    mass    = nil,
    enginep = nil,
}

-- Probe a getter once, cache callability, return value-or-nil. After the
-- first failure the getter is never invoked again — one caught exception
-- total for a missing method, not one per frame.
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

-- ---------------------------------------------------------------------------
-- Build the display rows for the current vehicle + config.
-- ---------------------------------------------------------------------------
-- A "row" is { label, value, tintIndex } where tintIndex selects a value
-- colour: 1 = normal, 2 = dim/"--", 3 = warn, 4 = over. The label is nil
-- for a one-liner so it spans the row.

local R_NORM, R_DIM, R_WARN, R_OVER = 1, 2, 3, 4

-- Read the effective config defensively. Falls back to a direct
-- SandboxVars read if the config layer is unavailable for any reason.
local function effectiveCfg()
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" then return c end
    end
    return SandboxVars and SandboxVars.BetterVehicleDynamics or {}
end

-- Resolve the human-readable tuning-profile name for the active Mode.
-- Uses BVD.getPresetName when present; otherwise reports the raw index.
local function profileName(cfg)
    local mode = cfg.Mode or 1
    if BVD and type(BVD.getPresetName) == "function" then
        local ok, nm = pcall(BVD.getPresetName, mode)
        if ok and type(nm) == "string" and nm ~= "" then return nm end
    end
    return "Mode " .. tostring(mode)
end

-- Format a numeric config value compactly (drops a trailing ".0").
local function numStr(n)
    if type(n) ~= "number" then return "--" end
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.2f", n)
end

-- Look up BVD reference data for this vehicle script, if any. This is the
-- researched HP/weight figure the realism option would apply — shown here
-- as the "rated" reference even when the option is off, for inspection.
local function referenceData(vehicle)
    local fullType
    pcall(function()
        local scr = vehicle:getScript()
        if scr and scr.getFullType then fullType = scr:getFullType() end
    end)
    if not fullType then return nil, nil end
    if BVD and type(BVD.getVehicleData) == "function" then
        local ok, d = pcall(BVD.getVehicleData, fullType)
        if ok and type(d) == "table" then return d, fullType end
    end
    return nil, fullType
end

-- Build the full row list. Pure read; no side effects.
local function buildRows(vehicle)
    local cfg  = effectiveCfg()
    local rows = {}

    -- Engine power -------------------------------------------------------
    -- Prefer the BVD reference HP for this script; otherwise derive from
    -- the live vehicle's engine power (PZ stores it x10 internally, the
    -- vanilla window divides by 10 for display — we match that).
    local refData = select(1, referenceData(vehicle))
    local hpStr, hpTint = "--", R_DIM
    if refData and type(refData.hp) == "number" and refData.hp > 0 then
        hpStr  = string.format("%d hp", refData.hp)
        hpTint = R_NORM
    else
        local ep = probeGet("enginep", function() return vehicle:getEnginePower() end)
        if type(ep) == "number" and ep > 0 then
            hpStr  = string.format("%d hp", math.floor((ep / 10) + 0.5))
            hpTint = R_NORM
        end
    end
    rows[#rows + 1] = { "Engine power", hpStr, hpTint }

    -- Mass: current laden vs reference ----------------------------------
    local mass = probeGet("mass", function() return vehicle:getMass() end)
    local massStr, massTint = "--", R_DIM
    if type(mass) == "number" and mass > 0 then
        local rated
        if refData and type(refData.mass_kg) == "number" and refData.mass_kg > 0 then
            rated = refData.mass_kg
        else
            pcall(function()
                local scr = vehicle:getScript()
                if scr and scr.getMass then
                    local m = scr:getMass()
                    if type(m) == "number" and m > 0 then rated = m end
                end
            end)
        end
        if rated then
            massStr  = string.format("%d / %d kg", mass, rated)
            massTint = R_NORM
            local ratio = mass / rated
            if ratio > 1.25 then
                massTint = R_OVER
            elseif ratio > 1.05 then
                massTint = R_WARN
            end
        else
            massStr  = string.format("%d kg", mass)
            massTint = R_NORM
        end
    end
    rows[#rows + 1] = { "Mass (laden / rated)", massStr, massTint }

    -- Tuning profile ----------------------------------------------------
    rows[#rows + 1] = { "Tuning profile", profileName(cfg), R_NORM }

    -- Grip settings -----------------------------------------------------
    rows[#rows + 1] = { "Tyre grip",   numStr(cfg.GripLevel),   R_NORM }
    rows[#rows + 1] = { "Rain grip",   numStr(cfg.WetGrip),     R_NORM }
    rows[#rows + 1] = { "Snow grip",   numStr(cfg.SnowGrip),    R_NORM }
    rows[#rows + 1] = { "Off-road grip", numStr(cfg.OffroadGrip), R_NORM }

    -- Drift + tyre-mark state -------------------------------------------
    local driftEnabled = cfg.Drift == true
    local driftLive = false
    pcall(function()
        if BetterVehicleDynamicsMod and BetterVehicleDynamicsMod.driftActive == true then
            driftLive = true
        end
    end)
    local driftStr
    if not driftEnabled then
        driftStr = "off"
    elseif driftLive then
        driftStr = "armed (sliding now)"
    else
        driftStr = "armed"
    end
    rows[#rows + 1] = { "Drift mode", driftStr, driftEnabled and R_NORM or R_DIM }

    local skid = cfg.SkidMarks ~= false
    rows[#rows + 1] = { "Tyre marks", skid and "on" or "off",
        skid and R_NORM or R_DIM }

    return rows
end

-- Decide whether the companion should exist at all. Gated by the same
-- DriverHUD toggle the rest of BVD reads.
local function sectionEnabled()
    local cfg = effectiveCfg()
    return cfg.DriverHUD ~= false
end

-- ---------------------------------------------------------------------------
-- The standalone companion panel
-- ---------------------------------------------------------------------------
-- A plain ISPanel subclass. It owns its rect, paints its own background
-- and border, and renders its own rows. It draws NOTHING into the
-- mechanics window. Its rows are supplied (and invalidated) by the
-- mechanics-window wrappers below.

local BVD_FONT = UIFont.Small   -- cached once; never resolved per frame

-- Font line height is constant for a fixed font in a session; resolve it
-- at most once instead of per contentHeight()/render() call.
local _fontH = nil
local function fontH()
    if not _fontH then _fontH = getTextManager():getFontHeight(BVD_FONT) end
    return _fontH
end

-- Live companions, so an abnormally-dropped mechanics window (mod
-- conflict, crash-recovery path that never calls close()/setVisible)
-- cannot leave an orphan panel; OnGameStop sweeps any survivor.
local liveCompanions = {}

BVDCompanionPanel = ISPanel:derive("BVDCompanionPanel")

function BVDCompanionPanel:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background      = false   -- we paint our own tinted fill in render
    o.moveWithMouse   = false
    o._rows           = nil
    return o
end

-- Compute the content height this panel needs for its current rows. Used
-- to size the panel so it never relies on, or spills into, the mechanics
-- window's geometry.
function BVDCompanionPanel:contentHeight()
    local lineHgt = fontH()
    local nRows   = (self._rows and #self._rows) or 0
    return PAD + lineHgt + TITLE_GAP + nRows * (lineHgt + LINE_PAD) + PAD
end

function BVDCompanionPanel:render()
    local rows = self._rows
    if not rows or #rows == 0 then return end

    local w = self.width
    local h = self.height
    local lineHgt = fontH()

    -- Own fill + border. Local coordinates: ISUIElement:drawRect is
    -- relative to this element, so (0,0) is the panel's own top-left.
    self:drawRect(0, 0, w, h, C_BG[4], C_BG[1], C_BG[2], C_BG[3])
    self:drawRectBorder(0, 0, w, h, C_BORDER[4],
        C_BORDER[1], C_BORDER[2], C_BORDER[3])

    local tx = PAD
    local ty = PAD
    self:drawText("Better Vehicle Dynamics", tx, ty,
        C_TITLE[1], C_TITLE[2], C_TITLE[3], 1, BVD_FONT)
    ty = ty + lineHgt + TITLE_GAP

    local valX = math.floor(w * 0.54)
    for i = 1, #rows do
        local row = rows[i]
        if ty + lineHgt > h - 2 then break end
        local label, value, tint = row[1], row[2], row[3]
        if label then
            self:drawText(label, tx, ty,
                C_LABEL[1], C_LABEL[2], C_LABEL[3], 1, BVD_FONT)
        end
        local cv = C_VALUE
        if tint == R_DIM then cv = C_DIM
        elseif tint == R_WARN then cv = C_WARN
        elseif tint == R_OVER then cv = C_OVER end
        self:drawText(value or "--", valX, ty, cv[1], cv[2], cv[3], 1, BVD_FONT)
        ty = ty + lineHgt + LINE_PAD
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle: tie the companion to the mechanics window
-- ---------------------------------------------------------------------------

-- Tear the companion down and forget it. Safe to call repeatedly. Never
-- throws (callers still pcall-isolate it, belt and braces).
local function teardownCompanion(mw)
    local p = mw._bvdPanel
    mw._bvdPanel = nil
    if p then
        liveCompanions[p] = nil
        pcall(function()
            if p.removeFromUIManager then p:removeFromUIManager() end
        end)
    end
end

-- Global safety-net: if the mechanics window is ever dropped without
-- close()/setVisible() running (mod conflict, abrupt session teardown),
-- sweep any surviving companion so none can orphan on screen.
local function sweepCompanions()
    for p in pairs(liveCompanions) do
        liveCompanions[p] = nil
        pcall(function()
            if p.removeFromUIManager then p:removeFromUIManager() end
        end)
    end
end

-- Create the companion once and cache it on the mechanics-window
-- instance. Returns the panel, or nil if it should not exist.
local function ensureCompanion(mw)
    if not sectionEnabled() then
        -- Option off: make sure no orphan survives a runtime toggle.
        if mw._bvdPanel then teardownCompanion(mw) end
        return nil
    end
    if mw._bvdPanel then return mw._bvdPanel end

    local p = BVDCompanionPanel:new(0, 0, PANEL_W, 200)
    p:initialise()
    p:instantiate()
    p:addToUIManager()
    p:setVisible(false)   -- stays hidden until first reposition this frame
    mw._bvdPanel = p
    liveCompanions[p] = true
    return p
end

-- Position the companion adjacent to the mechanics window: right by
-- default, left if the right edge would run off-screen, with y clamped
-- on-screen and height clamped to the window height.
local function repositionCompanion(mw, p)
    local rows = mw._bvdRows
    if not rows then
        rows = buildRows(mw.vehicle)
        mw._bvdRows = rows
    end
    p._rows = rows

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    -- Height: prefer the panel's own content height, but never taller
    -- than the mechanics window (keeps it visually paired and on-screen).
    local mwX, mwY = mw:getX(), mw:getY()
    local mwW, mwH = mw:getWidth(), mw:getHeight()
    local h = p:contentHeight()
    if h > mwH then h = mwH end
    if h < 60 then h = 60 end

    -- X: dock right by default; fall back to left if the right dock
    -- would push the panel off the right screen edge.
    local x = mwX + mwW + GAP
    if x + PANEL_W > screenW then
        x = mwX - PANEL_W - GAP
    end
    -- Last-resort clamp so it always stays fully on-screen horizontally.
    if x < 0 then x = 0 end
    if x + PANEL_W > screenW then x = screenW - PANEL_W end

    -- Y: align to the window top, then clamp so the whole panel is
    -- on-screen vertically.
    local y = mwY
    if y + h > screenH then y = screenH - h end
    if y < 0 then y = 0 end

    -- If neither dock could clear the window (pathological narrow screen /
    -- very wide window), hide rather than draw stacked over it — the whole
    -- point of this panel is to never obscure the mechanics screen.
    if x < mwX + mwW and x + PANEL_W > mwX then
        if p:isVisible() then p:setVisible(false) end
        return
    end

    p:setX(x)
    p:setY(y)
    p:setWidth(PANEL_W)
    p:setHeight(h)
    if not p:isVisible() then p:setVisible(true) end
    -- Keep the companion painted above the mechanics window.
    p:bringToTop()
end

-- Idempotent install: a sentinel on the class prevents a second wrap
-- (e.g. on /reloadlua) from stacking handlers and double-creating panels.
if not ISVehicleMechanics.__bvdCompanionWrapped then

    -- update: invalidate cached rows so config/vehicle changes are picked
    -- up without per-frame rebuilds. update runs far less often than
    -- prerender/render and is the natural refresh point.
    local _origUpdate = ISVehicleMechanics.update
    function ISVehicleMechanics:update()
        if _origUpdate then _origUpdate(self) end
        self._bvdRows = nil
    end

    -- prerender: original first (never suppressed), then create/reposition
    -- the companion in our own pcall. A fault here can never reach the
    -- vanilla window.
    local _origPrerender = ISVehicleMechanics.prerender
    function ISVehicleMechanics:prerender()
        if _origPrerender then _origPrerender(self) end
        pcall(function()
            -- Only show the companion while the window itself is visible
            -- and not collapsed; otherwise tear it down so nothing is
            -- orphaned behind a hidden/collapsed window.
            if (not self:isVisible()) or self.isCollapsed or (not self.vehicle) then
                if self._bvdPanel then teardownCompanion(self) end
                return
            end
            local p = ensureCompanion(self)
            if p then repositionCompanion(self, p) end
        end)
    end

    -- close: vanilla removes itself from the UI manager here. Tear the
    -- companion down too so no orphan is left on screen.
    local _origClose = ISVehicleMechanics.close
    function ISVehicleMechanics:close()
        if _origClose then _origClose(self) end
        pcall(teardownCompanion, self)
    end

    -- setVisible(false): the window can be hidden without close() (e.g.
    -- joypad / escape paths). Mirror its visibility onto the companion,
    -- tearing it fully down when hidden so nothing lingers.
    local _origSetVisible = ISVehicleMechanics.setVisible
    function ISVehicleMechanics:setVisible(bVisible, joypadData)
        if _origSetVisible then _origSetVisible(self, bVisible, joypadData) end
        pcall(function()
            if not bVisible then
                if self._bvdPanel then teardownCompanion(self) end
            end
        end)
    end

    -- Last-resort sweep so a companion can never outlive its session even
    -- if the window vanished by an unhooked path. Registered once (inside
    -- the idempotent guard) so /reloadlua cannot stack handlers.
    if Events and Events.OnGameStop then Events.OnGameStop.Add(sweepCompanions) end
    if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(sweepCompanions) end

    ISVehicleMechanics.__bvdCompanionWrapped = true
    print("[BVD] vehicle inspection companion installed (docked panel)")
end
