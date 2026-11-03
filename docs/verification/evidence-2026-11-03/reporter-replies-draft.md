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
Thanks, I tried this with CleanUI and NeatUI Framework: the panel shows beside the mechanics window at 1920x1080 and
above, and it only went missing when the game window was small (about 1280 px wide or less) or a big UI font made the
mechanics window fill the screen. 0.2.2 now moves the panel below/above the window, or pins it to the screen edge,
instead of hiding it. If you still do not see it, please tell me: your game resolution (windowed or fullscreen), the
UI font size in the game options, which UI mods you run, and your CleanUI version.

## Tire marks starting behind the car
Fixed in 0.2.2, thank you. Each wheel kept its last mark and, when you braked, reversed or drifted again, drew a
streak from that old spot to the car. A new skid now starts at the car.
