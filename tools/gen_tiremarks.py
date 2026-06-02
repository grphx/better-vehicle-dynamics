#!/usr/bin/env python3
"""
BVD tyre-mark decal generator (v0.1.8 — omnidirectional blob).

v0.1.8 replaces the dual-track streak sprites with a single soft
omnidirectional dark blob. The Lua side now stamps a decal at every
WHEEL'S world position rather than at the vehicle centreline, so the
sprite no longer needs to encode both tracks itself — each wheel's
blob lays its own dot, and a row of dots traces the actual wheel path.

All four sprite-type IDs (V, H, D1, D2) are written from the SAME
blob image because the floor-decal system buckets by heading and we
no longer want orientation to affect the look. Identical bytes per
file means we can drop the heading-bucketing logic without churning
existing save files that referenced the type IDs.

Deterministic (fixed seed). Run from repo root or anywhere — output
path is relative to this script's location.

Usage:
    python3 tools/gen_tiremarks.py

Output: workshop/BetterVehicleDynamics/42.18/media/textures/Item_bvd_tiremark_{v,h,d1,d2}.png
"""

import os
import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
RNG_SEED   = 20240516          # fixed — reproducible art
SIZE       = 64                # pixels per side (64x64 decal sprite)
BLOB_RADIUS_PX = 9             # core blob radius (pixels) — looks ~tire-print sized
                               # at PZ's tile render scale
BLOB_FEATHER   = 3.0           # gaussian sigma for soft edge falloff
CORE_ALPHA     = 180           # peak opacity (0-255) at blob centre
DARK_VALUE     = 24            # RGB grey value of the skid mark (near-black)
NOISE_AMP      = 18             # subtle grain on the blob so adjacent dots don't
                                # all look identical
# ---------------------------------------------------------------------------

rng = np.random.default_rng(RNG_SEED)


def build_blob():
    """
    Render one omnidirectional soft dark blob into a 64x64 RGBA image.

    The blob is a flat disc of radius BLOB_RADIUS_PX with a gaussian
    feathered edge, plus a touch of grain. Centred on the tile.
    """
    cx = cy = SIZE / 2.0
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    # Solid core out to BLOB_RADIUS_PX, then gaussian falloff.
    core = np.where(
        dist <= BLOB_RADIUS_PX,
        1.0,
        np.exp(-0.5 * ((dist - BLOB_RADIUS_PX) / BLOB_FEATHER) ** 2),
    )

    # Subtle per-pixel noise so a row of identical sprites doesn't look
    # tiled. Multiplicative on alpha so it only darkens, never lightens.
    grain = rng.normal(loc=0.0, scale=1.0, size=(SIZE, SIZE)).astype(np.float32)
    grain = np.clip(grain, -1.5, 1.5)
    alpha = core * CORE_ALPHA + grain * NOISE_AMP * core
    alpha = np.clip(alpha, 0.0, 255.0)

    rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    rgba[..., 0] = DARK_VALUE
    rgba[..., 1] = DARK_VALUE
    rgba[..., 2] = DARK_VALUE
    rgba[..., 3] = alpha.astype(np.uint8)
    return Image.fromarray(rgba, mode="RGBA")


def main():
    blob = build_blob()
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.normpath(
        os.path.join(here, "..", "workshop", "BetterVehicleDynamics",
                     "42.18", "media", "textures")
    )
    os.makedirs(out_dir, exist_ok=True)
    for suffix in ("v", "h", "d1", "d2"):
        path = os.path.join(out_dir, f"Item_bvd_tiremark_{suffix}.png")
        blob.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
