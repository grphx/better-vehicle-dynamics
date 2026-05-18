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

The mod ships exactly one audio file: a short tyre-slide loop used by the
sustained-skid sound. It is a trimmed, loop-tuned excerpt of a public-domain
tyre-slide recording released under Creative Commons Zero (CC0) and obtained
from Freesound (original file:
`freesound_community-chrysler-lhs-tire-squeal-03-04-25-2009-7154.mp3`).
CC0 is a full dedication to the public domain, so no attribution is legally
required; the source is nonetheless credited here as good practice and out
of respect for the recordist who shared it.

All processing is performed by the committed helper
`tools/make_skid_loop.sh`, which is the sole producer of the shipped clip:
it applies real spectral noise reduction to remove the recording's
broadband floor, objectively selects the most tonal tyre-squeal window of
the source, reduces it to mono at 44100 Hz, builds a seamless loop with an
equal-power wrap crossfade, applies a light low-end roll-off and gentle
high-shelf trim, normalises the level to a quiet background layer, and
encodes to Vorbis. The result is fully reproducible from the same source
file by running that one script.

Engine sounds use the game's own built-in sound events, played through the
normal engine path. No audio, samples, or sound scripts from "Realistic
Car Physics", from any other vehicle mod, or from any third party other
than the CC0 Freesound recording named above are used here or derived
from -- only this project's own code, the CC0 excerpt, and the processing
defined in this repository are shipped.
