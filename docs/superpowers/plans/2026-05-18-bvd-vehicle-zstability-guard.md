# BVD Vehicle Z-Stability Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A server/host-authoritative safety net that snaps a vehicle back onto its own level's floor when its physics height has sunk implausibly far below it, mitigating the "cars sucked into the ground" MP desync class.

**Architecture:** One new generic touchpoint in the already-frozen `CarController` per-tick path, gated on a Lua-published `BetterVehicleDynamicsMod.stabilityGuard` policy (same `bvdBridge()`/`bridgeFieldOr` mechanism as `loadResponse`). The floor reference is recomputed every check from the vehicle's *current* level (`PZMath.fastfloor(getZ())`) using PZ's own level→Y constant `2.44949F`; correction re-seats via vanilla `BaseVehicle.setWorldTransform()`. `BVD_Config` publishes the policy from sandbox; two new Handling-page sandbox options. Bundled into the current Necroid Java freeze so all later tuning is Lua/sandbox-only.

**Tech Stack:** Necroid Java class-patch toolchain (seeded src → `necroid test/capture/install`), PZ B42.18 Kahlua Lua, `tools/grepgate.sh` provenance gate, clean-room (original expression only).

**Domain note on "tests":** there is no Lua/PZ unit harness in this environment. The objective gates per task are: `necroid test` = `test build OK`, `./tools/grepgate.sh` PASS (exit 0), staged-tree structure assertions (`42`==`42.18`, mod ROOT rsync), and an explicit final **USER in-game acceptance** step. Treat those as the tests. Every Java task ends with `necroid test` + `capture` + `install` + mirror patch into the repo + grep gate + commit.

**Clean-room rule (every task):** original code/strings only; no banned provenance tokens — the gate (`tools/grepgate.sh`) is authoritative; docs are gate-scanned too. Reading pristine PZ for API is allowed; copying non-trivial vanilla blocks is not (the guard logic here is original; it only *calls* vanilla APIs).

**Authority model (applies to Task 1):** PZ runs Bullet vehicle physics on clients and the listen host, never on a dedicated server (every existing `Bullet.*` call in `CarController`/`BaseVehicle` is guarded `if (!GameServer.server)`), and a remotely-driven vehicle carries `Authorization.Remote`. The guard therefore acts only when `!GameServer.server` **and** the vehicle is **not** `Authorization.Remote` — i.e., the side that actually owns this vehicle's physics. This is the precise, vanilla-aligned realization of the spec's "authority only / no client-server fight".

---

### Task 1: CarController Z-stability guard touchpoint (the Java freeze)

**Files:**
- Modify (seeded src, then `necroid capture`): `/mnt/c/tools/necroid/src-better-vehicle-dynamics-42/zombie/core/physics/CarController.java`
- Mirror (generated): `mods/better-vehicle-dynamics-42/patches/zombie/core/physics/CarController.java.patch`

**Context the implementer needs:**
- `bvdBridge()` (CarController:306) returns `(KahluaTableImpl)LuaManager.env.rawget("BetterVehicleDynamicsMod")` or null.
- `bridgeFieldOr(KahluaTableImpl row, String field, float fallback)` (CarController:314) returns the float field or `fallback` when row is null / field absent / non-numeric. Use it for every numeric read so a missing policy is NO-OP.
- The loadResponse read idiom already in this file (CarController:1674): `Object raw = (bridge == null) ? null : bridge.rawget("loadResponse"); KahluaTableImpl t = (raw instanceof KahluaTableImpl) ? (KahluaTableImpl)raw : null;`. Mirror it for `"stabilityGuard"`.
- Per-tick path: lines 1735-1737 are `this.updateTireStats(); this.publishComputedState(); this.bvdPruneSkidMarks();`. The guard call goes immediately after `this.bvdPruneSkidMarks();`.
- Physics height of the vehicle is `this.vehicleObject.jniTransform.origin.y` (Bullet Y-up). PZ's level→Y constant is `2.44949F` (one floor level); vanilla clamps a legit physics Z into `[level*2.44949F, (level+0.995F)*2.44949F]` (BaseVehicle.load:2762).
- Level reference MUST be the vehicle's current logical level: `int level = PZMath.fastfloor(this.vehicleObject.getZ());` (negative for basements — correct for underground; this is the same `fastfloor(getZ())` the restingZ init uses at CarController:475).
- Re-seat is done by vanilla `this.vehicleObject.setWorldTransform(this.vehicleObject.jniTransform)` (BaseVehicle:4180) — it re-applies the transform through `Bullet.teleportVehicle` with the world offsets and current rotation, and a Bullet teleport resets the body's velocity (so it will not immediately re-sink). Do **not** hand-roll a Bullet call.
- `PZMath`, `GameServer`, `LuaManager`, `KahluaTableImpl`, and `BaseVehicle.Authorization` are already imported/used in this file (`Authorization.Remote` is used at CarController:495). No new imports.
- `this.vehicleObject` is the `BaseVehicle`. Counters are plain instance fields (one CarController per vehicle).

