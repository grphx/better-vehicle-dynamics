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

## Compatibility

Better Vehicle Dynamics patches vehicle handling data at load time through
the Necroid Java layer. It is broadly compatible with vehicle-skin and
vehicle-content mods. Mods that also hook the torque or drag calculation
paths may conflict; check each mod's notes.

## Credits

See `CREDITS.md`.
