# Better Vehicle Dynamics

A drivetrain and traction overhaul mod for Project Zomboid Build 42.

## What it does

Better Vehicle Dynamics replaces the vanilla driving model with a
simulation built around real torque curves, surface-aware grip, and
configurable rolling drag. The headline features are:

- **Torque-curve acceleration** — each vehicle class uses power-to-weight
  ratios sourced from manufacturer and Wikipedia specifications, so
  light coupes pull away briskly and laden cargo vans labour under load.
- **Surface and weather grip** — traction degrades realistically on wet
  roads, mud, gravel, and flooded surfaces. Oversteer and understeer
  emerge naturally rather than from hard speed caps.
- **Configurable rolling drag** — tyre rolling resistance and aerodynamic
  drag scale with speed and are exposed as sandbox sliders, letting server
  operators tune highway feel without touching Lua.
- **Opt-in reference power/weight table** — `BVD_VehicleData.lua` ships
  pre-filled figures for every base-game vehicle; modded vehicles fall back
  gracefully to class defaults.
- **Cargo-capacity rescaling** — trunk volumes are normalised to match the
  vehicle's real-world footprint; a hatchback and a box van no longer
  share the same carry weight.
- **Arcade drift mode** — an opt-in sandbox preset that loosens rear grip
  for cinematic slides without breaking the rest of the simulation.
- **Tyre marks** — persistent skid-mark decals on hard braking and
  high-slip turns.
- **Driver readout** — a lightweight HUD widget (togglable) showing
  current grip level, torque output, and surface type.

Everything is sandbox-tunable. The full taxonomy is: **Mode preset** plus
groups for drivetrain, grip, resistance, realism, driving quality-of-life,
impact forces, and drift.

## Requirements

- Project Zomboid Build 42.18 or later (unstable or stable once B42 ships).
- The companion Java bundle **better-vehicle-dynamics-42** via the Necroid
  loader. Install it once alongside the mod and it applies to all saves.

## Installation

1. Subscribe to **Better Vehicle Dynamics** on the Steam Workshop.
2. Download and run the Necroid bundle installer (`better-vehicle-dynamics-42`)
   once — it installs the Java side into your PZ install directory.
3. Enable the mod in the Mod Manager and start or load a save.
4. Review sandbox settings under the **Vehicle Dynamics** section to match
   your preferred balance.

## Migrating from older vehicle-physics mods

Better Vehicle Dynamics uses its own sandbox layout and its own internal
identifiers. If you were using a different vehicle-physics mod previously,
simply disable it, enable this one, and reconfigure your preferences in
the Vehicle Dynamics sandbox panel. There is no automatic migration of
settings; the systems are independent.

## Public data-pack API (for vehicle mod authors)

If your mod adds vehicles, you can have Better Vehicle Dynamics apply
real-world power and weight figures to them. This is the supported,
stable replacement for any per-vehicle string-override sandbox knob.

> **Field status:** `hp` and `mass_kg` are applied now (at world start,
> when the HP/Weight realism sandbox option is enabled). `cargo` is
> **accepted and validated but reserved** — it is stored for a future
> API version and does **not** change trunk capacity in API v1. The
> first registered `cargo` value logs one informational line. To enlarge
> trunks today, use the **TrunkScaling** sandbox option (a per-class
> capacity multiplier, independent of this API).

The API lives in the global `BVD` table and is safe to call from any
`shared/` Lua file at module load time. It never calls `error()` — a
malformed entry is skipped with a single clear log line, so a bad data
pack can never break your mod's load.

`BVD.API_VERSION` is an integer you can branch on; it is bumped only for
breaking changes.

### Register one vehicle

```lua
-- "Mod.Type" is your PZ vehicle script full type.
-- hp / mass_kg / cargo are each optional, but you must supply at least
-- one, and each must be a positive finite number.
BVD.registerVehicle("ExampleMod.FictionalRoadster", {
    hp      = 240,
    mass_kg = 1320,
    cargo   = 180,
})
```

### Register many at once

```lua
BVD.registerVehicles({
    ["ExampleMod.FictionalRoadster"] = { hp = 240, mass_kg = 1320, cargo = 180 },
    ["ExampleMod.HaulerRig"]         = { hp = 320, mass_kg = 7400, cargo = 2600 },
})
```

### Register a named pack

`registerPack` bundles a whole table under a name (used for logs and the
debug spawner grouping). You can optionally gate it behind a predicate and
set a priority (higher priority is applied last and wins on conflict):

