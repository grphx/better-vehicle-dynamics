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

Every sound shipped with this mod is wholly original. Both tyre-squeal
clips — the on-road `media/sound/BVD_skid.ogg` and the off-road
`media/sound/BVD_skid_offroad.ogg` — are synthesised from scratch by the
committed generator `tools/gen_skid_audio.py`: a deterministic numpy
build of a warbling stick-slip squeal tone over band-passed rubber-scrub
noise, resonant formants and a low contact body, finished with light
saturation, a high-shelf trim and a sample-exact equal-power loop
crossfade, then Vorbis-encoded. No sampled, recorded, or third-party
audio is used anywhere in the mod — there is none to attribute.
