# BVD Extensibility Freeze + Tire-Type Grip + Load Dynamics — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one final generic Java "freeze" so the tire-type grip system, load-sensitive acceleration, load-sensitive fuel, panel rework, and grouped sandbox pages — and all future tuning — are deliverable as Lua-only Workshop updates.

**Architecture:** A versioned `BetterVehicleDynamicsMod` bridge contract: Lua publishes *policy tables* (`tireProfiles`, `loadResponse`), Java applies them at touchpoints it already owns (`updateTireStats` grip, engine-force ramp) and publishes *computed state* back (`computed`, `protocolVersion`). Tire profiles & load→fuel are pure Lua; only the generic hooks are Java (one Necroid ship).

**Tech Stack:** PZ B42.18 Kahlua Lua; Necroid Java class patch (`better-vehicle-dynamics-42`, pinned `488e45e1…`); `tools/grepgate.sh` provenance gate; clean-room (original expression only).

**Domain note on "tests":** there is no Lua/PZ unit harness in this environment. The objective verification gates used throughout are: `./tools/grepgate.sh` PASS (exit 0), `necroid test` = `test build OK: 5 file(s) compiled.` for Java, staged-tree structure assertions, and explicit **USER in-game acceptance** steps. Treat those as the "tests". Every task ends with grep gate + commit; Java tasks also necroid test/capture/install + mirror patch; every staging rsync uses the **mod ROOT** (`workshop/BetterVehicleDynamics/`), never a version subdir.

**Clean-room rule (every task):** original code/strings only; no `RCP_`/bare `VPR`/`Realistic Car Physics`/KI5 identifiers; reading pristine PZ / vanilla for API is allowed, copying non-trivial blocks is not. The Java task is specified as a *contract*, not pre-written code (clean-room: the implementer authors from behaviour; the objective gate is grep + `necroid test` + the user parity gate — a pre-written "answer" would defeat independence).

---

## File Structure

- `mods/better-vehicle-dynamics-42/patches/zombie/core/physics/CarController.java.patch` — **modify** (the one Java freeze; via seeded src + necroid capture).
- `workshop/BetterVehicleDynamics/42.18/media/lua/shared/BVD_Tires.lua` — **create** (tire profile registry + public API + bridge publish).
- `workshop/BetterVehicleDynamics/42.18/media/lua/server/BVD_LoadFuel.lua` — **create** (load→fuel, MP-authoritative; server/SP).
- `workshop/BetterVehicleDynamics/42.18/media/lua/shared/BVD_Config.lua` — **modify** (new KEYS: `TireGripModel`, `LoadAffectsHandling`, `LoadAffectsFuel`; publish `loadResponse` policy; bump nothing else).
- `workshop/BetterVehicleDynamics/42.18/media/lua/client/BVD_HUD.lua` — **modify** (panel reads `computed`: per-surface effective grip + tire family + load penalty).
- `workshop/BetterVehicleDynamics/{42,42.18}/media/sandbox-options.txt` — **modify** (grouped `page=`; 3 new boolean options).
- `workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json` — **modify** (page titles + 3 new option strings).
- `README.md` — **modify** (document `BVD.registerTireProfile` + the bridge protocol version).

---

## Task 1: Java freeze — generic bridge contract in CarController

**Files:**
- Modify (seeded): `/mnt/c/tools/necroid/src-better-vehicle-dynamics-42/zombie/core/physics/CarController.java`
- Mirror: `mods/better-vehicle-dynamics-42/patches/zombie/core/physics/CarController.java.patch`

This is the ONLY Java change in the epic. It is a generic, behaviour-neutral-by-default contract. Implementer authors the code (clean-room); the contract below is exact.

- [ ] **Step 1: Read the target regions**

Read in the seeded src: `updateTireStats()` (~line 920), the throttle/`engineForce` ramp block (~700–775), `bvdBridge()` (~278), and where the bridge is read each tick (`updateModOptions`/per-tick). Confirm `getMass()` and the script base-mass source are reachable from the engine-force block.