```lua
BVD.registerPack("ExampleVehiclesPack", {
    ["ExampleMod.FictionalRoadster"] = { hp = 240, mass_kg = 1320 },
    ["ExampleMod.HaulerRig"]         = { hp = 320, mass_kg = 7400, cargo = 2600 },
}, {
    check    = function() return true end,  -- optional gate
    priority = 10,                          -- optional; default 0
    source   = "ExampleMod",                -- optional log tag
})
```

### Read back

```lua
local data = BVD.getVehicleData("ExampleMod.FictionalRoadster")  -- table or nil
local all  = BVD.getRegisteredVehicles()                          -- read-only
```

### Validation rules

- `scriptName` must be a non-empty string.
- `hp`, `mass_kg`, `cargo` are each optional; whichever you supply must be
  a positive, finite number. At least one is required.
- `hp` and `mass_kg` are applied in API v1. `cargo` is validated and
  stored but **reserved** (not applied in v1) — see the Field status note
  above.
- A malformed entry is rejected as a whole (no partial garbage is stored)
  with one warning line — never an error.
- Unknown extra keys are ignored (forward-compatible).
- Registering a vehicle whose script the game never loads is harmless: the
  overhaul simply does nothing for it. No error.

Entries' `hp` / `mass_kg` only take effect when the **HP/Weight realism**
sandbox option is enabled; otherwise they are stored but inert. `cargo`
is always stored but is reserved (not applied in API v1).

## Tire-profile API and bridge contract (for tire and vehicle mod authors)

### Registering a tire-grip profile

`BVD.registerTireProfile(familyKey, profile)` lets any mod add a new tire
family to the grip system without touching Java. The function is safe to
call from any `shared/` Lua file at module load time.

**`familyKey`** is the vanilla-style item family identifier with trailing
size digits removed — so a tire item family `NormalTire14` registers as
`"NormalTire"`. The key is case-sensitive and must be a non-empty string.

**`profile`** is a table with four numeric multipliers, one per surface:

```lua
{ road = <number>, wet = <number>, snow = <number>, offroad = <number> }
```

Each multiplier is relative to that surface's own base grip value, where
`1.0` is neutral (no change). A value below `1.0` reduces grip on that
surface; a value above `1.0` increases it. Any missing or invalid field
is silently defaulted to `1.0`, so partial profiles are safe.

**Return value:** `true` if the profile was stored, `false` if the
`familyKey` was invalid or the profile argument was not a table. The
function never calls `error()`.

**First registration wins.** If two mods register the same key the second
call returns `false` and the original profile is preserved. This keeps
the grip model stable across mod load orders.

**Fictional example:**

```lua
-- Call from your mod's shared/ Lua file. familyKey must match
-- your tire item family with trailing digits stripped.
BVD.registerTireProfile("ExampleSportTire", {
    road    = 1.20,   -- 20 % better than neutral on dry tarmac
    wet     = 0.95,   -- slight wet penalty
    snow    = 0.80,   -- noticeably worse on snow
    offroad = 0.75,   -- not suited for loose surfaces
})
```

### Built-in vanilla tire families

BVD ships default profiles for the three vanilla tire families. Their
approximate character:

| Family       | Road | Wet  | Snow | Offroad |
|--------------|------|------|------|---------|
| `OldTire`    | 0.90 | 0.85 | 0.85 | 0.85    |
| `NormalTire` | 1.00 | 1.00 | 1.00 | 1.00    |
| `ModernTire` | 1.12 | 1.05 | 0.92 | 0.90    |

Any family registered via `BVD.registerTireProfile` is automatically
folded into the Java grip calculation at every surface touchpoint — no
manual Java reinstall or rebuild is needed for new tire families. The Lua
table is the sole source of truth; Java reads it on each grip evaluation.

### Bridge protocol version

`BetterVehicleDynamicsMod.protocolVersion` is an integer published by the
Java bundle at world load. It is currently `1`.

Future Lua-only Workshop updates can read this field to feature-detect
what the installed Java bundle supports and degrade gracefully on the
parts that need a newer contract, rather than hard-breaking. An older Java
bundle always produces a lower-or-equal version number, so a guard such as

```lua
if (BetterVehicleDynamicsMod.protocolVersion or 0) >= 2 then
    -- use a feature that needs protocol v2
end
```

ensures older installs silently skip that branch. This is why tire
profiles, load tuning, and the driver readout can all be shipped as
Workshop-only updates: the Lua side controls the policy tables and the
display; the Java side exposes stable hooks and publishes `protocolVersion`
so the Lua side always knows which hooks are available.

## Compatibility

Better Vehicle Dynamics patches vehicle handling data at load time through
the Necroid Java layer. It is broadly compatible with vehicle-skin and
vehicle-content mods. Mods that also hook the torque or drag calculation
paths may conflict; check each mod's notes.

## Credits

See `CREDITS.md`.
