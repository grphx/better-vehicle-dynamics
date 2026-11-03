local f = io.open("/home/grphx/zomboid/better-vehicle-dynamics/workshop/BetterVehicleDynamics/42.20/media/lua/client/BVD_HUD.lua", "r")
local src = f:read("*a"); f:close()
local a = src:find("function BVD.dockCompanion", 1, true)
local b = src:find("local dockWarned", 1, true)
BVD = {}
assert((loadstring or load)(src:sub(a, b - 1)))()
local ok = true
local function check(name, cond, extra) print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  -- " .. extra) or "")); ok = ok and cond end
local function dock(mx, my, mw, mh, pw, ph, sw, sh)
    local x, y, mode = BVD.dockCompanion(mx, my, mw, mh, pw, ph, sw, sh, 8)
    return x, y, mode
end
local x, y, m = dock(400, 150, 800, 600, 280, 240, 1600, 900)
check("1600x900, 800 px window: docks on the right", m == "side" and x == 1208, string.format("%s x=%d y=%d", m, x, y))
x, y, m = dock(300, 150, 800, 600, 280, 240, 1280, 720)
check("1280x720, window too far right: docks on the left", m == "side" and x == 12, string.format("%s x=%d y=%d", m, x, y))
x, y, m = dock(100, 30, 1080, 500, 280, 240, 1280, 900)
check("a wide window with no room at the sides: stacked below it", m == "stacked" and y == 538, string.format("%s x=%d y=%d", m, x, y))
x, y, m = dock(100, 400, 1080, 480, 280, 240, 1280, 900)
check("no room at the sides or below: stacked above it", m == "stacked" and y == 152, string.format("%s x=%d y=%d", m, x, y))
x, y, m = dock(100, 60, 1080, 600, 280, 240, 1280, 720)
check("no free spot at all: pinned to the screen edge instead of hiding", m == "overlap" and x == 1000 and x + 280 <= 1280 and y >= 0, string.format("%s x=%d y=%d", m, x, y))
x, y, m = dock(560, 240, 800, 600, 280, 240, 1920, 1080)
check("1920x1080: docks on the right", m == "side" and x == 1368, string.format("%s x=%d y=%d", m, x, y))
-- whatever the sizes, the result is always fully on screen
local bad = 0
for sw = 800, 2560, 160 do for sh = 600, 1440, 120 do for mw = 300, 1200, 150 do for mh = 200, 700, 125 do
    for mx = 0, math.max(0, sw - mw), 211 do for my = 0, math.max(0, sh - mh), 173 do
        local px, py, pm = dock(mx, my, mw, mh, 280, 240, sw, sh)
        if px < 0 or py < 0 or px + 280 > sw or py + 240 > sh then bad = bad + 1 end
    end end
end end end end
check("over thousands of screen/window layouts the panel is always fully on screen", bad == 0, tostring(bad) .. " off-screen")
os.exit(ok and 0 or 1)
