# Queued fixes — deferred to B42.19 bundle

Changes that are designed and reviewed but intentionally held back so they
land alongside the B42.19 rebase, sparing users a second manual Necroid
re-install.

When we open the 42.19 directory, apply these in the new patches against
the fresh pristine. Each entry has the file path, the original code, and
the replacement so this is a paste-in job, not re-research.

---

## 1. Off-road cars feel quagmire-slow above ~40 km/h

User report (BVD Workshop, 2026-05-29): "trucks and SUVs especially can
barely get past like 40 mphs in second gear, max OffroadGrip and OffroadFloor
do not help; minimum RollResistanceOffroad helps a little."

Root cause: the off-road drag formula in `CarController` has a
speed-dependent term (`0.01F * absSpeed`) that's 10x its on-road
counterpart (`0.001F * absSpeed`). Combined with the `mass * 1/eff`
multiplier for low-`OffroadEfficiency` vehicles (trucks, SUVs), the drag
compounds quadratically with speed and eats most of the engine torque
once the vehicle gets past ~40 km/h on grass.

### Fix A — halve the speed-dependent drag term

**File:** `mods/better-vehicle-dynamics-42/patches/zombie/core/physics/CarController.java.patch`
**Locate:** the `if (this.vehicleObject.isDoingOffroad())` drag block
(roughly the line that reads `+         roll += 0.01F * absSpeed;`).

**Change:**

```diff
-         roll += 0.01F * absSpeed;
+         // v0.1.8 (42.19 bundle): speed-dependent off-road drag halved.
+         // Original 0.01F made cars feel quagmire-slow above ~40 km/h on
+         // grass even with grip floors and OffroadGrip maxed. The base term
+         // + mass + 1/eff multipliers still encode "off-road resists motion";
+         // this just tames the per-km/h compounding so trucks/SUVs can cruise.
+         roll += 0.005F * absSpeed;
```

### Fix B — safety clamp on negative surfaceGrip

**Same file**, in the `if (this.vehicleObject.isDoingOffroad())` block
inside `updateTireStats()` (the `surfaceGrip` computation block). Locate
the lines that read the `OffroadGrip` sandbox and compute `surfaceGrip`.
After the `surfaceGrip *= profOffroad` line (the tireProfiles fold), add:

```diff
          if (tp != null) {
             surfaceGrip *= profOffroad;
          }
+         // v0.1.8 (42.19 bundle): safety floor. The arithmetic above can
+         // produce <= 0 if the sandbox value, the tire-fill multiplier, or
+         // a published tireProfile off-road row pushes the result negative.
+         // A negative surfaceGrip would feed an inverted gripLimit downstream
+         // (engine pulling the car BACKWARDS). Belt-and-braces clamp so no
+         // upstream config drift can knock the math past zero.
+         if (surfaceGrip < 0.05F) {
+            surfaceGrip = 0.05F;
+         }
       }
```

### Fix C — clearer OffroadGrip tooltip (Lua-side)

**File:** `workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json`

The current tooltip — `"Grip factor on dirt, grass and gravel versus
sealed road."` — does not communicate that **higher = more grip**. Users
have been raising it expecting better behavior and not realizing it does
actually help (it does; they were chasing the wrong knob).

Replace the tooltip with:

```
Off-road grip strength. HIGHER = more grip (less tire slip) on dirt,
grass and gravel. Default 0.85 = moderate slip; 1.5 = near-paved feel.
Does not change rolling drag - tune that via Rolling drag off-road.
```

This Lua-side fix can technically ship in B42.18 without a Necroid
re-install since it's just a translation string, but bundling it with
the Java changes keeps the changelog story tidy.

---

## Why this is deferred (2026-05-29)

The Java fixes A and B require a Necroid Java rebuild + the user
re-running their manual installation. PZ B42.19 is expected this week
and will also force a manual re-install (because Necroid's pristine
snapshot rebases against the new vanilla JAR). Bundling the off-road
fixes into the 42.19 patch set means users only do the manual install
dance once, not twice in the same week.

When 42.19 lands:
1. `necroid resync-pristine` against the new PZ JAR
2. Rebase the existing BVD patches onto the new pristine
3. Apply Fix A + Fix B + Fix C as part of the same release
4. Bump `expectedVersion` in `mod.json`
5. Ship as v0.1.8 (Lua) + matching Necroid bump
