#!/usr/bin/env python3
"""
BVD tyre-mark decal generator.
Procedurally renders 4 ORIGINAL tyre-skid decals at 64x64 RGBA.
Deterministic (fixed seed). Run from repo root or anywhere — output
path is relative to this script's location.

Usage:
    python3 tools/gen_tiremarks.py

Output: workshop/BetterVehicleDynamics/42.18/media/textures/Item_bvd_tiremark_{v,h,d1,d2}.png
"""

import os
import math
import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
RNG_SEED   = 20240516          # fixed — reproducible art
SIZE       = 64                # pixels per side (64x64 decal sprite)
CORE_ALPHA = 70                # per-blob opacity (0-255). Calibrated for
                               # the flat-disk shape + sub-pixel-render
                               # combo: low enough that overlap blends to
                               # a smooth gradient (no visible centres),
                               # high enough that a single pass actually
                               # reads as a dark mark on asphalt.
EDGE_FADE  = 0.30              # fraction of half-width used for soft feather.
                               # Wider feather = crisper-looking thin line
                               # instead of a fuzzy wide blob.
TREAD_STRENGTH = 0             # tread ribs disabled — they read as noise on
                               # a thin streak. Set >0 to bring them back.
TREAD_LINES    = 1
TREAD_SPACING  = 6
TRACK_WIDTH    = 9             # pixel width of a single tyre track. 6 read
                               # too anemic, 12 (original dual-streak) was
                               # heavy. 9 is the visible middle.
TRACK_GAP      = 0             # single-streak sprite (per-wheel placement
                               # carries the lateral spacing now).
DARK_VALUE     = 30            # RGB grey value of the skid mark (near-black)
# ---------------------------------------------------------------------------

rng = np.random.default_rng(RNG_SEED)

def _gaussian_1d(x, sigma):
    """Return a Gaussian weight for position x (scalar or array)."""
    return np.exp(-0.5 * (x / sigma) ** 2)


def _build_canvas():
    """Return a zeroed float32 RGBA canvas [H, W, 4]."""
    return np.zeros((SIZE, SIZE, 4), dtype=np.float32)


def _splat_track(canvas, cx, cy, length, width, direction_deg, noise_map):
    """
    Splat a single tyre-track streak onto *canvas* in-place.

    canvas       : float32 [SIZE, SIZE, 4]
    cx, cy       : centre of the streak in pixel space
    length       : pixel length along the main axis
    width        : pixel width perpendicular to main axis
    direction_deg: 0 = vertical (along Y), 90 = horizontal (along X)
    noise_map    : float32 [SIZE, SIZE] grain map (0..1)
    """
    rad = math.radians(direction_deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)

    # Pixel grid
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    dx = xs - cx
    dy = ys - cy

    # Rotated coordinates: along-axis and cross-axis
    along  =  dx * sin_a + dy * cos_a   # streak length axis
    across = -dx * cos_a + dy * sin_a   # streak width axis

    half_l = length / 2.0
    half_w = width  / 2.0

    # Soft length falloff (Gaussian at ends)
    sigma_l = half_l * 0.28
    len_weight = np.where(
        np.abs(along) < half_l * (1.0 - EDGE_FADE),
        1.0,
        _gaussian_1d(np.abs(along) - half_l * (1.0 - EDGE_FADE), sigma_l)
    )

    # Soft width falloff
    sigma_w = half_w * 0.35
    wid_weight = np.where(
        np.abs(across) < half_w * (1.0 - EDGE_FADE),
        1.0,
        _gaussian_1d(np.abs(across) - half_w * (1.0 - EDGE_FADE), sigma_w)
    )

    # Tread-rib modulation along the cross axis
    tread = np.zeros_like(across)
    for rib in range(TREAD_LINES):
        offset = (rib - (TREAD_LINES - 1) / 2.0) * TREAD_SPACING
        tread += _gaussian_1d(across - offset, 1.2)
    tread = np.clip(tread, 0.0, 1.0)

    # Combine into alpha contribution
    base_alpha = len_weight * wid_weight
    tread_alpha = base_alpha * tread * (TREAD_STRENGTH / 255.0)
    combined = np.clip(base_alpha * (CORE_ALPHA / 255.0) + tread_alpha, 0.0, 1.0)

    # Subtle grain noise
    grain = noise_map * 0.08
    combined = np.clip(combined - grain * base_alpha, 0.0, 1.0)

    # Accumulate into canvas alpha; RGB is constant dark grey
    canvas[:, :, 0] = np.maximum(canvas[:, :, 0], DARK_VALUE / 255.0)
    canvas[:, :, 1] = np.maximum(canvas[:, :, 1], DARK_VALUE / 255.0)
    canvas[:, :, 2] = np.maximum(canvas[:, :, 2], DARK_VALUE / 255.0)
    canvas[:, :, 3] = np.maximum(canvas[:, :, 3], combined)


