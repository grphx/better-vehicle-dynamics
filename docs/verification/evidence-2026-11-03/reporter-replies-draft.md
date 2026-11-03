# Drafts for the Workshop commenters (not posted)

## Fast modded cars (reference power and weight)
Thanks for reporting this, it was a real bug. Cars that were spawned while 0.1.19 to 0.2.0 were installed already had
the boost saved into them, and 0.2.1 added it again, so those cars got it twice. That is fixed in 0.2.2. I also added
an "Acceleration ceiling" option (Drivetrain page) that caps how hard any car can launch, modded or not: I can
reproduce a modded car with a big engine force doing 0-100 km/h in about 3 seconds on the Casual-style grip settings,
and with the ceiling it no longer does. If a car still feels too fast, open its mechanics window: the info panel now
shows "Engine force" and "Launch limit". Tell me those two numbers, the car, and your Tire grip / Engine power sliders,
and I can look at exactly what it is doing.

## Info panel missing with CleanUI
Thanks for reporting this. There turned out to be a real bug, fixed in 0.2.3: "Clean UI 2.0 - Rax's Reborn" opens its
own Vehicle Mechanics window, and BVD's panel only attached to the vanilla one, so it never showed there. It does now
(I checked it in game, same window before and after). Rocco's CleanUI itself worked for me, and in a small game window
(about 1280 px wide or less, or a 1366x768 screen with the biggest UI font) the panel used to hide itself, which 0.2.2
fixed. Which Clean UI do you use (the Workshop name or ID), and what is your game resolution? If it still does not show
after updating to 0.2.3, tell me those two things and your other UI mods and I will look at it.

## Tire marks starting behind the car
Fixed in 0.2.2, thank you. Each wheel kept its last mark and, when you braked, reversed or drifted again, drew a
streak from that old spot to the car. A new skid now starts at the car.
