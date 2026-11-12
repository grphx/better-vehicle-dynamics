-- BVD_InstallNotice.lua  (client)
--
-- A short notice for a player whose copy of BVD has no working Java part (it is missing, or an old one is installed).
-- It never takes input and never pauses the game: a player who has just logged in in the middle of a horde keeps
-- playing. It sits in the top right corner, clear of the middle of the view, fades out after NOTICE_LIFE_MS and is shown once per game session.
-- Pure Lua.

require "ISUI/ISPanel"

BVD = BVD or {}

local W = 400
local MARGIN_RIGHT = 110   -- keeps clear of the moodle column on the right edge
local MARGIN_TOP = 64     -- below the game speed buttons
local PAD = 12
local NOTICE_LIFE_MS = 30000
local NOTICE_FADE_MS = 4000

local function nowMs()
    return getTimestampMs and getTimestampMs() or 0
end

BVDInstallNotice = ISPanel:derive("BVDInstallNotice")

function BVDInstallNotice:new(x, y, w, h, title, lines, life)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.title, o.lines = title, lines
    o.born = nowMs()
    o.life = life
    return o
end

--- 1 while it is fully shown, down to 0 over the last NOTICE_FADE_MS.
function BVDInstallNotice:alpha()
    local left = self.born + self.life - nowMs()
    if left <= 0 then return 0 end
    return math.min(1, left / NOTICE_FADE_MS)
end

function BVDInstallNotice:update()
    if self:alpha() <= 0 then self:removeFromUIManager() end
end

function BVDInstallNotice:render()
    local a = self:alpha()
    if a <= 0 then return end
    local tm = getTextManager()
    local lh = tm:getFontHeight(UIFont.Small)
    self:drawRect(0, 0, self.width, self.height, 0.78 * a, 0, 0, 0)
    self:drawRect(0, 0, 4, self.height, a, 0.95, 0.45, 0.15)
    self:drawText(self.title, PAD + 4, PAD, 1, 0.65, 0.3, a, UIFont.Medium)
    local y = PAD + tm:getFontHeight(UIFont.Medium) + 4
    for _, line in ipairs(self.lines) do
        self:drawText(line, PAD + 4, y, 1, 1, 1, a, UIFont.Small)
        y = y + lh
    end
end

--- Break `text` into lines no wider than `width` pixels.
local function wrap(text, width)
    local tm = getTextManager()
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if cur ~= "" and tm:MeasureStringX(UIFont.Small, try) > width then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

local panel = nil

--- Show the notice named by the translation key `key`. Does nothing if one is already up.
function BVD.showInstallNotice(key)
    if panel and panel:alpha() > 0 then return end
    local ok = pcall(function()
        local lines = wrap(getText(key), W - 2 * PAD - 4)
        local tm = getTextManager()
        local h = 2 * PAD + tm:getFontHeight(UIFont.Medium) + 4 + #lines * tm:getFontHeight(UIFont.Small)
        local x = getCore():getScreenWidth() - W - MARGIN_RIGHT
        panel = BVDInstallNotice:new(x, MARGIN_TOP, W, h, "Better Vehicle Dynamics", lines, BVD.installNoticeLifeMs or NOTICE_LIFE_MS)
        panel:initialise()
        panel:instantiate()
        panel.javaObject:setConsumeMouseEvents(false)   -- a notice, not a window: clicks pass through
        panel:addToUIManager()
    end)
    if not ok then panel = nil end
end

--- Test hook: is the notice up?
function BVD.installNoticeShown()
    return panel ~= nil and panel:alpha() > 0
end

return {}
