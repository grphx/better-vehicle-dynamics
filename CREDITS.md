# Credits

Better Vehicle Dynamics is written and maintained by grphx. It is an
independent work — including its Lua and its Necroid Java patches —
and is **not affiliated with, endorsed by, or derived from** "Realistic
Car Physics" (Black Moons) or any other vehicle mod.

The vehicle power/weight reference figures in
`media/lua/shared/BVD_VehicleData.lua` are researched and chosen by the
author, with sources cited inline (primarily manufacturer/Wikipedia
specifications). The driving behaviour aims to feel comparable to other
realism-focused vehicle mods — behaviour and game mechanics are not
copyrightable; only this project's own code and text are shipped here.

## Sound assets

The mod ships exactly one audio file: a tyre-slide loop used by the
sustained-skid sound. It is not a recording. It is synthesised entirely
from first principles -- band-limited noise plus a faint tonal partial
plus a slow amplitude envelope -- by the deterministic generator
`tools/gen_skid_loop.py`, which is committed in this repository and is
the sole source of the clip. Anyone can regenerate the byte-equivalent
file by running that script. Engine sounds use the game's own built-in
sound events, played through the normal engine path. There is no
sampled, recorded, or third-party audio of any kind in this mod, and
nothing here derives from any other vehicle mod's audio or sound
scripts -- only this project's own code and synthesised content are
shipped.
