# v0.1.19 - modded cars, off-road model, realism rules

Singleplayer, in game, `tools/autotest/BVDTests` (measurement tool `Ki5.lua`, scratch config pointing at the
KI5 downloads and the RVs/Heavy Duty/Trailers pack). Full throttle from a standstill, speed after 3 s and 5 s,
on a road start and on a strictly clear grass patch (floor is the only object on every square).

## What was run on the code that shipped

| Mode | What | Result |
|---|---|---|
| `rules` | realism rules over 480 combinations of script power, mass and registration (never weaker or lighter than the script, power ceiling, mass cap, repeatable, unregistered cars treated plainly) | 5/5 pass |
| `ki5` | 6 KI5 cars + CarNormal, default settings, road and clear grass | ran, no errors; see the open point below |
| `ki5_real` | same cars, realism option on: rules applied twice change nothing, registered and unregistered follow the same rules, switching off restores the originals | 5/5 pass, all cars move on road and grass |
| `ki5_unreg` | KI5 cars removed from BVD's tables, realism on | all cars moved on road and grass (run before the power ceiling was added; the ceiling does not touch any of these cars, the strongest is 24600 against a 28000 ceiling) |
| `others`, `others_real` | RVs/Heavy Duty pack: box truck, ambulance, RV, step van, a 5900-force muscle car; realism off and on | all cars move on road and grass |

## Not run on the shipped build

The plain `sp` suite, `mp`, `msc`, `wheels`, `wheels_off` were last run on v0.1.18 and were NOT rerun on this
build. The owner asked to stop verifying and ship.

## Open point

Harness findings during this work: a freshly debug-spawned car sometimes never gets going, with or without BVD
in the mod list (measured with BVD removed), so the measurement tool retries it. Waking the car's physics
before the drive (`setPhysicsActive`) fixed the stuck spawns, but the last `ki5` run with it showed clear-grass
speeds levelling off near 21 km/h at 5 s, where runs without it had about 35 on the same code (the mod's
default-mode behaviour did not change between those runs). I believe this is the harness and not the mod, but
I did not confirm it with a run without the wake before shipping. If a user reports modded cars stuck near
20 km/h on grass after this update, this is the first place to look.

## Findings that shaped the release

- `VehicleScript.Load(name, body)` drops the last value of the body when it has no trailing comma (probe-proven
  on a vanilla script): BVD's realism code never applied masses and, for unregistered cars, never applied power.
- Realism's 4x lived in the Java and only for registered cars: an unregistered modded car was 4x weaker.
