# Changelog

## [0.1.10] - 2026-06-10 - Authoritative packs: KI5 + Community rebaseline through vanilla floor

- **Pack `authoritative` flag (KI5 + Community pack fix).** v0.1.9
  added a "never write below vanilla engineForce/mass" floor to fix
  small-car stalling (#3). Side-effect: vehicles shipped by other mods
  with their own pre-tuned (often over-tuned) `engineForce` were now
  protected by that floor, so BVD's KI5 + Community reference packs
  could no longer rebaseline them to real-world values - to users it
  looked like "KI5 compatibility no longer applies." Pack spec now
  accepts `authoritative = true`; entries from authoritative packs
  bypass the floor and write through as-published. BVD's built-in
  vanilla table stays non-authoritative, so the small-car fix is
  preserved. Pack authors who want the same write-through behaviour
  pass `{ authoritative = true }` in their `BVD.registerPack` opts.
- KI5 reference pack and Community reference pack both ship marked
  `authoritative = true` in this release.



- **Vehicle spawner: right-click DROPPED, console command added (#1).**
  The "Better Vehicle Dynamics > Open Vehicle Spawner" right-click
  menu cluttered every world-object context for admins / SP /
  -debug sessions. Opening the spawner is now done from the in-game
  chat (T key): `/bvd-spawn`. Lua-console (` key) callers can use
  the global aliases `bvdSpawn()` or `BVD_VehicleSpawner_open()`.
  Auth gate is identical to the old menu (admin / moderator / SP /
  -debug); silent-fail for non-admins in MP.
- **Cargo capacity: multiplier actually enforced now (#2 + #4).**
  User reports said the trunk would *display* the scaled capacity
  (e.g. 520 kg) but stop accepting items at the vanilla cap (130 kg),
  and that bags placed INSIDE the trunk showed a red "won't fit"
  background even when the trunk was near-empty. Root cause: the old
  metatable hook only overrode `ItemContainer:getEffectiveCapacity`
  (display) and `hasRoomFor`, but PZ B42's transfer code enforces on
  the part-script-backing capacity (`setCapacity` runtime-caps at
  100 anyway). v0.1.9 rewrites the path entirely: at world start
  and on a throttled OnPlayerUpdate scan we walk the cell's vehicle
  list via the `iterator()` API, find each cargo container, and call
  `VehiclePart:setContainerCapacity()` (not the container-level
  `setCapacity`) to lift the script-backing limit. A
  `BVD_TrunkScaled` ModData flag dedupes — a vehicle is only scaled
  once per save. Compatible with isoContainers — falls back to a
  no-op when that mod is loaded, exactly as before.
- **HP/Weight overhaul: vanilla floor (#3).** Reports said
  "Reference power and weight" made some cars stop running. Root
  cause: for small / older vehicles, vanilla PZ compresses the
  HP-to-engineForce curve (a 15 hp scooter has engineForce ~400,
  not 150), so writing realistic `hp * 10` UNDER vanilla left them
  too sluggish to overcome rolling drag. v0.1.9 reads vanilla
  engineForce + mass via the script API and never writes a value
  below vanilla — only ever INCREASES. Also integer-formats the
  values via `string.format("%d", ...)` to dodge a parser quirk
  where float literals with trailing zeros could silently fail.

## [0.1.8] - 2026-06-06 - B42.19 rebase + off-road drag + per-wheel skids + MP skid sound

- **Per-wheel skid marks (Lua + Java).** The marks now anchor to each
  vehicle's actual rear-wheel positions instead of a single sprite at
  the centerline. Lua reads the vehicle script's wheel offsets and
  transforms them per-tick to world coords; sprite is an omnidirectional
  soft blob so curves trace as actual curves instead of polygons from
  the four-bucket orientation system. New Java patch on IsoSprite (BVD-
  scoped `BVD_renderTireMark` method) bypasses the integer-pixel snap
  and scales the sprite by tile scale so consecutive blob stamps blend
  into a smooth continuous line at any zoom level.
- **Permanent MP skid-sound fix (Java).** Replaced the entire Lua
  heartbeat model (`BVD_SkidSound.lua`, `BVD_SkidSync_Server.lua` —
  both deleted) with a per-client Java path in `CarController.update-
  Skidding`. Each client computes its own `wheelInfo[i].skidInfo` from
  local physics and drives its own emitter start/stop — no Start/Tick/
  Stop commands cross the network, no watchdog, no shared state. The
  looping bugs that v0.1.3 → v0.1.6 each patched a different symptom
  of are now structurally extinct: there is nothing for two clients
  to disagree on. Sound script renamed `BVD_SkidTile` → `BVD_SkidMP`
  with `loop=true` to force a clean FMOD re-registration.
- **Off-road drag halved (Java).** User report: "trucks and SUVs barely
  40 mph in 2nd gear off-road, max OffroadGrip / OffroadFloor do not
  help, RollResistanceOffroad to min only helps a little." Root cause:
  the off-road drag formula in CarController had a speed-dependent term
  (`0.01F * absSpeed`) that was 10x its on-road counterpart. Combined
  with the `mass * 1/eff` multiplier for low-OffroadEfficiency vehicles
  (trucks, SUVs), drag compounded quadratically with speed and ate
  most of the engine torque past ~40 km/h on grass. Halved to
  `0.005F * absSpeed`. Grip was not the bottleneck; drag was.
- **Surface-grip safety clamp (Java).** Defensive `if (surfaceGrip <
  0.05F) surfaceGrip = 0.05F` in the off-road branch of `updateTire-
  Stats`. Protects against a misconfigured tire profile or sandbox
  combination producing negative grip (which would invert the
  gripLimit feed and pull the car backwards). No effect under default
  settings.
- **OffroadGrip tooltip rewrite (Lua).** Old tooltip didn't say
  "HIGHER = more grip", so users raising it weren't sure it was
  actually helping. New tooltip is explicit: "HIGHER = more grip (less
  tire slip) on dirt, grass and gravel. Default 0.85 = moderate slip;
  1.5 = near-paved feel. Does not change rolling drag — tune that via
  Rolling drag off-road."
- **B42.19 rebase.** Necroid Java patches rebased onto the 42.19
  pristine. All BVD patches (CarController, WorldSimulation, Texture,
  IsoChunkMap, IsoFloorBloodSplat, IsoSprite) applied cleanly — no
  behaviour-affecting decompiler drift from TIS's 42.19 changes.
- **Manual install bundle renamed** `B42.18_Manual_Install/` →
  `B42.19_Manual_Install/` with freshly-compiled 42.19 .class files.
  Dedicated-server users redo the manual install once for this update,
  which covers the rebase AND all the changes above — a single install
  dance instead of one per fix.


- **B42.19 compatibility:** Necroid Java patches rebased onto the
  42.19 pristine. All 5 patches (CarController, WorldSimulation,
  Texture, IsoChunkMap, IsoFloorBloodSplat) applied cleanly against
  the new vanilla bytes - no behaviour-affecting decompiler drift.
- **Off-road drag halved (Java).** User report: "trucks and SUVs
  barely 40 mph in 2nd gear off-road, max OffroadGrip / OffroadFloor
  do not help, RollResistanceOffroad to min only helps a little."
  Root cause: the off-road drag formula in CarController had a
  speed-dependent term (`0.01F * absSpeed`) that was 10x the on-road
  counterpart. Combined with `mass * 1/eff` for low-OffroadEfficiency
  vehicles (trucks, SUVs), drag compounded quadratically with speed
  and ate most engine torque past ~40 km/h on grass. Halved to
  `0.005F * absSpeed`. Grip was not the bottleneck; drag was.
- **Surface-grip floor (Java).** Belt-and-braces clamp: surfaceGrip
  is now clamped to >= 0.05F before being folded into gripFactor.
  Protects against a published tire profile or misconfigured sandbox
  pushing the value <= 0 (which would have inverted the gripLimit
  feed and pulled the car backwards). No effect under default
  configuration; defensive only.
- **OffroadGrip tooltip rewrite (Lua).** Old tooltip didn't say
  "HIGHER = more grip", so users raising it expecting better
  behavior weren't sure it was actually helping. New tooltip is
  explicit: "HIGHER = more grip (less tire slip)" + a reference
  point ("default 0.85 = moderate slip; 1.5 = near-paved feel") +
  a pointer to Rolling drag off-road for drag tuning.
- **Manual install bundle renamed** B42.18_Manual_Install ->
  B42.19_Manual_Install with freshly-compiled 42.19 .class files.
  Users on dedicated servers must redo the manual install once for
  the 42.19 update; this single re-install carries both the version
  rebase AND the off-road drag fix.

## [0.1.7] - 2026-05-29 - Bundled KI5 reference pack (458 entries)

- New `BVD_Pack_KI5.lua` covers every drivable KI5 vehicle in the
  canonical "KI5's vehicle collection" (Steam Workshop 2490220997):
  **458 unique script entries** across 85 KI5 mods, with real-world
  hp / mass / cargo for the base car AND mechanically-distinct
  variants (F150 vs F250 vs F350, K10 vs K20 vs K30, Defender 90 vs
  110 vs 130, Hilux SC/XC/XCS, R/T vs Hemi 'Cuda, etc.).
- Cosmetic skin variants (e.g. the 60+ E150 liveries, the 30+
  Step-Van shops, the police skins) share the base car's specs.
- Burnt-out variants are skipped.
- Auto-registers via OnGameBoot, gated by:
  - `targetScriptPresent` predicate -> no KI5 installed = no-op
  - Priority 5 (under community pack's 10) so user overrides win
  - Existing-key skip avoids "replacing existing" log spam
- Net effect: with HP/Weight Realism enabled, every drivable KI5
  vehicle now gets a sensible real-world performance baseline
  without per-mod configuration.
- Pure Lua addition. No Java change, no manifest change.

## [0.1.6] - 2026-05-21 - Skid sound: rename event to flush cached loop=true

- v0.1.5 changed BVD_SkidLoop to loop=false at the script level, but
  reports kept coming. Root cause: PZ's audio engine caches sound-script
  registrations across world loads. A script-only loop=true -> false
  change on the SAME event name does NOT always flush the cached
  loop=true property in FMOD's runtime state.
- Fix: renamed the event from BVD_SkidLoop to BVD_SkidTile. PZ must
  register the new name fresh, picking up loop=false from scratch.
  The old BVD_SkidLoop registration becomes dead state - no code path
  references it anymore.
- No Lua logic change; only the event name and the EVENT_NAME constant
  in BVD_SkidSound.lua.
- Lua + media script change. No manual install update needed.

## [0.1.5] - 2026-05-21 - Skid sound: non-looping clip (real fix)

- Fix (regression chain from 0.1.3 / 0.1.4): in MP the skid sound kept
  looping at fixed points on the map even after the per-client refactor.
- Root cause finally diagnosed: BVD_Sounds.txt declared the sound with
  loop=true, so PZ's engine looped each instance natively. Every re-arm
  in the heartbeat model started ANOTHER permanent loop without being
  able to reliably stop the previous one (PlayWorldSound returns 0/nil
  in some paths, so the stop handle is invalid). Result: stacking
  loops at successive world positions.
- Fix: changed BVD_SkidLoop sound script to loop=false. Each play is
  one ~2 s tile that expires naturally. The Lua heartbeat code re-arms
  at REFIRE_MS (1.8 s) to tile consecutive clips with no audible seam.
  No stopSound dependency anywhere - when the driver stops sending
  heartbeats, re-arms stop, the last clip plays out, sound dies.
- Lua + media script change. No manual install update needed.

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
