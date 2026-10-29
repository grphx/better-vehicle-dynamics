-- BVD_Overhaul: trunk-capacity overhaul + HP/Weight overhaul (Lua-only).
--
-- Trunk: wraps ItemContainer.hasRoomFor + getEffectiveCapacity and
-- multiplies vanilla capacity by a per-class multiplier (Car / Van /
-- Truck / Trailer). Auto-disables when isoContainers is loaded.
--
-- HP/Weight: at world start, walks our independently-authored
-- BVD_VehicleData table (Wikipedia-cited real-world references) and
-- writes the chosen hp/mass values into each matching vehicle script
-- via vehicle:Load. Vehicles not in our table are untouched.
-- Modded vehicles can register via BVD.registerVehicle(name, data).

local vehicleData = require("BVD_VehicleData")

local function isModLoaded(name)
	if not getActivatedMods then return false end
	local mods = getActivatedMods()
	if not mods then return false end
	for i = 0, mods:size() - 1 do
		if mods:get(i) == name then return true end
	end
	return false
end

-- Vehicle classification by script-name pattern. Returns (bucket, mult)
-- where mult comes from the matching sandbox option. Default Car bucket
-- ensures unknown vehicles still get a per-class multiplier rather than
-- silently falling through.
local function vehicleBucket(fullType, sv)
	if not fullType then return nil end
	local name = fullType:match("^[^.]+%.(.+)$") or fullType

	if name:find("^Trailer") then
		return "Trailer", sv.TrunkTrailer or 1.0
	elseif name:find("^PickUpTruck") or name:find("^PickupTruck") then
		return "Truck", sv.TrunkTruck or 1.0
	elseif name:find("^PickUpVan") or name:find("^PickupVan") then
		return "Van", sv.TrunkVan or 1.0
	elseif name:find("^StepVan") then
		return "Truck", sv.TrunkTruck or 1.0
	elseif name:find("^OffRoad") then
		return "Truck", sv.TrunkTruck or 1.0
	elseif name:find("^Van") then
		return "Van", sv.TrunkVan or 1.0
	elseif name:find("^Modern") or name:find("Car") or name:find("^Sports")
		or name:find("^Luxury") or name:find("^Normal") then
		return "Car", sv.TrunkCar or 1.0
	end

	-- Substring fallback for year-prefixed modded vehicles.
	local stem = name:gsub("^[0-9]+", ""):gsub("^fr_[a-z]+_", "")
	local lower = stem:lower()

	if lower:find("semitrailer") or lower:find("trailer") then
		return "Trailer", sv.TrunkTrailer or 1.0
	end
	if lower:find("semitruck") or lower:find("truck")
			or lower:find("powerwagon") or lower:find("stepvan")
			or lower:find("oshkosh") or lower:find("amgeneral")
			or lower:find("bushmaster") or lower:find("humvee")
			or lower:find("m577") or lower:find("m113") then
		return "Truck", sv.TrunkTruck or 1.0
	end
	if lower:find("van") or lower:find("rv") or lower:find("bounder")
			or lower:find("econoline") or lower:find("camper") then
		return "Van", sv.TrunkVan or 1.0
	end
	return "Car", sv.TrunkCar or 1.0
end

local function isCargoContainer(typeStr)
	if not typeStr then return false end
	if typeStr:find("GloveBox") then return false end
	if typeStr == "Seat" or typeStr == "FrontSeat" or typeStr == "BackSeat"
		or typeStr == "TruckBedFrontSeat" then return false end
	if typeStr:find("TruckBed") or typeStr:find("TrailerTrunk")
		or typeStr:find("Trunk") or typeStr:find("Bed")
		or typeStr:find("VanSeat") then
		return true
	end
	return false
end

-- v0.1.9: TrunkScaling fully rewritten.
--
-- The previous metatable-hook approach (ItemContainer.hasRoomFor +
-- getEffectiveCapacity overrides) had two real bugs surfaced by users:
--
--   1. Nested containers (a bag inside the trunk) had self:getParent()
--      equal to the BAG, not the BaseVehicle — so the scaling never
--      applied recursively, and drag/drop into the bag showed a red
--      "won't fit" background even when the trunk was empty.
--   2. PZ B42's inventory transfer system reads the container's actual
--      capacity (setCapacity / getCapacity) at gate time, NOT just
--      getEffectiveCapacity. The hook updated the displayed value but
--      not the enforcement value — so trunks showed 520kg but stopped
--      loading at vanilla 130kg.
--
-- The new approach modifies each spawned vehicle's cargo containers
-- DIRECTLY at vehicle-creation time, calling setCapacity on every
-- TrunkDef/TruckBedDef/VanSeatDef container with the per-class multiplier.
-- A flag in ModData prevents double-scaling on subsequent world loads.
-- isoContainers compatibility: skip entirely if that mod is loaded
-- (parity with the old behaviour).

