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

## Compatibility

Better Vehicle Dynamics patches vehicle handling data at load time through
the Necroid Java layer. It is broadly compatible with vehicle-skin and
vehicle-content mods. Mods that also hook the torque or drag calculation
paths may conflict; check each mod's notes.

## Credits

See `CREDITS.md`.