def _make_noise():
    """Return a deterministic float32 [SIZE, SIZE] grain map in [0,1]."""
    base = rng.random((SIZE // 4, SIZE // 4), dtype=np.float32)
    img  = Image.fromarray((base * 255).astype(np.uint8), mode='L')
    img  = img.resize((SIZE, SIZE), Image.BILINEAR)
    return np.asarray(img, dtype=np.float32) / 255.0


def _canvas_to_image(canvas):
    """Convert float32 [H,W,4] (0..1) to PIL RGBA Image."""
    arr = np.clip(canvas * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, mode='RGBA')


def _render(direction_deg, label):
    """Render a tyre-mark decal with two parallel tracks."""
    canvas = _build_canvas()
    noise  = _make_noise()

    rad = math.radians(direction_deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)

    cx = SIZE / 2.0
    cy = SIZE / 2.0

    # v0.1.8: omnidirectional blob (NOT a directional streak). Reason: a
    # per-wheel single-streak sprite must rotate with vehicle heading, but
    # PZ only ships 4 floor-decal orientation buckets (h/v/d1/d2). The
    # bucket snap is invisible on the original dual-track sprite (symmetric
    # under 180-flip and softened by both lines) but VERY visible on a
    # single thin streak during a curve - each stamp visibly snaps to a
    # different angle. Using an omnidirectional blob removes the snap
    # entirely; consecutive quarter-tile stamps overlap into a smooth
    # tracking line at any heading.
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    blob_radius = TRACK_WIDTH * 1.6    # solid core radius in pixels. Slimmer
                                       # tyre-mark feel; still wider than the
                                       # per-stamp world spacing so adjacent
                                       # stamps overlap into a smooth line.
    blob_feather = TRACK_WIDTH * 0.65  # generous gaussian sigma. Soft edges
                                       # let consecutive disks fade INTO each
                                       # other instead of having a visible
                                       # disk perimeter where coverage drops.
    intensity = np.where(
        dist <= blob_radius,
        1.0,
        np.exp(-0.5 * ((dist - blob_radius) / blob_feather) ** 2),
    )
    alpha = np.clip(intensity * (CORE_ALPHA / 255.0), 0.0, 1.0)
    canvas[:, :, 0] = np.maximum(canvas[:, :, 0], DARK_VALUE / 255.0)
    canvas[:, :, 1] = np.maximum(canvas[:, :, 1], DARK_VALUE / 255.0)
    canvas[:, :, 2] = np.maximum(canvas[:, :, 2], DARK_VALUE / 255.0)
    canvas[:, :, 3] = np.maximum(canvas[:, :, 3], alpha)

    return _canvas_to_image(canvas)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(
        script_dir, os.pardir,
        "workshop", "BetterVehicleDynamics", "42.18", "media", "textures"
    )
    out_dir = os.path.normpath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    # direction_deg=0 → streak runs along Y (vertical); 90 → along X (horizontal).
    #
    # PZ blits floor decals as a SCREEN-aligned quad at the tile position --
    # there is no per-pixel isometric transform, so the iso perspective must
    # be baked into the artwork. The two diagonal sprites therefore use the
    # engine's exact 2:1 tile angle, atan(0.5) ≈ 26.565° off the horizontal,
    # NOT a naive 45°. This angle is dictated by the renderer (functional),
    # while the rib/noise pixel detail below remains independently authored.
    iso = math.degrees(math.atan(0.5))                 # ≈ 26.565
    specs = [
        ("Item_bvd_tiremark_v.png",  0.0,        "vertical   (screen-Y skid)"),
        ("Item_bvd_tiremark_h.png",  90.0,       "horizontal (screen-X skid)"),
        ("Item_bvd_tiremark_d1.png", 90.0 - iso, "shallow iso diagonal"),
        ("Item_bvd_tiremark_d2.png", 90.0 + iso, "shallow iso diagonal (mirror)"),
    ]

    for fname, angle, desc in specs:
        img  = _render(angle, desc)
        path = os.path.join(out_dir, fname)
        img.save(path, format="PNG")
        print(f"  {fname}  {img.size} {img.mode}  ({desc})")

    print(f"\nWrote {len(specs)} decals to:\n  {out_dir}")


if __name__ == "__main__":
    main()