- [ ] **Step 1: Add the two per-vehicle counter fields**

In `CarController.java`, find the existing line (CarController:~245):

```java
   private long bvdSkidPruneMs = 0L;
```

Add immediately below it:

```java
   private int bvdSinkTicks = 0;
   private int bvdGuardCooldown = 0;
```

- [ ] **Step 2: Add the guard method**

Immediately *before* the existing method declaration `private void publishComputedState() {` (CarController:~364), insert this complete method:

```java
   // Server/host-authoritative safety net: if this vehicle's physics height
   // has sunk implausibly far below its OWN current level's floor, snap it
   // back onto that floor. Mitigates the "vehicle sucked into the ground"
   // MP desync class. Generic + frozen: all numbers come from the Lua
   // BetterVehicleDynamicsMod.stabilityGuard policy (sandbox-driven); when
   // that policy is absent or disabled this is an immediate NO-OP and the
   // build is byte-identical to before. The floor is recomputed every call
   // from the vehicle's CURRENT level, never a stale saved Z.
   private void bvdStabilityGuard() {
      // Only the side that owns this vehicle's Bullet physics may correct
      // it: never a dedicated server (Bullet is not local there), never a
      // remotely-driven vehicle (slaved to the network).
      if (GameServer.server) {
         return;
      }
      if (this.vehicleObject == null
         || this.vehicleObject.isNetPlayerAuthorization(BaseVehicle.Authorization.Remote)) {
         return;
      }

      KahluaTableImpl bridge = this.bvdBridge();
      Object rawGuard = (bridge == null) ? null : bridge.rawget("stabilityGuard");
      KahluaTableImpl sg = (rawGuard instanceof KahluaTableImpl) ? (KahluaTableImpl)rawGuard : null;
      if (sg == null || bridgeFieldOr(sg, "enabled", 0.0F) < 0.5F) {
         this.bvdSinkTicks = 0;
         if (this.bvdGuardCooldown > 0) {
            this.bvdGuardCooldown--;
         }
         return;
      }

      float sinkDepth = bridgeFieldOr(sg, "sinkDepth", 1.0F);
      int dwellTicks = (int)bridgeFieldOr(sg, "dwellTicks", 5.0F);
      int cooldownTicks = (int)bridgeFieldOr(sg, "cooldownTicks", 60.0F);

      if (this.bvdGuardCooldown > 0) {
         this.bvdGuardCooldown--;
      }

      // Floor of the vehicle's CURRENT level (negative => basement; correct
      // for underground). 2.44949 is PZ's own level->physics-Y height.
      int level = PZMath.fastfloor(this.vehicleObject.getZ());
      float floorY = level * 2.44949F;
      float physicsY = this.vehicleObject.jniTransform.origin.y;

      boolean sunk = physicsY < floorY - sinkDepth;
      if (!sunk) {
         this.bvdSinkTicks = 0;
         return;
      }

      this.bvdSinkTicks++;
      if (this.bvdSinkTicks < dwellTicks || this.bvdGuardCooldown > 0) {
         return;
      }

      // Re-seat just above this level's floor (inside vanilla's legitimate
      // [level*2.44949, (level+0.995)*2.44949] band), then let vanilla's
      // own teleport push it to Bullet (which resets velocity).
      this.vehicleObject.jniTransform.origin.y = floorY + 0.10F;
      this.vehicleObject.setWorldTransform(this.vehicleObject.jniTransform);
      this.bvdSinkTicks = 0;
      this.bvdGuardCooldown = cooldownTicks;
   }
```

