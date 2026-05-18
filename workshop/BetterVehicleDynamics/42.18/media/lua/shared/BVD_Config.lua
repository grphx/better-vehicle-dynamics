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
-- LIVE RE-READ + CACHING (P6.3)
-- ----------------------------
-- cfg() now returns a CACHED table built once and rebuilt ONLY when the
-- underlying SandboxVars actually change. The build allocated a fresh
-- ~29-key table on every call; with cfg() now on a per-tick path that was
-- needless Kahlua GC pressure. Return-shape is byte-for-byte identical to
-- the previous implementation — only the allocation cadence changed.
--
-- The change detector runs on the existing per-vehicle update tick
-- (OnPlayerUpdate, the same event the drift/skid bridges already use),
-- throttled. When it sees the BVD sandbox values differ from the cached
-- snapshot it (a) invalidates the cfg cache and (b) asks BVD_Presets to
-- re-cascade for the (possibly new) Mode. This makes preset + slider
-- changes apply at runtime WITHOUT fighting the Java side: the Java
-- physics code re-reads SandboxVars directly every tick already, so a
-- live SandboxVars mutation is picked up by Java natively; this module
-- only keeps the Lua-side cache and the preset cascade in sync.
--
-- DELIBERATELY START-ONLY (not re-read live — would regress feel / be
-- unsafe to toggle mid-session):
--   * RealismHPWeight + the HP/Weight reference apply — applying it
--     rewrites every matching vehicle script via vehicle:Load at world
--     start; doing that on a live tick is heavy and would not cleanly
--     revert an already-loaded session, so it stays OnGameStart-only.
--   * TrunkScaling hook INSTALL — the ItemContainer metatable patch is a
--     one-time install (and is skipped entirely if isoContainers loads).
--     The patch body itself reads SandboxVars live, so the TrunkScaling
--     toggle and the Trunk* multipliers DO take effect live once the hook
--     is installed; only the install is start-only.
-- Everything else (Mode preset, grip / drag / shove / drift sliders, HUD
-- and skid toggles) is re-read live.
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

-- Canonical list of every SandboxVars key cfg() reads. Used both by the
-- builder defaults and by the change-detector fingerprint so the two can
-- never drift apart.
local KEYS = {
    "Mode", "DriverHUD", "SkidMarks",
    "EnginePower", "LowSpeedGrunt", "ReverseTopSpeed",
    "GripLevel", "WetGrip", "SnowGrip", "OffroadGrip",
    "Drag", "RollResistance", "RollResistanceOffroad",
    "RealismHPWeight", "TrunkScaling",
    "TrunkCar", "TrunkVan", "TrunkTruck", "TrunkTrailer",
    "ThrottleStart", "KeylessTow",
    "ShoveFoliage", "ShoveZombies", "ShoveCorpses",
    "Drift", "DriftGrip", "DriftMinSpeed", "DriftSteer", "DriftRotation",
    "TireGripModel", "LoadAffectsHandling", "LoadAffectsFuel", "LoadMaxPenalty",
}

-- Build the effective-config table fresh. Internal — public access is via
-- BVD.cfg(), which caches the result of this.
local function buildCfg()
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

        -- Load dynamics
        TireGripModel       = boolTrue("TireGripModel"),       -- default true
        LoadAffectsHandling = boolTrue("LoadAffectsHandling"), -- default true
        LoadAffectsFuel     = boolTrue("LoadAffectsFuel"),     -- default true
        LoadMaxPenalty      = num("LoadMaxPenalty", 0.5),      -- 0..0.9 frac
    }
end

-- ---------------------------------------------------------------------------
-- Cache + change detection
-- ---------------------------------------------------------------------------

local _cache = nil          -- last built cfg table (return-shape unchanged)
local _fingerprint = nil    -- string snapshot of raw SandboxVars BVD keys

-- Cheap deterministic fingerprint of the raw sandbox values. We compare
-- this rather than diffing the built table so we detect a change before
-- paying for a rebuild. tostring() over the fixed KEYS order is stable in
-- Kahlua for numbers/booleans/nil and is allocation-light vs. a full build.
local function fingerprint()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    local parts = {}
    for i = 1, #KEYS do
        local v = sv and sv[KEYS[i]]
        parts[i] = tostring(v)
    end
    return table.concat(parts, "|")
end

