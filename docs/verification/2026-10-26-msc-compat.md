# Maskarad's Summer Car compatibility - in-game verification (2026-10-26)

Build 42.21.0, ZombieBuddy 2.3.4, BVD v0.1.17 candidate. MSC = Workshop 3790160840 v0.1.5 (Lua only).

## Reproduction (v0.1.16)
Both mods loaded, `msc` mode (tools/autotest/BVDTests, scratch config pointing at the downloaded MSC mod).
`NullPointerException` at `BvdCar.update` (`engineBox.getFirstTag(tagGearbox)`) via
`ItemContainer$TagPredicate.init` -> `Objects.requireNonNull`. The ZB layer disabled itself ("driving is
vanilla until restart"). Cause: MSC's Engine part has a container; BVD's six `ProjectSummerCar:*` tags are null
without that mod.

## Fix
`partPackLoaded()` gate where `engineBox` is taken. Source diff against v0.1.16 is only that method and the one
condition (checked by rebuilding the old patched source and diffing).

## Results with the fix
- `msc` (MSC + BVD, ZB layer): PASS 9/9, 0 NullPointerExceptions. Car steers (139 deg), brakes to a stop, layer
  stays active, BVD readout published (laden 1.62, i.e. MSC's engine adds ~158 kg through the engine container).
- `sp` (plain cars): PASS 12/12, 0 console errors.
- `mp` (dedicated server without ZombieBuddy; client A drives, client B watches): A PASS 12/12, B PASS 4/4,
  server 0 errors. (One earlier MP attempt lost its server and client B with no error in the logs - processes
  killed from outside - and was rerun from scratch.)

## Not covered
- Manual-install path in game (same source, compiled classes refreshed; not installed to the game for testing).
- Real MSC saves, MSC multiplayer.
- BVD load penalty with MSC's engine weight (known, unchanged): MSC car 33.5 km/h vs 39.5 km/h in 6 s.
