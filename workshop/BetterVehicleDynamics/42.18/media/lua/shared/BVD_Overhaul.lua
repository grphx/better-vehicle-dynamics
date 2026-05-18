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

local trunkPatched = false
local trunkHookHitOnce = false

local function patchTrunkContainers()
	if trunkPatched then return end
	if isModLoaded("isoContainers") then
		print("[BVD] TrunkScaling: skipped install — isoContainers loaded.")
		return
	end
	if not ItemContainer then return end
	local mt = __classmetatables and __classmetatables[ItemContainer.class]
	if not mt or not mt.__index then return end

	local index = mt.__index
	local originalHasRoomFor = index.hasRoomFor
	local originalgetEffectiveCapacity = index.getEffectiveCapacity

	function index:getEffectiveCapacity(chr)
		local base = originalgetEffectiveCapacity(self, chr)
		local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
		if sv and sv.TrunkScaling and self:getParent() and instanceof(self:getParent(),"BaseVehicle") then
			if isCargoContainer(self:getType()) then
				local bucket, mult = vehicleBucket(self:getParent():getScript():getFullType(), sv)
				if bucket and mult and mult ~= 1.0 then
					if not trunkHookHitOnce then
						trunkHookHitOnce = true
						print(string.format(
							"[BVD] TrunkScaling hit: vehicle=%s container=%s bucket=%s base=%.0f mult=%.2f -> %.0f",
							tostring(self:getParent():getScript():getFullType()),
							tostring(self:getType()),
							tostring(bucket),
							base, mult, base * mult))
					end
					return base * mult
				end
			end
		end
		return base
	end

	function index:hasRoomFor(chr, item)
		local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
		if sv and sv.TrunkScaling and self:getParent() and instanceof(self:getParent(),"BaseVehicle") then
			if isCargoContainer(self:getType()) then
				local bucket, mult = vehicleBucket(self:getParent():getScript():getFullType(), sv)
				if bucket and mult and mult ~= 1.0 then
					if type(item) ~= "number" then
						item = item:getWeight()
					end
					return (self:getCapacityWeight() + item) <= self:getEffectiveCapacity(chr)
				end
			end
		end
		return originalHasRoomFor(self, chr, item)
	end

	trunkPatched = true
	print("[BVD] TrunkScaling: container hook installed.")
end

pcall(patchTrunkContainers)
Events.OnGameStart.Add(function() pcall(patchTrunkContainers) end)

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

local function applyHPWeight()
	local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
	if not sv or sv.RealismHPWeight ~= true then return end
	local sm = getScriptManager and getScriptManager()
	if not sm then return end
	-- Merge every registered data pack into our vehicle table just before
	-- we apply. OnInitGlobalModData is late enough that all shared/ files
	-- have loaded and any BVD.registerPack / BVD.Packs.register calls have
	-- run. registerVehicle writes straight into vehicleData already; this
	-- folds in the pack path too. Guarded — a broken pack must not abort
	-- the built-in table apply below.
	if BVD and BVD.Packs and BVD.Packs.applyAll then
		pcall(function() BVD.Packs.applyAll(vehicleData) end)
	end
	local touched = 0
	for fullType, spec in pairs(vehicleData) do
		-- 'cargo' is validated + stored but reserved (see header note). If
		-- any registered entry carries it, surface ONE info line. This is
		-- the only place all registered data (built-in + packs) is funneled,
		-- so it fires exactly once regardless of how cargo was registered.
		-- Pure log — never mutates spec or the vehicle, so a registration
		-- with no cargo is byte-identical to before this change.
		if spec.cargo ~= nil then noteReservedCargo() end
		local v = sm:getVehicle(fullType)
		if v ~= nil then
			local hp = spec.hp
			local mass = spec.mass_kg
			if hp and mass then
				v:Load(v:getName(), "{ engineForce = " .. (hp * 10) .. ", mass = " .. mass .. ", }")
			elseif hp then
				v:Load(v:getName(), "{ engineForce = " .. (hp * 10) .. ", }")
			elseif mass then
				v:Load(v:getName(), "{ mass = " .. mass .. ", }")
			end
			touched = touched + 1
		end
	end
	print(string.format("[BVD] HPWeight applied to %d vehicles", touched))
end

Events.OnInitGlobalModData.Add(applyHPWeight)
