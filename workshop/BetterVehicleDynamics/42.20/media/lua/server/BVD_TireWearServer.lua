-- BVD_TireWearServer.lua  (server / singleplayer)
--
-- Applies BVD's "tires wear from wheel slip" to a vehicle. The driver's
-- client counts the slip (client/BVD_RuntimeChecks.lua) and asks for a few
-- condition points; this side changes the vehicle PART, so the mechanics
-- window shows it, the grip model reads it, the tire item follows it, and
-- transmitPartCondition (which only does anything on a server) sends it to
-- every player. Pure Lua; no Java install needed.

BVD = BVD or {}

local DRIVEN_TIRES = { "TireRearLeft", "TireRearRight" }   -- only the rear wheels get engine force
local MAX_POINTS_PER_REQUEST = 5
local MIN_INTERVAL_MS = 900          -- a client asks about every 2 s at the default rate; this stops spamming
local lastRequestAt = {}             -- vehicle id -> last accepted request, ms

local function wearEnabled()
    local ok, cfg = pcall(BVD.cfg)
    return ok and type(cfg) == "table" and cfg.TireSlipWear == true
end

local function onClientCommand(module, command, player, args)
    if module ~= "BetterVehicleDynamics" or command ~= "tireWear" then return end
    if type(args) ~= "table" or not wearEnabled() then return end

    local vehicle = getVehicleById(tonumber(args.vehicle) or -1)
    if not vehicle or not vehicle:isDriver(player) then return end

    local now = getTimestampMs()
    local id = vehicle:getId()
    if lastRequestAt[id] and now - lastRequestAt[id] < MIN_INTERVAL_MS then return end
    lastRequestAt[id] = now

    local points = math.floor(tonumber(args.points) or 0)
    points = math.max(0, math.min(points, MAX_POINTS_PER_REQUEST))
    if points == 0 then return end

    for _, partId in ipairs(DRIVEN_TIRES) do
        local part = vehicle:getPartById(partId)
        if part and part:getInventoryItem() then
            local condition = part:getCondition()
            if condition > 0 then
                part:setCondition(math.max(0, condition - points))
                vehicle:transmitPartCondition(part)
            end
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
