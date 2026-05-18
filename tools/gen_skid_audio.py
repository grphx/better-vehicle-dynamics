#!/usr/bin/env python3
"""
BVD skid-audio generator.

Deterministically synthesises TWO short, seamlessly-loopable mono tyre
squeal clips entirely from numpy noise + oscillators + filters. There is
NO sampled or third-party audio anywhere: every sample is computed from
scratch here, so both clips are wholly original by construction. This
script is the SOLE producer of both BVD_skid.ogg and BVD_skid_offroad.ogg.

A convincing tyre skid is a stick-slip phenomenon: a strong WARBLING
tonal squeal sitting over a bed of broadband rubber-scrub noise, coloured
by a couple of rubbery resonances, with a little low-frequency contact
weight underneath. We build exactly that, in four layers:

  1. Squeal tone   -- inharmonic partial stack whose fundamental wanders
                       (slow LFO + fast low-amplitude jitter). This
                       wandering pitch is THE cue that sells it as a real
                       skid rather than a test tone.
  2. Scrub noise   -- white -> bandpass, amplitude-roughened by a fast
                       random AM envelope (granular rubber-on-asphalt).
  3. Formants      -- 2-3 high-Q resonators on a noise bed for the
                       rubbery resonant character.
  4. Low body      -- low-passed rumble for contact weight, kept low in
                       the mix.

Mixed, gently tanh-saturated for grit, high-shelf-trimmed above ~7 kHz,
then loudness/peak-trimmed. The clip is made loop-seamless with a
sample-exact equal-power (cos/sin) crossfade of its tail back into its
head, done in numpy (ffmpeg acrossfade mis-truncates a single file). The
loop length is snapped to a near-integer number of mean-f0 periods so the
dominant squeal phase is close to continuous across the seam; the warble
plus the crossfade mask any residue.

The Java/Lua side plays these as a SUSTAINED LOOP and re-triggers exactly
as the crossfade tail begins, so a held slide is one continuous squeal.

Usage:
    python3 tools/gen_skid_audio.py

Output:
    workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid.ogg
    workshop/BetterVehicleDynamics/42.18/media/sound/BVD_skid_offroad.ogg
"""

import os
import subprocess
import sys
import wave

import numpy as np

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
RNG_SEED   = 20240517      # fixed -- reproducible audio
SR         = 44100         # sample rate (Hz)
DUR_S      = 2.00          # nominal clip length (seconds, refined per-clip)
XFADE_S    = 0.200         # loop-seam crossfade length (seconds)
TARGET_RMS_DBFS  = -17.0   # mid of the -16..-18 dBFS target
TARGET_PEAK_DBFS = -2.0    # true-ish peak ceiling (do NOT slam to -1)
FFMPEG = os.path.expanduser(
    "~/.local/lib/python3.12/site-packages/imageio_ffmpeg/"
    "binaries/ffmpeg-linux-x86_64-v7.0.2"
)
# ---------------------------------------------------------------------------


