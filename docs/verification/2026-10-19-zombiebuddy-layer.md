# ZombieBuddy layer - in-game verification (2026-10-19)

Build 42.21.0, ZombieBuddy 2.3.4, branch `zb-and-comments`. Harness: `~/zomboid/pz-autotest`
(`tools/autotest.json`, test mod `tools/autotest/BVDTests`). No manual-install classes present; BVD's Java
loaded only through ZombieBuddy.

## Singleplayer (`pzat.py sp sp`, `-nosteam` so the Workshop subscription can't shadow the copy under test)
PASS 12/12, 0 console errors: layer active, tyre-mark helper exposed, `javaVersion` 3.4, enter, engine start,
accelerate (41 km/h), BVD `computed` readout published, vanilla `isGasPedalPressed` sees BVD state, steering
(127 deg change), brake to stop, no sinking.

## Dedicated server (`pzat.py mp`; server without ZombieBuddy/Java, two clients with it)
- Client A (driver): PASS 12/12.
- Client B (watcher): PASS 4/4 - sees A's car with a driver, sees it move 13.4 tiles, BVD readout stays local.
- Server: 0 errors mentioning BVD; no "not installed" spam (forbidden pattern).

## Bugs found by these runs
- Skipping vanilla `updateControls` also skipped other mods' advice on it (ZB applies later mods' advice
  outermost). Fixed: hook is now OnExit + `readPedals()` only.
- Test-side: Workshop shadowing in Steam-mode SP (added harness `sp_nosteam`), random-condition debug spawns
  (repair/fuel/battery/unlock), parked cars within 45 tiles, MP engine start must go through the server.

## Not covered yet
- Manual install AND ZombieBuddy both present (ZB layer should stand down).
- Mixed MP: one client on ZombieBuddy, one on the manual install.
- Feel/balance parity vs the manual install (owner playtest).
- Review footage: `media/review/` (published privately); brake-mark and corner shots still to re-stage.
