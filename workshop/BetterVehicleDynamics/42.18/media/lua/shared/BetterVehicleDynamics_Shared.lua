print("Better Vehicle Dynamics Loaded")

-- Load-order-safe seed of the bridge globals. The PRIMARY init guard lives
-- in client/BetterVehicleDynamics.lua (the owning file); this shared file
-- only seeds defaults. Use `or {}` rather than a bare `= {}` so that if a
-- sister file (client bridge / drift bridge) already created the table we
-- do not wipe the fields it set. The default fields use `if nil` seeding
-- for the same reason — never clobber a value another module already wrote.
BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}
if BetterVehicleDynamicsMod.javaVersion == nil then
	BetterVehicleDynamicsMod.javaVersion = "not installed" -- Not installed.
end
if BetterVehicleDynamicsMod.forceGear == nil then
	BetterVehicleDynamicsMod.forceGear = 1;
end
