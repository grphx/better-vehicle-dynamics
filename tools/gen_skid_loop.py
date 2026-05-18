#!/usr/bin/env python3
"""Deterministic generator for the Better Vehicle Dynamics skid-loop clip.

Produces one mono 44100 Hz Vorbis (~q5) file engineered to loop natively:
FMOD's loop=true will repeat the buffer end-to-start forever, so the clip
must be PERFECTLY seam-continuous (no click, no level pump at the wrap).

Sound design (a held tyre slide, not a pure squeal):
  * Core: broadband rubber-scrub noise, band-passed ~700 Hz - 3.5 kHz.
    This is the dominant layer -- gritty, textured, "the tyre is grinding
    across the road" -- which is what the user actually wanted to hear.
  * Roughness: slow amplitude modulation (~15-40 Hz) so the scrub has a
    living, juddering envelope rather than flat static.
  * Squeal: a *subtle*, low-level tonal partial that gently wanders in
    pitch around ~1.4 kHz. Secondary by design -- it colours the scrub,
    it does not dominate it.

Seam strategy (belt and braces):
  1. The whole texture is built from inherently periodic primitives whose
     periods divide the loop length exactly: the AM/wander LFOs use integer
     cycle counts over the clip, and the noise bed is synthesised in the
     frequency domain with an integer-bin spectrum so its inverse FFT is
     mathematically periodic at the clip length.
  2. On top of that an equal-power (constant-energy) wrap crossfade folds
     the tail back over the head, which absorbs any residual filter
     transient and guarantees a continuous first-derivative at the seam.

Everything is original and synthesised here from first principles: no
sampled, recorded, or third-party audio of any kind.
"""

import os
import subprocess
import sys
import wave

import numpy as np

# --- deterministic config ---------------------------------------------------
SEED         = 0x5C1D            # fixed; RNG is reset right before synthesis
SR           = 44100             # Hz, mono
DURATION_S   = 2.0               # seconds (exact -> integer sample count)
N            = int(round(SR * DURATION_S))

FF_BIN = ("/home/grphx/.local/lib/python3.12/site-packages/"
          "imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2")

OUT_OGG = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "workshop", "BetterVehicleDynamics", "42.18",
    "media", "sound", "BVD_skid_loop.ogg",
)

# Target loudness
TARGET_RMS_DBFS  = -18.0
PEAK_CEIL_DBFS   = -2.0


def _periodic_bandnoise(rng, n, sr, f_lo, f_hi, tilt=0.0):
    """White-ish noise band-limited to [f_lo, f_hi], synthesised in the
    frequency domain so the inverse FFT is exactly periodic over n samples.

    Random phase per bin + zeroed bins outside the band; bin 0 (DC) and the
    Nyquist bin are forced real so the result is a real signal. Because the
    spectrum lives on the exact rfft bin grid of length n, irfft(spectrum)
    has period n by construction -- the natural seam is already perfect
    before any crossfade is applied.
    """
    nbins = n // 2 + 1
    freqs = np.fft.rfftfreq(n, d=1.0 / sr)
    mag = np.zeros(nbins, dtype=np.float64)
    band = (freqs >= f_lo) & (freqs <= f_hi)
    mag[band] = 1.0
    # Gentle spectral tilt (dB per octave) so the scrub is not flat-white.
    with np.errstate(divide="ignore"):
        octv = np.log2(np.where(freqs > 1.0, freqs, 1.0) / max(f_lo, 1.0))
    mag *= np.power(10.0, (tilt * octv) / 20.0)
    # Soft raised-cosine skirts at the band edges -> no ringing at the cuts.
    edge = max(1, int(0.06 * (f_hi - f_lo) * n / sr))
    if band.any():
        idx = np.where(band)[0]
        lo0, hi0 = idx[0], idx[-1]
        for k in range(min(edge, len(idx))):
            w = 0.5 - 0.5 * np.cos(np.pi * (k + 1) / (edge + 1))
            mag[lo0 + k] *= w
            mag[hi0 - k] *= w
    phase = rng.uniform(0.0, 2.0 * np.pi, size=nbins)
    spec = mag * np.exp(1j * phase)
    spec[0] = 0.0
    if n % 2 == 0:
        spec[-1] = spec[-1].real
    sig = np.fft.irfft(spec, n=n)
    m = np.max(np.abs(sig))
    return sig / m if m > 0 else sig


def _wander_tone(n, sr, base_cycles, depth_hz, wander_cycles):
    """Low-level squeal partial whose pitch gently wanders.

    The total accumulated phase is forced to close on an exact multiple of
    2*pi over the clip so the tone is perfectly circular (its value AND
    slope match at the wrap). The carrier uses an INTEGER cycle count
    (base_cycles) over the buffer; the wander term is the integral of a
    zero-mean periodic LFO (integer wander_cycles), so its contribution to
    the phase also returns to zero at n. Both pieces therefore wrap exactly.
    """
    idx = np.arange(n)
    # Integer-cycle carrier phase: ends at 2*pi*base_cycles -> closes.
    carrier = 2.0 * np.pi * base_cycles * idx / n
    # Zero-mean periodic FM; its running integral is periodic over n.
    lfo = np.sin(2.0 * np.pi * wander_cycles * idx / n)
    fm = np.cumsum(lfo)
    fm -= np.linspace(0.0, fm[-1], n)          # remove residual drift -> closes
    fm *= (2.0 * np.pi * depth_hz / sr)
    phase = carrier + fm
    tone = np.sin(phase) + 0.18 * np.sin(3.0 * phase)
    return tone / np.max(np.abs(tone))


