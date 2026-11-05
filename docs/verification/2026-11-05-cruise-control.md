# "The car accelerates to max speed on its own" (Workshop report, 2026-11-05)

In game, singleplayer, `Base.CarNormal`, automatic.

- **No input:** `noinput` mode. A stock car and two strong modded-style cars (1300 kg / 14000, 2000 kg / 16000) with no keys
  stay at 0-1 km/h for 12 s; after a 1 s tap on the gas they roll to a stop. Cruise state false all the time
  (`no_input_nothing_moves.log`). Nothing in the physics pushes a car on its own.
- **The cause:** Left Shift is BVD's default drift key and the vanilla cruise-control key. Reproduced (`before_fix_cruise_runs_away.log`,
  mode `cruise`, old build): from 25 km/h, Shift + forward for 5 s switches cruise on (target 34 -> 54 -> 74 km/h); with every
  key released the car keeps accelerating to 72 km/h and holds it until a tap on the brake switches the cruise off.
  A car at a standstill cannot start it (Shift cancels the gas and cruise needs speed).
- **The fix:** `BVD_Drift.lua` publishes `driftOnCruiseKey` (drift key == the game's cruise key); `CarController.java`
  clears the cruise key while it is set. First attempt put the clear in `updateModOptions()` (runs every 60 ticks): test
  failed (`fix_attempt1_filter_in_wrong_method.log`); moved to `updateControlsCalculation()`.
- **After:** `after_fix.log`, `after_fix_with_gas_pedal.log`, 7/7. Default (shared key): cruise stays off, gas pedal registered,
  25 -> 53 km/h with Shift + forward held, 57 -> 30 km/h coasting 10 s after release. Rebound drift key
  (`BVD.testSharedKey = false`): vanilla cruise works as before (switches on, holds speed, a brake tap cancels it).
- Test mod: `noinput` and `cruise` in Ki5.lua; harness gained `PZTestShift` (pz-autotest, uncommitted there).
- Not run yet: the full regression (only needed before a release).
