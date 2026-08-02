-- BVD_Pack_Community.lua
--
-- Optional, self-disabling reference-data pack for a handful of
-- well-known community / utility / military add-on vehicles.
--
-- WHAT THIS IS
--   This file ONLY supplies real-world reference power/weight numbers
--   for third-party vehicles, fed through Better Vehicle Dynamics'
--   public registration API (BVD.registerPack / BVD.registerVehicle).
--   It contains NO code, scripts, models, textures, sounds or any
--   other asset from any third-party vehicle mod, and it does NOT
--   require, depend on, or load any such mod. If the targeted add-on
--   vehicles are not installed, this pack registers NOTHING and is a
--   completely silent no-op (at most one informational log line).
--
-- WHERE THE NUMBERS COME FROM
--   Every figure below is the author's own value, derived from general
--   public real-world knowledge of the actual production vehicle the
--   PZ counterpart is modelled on (manufacturer specs / encyclopaedic
--   curb-mass and engine-output figures). Each entry carries an inline
--   `-- source:` note recording the real vehicle, the published basis,
--   and the assumption made (e.g. gross vs curb mass). No other mod's
--   data table, identifier list, or comments were consulted or copied.
--
-- SCOPE NOTE
--   SoupedUp is a cooking mod and is explicitly NOT in scope here — it
--   has nothing to do with vehicles. This pack only targets actual
--   drivable community vehicles.
--
-- HOW IT IS GATED (true no-op when those mods are absent)
--   The whole pack is registered behind a `check` predicate that asks
--   the script manager whether at least one targeted vehicle script is
--   actually loaded. The predicate is probe-and-cache and Kahlua-safe
--   (every Java call is wrapped in pcall). BVD.Packs.applyAll silently
--   skips a pack whose check returns false, so when none of the target
--   mods are subscribed this pack contributes zero entries, prints no
--   warnings, and cannot affect any vanilla or modded vehicle. A wrong
--   or stale script id is therefore harmless: it simply never matches.
--
-- LOAD-ORDER SAFETY
--   In shared/ alphabetical (ASCII) order this file sorts as
--   BVD_API.lua < BVD_Pack_Community.lua < BVD_Packs.lua, i.e. it
--   loads AFTER the API but BEFORE the pack framework, and BEFORE
--   BVD_VehicleData.lua. So at this file's own load time neither the
--   pack framework nor the built-in vehicle table is guaranteed
--   present. We therefore (a) lazily require the API, and (b) defer
--   the actual registration to OnGameBoot, by which point every
--   shared/ module has loaded. The API's registerPack itself also
--   defensively requires BVD_Packs, so framework availability is
--   double-guarded.
--
-- OVERRIDE / CLOBBER POLICY ("first / more-specific wins")
--   At registration time we drop any entry that BVD already knows
--   about — whether from the built-in BVD_VehicleData table or from
--   an earlier BVD.registerVehicle call — by consulting
--   BVD.getRegisteredVehicles(). The pack is also registered at the
--   default priority (0), so any higher-priority pack still wins on
--   conflict, and BVD.Packs is first-registration-wins by name. This
--   pack is purely additive: it never overrides a more specific or
--   user-supplied value, and it never touches a vanilla vehicle.

BVD = BVD or {}

-- --------------------------------------------------------------------------
-- Reference data.
--
-- Keys are the public PZ vehicle script full types of well-known
-- community add-on vehicles. These ids are factual interop identifiers
-- (not creative expression). Conservative, widely-used canonical forms
-- are used; because the pack is detection-gated, any id that does not
-- resolve on a given install is simply ignored with zero side effects,
-- so the table favours the best-known forms over an exhaustive guess.
--
-- All figures below are the author's OWN reference values, chosen from
-- general public real-world manufacturer/encyclopaedic knowledge of the
-- actual production vehicle (basis noted per entry) -- not taken from
-- any other vehicle mod's data.
--
-- hp      = author-chosen reference horsepower (engine output)
-- mass_kg = author-chosen reference mass (kg)
-- cargo   = author-estimated; forward-compat only. API_VERSION 1
--           validates + stores but does NOT apply cargo (see
--           BVD_API.lua header). Honest forward data; harmless today.
-- --------------------------------------------------------------------------
local DATA = {}

-- HMMWV (High Mobility Multipurpose Wheeled Vehicle), M998-family.
-- source: AM General HMMWV. 6.2L / 6.5L diesel V8, ~150 hp; curb mass
-- roughly 2.3 t, combat-loaded gross up to ~4.5 t. I take the unloaded
-- end (curb ~2400 kg) so the in-game vehicle is heavy but not a brick;
-- 150 hp matches the naturally-aspirated military diesel.
DATA["Base.Humvee"] = { hp = 150, mass_kg = 2400, cargo = 600 }

-- M35-series 2.5-ton 6x6 cargo truck ("deuce and a half").
-- source: Reo/AM General M35. Multifuel inline-6, ~140 hp; empty
-- chassis ~5.9 t, rated 2.5-ton off-road payload (more on-road).
-- Assumption: I use the empty/curb figure (~6000 kg) for the base
-- vehicle mass; payload is left to PZ's own cargo handling.
DATA["Base.M35"] = { hp = 140, mass_kg = 6000, cargo = 1800 }