- [ ] **Step 3: Call the guard from the per-tick path**

In `CarController.java` find (CarController:~1737):

```java
      this.publishComputedState();
      this.bvdPruneSkidMarks();
```

Replace with:

```java
      this.publishComputedState();
      this.bvdPruneSkidMarks();
      this.bvdStabilityGuard();
```

- [ ] **Step 4: Compile gate**

Run:

```bash
cmd.exe /c "cd /d C:\tools\necroid && necroid.exe test" 2>&1 | grep -aiE 'test build OK|error:|javac failed' | tail -2
```

Expected: `test build OK: 5 file(s) compiled.` (5, not 6 — FBORenderCell is NOT touched). If `error:` appears, fix the reported line and re-run; do not proceed until `test build OK`.

- [ ] **Step 5: Capture + install + mirror the patch**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics
cmd.exe /c "cd /d C:\tools\necroid && necroid.exe capture better-vehicle-dynamics-42" 2>&1 | grep -aiE 'captured|error' | tail -1
cmd.exe /c "cd /d C:\tools\necroid && necroid.exe install better-vehicle-dynamics-42" 2>&1 | grep -aiE 'install complete|error' | tail -1
rsync -a --delete /mnt/c/tools/necroid/mods/better-vehicle-dynamics-42/patches/ mods/better-vehicle-dynamics-42/patches/ 2>&1 | tail -1
grep -nE 'bvdStabilityGuard|stabilityGuard' mods/better-vehicle-dynamics-42/patches/zombie/core/physics/CarController.java.patch | head -3
```

Expected: `captured 5 file(s) …`, `install complete …`, and the grep shows the new method + `rawget("stabilityGuard")` present in the mirrored patch.

- [ ] **Step 6: Grep gate**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics && ./tools/grepgate.sh; echo "exit=$?"
```

Expected: `GREP GATE PASS …` and `exit=0`.

- [ ] **Step 7: Commit**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics
git add -A && git commit -m "feat(stability): server/host-authoritative vehicle Z-sink guard (Java freeze)

CarController per-tick touchpoint reads BetterVehicleDynamicsMod.
stabilityGuard via bvdBridge/bridgeFieldOr; recomputes the current
level's floor (PZ's 2.44949 level->Y) every check; on a sustained
sink below floor-sinkDepth (dwell + per-vehicle cooldown) re-seats via
vanilla setWorldTransform. NO-OP when policy absent/disabled; gated to
!GameServer.server and non-Remote authority. Bundled into the freeze.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 2: Lua publish + sandbox options + EN strings

**Files:**
- Modify: `workshop/BetterVehicleDynamics/42.18/media/lua/shared/BVD_Config.lua`
- Modify: `workshop/BetterVehicleDynamics/42.18/media/sandbox-options.txt`
- Modify: `workshop/BetterVehicleDynamics/42/media/sandbox-options.txt` (kept byte-identical to 42.18)
- Modify: `workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json`

**Context:** `BVD_Config.lua` already has: a `KEYS` list (line ~81) ending `… "LoadAffectsFuel", "LoadMaxPenalty",`; a `buildCfg()` "Load dynamics" block ending `LoadMaxPenalty = num("LoadMaxPenalty", 0.5),`; `publishLoadResponse()` (def line 216); `onLiveTick()` which calls `publishLoadResponse()` at line 265; and a module-load initial `publishLoadResponse()` at line 284. `num(key, default)` and `boolTrue(key)` helpers exist in `buildCfg`. Sandbox option `2.44949` is PZ's level→Y; Lua converts the human "tiles" number to physics-Y `sinkDepth` so Java stays trivial.

- [ ] **Step 1: Add the two keys to `KEYS`**

In `BVD_Config.lua` find:

```lua
    "TireGripModel", "LoadAffectsHandling", "LoadAffectsFuel", "LoadMaxPenalty",
```

Replace with:

```lua
    "TireGripModel", "LoadAffectsHandling", "LoadAffectsFuel", "LoadMaxPenalty",
    "StabilityGuard", "StabilityGuardSinkTiles",
```