- [ ] **Step 2: protocolVersion (Java → Lua), one-shot**

Where BVD first resolves its bridge each world load, set `bridge.rawset("protocolVersion", (double)1)`. Constant `BVD_BRIDGE_PROTOCOL = 1`. Original identifier.

- [ ] **Step 3: tireProfiles fold in `updateTireStats()`**

In the existing per-wheel loop that already does `getPartById("Tire"+wheel.getId())` and `getInventoryItem().getWheelFriction()`: derive `familyKey` = the tire item's type name with a trailing run of digits stripped (e.g. `ModernTire2` → `ModernTire`). Read `KahluaTableImpl tp = bridge.rawget("tireProfiles")`; for the vehicle, average each wheel's `{road,wet,snow,offroad}` from `tp[familyKey]` (missing key/table/field ⇒ 1.0). Apply the averaged per-surface factor to the matching existing branch: multiply the road/base grip by `road`; the `WetGrip` branch result by `wet`; the snow branch by `snow`; the offroad branch by `offroad`. Magnitude still comes from vanilla `wheelFriction` (no double count — profile is a *character* multiplier, neutral=1.0 ⇒ identical to today).

- [ ] **Step 4: loadResponse penalty at the engine-force ramp**

Compute `baseMass` = (BVD reference `mass_kg` for `script.getName()` if present in the data BVD already loads, else `script.getMass()`); `ladenRatio = clamp(getMass()/baseMass, 1.0, 3.0)`. Read `KahluaTableImpl lr = bridge.rawget("loadResponse")`. If `lr` present and `lr.rawgetBool("enabled")` and `ladenRatio > lr.rawgetFloat("threshold")`: `p = lr.rawgetFloat("maxPenalty") * clamp((ladenRatio-threshold)/(fullAt-threshold),0,1)`; fade `p *= clamp(1 - speedKmh/easeBySpeedKmh, 0, 1)`; scale the launch/low-speed engine force by `(1 - p)`. Absent/disabled/`ladenRatio<=threshold` ⇒ **no change** (parity-safe; verify empty vehicle force math is byte-identical when `lr` nil).

- [ ] **Step 5: computed-state-out for the local player's vehicle**

Once per relevant tick, only when this controller's vehicle is the local player's current vehicle, write `bridge.rawset("computed", t)` where `t` has `tireFamily` (string), `gripRoad/gripWet/gripSnow/gripOffroad` (the effective per-surface grip after Step 3), `ladenRatio`, `loadPenalty` (the `p` from Step 4, else 0). Reuse an instance KahluaTableImpl (no per-tick alloc). Never write for non-local vehicles.

- [ ] **Step 6: necroid test (compile gate)**

```
cmd.exe /c "cd /d C:\tools\necroid && necroid.exe test" 2>&1 | grep -viE 'UNC|CMD.EXE|wsl.localhost|Defaulting' | tail -3
```
Expected: `test build OK: 5 file(s) compiled.`

- [ ] **Step 7: capture + install + mirror patch**

```
cmd.exe /c "cd /d C:\tools\necroid && necroid.exe capture better-vehicle-dynamics-42" 2>&1 | grep -viE 'UNC|CMD.EXE|wsl.localhost|Defaulting' | tail -1
cmd.exe /c "cd /d C:\tools\necroid && necroid.exe install  better-vehicle-dynamics-42" 2>&1 | grep -viE 'UNC|CMD.EXE|wsl.localhost|Defaulting' | tail -1
rsync -a --delete /mnt/c/tools/necroid/mods/better-vehicle-dynamics-42/patches/ /home/grphx/zomboid/better-vehicle-dynamics/mods/better-vehicle-dynamics-42/patches/
```
Expected: `install complete. to=client … class files=29`.

