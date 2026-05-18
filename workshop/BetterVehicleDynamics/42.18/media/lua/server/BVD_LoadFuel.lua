-- BVD_LoadFuel.lua — extra fuel burn proportional to how laden a vehicle
-- is. Pure Lua (no Java). Mutates the GasTank container directly, so it
-- is future-tunable via Workshop with zero manual reinstall.
--
-- MP authority: vehicle fuel is shared state. To avoid N-fold draining,
-- the write happens ONLY where it is authoritative: dedicated/host server
-- in MP, the local game in single-player. Clients render the synced tank.

BVD = BVD or {}

local LOAD_FUEL_RATE = 0.0009   -- tank-units/sec of EXTRA drain per unit
                                -- of (ladenRatio-1) at full throttle.
                                -- Subtle but noticeable when heavy.
local lastMs = {}               -- per-vehicle id -> last apply ms

-- Is this game instance the authority for world/vehicle state writes?
local function isAuthority()
    if isClient and isClient() then return false end  -- MP client: no
    return true                                       -- SP or server/host
end

local function cfgOn()
    if BVD and BVD.cfg then
        local ok, c = pcall(BVD.cfg)
        if ok and type(c) == "table" then return c.LoadAffectsFuel ~= false end
    end
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    return not (sv and sv.LoadAffectsFuel == false)
end

local function baseMassOf(v)
    local m
    pcall(function()
        local s = v:getScript()
        if s and s.getMass then m = s:getMass() end
    end)
    if BVD and type(BVD.getVehicleData) == "function" then
        pcall(function()
            local s = v:getScript()
            local ft = s and s.getFullType and s:getFullType()
            local d = ft and BVD.getVehicleData(ft)
            if d and type(d.mass_kg) == "number" and d.mass_kg > 0 then
                m = d.mass_kg
            end
        end)
    end
    return m
end

local function tick(v)
    if not v or not v.isEngineRunning then return end
    local okEng, running = pcall(function() return v:isEngineRunning() end)
    if not okEng or not running then return end

    local base = baseMassOf(v)
    if not base or base <= 0 then return end
    local cur = 0
    pcall(function() cur = v:getMass() or 0 end)
    local ratio = cur / base
    if ratio <= 1.0 then return end
    if ratio > 3.0 then ratio = 3.0 end

    -- Only burn the extra while the driver is actually on the gas. Vanilla
    -- pedals are digital, so gas-pressed == full throttle (1.0); there is no
    -- analog throttle getter on the B42 vehicle object (isGasPedalPressed is
    -- the accessor the rest of the mod uses).
    local gas = false
    pcall(function() gas = v:isGasPedalPressed() == true end)
    if not gas then return end
    local thr = 1.0

    local id  = (v.getId and v:getId()) or tostring(v)
    local now = (getTimestampMs and getTimestampMs()) or 0
    local prev = lastMs[id] or now
    lastMs[id] = now
    local dt = (now - prev) / 1000.0
    if dt <= 0 or dt > 5 then return end          -- skip first/odd frames

    local extra = LOAD_FUEL_RATE * (ratio - 1.0) * thr * dt
    if extra <= 0 then return end

    pcall(function()
        local gt = v:getPartById("GasTank")
        if not gt then return end
        local amt = gt:getContainerContentAmount()
        if type(amt) ~= "number" then return end
        local nv = amt - extra
        if nv < 0 then nv = 0 end
        gt:setContainerContentAmount(nv)
    end)
end

local function onPlayerUpdate(player)
    if not isAuthority() then return end
    if not cfgOn() then return end
    if not player or player:isDead() then return end
    local v = player:getVehicle()
    if v then tick(v) end
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end

print("[BVD.LoadFuel] load-sensitive fuel drain installed (authority-gated)")
