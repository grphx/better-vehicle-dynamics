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

-- Returns a COPY so a caller can't mutate the live registry entry.
function BVD.getTireProfile(familyKey)
    local r = registry[familyKey]
    if not r then return nil end
    return { road = r.road, wet = r.wet, snow = r.snow, offroad = r.offroad }
end

-- Is the per-tire grip model enabled? Gated by the TireGripModel sandbox
-- toggle (default on). Read defensively via BVD.cfg(); falls back to
-- enabled if the config layer is unavailable for any reason.
local function tireModelOn()
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" then return c.TireGripModel ~= false end
    end
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    return not (sv and sv.TireGripModel == false)
end

-- Push the merged table onto the bridge for Java. Defaults first, then
-- any registered families (registry already first-write-wins). When the
-- TireGripModel toggle is OFF we publish an EMPTY table: Java's per-family
-- lookups all miss -> every surface factor is the neutral 1.0, i.e. tire
-- choice has no per-surface effect (identical to pre-feature behaviour).
-- Called on the live sandbox cadence too, so toggling applies without a
-- Java reinstall.
function BVD.publishTireProfiles()
    if not tireModelOn() then
        BetterVehicleDynamicsMod.tireProfiles = {}
        return
    end
    -- v0.1.2: OffroadFloor clamps each profile's offroad multiplier up to a
    -- sandbox-tunable minimum so sports-tire profiles (which may register
    -- offroad < 0.55) don't make high-HP cars walking-speed-slow on grass.
    -- Realism for road/wet/snow stays untouched.
    local floor = 0.55
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" and type(c.OffroadFloor) == "number" then
            floor = c.OffroadFloor
        end
    end
    local function clampOffroad(p)
        if not p then return p end
        local o = p.offroad or 1.0
        if o < floor then o = floor end
        return { road = p.road, wet = p.wet, snow = p.snow, offroad = o }
    end
    local merged = {}
    for k, v in pairs(DEFAULTS) do merged[k] = clampOffroad(v) end
    for k, v in pairs(registry) do merged[k] = clampOffroad(v) end
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

