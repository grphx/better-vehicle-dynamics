# BVD Lite — Lua-only drivetrain for Better Vehicle Dynamics

Date: 2026-10-16 · Status: written, awaiting user spec review
Background: `docs/LUA_ONLY_FEASIBILITY.md` (API audit + probe results).

## 1. Goal

Make Better Vehicle Dynamics work **without the Necroid Java bundle**, keeping the
part players feel most — torque curves, gearing, grip — so the Workshop mod is
usable with no manual install and survives PZ updates without a Java rebase.

Success criteria:
- With Java absent, a car accelerates per a torque curve + real gear ratios: acceleration
  changes with RPM and steps at shifts according to BVD's ratios, not vanilla's chain.
- Top speed emerges from power vs drag (no hard vanilla cap), within ±10% of the
  target computed from the vehicle's HP and drag settings.
- Grip varies per wheel with surface, weather, tyre wear and weight transfer.
- Works in SP and MP (dedicated server, mixed Full/Lite clients).
- With Java present, behaviour is unchanged from today's BVD Full (Lite inert, no Lite writes).
- No permanent change to any vehicle's engine stats survives exit/save/quit/crash.

## 2. Decisions (user-approved)

| Topic | Decision |
|---|---|
| Packaging | Same Workshop mod (`BetterVehicleDynamics`), auto mode: Full if Java present, else Lite. No new listing, no new images. |
| MP | SP + MP in v1. Mode is per client. |
| Tyre marks | Full-only. Lite draws none. |
| v1 features | Drivetrain (curve + virtual gears + shaping), real drag/top speed, torque-curve archetypes, weight-transfer grip, manual gears + kickdown. |
| Deferred to v1.1 | Drift approximation, skid sound, fuel-by-load, stability guard, live tuning overlay. |
| Never in Lite | Analog pedals, steering tuning, shove/foliage/corpse scaling, tyre marks (Java-only). |

## 3. Verified engine facts this design relies on (pristine 42.21)

- Bullet receives one drive float: `Bullet.controlVehicle(id, engineForce, brakingForce, steering)`
  (`CarController.java:328`). Gears/RPM exist only inside Java's computation of that float.
- `control_ForwardNew` (`CarController.java:683-800`) computes
  `engineForce = getEnginePower() × chain(state)`; every chain term is Lua-readable;
  `BaseVehicle:setEngineFeature(quality, loudness, power)` is Lua-callable.
- **Probe 2026-10-16:** inverse shaping held acceleration constant (~13.5 km/h/s) across gears
  1–3, 14–91 km/h; accel ≈ 0.0061 × predicted force in both vanilla and shaped runs; zero
  external power resets in SP.
- Vanilla road drag is negligible → Lite must supply drag.
- Physics runs only on the authorized driver client; server never steps Bullet.
- `VehiclePart:setWheelFriction` is pushed to Bullet every tick (`BaseVehicle.java:9408`), but
  `updatePartStats()` (`:9225-9249`) rewrites it from the tyre item.
- `applyImpulseGeneric` forces are consumed in the first 10 ms substep, ×30, capped
  `1500 × fudgedMass` (`BaseVehicle.java:3632-3672`), driver-client only.

## 4. Architecture

New files in `workshop/BetterVehicleDynamics/42.20/media/lua/` (mirrored to the `42` tree as today):

| File | Side | Responsibility | Depends on |
|---|---|---|---|
| `client/BVDL_Runtime.lua` | client | Mode detection, per-tick loop for local driver, power safety (save/restore), publishes `BetterVehicleDynamicsMod.computed`, kill-switch per vehicle | all BVDL modules, `BVD_Config` |
| `shared/BVDL_Engine.lua` | shared | Torque-curve archetypes, archetype selection, rated torque from HP | `BVD_VehicleData`, `BVD_API` |
| `shared/BVDL_Gearbox.lua` | shared | Virtual gear + RPM state machine, auto shift w/ hysteresis + kickdown, manual mode | — |
| `shared/BVDL_Shaper.lua` | shared | `chain(state)` mirror of vanilla, inversion to engine power, singular-zone guards | — |
| `shared/BVDL_Drag.lua` | shared | Aero + rolling drag force from speed, surface, sandbox knobs | `BVD_Config` |
| `shared/BVDL_Grip.lua` | shared | Per-wheel friction: base (from tyre item), surface/weather/wear multipliers, weight transfer | `BVD_Config`, `BVD_Tires` |

Pure-math modules (Engine, Gearbox, Shaper, Drag, Grip) take plain numbers/tables and return
numbers — no game calls — so they can be unit-tested headless with a stock Lua 5.1 interpreter.
Only `BVDL_Runtime` touches the game API.

Existing files changed:
- `client/BetterVehicleDynamics.lua`: `BetterVehicleDynamicsVersionCheck` no longer shows the
  "not installed" modal; it hands off to `BVDL_Runtime` (the "outdated Java" modal stays).
