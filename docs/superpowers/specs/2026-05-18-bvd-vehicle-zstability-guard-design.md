# BVD Vehicle Z-Stability Guard — Design

**Status:** approved 2026-05-18
**Goal:** A proactive, server-authoritative safety net that detects a vehicle
sunk implausibly below its own floor resting height and snaps it back, to
mitigate the "cars clipping / sucked into the ground" multiplayer desync
class observed with predecessor/upstream physics mods. BVD's clean
re-authored physics is not believed to cause this, but the guard hardens
BVD servers against the whole class regardless of cause.

**Architecture in one line:** generic *frozen* Java touchpoint in
`CarController` reads a Lua-tunable `stabilityGuard` policy off the
`BetterVehicleDynamicsMod` bridge (identical mechanism to `loadResponse`),
sandbox-gated, parity-safe; bundled into the current one-time Necroid
freeze so all future tuning is Lua-only with no manual reinstall.

---

## 1. Decisions (locked during brainstorm)

- **Correction mode:** snap the vehicle back to its computed floor resting
  height immediately (re-seat), not eased, not clamp-only.
- **Trigger scope:** *sunk below floor only* — a vehicle whose Z is below
  its own `restingZ` by more than a margin. No handling of flung /
  stuck-airborne (out of scope; far higher false-positive risk).
- **Approach:** in `CarController`'s existing per-tick path, reusing the
  `restingZ` value `CarController` already computes (no re-derived floor
  math → no divergence). Not a `WorldSimulation` sweep.
- **Default:** sandbox toggle defaults **ON** (pure safety net; by
  construction only ever touches an already-invalid state).

## 2. Why "below own floor" is false-positive-proof

`CarController` already computes `restingZ` — the correct chassis height
for the vehicle's current tile floor — as
`PZMath.fastfloor(z) * 3 * 0.8164967 - min(wheelLow, chassisLow)`, lower-
clamped to `fastfloor(z) * 3 * 0.8164967 + 0.1`. Legitimate elevation
changes (ramps, multi-level garages, jumps, towing, slopes) move a
vehicle **at or above** a floor level, never *below* its own local floor.
Therefore "Z is below `restingZ` by more than `sinkDepth`" is a state
that is never legitimate in normal play, so correcting it cannot harm
ramps/garages/jumps/towing. This single rule is the core safety argument.

## 3. Bridge contract addition

Lua publishes `BetterVehicleDynamicsMod.stabilityGuard` (a table), read in
`CarController` via the existing `bvdBridge()` +
`bridgeFieldOr(table, field, fallback)` helpers. `protocolVersion` stays
`1`: the field is additive and optional, feature-detected by presence;
older Lua that never publishes it leaves the guard inert.

Fields (every read via `bridgeFieldOr` with a NO-OP-safe fallback):

| field          | type  | fallback | meaning |
|----------------|-------|----------|---------|
| `enabled`      | float\* | `0` (off) | guard active when `>= 0.5` |
| `sinkDepth`    | float | `1.0` | world-Z units below `restingZ` that counts as impossible |
| `dwellTicks`   | float | `5`   | consecutive offending controller ticks before correcting (debounce) |
| `cooldownTicks`| float | `60`  | minimum controller ticks between corrections for the same vehicle (anti-thrash) |

\* booleans cross the Kahlua bridge as numbers, matching how
`loadResponse.enabled` is already handled; Lua publishes `1`/`0`.

If `bvdBridge()` is null, or the `stabilityGuard` key is absent, or
`enabled < 0.5`, the touchpoint returns immediately — behaviour is
byte-identical to today.

## 4. Detection & correction (the touchpoint)

Location: `CarController`, the per-tick path that already calls
`publishComputedState()` (the path BVD owns and that compiles).

Logic, in order:

1. **Authority gate.** If `GameClient.client` (a remote MP client), return
   — remote clients render server-synced transforms; correcting locally
   would fight the server. Runs only on SP and the server/host.
2. **Policy gate.** Resolve `stabilityGuard`; if null/absent/`enabled<0.5`,
   return.
3. **Compute / reuse `restingZ`** for this vehicle using the same
   expression `CarController` already uses for the Bullet seat (single
   source of truth — no second floor formula anywhere).
4. **Sink test.** Let `liveZ` be the vehicle's current physics Z. It is
   "sunk" iff `liveZ < restingZ - sinkDepth`.
5. **Debounce.** Per-vehicle-controller counter `sinkTicks`: increment
   while sunk, reset to 0 when not sunk. Only act when
   `sinkTicks >= dwellTicks`.
6. **Cooldown.** Per-controller `ticksSinceCorrection`; only act when it
   `>= cooldownTicks`. On a correction, reset it to 0 and `sinkTicks` to 0.
