# Better Vehicle Dynamics — Public Lua API

Stable, versioned entry point for other Project Zomboid mods to feed
their vehicles into Better Vehicle Dynamics (BVD). Register typed Lua
tables instead of editing fragile sandbox strings.

- **Global:** `BVD` (created on load; safe to `BVD = BVD or {}` before use).
- **Version:** `BVD.API_VERSION` → number. Currently `1`. Bumped only on
  a breaking change to the documented surface, with a deprecation period.
- **Never throws:** the API never calls `error()`. Bad input is rejected
  with a single `[BVD.API] WARNING:` log line — a misbehaving pack can
  only reduce its own coverage, never break another mod's file load.
- **When it applies:** `hp` → engine force and `mass_kg` → mass are
  applied at world start, and only while the *Reference power & weight*
  sandbox option is enabled and the BVD Java component is installed.
  Registration always succeeds for a well-formed entry even if PZ never
  loads that script — it simply no-ops at apply time.

## Register one vehicle

```lua
BVD = BVD or {}
Events.OnGameBoot.Add(function()
    BVD.registerVehicle("MyMod.ExampleRoadster", {
        hp      = 240,     -- number > 0, applied as engine force
        mass_kg = 1450,    -- number > 0, applied as vehicle mass
        cargo   = 260,     -- accepted + validated, RESERVED (not applied in API v1)
    })
end)
```

`scriptName` is the PZ vehicle script full type (e.g. `"MyMod.ExampleRoadster"`).
Returns the stored entry on success, or `nil` if the entry was skipped
(a single warning is logged).

## Register many at once

```lua
BVD.registerVehicles({
    ["MyMod.ExampleRoadster"] = { hp = 240, mass_kg = 1450 },
    ["MyMod.ExampleHauler"]   = { hp = 180, mass_kg = 3200 },
})
```

Each entry is validated independently; a bad one is skipped without
affecting the others.

## Register a data pack

For "here is my whole table" — convenience wrapper:

```lua
BVD.registerPack("mymod_vehicles", {
    ["MyMod.ExampleRoadster"] = { hp = 240, mass_kg = 1450 },
}, {
    check    = function() return true end,  -- optional; should this pack apply?
    priority = 0,                            -- optional; higher applied last (wins conflicts)
    source   = "mymod",                      -- optional; informational log tag
})
```

Lower-level form (inline table or a `require`-path to a data module that
returns `{ [fullType] = entry }`):

```lua
BVD.Packs.register("mymod_vehicles", {
    data     = "MyMod_VehicleData",   -- or an inline table
    check    = function() return true end,
    priority = 0,
    source   = "bundled",
})
```

Pack registration is **idempotent on `name`**: the first registration
for a name wins; a duplicate name is ignored with one info line. Pick a
unique, namespaced pack name.

## Query

```lua
local data = BVD.getVehicleData("MyMod.ExampleRoadster")  -- table | nil
local all  = BVD.getRegisteredVehicles()                  -- live table; DO NOT mutate
local v    = BVD.API_VERSION                              -- number
```

## Tyre-grip profiles

Register a per-surface grip profile for a tyre family (vanilla-style
item family name with no trailing size digits, e.g. `"ModernTire"`).
Values are multipliers; `1.0` is neutral.

```lua
local ok = BVD.registerTireProfile("ExampleSportTire", {
    road    = 1.15,
    wet     = 0.95,
    snow    = 0.80,
    offroad = 0.85,
})
-- returns true if registered, false if rejected or already registered

local p = BVD.getTireProfile("ExampleSportTire")  -- a COPY, or nil
```

First registration per family key wins. Non-numeric / `<= 0` / `NaN` /
`inf` fields are sanitised to `1.0` (neutral) rather than rejected.

## Validation contract

- `scriptName` / pack `name` must be a non-empty string, else the entry
  is skipped with one warning.
- `data` must be a table. Recognised numeric fields: `hp`, `mass_kg`,
  `cargo`. Each present field must be a finite number `> 0`. One bad
  field rejects the **whole** entry — partial data is never stored.
- Unknown extra keys are ignored (forward-compatible).
- Unknown / not-yet-loaded vehicle scripts are not an error.

## Notes

- `cargo` is accepted and validated but **reserved** in API v1 (stored
  for a future version, not applied). For larger storage today, players
  use the *Cargo capacity rescale* sandbox option.
- Register from `Events.OnGameBoot` (or later) — never at bare file
  scope — for load-order safety.
