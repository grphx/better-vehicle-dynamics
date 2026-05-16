local MIN_INTERVAL_MS = 380
local DEDUPE_MS       = 1500
local BURNOUT_SPEED   = 10
local SKID_SPEED      = 30

local TYPE_V, TYPE_H, TYPE_D1, TYPE_D2 = 21, 22, 23, 24

local LAST_TICK_MS = 0
local recentTiles  = {}

local function preloadTextures()
    local files = {
        bvd_tiremark_v  = "media/textures/Item_bvd_tiremark_v.png",
        bvd_tiremark_h  = "media/textures/Item_bvd_tiremark_h.png",
        bvd_tiremark_d1 = "media/textures/Item_bvd_tiremark_d1.png",
        bvd_tiremark_d2 = "media/textures/Item_bvd_tiremark_d2.png",
    }
    for name, path in pairs(files) do
        local t = getTexture(path)
        if t and Texture and Texture.BVD_registerSharedTexture then
            Texture.BVD_registerSharedTexture(name, t)
        end
    end
    print("[BVD.Skidmarks] 4 orientation sprites registered")
end

Events.OnGameBoot.Add(preloadTextures)

local function typeForVehicle(v)
    local d = nil
    if v.getDir then d = v:getDir() end
    if not d then return TYPE_V end
    local n = tostring(d)
    if     n == "N" or n == "S"   then return TYPE_V
    elseif n == "E" or n == "W"   then return TYPE_H
    elseif n == "NE" or n == "SW" then return TYPE_D1
    elseif n == "NW" or n == "SE" then return TYPE_D2
    end
    return TYPE_V
end

local function dropMark(v, sq)
    if not sq then return end
    local chunk = sq.getChunk and sq:getChunk()
    if not chunk or not chunk.addBloodSplat then return end

    -- Vehicle world coords (floats). chunk:addBloodSplat treats them as
    -- the splat's render anchor inside the resolved tile.
    local vx = v:getX() or sq:getX()
    local vy = v:getY() or sq:getY()
    local vz = v:getZ() or sq:getZ()

    local key = math.floor(vx) .. "," .. math.floor(vy) .. "," .. math.floor(vz)
    local now = getTimestampMs and getTimestampMs() or 0
    if recentTiles[key] and (now - recentTiles[key]) < DEDUPE_MS then return end
    recentTiles[key] = now

    if (now % 8000) < 50 then
        for k, t in pairs(recentTiles) do
            if (now - t) > DEDUPE_MS * 4 then recentTiles[k] = nil end
        end
    end

    chunk:addBloodSplat(vx, vy, vz, typeForVehicle(v))
end

local function onPlayerUpdate(player)
    if not player or player:isDead() then return end
    local sv = SandboxVars and SandboxVars.BetterVehicleDynamics
    if sv and sv.SkidMarks == false then return end
    local v = player:getVehicle()
    if not v or v:getDriver() ~= player then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if now - LAST_TICK_MS < MIN_INTERVAL_MS then return end

    local speed = v:getCurrentSpeedKmHour() or 0
    if speed < 0 then speed = -speed end
    local gas, brake = v:isGasPedalPressed(), v:isBrakePedalPressed()
    local drifting  = BetterVehicleDynamicsMod
                       and BetterVehicleDynamicsMod.driftActive == true
                       and speed > 15
    local isBurnout = speed < BURNOUT_SPEED and gas
    local isSkid    = speed > SKID_SPEED    and brake
    if not (isBurnout or isSkid or drifting) then return end

    dropMark(v, v:getCurrentSquare())
    LAST_TICK_MS = now
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
print("[BVD.Skidmarks] tire-mark decal hook installed (4 orientations)")
