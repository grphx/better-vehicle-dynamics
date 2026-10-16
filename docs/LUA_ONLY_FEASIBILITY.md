# Can BVD go Lua-only? (audit 2026-10-16, against pristine 42.21)

Verdict: a **Lua-only "BVD Lite"** is realistic at roughly **45–55% of the felt
difference**; the drivetrain core needs Java. Recommended: ship Lite on the
Workshop (no manual install, survives PZ updates) and keep the Necroid bundle
as optional **BVD Full**, detected via the existing `javaVersion` handshake —
Lite disables its per-tick writes when Java is present.

## What Lua can reach (verified in pz-research/lua-api/lua-api.txt + pz-src)
- `CarController`, `Bullet`, `WorldSimulation` are **not exposed**. `getController()` returns an opaque object.
- `VehiclePart:setWheelFriction(f)` — **per-wheel grip**, pushed to Bullet every tick
  (`BaseVehicle.java:9408`, `data[offset+2] = frictionMul * part.getWheelFriction()`).
  The patch comment "PZ exposes no per-wheel friction" (CarController patch ~L1665) is wrong for Lua.
  Caveat: `updatePartStats()` (`BaseVehicle.java:9225-9249`) rewrites it from the tire item
  (condition, mechanic skill, cap 2.3) — store the base, multiply, re-apply after part changes.
- `BaseVehicle:applyImpulseGeneric(fromX,fromY,fromZ, dirX,dirY,dirZ, strength)` — force + torque
  (off-centre origin), consumed in the first 10 ms substep, ×30, capped `1500*fudgedMass`
  (`BaseVehicle.java:3632-3672`, `WorldSimulation.java:106`); only on the authorized driver client.
- `VehicleScript:Load(name, "{ ... }")` + `toBullet()` — retune mass, engineForce, gearRatio*,
  rollInfluence, steeringIncrement/Clamp, suspension*, wheelFriction, stoppingMovementForce,
  maxSpeed(Reverse), offRoadEfficiency, centerOfMassOffset (`VehicleScript.java:144-253,562-575`).
  Shared by every vehicle of that script.
- Also: `setMass/updateTotalMass`, `setMaxSpeed`, `setBrakingForce`, `setEngineFeature(q,loud,force)`,
  `setRegulatorSpeed`, `setTireInflation`, `get/setWorldTransform`, `getLinearVelocity`,
  `getForwardVector`, `getMinWheelSkid`, `isDoingOffroad`.

## Feature verdicts (A = Lua, B = approximate, C = Java-only)
| Feature | Verdict |
|---|---|
| Grip model (surface/weather/tire wear/profiles) | **A** — per-wheel `setWheelFriction` (better than today's script-wide Load) |
| Coast-down `stoppingMovementForce=0.01`, HP/mass, tire inflation=1, HUD | **A** |
| Aero + rolling drag | **B** — counter-velocity `applyImpulseGeneric` per tick, recalibrate ×30 and dt |
| Arcade drift | **B** — rear friction cut + yaw impulse; steering input must be polled from keys/joypad; faster steering rate impossible |
| Braking strength, keyless tow brake | **B** — `setBrakingForce` after part stats |
| Load response, reverse cap, low-speed grunt | **B** — `setEngineFeature` scaling / `maxSpeedReverse` (shared per script) |
| Stability guard | **B** — world transform (Transform field access unverified) |
| Skid + engine sound | **B** — `getMinWheelSkid` + emitter; can't mute vanilla engine |
| Torque curve, RPM integration, gearbox, converter, manual/analog pedals, wheelspin, steering dynamics, trait throttle, cruise logic | **C** — values passed to `Bullet.controlVehicle` are private locals in `CarController.update()`; vanilla rewrites RPM/gear/steer each tick |
| Shove/foliage/corpse impulse scaling | **C** — private impulse lists |
| Skidmark decals as implemented (types 21-24, fade) | **C** — `FLOOR_BLOOD_TYPES` has 21 entries; Lua-only needs a different render technique |

MP: physics runs only on the driver client (server never steps Bullet) → Lite logic is client-side for the local driver's vehicle.

## UPDATE 2026-10-16: torque curve IS reachable from Lua ("inverse shaping")

The audit above marked torque curve / gearbox as C. Closer reading of the vanilla
forward path says otherwise — at least for the *force* the car feels.

**Key facts (pristine 42.21):**
- Bullet never sees gears or RPM. The only drive input is the single float passed to
  `Bullet.controlVehicle(id, engineForce, brakingForce, steering)` (`CarController.java:328`).
  Gears/RPM are just multipliers inside Java that produce that float.
- In `control_ForwardNew` (`CarController.java:683-800`, dispatched at :272) that float is a
  deterministic chain whose only free input is **`vehicle:getEnginePower()`**:
  `power × (1.5 if gear 1) × (0.3 + rpm/30000) × (1 − speed/200) × redline((7000−rpm)/1000 if rpm>6000)`
  `× traits (Sunday Driver 0.75 / caps) × maxSpeed cap × towing × parking-brake ×8 × MP speedLimit`,
  then `checkTire` (flat tyres) and off-road `limitMod` (gear, towing, `offroadEfficiency`) (:306-322).
- `getEnginePower()` = `VehicleEngine.getPower()`, set by Lua-exposed
  `BaseVehicle:setEngineFeature(quality, loudness, power)` (`BaseVehicle.java:8230`).
- Every other term is Lua-readable: `getEngineSpeed`, `getCurrentSpeedKmHour`, `getTransmissionNumber`,
  `getMaxSpeed`, `isDoingOffroad`, `getScript():getOffroadEfficiency()`, driver traits, towing.

**Technique:** each tick on the driver client, compute our own virtual RPM from wheel speed and
BVD's gear ratios + shift hysteresis, look up torque on our curve (converter slip, grunt, load,
redline), convert to desired drive force `F*`, then
`setEngineFeature(q, loud, round(F* / vanillaFactor(state)))`. Vanilla's chain cancels and Bullet
receives ~`F*`. Because the force goes through the wheel engine force (not a body impulse),
**Bullet's own tyre slip still applies** → wheelspin/traction limits emerge naturally with
per-wheel `setWheelFriction`.

