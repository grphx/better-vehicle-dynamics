-- BVD_VehicleData: per-vehicle real-world reference values.
--
-- Each entry maps a Project Zomboid vehicle script name to a chosen
-- real-world counterpart and that counterpart's published specs:
--   hp       — manufacturer-rated horsepower
--   mass_kg  — published curb weight in kilograms
--   cargo    — BVD-suggested cargo capacity in PZ inventory units
--
-- Sources are noted per-entry. Where multiple real-world cars could
-- match a PZ silhouette, I picked one based on personal visual judgement
-- and stuck with it — these mappings are my own editorial choices and
-- may differ from any other mod's table.
--
-- Vehicles not in this table are simply not touched by HP/Weight
-- Overhaul. Modded vehicles can register their own data via
-- BVD.registerVehicle(scriptName, data).

local M = {}

-- Helper: re-use a single spec across smashed/burnt/livery variants.
local function dup(spec) return { hp = spec.hp, mass_kg = spec.mass_kg, cargo = spec.cargo } end

-- ============================================================================
-- Vanilla PZ vehicles
-- ============================================================================

-- "Chevalier Cossette" (CarLuxury) — sized like a late-90s American luxury
-- sedan. Picked: Lincoln Town Car (1998–2002, Panther platform).
-- Ref: en.wikipedia.org/wiki/Lincoln_Town_Car (4.6L Modular V8, 220hp,
-- curb ~1860kg).
M["Base.CarLuxury"] = { hp = 220, mass_kg = 1860, cargo = 220 }

-- "Chevalier Cerise Wagon" (CarStationWagon) — full-size 1990s American
-- station wagon. Picked: Buick Roadmaster Estate (1992–96).
-- Ref: en.wikipedia.org/wiki/Buick_Roadmaster (5.7L LT1, 260hp, ~2055kg).
M["Base.CarStationWagon"]  = { hp = 260, mass_kg = 2055, cargo = 480 }
M["Base.CarStationWagon2"] = { hp = 260, mass_kg = 2055, cargo = 480 }

-- "Chevalier Nyala" (ModernCar) — newer mid-size sedan silhouette.
-- Picked: Toyota Camry XV40 (2006–11).
-- Ref: en.wikipedia.org/wiki/Toyota_Camry_(XV40) (2.4L I4, 158hp, ~1500kg).
M["Base.ModernCar"]  = { hp = 158, mass_kg = 1500, cargo = 230 }
M["Base.ModernCar02"] = { hp = 158, mass_kg = 1500, cargo = 230 }

-- "Dash Rancher" (CarNormal) — generic American mid-size sedan.
-- Picked: Ford Taurus first-gen (1986–91).
-- Ref: en.wikipedia.org/wiki/Ford_Taurus_(first_generation) (3.0L Vulcan
-- V6, 140hp, ~1480kg).
M["Base.CarNormal"] = { hp = 140, mass_kg = 1480, cargo = 240 }

-- "Dash Elite" (CarSmall) — compact 1990s economy hatchback / small sedan.
-- Picked: Geo Metro 3-cyl (1989–94).
-- Ref: en.wikipedia.org/wiki/Geo_Metro (1.0L I3, 55hp, ~735kg).
M["Base.CarSmall"] = { hp = 55, mass_kg = 735, cargo = 110 }

-- "Chevalier D6 Taxi" (CarTaxi) — body-on-frame fleet sedan.
-- Picked: Ford Crown Victoria P71 (1998 Police Interceptor era).
-- Ref: en.wikipedia.org/wiki/Ford_Crown_Victoria_Police_Interceptor
-- (4.6L V8, 210hp, ~1840kg).
M["Base.CarTaxi"]  = { hp = 210, mass_kg = 1840, cargo = 230 }
M["Base.CarTaxi2"] = { hp = 210, mass_kg = 1840, cargo = 230 }

-- "Step Van" (StepVan) — multi-stop walk-in delivery truck.
-- Picked: Chevrolet P30 / Grumman Olson chassis (mid-1990s box-van era).
-- Ref: en.wikipedia.org/wiki/Chevrolet_P30 (5.7L V8 TBI, ~190hp, GVW
-- around 4500kg, curb ~2900kg).
M["Base.StepVan"] = { hp = 190, mass_kg = 2900, cargo = 1500 }

-- "Chevalier D6" (PickUpTruck) — full-size half-ton American pickup,
-- 90s vintage. Picked: Ford F-150 ninth-gen.
-- Ref: en.wikipedia.org/wiki/Ford_F-Series_(ninth_generation) (4.9L I6,
-- 150hp, ~1900kg).
M["Base.PickUpTruck"] = { hp = 150, mass_kg = 1900, cargo = 720 }

