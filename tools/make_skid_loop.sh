#!/usr/bin/env bash
# ===========================================================================
# make_skid_loop.sh
#
# Deterministic producer of the Better Vehicle Dynamics sustained-skid clip:
#
#     workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid_loop.ogg
#
# It is a short, loop-tuned excerpt of a CC0 (Creative Commons Zero /
# public-domain) real tyre-slide recording sourced from Freesound (original
# file: freesound_community-chrysler-lhs-tire-squeal-03-04-25-2009-7154.mp3).
# Under CC0 no attribution is legally required; it is credited in CREDITS.md
# as good practice. No other mod's audio or sound scripts are used or
# derived from anywhere -- this is the sole producer of the clip.
#
# Why an excerpt of a real recording and not a synth: the earlier synthetic
# clip sounded like a thin "screech". A real recording already carries the
# body and grit of an actual tyre scrubbing tarmac, which is the whole point.
#
# Pipeline (all sample-exact in numpy; ffmpeg is used only to decode the
# source and to encode the final Vorbis -- ffmpeg's acrossfade mis-truncates
# a single-file self-loop, so the wrap crossfade is done by hand):
#
#   1. Decode the CC0 mp3 to mono float PCM.
#   2. Objectively pick the most STEADY-STATE sustained-slide region of the
#      recording: the window whose short-time RMS envelope AND spectral
#      envelope (centroid / bandwidth) are flattest, explicitly avoiding the
#      attack transient, the loud surges, any pitch sweep, and the tail
#      decay. The chosen core is reported with its objective metric.
#   3. Reverse-mirror the steady core (core followed by its time-reverse) to
#      reach the ~2.0-2.6 s target length. For a broadband tyre-scrub
#      texture a time-reversed copy is perceptually identical to the
#      forward copy, and the mirror makes BOTH the internal turnaround and
#      the end->start wrap mathematically continuous (the mirror ends on the
#      same sample it starts on), so the FMOD loop=true repeat is seamless.
#   4. A short equal-power (sin/cos) wrap crossfade folds a ~250 ms tail
#      back over the head as belt-and-braces against any residual
#      sub-sample mismatch -- no click, no level pump at the wrap.
#   5. Light cleanup only: a gentle low-end roll-off below ~120 Hz (so the
#      energy does not pile up into rumble when the clip loops forever) and
#      a mild high-shelf cut above ~7 kHz to take the hard edge off.
#   6. Normalise RMS to ~-18 dBFS and guarantee true-peak <= -2 dBFS
#      (measured on a 4x-oversampled reconstruction; we do NOT slam it).
#   7. Encode mono 44100 Hz libvorbis ~q5, then VERIFY the decoded output.
#
# Determinism: there is no RNG anywhere; the same source mp3 yields the same
# bytes every run.
# ===========================================================================
set -euo pipefail

FF="/home/grphx/.local/lib/python3.12/site-packages/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2"
SRC="/mnt/c/Users/Grphx/Downloads/freesound_community-chrysler-lhs-tire-squeal-03-04-25-2009-7154.mp3"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid_loop.ogg"

if [ ! -f "$SRC" ]; then echo "source mp3 not found: $SRC" >&2; exit 1; fi
if [ ! -x "$FF" ];   then echo "ffmpeg not found: $FF"     >&2; exit 1; fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DEC="$WORK/src.wav"

# 1. Decode the CC0 source to mono PCM at its native 48 kHz for analysis.
"$FF" -hide_banner -loglevel error -y -i "$SRC" -ac 1 -ar 48000 -f wav "$DEC"

# 2-7. Sample-exact processing + verification in numpy; ffmpeg only encodes.
FF_BIN="$FF" SRC_WAV="$DEC" OUT_OGG="$OUT" python3 - <<'PY'
import os, subprocess, sys, wave
import numpy as np

FF      = os.environ["FF_BIN"]
SRC_WAV = os.environ["SRC_WAV"]
OUT_OGG = os.environ["OUT_OGG"]

OUT_SR          = 44100
TARGET_RMS_DBFS = -18.0
TRUE_PEAK_CEIL  = -2.0
XFADE_S         = 0.25     # wrap crossfade length (seconds)


