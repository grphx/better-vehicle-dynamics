-- BVD_SkidPurge.lua — debug action: remove every BVD tyre-mark floor
-- decal from the loaded chunks around the player.
--
-- This doubles as a PROBE. PZ's floor-splat stores are Java collections;
-- whether Lua can read the chunk field and drive the collection API is
-- exactly what we are unsure of. The action prints a one-line summary
-- (field-readable / api-usable / removed count) so the console tells us
-- which removal path actually works in the live game.

local MIN_T, MAX_T   = 21, 24    -- BVD tyre-mark floor-splat type ids
local CHUNK_TILES    = 8         -- tiles per chunk side
local RADIUS_TILES   = 120       -- cover the loaded area generously

local function isSkid(t)
    return type(t) == "number" and t >= MIN_T and t <= MAX_T
end

local function splatType(s)
    local t
    if not pcall(function() t = s.type end) or t == nil then
        pcall(function() t = s:getType() end)
    end
    return t
end

-- A chunk's floorBloodSplats is a BoundedQueue and floorBloodSplatsFade
-- an ArrayList; both expose size()/get(i)/clear()/add(e), so the same
-- "keep the survivors, drop the skids" rebuild works for either.
-- Returns removed count, or nil if the collection API is unusable.
local function purgeCollection(c)
    if c == nil then return nil end
    local okSize, n = pcall(function() return c:size() end)
    if not okSize or type(n) ~= "number" then return nil end
    local keep, removed = {}, 0
    for i = 0, n - 1 do
        local okGet, s = pcall(function() return c:get(i) end)
        if okGet and s ~= nil then
            if isSkid(splatType(s)) then
                removed = removed + 1
            else
                keep[#keep + 1] = s
            end
        end
    end
    if removed == 0 then return 0 end
    if not pcall(function() c:clear() end) then return nil end
    for i = 1, #keep do
        pcall(function() c:add(keep[i]) end)
    end
    return removed
end

-- Public entry — invoked from the debug menu.
function BVD_ClearSkidMarks()
    local player = getSpecificPlayer(0)
    local cell   = getCell and getCell()
    if not player or not cell then
        print("[BVD.SkidPurge] no player/cell — load into the world first")
        return
    end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    local seen, chunks = {}, {}
    for dx = -RADIUS_TILES, RADIUS_TILES, CHUNK_TILES do
        for dy = -RADIUS_TILES, RADIUS_TILES, CHUNK_TILES do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            local ch = sq and sq.getChunk and sq:getChunk()
            if ch then
                local key
                pcall(function() key = ch:getChunkX() .. ":" .. ch:getChunkY() end)
                key = key or tostring(ch)
                if not seen[key] then
                    seen[key] = true
                    chunks[#chunks + 1] = ch
                end
            end
        end
    end

    local readable, usable, removed = false, false, 0
    for i = 1, #chunks do
        local ch = chunks[i]
        local q, qf
        pcall(function() q  = ch.floorBloodSplats end)
        pcall(function() qf = ch.floorBloodSplatsFade end)
        if q ~= nil or qf ~= nil then readable = true end
        local r1 = purgeCollection(q)
        local r2 = purgeCollection(qf)
        if r1 ~= nil or r2 ~= nil then usable = true end
        removed = removed + (r1 or 0) + (r2 or 0)
    end

    print(string.format(
        "[BVD.SkidPurge] chunks=%d  field-readable=%s  api-usable=%s  removed=%d",
        #chunks, tostring(readable), tostring(usable), removed))
    pcall(function()
        player:Say("BVD: cleared " .. removed .. " skid mark(s)")
    end)
end

print("[BVD] SkidPurge probe loaded")
