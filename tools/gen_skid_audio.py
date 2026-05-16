#!/usr/bin/env python3
"""
BVD skid-audio generator.

Deterministically synthesises TWO short, seamlessly-loopable mono tyre
screech clips entirely from numpy noise + filters (no sampled audio --
original by construction), writes them as WAV, then transcodes to OGG
with the bundled imageio-ffmpeg binary.

The Java side (CarController.updateSkidding) plays these as a SUSTAINED
LOOP and rides the emitter volume per physics tick, so each clip is:
  * ~0.7 s long
  * loop-seam crossfaded (head faded into the tail) so the wrap is
    inaudible when the engine repeats it
  * normalised to a comfortable headroom (game scales volume on top)

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
DUR_S      = 0.70          # clip length (seconds)
XFADE_S    = 0.060         # loop-seam crossfade length (seconds)
PEAK       = 0.82          # post-normalise peak (leave game some headroom)
FFMPEG = os.path.expanduser(
    "~/.local/lib/python3.12/site-packages/imageio_ffmpeg/"
    "binaries/ffmpeg-linux-x86_64-v7.0.2"
)
# ---------------------------------------------------------------------------


def _biquad(x, b, a):
    """Direct-form-I biquad (transposed-free); b/a length-3 coefficient lists."""
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


def _normalise(x, peak=PEAK):
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x * (peak / m)


def _loopify(x):
    """Crossfade the clip's head into its tail so x[end] -> x[0] is seamless.

    Take the first XFADE samples, fade them in, and add them (with the tail
    faded out) onto the final XFADE samples. The clip length is unchanged;
    playing it on repeat then has no discontinuity at the wrap point.
    """
    xf = int(XFADE_S * SR)
    if xf * 2 >= x.shape[0]:
        return x
    out = x.copy()
    ramp = np.linspace(0.0, 1.0, xf, endpoint=True)
    head = x[:xf]
    tail = out[-xf:]
    out[-xf:] = tail * (1.0 - ramp) + head * ramp
    return out


def _screech_pavement(rng):
    """Pavement screech: tonal-ish band-passed noise + pitch wobble +
    a low rubber-roar layer underneath."""
    n = int(DUR_S * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n).astype(np.float64)

    # Slow pitch wobble applied as a time-varying band-pass centre. We
    # approximate the wobble by summing three fixed band-passes tuned
    # around the screech band (1.5-4 kHz emphasis) at slightly detuned
    # centres and modulating their mix with low-rate LFOs.
    lfo1 = 0.5 + 0.5 * np.sin(2.0 * np.pi * 5.5 * t)
    lfo2 = 0.5 + 0.5 * np.sin(2.0 * np.pi * 8.3 * t + 1.1)

    bp_lo = _bandpass(noise, 1700.0, 4.0)
    bp_md = _bandpass(noise, 2600.0, 5.0)
    bp_hi = _bandpass(noise, 3600.0, 6.0)
    screech = bp_lo * (0.7 + 0.3 * lfo1) \
        + bp_md * (0.6 + 0.4 * lfo2) \
        + bp_hi * (0.4 + 0.3 * (1.0 - lfo1))

    # Low rubber-roar layer: heavily low-passed noise with a gentle hum.
    roar = _lowpass(rng.standard_normal(n).astype(np.float64), 220.0)
    roar += 0.25 * np.sin(2.0 * np.pi * 90.0 * t) * \
        _lowpass(rng.standard_normal(n).astype(np.float64), 60.0)

    mix = 0.80 * _normalise(screech, 1.0) + 0.34 * _normalise(roar, 1.0)
    mix = _highpass(mix, 120.0)            # clear the rumble mud
    return _normalise(_loopify(mix))


def _screech_offroad(rng):
    """Gravel/dirt: broader, grittier lower-mid noise, much less tonal."""
    n = int(DUR_S * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n).astype(np.float64)

    # Wide low-mid grit instead of a narrow screech tone.
    grit = _bandpass(noise, 900.0, 1.1) + 0.7 * _bandpass(noise, 1500.0, 1.4)
    grit = _lowpass(grit, 2600.0)

    # Scatter transients -- little gravel "tick" bursts -- for grittiness.
    ticks = np.zeros(n)
    count = 70
    idx = rng.integers(0, n, size=count)
    amp = rng.uniform(0.3, 1.0, size=count)
    ticks[idx] = amp * rng.choice([-1.0, 1.0], size=count)
    ticks = _bandpass(ticks, 1800.0, 1.5)

    # Low dirt rumble.
    rumble = _lowpass(rng.standard_normal(n).astype(np.float64), 170.0)
    am = 0.7 + 0.3 * np.sin(2.0 * np.pi * 11.0 * t)

    mix = 0.70 * _normalise(grit, 1.0) * am \
        + 0.45 * _normalise(ticks, 1.0) \
        + 0.40 * _normalise(rumble, 1.0)
    mix = _highpass(mix, 90.0)
    return _normalise(_loopify(mix))


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
        "-c:a", "libvorbis", "-q:a", "4", "-ac", "1", "-ar", str(SR),
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
        ("BVD_skid.ogg",         _screech_pavement, "pavement screech"),
        ("BVD_skid_offroad.ogg", _screech_offroad,  "gravel / dirt"),
    ]

    for fname, fn, desc in jobs:
        rng = np.random.default_rng(RNG_SEED)   # reset per clip -> stable
        samples = fn(rng)
        ogg_path = os.path.join(out_dir, fname)
        wav_path = ogg_path[:-4] + ".tmp.wav"
        _write_wav(wav_path, samples)
        _encode_ogg(wav_path, ogg_path)
        os.remove(wav_path)
        size = os.path.getsize(ogg_path)
        print(f"  {fname}  {size} bytes  {DUR_S:.2f}s mono  ({desc})")

    print(f"\nWrote 2 skid clips to:\n  {out_dir}")


if __name__ == "__main__":
    main()