- `client/BVD_HUD.lua` / `client/BVD_RuntimeChecks.lua`: read `computed` unchanged; add a
  `mode` field display (`Full` / `Lite`).
- `shared/BVD_API.lua`: `BVD.registerVehicle` accepts optional `engine` (archetype id) and
  `gearbox` (ratio array) fields; validated like existing fields.
- Translations (`Translate/EN/*.json`): new strings for mode label + any new sandbox options.

## 5. Mode detection

1. `BetterVehicleDynamicsMod.javaVersion` is written by the Java `CarController` constructor.
2. On the local player's first vehicle entry (`OnEnterVehicle`) — after at least one controller
   has been constructed — `BVDL_Runtime` reads it:
   - `"3.4"` (or any non-`"not installed"` value) → **Full**: Lite stays inert for the session.
   - `"not installed"` → **Lite**: activate.
3. Decision is per client and cached for the session; logged once as `[BVD] mode=Lite|Full`.
4. Dedicated server: Lite code never runs on the server (no physics there).

## 6. Per-tick pipeline (Lite, local driver only)

Runs on `OnTick` when: mode Lite, local player is driver, engine running, vehicle not kill-switched.

1. **Read state**: signed speed (km/h), forward/linear velocity, vanilla gear & RPM, engine
   power/quality/loudness, offroad flag, script, driver traits, towing, per-wheel parts,
   weather (rain/snow intensity), throttle-intent (see §7.4).
2. **Gearbox** (`BVDL_Gearbox.step`): wheel RPM from speed and tyre radius → engine RPM =
   wheelRpm × gearRatio × finalDrive; auto: upshift at `shiftUpRpm`, downshift at
   `shiftDownRpm` with hysteresis; **kickdown** when throttle is held and RPM < `kickdownRpm`
   in a gear whose lower neighbour stays below redline; manual mode: gear only changes on
   `forceGear` deltas from the existing ShiftUp/ShiftDown keybinds. Torque-converter slip below
   lockup (`LowSpeedGrunt` knob) as in Full's defaults (lockup 2000 rpm, band 800).
3. **Engine** (`BVDL_Engine.torque(archetype, rpm, ratedTorque)`): normalized curve × rated torque.
4. **Drive force** = torque × gearRatio × finalDrive / wheelRadius × `EnginePower` knob ×
   load response (if `LoadAffectsHandling`).
5. **Drag** (`BVDL_Drag.force`): `Drag × k_aero × v²` + `RollResistance(Offroad) × mass × g`.
6. **Target** `F* = max(0, drive − drag_on_throttle)`; shaped through `BVDL_Shaper`:
   `power = clamp(round(F* / chain), 1, base × POWER_CEILING)`.
   Guards: keep vanilla out of singular zones — `setMaxSpeed` raised to `max(script max, Lite
   top speed) × 1.3` while Lite drives (restored on exit), redline guard at 6900 vanilla rpm,
   chain < 0.02 → hand back.
7. **Off-throttle / excess drag + engine braking**: a single rearward `applyImpulseGeneric`
   from the centre of mass, scaled by the calibrated impulse→decel factor (§9 task C1).
8. **Grip** (`BVDL_Grip`): per wheel `friction = base × surface × weather × wear × transfer`,
   applied with `VehiclePart:setWheelFriction`; `base` re-read after any `updatePartStats`
   (detected by friction ≠ last written value).
   Weight transfer: longitudinal accel shifts load front↔rear by
   `Δ = mass × a × cgHeight / wheelbase` (cgHeight/wheelbase from script extents/wheel
   positions, clamped); friction scales with `(load/staticLoad)^0.8`, clamped [0.5, 1.4].
9. **Publish** `computed`: `mode, gear, rpm, torque, driveForce, drag, gripFL/FR/RL/RR,
   archetype, ladenRatio` for HUD/RuntimeChecks.

## 7. Components in detail

### 7.1 Torque-curve archetypes (`BVDL_Engine`)
Normalized torque vs normalized RPM (0..1 of redline), as 8-point piecewise-linear tables,
authored originally for this mod:

| Archetype | Character | Redline | Peak torque at |
|---|---|---|---|
| `diesel` | strong low end, early fade | 4200 | ~35% |
| `v8` | broad flat plateau | 5800 | ~45% |
| `inline4` | needs revs, peaky top | 6800 | ~70% |
| `sports` | strong mid-high | 7200 | ~65% |

Selection: `BVD.registerVehicle` `engine` field → else class rule from script name / existing
BVD vehicle class (trucks, vans, ambulances → `diesel`; luxury/station wagon/police → `v8`;
small/normal cars → `inline4`; sports → `sports`) → fallback `inline4`.
Rated torque from HP: `T_peak = HP × 7121 / (rpm_at_peak_power)` (HP→N·m), then scaled into
PZ force units by one calibration constant `K_FORCE` fit so a BVD-Full reference car (same
`EnginePower` knob) reaches 0–100 km/h within ±15% of Full (§9 task C2).

