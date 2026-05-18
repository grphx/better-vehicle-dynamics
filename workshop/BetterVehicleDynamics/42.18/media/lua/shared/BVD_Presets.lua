-- BVD_Presets.lua — difficulty presets that override individual sandbox knobs.
--
-- Preset values are applied at OnGameStart, after the user's saved sandbox
-- options have already loaded. When preset == Custom (1), this module does
-- nothing and the player's per-knob values are honored. Any other preset
-- overrides the listed knobs in-memory for the session.
--
-- Knobs not listed in a preset table are left at the user's configured value.

BVD = BVD or {}

BVD.PRESETS = {
    [1] = "Custom",
    [2] = "Casual",
    [3] = "Realistic",
    [4] = "Hardcore",
}

-- Keys use the BVD sandbox taxonomy.
-- EnginePower: a single engine-output knob collapsed from the original three per-class torque modifiers (sport / standard / heavy-duty).
--   All three were identical in every preset so a single EnginePower key covers the behaviour.
-- GripLevel: collapsed from OverallTraction (primary) + AccelerationTraction (secondary).
--   The overall (feel) value is used as GripLevel; the per-acceleration sub-knob is merged in.
--   Flag for review if the P3 sandbox design wants to split these again.
local PRESET_VALUES = {
    Casual = {
        EnginePower      = 1.4,
        GripLevel        = 1.5,
        WetGrip          = 0.95,
        SnowGrip         = 0.7,
        OffroadGrip      = 0.85,
        ShoveZombies     = 0.5,
        ShoveCorpses     = 0.5,
        ShoveFoliage     = 0.5,
        RealismHPWeight  = false,
        TrunkScaling     = false,
        TrunkCar         = 1.5,
        TrunkVan         = 1.5,
        TrunkTruck       = 1.5,
        TrunkTrailer     = 1.5,
    },
    -- Realistic/Hardcore intentionally leave RealismHPWeight to the player's toggle (no forced value).
    Realistic = {
        EnginePower      = 1.0,
        GripLevel        = 1.0,
        WetGrip          = 0.7,
        SnowGrip         = 0.4,
        OffroadGrip      = 0.6,
        ShoveZombies     = 1.0,
        ShoveCorpses     = 1.0,
        ShoveFoliage     = 1.0,
        TrunkScaling     = true,
        TrunkCar         = 1.0,
        TrunkVan         = 1.0,
        TrunkTruck       = 1.0,
        TrunkTrailer     = 1.0,
    },
    Hardcore = {
        EnginePower      = 0.85,
        GripLevel        = 0.75,
        WetGrip          = 0.45,
        SnowGrip         = 0.2,
        OffroadGrip      = 0.4,
        ShoveZombies     = 1.5,
        ShoveCorpses     = 1.5,
        ShoveFoliage     = 1.4,
        TrunkScaling     = true,
        TrunkCar         = 0.8,
        TrunkVan         = 0.8,
        TrunkTruck       = 0.8,
        TrunkTrailer     = 0.8,
    },
}

BVD.PRESET_VALUES = PRESET_VALUES

function BVD.getPresetName(idx)
    return BVD.PRESETS[idx or 1] or "Custom"
end

function BVD.getPresetValues(name)
    return PRESET_VALUES[name]
end

local PRESET_MODDATA_KEY = "BVD_PresetState"

