-- BVD_Packs.lua — pluggable vehicle data pack framework.
--
-- A "pack" is a bundle of per-vehicle data ({hp, mass_kg, cargo}
-- entries) gated on a predicate. Pack data is merged into BVD's vehicle
-- table at applyAll time, intended for callers to invoke when their
-- own data is ready. v0.7.0 ships NO bundled packs — the framework
-- exists so mod authors can publish their own data packs.
--
-- Two ways to plug in:
--   1. BVD.Packs.register("MyMod", { check=..., data="MyMod_Data" })
--      from any shared/ lua file; later BVD.Packs.applyAll(target).
--   2. For one-off vehicles, BVD.registerVehicle(fullType, data) directly.

BVD = BVD or {}
BVD.Packs = BVD.Packs or {}

local registry = {}
-- Snapshot of what was merged, keyed by pack name. Populated by applyAll
-- so other code (e.g. the spawner UI) can list entries per pack without
-- guessing data-module names.
local appliedSnapshot = {}

--- Register a pack. Idempotent on `name`.
-- @param name   string identifier (e.g. "acme_trucks", "examplePack")
-- @param spec   {
--   check    = function(): bool — should this pack apply?  Default: always true.
--   data     = table | string  — inline table or `require`-path to a data module
--                                that returns a table of {fullType = entry}.
--                                Entry shape: { hp = <number>, mass_kg = <number>, cargo = <number> }
--                                Any missing field is just skipped by the overhaul.
--   source   = string — informational tag for logs ("bundled" / "external" / etc.)
--   priority = number — higher applied last; later writes override earlier on conflict
-- }
function BVD.Packs.register(name, spec)
    if not name or type(name) ~= "string" then
        print("[BVD.Packs] register: name must be a string")
        return
    end
    if registry[name] then
        -- Already registered — keep first ("first registration wins").
        -- Lets users `require` packs defensively from multiple entry
        -- points without double-merging. One info line per duplicate
        -- name (this dedupe site fires once per such call — not per
        -- entry — so it is not spammy); pick a fresh name to register
        -- genuinely different data.
        print("[BVD.Packs] register: pack '" .. name ..
            "' already registered — keeping first, ignoring duplicate")
        return
    end
    registry[name] = spec or {}
end

--- Resolve the data field into a concrete table.
local function resolveData(spec)
    local d = spec.data
    if type(d) == "table" then return d end
    if type(d) == "string" then
        local ok, loaded = pcall(require, d)
        if ok and type(loaded) == "table" then return loaded end
        print(string.format("[BVD.Packs] failed to require %q: %s",
            d, tostring(loaded)))
        return nil
    end
    return nil
end

--- Apply every enabled pack into `targetTable` (in priority order).
-- Returns the count of total entries written across all enabled packs.
function BVD.Packs.applyAll(targetTable)
    if type(targetTable) ~= "table" then return 0 end

    -- Build a sorted list (deterministic ordering for logs + conflict resolution).
    local ordered = {}
    for n, s in pairs(registry) do
        table.insert(ordered, { name = n, spec = s, prio = s.priority or 0 })
    end
    table.sort(ordered, function(a, b)
        if a.prio == b.prio then return a.name < b.name end
        return a.prio < b.prio
    end)

    appliedSnapshot = {}

    local total = 0
    for _, entry in ipairs(ordered) do
        local s = entry.spec
        local active = true
        local checkErr = nil
        if type(s.check) == "function" then
            local ok, res = pcall(s.check)
            if not ok then
                active = false
                checkErr = tostring(res)
            else
                active = res == true
            end
        end
        if not active then
            -- Silent skip on `check=false`. Only log when check ERRORED so
            -- broken pack predicates surface in the log.
            if checkErr then
                print(string.format("[BVD.Packs] %s check errored: %s",
                    entry.name, checkErr))
            end
        else
            local data = resolveData(s)
            if data then
                local snap = {}
                local count = 0
                for fullType, vehicleData in pairs(data) do
                    targetTable[fullType] = vehicleData
                    snap[fullType] = vehicleData
                    count = count + 1
                end
                appliedSnapshot[entry.name] = snap
                total = total + count
            else
                print("[BVD.Packs] " .. entry.name .. " enabled but no data resolved")
            end
        end
    end
    return total
end

--- Return the snapshot of {pack_name = {fullType = data}} from the most
-- recent applyAll. Used by the spawner panel to group rows by pack.
function BVD.Packs.getAppliedSnapshot()
    return appliedSnapshot
end

--- For introspection / debugging — return a list of {name, active} entries.
function BVD.Packs.list()
    local out = {}
    for n, s in pairs(registry) do
        local active = true
        if type(s.check) == "function" then
            local ok, res = pcall(s.check)
            active = ok and res == true
        end
        table.insert(out, { name = n, active = active, source = s.source })
    end
    return out
end

return BVD.Packs