- [ ] **Step 2: Add the two keys to `buildCfg()`**

In `BVD_Config.lua` find:

```lua
        LoadMaxPenalty      = num("LoadMaxPenalty", 0.5),      -- 0..0.9 frac
    }
```

Replace with:

```lua
        LoadMaxPenalty      = num("LoadMaxPenalty", 0.5),      -- 0..0.9 frac
        StabilityGuard         = boolTrue("StabilityGuard"),          -- default true
        StabilityGuardSinkTiles = num("StabilityGuardSinkTiles", 0.75),
    }
```

- [ ] **Step 3: Add `publishStabilityGuard()`**

In `BVD_Config.lua`, find the end of `publishLoadResponse` (line ~231):

```lua
        easeBySpeedKmh = 35.0,   -- fully gone by 35 km/h
    }
end
```

Insert immediately after that `end` (before the `-- ---` "Live re-read" comment block):

```lua

-- ---------------------------------------------------------------------------
-- Stability-guard bridge publish
-- ---------------------------------------------------------------------------
-- Writes BetterVehicleDynamicsMod.stabilityGuard so the frozen Java guard
-- can re-seat a vehicle that has sunk implausibly below its own level's
-- floor (MP "sucked into the ground" mitigation). The sandbox exposes a
-- human "tiles" number; we convert it to physics-Y units here (PZ's level
-- height is 2.44949) so the Java side stays a trivial comparison. dwell and
-- cooldown are authoring constants (Lua-tunable later, no reinstall); only
-- `enabled` and `sinkDepth` track sandbox at runtime.
local function publishStabilityGuard()
    BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}
    local c = BVD.cfg()
    local tiles = tonumber(c and c.StabilityGuardSinkTiles) or 0.75
    if tiles < 0.25 then tiles = 0.25 elseif tiles > 3.0 then tiles = 3.0 end
    BetterVehicleDynamicsMod.stabilityGuard = {
        enabled       = ((c and c.StabilityGuard ~= false) and 1.0) or 0.0,
        sinkDepth     = tiles * 2.44949,   -- "tiles" -> physics-Y units
        dwellTicks    = 5.0,               -- consecutive offending ticks
        cooldownTicks = 60.0,              -- min ticks between corrections
    }
end
```

- [ ] **Step 4: Call it at the two existing publish sites**

In `BVD_Config.lua` find (inside `onLiveTick`, line ~265):

```lua
    publishLoadResponse()
    if BVD and BVD.publishTireProfiles then pcall(BVD.publishTireProfiles) end
```

Replace with:

```lua
    publishLoadResponse()
    publishStabilityGuard()
    if BVD and BVD.publishTireProfiles then pcall(BVD.publishTireProfiles) end
```

Then find the module-load initial publish (line ~284):

```lua
publishLoadResponse()
```

(the final standalone call near end of file). Replace that single line with:

```lua
publishLoadResponse()
publishStabilityGuard()
```

- [ ] **Step 5: Add the two sandbox options (42.18) on the Handling page**

In `workshop/BetterVehicleDynamics/42.18/media/sandbox-options.txt` find the `OffroadGrip` option followed by the `Drag` option:

```
option BetterVehicleDynamics.OffroadGrip
{
    type = double, min = 0.25, max = 1.5, default = 0.85,
    page = BetterVehicleDynamics_Handling, translation = BVD_OffroadGrip,
}

option BetterVehicleDynamics.Drag
```

Replace with (insert the two new options between them):

```
option BetterVehicleDynamics.OffroadGrip
{
    type = double, min = 0.25, max = 1.5, default = 0.85,
    page = BetterVehicleDynamics_Handling, translation = BVD_OffroadGrip,
}

option BetterVehicleDynamics.StabilityGuard
{
    type = boolean, default = true,
    page = BetterVehicleDynamics_Handling, translation = BVD_StabilityGuard,
}

option BetterVehicleDynamics.StabilityGuardSinkTiles
{
    type = double, min = 0.25, max = 3.0, default = 0.75,
    page = BetterVehicleDynamics_Handling, translation = BVD_StabilityGuardSinkTiles,
}

option BetterVehicleDynamics.Drag
```