local SCALED_FLAG = "BVD_TrunkScaled"

local function scaleVehicleCargo(vehicle)
	if not vehicle or not vehicle.getScript then return end

	local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
	if not sv or not sv.TrunkScaling then return end
	if isModLoaded("isoContainers") then return end

	local ok, script = pcall(function() return vehicle:getScript() end)
	if not ok or not script then return end
	local fullType
	pcall(function() fullType = script:getFullType() end)
	if not fullType then return end

	local bucket, mult = vehicleBucket(fullType, sv)
	if not mult or mult == 1.0 then return end

	-- Idempotency: tag this vehicle once scaled so re-applying on world
	-- reload doesn't compound (a 2x bucket would become 4x on second load,
	-- 8x on third, etc).
	local modData = vehicle:getModData()
	if modData[SCALED_FLAG] then return end

	-- Walk every part and look for an attached cargo container. Use
	-- part:setContainerCapacity (not container:setCapacity) — the
	-- container-level setter is silently capped at 100 by PZ B42 (see
	-- "Attempting to set capacity over maximum capacity of 100" warning
	-- in the engine log), while the part-level setter writes the script-
	-- backing field that the transfer gate actually checks.
	local partCount = 0
	pcall(function() partCount = vehicle:getPartCount() or 0 end)
	local scaledAny = false
	for i = 0, partCount - 1 do
		local part
		pcall(function() part = vehicle:getPartByIndex(i) end)
		if part then
			local container
			pcall(function() container = part:getItemContainer() end)
			if container then
				local cType
				pcall(function() cType = container:getType() end)
				if isCargoContainer(cType) then
					local baseCap = 0
					pcall(function()
						baseCap = part.getContainerCapacity
							and part:getContainerCapacity()
							or container:getCapacity()
					end)
					if baseCap and baseCap > 0 then
						local target = baseCap * mult
						if part.setContainerCapacity then
							pcall(function() part:setContainerCapacity(target) end)
						else
							-- Fallback: older B42 patch levels may only expose the
							-- container-level setter (which caps at 100). Better
							-- than nothing.
							pcall(function() container:setCapacity(target) end)
						end
						scaledAny = true
					end
				end
			end
		end
	end

	if scaledAny then
		modData[SCALED_FLAG] = true
	end
end

-- Apply to all existing world vehicles at world load. New vehicles that
-- spawn later catch the OnVehicleCreated hook below.
local function scaleAllWorldVehicles()
	local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
	if not sv or not sv.TrunkScaling then return end
	if isModLoaded("isoContainers") then
		print("[BVD] TrunkScaling: skipped — isoContainers loaded.")
		return
	end

	local cell = getCell and getCell()
	if not cell then return end
	local vehicles
	pcall(function() vehicles = cell:getVehicles() end)
	if not vehicles then return end

	local n = 0
	pcall(function() n = vehicles:size() end)
	for i = 0, n - 1 do
		local v
		pcall(function() v = vehicles:get(i) end)
		if v then pcall(scaleVehicleCargo, v) end
	end
end

Events.OnGameStart.Add(scaleAllWorldVehicles)

-- PZ raises OnVehicleCreated for every fresh spawn (admin spawner,
-- distribution, mod-side spawns, etc.). The hook runs once per vehicle
-- and is scoped to that single instance, so the idempotency flag in
-- ModData (above) catches the case where OnGameStart already scaled it
-- and the engine re-fires the create event during chunk reload.
if Events then
	-- B42 may surface the event under either name depending on patch
	-- level; register both if present and let the ModData flag dedupe.
	if Events.OnVehicleCreated then
		Events.OnVehicleCreated.Add(scaleVehicleCargo)
	end
	if Events.OnNewVehicleCreated then
		Events.OnNewVehicleCreated.Add(scaleVehicleCargo)
	end
end

-- Expose as a global so other modules / the Lua console can call it.
_G.BVD_scaleVehicleCargo = scaleVehicleCargo