-- "PickUpVan" (full-size family/passenger van).
-- Picked: Ford E-150 Econoline (1992–96).
-- Ref: en.wikipedia.org/wiki/Ford_E-Series (4.9L I6, 145hp, ~2400kg).
M["Base.PickUpVan"] = { hp = 145, mass_kg = 2400, cargo = 870 }

-- "Mass-market van" (Van + variants) — full-size cargo van.
-- Picked: Chevrolet Express (1996+).
-- Ref: en.wikipedia.org/wiki/Chevrolet_Express (5.0L V8, 200hp, ~2380kg).
M["Base.Van"]      = { hp = 200, mass_kg = 2380, cargo = 900 }
M["Base.VanSpiffo"] = { hp = 200, mass_kg = 2380, cargo = 900 }

-- "Off-Road" (OffRoad) — body-on-frame SUV / Jeep silhouette.
-- Picked: Jeep Wrangler YJ (1987–95).
-- Ref: en.wikipedia.org/wiki/Jeep_Wrangler#YJ (4.2L AMC I6, 112hp,
-- ~1450kg).
M["Base.OffRoad"] = { hp = 112, mass_kg = 1450, cargo = 280 }

-- ============================================================================
-- Smashed / Burnt / Police / Variant livery passthrough
-- Each variant uses the same spec as its base since they share scripts.
-- ============================================================================
M["Base.CarLuxurySmashedFront"]       = dup(M["Base.CarLuxury"])
M["Base.CarLuxurySmashedLeft"]        = dup(M["Base.CarLuxury"])
M["Base.CarLuxurySmashedRear"]        = dup(M["Base.CarLuxury"])
M["Base.CarLuxurySmashedRight"]       = dup(M["Base.CarLuxury"])
M["Base.LuxuryCarBurnt"]              = dup(M["Base.CarLuxury"])

M["Base.CarStationWagonSmashedFront"] = dup(M["Base.CarStationWagon"])
M["Base.CarStationWagonSmashedLeft"]  = dup(M["Base.CarStationWagon"])
M["Base.CarStationWagonSmashedRear"]  = dup(M["Base.CarStationWagon"])
M["Base.CarStationWagonSmashedRight"] = dup(M["Base.CarStationWagon"])

M["Base.CarNormalSmashedFront"]       = dup(M["Base.CarNormal"])
M["Base.CarNormalSmashedLeft"]        = dup(M["Base.CarNormal"])
M["Base.CarNormalSmashedRear"]        = dup(M["Base.CarNormal"])
M["Base.CarNormalSmashedRight"]       = dup(M["Base.CarNormal"])
M["Base.CarNormalBurnt"]              = dup(M["Base.CarNormal"])
M["Base.NormalCarBurntPolice"]        = dup(M["Base.CarNormal"])

M["Base.CarSmallSmashedFront"]        = dup(M["Base.CarSmall"])
M["Base.CarSmallSmashedLeft"]         = dup(M["Base.CarSmall"])
M["Base.CarSmallSmashedRear"]         = dup(M["Base.CarSmall"])
M["Base.CarSmallSmashedRight"]        = dup(M["Base.CarSmall"])

M["Base.ModernCarSmashedFront"]       = dup(M["Base.ModernCar"])
M["Base.ModernCarSmashedLeft"]        = dup(M["Base.ModernCar"])
M["Base.ModernCarSmashedRear"]        = dup(M["Base.ModernCar"])
M["Base.ModernCarSmashedRight"]       = dup(M["Base.ModernCar"])
M["Base.ModernCarBurnt"]              = dup(M["Base.ModernCar"])

M["Base.OffRoadSmashedFront"]         = dup(M["Base.OffRoad"])
M["Base.OffRoadSmashedLeft"]          = dup(M["Base.OffRoad"])
M["Base.OffRoadSmashedRear"]          = dup(M["Base.OffRoad"])
M["Base.OffRoadSmashedRight"]         = dup(M["Base.OffRoad"])
M["Base.OffRoadBurnt"]                = dup(M["Base.OffRoad"])

M["Base.PickUpTruckSmashedFront"]     = dup(M["Base.PickUpTruck"])
M["Base.PickUpTruckSmashedLeft"]      = dup(M["Base.PickUpTruck"])
M["Base.PickUpTruckSmashedRear"]      = dup(M["Base.PickUpTruck"])
M["Base.PickUpTruckSmashedRight"]     = dup(M["Base.PickUpTruck"])

return M
