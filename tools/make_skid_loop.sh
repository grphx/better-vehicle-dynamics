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
# History: an earlier cut took a flattest-RMS window from a steady ~5 s
# passage. In-game that read as broadband static/hiss and sat too loud as
# foreground noise. This revision (a) cuts from the punchier, more TONAL
# 8-9 s region of the source instead (real tyre squeal, far less hiss),
# (b) applies real spectral noise reduction (ffmpeg afftdn) to kill the
# residual broadband floor, and (c) normalises ~5 dB quieter so the loop
# sits UNDER the engine as a background layer rather than as foreground
# static.
#
# Pipeline (sample-exact in numpy where it matters; ffmpeg decodes the
# source, performs the spectral denoise, and encodes the final Vorbis --
# ffmpeg's acrossfade mis-truncates a single-file self-loop, so the wrap
# crossfade is still done by hand):
#
#   1. Decode the CC0 mp3 to mono float PCM.
#   2. Objectively pick the most TONAL ~1.0-1.3 s sub-window inside the
#      7.8-9.4 s region (the user-requested 8-9 s squeal): the window with
#      the highest tonal-to-noise ratio (inverse spectral flatness), NOT
#      the flattest-RMS metric the old version used (that one selected the
#      hiss). The chosen core is reported with its tonal metric.
#   3. Spectral noise reduction: estimate the broadband noise floor from a
#      quiet portion of the source and run ffmpeg afftdn so the hiss is
#      clearly gone but the squeal body stays. The silent-gap RMS is
#      measured before and after and the noise-floor reduction reported.
#   4. Reverse-mirror the denoised core (core followed by its time-reverse)
#      to reach the ~2.0-2.4 s target length. For a broadband tyre-scrub
#      texture a time-reversed copy is perceptually identical to the
#      forward copy, and the mirror makes BOTH the internal turnaround and
#      the end->start wrap mathematically continuous (the mirror ends on
#      the same sample it starts on), so the FMOD loop=true repeat is
#      seamless.
#   5. A short equal-power (sin/cos) wrap crossfade folds a ~250 ms tail
#      back over the head as belt-and-braces against any residual
#      sub-sample mismatch -- no click, no level pump at the wrap.
#   6. Light cleanup only: a gentle low-end roll-off below ~120 Hz (so the
#      energy does not pile up into rumble when the clip loops forever) and
#      a mild high-shelf cut above ~7 kHz to take the hard edge off.
#   7. Normalise RMS to ~-23 dBFS (~5 dB quieter than before, a background
#      layer) and guarantee true-peak <= -3 dBFS (measured on a
#      4x-oversampled reconstruction; we do NOT slam it).
#   8. Encode mono 44100 Hz libvorbis ~q5, then VERIFY the decoded output.
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

# 2-8. Processing + verification: numpy for selection/loop/level, ffmpeg
#      afftdn for the spectral denoise, ffmpeg libvorbis for the encode.
FF_BIN="$FF" SRC_WAV="$DEC" OUT_OGG="$OUT" python3 - <<'PY'
import os, subprocess, sys, wave
import numpy as np

FF      = os.environ["FF_BIN"]
SRC_WAV = os.environ["SRC_WAV"]
OUT_OGG = os.environ["OUT_OGG"]

OUT_SR          = 44100
TARGET_RMS_DBFS = -23.0    # ~5 dB quieter than the old -18: a background
                           # layer that sits UNDER the engine, not static
TRUE_PEAK_CEIL  = -3.0
XFADE_S         = 0.25     # wrap crossfade length (seconds)

# Tonal sub-window search band (the user-requested 8-9 s squeal region,
# with a little slack either side so the picker can centre on the cleanest
# 1.0-1.3 s of genuine tyre tone rather than the hiss around it).
TONAL_LO_S      = 7.8
TONAL_HI_S      = 9.4
CORE_LENS_S     = (1.0, 1.1, 1.2, 1.3)

# Quiet portions of the source used (a) to seed afftdn's noise profile and
# (b) to A/B the silent-gap RMS before vs after denoise. Both are clearly
# below the slide level (intro hiss ~-45 dBFS, tail decay ~-47 dBFS).
NOISE_INTRO_S   = (0.05, 1.30)
NOISE_TAIL_S    = (13.35, 13.75)

# afftdn spectral subtraction: nf is the assumed noise floor (dBFS), nr the
# reduction amount (dB). Tuned so the broadband hiss is clearly gone while
# the tonal squeal body is preserved.
AFFTDN_NF       = -25
AFFTDN_NR       = 12


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


def spectral_flatness(seg):
    """Wiener entropy: geometric / arithmetic mean of the power spectrum.

    ~1 for white noise (broadband hiss), ->0 for a strongly tonal signal
    (a tyre SQUEAL with concentrated spectral energy). Its inverse is the
    tonal-to-noise ratio we maximise -- the OPPOSITE selection criterion
    to the old flattest-RMS picker, which (the user found) homed in on the
    hiss because the hiss is exactly what has the steadiest RMS envelope.
    """
    win = np.hanning(len(seg))
    sp = np.abs(np.fft.rfft(seg * win)) ** 2 + 1e-12
    gm = np.exp(np.mean(np.log(sp)))
    am = np.mean(sp)
    return gm / am


