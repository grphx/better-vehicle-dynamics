# Changelog

## [0.1.4] - 2026-05-21 - Skid sound: drop vehicle-emitter path + fix manager re-arm leak

- Fix (regression from 0.1.3): in MP the skid sound still looped
  endlessly at the point in the world where the skid happened, and
  multiple sounds could be heard at once.
- Two bugs in the 0.1.3 refactor:
  1. `vehicle:getEmitter():playSound()` propagates positionally to
     nearby clients. Combined with the per-client heartbeat model
     this caused N^2 duplication: every client received the Start
     command, called the vehicle emitter, and each call broadcast
     the sound to OTHER clients too. Dropped the vehicle-emitter
     code path entirely; the heartbeat model only uses world or
     manager emitters which are local to the calling client.
  2. The manager-fallback re-arm logic overwrote `soundId` with the
     new id without stopping the old one. Old positional sounds kept
     playing at their original world positions forever. Now we stop
     the previous sound before each re-arm.
- Lua-only. No manual install update needed.

## [0.1.3] - 2026-05-21 - Skid sound MP fix + Skid Sound sandbox toggle

- Fix: in MP, the tire-skid sound played forever on other clients when
  a remote driver finished skidding (PZ's positional-sound stop does
  not reliably replicate). Refactored to a per-vehicle heartbeat model:
  the driver sends Start/Tick/Stop commands; every client plays its
  OWN local sound on receipt and stops via explicit Stop or a 700ms
  watchdog timeout if heartbeats stop arriving (handles driver
  disconnect mid-skid).
- Same fix resolves "skid sound plays while my vehicle is off or while
  I'm not in it" - that was the same bug from another angle.
- New sandbox option **Tire skid sound** (Readout page, default ON).
  Independent of **Tire marks** so a player can keep the visual decals
  and mute the sound (or vice versa). Set to OFF if a sound mod
  conflicts.
- New server-side file `BVD_SkidSync_Server.lua` relays the heartbeat
  to all online clients.
- Lua-only change. No manual install update needed.

## [0.1.2] - 2026-05-21 - Off-road floor + tire wear from slip + stuck diagnostics

- New sandbox option **Off-road grip floor** (Handling, default 0.55,
  range 0.3-1.0). Clamps each tire profile's off-road multiplier up to
  this minimum. Sports-tire profiles no longer drop low enough to make
  high-HP cars walking-speed-slow on grass. Default cars unaffected
  (their off-road multipliers are already >= 0.85).
- New sandbox option **Tires wear from wheel slip** (Tires & Load,
  default ON) + **Tire wear rate from slip** (default 1.0, range 0-2).
  When the engine is forcing wheels faster than the surface can grip,
  driven tires lose condition over time. Lets you brute-force grass at
  the cost of bald tires later. Set rate to 0 to disable wear without
  disabling the model.
- Tightened the load-penalty clamp from 0.9 to 0.85, so even worst-case
  stacking with other mods can't drop the engine's force-to-wheels
  below 15% of nominal. Defensive against the "engine revving but car
  doesn't move" report.
- New diagnostic log `[BVD-DIAG] stuck: ...` fires once per stuck
  event (engine running + throttle + speed < 3 km/h for 2 s) with the
  current load%, force, tyre family, and surface. Data path for
  tracking down the persistent "stuck car" bug on dedicated servers.
- Lua-only change. No manual install update needed.

## [0.1.1] — 2026-05-20 — Engine power scaler wired

- Fix: the `EnginePower` sandbox option (Drivetrain page, range 0.25–3.0,
  default 1.0) is now actually applied. The option existed since 0.1.0 but
  wasn't multiplied into the HP/Weight overhaul's `engineForce` write —
  changing it had no effect. Now `engineForce = hp × 10 × EnginePower`,
  giving users a knob to dial up top-end and acceleration without losing
  the realism baseline. Default 1.0 preserves 0.1.0 behaviour exactly.
- Note: only takes effect with **Reference power & weight** enabled. The
  scaler is a multiplier on the researched values; if you opt out of the
  overhaul, vanilla engineForce is unchanged.
- Lua-only change. No manual install update needed.

## [0.1.0] — 2026-05-19 — Initial release

- Independent drivetrain & traction overhaul for B42.18.
- Torque-curve acceleration with tunable low-speed shove.
- Surface- & weather-aware grip (road / rain / snow / off-road).
- Tyre-type per-surface grip model (worn / standard / modern).
- Load → handling (sandbox-tunable launch penalty) and load → fuel use.
- Configurable air drag + rolling resistance; opt-in reference
  power/weight table with a public registration API.
- Cargo-capacity rescale; arcade drift mode (off by default).
- Tyre marks that self-expire (~10 in-game min).
- Docked vehicle info panel.
- Server-authoritative vehicle ground-clip (Z-sink) guard.
- Sandbox taxonomy: Mode preset + Handling / Tyres & Load /
  Drivetrain / Readout pages.
- Clean-room Java engine bundle better-vehicle-dynamics-42.