-- v0.1.9: throttled scanner. The previous scanner crashed because it
-- used cell:getVehicles():get(i) — that method doesn't exist on PZ's
-- vehicle list (probed via BVD_probeVehicleList; only size, isEmpty,
-- iterator, stream, toArray exist). The correct pattern is the Java
-- iterator: iterator() -> hasNext() / next().
--
-- Walks the cell's vehicle list every ~2 seconds, scales any vehicle
-- whose ModData flag isn't set. The flag dedupes — already-scaled
-- vehicles short-circuit. This catches every spawn path automatically
-- (admin spawner, distribution, horde, mod spawns) without needing
-- the player to enter the vehicle first.
local _lastScanMs = 0
local _SCAN_INTERVAL_MS = 2000

if Events and Events.OnPlayerUpdate then
	Events.OnPlayerUpdate.Add(function()
		local now = getTimestampMs and getTimestampMs() or 0
		if now - _lastScanMs < _SCAN_INTERVAL_MS then return end
		_lastScanMs = now

		local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
		if not sv or not sv.TrunkScaling then return end
		if isModLoaded("isoContainers") then return end

		local cell = getCell and getCell()
		if not cell then return end
		local list = cell:getVehicles()
		if not list then return end

		local iter = list:iterator()
		if not iter then return end

		local fn = _G.BVD_scaleVehicleCargo
		if not fn then return end

		while iter:hasNext() do
			local v = iter:next()
			if v then
				local md = v:getModData()
				if md and not md[SCALED_FLAG] then
					pcall(fn, v)
				end
			end
		end
	end)
end

-- Spec-generation token. PZ recreates the Lua state per world load, so the
-- `or 0` baseline is fresh each session; bumping on every world load yields a
-- value the Java side has not loaded specs for yet, which forces a one-time
-- per-world-load rebuild of the drivetrain reference maps (the Java compares
-- this int against its own last-loaded generation). Tiny, BVD-namespaced.
BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}
Events.OnGameStart.Add(function()
	BetterVehicleDynamicsMod.specGen = (BetterVehicleDynamicsMod.specGen or 0) + 1
end)

-- HP / Weight overhaul: apply our reference values at world start.
-- engineForce in PZ scales roughly 10x horsepower for similar feel to
-- vanilla balance (a heavy box-truck vanilla engineForce ~1070 ≈ 107hp×10).
--
-- CARGO FIELD — accepted, validated, RESERVED (not applied by API v1).
-- ------------------------------------------------------------------
-- hp -> engineForce and mass_kg -> mass are TOP-LEVEL scalar fields of a
-- PZ vehicle script, so vehicle:Load(name, "{ engineForce=.., mass=.. }")
-- overlays them safely. Container capacity is NOT top-level: in B42 it
-- lives doubly nested as `part <TrunkPartName> { container { capacity=N } }`
-- and the trunk part name varies per vehicle (TruckBed / TrunkDoor /
-- trailer trunk / converted van seats — see isCargoContainer above). The
-- registration API only carries {hp,mass_kg,cargo} keyed by vehicle full
-- type; it does NOT know each vehicle's trunk part name, and the deep-merge
-- semantics of a partial nested `part` fragment through vehicle:Load are
-- undocumented and untested here (a partial part block can replace the
-- whole part, destroying install/uninstall/test/model data). Forcing it
-- would risk breaking vehicles. BVD already has a SAFE per-class cargo
-- mechanism — the live TrunkScaling ItemContainer hook above — so cargo
-- via this API stays reserved until a verified per-vehicle mechanism
-- exists. We still accept + validate it (forward-compat) and emit ONE
-- info line the first time any registered entry supplies it.
local _cargoNoticeShown = false
local function noteReservedCargo()
	if _cargoNoticeShown then return end
	_cargoNoticeShown = true
	print("[BVD] cargo: a registered entry supplied a 'cargo' value — " ..
		"accepted and validated but NOT applied by this API version " ..
		"(API_VERSION=" .. tostring(BVD and BVD.API_VERSION or "?") ..
		"). hp/mass_kg apply now; cargo is stored for a future version. " ..
		"For larger trunks today use the TrunkScaling sandbox option.")
end

-- The realism option gives every vehicle the same treatment, registered or not:
--   * power: engineForce is multiplied by REALISM_POWER_GAIN. A registered car first takes the larger of its
--     researched value (hp * 10) and its own script value, so registration can raise a car but never push it
--     below what its author tuned it for. Before v0.1.19 only registered cars got this gain (as a 4x in the
--     Java), which made an unregistered car four times weaker than a registered one of the same power.
--   * mass: a registered car takes its researched mass up to MASS_CAP, but never lighter than its script.
--   * power is capped at REALISM_FORCE_CAP (never below the script's own value).
-- Everything is computed from the scripts' ORIGINAL values, kept here, so running this again (another world
-- in the same session) does not compound, and turning the option off puts the originals back.
local REALISM_POWER_GAIN = 4.0
local MASS_CAP = 1700          -- script mass; parts (~300 kg) and cargo come on top, and a vehicle above about
                               -- 2400 kg all-up sits on its suspension stops (bench measurement)

