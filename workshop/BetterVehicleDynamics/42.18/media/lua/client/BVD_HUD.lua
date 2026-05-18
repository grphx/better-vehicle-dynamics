-- BVD_HUD.lua — Better Vehicle Dynamics inspection panel.
--
-- This module no longer draws a free-floating on-screen instrument
-- cluster. Instead it adds a clearly-labelled, read-only "Better Vehicle
-- Dynamics" section INSIDE the game's own vehicle mechanics window
-- (ISVehicleMechanics) — the screen a player already opens to inspect a
-- parked vehicle. Because that window is only ever seen on a stationary
-- vehicle, the section shows STATIC / inspection data (configured power
-- and weight references, the active tuning profile, grip settings, drift
-- and tyre-mark state) rather than any live speed or gear readout.
--
-- DESIGN CONTRACT
-- ---------------
--   * We wrap ISVehicleMechanics:render with a stored-original + call-
--     through. The original is ALWAYS invoked first and is never
--     suppressed, short-circuited, or mutated. Our extra drawing happens
--     afterwards and is wrapped in its own pcall, so a fault in our block
--     can never break or blank the vanilla mechanics window.
--   * We only DRAW (read-only text/rects) into an unused region of that
--     window — the area below the vehicle info box on the left, beside
--     the part overlay. We add no child widgets, register no events on
--     the window, and write no vehicle or sandbox state.
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
-- When that option is off the section is simply not drawn and the
-- vanilla window is left exactly as the game shipped it.

require "Vehicles/ISUI/ISVehicleMechanics"

BVD = BVD or {}

-- ---------------------------------------------------------------------------
-- Layout constants (all local; no per-frame table churn)
-- ---------------------------------------------------------------------------
local PAD       = 6      -- inner text padding
local LINE_PAD  = 2      -- extra spacing between rows
local TITLE_GAP = 4      -- gap under the section heading
local BLOCK_TOP = 10     -- gap below the vanilla info box before our block

-- Tints, hoisted so render allocates no per-frame table.
local C_BORDER = { 0.55, 0.62, 0.70, 0.30 }
local C_BG     = { 0.04, 0.05, 0.07, 0.55 }
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
    script  = nil,
    sMass   = nil,
    fullt   = nil,
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
-- for the surface/info one-liner so it spans the row.

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

-- ---------------------------------------------------------------------------
-- ISVehicleMechanics wrapper
-- ---------------------------------------------------------------------------

-- Cache the font once; never resolve it per frame.
local BVD_FONT = UIFont.Small

-- Decide whether the BVD section should draw at all. Gated by the same
-- DriverHUD toggle the rest of BVD reads.
local function sectionEnabled()
    local cfg = effectiveCfg()
    return cfg.DriverHUD ~= false
end

-- Draw the section into the window. `self` is the ISVehicleMechanics
-- instance; this is only called from the wrapped render, AFTER the
-- original render, and only inside a pcall.
local function drawSection(self)
    if self.isCollapsed then return end
    if not self.vehicle then return end
    if not sectionEnabled() then return end

    -- Rebuild rows only when the window's update tick flagged a change.
    -- buildRows is pure; we cache its result on the instance.
    if self._bvdRows == nil then
        self._bvdRows = buildRows(self.vehicle)
    end
    local rows = self._bvdRows
    if not rows or #rows == 0 then return end

    local lineHgt = getTextManager():getFontHeight(BVD_FONT)

    -- Anchor: directly below the vanilla vehicle info box, on the left
    -- side of the window beside the part overlay. rectY/rectHgt and
    -- xCarTexOffset are vanilla layout fields we only READ.
    local infoBottom = (self.rectY or 0) + (self.rectHgt or 0)
    local x = PAD
    local y = infoBottom + BLOCK_TOP
    local w = (self.xCarTexOffset or 300) - (PAD * 2)
    if w < 120 then return end   -- pathologically narrow window: skip

    -- Total block height: title + a blank gap + one line per row.
    local rowsH  = (#rows) * (lineHgt + LINE_PAD)
    local blockH = PAD + lineHgt + TITLE_GAP + rowsH + PAD

    -- Do not draw past the bottom of the window content.
    local maxY = self:getHeight() - PAD
    if y + blockH > maxY then
        blockH = maxY - y
        if blockH < lineHgt * 3 then return end
    end

    self:drawRect(x, y, w, blockH, C_BG[4], C_BG[1], C_BG[2], C_BG[3])
    self:drawRectBorder(x, y, w, blockH, C_BORDER[4],
        C_BORDER[1], C_BORDER[2], C_BORDER[3])

    local tx = x + PAD
    local ty = y + PAD
    self:drawText("Better Vehicle Dynamics", tx, ty,
        C_TITLE[1], C_TITLE[2], C_TITLE[3], 1, BVD_FONT)
    ty = ty + lineHgt + TITLE_GAP

    local valX = x + math.floor(w * 0.52)
    for i = 1, #rows do
        local row = rows[i]
        if ty + lineHgt > y + blockH - 2 then break end
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

-- Invalidate the cached rows on the window's update tick so configuration
-- or vehicle changes are picked up without per-frame rebuilds. The update
-- method runs far less often than render and is the natural refresh point.
local _origUpdate = ISVehicleMechanics.update
function ISVehicleMechanics:update()
    if _origUpdate then _origUpdate(self) end
    -- Cheap: just drop the cache; the next render rebuilds once.
    self._bvdRows = nil
end

-- Wrap render: original first (never suppressed), then our pcall-isolated
-- section. A fault in drawSection can never reach the vanilla window.
local _origRender = ISVehicleMechanics.render
function ISVehicleMechanics:render()
    if _origRender then _origRender(self) end
    pcall(drawSection, self)
end

print("[BVD] vehicle inspection section installed (mechanics window)")
