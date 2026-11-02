-- Make a debug-spawned car drivable: spawns come in random condition
-- (dead battery, empty tank, locked doors), which would make the drive
-- checks luck.
BVDTestsFix = function(v)
    v:repair()
    local tank = v:getPartById("GasTank")
    if tank then
        tank:setContainerContentAmount(tank:getContainerCapacity())
        v:transmitPartModData(tank)
    end
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        local door = part:getDoor()
        if door and door:isLocked() then
            door:setLocked(false)
            v:transmitPartDoor(part)
        end
    end
    local bat = v:getPartById("Battery")
    if bat and bat:getInventoryItem() then
        bat:getInventoryItem():setUsedDelta(1.0)
        v:transmitPartUsedDelta(bat)
    end
end

-- Fit a full set of good tires the way the game's own install does it. A debug-spawned car can come without tires
-- (the game marks those wheels "removed" in the physics, so the engine drives nothing) or with flat ones (a tire
-- with no air explodes and drops on the road as soon as the car runs above 10 km/h). Swapping the part's item is
-- not enough: the air, the physics flag and the wheel model all have to be set too.
BVDTestsFitTires = function(v, tireType)
    tireType = tireType or "Base.NormalTire2"
    for _, id in ipairs({ "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }) do
        local part = v:getPartById(id)
        if part then
            local item = instanceItem(tireType)
            item:setCondition(100)
            part:setInventoryItem(item)
            part:setCondition(100)
            local cap = 0
            pcall(function() cap = part:getContainerCapacity() end)   -- what the game itself fills a tire to
            if cap > 0 then pcall(function() part:setContainerContentAmount(cap, false, true) end) end
            pcall(function() part:setModelVisible("InflatedTirePlusWheel", true) end)
            v:transmitPartItem(part)
            v:setTireRemoved(part:getWheelIndex(), false)
        end
    end
    pcall(function() v:updatePartStats() end)
end
