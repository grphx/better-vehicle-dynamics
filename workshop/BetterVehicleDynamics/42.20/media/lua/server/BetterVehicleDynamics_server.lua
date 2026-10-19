-- Dedicated servers never simulate vehicle physics (the driving client does),
-- so the Java side is client-only and a server without it is the normal case.
-- Log one informational line instead of a warning on every vehicle spawn.
local VersionCheckConfirmed = false

function BetterVehicleDynamicsVersionCheckServer()
	if VersionCheckConfirmed then return end
	VersionCheckConfirmed = true
	if BetterVehicleDynamicsMod.javaVersion == "not installed" then
		print("Better Vehicle Dynamics: no Java side on this server - that is expected, only players need it.")
	elseif BetterVehicleDynamicsMod.javaVersion ~= "3.4" then
		print("Better Vehicle Dynamics: this server has an old Java side (" .. tostring(BetterVehicleDynamicsMod.javaVersion) .. "). The server does not need it; it is safe to remove.")
	end
end

if isServer() then
	Events.OnSpawnVehicleEnd.Add(BetterVehicleDynamicsVersionCheckServer)
end