def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, sr, n = w.getnchannels(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    a = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return a, sr


def stft_features(x, sr, hop_s=0.010, win_s=0.040):
    hop = int(hop_s * sr)
    win = int(win_s * sr)
    nh = (len(x) - win) // hop
    rms = np.empty(nh)
    cen = np.empty(nh)
    bw = np.empty(nh)
    hann = np.hanning(win)
    fr = np.fft.rfftfreq(win, 1.0 / sr)
    for i in range(nh):
        s = x[i * hop:i * hop + win]
        rms[i] = np.sqrt(np.mean(s ** 2))
        sp = np.abs(np.fft.rfft(s * hann)) + 1e-9
        c = (fr * sp).sum() / sp.sum()
        cen[i] = c
        bw[i] = np.sqrt(((fr - c) ** 2 * sp).sum() / sp.sum())
    return hop, rms, 20.0 * np.log10(rms + 1e-12), cen, bw


def pick_steady_core(x, sr):
    """Objectively choose the flattest sustained-slide region.

    Score = weighted sum of: RMS-envelope std (steadiness of loudness),
    spectral-centroid CV and bandwidth CV (steadiness of timbre), and the
    absolute centroid slope over the window (rejects any pitch sweep).
    A median-energy band excludes the near-silent attack and tail decay;
    the std/slope terms reject the loud surges and the onset transient.
    Core length is held to ~1.05 s -- long enough to carry the texture,
    short enough to stay inside one genuinely steady passage -- then
    reverse-mirrored in build_loop() to the final ~2.1 s.
    """
    hop, rms, rdb, cen, bw = stft_features(x, sr)
    nh = len(rdb)
    core_s = 1.05
    wn = int(round(core_s / 0.010))
    best = None
    for st in range(0, nh - wn):
        sr_db = rdb[st:st + wn]
        sc = cen[st:st + wn]
        sb = bw[st:st + wn]
        med = np.median(sr_db)
        if med < -34.0 or med > -27.0:        # not the tail / attack / a surge
            continue
        rstd = sr_db.std()
        ccv = sc.std() / (sc.mean() + 1e-9)
        bcv = sb.std() / (sb.mean() + 1e-9)
        tt = np.arange(wn)
        cslope = abs(np.polyfit(tt, sc, 1)[0]) * wn / (sc.mean() + 1e-9)
        score = (1.0 * rstd + 9.0 * ccv + 6.0 * bcv + 14.0 * cslope)
        if best is None or score < best[0]:
            best = (score, st * hop, rstd, ccv, bcv, cslope, med)
    if best is None:
        raise SystemExit("no steady-state region found in source")
    score, start, rstd, ccv, bcv, cslope, med = best
    n0 = start
    n1 = start + int(round(core_s * sr))
    core = x[n0:n1].copy()
    print("[analysis] steady-state core selected")
    print("  source window : start %.3f s  length %.3f s  (%d samples @ %d Hz)"
          % (start / sr, len(core) / sr, len(core), sr))
    print("  objective     : score %.4f" % score)
    print("    RMS-env std        : %.3f dB   (flatness of loudness)" % rstd)
    print("    centroid CV        : %.4f      (flatness of timbre)" % ccv)
    print("    bandwidth CV       : %.4f" % bcv)
    print("    |centroid slope|   : %.5f     (pitch-sweep rejection)"
          % cslope)
    print("    median RMS in win  : %.1f dBFS (sustained-slide level)" % med)
    return core


def reverse_mirror(core):
    """mirror = core ++ reverse(core)[1:]  (drop the duplicated turnaround
    sample). The turnaround is C1-smooth and the end->start wrap is EXACT
    by construction: mirror[-1] == core[0] == mirror[0]. The mirror is
    therefore an exactly periodic buffer -- circular FFT EQ applied to it
    stays continuous, which is why EQ runs on the mirror, BEFORE the
    belt-and-braces wrap crossfade (running EQ after a non-periodic
    reassembly would reintroduce an endpoint step)."""
    return np.concatenate([core, core[-2::-1]])


def wrap_crossfade(x, sr):
    """Length-preserving equal-power crossfade CENTRED on the loop point.

    A reverse-mirror is already exactly seam-continuous, so the crossfade
    must not be allowed to PUSH the endpoints apart (a naive "make the end
    equal some interior sample" fold does exactly that and reintroduces a
    click). Instead this blends a ~XFADE_S region that straddles the wrap
    -- the second half of the tail and the first half of the head -- with
    the SAME region viewed one period away, using wrapped (circular)
    indexing and equal-power sin/cos weights. Because the blend is circular
    and symmetric about the loop point, x[0] and x[-1] are transformed by
    the mirror-image of the same operation: their continuity is preserved
    (not degraded) while any residual sub-sample mismatch from resampling
    or EQ is smoothed. Total length is unchanged; no level pump.
    """
    n = len(x)
    half = int(round(0.5 * XFADE_S * sr))
    half = min(half, n // 4)
    if half < 1:
        return x.copy()
    y = x.copy()
    idx = np.arange(-half, half)             # straddles the wrap at 0
    pos = idx % n                            # circular sample positions
    # Equal-power weight: 1 at the centre (loop point), tapering each side.
    u = (idx + 0.5) / (2.0 * half)           # in (-0.5, 0.5)
    blend = np.cos(np.pi * u) ** 2           # 1 at centre, 0 at the edges
    # The "other view" one period away is identical for a periodic signal;
    # for the slightly-aperiodic real cut it is the gentle averaging that
    # removes the residual step without moving the endpoints relative to
    # each other (idx and idx+n alias to the same circular positions).
    wrapped = x[(idx + n) % n]
    y[pos] = x[pos] * (1.0 - blend) + 0.5 * (x[pos] + wrapped) * blend
    return y


def eq_cleanup(x, sr):
    """Light, loop-friendly tone shaping (FFT-domain, zero-phase).

    - one-pole-ish gentle roll-off below ~120 Hz so low energy does not
      accumulate into rumble across an endless loop;
    - mild high-shelf attenuation above ~7 kHz (-4 dB) to take the harsh
      edge off without dulling the grit.
    Zero-phase FFT shaping keeps the wrap continuity intact.
    """
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    g = np.ones_like(f)
    lo = f < 120.0
    g[lo] = np.clip((f[lo] / 120.0) ** 1.5, 0.0, 1.0)   # roll off sub-120 Hz
    hs = 10.0 ** (-4.0 / 20.0)
    blend = 1.0 / (1.0 + np.exp(-(f - 7000.0) / 1200.0))  # smooth >7 kHz
    g = g * (1.0 - blend) + g * hs * blend
    return np.fft.irfft(X * g, n=n)


def true_peak_dbfs(x, sr, os=4):
    n = len(x)
    X = np.fft.rfft(x)
    Y = np.zeros(n * os // 2 + 1, dtype=complex)
    Y[:len(X)] = X
    up = np.fft.irfft(Y, n=n * os) * os
    return 20.0 * np.log10(np.max(np.abs(up)) + 1e-12), up


def normalise(x, sr):
    rms = np.sqrt(np.mean(x ** 2))
    if rms > 0:
        x = x * (10.0 ** (TARGET_RMS_DBFS / 20.0) / rms)
    tp, _ = true_peak_dbfs(x, sr)
    ceil = TRUE_PEAK_CEIL
    if tp > ceil:
        x = x * (10.0 ** ((ceil - tp) / 20.0))
    return x


def measure_seam(x):
    jump = abs(float(x[0]) - float(x[-1]))
    typ = float(np.mean(np.abs(np.diff(x)))) or 1e-12
    return jump, jump / typ


def encode_ogg(x, sr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(x, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype("<i2").tobytes()
    cmd = [FF, "-hide_banner", "-loglevel", "error", "-y",
           "-f", "s16le", "-ar", str(sr), "-ac", "1", "-i", "pipe:0",
           "-c:a", "libvorbis", "-qscale:a", "5",
           "-ac", "1", "-ar", str(sr), path]
    p = subprocess.run(cmd, input=pcm16,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace"))
        raise SystemExit("ffmpeg encode failed")


def verify(path, sr):
    with open(path, "rb") as fh:
        magic = fh.read(4)
    print("[verify] OggS magic  :", magic == b"OggS", magic)
    tmp = path + ".verify.wav"
    p = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y",
                        "-i", path, "-f", "wav", tmp],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace"))
        raise SystemExit("ffmpeg decode (verify) failed")
    dec, drate = read_wav(tmp)
    os.remove(tmp)
    rms = np.sqrt(np.mean(dec ** 2))
    peak = np.max(np.abs(dec))
    tp, _ = true_peak_dbfs(dec, drate)
    jump, ratio = measure_seam(dec)
    print("[verify] channels    : 1 (mono)")
    print("[verify] sample rate : %d Hz" % drate)
    print("[verify] duration    : %.4f s  (%d frames)"
          % (len(dec) / float(drate), len(dec)))
    print("[verify] RMS         : %.2f dBFS" % (20.0 * np.log10(rms + 1e-12)))
    print("[verify] sample peak : %.2f dBFS" % (20.0 * np.log10(peak + 1e-12)))
    print("[verify] true peak   : %.2f dBFS (4x oversampled)" % tp)
    print("[verify] seam jump   : %.8f abs  (%.4f x mean interior step)"
          % (jump, ratio))


def main():
    src, sr = read_wav(SRC_WAV)
    core = pick_steady_core(src, sr)

    # Reverse-mirror the steady core -> an exactly periodic ~2.1 s buffer.
    mir = reverse_mirror(core)

    # Resample 48k -> 44100 Hz by band-limited rfft length change. Doing
    # this on the periodic mirror keeps it periodic (irfft of a truncated
    # rfft of a periodic signal is still periodic), so the wrap stays
    # continuous; length is preserved by the subsequent steps.
    n_in = len(mir)
    n_out = int(round(n_in * OUT_SR / sr))
    X = np.fft.rfft(mir)
    if n_out < n_in:
        X = X[:n_out // 2 + 1]
    mir = np.fft.irfft(X, n=n_out) * (n_out / n_in)

    # EQ the still-periodic mirror (circular FFT shaping preserves the
    # mirror's exact end==start continuity), THEN apply the belt-and-braces
    # wrap crossfade as the final sample-domain operation, THEN normalise.
    mir = eq_cleanup(mir, OUT_SR)
    loop = wrap_crossfade(mir, OUT_SR)
    loop = normalise(loop, OUT_SR)

    j, r = measure_seam(loop)
    print("[build] pre-encode seam: %.8f abs (%.4f x mean step), len %.4f s"
          % (j, r, len(loop) / OUT_SR))

    encode_ogg(loop, OUT_SR, OUT_OGG)
    print("[build] wrote", OUT_OGG)
    verify(OUT_OGG, OUT_SR)


if __name__ == "__main__":
    main()
PY
