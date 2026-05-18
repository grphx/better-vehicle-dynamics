# BVD — Java Extensibility Freeze + Tire-Type Grip + Load-Sensitive Dynamics

- Date: 2026-05-18
- Status: APPROVED (design); pending spec review → writing-plans
- Repo: `/home/grphx/zomboid/better-vehicle-dynamics` (deliverable; standalone)
- Supersedes: the "upload-ready" state of the BVD clean-room. BVD now
  publishes to the Workshop **after** this epic, not before.

## 1. Context & Why

BVD is the clean-room replacement for VPR (RCP copyright takedown). Its
Java ships as a manual Necroid bundle — **not** Workshop-auto-updated — so
every Java change forces users to redo a manual install. The user's
priority: ship **one** more Java change that is a *generic, frozen,
versioned extensibility contract*, after which the entire foreseeable
roadmap (new tire types, grip/handling rebalances, per-vehicle data packs,
new readouts, load→handling tuning) is deliverable as **Lua-only Workshop
updates** — no further manual reinstalls.

Two concrete features ride on that contract for v1:

- **Tire-type per-surface grip.** Vanilla B42 has `OldTire`/`NormalTire`/
  `ModernTire` (×3 size classes) with real `wheelFriction` (1.2/1.4/1.6)
  that vanilla already applies as a single flat number. This feature gives
  each family a per-*surface* character (road/wet/snow/off-road tradeoffs).
- **Load-sensitive dynamics.** A laden vehicle should launch sluggishly
  ("engine straining") and burn more fuel.

Behaviour parity with VPR/RCP is allowed; **expression must be 100%
original**; the grep gate (`./tools/grepgate.sh`) stays PASS.

## 2. Goals / Non-Goals

**Goals**
- One final generic Java freeze; all listed roadmap thereafter is Lua-only.
- Tire choice produces a per-surface grip tradeoff, per vehicle.
- Laden mass reduces launch acceleration and increases fuel use.
- Driver-inspection panel shows real *per-vehicle effective* values
  (replacing the opaque global `0.7`).
- Sandbox options reorganised into grouped pages.

**Non-Goals (deferred / YAGNI)**
- Named Sport/All-terrain tire **items** — a future separate mod via the
  public `BVD.registerTireProfile` API. v1 ships only the vanilla families.
- Per-wheel mixed-tire UI (aggregate per vehicle).
- Load effects on braking / top speed.
- A blanket "Lua-ify every Java path" audit beyond the touchpoints this
  roadmap needs.

## 3. Architecture — the frozen Java↔Lua contract (the "freeze")

Generic *by shape, not by feature*. Java knows "apply a per-surface
multiplier table to grip", "scale engine force by a load curve", "publish
computed state" — it does **not** know "Modern tire" or "cargo".

### 3.1 Policy IN (Lua → Java), on the existing `BetterVehicleDynamicsMod` bridge
- `tireProfiles` — map `familyKey → {road, wet, snow, offroad}` (numbers;
  1.0 = neutral). Absent key or absent table ⇒ all 1.0 (identity).
- `loadResponse` — `{ enabled=bool, threshold=float, maxPenalty=float,
  fullAt=float, easeBySpeedKmh=float }`. Absent/disabled ⇒ identity.
- Existing channels (`vehicleData`, `engineData`, `gearboxData`,
  `converterData`, drift/steering/etc.) are unchanged.

### 3.2 Computed state OUT (Java → Lua), `BetterVehicleDynamicsMod.computed`
Updated each relevant tick for the **local player's** current vehicle
only (display use; not authoritative state):
`{ tireFamily=string, gripRoad, gripWet, gripSnow, gripOffroad,
ladenRatio, loadPenalty }`. Missing/again-degrade-safe: panel shows `--`.

### 3.3 Versioning / backward compatibility
Java publishes `BetterVehicleDynamicsMod.protocolVersion` (int, starts at
`1`). Lua feature-detects: if a future Lua update needs a newer contract
than the installed Java exposes, the affected feature **no-ops with a
single info log** — it MUST NOT hard-require a Java reinstall. This is the
mechanism that makes "Lua-only future updates" actually safe.

### 3.4 Java touchpoints changed (the one-time freeze, all in `CarController.java`)
- `updateTireStats()` — derive tire family key from the installed tire
  item; fold its `tireProfiles` per-surface multiplier into the existing
  road/wet/snow/off-road grip branches; aggregate per vehicle.