**Expected fidelity:** force-vs-speed character (the "feel") ≈ Java BVD, with 1 tick lag
(we read last tick's RPM; vanilla's RPM ramps ≤10/tick so the error is tiny).

**Remaining limits / risks (must probe in-game):**
1. Engine braking / negative torque: power can't go negative → emulate with `setBrakingForce`
   or a counter `applyImpulseGeneric` when off-throttle.
2. Singularities: redline factor → 0 above 7000 rpm, maxSpeed cap past maxSpeed → keep vanilla
   out of those zones (`setMaxSpeed` high, clamp our divisor, cap power).
3. RPM *heard* is vanilla's (engine sound pitch follows `getEngineSpeed`). Options: accept, or
   `setEngineSpeed(virtualRpm)` after vanilla's update — but vanilla's shift logic reads it too
   (harmless for force since we invert it, but gear display/shift timing would follow ours).
   Tick-order of OnTick vs vehicle update needs a probe.
4. `power` persists: it's the engine part's real stat (saved, shown in mechanics UI, network field
   `network/fields/vehicle/VehicleEngine.java`). Store the base value, restore on exit-vehicle,
   OnSave and quit; check whether the server re-sends it to the driver in MP.
5. Throttle is digital in vanilla — analog pedals and manual-gear *input* still need Java.
   (A Lua manual-gear mode via our own keybinds is possible since gears are virtual.)
6. Reverse uses `control_Reverse` (different chain) — needs its own inverse.

**Probe plan:** client Lua on OnTick logs `getEngineSpeed, getCurrentSpeedKmHour,
getTransmissionNumber, getEnginePower` and sets a constant `F*` via inversion; verify on a flat
road that acceleration is constant (force flat) across gear changes. Then swap in a real curve.

**Probe built (2026-10-16):** `C:\Users\Grphx\Zomboid\mods\BVDTorqueProbe\` (local only, SP only).
F9 cycles OFF → OBSERVE → FLAT. Logs `[BVD-PROBE]` lines + per-gear mean-acceleration summary
to console.txt. Refuses to run if the BVD Java override is installed (`javaVersion` handshake),
because the inversion assumes vanilla `CarController`. Also logs `power changed outside the probe`
if anything rewrites engine power between ticks (answers risk 4).

## PROBE RESULT 2026-10-16 — inverse shaping WORKS (on-road, SP, base power 4800)

| Run | Gear | Speed km/h | Force (predicted) | Accel km/h/s |
|---|---|---|---|---|
| vanilla OBSERVE | 1 | 5–48 | ~2300 | ~13.5–14 |
| vanilla OBSERVE | 2 | 25–53 | ~1500 | ~9 |
| vanilla OBSERVE | 3 | 53–78 | ~1300 | ~8 |
| FLAT (target 2160) | 1 | 14–25 | 2160 | ~13.2–14 |
| FLAT | 2 | 26–58 | 2160 | ~13.3–13.7 |
| FLAT | 3 | 61–91 | 2160 | ~13.1–14.0 |
| FLAT handed back (>92% maxSpeed) | 3–4 | 93–109 | 1077→518 | 8→3.5 |

- FLAT holds acceleration constant across gears 1–3 and 14–91 km/h, while vanilla steps down at every
  shift. Both modes fit accel ≈ 0.0061 × predicted force → the chain model is exact enough and Bullet
  receives the force Lua chooses.
- Implication: vanilla has almost no speed-dependent drag on paved road at these speeds — all of BVD's
  aero/rolling drag must be supplied by us (impulse or by folding it into the target force).
- `power changed outside the probe`: 0 occurrences (SP). MP still untested.
- Off-road samples (grass) accelerate much less at the same predicted force (Bullet off-road friction),
  as expected; the off-road limitMod term inverted cleanly (no clamps logged).
- Vanilla RPM is synthetic (pins at 3000 in gear 1 while crawling) → BVD Lite must run its own virtual
  RPM/gears; vanilla RPM only matters for the engine sound pitch.

Next: virtual gearbox + real torque curve on top of the FLAT plumbing; drag term; reverse chain;
engine-braking emulation; MP test (does the server re-send engine power?).