-- Full-size American school bus (conventional / type C, rear diesel).
-- source: typical 1980s–90s Blue Bird / Thomas type-C body on a
-- medium-duty chassis. ~190 hp diesel; GVWR commonly ~14 t but curb
-- (empty, no passengers) is far lower. Assumption: I model the empty
-- curb mass (~9500 kg) rather than GVWR so handling is plausible.
DATA["Base.SchoolBus"] = { hp = 190, mass_kg = 9500, cargo = 1600 }

-- Type-III box ambulance on a cutaway van chassis.
-- source: generic 1990s E-/G-series cutaway ambulance. ~190 hp V8
-- (gas) or diesel; curb with module fitted ~4.5 t. Assumption:
-- equipped curb mass (~4500 kg) since the box body is always present.
DATA["Base.Ambulance"] = { hp = 190, mass_kg = 4500, cargo = 700 }

-- Medium-duty cube / box delivery truck.
-- source: class-5 cabover or conventional box truck (e.g. medium-duty
-- diesel of the era). ~210 hp; empty curb roughly 5 t depending on
-- body length. Assumption: empty curb (~5000 kg), payload via PZ.
DATA["Base.BoxTruck"] = { hp = 210, mass_kg = 5000, cargo = 2200 }

-- Conventional pumper fire engine.
-- source: typical municipal pumper on a custom fire chassis. Large
-- diesel ~330 hp to move a fully-equipped truck; in-service mass with
-- water tank commonly ~14 t. Assumption: laden in-service mass
-- (~14000 kg) since a fire engine effectively always carries its
-- pump, tank and gear.
DATA["Base.FireTruck"] = { hp = 330, mass_kg = 14000, cargo = 1200 }

-- Armoured police / tactical van (SWAT-style).
-- source: armoured cash-in-transit / tactical van on a heavy van or
-- medium-truck chassis with applied armour. ~250 hp to haul the extra
-- mass; armoured curb roughly 6 t. Assumption: armoured curb mass
-- (~6000 kg) — the armour is structural and always present.
DATA["Base.SWATVan"] = { hp = 250, mass_kg = 6000, cargo = 800 }

-- --------------------------------------------------------------------------
-- Detection: is at least one targeted script actually loaded?
--
-- Probe-and-cache. getScriptManager():getVehicle(fullType) returns a
-- non-nil VehicleScript only for scripts PZ actually parsed (vanilla +
-- subscribed mods). We cache the boolean so the predicate is cheap if
-- BVD.Packs ever re-evaluates it. Every Java touch is pcall-wrapped:
-- Kahlua's pcall still logs caught Java exceptions, so we guard the
-- whole resolve in one pcall rather than calling-and-hoping.
-- --------------------------------------------------------------------------
local _detected -- nil = not yet probed, true/false = cached result

local function anyTargetScriptPresent()
    if _detected ~= nil then return _detected end
    local found = false
    pcall(function()
        local sm = getScriptManager and getScriptManager()
        if not sm then return end
        for fullType in pairs(DATA) do
            if sm:getVehicle(fullType) ~= nil then
                found = true
                break -- one hit is enough; stop probing
            end
        end
    end)
    _detected = found
    return found
end

-- --------------------------------------------------------------------------
-- Registration (deferred to OnGameBoot — see LOAD-ORDER SAFETY header).
--
-- By OnGameBoot every shared/ module has loaded, so the API and the
-- built-in vehicle table are resolvable and we can honestly prune
-- against what BVD already knows. The per-script presence gate is the
-- pack's `check` predicate, evaluated later by BVD.Packs.applyAll at
-- world init.
-- --------------------------------------------------------------------------
local function registerCommunityPack()
    -- Lazily resolve the public API (load order does not guarantee it
    -- here at file scope, but it is certainly present by OnGameBoot).
    if not (BVD and BVD.registerPack) then
        pcall(require, "BVD_API")
    end
    if not (BVD and BVD.registerPack) then
        -- API genuinely unavailable: stay silent except one info line.
        print("[BVD] community pack: BVD API unavailable — pack skipped")
        return
    end

    -- Drop anything BVD already covers so we never clobber the built-in
    -- BVD_VehicleData table or a more specific user/earlier-pack entry.
    -- getRegisteredVehicles() is the live merged table; treat read-only.
    local known = {}
    pcall(function()
        if BVD.getRegisteredVehicles then
            known = BVD.getRegisteredVehicles() or {}
        end
    end)

    local pack, kept, skipped = {}, 0, 0
    for fullType, spec in pairs(DATA) do
        if known[fullType] ~= nil then
            skipped = skipped + 1
        else
            pack[fullType] = { hp = spec.hp, mass_kg = spec.mass_kg, cargo = spec.cargo }
            kept = kept + 1
        end
    end

    if kept == 0 then
        -- Everything is already covered by a more specific source. Do
        -- not register an empty pack; one info line, then silence.
        return
    end

    -- Register through the public API. The `check` predicate makes the
    -- whole pack a silent no-op unless a targeted script is present;
    -- default priority (0) lets any higher-priority pack still win.
    BVD.registerPack("BVD Community Reference", pack, {
        check         = anyTargetScriptPresent,
        priority      = 0,
        source        = "bvd-community-pack",
        -- Community-pack vehicles often ship pre-tuned by their authors;
        -- these curated real-world figures should overwrite, not be
        -- floored by, whatever the script already declares.
        authoritative = true,
    })
end

-- Defer; never register at file scope (load-order + clobber safety).
Events.OnGameBoot.Add(function() pcall(registerCommunityPack) end)

return true