- engine-force/throttle path (the block BVD already owns) — apply the
  `loadResponse` launch penalty.
- a small computed-state writer — publish §3.2 for the local vehicle.

No other Java class is touched. Load→fuel needs **no Java** (§6).

## 4. Consumer A — Tire-type per-surface grip

**Java:** in `updateTireStats`'s existing per-wheel loop, family key =
installed tire item type with a trailing size digit stripped
(`ModernTire2` → `ModernTire`). Look up `bridge.tireProfiles[key]`. Fold
the surface factor into the matching existing grip branch. Unknown key or
no table ⇒ 1.0 (today's behaviour, exactly). Aggregate **per vehicle**:
average the per-wheel profile factors (consistent with the existing
`wearSum/wheelCount` averaging; mixed tires average). The raw vanilla
`getWheelFriction()` still scales overall magnitude — the profile only
adds *surface character*, so there is no double-count of "more grip".

**Lua:** new shared module `BVD_Tires.lua`:
- Default profiles (Lua-tunable starting points; 1.0 = neutral):
  - `OldTire`    = `{road=0.90, wet=0.85, snow=0.85, offroad=0.85}`
  - `NormalTire` = `{road=1.00, wet=1.00, snow=1.00, offroad=1.00}`
  - `ModernTire` = `{road=1.12, wet=1.05, snow=0.92, offroad=0.90}`
- Public API `BVD.registerTireProfile(familyKey, {road=,wet=,snow=,
  offroad=})` — validated, last-write-wins by key documented, original
  prose; for the future Sport/All-terrain mod & community packs. Mirrors
  the existing `BVD.registerVehicle`/`registerPack` style.
- Publishes the merged table onto the bridge (same pattern as the
  existing `vehicleData` channel; rebuilt on sandbox/registration change).
- Gated by a `TireGripModel` boolean sandbox toggle (default on).

**Panel:** the docked inspection panel replaces the bare global grip rows
with the **effective per-surface grip for this vehicle** read from
`computed` (`gripRoad/Wet/Snow/Offroad`), each shown as a readable value +
qualitative word, plus the installed **tire family** name. Fixes the
original "0.7 is meaningless / it's global" complaint.

## 5. Consumer B — Load-sensitive acceleration

**Definitions:** `baseMass` = BVD reference `mass_kg` for the script if
registered, else `vehicle:getScript():getMass()`. `currentMass` =
`vehicle:getMass()`. `ladenRatio = clamp(currentMass / baseMass, 1.0,
3.0)`.

**Java (freeze):** at the engine-force/throttle ramp BVD already owns,
when `loadResponse.enabled` and `ladenRatio > threshold`, reduce launch /
low-speed engine force by up to `maxPenalty` (fraction), scaling from 0 at
`threshold` to full at `fullAt`, and fading the penalty to ~0 by
`easeBySpeedKmh` so it is a *launch/low-speed* "strain", not a top-speed
nerf. `ladenRatio ≤ threshold` or disabled ⇒ **identical to today**
(parity-safe for empty/normal vehicles).

**Defaults (Lua-tunable):** `threshold=1.05, maxPenalty=0.35, fullAt=1.6,
easeBySpeedKmh=25`. Gated by a `LoadAffectsHandling` sandbox toggle.

## 6. Consumer C — Load-sensitive fuel (pure Lua, no Java)

PZ fuel is the `GasTank` part's container content
(`vehicle:getPartById("GasTank"):getContainerContentAmount()` /
`getContainerCapacity()`), Lua-readable and Lua-mutable. Implemented
entirely in Lua on BVD's **existing per-vehicle tick** (`OnPlayerUpdate`
cadence already used by `BVD_Config`/drift/skid): while the engine is
running, subtract an *extra* drain on top of PZ's own (unknown, native)
consumption: `extra = loadFuelRate × (ladenRatio - 1) × throttle × dt`,
where `loadFuelRate` is an absolute Lua-tunable units/sec constant
(independent of PZ's internal burn rate, which we neither read nor
touch). Clamped so tank ≥ 0, all pcall-safe. Default `loadFuelRate`
tuned in Lua to a subtle but noticeable extra burn at heavy load. Gated by a `LoadAffectsFuel`
sandbox toggle.

