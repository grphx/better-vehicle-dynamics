-- BVD_Config.lua — thin accessor for effective sandbox configuration.
--
-- PURPOSE
-- -------
-- Returns a normalized, read-only snapshot of every BetterVehicleDynamics
-- sandbox option, post-preset. Call BVD.cfg() wherever you need the current
-- effective value of any BVD knob without hard-coding SandboxVars key names.
-- Intended primarily for P6/API consumers and as the single place that lists
-- all 29 canonical key names with their defaults.
--
-- PARITY-FIRST DESIGN NOTE
-- ------------------------
-- This module is ADDITIVE. The preset cascade lives in BVD_Presets.lua and
-- runs at OnGameStart; it writes chosen preset values back into SandboxVars
-- before Java reads them. BVD_Config.cfg() simply reads whatever is in
-- SandboxVars at call time — it does not replace, bypass, or fight the preset
-- cascade. Existing physics/overhaul modules continue to read SandboxVars
-- directly; they are NOT rewired through BVD.cfg(). That would change the
-- execution model and risk parity. cfg() is a utility, not a plumbing change.
--
-- GRIPLEVEL COLLAPSE (PREDECESSOR PARITY NOTE)
-- --------------------------------------------
-- The predecessor mod's original two-knob model exposed two separate traction
-- knobs: an overall-traction value (preset values 1.5/1.0/0.75 across
-- Casual/Realistic/Hardcore) and an acceleration-traction value (1.3/1.0/0.8).
-- BVD intentionally collapses both into the single GripLevel key. The
-- overall-traction value is used as GripLevel because the overall cornering
-- traction budget dominates driving feel; the acceleration sub-knob is folded
-- in. The GripLevel sandbox default of 1.0 matches the predecessor's
-- overall-traction "Custom" default, preserving out-of-the-box feel parity.
-- This is the intentional and reviewed parity choice; do NOT re-split
-- GripLevel back into two knobs without a design review.

BVD = BVD or {}

--- Returns a table of every effective BVD option value.
-- Reads SandboxVars.BetterVehicleDynamics at call time (after any preset
-- cascade has already run), falls back to the sandbox-options.txt default for
-- any nil key. Pure read — no sandbox writes, no side effects.
-- @return table  { Mode, DriverHUD, SkidMarks, EnginePower, ... }
function BVD.cfg()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics

    -- Helper: read a numeric key with a fallback default.
    local function num(key, default)
        local v = sv and sv[key]
        return (type(v) == "number") and v or default
    end

    -- Helper: read a boolean key. When the sandbox default is TRUE we use the
    -- "not false" idiom so a missing key returns the right default. When the
    -- sandbox default is FALSE we require an explicit true to avoid false
    -- positives on nil.
    local function boolTrue(key)   -- default = true
        return sv == nil or sv[key] ~= false
    end
    local function boolFalse(key)  -- default = false
        return sv ~= nil and sv[key] == true
    end

    return {
        -- General
        Mode            = num("Mode", 1),           -- enum 1..4; 1 = Custom
        DriverHUD       = boolTrue("DriverHUD"),    -- default true
        SkidMarks       = boolTrue("SkidMarks"),    -- default true

        -- Drivetrain
        EnginePower     = num("EnginePower",    1.0),
        LowSpeedGrunt   = num("LowSpeedGrunt",  2.5),
        ReverseTopSpeed = num("ReverseTopSpeed", 25),

        -- Grip
        -- GripLevel is the collapse of the predecessor's overall-traction +
        -- acceleration-traction knobs into one (see parity note in header).
        -- Default 1.0 == the predecessor's overall-traction "Custom" default.
        GripLevel       = num("GripLevel",       1.0),
        WetGrip         = num("WetGrip",         0.7),
        SnowGrip        = num("SnowGrip",        0.45),
        OffroadGrip     = num("OffroadGrip",     0.85),

        -- Resistance
        Drag                  = num("Drag",                  1.0),
        RollResistance        = num("RollResistance",        1.0),
        RollResistanceOffroad = num("RollResistanceOffroad", 1.8),

        -- Realism
        RealismHPWeight = boolFalse("RealismHPWeight"), -- default false
        TrunkScaling    = boolFalse("TrunkScaling"),    -- default false
        TrunkCar        = num("TrunkCar",     1.0),
        TrunkVan        = num("TrunkVan",     1.0),
        TrunkTruck      = num("TrunkTruck",   1.0),
        TrunkTrailer    = num("TrunkTrailer", 1.0),

        -- Driving QoL
        ThrottleStart = boolTrue("ThrottleStart"), -- default true
        KeylessTow    = boolTrue("KeylessTow"),    -- default true

        -- Impacts
        ShoveFoliage = num("ShoveFoliage", 1.0),
        ShoveZombies = num("ShoveZombies", 1.0),
        ShoveCorpses = num("ShoveCorpses", 1.0),

        -- Drift
        Drift         = boolFalse("Drift"),          -- default false
        DriftGrip     = num("DriftGrip",     0.35),
        DriftMinSpeed = num("DriftMinSpeed", 20),
        DriftSteer    = num("DriftSteer",    1.5),
        DriftRotation = num("DriftRotation", 2000),
    }
end

print("[BVD] config layer loaded")

return BVD