def _biquad(x, b, a):
    """Direct-form-I biquad; b/a length-3 coefficient lists."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    a0, a1, a2 = a
    for n in range(x.shape[0]):
        xn = x[n]
        yn = (b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, xn
        y2, y1 = y1, yn
        y[n] = yn
    return y


def _bandpass(x, f0, q):
    """RBJ band-pass (constant skirt gain) biquad."""
    w0 = 2.0 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2.0 * q)
    cw = np.cos(w0)
    b = [q * alpha, 0.0, -q * alpha]
    a = [1.0 + alpha, -2.0 * cw, 1.0 - alpha]
    return _biquad(x, b, a)


def _lowpass(x, f0, q=0.707):
    """RBJ low-pass biquad."""
    w0 = 2.0 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2.0 * q)
    cw = np.cos(w0)
    b0 = (1.0 - cw) / 2.0
    b = [b0, 1.0 - cw, b0]
    a = [1.0 + alpha, -2.0 * cw, 1.0 - alpha]
    return _biquad(x, b, a)


def _highpass(x, f0, q=0.707):
    """RBJ high-pass biquad."""
    w0 = 2.0 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2.0 * q)
    cw = np.cos(w0)
    b0 = (1.0 + cw) / 2.0
    b = [b0, -(1.0 + cw), b0]
    a = [1.0 + alpha, -2.0 * cw, 1.0 - alpha]
    return _biquad(x, b, a)


def _highshelf(x, f0, gain_db, q=0.707):
    """RBJ high-shelf biquad (gain_db negative => trim the top)."""
    a_amp = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * np.pi * f0 / SR
    cw = np.cos(w0)
    sw = np.sin(w0)
    alpha = sw / (2.0 * q)
    two_sqrt_a_alpha = 2.0 * np.sqrt(a_amp) * alpha
    b0 = a_amp * ((a_amp + 1.0) + (a_amp - 1.0) * cw + two_sqrt_a_alpha)
    b1 = -2.0 * a_amp * ((a_amp - 1.0) + (a_amp + 1.0) * cw)
    b2 = a_amp * ((a_amp + 1.0) + (a_amp - 1.0) * cw - two_sqrt_a_alpha)
    a0 = (a_amp + 1.0) - (a_amp - 1.0) * cw + two_sqrt_a_alpha
    a1 = 2.0 * ((a_amp - 1.0) - (a_amp + 1.0) * cw)
    a2 = (a_amp + 1.0) - (a_amp - 1.0) * cw - two_sqrt_a_alpha
    return _biquad(x, [b0, b1, b2], [a0, a1, a2])


def _rms(x):
    return float(np.sqrt(np.mean(x * x)) + 1e-12)


def _smooth_random(rng, n, rate_hz):
    """A smooth random control signal: white noise low-passed at rate_hz,
    normalised to roughly unit peak. Used for the 'alive' wander."""
    raw = rng.standard_normal(n).astype(np.float64)
    sm = _lowpass(raw, max(1.0, rate_hz))
    m = np.max(np.abs(sm))
    return sm / m if m > 1e-9 else sm


def _loop_samples(f0_mean):
    """Pick a clip length close to DUR_S but snapped so the loop body
    (length - crossfade) spans a near-integer number of mean-f0 periods,
    keeping the dominant squeal phase near-continuous across the seam."""
    period = SR / f0_mean
    target_body = DUR_S * SR - XFADE_S * SR
    k = round(target_body / period)
    body = int(round(k * period))
    return body + int(round(XFADE_S * SR))


def _squeal_tone(rng, n, t, f0_lo, f0_hi, partials, partial_rolloff,
                 lfo_depth, lfo_rate, jitter_depth, jitter_rate):
    """Inharmonic partial stack with a wandering fundamental.

    f0(t) = base * (1 + lfo_depth*slowLFO + jitter_depth*fastJitter)
    The slow LFO is a smooth sine-ish wander; the jitter is a faster,
    low-amplitude smoothed-noise tremor -- together the 'warble' that
    makes the ear hear a tyre under load instead of an oscillator.
    """
    base = 0.5 * (f0_lo + f0_hi)
    # Slow wander: a couple of detuned sines so it never repeats blandly.
    slow = (np.sin(2.0 * np.pi * lfo_rate * t)
            + 0.45 * np.sin(2.0 * np.pi * (lfo_rate * 1.7) * t + 0.9))
    slow /= np.max(np.abs(slow))
    fast = _smooth_random(rng, n, jitter_rate)
    f0 = base * (1.0 + lfo_depth * slow + jitter_depth * fast)

    # Phase accumulator so the instantaneous frequency is honoured.
    phase = 2.0 * np.pi * np.cumsum(f0) / SR
    tone = np.zeros(n)
    # Slightly inharmonic stretch so partials are not exact integers.
    stretch = 1.0028
    for k in range(1, partials + 1):
        ratio = k * (stretch ** (k - 1))
        gain = partial_rolloff ** (k - 1)
        # tiny per-partial phase offset for a less synthetic stack
        tone += gain * np.sin(ratio * phase + 0.31 * k)
    tone /= np.max(np.abs(tone))
    return tone, float(np.mean(f0))


def _scrub_noise(rng, n, t, bp_lo, bp_hi, am_rate_lo, am_rate_hi,
                 am_depth):
    """White -> band-passed scrub bed, roughened by a fast random AM
    envelope (granular rubber-on-asphalt texture)."""
    noise = rng.standard_normal(n).astype(np.float64)
    band = _bandpass(noise, np.sqrt(bp_lo * bp_hi),
                     np.sqrt(bp_lo * bp_hi) / (bp_hi - bp_lo))
    # Random AM in the 30-90 Hz region: smoothed noise mapped to [1-d, 1].
    am_rate = 0.5 * (am_rate_lo + am_rate_hi)
    env = _smooth_random(rng, n, am_rate)
    env = 1.0 - am_depth * (0.5 * (env + 1.0))
    out = band * env
    m = np.max(np.abs(out))
    return out / m if m > 1e-9 else out


def _formant_bed(rng, n, freqs, qs, gains):
    """High-Q resonators on a shared noise bed -> rubbery resonance."""
    noise = rng.standard_normal(n).astype(np.float64)
    out = np.zeros(n)
    for f, q, g in zip(freqs, qs, gains):
        out += g * _bandpass(noise, f, q)
    m = np.max(np.abs(out))
    return out / m if m > 1e-9 else out


def _low_body(rng, n, t, cutoff, hum_hz, hum_amp):
    """Low-passed rumble for contact weight, plus a faint hum."""
    body = _lowpass(rng.standard_normal(n).astype(np.float64), cutoff)
    body += hum_amp * np.sin(2.0 * np.pi * hum_hz * t) * \
        _lowpass(rng.standard_normal(n).astype(np.float64), 55.0)
    m = np.max(np.abs(body))
    return body / m if m > 1e-9 else body


def _finish(mix):
    """Soft-saturate, trim the harsh top, then hit the RMS target while
    holding the peak at-or-just-under the ceiling.

    A skid is a fairly dense signal, so after light saturation its crest
    factor is modest. We set the drive so that AT the target RMS the
    natural peak sits close to (but never above) the ceiling -- loud
    enough, with the spec's headroom, and explicitly NOT slammed.
    """
    mix = mix / (np.max(np.abs(mix)) + 1e-12)
    # Light grit -- tanh adds odd harmonics; gentle so we keep crest.
    mix = np.tanh(0.9 * mix) / np.tanh(0.9)
    mix = _highshelf(mix, 7000.0, -4.5)        # tame harshness >7 kHz
    # Loudness: scale to target RMS first.
    mix = mix * (10.0 ** (TARGET_RMS_DBFS / 20.0) / _rms(mix))
    peak = np.max(np.abs(mix))
    ceil = 10.0 ** (TARGET_PEAK_DBFS / 20.0)
    if peak > ceil:
        # Peak over the ceiling: pull the whole thing down (RMS drops a
        # touch but stays inside the -16..-18 window) -- never slam.
        mix = mix * (ceil / peak)
    return mix


def _loopify(x):
    """Equal-power (cos/sin) crossfade of the tail back into the head so
    x played on repeat has no discontinuity at the wrap. Sample-exact and
    deterministic -- done here, never via ffmpeg acrossfade."""
    xf = int(round(XFADE_S * SR))
    if xf * 2 >= x.shape[0]:
        return x
    out = x.copy()
    th = np.linspace(0.0, np.pi / 2.0, xf, endpoint=True)
    fade_in = np.sin(th)          # head ramps up
    fade_out = np.cos(th)         # tail ramps down
    head = x[:xf]
    tail = out[-xf:]
    out[-xf:] = tail * fade_out + head * fade_in
    return out


def _seam_wrap_step(x):
    """Max single-sample step across the loop boundary x[-1] -> x[0]
    (within the crossfaded region), as a fraction of full scale."""
    return float(abs(x[0] - x[-1]))


def _screech_pavement(rng):
    """On-road: a strong warbling stick-slip squeal over rubber scrub."""
    # Probe the mean f0 once with a throwaway pass to size the loop, then
    # rebuild deterministically at that exact length.
    _, f0_mean = _squeal_tone(
        rng, int(DUR_S * SR), np.arange(int(DUR_S * SR)) / SR,
        f0_lo=720.0, f0_hi=940.0, partials=4, partial_rolloff=0.58,
        lfo_depth=0.10, lfo_rate=4.3, jitter_depth=0.035, jitter_rate=22.0)
    rng = np.random.default_rng(RNG_SEED)      # reset -> deterministic
    n = _loop_samples(f0_mean)
    t = np.arange(n) / SR

    tone, _ = _squeal_tone(
        rng, n, t,
        f0_lo=720.0, f0_hi=940.0, partials=4, partial_rolloff=0.58,
        lfo_depth=0.10, lfo_rate=4.3, jitter_depth=0.035, jitter_rate=22.0)

    scrub = _scrub_noise(rng, n, t, bp_lo=1400.0, bp_hi=3200.0,
                         am_rate_lo=30.0, am_rate_hi=90.0, am_depth=0.55)

    formants = _formant_bed(
        rng, n, freqs=[900.0, 1800.0, 3000.0],
        qs=[9.0, 11.0, 8.0], gains=[1.0, 0.8, 0.55])

    body = _low_body(rng, n, t, cutoff=150.0, hum_hz=95.0, hum_amp=0.20)

    mix = (0.62 * tone
           + 0.40 * scrub
           + 0.30 * formants
           + 0.16 * body)
    mix = _highpass(mix, 110.0)                 # clear sub-rumble mud
    return _finish(_loopify(mix))


def _screech_offroad(rng):
    """Off-road: same engine, grittier and broader -- lower, noisier,
    much weaker squeal tone (gravel/dirt scrub dominates)."""
    _, f0_mean = _squeal_tone(
        rng, int(DUR_S * SR), np.arange(int(DUR_S * SR)) / SR,
        f0_lo=480.0, f0_hi=640.0, partials=3, partial_rolloff=0.5,
        lfo_depth=0.13, lfo_rate=3.4, jitter_depth=0.06, jitter_rate=26.0)
    rng = np.random.default_rng(RNG_SEED)
    n = _loop_samples(f0_mean)
    t = np.arange(n) / SR

    tone, _ = _squeal_tone(
        rng, n, t,
        f0_lo=480.0, f0_hi=640.0, partials=3, partial_rolloff=0.5,
        lfo_depth=0.13, lfo_rate=3.4, jitter_depth=0.06, jitter_rate=26.0)

    # Broader, lower scrub bed -> gravelly rather than a tight screech.
    scrub = _scrub_noise(rng, n, t, bp_lo=700.0, bp_hi=2600.0,
                         am_rate_lo=35.0, am_rate_hi=85.0, am_depth=0.70)

    formants = _formant_bed(
        rng, n, freqs=[700.0, 1400.0],
        qs=[4.0, 5.0], gains=[1.0, 0.7])

    body = _low_body(rng, n, t, cutoff=190.0, hum_hz=70.0, hum_amp=0.28)

    # Tone deliberately recessed; scrub + body carry the off-road feel.
    mix = (0.26 * tone
           + 0.60 * scrub
           + 0.26 * formants
           + 0.30 * body)
    mix = _highpass(mix, 90.0)
    return _finish(_loopify(mix))


def _write_wav(path, samples):
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def _encode_ogg(wav_path, ogg_path):
    if not os.path.isfile(FFMPEG):
        sys.exit(f"ffmpeg binary not found: {FFMPEG}")
    cmd = [
        FFMPEG, "-y", "-hide_banner", "-loglevel", "error",
        "-i", wav_path,
        "-c:a", "libvorbis", "-q:a", "5", "-ac", "1", "-ar", str(SR),
        ogg_path,
    ]
    subprocess.run(cmd, check=True)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.normpath(os.path.join(
        script_dir, os.pardir,
        "workshop", "BetterVehicleDynamics", "42.18", "media", "sound"
    ))
    os.makedirs(out_dir, exist_ok=True)

    jobs = [
        ("BVD_skid.ogg",         _screech_pavement, "on-road squeal"),
        ("BVD_skid_offroad.ogg", _screech_offroad,  "off-road grit"),
    ]

    for fname, fn, desc in jobs:
        rng = np.random.default_rng(RNG_SEED)   # reset per clip -> stable
        samples = fn(rng)
        dur = samples.shape[0] / SR
        rms_db = 20.0 * np.log10(_rms(samples))
        peak_db = 20.0 * np.log10(np.max(np.abs(samples)) + 1e-12)
        seam = _seam_wrap_step(samples)
        ogg_path = os.path.join(out_dir, fname)
        wav_path = ogg_path[:-4] + ".tmp.wav"
        _write_wav(wav_path, samples)
        _encode_ogg(wav_path, ogg_path)
        os.remove(wav_path)
        size = os.path.getsize(ogg_path)
        print(f"  {fname}  {size} B  {dur:.4f}s mono {SR}Hz  "
              f"RMS {rms_db:+.2f} dBFS  peak {peak_db:+.2f} dBFS  "
              f"seam |wrap-step| {seam:.5f}  ({desc})")

    print(f"\nWrote 2 skid clips to:\n  {out_dir}")


if __name__ == "__main__":
    main()
