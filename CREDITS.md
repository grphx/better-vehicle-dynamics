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

The on-road tyre-squeal clip (`media/sound/BVD_skid.ogg`) is a short,
trimmed and loudness-normalised excerpt of a recording sourced from
Freesound's community / public-domain pool. The original file —
`freesound_community-chrysler-lhs-tire-squeal-03-04-25-2009-7154.mp3` —
was released under the Creative Commons Zero (CC0 1.0) public-domain
dedication. Under CC0 the author has waived all rights to the extent
allowed by law, so no attribution is legally required; it is credited
here purely as good practice and out of respect for the original
recordist. The processing (steady-state windowing, mono/44.1 kHz
resample, gentle compression, a mild high-shelf, an equal-power loop
crossfade, loudness normalisation, Vorbis encode) is performed by the
committed helper `tools/make_skid_sample.sh`.

The off-road tyre-squeal clip (`media/sound/BVD_skid_offroad.ogg`) is
not sampled at all — it is synthesised from scratch by
`tools/gen_skid_audio.py` and is therefore wholly original.