**MP authority:** the fuel write must apply exactly once. Single-player:
the local game applies it. Multiplayer: only the **server** applies it
(BVD has a server-side Lua file; guard with `isClient()`/`isServer()`
context checks); clients render the synced result. Read-only grip/accel
are unaffected — they are per-machine physics via the bridge as today;
only this fuel *mutation* needs the authority gate.

No Java touchpoint ⇒ future-proof by construction.

## 7. Panel rework

Reuse the existing docked companion panel (`BVD_HUD.lua`). Rows become,
all from `computed` / Lua state (per *this* vehicle):
tire family · Road/Wet/Snow/Off-road effective grip (value + word) ·
Cargo load (already wired) · Load penalty (when load features on).
No new sandbox key (still gated by the existing `DriverHUD`). American
spelling ("Tire") already standardised.

## 8. Sandbox reorganisation (grouped pages)

PZ supports multiple sandbox **pages** (CommonSense-style) via the
`page =` attribute + page-title translation keys. Split BVD's options
into ~4 original-named pages, e.g.:
- *BVD — Handling* (grip, drift, drag, steering, GripLevel/Wet/Snow/Off)
- *BVD — Tires & Load* (`TireGripModel`, `LoadAffectsHandling`,
  `LoadAffectsFuel`)
- *BVD — Drivetrain* (HP/Weight realism, trunk scaling, etc.)
- *BVD — Readout & Misc* (`DriverHUD`, skid marks, etc.)
Exact option→page assignment finalised during implementation. All page
labels/strings original, EN-only, grep-gate clean. Option **keys** and
`BVD_Config` lists unchanged where possible (only `page=` + new toggles
added) to avoid disturbing existing saves/taxonomy; new toggles added to
`BVD_Config` KEYS + `Sandbox.json`.

## 9. Clean-room · persistence · review

- All new identifiers `BVD_`/`bvd`; original bridge channel names;
  original Lua/strings/prose. Tire family keys are vanilla item names
  (factual interop, like vehicle script ids — not creative expression).
  Grep gate covers all changed files; CREDITS soft-exempt only.
- **Persistence:** nothing new saved. Tire profile + laden ratio derived
  live each tick; fuel mutates the existing GasTank (persists naturally).
  No new ModData (simpler, MP-safe).
- **Review:** every implementation task ends with grep gate + a
  spec-compliance + code-quality/clean-room review (subagent-driven),
  then a final holistic clean-room review before publish, then the user
  does the Workshop upload.

## 10. Decomposition (for the implementation plan)

1. **Java freeze** (CarController only): bridge protocolVersion, read
   `tireProfiles`/`loadResponse`, apply tire per-surface fold + load
   engine-force penalty, write `computed` state out. necroid
   test/capture/install; mirror patch. (One Necroid ship.)
2. **`BVD_Tires.lua`**: default Old/Normal/Modern profiles +
   `BVD.registerTireProfile` public API + bridge publish + sandbox gate.
3. **Load→accel wiring**: Lua publishes `loadResponse`; verify Java
   penalty; tune defaults.
4. **Load→fuel** (Lua-only): per-tick drain on BVD's existing cadence +
   MP authority gate.
5. **Panel rework**: consume `computed`; per-surface effective grip +
   tire family + load penalty.
6. **Sandbox re-paging**: grouped pages + new toggles + translations.
7. **Integration + final holistic clean-room review + user in-game gate**
   (tire tradeoffs feel right, heavy load sluggish + thirstier, panel
   correct, base/empty parity unchanged, console clean, MP-safe), then
   user Workshop upload.

## 11. Risks & mitigations

- *PZ vehicle fuel-burn site is native/unknown* → mitigated: we never
  hook it; we adjust the GasTank container from Lua (vanilla Lua does the
  same read).
- *MP double-apply of fuel* → server-authoritative gate (§6).
- *Double-counting tire grip vs vanilla `wheelFriction`* → profile adds
  surface *character* only; magnitude still from vanilla friction (§4).
- *Old Java vs new Lua mismatch* → `protocolVersion` feature-detect;
  graceful no-op, never a forced reinstall (§3.3).
- *Per-tick cost* → reuse existing loops/cadence; no new per-frame infra.
- *Clean-room* → standard grep gate + per-task + final reviews.
