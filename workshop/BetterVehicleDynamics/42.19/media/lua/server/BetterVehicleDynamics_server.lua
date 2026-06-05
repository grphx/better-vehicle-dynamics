function BetterVehicleDynamicsVersionCheckServer()
	if BetterVehicleDynamicsMod.javaVersion == "not installed" and not VersionCheckConfirmed then
		--VersionCheckConfirmed = true; -- spam if not installed.
		print("Better Vehicle Dynamics is not properly installed on your server. See Steam workshop page for details");
	elseif BetterVehicleDynamicsMod.javaVersion ~= "3.4" and not VersionCheckConfirmed then
		--VersionCheckConfirmed = true; -- spam if out of date
		print("Better Vehicle Dynamics manual install is outdated on your server. Reinstall Zombie Folder to update to latest version. See Steam workshop page for details")
	else
		VersionCheckConfirmed = true;
	end
end

if isServer() then
	Events.OnSpawnVehicleEnd.Add(BetterVehicleDynamicsVersionCheckServer)
end