local function applyPreset()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if not sv then return end

    local presetIdx = sv.Mode or 1
    local presetName = BVD.getPresetName(presetIdx)
    if presetName == "Custom" then
        print("[BVD.Presets] preset=Custom — using per-knob sandbox values")
        return
    end

    local values = PRESET_VALUES[presetName]
    if not values then
        print("[BVD.Presets] unknown preset index " .. tostring(presetIdx) .. " — falling back to Custom")
        return
    end

    -- Apply each preset only once per save. If the player picks a preset
    -- on world creation we cascade its values; on subsequent loads we
    -- detect the preset hasn't changed and skip, so per-knob edits the
    -- player made after the initial apply are honored.
    local state = ModData and ModData.getOrCreate and ModData.getOrCreate(PRESET_MODDATA_KEY)
    if state and state.lastAppliedPreset == presetName then
        print("[BVD.Presets] preset=" .. presetName .. " already applied; honoring current sandbox values")
        return
    end

    print("[BVD.Presets] applying preset: " .. presetName)
    local opts = getSandboxOptions and getSandboxOptions()
    local changedCount = 0
    for key, val in pairs(values) do
        sv[key] = val
        if opts then
            local opt = opts:getOptionByName("BetterVehicleDynamics." .. key)
            if opt then
                pcall(function() opt:setValue(val) end)
            end
        end
        if type(val) == "number" then
            print(string.format("  %s = %.2f", key, val))
        else
            print(string.format("  %s = %s", key, tostring(val)))
        end
        changedCount = changedCount + 1
    end

    -- Best-effort: persist mutated values back to the save so the next
    -- sandbox-UI open reflects them. setValue should already be persistent,
    -- but B42 versions vary; saveOptions() forces a flush when available.
    if opts and opts.saveOptions then
        pcall(function() opts:saveOptions() end)
    end

    -- Mark this preset as applied so subsequent loads don't re-stomp
    -- the player's per-knob tuning.
    if state then
        state.lastAppliedPreset = presetName
    end

    -- Visible feedback so the player knows the preset took effect.
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if player and player.Say then
        pcall(function()
            player:Say(string.format("[BVD] preset applied: %s (%d knobs overridden)",
                presetName, changedCount))
        end)
    end
end

-- Apply at OnGameStart so the values land before Java reads them.
-- OnSandboxOptionsLoaded would be earlier but doesn't exist in every B42
-- patch; OnGameStart is universally available.
Events.OnGameStart.Add(applyPreset)

-- ---------------------------------------------------------------------------
-- Live preset re-cascade (P6.3)
-- ---------------------------------------------------------------------------
-- Called by BVD_Config's change detector when it sees SandboxVars changed
-- at runtime. The OnGameStart applyPreset() above uses a once-per-save
-- ModData guard so it never re-stomps the player's per-knob tuning on
-- reload. The LIVE path is different: a Mode change at runtime is an
-- explicit, deliberate player action, so when (and only when) the Mode
-- index actually differs from the last one we cascaded, we re-apply that
-- preset's values. A pure slider edit (Mode unchanged) is intentionally
-- NOT re-stomped here — the player is hand-tuning and we honor that, the
-- cfg cache refresh alone surfaces their new values.
--
-- This does not fight Java: it only writes SandboxVars (which Java already
-- re-reads every tick). It writes the SAME keys the OnGameStart cascade
-- writes, so feel parity at world start is unchanged.
local _liveLastMode = nil

function BVD.reapplyPresetLive()
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if not sv then return end

    local presetIdx = sv.Mode or 1
    if _liveLastMode == nil then
        -- First live check this session — adopt the current Mode as the
        -- baseline without cascading (OnGameStart already handled boot).
        _liveLastMode = presetIdx
        return
    end
    if presetIdx == _liveLastMode then
        -- Mode unchanged: this was a slider edit. Honor the player's
        -- hand-tuned values; nothing to cascade.
        return
    end

    _liveLastMode = presetIdx
    local presetName = BVD.getPresetName(presetIdx)
    if presetName == "Custom" then
        print("[BVD.Presets] live: Mode -> Custom; honoring per-knob values")
        return
    end

    local values = PRESET_VALUES[presetName]
    if not values then
        print("[BVD.Presets] live: unknown preset index " ..
            tostring(presetIdx))
        return
    end

    print("[BVD.Presets] live: re-cascading preset " .. presetName)
    local opts = getSandboxOptions and getSandboxOptions()
    for key, val in pairs(values) do
        sv[key] = val
        if opts then
            local opt = opts:getOptionByName("BetterVehicleDynamics." .. key)
            if opt then
                pcall(function() opt:setValue(val) end)
            end
        end
    end
    -- Refresh the once-per-save marker so a later world reload does not
    -- re-stomp tuning the player does AFTER this live preset change.
    local state = ModData and ModData.getOrCreate
        and ModData.getOrCreate(PRESET_MODDATA_KEY)
    if state then state.lastAppliedPreset = presetName end

    if BVD.invalidateConfigCache then BVD.invalidateConfigCache() end

    local player = getSpecificPlayer and getSpecificPlayer(0)
    if player and player.Say then
        pcall(function()
            player:Say("[BVD] preset switched live: " .. presetName)
        end)
    end
end

return BVD
