#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# make_skid_sample.sh
#
# Deterministically carves a tight, SEAMLESSLY-LOOPING tyre-squeal clip out of
# a CC0 / public-domain Freesound recording and writes it as the on-road skid
# sound:
#
#     workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid.ogg
#
# This REPLACES the previously-synthesised on-road clip. The off-road clip
# (BVD_skid_offroad.ogg) and its synth generator (tools/gen_skid_audio.py)
# are deliberately left untouched.
#
# -- Window selection (objective, not blind) ----------------------------------
# A numpy pass over the decoded WAV (25-30 ms frames, 5 ms hop) measured, for
# every candidate window, the std-dev of frame RMS (loudness flatness) and the
# std-dev of the spectral centroid (timbre flatness), restricted to windows
# louder than the file mean. The flattest sustained-squeal region converged
# firmly on START = 6.42 s, L = 2.00 s:
#     rms = -25.2 +/- 4.6 dB    spectral centroid = 1875 +/- 188 Hz
# i.e. the most stable loudness AND the most stable timbre in the recording.
# The earlier 1.40 s @ 6.00 s slice straddled the loud attack at ~6.1 s and a
# dip toward 7.0 s, so it was not steady-state -- that, plus a cooldown
# shorter than the clip (it restacked on itself), is what sounded "weird".
#
# The residual +/-4.6 dB RMS swing is inherent to a real tyre squeal (the
# whole recording pulses by ~10 dB everywhere); a gentle compressor evens it
# so the loop reads as one continuous slide rather than a pulsing sample.
#
# -- Processing chain ---------------------------------------------------------
#   atrim/asetpts   isolate the chosen window cleanly
#   aresample       mono / 44100 Hz
#   acompressor     gentle 3:1 above -26 dB -> tames the inherent ~10 dB
#                   pulsing so back-to-back loops sound continuous
#   highshelf       mild -3 dB shelf above 6.5 kHz: the source has only
#                   0.12% energy >6 kHz so this is a light de-harsh / hiss
#                   tamer on rapid retrigger, NOT a heavy filter (no narrow
#                   notch is needed: the squeal is broadband around a 1 kHz
#                   fundamental with no single pathological resonant whistle)
#   loop-xfade      EQUAL-POWER cos/sin crossfade of the clip's own tail into
#                   its head over XF seconds, done in numpy (deterministic,
#                   sample-exact -- ffmpeg's acrossfade mis-truncates when
#                   both legs come from one file) -> the file is internally
#                   loop-seamless: when PlayWorldSound re-fires it back to
#                   back there is no click and no gap. fall^2+rise^2=1 so
#                   the squeal energy is constant across the splice.
#   loudnorm        RMS/integrated-loudness normalise (I=-17, TP=-2.0): a
#                   controlled level, NOT a peak slam to -1 dBFS (the old
#                   slam made the screech harsh)
#
# Loop math the Lua relies on: the emitted clip is (L - XF) seconds long
# because acrossfade overlaps the tail XF onto the head and discards the
# overlapped material. CLIP_LEN_MS below is that final length and is the
# number BVD_Skidmarks.lua's SOUND_COOLDOWN_MS is tied to.
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

# --- selected window (objective: flattest loud RMS + centroid; see header) ---
START=6.42      # seconds into source: start of the flattest sustained squeal
DUR=2.00        # seconds: raw window length (2.0 .. 2.6 s target band)
XF=0.20         # seconds: equal-power tail->head crossfade (150 .. 250 ms)
SR=44100        # output sample rate

# Final emitted clip length = DUR - XF (acrossfade consumes the overlap).
# This MUST stay in sync with SOUND_COOLDOWN_MS in BVD_Skidmarks.lua.
CLIP_LEN_MS="$(awk -v d="$DUR" -v x="$XF" 'BEGIN{printf "%d", (d - x)*1000}')"

[ -x "$FFMPEG" ] || { echo "ffmpeg not found/executable: $FFMPEG" >&2; exit 2; }
[ -f "$SRC" ]    || { echo "source asset not found: $SRC" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

# Pass 1: tame + shape the raw window into a clean mono stem.
STEM="$(mktemp --suffix=.wav)"
LOOP="$(mktemp --suffix=.wav)"
trap 'rm -f "$STEM" "$LOOP"' EXIT
"$FFMPEG" -hide_banner -y -ss "$START" -t "$DUR" -i "$SRC" \
  -ac 1 -ar "$SR" \
  -af "acompressor=threshold=-26dB:ratio=3:attack=15:release=180:makeup=3,highshelf=f=6500:g=-3,loudnorm=I=-17:TP=-2.0:LRA=11" \
  -c:a pcm_s16le "$STEM"

# Pass 2: equal-power loop crossfade in numpy. ffmpeg's acrossfade
# mis-truncates when both legs are slices of one file, so we do the
# splice sample-exactly here: the first XF seconds of the output is the
# faded tail (cos) summed with the faded-in head (sin); cos^2+sin^2=1 so
# squeal energy is constant across the seam. Output length = DUR - XF and
# the file is loop-seamless for back-to-back PlayWorldSound retriggers.
python3 - "$STEM" "$LOOP" "$XF" << 'PY'
import sys, wave, numpy as np
stem, out, xf_s = sys.argv[1], sys.argv[2], float(sys.argv[3])
w = wave.open(stem, 'rb'); sr = w.getframerate(); n = w.getnframes()
x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768.0
w.close()
xf = int(round(xf_s * sr))
if xf < 1 or xf * 2 >= n:
    raise SystemExit("crossfade length out of range for stem")
t   = np.linspace(0.0, np.pi / 2.0, xf, endpoint=True)
fall, rise = np.cos(t), np.sin(t)           # equal-power: fall^2+rise^2=1
body = x[:n - xf].copy()
body[:xf] = x[n - xf:] * fall + x[:xf] * rise
o = np.clip(np.round(body * 32767.0), -32768, 32767).astype(np.int16)
ow = wave.open(out, 'wb')
ow.setnchannels(1); ow.setsampwidth(2); ow.setframerate(sr)
ow.writeframes(o.tobytes()); ow.close()
PY

# Pass 3: encode the loop-seamless stem to Vorbis q5 mono 44.1k.
"$FFMPEG" -hide_banner -y -i "$LOOP" \
  -ac 1 -ar "$SR" -c:a libvorbis -q:a 5 \
  "$OUT"

echo "wrote: $OUT  (final clip length ~= ${CLIP_LEN_MS} ms = DUR-XF)"
ls -la "$OUT"