--- Returns a table of every effective BVD option value.
-- Reads SandboxVars.BetterVehicleDynamics (after any preset cascade has
-- run), falling back to the sandbox-options.txt default for any nil key.
-- The result is CACHED and only rebuilt when the underlying SandboxVars
-- change. Pure read — no sandbox writes, no side effects. The returned
-- table shape is identical to pre-P6.3.
-- @return table  { Mode, DriverHUD, SkidMarks, EnginePower, ... }
function BVD.cfg()
    if _cache == nil then
        _fingerprint = fingerprint()
        _cache = buildCfg()
    end
    return _cache
end

--- Force the next BVD.cfg() to rebuild. Called by the change detector and
-- available to other modules that mutate SandboxVars directly.
function BVD.invalidateConfigCache()
    _cache = nil
    _fingerprint = nil
end

-- ---------------------------------------------------------------------------
-- Load-response bridge publish
-- ---------------------------------------------------------------------------
-- Writes BetterVehicleDynamicsMod.loadResponse so the Java CarController can
-- read the launch-penalty policy without knowing about BVD_Config internals.
-- Called at module load (initial publish) and from onLiveTick whenever a
-- sandbox change is detected (same cadence as preset re-cascade). Threshold,
-- penalty curve, and ease constants are authoring values — only `enabled`
-- tracks the sandbox toggle at runtime.

local function publishLoadResponse()
    BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}
    local c = BVD.cfg()
    -- maxPenalty is player-tunable (sandbox BVD_LoadMaxPenalty, default
    -- 0.50). Clamp defensively to the option's own [0, 0.9] range so a
    -- hand-edited config can't invert or fully kill the torque.
    local mp = tonumber(c and c.LoadMaxPenalty) or 0.5
    if mp < 0.0 then mp = 0.0 elseif mp > 0.9 then mp = 0.9 end
    BetterVehicleDynamicsMod.loadResponse = {
        enabled        = (c and c.LoadAffectsHandling ~= false),
        threshold      = 1.05,   -- no effect until >5% over reference mass
        maxPenalty     = mp,     -- sandbox-driven cap on launch-force loss
        fullAt         = 1.45,   -- mp reached by ~45% over reference mass
        easeBySpeedKmh = 35.0,   -- fully gone by 35 km/h
    }
end

-- ---------------------------------------------------------------------------
-- Live re-read on the per-vehicle update tick
-- ---------------------------------------------------------------------------
-- Throttled so we are not concatenating a fingerprint every frame. When a
-- change is seen we drop the cache and re-cascade the preset for the (maybe
-- new) Mode. The Java physics side reads SandboxVars directly each tick, so
-- live slider edits already reach Java; this only keeps the Lua cache and
-- the preset cascade consistent — it does not push values at Java.

local _tick = 0
local function onLiveTick()
    _tick = _tick + 1
    -- ~ every 30 player-update ticks. OnPlayerUpdate is the same cadence
    -- the drift/skid bridges run at; 30 is well below a human's ability
    -- to perceive sandbox-edit latency while keeping the check cheap.
    if (_tick % 30) ~= 0 then return end

    local fp = fingerprint()
    if fp == _fingerprint then return end

    -- A BVD sandbox value changed at runtime. Invalidate the cache and ask
    -- the preset module to re-cascade for the current Mode (no-op when
    -- Mode == Custom). Guarded so a missing preset module is non-fatal.
    _fingerprint = fp
    _cache = nil
    if BVD and type(BVD.reapplyPresetLive) == "function" then
        pcall(BVD.reapplyPresetLive)
        -- Re-cascade may itself have mutated SandboxVars; resync the
        -- fingerprint so we do not loop on our own writes.
        _fingerprint = fingerprint()
    end
    -- Re-publish bridge tables so Java picks up any toggled options live.
    publishLoadResponse()
    if BVD and BVD.publishTireProfiles then pcall(BVD.publishTireProfiles) end
    print("[BVD] config: live sandbox change detected — cache refreshed")
end

-- OnPlayerUpdate only fires in a context that has a local player, i.e.
-- the client (and SP host). A dedicated server has no local player, so
-- this event never fires there and the live re-read is client-only BY
-- DESIGN: the server already reads SandboxVars at world start and the
-- Java physics side re-reads them per tick, so a server has nothing to
-- live-resync here. The `if Events and Events.OnPlayerUpdate` guard is
-- what makes this shared/ placement safe — on the server the event may
-- be absent/never-fired and we simply skip registration with no error.
if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onLiveTick)
end

-- Initial publish: seed the bridge table as soon as the module loads so
-- Java sees a valid loadResponse even before any OnPlayerUpdate fires.
publishLoadResponse()

print("[BVD] config layer loaded (cached + live re-read)")

return BVD
