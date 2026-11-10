-- Pure-function checks, no car and no driving.
-- Ported: Ki5.lua "rules" (the realism rules across the whole range of script force / mass / registration) and the
--   four Wheels.lua slipWearPoints frame-rate checks.
-- NEW coverage, not in the old suite (do not read these as inherited regressions): BVD.skidStreakContinues (the old
--   "skidstreak" test drove the car and measured fills / fresh streaks / first-mark distance, which is not ported) and
--   BVD.dockCompanion (the old "mechanics_narrow" test opened the real panel in a window too small for any side).
local MOD_ID = "BetterVehicleDynamics"

ZomboTest.scenario{
    id = "bvd_pure_logic",
    description = "BVD's realism rules, slip-wear counter, skid-streak rule and panel docking behave across their whole input range.",
    tags = {"bvd", "pure", "realism", "tire-wear", "skidmarks", "ui"},
    modes = {"sp"},
    startAt = {x = 10586, y = 11180, z = 0},

    setup = function(S)
        S.need("BetterVehicleDynamics is active", S.modActive(MOD_ID), MOD_ID)
        S.need("BVD.realismTarget exists", type(BVD.realismTarget) == "function")
        S.need("BVD.slipWearPoints exists", type(BVD.slipWearPoints) == "function")
        S.need("BVD.skidStreakContinues exists", type(BVD.skidStreakContinues) == "function")
        S.need("BVD.dockCompanion exists", type(BVD.dockCompanion) == "function")
    end,

    run = function(S)
        -- ---- realism rules (Ki5 "rules") ----
        local forces = { 1, 400, 1500, 3000, 4000, 6150, 9000, 15000, 40000, 250000 }
        local masses = { 30, 300, 800, 1100, 1700, 2400, 6000, 20000 }
        local specs = { false, { hp = 90 }, { hp = 150, mass_kg = 1200 }, { hp = 700, mass_kg = 1500 }, { hp = 5000, mass_kg = 90000 }, { mass_kg = 900 } }
        local n, bad = 0, {}
        for _, f in ipairs(forces) do
            for _, m in ipairs(masses) do
                for si, spec in ipairs(specs) do
                    spec = spec or nil
                    local force, mass = BVD.realismTarget(f, m, spec)
                    local force2, mass2 = BVD.realismTarget(f, m, spec)   -- same inputs, same outputs (no hidden state)
                    n = n + 1
                    local why
                    if type(force) ~= "number" or force ~= force or force == math.huge then why = "force not a finite number"
                    elseif force < f then why = "weaker than its script"
                    elseif mass ~= nil and (type(mass) ~= "number" or mass ~= mass) then why = "mass not a number"
                    elseif mass ~= nil and mass < m then why = "lighter than its script"
                    elseif mass ~= nil and mass > math.max(1700, m) then why = "above the mass cap"
                    elseif not spec and (mass ~= nil or force ~= f) then why = "unregistered car treated differently"
                    elseif spec and spec.hp and force ~= math.max(spec.hp * 10, f) then why = "registered power is not max(researched, script)"
                    elseif spec and not spec.hp and force ~= f then why = "registered car without hp changed power"
                    elseif force ~= force2 or mass ~= mass2 then why = "not repeatable" end
                    if why and #bad < 8 then bad[#bad + 1] = string.format("f=%s m=%s spec#%d: %s (-> %s, %s)", f, m, si, why, tostring(force), tostring(mass)) end
                end
            end
        end
        S.observe(n .. " combinations of script force, mass and registration checked")
        S.check("realism rules hold for every combination", #bad == 0, table.concat(bad, " | "))
        local f, m = BVD.realismTarget(4000, 1000, nil)
        S.check("an ordinary unregistered car keeps its script force and its mass", f == 4000 and m == nil, tostring(f) .. "/" .. tostring(m))
        f = BVD.realismTarget(15000, 1000, nil)
        S.check("a strong engine's script force is left alone", f == 15000, tostring(f))
        f = BVD.realismTarget(1000, 1000, { hp = 200 })
        S.check("a registered car takes its researched power when that is higher (hp x 10)", f == 2000, tostring(f))
        local _, hm = BVD.realismTarget(4000, 2600, { hp = 200, mass_kg = 1500 })
        S.check("a registered heavy truck is not made lighter", hm == 2600, tostring(hm))

        -- ---- slip-wear counter (Wheels.lua): total points over `seconds` of being stuck, called `fps` times a second ----
        local function simulate(fps, seconds, stuckFor, rate)
            local state, total = { accum = 0 }, 0
            for _ = 1, math.floor(fps * seconds) do
                total = total + BVD.slipWearPoints(state, 1 / fps, stuckFor, rate)
            end
            return total
        end
        local at60, at10, at240 = simulate(60, 60, 10, 1), simulate(10, 60, 10, 1), simulate(240, 60, 10, 1)
        S.check("a minute of slip is about 30 points at any frame rate",
            math.abs(at60 - 30) <= 1 and math.abs(at10 - 30) <= 1 and math.abs(at240 - 30) <= 1,
            string.format("10 fps %d, 60 fps %d, 240 fps %d", at10, at60, at240))
        S.check("nothing counts before the dwell", simulate(60, 10, 1.9, 1) == 0)
        S.check("rate 2 doubles it", math.abs(simulate(60, 60, 10, 2) - 60) <= 1)
        S.check("rate 0 is off", simulate(60, 60, 10, 0) == 0)

        -- ---- skid-streak rule (Ki5 "skidstreak", rule half) ----
        local now = 100000
        S.check("a mark 100 ms after the last continues the streak", BVD.skidStreakContinues({ ts = now - 100, z = 0 }, now, 0) == true)
        S.check("a mark 2 s after the last starts a new streak", BVD.skidStreakContinues({ ts = now - 2000, z = 0 }, now, 0) == false)
        S.check("the first mark ever starts a streak", BVD.skidStreakContinues(nil, now, 0) == false)
        S.check("a mark on another floor level starts a new streak", BVD.skidStreakContinues({ ts = now - 100, z = 0 }, now, 1) == false)

        -- ---- panel docking (Ki5 "mechanics_narrow", geometry half) ----
        local bad2, cases = {}, 0
        local screens = { {1920, 1080}, {1280, 720}, {800, 600} }
        local wins = { {0, 0, 300, 400}, {600, 200, 400, 500}, {1500, 100, 400, 600}, {0, 0, 780, 560}, {100, 50, 1100, 600}, {350, 80, 1500, 900} }
        local PW, PH, GAP = 260, 320, 8
        for _, sc in ipairs(screens) do
            for _, w in ipairs(wins) do
                local sw, sh = sc[1], sc[2]
                local mx, my, mw, mh = w[1], w[2], math.min(w[3], sw), math.min(w[4], sh)
                if mx + mw > sw then mx = sw - mw end
                if my + mh > sh then my = sh - mh end
                local x, y, mode = BVD.dockCompanion(mx, my, mw, mh, PW, PH, sw, sh, GAP)
                cases = cases + 1
                local onScreen = x >= 0 and y >= 0 and x + PW <= sw and y + PH <= sh
                local clear = x + PW <= mx or x >= mx + mw or y + PH <= my or y >= my + mh
                if not onScreen then bad2[#bad2 + 1] = string.format("%dx%d win %d,%d %dx%d: panel off screen at %d,%d (%s)", sw, sh, mx, my, mw, mh, x, y, tostring(mode)) end
                if mode ~= "overlap" and not clear then bad2[#bad2 + 1] = string.format("%dx%d win %d,%d %dx%d: %s panel overlaps the window at %d,%d", sw, sh, mx, my, mw, mh, tostring(mode), x, y) end
            end
        end
        S.observe(cases .. " window / screen combinations docked")
        S.check("the panel is always fully on screen, and clear of the window unless nothing fits", #bad2 == 0, table.concat(bad2, " | "))
        local x1, _, m1 = BVD.dockCompanion(100, 100, 400, 400, PW, PH, 1920, 1080, GAP)
        S.check("with room on the right the panel goes beside the window", m1 == "side" and x1 == 100 + 400 + GAP, tostring(m1) .. " x " .. tostring(x1))
        local _, _, m2 = BVD.dockCompanion(0, 0, 1900, 1060, PW, PH, 1920, 1080, GAP)
        S.check("a window filling the screen still gets a panel (overlap fallback)", m2 == "overlap", tostring(m2))
    end,
}