7. **Correct.** Re-seat the vehicle at `restingZ` using the same Bullet
   transform-seat operation BVD performs at vehicle init, and zero the
   vehicle's vertical velocity component so it does not immediately
   re-sink the next tick.

Counters (`sinkTicks`, `ticksSinceCorrection`) are plain instance fields
on the `CarController` (one controller per vehicle), so state is naturally
per-vehicle with no maps or allocation.

An optional throttled log line (at most once per correction, not per
tick) records that a recovery occurred, so server admins can confirm the
guard is doing real work in the field. It is gated so it cannot spam.

## 5. Sandbox + Lua

- New sandbox options on the **Handling** page (`42` and `42.18`,
  identical):
  - `BetterVehicleDynamics.StabilityGuard` — boolean, default `true`.
  - `BetterVehicleDynamics.StabilityGuardSinkTiles` — double, default
    `0.75`, range `0.25`–`3.0` (in PZ floor-levels; Lua converts to
    `sinkDepth` world-Z units via the `* 3 * 0.8164967` level height).
- EN strings in `Translate/EN/Sandbox.json` (label + tooltip, plain
  English, no jargon).
- `BVD_Config`: add `StabilityGuard` and `StabilityGuardSinkTiles` to
  `KEYS` and `buildCfg()`; add `publishStabilityGuard()` mirroring
  `publishLoadResponse()` (sets `enabled`, `sinkDepth`, `dwellTicks=5`,
  `cooldownTicks=60`), called at the same two sites the other publishes
  use (module-load initial publish + `onLiveTick` re-read). `dwellTicks`
  and `cooldownTicks` are authoring constants in Lua (tunable later with
  no reinstall); only `enabled` and `sinkDepth` track sandbox at runtime.

## 6. Parity / safety / MP correctness

- **NO-OP guarantee:** absent or disabled policy ⇒ immediate return ⇒
  byte-identical to the current build. The empty-bridge path is the
  default and is exercised by the existing parity tests.
- **Cannot harm normal play:** only ever moves a vehicle that is below its
  own floor — a state unreachable by legitimate driving.
- **MP authority:** only SP/host correct; remote clients untouched ⇒ no
  client/server fight, no double-correction.
- **Anti-thrash:** dwell + per-vehicle cooldown bound corrections.
- **One freeze:** ships with the current Necroid Java; thereafter
  `sinkDepth`/`enabled` are sandbox, `dwell`/`cooldown` are Lua —
  zero future manual reinstalls for tuning.

## 7. Testing & honest limitations

Objective gates (the project's "tests"):
- `necroid test` → `test build OK` (Java compiles).
- `./tools/grepgate.sh` PASS (no banned provenance tokens; this doc
  included — uses "predecessor/upstream mod" wording only).
- Staged-tree assertion (mod ROOT rsync, `42`==`42.18` sandbox).
- **SP parity smoke (USER):** drive normally across slopes, ramps,
  multi-level parking, towing, jumps for a session → expect **zero**
  corrections and unchanged feel. Any spurious correction is a failure.

**Honest limitation (in scope by acknowledgement, not by omission):**
no multiplayer reproduction of the predecessor desync exists, so true
MP efficacy is **field-validated by server admins**, not lab-proven
here. The design is justified *by construction* — it corrects a
provably-invalid state (vehicle below its own floor) — rather than by
reproducing the upstream bug. Success signal in the field = admins see
the throttled recovery log fire and players stop reporting buried cars;
the guarantee we make is parity-safety and soundness, not a promise to
cure PZ netcode.

## 8. Out of scope (YAGNI)

- Flung / stuck-airborne correction.
- Eased/clamp correction modes.
- Per-vehicle-type tuning.
- Diagnosing the predecessor mod's root cause.
- Any client-side correction.

## 9. File touch list (for the plan)

- Modify (seeded → necroid capture): `CarController.java` — add the
  guard touchpoint + per-instance counters; reuse existing `restingZ`.
  (The one-time freeze; mirror patch into
  `mods/better-vehicle-dynamics-42/patches/...`.)
- Modify: `workshop/BetterVehicleDynamics/42.18/media/lua/shared/BVD_Config.lua`
  — `KEYS`, `buildCfg()`, `publishStabilityGuard()` + call sites.
- Modify: `workshop/BetterVehicleDynamics/{42,42.18}/media/sandbox-options.txt`
  — two options, Handling page, identical in both.
- Modify: `workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json`
  — label + tooltip for both options.
- Modify: `README.md` — document the guard + that it is Lua/sandbox-tunable.
- Gate: `./tools/grepgate.sh` after every commit (docs are gate-scanned).
