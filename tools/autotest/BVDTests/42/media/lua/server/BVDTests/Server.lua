-- Test-server command: spawn a vehicle for a client (clients cannot in MP).
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "BVDTests" or command ~= "spawn" then return end
    local sq = getCell():getGridSquare(args.x, args.y, 0)
    if sq then addVehicleDebug(args.script, IsoDirections.E, nil, sq) end
end)
