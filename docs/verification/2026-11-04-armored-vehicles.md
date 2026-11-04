# Armored vehicles "barely accelerate" (Steam report, 2026-11-04)

Report: the M1A1 Abrams (Workshop 3397147307) and Papa Chad's armoured vehicles (M113 2705655822, M163 3598575779,
M41 3608725379, M998 Humvee 3554424111) "more or less unable to accelerate". Tested the real vehicles, as shipped, with
their required mods (Military Tool Kit 2705406713, WarThunderVehicleLibrary 3399660368), in game, singleplayer,
flat out for 5 s. "van" = the same vehicles with BVD's Java part off (vanilla physics).

## What it was
The three tracked vehicles (M113, M163, M41) script `maxSpeed = 25`. BVD turns top speed into a gear scale
(`speedToRpm = 0.95 * redline / topSpeed`), which is ~171 for them against ~36 for a car. Wheel torque exceeds the
grip limit by that factor, so the wheel-slip integrator runs the driven wheels away on soft ground, the converter
unloads and the force collapses (engine at the rev limit 82-84 % of the time, at 7 km/h).

| grass, km/h at 3 s / 5 s | vanilla | BVD before | BVD after |
|---|---|---|---|
| M113 APC | 30 / 40 | 7 / 18 | 18 / 28 |
| M163 VADS | 31 / 40 | 10 / 26 | 21 / 28 |
| M41 Walker Bulldog | 31 / 40 | 8 / 24 | 22 / 29 |

Road: vanilla 35 / 42, BVD before 27-28 / 28, after 28 / 28 (they sit at the script's own 25 km/h + margin).

## Fix
`CarController.java`: the slip build-up is scaled by `min(1, 71.25 / speedToRpm)`, i.e. only vehicles whose top speed is
under 60 km/h; every car is bit-identical.

## Not changed, by design
- M1A1 (mass ~2150, force 14000, maxSpeed 90): road 40 / 60 km/h (vanilla 54-62 / 85); grass 22 / 42 (vanilla 39 / 55).
  Slower than vanilla, not stuck: BVD's general car tuning and off-road model.
- M998 Humvee: road 25 / 42 (vanilla 37 / 59). Same.
- The tracked vehicles stay at ~28 km/h on the road because BVD honours their `maxSpeed = 25`. Vanilla ignores it
  (40+ km/h). Open question for the owner: floor the gear mapping so they can go ~45-50.

## Test notes
- The Abrams library has its own bug (`GetHeliType` is nil in MainHeliCore.lua:42; `helicopterVisualSoundUpdate`) and
  throws thousands of Lua errors a run, with or without BVD. The Abrams spawns with a battery at 0 charge: the
  test forces the start. Not BVD.
- Harness: a Lua error froze the game on the Lua debugger (Break On Error under `-debug`); fixed with a ZombieBuddy
  patch in pzautotest. A watchdog (`pz-autotest/watchdog.py`) now classifies errors and reports stalls.
- Regression: `sp` 12/12, 0 watchdog errors (`evidence-2026-11-04-armor/regression_sp.log`).