### 7.2 Gearbox (`BVDL_Gearbox`)
- Ratio sets reuse BVD Full's defaults (`DEFAULT_GEARBOX_3/4/5`, where index 0 is reverse):
  3-speed `{R 2.6 | 2.6, 1.6, 1.0}`, 4-speed `{R 3.0 | 3.0, 1.8, 1.3, 1.0}`,
  5-speed `{R 3.2 | 3.2, 2.0, 1.5, 1.15, 0.9}`; count from script `gearRatioCount` clamped 3..5;
  override via `BVD.registerVehicle{gearbox=…}` (same layout, reverse first).
- Shift points as fractions of archetype redline: up 0.85, down 0.45, kickdown below 0.55
  under sustained throttle (≥0.4 s); 0.35 s shift time during which drive force × 0.2.
- Reverse: the set's reverse ratio, capped at `ReverseTopSpeed`. Reverse shaping inverts
  `control_Reverse`'s chain (separate function in `BVDL_Shaper`).
- Manual mode (`BetterVehicleDynamicsMod.manualShift`): auto logic off; `forceGear` deltas
  shift; rev limiter at redline cuts drive force.

### 7.3 Drag (`BVDL_Drag`)
`F_aero = Drag_knob × Cd_A(class) × v²`, `F_roll = RollResistance × m × g` (offroad uses
`RollResistanceOffroad`, floored by `OffroadFloor`). `Cd_A` per class table (car/van/truck).
Top speed falls out where drive force at the top gear ≈ drag.

### 7.4 Throttle intent
Vanilla throttle isn't directly readable; Lite infers "on throttle" from the game's accelerate
binding (`GameKeyboard.isKeyDown` on the vehicle-forward keybind, plus joypad trigger where
exposed) — digital, as in vanilla. If neither is readable for an input device, fall back to
"vanilla force > 0" heuristics (engine power path only matters when vanilla is in
`control_ForwardNew`, which itself implies throttle).

### 7.5 Grip (`BVDL_Grip`)
Multipliers reuse BVD's existing knobs (`GripLevel`, `WetGrip`, `SnowGrip`, `OffroadGrip`,
`TireGripModel` + `BVD_Tires` profiles). Applied per wheel; never written when the computed
value is within 1% of the last write (avoid churn).

## 8. Safety & error handling

- **Power ledger**: before the first write to a vehicle, store original `{power, maxSpeed}` in
  vehicle modData `BVDL_orig`. Restore on: exit vehicle (polled + `OnExitVehicle` when
  available), `OnSave`, player death, mode change, disconnect/quit (`OnSave` covers SP quit;
  MP: restore on `OnDisconnect` if exposed, else on next entry).
- **Stale repair**: on any vehicle entry with `BVDL_orig` present and nobody shaping it,
  restore and clear.
- **Foreign writer detection**: if engine power ≠ last written value at the next tick (and no
  `updatePartStats` cause), log `[BVD] foreign power write` once and kill-switch that vehicle
  for the session (vanilla driving), restoring originals.
- **Errors**: each tick body runs in `pcall`; an error logs once with vehicle + module and
  kill-switches that vehicle. No per-tick log spam.
- Kahlua rules (`pz_kahlua_gotchas`): no `os.*`, dot-existence checks, no `%d` on numbers,
  `getTimestampMs()` for time.

## 9. Testing

**Headless unit tests** (stock Lua 5.1 via `tools/test_lite.sh`): Engine curves (monotonic
domains, peak locations), Gearbox state machine (shift up/down/kickdown/manual sequences),
Shaper (chain mirror reproduces probe numbers; inversion round-trip), Drag (top-speed solve),
Grip (transfer clamps, churn threshold).

**In-game calibration (first in the plan):**
- C1 impulse→decel factor: coast-down runs with known impulses.
- C2 `K_FORCE`: 0–100 km/h vs Full on 3 reference cars (requires temporary Java reinstall, or
  recorded Full numbers).
- C3 per-wheel friction → lateral grip: skidpad radius at fixed speed, dry vs wet.

**Scenario harness** (evolve `BVDTorqueProbe` into `BVDLiteBench`, local-only): 0–100 time,
top speed, coast-down 100→50, shift trace, wet/dry skidpad; prints a summary table.

**MP test**: local dedicated server + 2 clients (one Lite, one with Java): drive, swap drivers,
disconnect mid-drive, reconnect → no stuck power, no foreign-write kill-switch, no desync.

**Regression**: with Java installed, BVD Full behaviour unchanged (Lite inert — verified by
`computed.mode == "Full"` and no `BVDL_orig` writes).

## 10. Out of scope (v1)

Tyre marks, drift, skid sound, fuel-by-load, stability guard, live tuning overlay, analog
pedals, steering tuning, shove/foliage/corpse scaling, engine-sound pitch override.
