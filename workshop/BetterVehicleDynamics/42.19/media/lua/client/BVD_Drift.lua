-- BVD_Drift.lua — drift-mode key state bridge.
--
-- Reads the user's configured drift key from PZAPI ModOptions
-- (registered as "DriftKey" in BetterVehicleDynamics.lua, default
-- Left Shift). Polls per OnPlayerUpdate while the player is driving
-- and writes the result to BetterVehicleDynamicsMod.driftActive so
-- the Java side can apply drift physics in CarController.applyFriction.

require "PZAPI/ModOptions"

-- SECONDARY bridge-global init guard. The PRIMARY guard lives in the
-- owning file client/BetterVehicleDynamics.lua. This `or {}` is kept here
-- so the drift bridge is still safe in load orders where this file
-- happens to execute before the owning file. Behaviour-identical to the
-- previous code — same `or {}`, just now explicitly the secondary.
BetterVehicleDynamicsMod = BetterVehicleDynamicsMod or {}
BetterVehicleDynamicsMod.driftActive = false

local function getDriftKey()
    -- Look up the PZAPI ModOptions instance our sister file registered.
    -- Cached at boot via a closure; safe to re-query if user changes binding.
    local opts = PZAPI.ModOptions:getOptions("BetterVehicleDynamics")
    if not opts then return Keyboard.KEY_LSHIFT end
    local bind = opts:getOption("DriftKey")
    if bind and bind.getValue then
        local k = bind:getValue()
        if k and k ~= 0 then return k end
    end
    return Keyboard.KEY_LSHIFT
end

local wasDrifting   = false
local driftSoundId  = nil
local driftVehicle  = nil

local function stopDriftSound()
    if driftSoundId and driftVehicle then
        pcall(function() driftVehicle:stopSound(driftSoundId) end)
    end
    driftSoundId = nil
    driftVehicle = nil
end

local function onPlayerUpdate(player)
    if not player or player:isDead() then
        BetterVehicleDynamicsMod.driftActive = false
        if wasDrifting then stopDriftSound(); wasDrifting = false end
        return
    end
    local v = player:getVehicle()
    if not v or v:getDriver() ~= player then
        BetterVehicleDynamicsMod.driftActive = false
        if wasDrifting then stopDriftSound(); wasDrifting = false end
        return
    end

    local nowDrifting = isKeyDown(getDriftKey()) == true
    BetterVehicleDynamicsMod.driftActive = nowDrifting

    if nowDrifting and not wasDrifting then
        pcall(function()
            driftSoundId = v:playSoundImpl("VehicleHandBrake", nil)
            driftVehicle = v
        end)
    elseif not nowDrifting and wasDrifting then
        stopDriftSound()
    end

    wasDrifting = nowDrifting
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
