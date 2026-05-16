-- BVD_API.lua — public registration API for other vehicle mods.
--
-- Other mods can call BVD.registerVehicle to add per-vehicle data that
-- BVD will apply when HPWeight Overhaul is enabled. The data is read at
-- OnInitGlobalModData by BVD_Overhaul.lua, so callers should register at
-- module load time (anywhere in a shared/ lua file) to be safe.
--
-- Schema:
--   BVD.registerVehicle("Base.MyCar", { hp = 200, mass_kg = 1500, cargo = 250 })
--
-- Vehicles registered this way are merged into the same table that
-- BVD_VehicleData.lua populates. Modder values override built-in entries
-- if the scriptName matches.

BVD = BVD or {}

local function err(msg) error("[BVD.API] " .. msg, 3) end

-- Module reference for BVD_VehicleData. We require lazily because the API
-- module can load before the data module in some load orders.
local function dataTable()
    local ok, t = pcall(require, "BVD_VehicleData")
    if ok and type(t) == "table" then return t end
    return nil
end

function BVD.registerVehicle(scriptName, data)
    if type(scriptName) ~= "string" or scriptName == "" then
        err("registerVehicle: scriptName must be a non-empty string")
    end
    if type(data) ~= "table" then
        err("registerVehicle: data must be a table")
    end
    if data.hp ~= nil and (type(data.hp) ~= "number" or data.hp <= 0) then
        err("registerVehicle('" .. scriptName .. "'): hp must be a positive number")
    end
    if data.mass_kg ~= nil and (type(data.mass_kg) ~= "number" or data.mass_kg <= 0) then
        err("registerVehicle('" .. scriptName .. "'): mass_kg must be a positive number")
    end

    local t = dataTable()
    if t then
        if t[scriptName] ~= nil then
            print("[BVD.API] overwriting existing vehicle entry: " .. scriptName)
        end
        t[scriptName] = data
    end
    return data
end

function BVD.registerVehicles(entries)
    if type(entries) ~= "table" then
        err("registerVehicles: entries must be a table")
    end
    for k, v in pairs(entries) do BVD.registerVehicle(k, v) end
end

function BVD.getRegisteredVehicles()
    return dataTable() or {}
end

function BVD.getVehicleData(scriptName)
    local t = dataTable()
    return t and t[scriptName]
end

return BVD
