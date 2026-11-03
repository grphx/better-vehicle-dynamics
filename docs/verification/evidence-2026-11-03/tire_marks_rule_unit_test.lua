Events = setmetatable({}, { __index = function() return { Add = function() end } end })
getTimestampMs = function() return 0 end
dofile("/home/grphx/zomboid/better-vehicle-dynamics/workshop/BetterVehicleDynamics/42.20/media/lua/client/BVD_Skidmarks.lua")
local f = BVD.skidStreakContinues
local ok = true
local function check(name, cond) print((cond and "PASS " or "FAIL ") .. name); ok = ok and cond end
check("no previous drop starts a fresh streak", f(nil, 1000, 0) == false)
check("a drop 50 ms ago continues the streak", f({ ts = 950, z = 0 }, 1000, 0) == true)
check("a drop 300 ms ago still continues (a frame hitch)", f({ ts = 700, z = 0 }, 1000, 0) == true)
check("a drop 400 ms ago is an earlier skid", f({ ts = 600, z = 0 }, 1000, 0) == false)
check("a drop from 5 s ago (the reported bug) is an earlier skid", f({ ts = -4000, z = 0 }, 1000, 0) == false)
check("a drop on another level starts fresh", f({ ts = 950, z = 1 }, 1000, 0) == false)
os.exit(ok and 0 or 1)