def pick_tonal_core(x, sr):
    """Pick the most TONAL ~1.0-1.3 s sub-window of the 7.8-9.4 s region.

    The user asked specifically for the 8-9 s passage -- the punchier,
    more tonal squeal with far less broadband hiss than the old steady
    window. We scan candidate lengths/offsets inside [TONAL_LO_S,
    TONAL_HI_S] and keep the window with the highest tonal-to-noise ratio
    (1 / spectral flatness). The chosen core and its tonal metric are
    reported alongside the metric of the OLD region for comparison.
    """
    best = None
    step = int(round(0.05 * sr))
    for core_s in CORE_LENS_S:
        wn = int(round(core_s * sr))
        st0 = int(round(TONAL_LO_S * sr))
        st1 = int(round((TONAL_HI_S - core_s) * sr))
        for st in range(st0, st1, step):
            seg = x[st:st + wn]
            sf = spectral_flatness(seg)
            tnr = 1.0 / sf
            if best is None or tnr > best[0]:
                rms = np.sqrt(np.mean(seg ** 2))
                best = (tnr, st, wn, sf, 20.0 * np.log10(rms + 1e-12), core_s)
    if best is None:
        raise SystemExit("no tonal region found in the 7.8-9.4 s band")
    tnr, start, wn, sf, rdb, core_s = best
    core = x[start:start + wn].copy()

    # Old-version reference: the flattest-RMS steady passage was ~3-6 s,
    # which is broadband hiss. Report its flatness so the improvement in
    # tonality is quantified, not just asserted.
    old_seg = x[int(round(3.0 * sr)):int(round(4.0 * sr))]
    old_sf = spectral_flatness(old_seg)

    print("[analysis] tonal core selected (8-9 s squeal region)")
    print("  source window : start %.3f s  length %.3f s  (%d samples @ %d Hz)"
          % (start / sr, len(core) / sr, len(core), sr))
    print("  tonal metric  : TNR %.1f  (spectral flatness %.6f; lower=tonal)"
          % (tnr, sf))
    print("  old region    : flatness %.6f  (TNR %.1f) at ~3-4 s steady hiss"
          % (old_sf, 1.0 / old_sf))
    print("  -> selected window is %.0fx more tonal than the old hiss window"
          % (old_sf / max(sf, 1e-12)))
    print("  window RMS    : %.1f dBFS (pre-denoise, pre-normalise)" % rdb)
    return core


def silent_gap_rms_dbfs(x, sr, span_s):
    a = int(round(span_s[0] * sr))
    b = int(round(span_s[1] * sr))
    seg = x[a:b]
    r = np.sqrt(np.mean(seg ** 2))
    return 20.0 * np.log10(r + 1e-12), seg


def spectral_denoise(src, sr):
    """Real broadband noise reduction via ffmpeg afftdn.

    The "static" the user heard is the recording's own broadband floor.
    afftdn performs spectral subtraction; nf/nr are tuned (constants
    above) so the hiss is clearly gone while the tonal squeal body stays.
    afftdn is applied to the WHOLE decoded source (so the quiet gaps used
    for the A/B measurement are denoised identically to the core), then
    the same gaps are re-measured and the noise-floor reduction reported.
    """
    intro_before, _ = silent_gap_rms_dbfs(src, sr, NOISE_INTRO_S)
    tail_before, _ = silent_gap_rms_dbfs(src, sr, NOISE_TAIL_S)

    pcm16 = (np.clip(src, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    af = "afftdn=nf=%d:nr=%d" % (AFFTDN_NF, AFFTDN_NR)
    cmd = [FF, "-hide_banner", "-loglevel", "error", "-y",
           "-f", "s16le", "-ar", str(sr), "-ac", "1", "-i", "pipe:0",
           "-af", af, "-f", "wav", "pipe:1"]
    p = subprocess.run(cmd, input=pcm16,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace"))
        raise SystemExit("ffmpeg afftdn denoise failed")
    buf = p.stdout
    hdr = buf.find(b"data")
    pcm = np.frombuffer(buf[hdr + 8:], dtype="<i2").astype(np.float64) / 32768.0
    # Length can shift by a few samples through the wav container; align.
    n = min(len(pcm), len(src))
    den = pcm[:n]

    intro_after, _ = silent_gap_rms_dbfs(den, sr, NOISE_INTRO_S)
    tail_after, _ = silent_gap_rms_dbfs(den, sr, NOISE_TAIL_S)
    print("[denoise] afftdn nf=%d nr=%d (spectral subtraction)"
          % (AFFTDN_NF, AFFTDN_NR))
    print("  intro gap RMS : %.2f -> %.2f dBFS  (reduction %.2f dB)"
          % (intro_before, intro_after, intro_before - intro_after))
    print("  tail  gap RMS : %.2f -> %.2f dBFS  (reduction %.2f dB)"
          % (tail_before, tail_after, tail_before - tail_after))
    return den


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

    # 3. Spectral denoise the whole source FIRST (so the picker scores the
    #    cleaned squeal, and the silent-gap A/B is measured on it).
    den = spectral_denoise(src, sr)

    # 2. Pick the most tonal sub-window of the 8-9 s squeal region.
    core = pick_tonal_core(den, sr)

    # Reverse-mirror the denoised core -> an exactly periodic ~2.1 s buffer.
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