- [ ] **Step 6: Mirror sandbox-options to the 42 tree (must stay identical)**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics
cp workshop/BetterVehicleDynamics/42.18/media/sandbox-options.txt workshop/BetterVehicleDynamics/42/media/sandbox-options.txt
diff -q workshop/BetterVehicleDynamics/42/media/sandbox-options.txt workshop/BetterVehicleDynamics/42.18/media/sandbox-options.txt && echo "42 == 42.18 OK"
```

Expected: `42 == 42.18 OK`.

- [ ] **Step 7: Add the EN strings**

In `workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json` find the file's final two entries + closing brace:

```json
    "Sandbox_BVD_LoadMaxPenalty": "Max launch penalty when fully loaded",
    "Sandbox_BVD_LoadMaxPenalty_tooltip": "Biggest drop in launch force for a fully loaded vehicle (0.50 = up to 50% less force from a stop). Fades out as the vehicle speeds up. Requires 'Load affects handling'."
}
```

Replace with:

```json
    "Sandbox_BVD_LoadMaxPenalty": "Max launch penalty when fully loaded",
    "Sandbox_BVD_LoadMaxPenalty_tooltip": "Biggest drop in launch force for a fully loaded vehicle (0.50 = up to 50% less force from a stop). Fades out as the vehicle speeds up. Requires 'Load affects handling'.",

    "Sandbox_BVD_StabilityGuard": "Vehicle ground-clip guard",
    "Sandbox_BVD_StabilityGuard_tooltip": "Safety net for multiplayer: if a vehicle sinks far below the floor of the level it is on (the 'sucked into the ground' desync), it is snapped back onto that floor. Only acts on a state that is never reached by normal driving, so ramps, basements and multi-level parking are unaffected.",

    "Sandbox_BVD_StabilityGuardSinkTiles": "Ground-clip trigger depth (levels)",
    "Sandbox_BVD_StabilityGuardSinkTiles_tooltip": "How far below its own level's floor a vehicle must sink before the guard re-seats it, measured in floor levels (0.75 = three-quarters of one level). Lower reacts sooner; raise it if a custom map ever triggers it wrongly. Requires 'Vehicle ground-clip guard'."
}
```

- [ ] **Step 8: Validate JSON, stage, assert layout, grep gate**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics
python3 -c "import json;json.load(open('workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json'))" && echo "JSON OK"
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/" 2>&1 | tail -1
test ! -d "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/media" && echo "layout ok (no flat root media/)"
./tools/grepgate.sh; echo "exit=$?"
```

Expected: `JSON OK`, `layout ok (no flat root media/)`, `GREP GATE PASS …`, `exit=0`.

- [ ] **Step 9: Commit**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics
git add -A && git commit -m "feat(stability): publish stabilityGuard policy + Handling sandbox options