- [ ] **Step 8: grep gate + commit**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
./tools/grepgate.sh   # expect: GREP GATE PASS … exit 0
git add -A && git commit -q -m "freeze: generic BVD bridge contract — protocolVersion, tireProfiles fold, loadResponse penalty, computed-state-out (identity when no policy)"
```

---

## Task 2: BVD_Tires.lua — profile registry + public API + bridge publish

**Files:**
- Create: `workshop/BetterVehicleDynamics/42.18/media/lua/shared/BVD_Tires.lua`

- [ ] **Step 1: Create the module (full code)**

```lua
-- BVD_Tires.lua — per-tire-family surface-grip profiles.
--
-- Java reads BetterVehicleDynamicsMod.tireProfiles[familyKey] =
-- {road,wet,snow,offroad} (1.0 = neutral) and folds it into grip per
-- surface. This module owns the DEFAULT vanilla-family profiles and a
-- public registration API so future tire mods / packs add families with
-- ZERO Java change. All numbers are Lua data, tunable via Workshop update.

BVD = BVD or {}
BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}

local SURFACES = { "road", "wet", "snow", "offroad" }

-- Default profiles for the three vanilla tire families. Neutral = 1.0.
-- Modern: road-biased (great tarmac, weaker loose surfaces).
-- Normal: balanced baseline. Old: uniformly poorer.
local DEFAULTS = {
    OldTire    = { road = 0.90, wet = 0.85, snow = 0.85, offroad = 0.85 },
    NormalTire = { road = 1.00, wet = 1.00, snow = 1.00, offroad = 1.00 },
    ModernTire = { road = 1.12, wet = 1.05, snow = 0.92, offroad = 0.90 },
}

local registry = {}   -- familyKey -> sanitized {road,wet,snow,offroad}

