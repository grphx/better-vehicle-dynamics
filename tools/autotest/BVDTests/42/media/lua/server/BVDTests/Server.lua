-- Test-server commands: spawn a vehicle for a client (clients cannot in MP), then make it drivable.
require "BVDTests/Fix"

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "BVDTests" or command ~= "spawn" then return end
    local sq = getCell():getGridSquare(args.x, args.y, 0)
    if not sq then return end
    local v = addVehicleDebug(args.script, IsoDirections.E, nil, sq)
    if v then BVDTestsFix(v) end
end)
