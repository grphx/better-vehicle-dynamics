-- BVD_DebugMenu: admin right-click context menu for Better Vehicle Dynamics.
-- Pattern matches Director's ZT_DebugMenu — submenu gated by admin / SP /
-- -debug launch.

local function isAuthorized(player)
    if not player then return false end
    if not isClient() then return true end -- SP / listen host
    local ok, isAdm = pcall(isAdmin)
    if ok and isAdm then return true end
    local lvl
    pcall(function() lvl = player:getAccessLevel() end)
    if lvl == "Admin" or lvl == "admin"
        or lvl == "Moderator" or lvl == "moderator" then
        return true
    end
    local okDbg, dbg = pcall(function() return getCore():getDebug() end)
    if okDbg and dbg then return true end
    return false
end

local function addBvdDebugMenu(playerIndex, context, worldObjects, test)
    if test then return true end
    local player = getSpecificPlayer(playerIndex or 0)
    if not isAuthorized(player) then return end

    local parent = context:addOption("Better Vehicle Dynamics", nil, nil)
    local sub    = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)

    sub:addOption("Open Vehicle Spawner", nil, function()
        if BVD_VehicleSpawner_open then
            BVD_VehicleSpawner_open()
        else
            player:Say("[BVD] spawner UI not loaded")
        end
    end)

    sub:addOption("Clear all skid marks", nil, function()
        if BVD_ClearSkidMarks then
            BVD_ClearSkidMarks()
        else
            player:Say("[BVD] skid purge not loaded")
        end
    end)
end

Events.OnFillWorldObjectContextMenu.Add(addBvdDebugMenu)

print("[BVD] DebugMenu loaded")
