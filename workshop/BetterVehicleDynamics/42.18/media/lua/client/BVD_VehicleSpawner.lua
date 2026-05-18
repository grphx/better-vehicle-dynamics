-- BVD_VehicleSpawner: collapsable window listing every vehicle from every
-- enabled BVD_Packs entry, with a per-row Spawn button that drops the
-- vehicle on the player's tile via PZ's debug spawn API.
--
-- Gated by admin / SP / -debug launch (see BVD_DebugMenu).

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

BVD_VehicleSpawnerWindow = ISCollapsableWindow:derive("BVD_VehicleSpawnerWindow")

local _instance = nil
local PANEL_W = 460
local PANEL_H = 600

-- ---------------------------------------------------------------------------
-- Build the row list by walking every vehicle script the game knows about.
-- Each script's module is used as the "source" tag in the list.
-- ---------------------------------------------------------------------------

local function collectVehicleRows()
    local rows = {}
    local seen = {}

    local function addRow(fullType, source)
        if seen[fullType] then return end
        seen[fullType] = true
        table.insert(rows, {
            fullType = fullType,
            pack     = source or "?",
        })
    end

    -- getAllVehicleScripts() returns an ArrayList<VehicleScript> with every
    -- vehicle PZ has loaded (vanilla + every active mod).
    local sm = getScriptManager and getScriptManager()
    if sm then
        local list
        pcall(function() list = sm:getAllVehicleScripts() end)
        if list then
            for i = 0, list:size() - 1 do
                local v = list:get(i)
                local ok, ft = pcall(function() return v:getFullName() end)
                if not ok or not ft then
                    pcall(function() ft = v:getName() end)
                end
                if ft then
                    -- Module is everything before the dot.
                    local mod = ft:match("^([^.]+)%.") or "Base"
                    addRow(ft, mod)
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.pack == b.pack then return a.fullType < b.fullType end
        return a.pack < b.pack
    end)
    return rows
end

-- ---------------------------------------------------------------------------
-- Spawning
-- ---------------------------------------------------------------------------

local function spawnVehicleAtPlayer(fullType)
    local player = getSpecificPlayer(0)
    if not player then return false, "no player" end
    local square = player:getCurrentSquare()
    if not square then return false, "no square" end
    -- Canonical B42 signature (verified against damnlib + Bandits mods):
    --   addVehicleDebug(scriptName, IsoDirections dir, Integer skinIndex, IsoGridSquare square)
    local ok, err = pcall(function()
        addVehicleDebug(fullType, IsoDirections.N, nil, square)
    end)
    if not ok then return false, tostring(err) end
    return true
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