local function sanitize(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for i = 1, #SURFACES do
        local k = SURFACES[i]
        local v = t[k]
        if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then
            v = 1.0                          -- neutral on a bad/absent field
        end
        out[k] = v
    end
    return out
end

-- Public API: register/replace a tire family's surface profile.
-- familyKey is the vanilla-style item family (e.g. "ModernTire") with no
-- trailing size digits. First registration wins per key (documented).
function BVD.registerTireProfile(familyKey, profile)
    if type(familyKey) ~= "string" or familyKey == "" then return false end
    local s = sanitize(profile)
    if not s then return false end
    if registry[familyKey] == nil then
        registry[familyKey] = s
        BVD.publishTireProfiles()
        return true
    end
    return false
end

function BVD.getTireProfile(familyKey)
    return registry[familyKey]
end

-- Push the merged table onto the bridge for Java. Defaults first, then
-- any registered families (registry already first-write-wins).
function BVD.publishTireProfiles()
    local merged = {}
    for k, v in pairs(DEFAULTS)  do merged[k] = v end
    for k, v in pairs(registry)  do merged[k] = v end
    BetterVehicleDynamicsMod.tireProfiles = merged
end

-- Seed defaults into the registry-visible API surface and publish once
-- all shared modules are loaded.
local function bootstrap()
    for k, v in pairs(DEFAULTS) do
        if registry[k] == nil then registry[k] = v end
    end
    BVD.publishTireProfiles()
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(bootstrap)
else
    bootstrap()
end

print("[BVD.Tires] tire-profile registry installed (default Old/Normal/Modern)")
```

- [ ] **Step 2: grep gate + stage + commit**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/"
test ! -d "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/media" && echo "layout ok"
./tools/grepgate.sh
git add -A && git commit -q -m "tires: BVD_Tires.lua — default Old/Normal/Modern surface profiles + BVD.registerTireProfile public API + bridge publish"
```
Expected: `layout ok`, `GREP GATE PASS`, exit 0.

---

## Task 3: Load→acceleration policy publish + sandbox toggle

**Files:**
- Modify: `workshop/BetterVehicleDynamics/42.18/media/lua/shared/BVD_Config.lua`

- [ ] **Step 1: Add the new boolean keys**

Read `BVD_Config.lua`; find the `KEYS` list and the `buildCfg()` body. Add to KEYS: `"TireGripModel"`, `"LoadAffectsHandling"`, `"LoadAffectsFuel"`. In `buildCfg()` add (use the file's existing `boolTrue`/`boolFalse` helpers):
```lua
        TireGripModel       = boolTrue("TireGripModel"),       -- default on
        LoadAffectsHandling = boolTrue("LoadAffectsHandling"), -- default on
        LoadAffectsFuel     = boolTrue("LoadAffectsFuel"),     -- default on
```
(Match the existing key→helper formatting exactly so the fingerprint/cfg-cache picks them up.)

- [ ] **Step 2: Publish the `loadResponse` policy onto the bridge**

In the same module's existing bridge-publish path (where it already syncs sandbox-derived values; e.g. the live-tick / OnGameStart publish), add:
```lua
-- loadResponse: Java reads this to make a laden vehicle launch slowly.
-- All numbers Lua-tunable; gated by the LoadAffectsHandling toggle.
local function publishLoadResponse()
    local c = BVD.cfg()
    BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}
    BetterVehicleDynamicsMod.loadResponse = {
        enabled        = (c.LoadAffectsHandling ~= false),
        threshold      = 1.05,
        maxPenalty     = 0.35,
        fullAt         = 1.60,
        easeBySpeedKmh = 25.0,
    }
end
```
Call `publishLoadResponse()` from the same place(s) the module already (re)publishes config (initial + on the existing sandbox-change cadence). If `BVD.publishTireProfiles` exists, also call it there so both policies refresh together.

- [ ] **Step 3: grep gate + stage + commit**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/"
./tools/grepgate.sh
git add -A && git commit -q -m "load: publish loadResponse policy on the bridge + TireGripModel/LoadAffectsHandling/LoadAffectsFuel cfg keys"
```
Expected: `GREP GATE PASS`, exit 0.

---

## Task 4: Load→fuel — pure Lua, MP server-authoritative

**Files:**
- Create: `workshop/BetterVehicleDynamics/42.18/media/lua/server/BVD_LoadFuel.lua`

- [ ] **Step 1: Create the module (full code)**

```lua
-- BVD_LoadFuel.lua — extra fuel burn proportional to how laden a vehicle
-- is. Pure Lua (no Java). Mutates the GasTank container directly, so it
-- is future-tunable via Workshop with zero manual reinstall.
--
-- MP authority: vehicle fuel is shared state. To avoid N-fold draining,
-- the write happens ONLY where it is authoritative: dedicated/host server
-- in MP, the local game in single-player. Clients render the synced tank.

BVD = BVD or {}

local LOAD_FUEL_RATE = 0.0009   -- tank-units/sec of EXTRA drain per unit
                                -- of (ladenRatio-1) at full throttle.
                                -- Subtle but noticeable when heavy.
local lastMs = {}               -- per-vehicle id -> last apply ms

-- Is this game instance the authority for world/vehicle state writes?
local function isAuthority()
    if isClient and isClient() then return false end  -- MP client: no
    return true                                       -- SP or server/host
end

local function cfgOn()
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" then return c.LoadAffectsFuel ~= false end
    end
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    return not (sv and sv.LoadAffectsFuel == false)
end

local function baseMassOf(v)
    local m
    pcall(function()
        local s = v:getScript()
        if s and s.getMass then m = s:getMass() end
    end)
    if BVD and type(BVD.getVehicleData) == "function" then
        pcall(function()
            local s = v:getScript()
            local ft = s and s.getFullType and s:getFullType()
            local d = ft and BVD.getVehicleData(ft)
            if d and type(d.mass_kg) == "number" and d.mass_kg > 0 then
                m = d.mass_kg
            end
        end)
    end
    return m
end

local function tick(v)
    if not v or not v.isEngineRunning then return end
    local okEng, running = pcall(function() return v:isEngineRunning() end)
    if not okEng or not running then return end

    local base = baseMassOf(v)
    if not base or base <= 0 then return end
    local cur = 0
    pcall(function() cur = v:getMass() or 0 end)
    local ratio = cur / base
    if ratio <= 1.0 then return end
    if ratio > 3.0 then ratio = 3.0 end

    local thr = 0
    pcall(function() thr = v:getThrottle() or 0 end)
    if thr <= 0 then return end

    local id  = (v.getId and v:getId()) or tostring(v)
    local now = (getTimestampMs and getTimestampMs()) or 0
    local prev = lastMs[id] or now
    lastMs[id] = now
    local dt = (now - prev) / 1000.0
    if dt <= 0 or dt > 5 then return end          -- skip first/odd frames

    local extra = LOAD_FUEL_RATE * (ratio - 1.0) * thr * dt
    if extra <= 0 then return end

    pcall(function()
        local gt = v:getPartById("GasTank")
        if not gt then return end
        local amt = gt:getContainerContentAmount()
        if type(amt) ~= "number" then return end
        local nv = amt - extra
        if nv < 0 then nv = 0 end
        gt:setContainerContentAmount(nv)
    end)
end

local function onPlayerUpdate(player)
    if not isAuthority() then return end
    if not cfgOn() then return end
    if not player or player:isDead() then return end
    local v = player:getVehicle()
    if v then tick(v) end
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end

print("[BVD.LoadFuel] load-sensitive fuel drain installed (authority-gated)")
```

> Implementer note: confirm `getThrottle()` and `setContainerContentAmount()` exist on this B42.18 build during the user gate; both are pcall-wrapped so a missing method degrades to "no extra drain", never an error. If `setContainerContentAmount` is absent, fall back to the container's set-by-delta API discovered in `ISVehicleRoadtripDebug.lua` and note it in the task report.

- [ ] **Step 2: grep gate + stage + commit**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/"
./tools/grepgate.sh
git add -A && git commit -q -m "load: BVD_LoadFuel.lua — extra fuel drain by laden ratio, pure Lua, MP server-authoritative"
```
Expected: `GREP GATE PASS`, exit 0.

---

## Task 5: Panel rework — per-vehicle effective grip + tire family + load

**Files:**
- Modify: `workshop/BetterVehicleDynamics/42.18/media/lua/client/BVD_HUD.lua`

- [ ] **Step 1: Read the current `buildRows` + cargoLoad region** (lines ~104–160) so the edit matches current structure.

- [ ] **Step 2: Replace the grip rows with computed-state rows**

Read `BetterVehicleDynamicsMod.computed` (pcall-guarded; nil ⇒ all `--`). Replace the four static `cfg.GripLevel/WetGrip/...` rows with, in order:
```lua
    local comp = nil
    pcall(function() comp = BetterVehicleDynamicsMod and BetterVehicleDynamicsMod.computed end)
    local function gv(k)  -- effective grip value -> string + tint
        local x = comp and comp[k]
        if type(x) ~= "number" then return "--", R_DIM end
        return string.format("%.2f", x), R_NORM
    end
    rows[#rows+1] = { "Tire type",   (comp and comp.tireFamily) or "--",
                      (comp and comp.tireFamily) and R_NORM or R_DIM }
    do local s,t = gv("gripRoad")    rows[#rows+1] = { "Road grip",     s, t } end
    do local s,t = gv("gripWet")     rows[#rows+1] = { "Wet grip",      s, t } end
    do local s,t = gv("gripSnow")    rows[#rows+1] = { "Snow grip",     s, t } end
    do local s,t = gv("gripOffroad") rows[#rows+1] = { "Off-road grip", s, t } end
```
Keep "Tuning profile" and "Cargo load". Add after Cargo load:
```lua
    local lp = comp and comp.loadPenalty
    if type(lp) == "number" and lp > 0.001 then
        rows[#rows+1] = { "Load penalty",
            string.format("-%d%% launch", math.floor(lp*100+0.5)),
            (lp > 0.2) and R_OVER or R_WARN }
    end
```
(`R_NORM/R_DIM/R_WARN/R_OVER` already exist in the file.)

- [ ] **Step 3: grep gate + stage + commit**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/"
./tools/grepgate.sh
git add -A && git commit -q -m "panel: show per-vehicle effective per-surface grip + tire family + load penalty (from computed bridge state)"
```
Expected: `GREP GATE PASS`, exit 0.

---

## Task 6: Sandbox reorganisation into grouped pages + new toggles

**Files:**
- Modify: `workshop/BetterVehicleDynamics/42/media/sandbox-options.txt`
- Modify: `workshop/BetterVehicleDynamics/42.18/media/sandbox-options.txt`
- Modify: `workshop/BetterVehicleDynamics/common/media/lua/shared/Translate/EN/Sandbox.json`

- [ ] **Step 1: Read both sandbox-options.txt + Sandbox.json** to see the exact current option blocks and the existing `page = BetterVehicleDynamics` / `translation =` pattern.

- [ ] **Step 2: Define the page groups**

Assign every existing option a `page` from this set (keep IDs/keys unchanged — only `page=` changes), and add the 3 new boolean options:
- `BetterVehicleDynamics_Handling` — grip (GripLevel/WetGrip/SnowGrip/OffroadGrip), drift, drag, steering.
- `BetterVehicleDynamics_TiresLoad` — `TireGripModel`, `LoadAffectsHandling`, `LoadAffectsFuel`.
- `BetterVehicleDynamics_Drivetrain` — HP/Weight realism, trunk scaling, engine/gearbox.
- `BetterVehicleDynamics_Readout` — DriverHUD, skid marks, misc.

New options block (add to **both** `42` and `42.18` sandbox-options.txt, identical), e.g.:
```
    option BetterVehicleDynamics.TireGripModel
    {
        type = boolean, default = true,
        page = BetterVehicleDynamics_TiresLoad, translation = BVD_TireGripModel,
    }
    option BetterVehicleDynamics.LoadAffectsHandling
    {
        type = boolean, default = true,
        page = BetterVehicleDynamics_TiresLoad, translation = BVD_LoadAffectsHandling,
    }
    option BetterVehicleDynamics.LoadAffectsFuel
    {
        type = boolean, default = true,
        page = BetterVehicleDynamics_TiresLoad, translation = BVD_LoadAffectsFuel,
    }
```

- [ ] **Step 3: Sandbox.json — page titles + new option strings (original prose, EN-only)**

Add the four `Sandbox_<page>` page-title keys + the three new option label/tooltip pairs, e.g.:
```
    "Sandbox_BetterVehicleDynamics_Handling": "BVD — Handling",
    "Sandbox_BetterVehicleDynamics_TiresLoad": "BVD — Tires & Load",
    "Sandbox_BetterVehicleDynamics_Drivetrain": "BVD — Drivetrain",
    "Sandbox_BetterVehicleDynamics_Readout": "BVD — Readout & Misc",
    "Sandbox_BVD_TireGripModel": "Tire grip model",
    "Sandbox_BVD_TireGripModel_tooltip": "Different tire types (worn / standard / modern) get distinct grip on road, rain, snow and off-road instead of one flat value.",
    "Sandbox_BVD_LoadAffectsHandling": "Load affects handling",
    "Sandbox_BVD_LoadAffectsHandling_tooltip": "A heavily laden vehicle launches sluggishly from low speed, as if the engine is straining against the weight.",
    "Sandbox_BVD_LoadAffectsFuel": "Load affects fuel use",
    "Sandbox_BVD_LoadAffectsFuel_tooltip": "Carrying a heavy load burns extra fuel while driving.",
```
(Keep existing keys; only add. Update any existing `Sandbox_BetterVehicleDynamics` single-page title if the old flat page key is now unused.)

- [ ] **Step 4: grep gate + stage + commit**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/"
./tools/grepgate.sh
git add -A && git commit -q -m "sandbox: grouped option pages (Handling/Tires&Load/Drivetrain/Readout) + 3 new toggles + EN strings"
```
Expected: `GREP GATE PASS`, exit 0.

---

## Task 7: Docs + integration + final review + user gate

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README — document the public API + protocol**

Add a section: `BVD.registerTireProfile(familyKey, {road=,wet=,snow=,offroad=})` (1.0 = neutral; first-write-wins; example with a FICTIONAL family name, e.g. `"ExampleSportTire"`); and note `BetterVehicleDynamicsMod.protocolVersion` so future Lua updates feature-detect and never force a Java reinstall. Original prose, no banned tokens.

- [ ] **Step 2: Full re-stage + structure assertion**

```
cd /home/grphx/zomboid/better-vehicle-dynamics
rsync -a --delete workshop/BetterVehicleDynamics/ "/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics/"
D="/mnt/c/Users/Grphx/Zomboid/Workshop/BetterVehicleDynamics/Contents/mods/BetterVehicleDynamics"
ls "$D"/mod.info "$D"/42/mod.info "$D"/42.18/mod.info >/dev/null && echo "root+version mod.info OK"
test ! -d "$D/media" && echo "no flat root media OK"
./tools/grepgate.sh
git add -A && git commit -q -m "docs: public tire-profile API + bridge protocol version; final stage"
```
Expected: both `OK` lines, `GREP GATE PASS`, exit 0.

- [ ] **Step 3: Final holistic clean-room review (subagent, read-only)**

Dispatch a review of the whole epic diff: zero banned tokens, Java is generic (no feature names baked in), all new Lua/strings original, identity-when-no-policy parity for the Java freeze, MP authority correct in BVD_LoadFuel, panel display-only. Verbatim grep gate. Fix any CHANGES REQUESTED, re-review.

- [ ] **Step 4: USER in-game acceptance gate**

User cold-restarts PZ (Java freeze needs a fresh JVM) and confirms:
1. Empty/normal vehicle drive + skid feel **unchanged** vs current (parity).
2. Fit Modern vs Old tires → panel shows different per-surface grip; Modern noticeably better on road, Old/Modern tradeoff off-road/snow.
3. Heavily load the trunk → launch is sluggish ("straining"), eases with speed; empties back to normal.
4. Driving heavily-laden burns fuel faster than empty.
5. Panel shows tire type + 4 effective grips + cargo + load penalty, readable, no overlap.
6. Sandbox menu shows the grouped BVD pages with the 3 new toggles; toggling each off disables its feature.
7. Console: no `SEVERE` / `Tried to call nil`. (MP, if tested: fuel drains once, not per-client.)
Regressions loop back to the relevant task. When green, the epic is complete → user does the Workshop upload (out of plan scope).

---

## Self-Review

**Spec coverage:** §3 freeze → Task 1 (protocolVersion/tireProfiles/loadResponse/computed, all 4 sub-points). §4 tire grip → Task 1 Step 3 + Task 2 + Task 5. §5 load→accel → Task 1 Step 4 + Task 3. §6 load→fuel → Task 4 (MP authority covered). §7 panel → Task 5. §8 sandbox pages → Task 6. §9 clean-room/persistence/review → every task's grep gate + Task 7 Step 3; no new persistence by construction. §10 decomposition → Tasks 1–7 map 1:1 to the spec's 7 phases. §11 risks → mitigations embedded (identity fallback Task 1 S3/S4; MP authority Task 4 S1; protocolVersion Task 1 S2; pcall safety Task 4). No gaps.

**Placeholder scan:** new Lua modules given in full; Java task is an explicit contract (intentionally not pre-written — clean-room, gated by grep + `necroid test` + user parity, mirroring the original BVD plan's accepted granularity); edit tasks give exact code blocks + line anchors. No "TBD"/"similar to"/"add error handling".

**Type/name consistency:** bridge keys identical across tasks — `tireProfiles`, `loadResponse`, `computed`, `protocolVersion`; cfg keys `TireGripModel`/`LoadAffectsHandling`/`LoadAffectsFuel` consistent (Config Task 3 ↔ sandbox Task 6 ↔ consumers Task 4/Task 1); `BVD.registerTireProfile`/`publishTireProfiles`/`getTireProfile` consistent (Task 2 ↔ README Task 7); computed field names `tireFamily/gripRoad/gripWet/gripSnow/gripOffroad/ladenRatio/loadPenalty` identical (Task 1 S5 ↔ Task 5 S2). Consistent.
