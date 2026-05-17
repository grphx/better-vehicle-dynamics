#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# make_skid_sample.sh
#
# Deterministically carves a tight tyre-squeal clip out of a CC0 / public-domain
# Freesound recording and writes it as the on-road skid sound:
#
#     workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid.ogg
#
# This REPLACES the previously-synthesised on-road clip. The off-road clip
# (BVD_skid_offroad.ogg) and its synth generator (tools/gen_skid_audio.py)
# are deliberately left untouched.
#
# Window selection is NOT blind: an RMS sweep of the source (see commit
# notes / project log) showed the loudest sustained squeal sits in the
# ~6.0 .. ~7.4 s region. We take a fixed 1.40 s slice starting at 6.00 s
# (verified RMS ~= -17.8 dBFS, i.e. firmly inside the loud squeal, not the
# quiet head/tail of the recording). The slice is then:
#   * downmixed/kept mono, resampled to 44100 Hz
#   * loudness-normalised so the true peak sits near -1 dBFS
#   * given ~30 ms fades in and out so rapid re-triggers don't click
#   * encoded with libvorbis at ~q4
#
# Re-runnable: same source + same ffmpeg => byte-stable intent (the OGG is
# committed alongside this script).
#
# Usage:
#     tools/make_skid_sample.sh
# -----------------------------------------------------------------------------
set -euo pipefail

FFMPEG="/home/grphx/.local/lib/python3.12/site-packages/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2"
SRC="/mnt/c/Users/Grphx/Downloads/freesound_community-chrysler-lhs-tire-squeal-03-04-25-2009-7154.mp3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_ROOT/workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid.ogg"

# --- selected window (see header note; chosen by RMS sweep, not blindly) -----
START=6.00      # seconds into the source: start of the loud sustained squeal
DUR=1.40        # seconds: clip length (1.2 .. 1.6 s target band)
SR=44100        # output sample rate
FADE=0.030      # 30 ms fade in / out to kill re-trigger clicks

[ -x "$FFMPEG" ] || { echo "ffmpeg not found/executable: $FFMPEG" >&2; exit 2; }
[ -f "$SRC" ]    || { echo "source asset not found: $SRC" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

# fade-out start = clip duration minus the fade length
FADE_OUT_START="$(awk -v d="$DUR" -v f="$FADE" 'BEGIN{printf "%.3f", d - f}')"

# Single pass:
#   atrim/asetpts  -> isolate the chosen window cleanly
#   aresample      -> mono / 44100 Hz
#   afade          -> in + out de-click ramps
#   loudnorm-ish   -> peak-normalise to ~ -1 dBFS (alimiter target + dynaudnorm
#                     would drift; a fixed loudnorm here keeps it deterministic)
"$FFMPEG" -hide_banner -y -ss "$START" -t "$DUR" -i "$SRC" \
  -ac 1 -ar "$SR" \
  -af "afade=t=in:st=0:d=${FADE},afade=t=out:st=${FADE_OUT_START}:d=${FADE},loudnorm=I=-16:TP=-1.0:LRA=11" \
  -c:a libvorbis -q:a 4 \
  "$OUT"

echo "wrote: $OUT"
ls -la "$OUT"