BVD_Config: KEYS + buildCfg + publishStabilityGuard() (tiles->physics-Y
via PZ's 2.44949; dwell/cooldown authoring constants) called at the two
existing publish sites. Two Handling-page options (StabilityGuard
default true, StabilityGuardSinkTiles double 0.25-3.0 default 0.75),
42==42.18, EN strings.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 3: README note

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the guard**

In `README.md`, find the section that documents sandbox options / features (search for `LoadMaxPenalty` or the Tires/Load feature paragraph). Immediately after that paragraph add:

```markdown
### Vehicle ground-clip guard (multiplayer safety net)

On a server or host, if a vehicle sinks implausibly far below the floor
of the level it is on — the "sucked into the ground" multiplayer desync
— Better Vehicle Dynamics snaps it back onto that floor. It only ever
acts on a state that normal driving cannot produce (a vehicle below its
*own* level's floor), so ramps, basements and multi-level parking are
unaffected. Controlled by the **Vehicle ground-clip guard** toggle
(default on) and **Ground-clip trigger depth (levels)** on the
Handling sandbox page; both are tunable live with no manual Java
reinstall.
```

- [ ] **Step 2: Grep gate + commit**

```bash
cd /home/grphx/zomboid/better-vehicle-dynamics
./tools/grepgate.sh; echo "exit=$?"
git add -A && git commit -m "docs(stability): README note for the vehicle ground-clip guard

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

Expected: `GREP GATE PASS …`, `exit=0`.

---

### Task 4: USER in-game acceptance gate (terminal hand-off)

This task is **not** executed by an agent. After Tasks 1-3 are committed and the final code review is clean, present the following to the user and stop. The Java changed, so it requires one full cold restart.

- [ ] **Step 1: Present the acceptance checklist to the user**

> The Z-stability guard is built and installed. Do one **full cold restart** (quit PZ to desktop, confirm `javaw.exe`/`ProjectZomboid*` gone in Task Manager, relaunch — its install is in the Necroid Java freeze). Then in single-player:
>
> 1. **Parity / no false positives:** drive normally for a session across slopes, ramps, multi-level parking, towing, jumps, **and into/out of an underground or basement level and across Z-level boundaries**. Expect the car to behave exactly as before and **never** get snapped/teleported. Any spurious re-seat — especially at a level transition or in a basement — is a failure; report it.
> 2. **Toggle:** confirm **Handling → Vehicle ground-clip guard** and **Ground-clip trigger depth (levels)** appear in Sandbox options and that turning the guard off is honoured (no corrections at all).
> 3. **Console:** no `SEVERE` / `Tried to call nil` / exception from `CarController` or stability.
>
> (True MP efficacy against the predecessor desync is field-validated by server admins per the spec; SP acceptance here proves parity-safety and that the option wiring works.)

- [ ] **Step 2: On user confirmation, mark the epic complete**

When the user confirms parity holds and the options work, the feature is done — it is bundled in the current Java freeze and all future tuning is Lua/sandbox-only.

---

## Self-Review

**1. Spec coverage:**
- Spec §1 decisions (snap-back / sunk-below-floor-only / CarController approach / default ON) → Task 1 method + Task 2 `StabilityGuard` default true. ✔
- Spec §2 false-positive-proof + underground + **current-level recompute hard rule** → Task 1 Step 2 recomputes `level = fastfloor(getZ())` and `floorY = level*2.44949` every call, never a saved Z; negative levels handled. ✔
- Spec §3 bridge contract (`enabled`/`sinkDepth`/`dwellTicks`/`cooldownTicks`, all `bridgeFieldOr` NO-OP-safe, protocolVersion unchanged) → Task 1 Step 2 reads exactly those via `bridgeFieldOr`; no protocolVersion change. ✔
- Spec §4 detection/correction order (authority gate → policy gate → current-level floor → sink test → dwell → cooldown → re-seat + reset) → implemented in that exact order. ✔ (Velocity reset is delegated to vanilla `setWorldTransform`→`Bullet.teleportVehicle`, which the spec explicitly allows as "the same operation BVD already does at init"; documented in Context.)
- Spec §5 sandbox/Lua (Handling page, `StabilityGuard`+`StabilityGuardSinkTiles`, EN strings, `publishStabilityGuard` mirroring `publishLoadResponse`, dwell/cooldown Lua constants) → Task 2. ✔
- Spec §6 parity/safety/one-freeze + exotic-map escape hatch (toggle/threshold) → NO-OP guard + sandbox toggle/number; README + tooltip state the escape hatch. ✔
- Spec §7 gates + honest MP caveat → per-task gates; Task 4 Step 1 restates the field-validation caveat. ✔
- Spec §8 out-of-scope → nothing in the plan adds flung/airborne, eased/clamp, per-type, client correction. ✔
- Spec §9 file touch list → Tasks 1-3 cover CarController, BVD_Config, both sandbox-options, Sandbox.json, README. ✔

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to"/bare prose steps — every code step has the full literal code and every command has expected output. ✔

**3. Type consistency:** `bvdStabilityGuard()` (defined Task 1 Step 2, called Task 1 Step 3) — names match. Bridge key `"stabilityGuard"` and fields `enabled`/`sinkDepth`/`dwellTicks`/`cooldownTicks` are identical between the Java reader (Task 1) and the Lua publisher (Task 2). Sandbox keys `StabilityGuard`/`StabilityGuardSinkTiles` identical across `KEYS`, `buildCfg`, `sandbox-options.txt`, and the `BVD_*` translation ids in `Sandbox.json`. Counter fields `bvdSinkTicks`/`bvdGuardCooldown` declared once (Step 1) and only used in the method (Step 2). ✔