local REALISM_FORCE_CAP = 28000 -- ceiling on the boosted engineForce (the strongest car seen, a 6150-force
                               -- supercar, comes to 24600); a mod that already ships big engines is not
                               -- quadrupled into absurdity. Never below the car's own script value.

local original = {}            -- fullType -> { force = , mass = } as the scripts first loaded

--- What the realism option turns one script into. Pure: depends only on the arguments, so it holds for any
--- modded car whatever its numbers. `force`/`mass` are the script's ORIGINAL values; `spec` is the registered
--- entry or nil. Returns the engineForce and the mass (nil = leave the mass alone). Guarantees, for any
--- positive input: the result is never weaker or lighter than the script itself, power never exceeds
--- max(REALISM_FORCE_CAP, the script's own), and a registered mass never exceeds max(MASS_CAP, the script's own).
function BVD.realismTarget(force, mass, spec)
	local base, newMass = force, nil
	if spec then
		if spec.hp then base = math.max(spec.hp * 10, force) end
		if spec.mass_kg and mass then newMass = math.max(mass, math.min(spec.mass_kg, MASS_CAP)) end
	end
	local boosted = math.max(force, math.min(base * REALISM_POWER_GAIN, REALISM_FORCE_CAP))
	return boosted, newMass
end

local function remember(v, fullType)
	local o = original[fullType]
	if not o then
		local force, mass
		pcall(function() force = v:getEngineForce() end)
		pcall(function() mass = v:getMass() end)
		o = { force = force, mass = mass }
		original[fullType] = o
	end
	return o
end

-- NOTE the trailing comma. The script parser silently drops the LAST value of the body when it has no
-- comma after it, so "{ engineForce = 7000 }" changes nothing and "{ engineForce = 1, mass = 2 }" loses the
-- mass. Before v0.1.19 these were written without it: power was applied only when a mass came after it,
-- and masses were never applied at all.
local function loadValues(v, force, mass)
	if force and mass then
		v:Load(v:getName(), string.format("{ engineForce = %d, mass = %d, }", math.floor(force + 0.5), math.floor(mass + 0.5)))
	elseif force then
		v:Load(v:getName(), string.format("{ engineForce = %d, }", math.floor(force + 0.5)))
	end
end

local function applyHPWeight()
	local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
	local sm = getScriptManager and getScriptManager()
	if not sm then return end

	if not sv or sv.RealismHPWeight ~= true then
		-- option off: hand back anything an earlier world in this session changed
		for fullType, o in pairs(original) do
			local v = sm:getVehicle(fullType)
			if v and o.force then pcall(loadValues, v, o.force, o.mass) end
		end
		return
	end

	-- Merge every registered data pack into our vehicle table just before
	-- we apply. OnInitGlobalModData is late enough that all shared/ files
	-- have loaded and any BVD.registerPack / BVD.Packs.register calls have
	-- run. registerVehicle writes straight into vehicleData already; this
	-- folds in the pack path too. Guarded - a broken pack must not abort
	-- the apply below.
	if BVD and BVD.Packs and BVD.Packs.applyAll then
		pcall(function() BVD.Packs.applyAll(vehicleData) end)
	end

	local scripts = sm:getAllVehicleScripts()
	local touched = 0
	for i = 0, scripts:size() - 1 do
		local v = scripts:get(i)
		local fullType = v:getFullName()
		local o = remember(v, fullType)
		-- no engine to power (trailers, burnt wrecks): leave alone
		if o.force and o.force > 0 and not fullType:find("Burnt", 1, true) then
			local spec = vehicleData[fullType] or vehicleData[v:getName()]
			-- 'cargo' is validated + stored but reserved (see the note above). If any
			-- registered entry carries it, surface ONE info line.
			if spec and spec.cargo ~= nil then noteReservedCargo() end
			local force, mass = BVD.realismTarget(o.force, o.mass, spec)
			-- the EnginePower sandbox option is applied once, in the Java, to every vehicle
			pcall(loadValues, v, force, mass)
			touched = touched + 1
		end
	end
end

Events.OnInitGlobalModData.Add(applyHPWeight)