function BVD_VehicleSpawnerWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function BVD_VehicleSpawnerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local titleH = self:titleBarHeight()
    local pad = 8
    local y = titleH + pad

    -- Filter row
    self.filterLabel = ISLabel:new(pad, y, 18, "Filter:", 1, 1, 1, 1, UIFont.Small, true)
    self.filterLabel:initialise()
    self.filterLabel:instantiate()
    self:addChild(self.filterLabel)

    self.filterEntry = ISTextEntryBox:new("", pad + 50, y - 2, self.width - pad * 2 - 60, 22)
    self.filterEntry:initialise()
    self.filterEntry:instantiate()
    self.filterEntry.onTextChange = function() self:rebuildList() end
    self:addChild(self.filterEntry)

    y = y + 28

    -- Counts label
    self.countLabel = ISLabel:new(pad, y, 16,
        "loading...", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    self.countLabel:initialise()
    self.countLabel:instantiate()
    self:addChild(self.countLabel)

    y = y + 22

    -- Scrolling list
    self.list = ISScrollingListBox:new(pad, y, self.width - pad * 2,
        self.height - y - pad - 4)
    self.list:initialise()
    self.list:instantiate()
    -- IMPORTANT: ISScrollingListBox's prerender does arithmetic on these
    -- fields. They MUST be numbers before the first render or you get a
    -- "__sub not defined for operands" crash from ISScrollingListBox.lua:531.
    self.list.itemheight   = 28
    self.list.selected     = 0
    self.list.smListHeight = 0
    self.list.drawBorder   = true
    self.list.font         = UIFont.Small
    self.list.joypadParent = self
    self.list.doDrawItem   = function(lb, lY, item, alt) return self:drawRow(lb, lY, item, alt) end
    self:addChild(self.list)

    self.allRows = collectVehicleRows()
    self:rebuildList()
end

function BVD_VehicleSpawnerWindow:rebuildList()
    self.list:clear()
    local needle = (self.filterEntry and self.filterEntry:getText() or ""):lower()
    local shown = 0
    for _, row in ipairs(self.allRows) do
        if needle == "" or row.fullType:lower():find(needle, 1, true)
                or row.pack:lower():find(needle, 1, true) then
            self.list:addItem(row.fullType, row)
            shown = shown + 1
        end
    end
    if self.countLabel then
        self.countLabel:setName(string.format(
            "%d of %d vehicles (click row to spawn at your tile)",
            shown, #self.allRows))
    end
end

function BVD_VehicleSpawnerWindow:drawRow(lb, y, item, alt)
    local row = item.item
    local h = lb.itemheight
    if self.list.selected == item.index then
        lb:drawRect(0, y, lb.width, h, 0.3, 0.2, 0.6, 0.9)
    elseif alt then
        lb:drawRect(0, y, lb.width, h, 0.2, 0.15, 0.15, 0.15)
    end
    -- Pack tag (left, color-keyed)
    local packColor = { r = 0.7, g = 0.8, b = 1.0 }
    if row.pack == "Base" then
        packColor = { r = 0.85, g = 0.85, b = 0.85 }
    end
    lb:drawText("[" .. row.pack .. "]", 6, y + 4, packColor.r, packColor.g, packColor.b, 1, UIFont.Small)
    lb:drawText(row.fullType, 110, y + 4, 1, 1, 1, 1, UIFont.Small)
    return y + h
end

function BVD_VehicleSpawnerWindow:onMouseUp(x, y)
    -- Row click-to-spawn is handled entirely on the inner list via
    -- patchListClick (self.list.onMouseUp), NOT here — so this window
    -- override must not swallow the event. It previously did nothing,
    -- which meant ISCollapsableWindow's own onMouseUp never ran and the
    -- title-bar drag-release / resize-end / move-end logic was dead. Pass
    -- through to the base implementation so dragging and resizing work.
    return ISCollapsableWindow.onMouseUp(self, x, y)
end

function BVD_VehicleSpawnerWindow:onSelectRow()
    if not self.list then return end
    local item = self.list.items[self.list.selected]
    if not item or not item.item then return end
    local row = item.item
    local ok, err = spawnVehicleAtPlayer(row.fullType)
    local player = getSpecificPlayer(0)
    if ok then
        if player and player.Say then
            pcall(function() player:Say("[BVD] spawned " .. row.fullType) end)
        end
    else
        if player and player.Say then
            pcall(function() player:Say("[BVD] spawn failed: " .. tostring(err)) end)
        end
    end
end

-- Hook ISScrollingListBox's row click. Easiest path: override onMouseUp
-- of the list itself to detect click + then call onSelectRow.
local function patchListClick(self)
    local origMouseUp = self.list.onMouseUp
    self.list.onMouseUp = function(lb, mx, my)
        if origMouseUp then origMouseUp(lb, mx, my) end
        self:onSelectRow()
    end
end

function BVD_VehicleSpawnerWindow:onResolutionChange(oldW, oldH, newW, newH)
    -- Re-anchor if needed; for now, ignore.
end

-- ---------------------------------------------------------------------------
-- Public open()
-- ---------------------------------------------------------------------------

function BVD_VehicleSpawner_open()
    if _instance and _instance:getIsVisible() then
        _instance:close()
        return
    end
    if not _instance then
        local x = (getCore():getScreenWidth() - PANEL_W) / 2
        local y = (getCore():getScreenHeight() - PANEL_H) / 2
        _instance = BVD_VehicleSpawnerWindow:new(x, y, PANEL_W, PANEL_H)
        _instance:setTitle("BVD Vehicle Spawner (debug)")
        _instance:setResizable(true)
        _instance:initialise()
        _instance:addToUIManager()
        patchListClick(_instance)
    else
        _instance:setVisible(true)
        _instance:addToUIManager()
    end
end

print("[BVD] VehicleSpawner client loaded")