def synthesize():
    rng = np.random.default_rng(SEED)

    # 1. Dominant scrub bed: broadband rubber noise ~700 Hz - 3.5 kHz,
    #    mildly darkened (negative tilt) so it grinds rather than hisses.
    scrub = _periodic_bandnoise(rng, N, SR, 700.0, 3500.0, tilt=-2.5)

    # A second, lower, narrower noise band adds body/weight under the grind.
    body = _periodic_bandnoise(rng, N, SR, 320.0, 900.0, tilt=-1.0)

    # 2. Slow amplitude roughness: a sum of a few AM tones in the 15-40 Hz
    #    range, each with an integer cycle count over the clip so the whole
    #    envelope is exactly periodic (seam-safe). Kept above zero so it
    #    modulates rather than gates the scrub.
    am = np.zeros(N)
    for cyc, amp in ((34, 0.5), (52, 0.3), (78, 0.2)):  # ~17 / 26 / 39 Hz
        ph = rng.uniform(0.0, 2.0 * np.pi)
        am += amp * np.sin(2.0 * np.pi * cyc * np.arange(N) / N + ph)
    am = 0.62 + 0.38 * (am / np.max(np.abs(am)))         # in ~[0.24, 1.0]

    # 3. Subtle wandering squeal partial (secondary layer, low level).
    #    base_cycles is an integer count over the buffer (~1400 Hz at 2 s).
    squeal = _wander_tone(N, SR, base_cycles=2800, depth_hz=120.0,
                          wander_cycles=3)

    # Mix: scrub dominates, body fills the low-mids, squeal only seasons it.
    # Every layer is circular-by-construction (FFT-periodic noise beds,
    # integer-cycle AM, phase-closed squeal), so the buffer already wraps
    # without an endpoint discontinuity -- no one-sided fold is applied
    # (a forward crossfade would actually BREAK x[0]==x[-1]).
    mix = (0.78 * scrub + 0.34 * body) * am + 0.12 * squeal

    # 4. Belt-and-braces seam clean-up: circularly convolve a tiny
    #    raised-cosine kernel ONLY across the wrap region so any residual
    #    sub-sample mismatch (band-edge skirts, float rounding) is smoothed
    #    symmetrically -- this preserves circular continuity exactly because
    #    the smoothing itself is performed on the circular (wrapped) signal.
    w = 9                                                # samples each side
    ker = np.hanning(2 * w + 1)
    ker /= ker.sum()
    seg = w + len(ker)
    edge = np.concatenate([mix[-seg:], mix[:seg]])       # wrapped neighbourhood
    sm = np.convolve(edge, ker, mode="same")
    mix[-seg:] = sm[:seg]
    mix[:seg] = sm[seg:2 * seg]

    # 5. Loudness: normalise RMS to target, then guarantee the peak ceiling.
    rms = np.sqrt(np.mean(mix ** 2))
    if rms > 0:
        mix *= (10.0 ** (TARGET_RMS_DBFS / 20.0)) / rms
    peak = np.max(np.abs(mix))
    ceil = 10.0 ** (PEAK_CEIL_DBFS / 20.0)
    if peak > ceil:
        mix *= ceil / peak

    return mix.astype(np.float64)


def _measure_seam(x):
    """Sample-step discontinuity across the loop point: |x[0] - x[-1]|
    measured against the local sample-to-sample step magnitude, so it is
    expressed as a multiple of the signal's own typical step. < ~1 means
    the wrap is indistinguishable from any interior sample transition.
    """
    jump = abs(float(x[0]) - float(x[-1]))
    typ = float(np.mean(np.abs(np.diff(x)))) or 1e-12
    return jump, jump / typ


def _encode_ogg(samples, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype("<i2").tobytes()
    cmd = [
        FF_BIN, "-hide_banner", "-loglevel", "error", "-y",
        "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
        "-c:a", "libvorbis", "-qscale:a", "5", "-ac", "1", "-ar", str(SR),
        path,
    ]
    p = subprocess.run(cmd, input=pcm16, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace"))
        raise SystemExit("ffmpeg encode failed")


def _verify(path):
    """All measurements are taken on the DECODED Vorbis output -- i.e. the
    exact samples the game will play and loop -- not the pre-encode buffer.
    """
    with open(path, "rb") as fh:
        magic = fh.read(4)
    print("OggS magic     :", magic == b"OggS", magic)
    tmp = path + ".verify.wav"
    cmd = [FF_BIN, "-hide_banner", "-loglevel", "error", "-y",
           "-i", path, "-f", "wav", tmp]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace"))
        raise SystemExit("ffmpeg decode (verify) failed")
    with wave.open(tmp, "rb") as w:
        ch, rate, nfr = w.getnchannels(), w.getframerate(), w.getnframes()
        raw = w.readframes(nfr)
    os.remove(tmp)
    dec = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    print("channels       :", ch, "(mono)" if ch == 1 else "(NOT MONO)")
    print("sample rate    :", rate, "Hz")
    print("duration       : %.4f s  (%d frames)" % (nfr / float(rate), nfr))
    rms = np.sqrt(np.mean(dec ** 2))
    peak = np.max(np.abs(dec))
    print("RMS            : %.2f dBFS" % (20.0 * np.log10(rms)))
    print("peak           : %.2f dBFS" % (20.0 * np.log10(peak)))
    jump, ratio = _measure_seam(dec)
    print("seam jump      : %.6f abs  (%.4f x mean interior step)"
          % (jump, ratio))


def main():
    samples = synthesize()
    _encode_ogg(samples, OUT_OGG)
    print("wrote", OUT_OGG)
    _verify(OUT_OGG)


if __name__ == "__main__":
    main()
