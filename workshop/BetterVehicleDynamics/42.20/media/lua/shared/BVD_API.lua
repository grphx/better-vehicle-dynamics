-- BVD_API.lua — STABLE public registration API for other vehicle mods.
--
-- This is the supported, versioned entry point for third-party mods that
-- want Better Vehicle Dynamics to apply real-world HP / weight figures to
-- their vehicles. It is the original, superior replacement for
-- the dropped per-vehicle sandbox string-override knobs: instead of one
-- giant fragile sandbox string, mod authors register typed Lua tables.
--
-- API SURFACE (stable — these signatures will not change in a breaking
-- way without a major version bump and a deprecation period):
--
--   BVD.registerVehicle(scriptName, { hp=, mass_kg=, cargo= })
--       Register/replace one vehicle's data. scriptName is the PZ vehicle
--       script full type, e.g. "MyMod.FictionalRoadster".
--       FIELD STATUS: hp -> engineForce and mass_kg -> mass are APPLIED
--       (at world start, when the HP/Weight realism sandbox option is on).
--       cargo is ACCEPTED + VALIDATED but RESERVED — stored for a future
--       API version, NOT applied in API_VERSION 1. Container capacity is a
--       doubly-nested per-part script field whose part name this API does
--       not carry; the safe per-class cargo lever today is the separate
--       TrunkScaling sandbox option. The first registered cargo value logs
--       one info line (see BVD_Overhaul.lua). Passing cargo is harmless
--       and forward-compatible.
--
--   BVD.registerVehicles({ ["MyMod.A"]={...}, ["MyMod.B"]={...} })
--       Bulk form. Each entry is validated independently.
--
--   BVD.registerPack(name, { ["MyMod.A"]={...}, ... }, opts?)
--       Convenience wrapper around BVD.Packs.register for the common case
--       of "here is my whole inline data table". opts is optional and may
--       carry { check=function, priority=number, source=string }.
--
--   BVD.getVehicleData(scriptName) -> table|nil
--   BVD.getRegisteredVehicles()   -> table   (live data table; do not mutate)
--   BVD.API_VERSION               -> number  (bump on breaking changes)
--
-- VALIDATION CONTRACT:
--   * scriptName must be a non-empty string, else the entry is skipped
--     with ONE warn line (no per-field spam, no error()).
--   * data must be a table. Recognised numeric fields: hp, mass_kg, cargo.
--     Each, if present, must be a finite number > 0. A bad field makes the
--     WHOLE entry rejected (one warn) — partial garbage is never stored.
--   * Unknown extra keys in data are ignored silently (forward-compat:
--     future BVD versions may read them; today's BVD does not choke).
--   * Unknown / absent vehicle scripts are NOT validated here and NOT an
--     error — registration always succeeds for a well-formed entry; the
--     overhaul simply no-ops at apply time if PZ never loaded that script.
--   * This module NEVER calls error(). A misbehaving data pack can degrade
--     its own coverage but can never break another mod's file load.

BVD = BVD or {}

-- Public, queryable API version. Consumers can branch on this. Bump the
-- integer only for a breaking change to the documented surface above.
BVD.API_VERSION = 1

-- Single warn helper. We deliberately avoid error() — a third-party mod
-- passing junk should see a clear log line, not a broken load.
local function warn(msg)
    print("[BVD.API] WARNING: " .. tostring(msg))
end

-- Lazily resolve the live vehicle data table. The API module can load
-- before BVD_VehicleData in some load orders, so resolve on demand and
-- cache the handle once we have it.
local _dataCache = nil
local function dataTable()
    if _dataCache ~= nil then return _dataCache end
    local ok, t = pcall(require, "BVD_VehicleData")
    if ok and type(t) == "table" then
        _dataCache = t
        return t
    end
    return nil
end

-- A number that is real, finite, and strictly positive. Kahlua has no
-- math.type; the (n ~= n) test rejects NaN and the inf comparison rejects
-- +/-inf, which is the cheap portable way to do this here.
local function isPositiveFinite(n)
    if type(n) ~= "number" then return false end
    if n ~= n then return false end          -- NaN
    if n == math.huge or n == -math.huge then return false end
    return n > 0
end

-- Validate one entry. Returns a sanitized COPY on success (so the caller
-- cannot mutate our stored table by holding the reference), or nil + a
-- single reason string on failure. We copy only the recognised fields;
-- unknown keys are dropped from the stored copy but never warned about.
local RECOGNISED = { "hp", "mass_kg", "cargo" }
local function sanitize(scriptName, data)
    if type(scriptName) ~= "string" or scriptName == "" then
        return nil, "scriptName must be a non-empty string (got " ..
            type(scriptName) .. ")"
    end
    if type(data) ~= "table" then
        return nil, "data for '" .. scriptName ..
            "' must be a table (got " .. type(data) .. ")"
    end
    local clean = {}
    for _, field in ipairs(RECOGNISED) do
        local v = data[field]
        if v ~= nil then
            if not isPositiveFinite(v) then
                return nil, "'" .. scriptName .. "'." .. field ..
                    " must be a positive finite number (got " ..
                    tostring(v) .. ")"
            end
            clean[field] = v
        end
    end
    -- An entry that carries none of the recognised fields is useless and
    -- almost certainly a caller mistake — reject it with a clear reason
    -- rather than silently storing an empty table.
    if clean.hp == nil and clean.mass_kg == nil and clean.cargo == nil then
        return nil, "'" .. scriptName ..
            "' has none of hp / mass_kg / cargo — nothing to apply"
    end
    return clean
end

--- Register (or replace) a single vehicle's reference data.
-- @param scriptName  string  PZ vehicle script full type ("Mod.Vehicle")
-- @param data        table   { hp=, mass_kg=, cargo= } — each optional but
--                            at least one required; each positive finite.
-- @return table|nil  the stored sanitized copy, or nil if rejected.
function BVD.registerVehicle(scriptName, data)
    local clean, reason = sanitize(scriptName, data)
    if not clean then
        warn("registerVehicle skipped: " .. reason)
        return nil
    end
    local t = dataTable()
    if not t then
        -- Data module not resolvable yet/at all. Not fatal: report once.
        warn("registerVehicle('" .. scriptName ..
            "'): vehicle data table unavailable — entry not stored")
        return nil
    end
    if t[scriptName] ~= nil then
        print("[BVD.API] replacing existing vehicle entry: " .. scriptName)
    end
    t[scriptName] = clean
    return clean
end

--- Bulk register. Each entry is validated independently; a bad entry is
-- skipped (one warn) without aborting the rest.
-- @param entries  table  { [scriptName] = data, ... }
-- @return number  count of entries successfully stored.
function BVD.registerVehicles(entries)
    if type(entries) ~= "table" then
        warn("registerVehicles: entries must be a table (got " ..
            type(entries) .. ")")
        return 0
    end
    local stored = 0
    for k, v in pairs(entries) do
        if BVD.registerVehicle(k, v) ~= nil then
            stored = stored + 1
        end
    end
    return stored
end

--- Convenience: register an inline data table as a named pack. Thin
-- wrapper over BVD.Packs.register so authors who just have a static table
-- do not need to learn the pack spec shape. Predicate / priority / source
-- can still be passed via the optional opts table.
--
-- NAME IDEMPOTENCY: registration is keyed by `name` and is first-write-
-- wins. A second registerPack (or BVD.Packs.register) call with a name
-- already in the registry is IGNORED — the original pack is kept and the
-- new data is discarded. This lets authors `require`/register defensively
-- from multiple entry points without double-merging. A duplicate name
-- logs one informational line (at the BVD.Packs.register dedupe point);
-- pick a fresh name if you actually intend to register different data.
--
-- @param name  string  pack identifier (for logs + spawner grouping)
-- @param tbl   table   { [scriptName] = { hp=, mass_kg=, cargo= }, ... }
-- @param opts  table?  { check=function, priority=number, source=string }
-- @return boolean  true if the pack was accepted into the registry. Note:
--                  returns true even when an earlier pack of the same name
--                  already won (the call is a well-formed no-op then).
function BVD.registerPack(name, tbl, opts)
    if type(name) ~= "string" or name == "" then
        warn("registerPack: name must be a non-empty string")
        return false
    end
    if type(tbl) ~= "table" then
        warn("registerPack('" .. name ..
            "'): data must be a table (got " .. type(tbl) .. ")")
        return false
    end
    -- Pre-validate every entry so a pack can never inject malformed data
    -- into the apply path. We hand BVD.Packs a fully sanitized table.
    local clean = {}
    local kept, dropped = 0, 0
    for scriptName, data in pairs(tbl) do
        local c, reason = sanitize(scriptName, data)
        if c then
            clean[scriptName] = c
            kept = kept + 1
        else
            dropped = dropped + 1
            warn("registerPack('" .. name .. "') dropped entry: " .. reason)
        end
    end
    if kept == 0 then
        warn("registerPack('" .. name ..
            "'): no valid entries — pack not registered")
        return false
    end
    opts = type(opts) == "table" and opts or {}
    -- Ensure the pack framework is loaded regardless of file load order.
    if not (BVD.Packs and BVD.Packs.register) then
        pcall(require, "BVD_Packs")
    end
    if BVD.Packs and BVD.Packs.register then
        BVD.Packs.register(name, {
            data          = clean,
            check         = opts.check,
            priority      = opts.priority,
            source        = opts.source or "external",
            authoritative = opts.authoritative == true,
        })
        print(string.format(
            "[BVD.API] registerPack('%s'): %d entries accepted, %d dropped",
            name, kept, dropped))
        return true
    end
    warn("registerPack('" .. name ..
        "'): BVD.Packs framework unavailable")
    return false
end

--- Live read-back of the merged vehicle data table. Treat as read-only;
-- mutate via registerVehicle, not by editing the returned table.
function BVD.getRegisteredVehicles()
    return dataTable() or {}
end

--- Look up one vehicle's stored data (or nil).
function BVD.getVehicleData(scriptName)
    local t = dataTable()
    return t and t[scriptName] or nil
end

return BVD
