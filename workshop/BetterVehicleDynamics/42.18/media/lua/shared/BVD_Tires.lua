-- BVD_Tires.lua — per-tire-family surface-grip profiles.
--
-- Java reads BetterVehicleDynamicsMod.tireProfiles[familyKey] =
-- {road,wet,snow,offroad} (1.0 = neutral) and folds it into grip per
-- surface. This module owns the DEFAULT vanilla-family profiles and a
-- public registration API so future tire mods / packs add families with
-- ZERO Java change. All numbers are Lua data, tunable via Workshop update.

BVD = BVD or {}
BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}

local SURFACES = { "road", "wet", "snow", "offroad" }

-- Default profiles for the three vanilla tire families. Neutral = 1.0.
-- Modern: road-biased (great tarmac, weaker loose surfaces).
-- Normal: balanced baseline. Old: uniformly poorer.
local DEFAULTS = {
    OldTire    = { road = 0.90, wet = 0.85, snow = 0.85, offroad = 0.85 },
    NormalTire = { road = 1.00, wet = 1.00, snow = 1.00, offroad = 1.00 },
    ModernTire = { road = 1.12, wet = 1.05, snow = 0.92, offroad = 0.90 },
}

local registry = {}   -- familyKey -> sanitized {road,wet,snow,offroad}

local function sanitize(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for i = 1, #SURFACES do
        local k = SURFACES[i]
        local v = t[k]
        if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then
            v = 1.0                          -- neutral on a bad/absent field
        end
        out[k] = v
    end
    return out
end

-- Public API: register/replace a tire family's surface profile.
-- familyKey is the vanilla-style item family (e.g. "ModernTire") with no
-- trailing size digits. First registration wins per key (documented).
function BVD.registerTireProfile(familyKey, profile)
    if type(familyKey) ~= "string" or familyKey == "" then return false end
    local s = sanitize(profile)
    if not s then return false end
    if registry[familyKey] == nil then
        registry[familyKey] = s
        BVD.publishTireProfiles()
        return true
    end
    return false
end

function BVD.getTireProfile(familyKey)
    return registry[familyKey]
end

-- Push the merged table onto the bridge for Java. Defaults first, then
-- any registered families (registry already first-write-wins).
function BVD.publishTireProfiles()
    local merged = {}
    for k, v in pairs(DEFAULTS)  do merged[k] = v end
    for k, v in pairs(registry)  do merged[k] = v end
    BetterVehicleDynamicsMod.tireProfiles = merged
end

-- Seed defaults into the registry-visible API surface and publish once
-- all shared modules are loaded.
local function bootstrap()
    for k, v in pairs(DEFAULTS) do
        if registry[k] == nil then registry[k] = v end
    end
    BVD.publishTireProfiles()
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(bootstrap)
else
    bootstrap()
end

print("[BVD.Tires] tire-profile registry installed (default Old/Normal/Modern)")
