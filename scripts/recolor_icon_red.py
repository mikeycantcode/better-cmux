#!/usr/bin/env python3
"""Recolor the cmux chevron gradient from blue->purple to bright-red->crimson.

Operates on rasterized icon PNGs in place: it masks only the chromatic blue/cyan/
purple chevron pixels (the squircle is white, the shadow gray, the dark background
neutral, the DEV banner orange -- all left untouched) and remaps each masked pixel
to the red gradient (#ff5a5a -> #ff2d2d -> #c81e3a) by its horizontal position
within the chevron, preserving per-pixel luminance and alpha so edges/glow survive.

Requires Pillow:  python3 -m pip install --user Pillow
Run from repo root:  python3 scripts/recolor_icon_red.py
"""
import colorsys
import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STOPS = [(0.0, (0xFF, 0x5A, 0x5A)), (0.52, (0xFF, 0x2D, 0x2D)), (1.0, (0xC8, 0x1E, 0x3A))]

HUE_LO, HUE_HI = 170.0 / 360.0, 290.0 / 360.0
# Low threshold so the faint blue/cyan glow halo around the chevron is recolored too;
# the white squircle, gray shadow, and dark background are near-zero saturation (safe),
# and the orange DEV banner is outside the blue hue band (untouched).
SAT_MIN = 0.08

TARGETS = [
    "AppIcon.icon/Assets/cmux-icon-chevron 2.png",
    "design/cmux-icon-chevron.png",
    "Assets.xcassets/AppIconLight.imageset/AppIconLight.png",
    "Assets.xcassets/AppIconDark.imageset/AppIconDark.png",
    "web/app/icon.png",
    "web/app/apple-icon.png",
    "web/public/logo.png",
]
APPICON_DIRS = [
    "Assets.xcassets/AppIcon.appiconset",
    "Assets.xcassets/AppIcon-Debug.appiconset",
]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient_color(pos):
    pos = max(0.0, min(1.0, pos))
    for i in range(len(STOPS) - 1):
        p0, c0 = STOPS[i]
        p1, c1 = STOPS[i + 1]
        if pos <= p1:
            t = 0.0 if p1 == p0 else (pos - p0) / (p1 - p0)
            return lerp(c0, c1, t)
    return STOPS[-1][1]


def chevron_bbox(px, w, h):
    min_x, max_x = w, -1
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)[0]
            sat = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1]
            if sat >= SAT_MIN and HUE_LO <= hh <= HUE_HI:
                min_x = min(min_x, x)
                max_x = max(max_x, x)
    return min_x, max_x


def recolor(path):
    full = os.path.join(REPO, path)
    if not os.path.exists(full):
        print("skip (missing):", path)
        return
    img = Image.open(full).convert("RGBA")
    w, h = img.size
    px = img.load()
    min_x, max_x = chevron_bbox(px, w, h)
    if max_x < 0:
        print("skip (no chevron pixels):", path)
        return
    span = max(1, max_x - min_x)
    changed = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, light, _ = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            sat = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1]
            if sat < SAT_MIN or not (HUE_LO <= hh <= HUE_HI):
                continue
            base = gradient_color((x - min_x) / span)
            bl = colorsys.rgb_to_hls(base[0] / 255, base[1] / 255, base[2] / 255)[1]
            scale = (light / bl) if bl > 0 else 1.0
            scale = max(0.35, min(1.6, scale))
            nr = min(255, int(base[0] * scale))
            ng = min(255, int(base[1] * scale))
            nb = min(255, int(base[2] * scale))
            px[x, y] = (nr, ng, nb, a)
            changed += 1
    img.save(full)
    print(f"recolored {changed:>7} px  {path}")


def main():
    paths = list(TARGETS)
    for d in APPICON_DIRS:
        full_d = os.path.join(REPO, d)
        if os.path.isdir(full_d):
            for f in sorted(os.listdir(full_d)):
                if f.endswith(".png"):
                    paths.append(os.path.join(d, f))
    for p in paths:
        recolor(p)


if __name__ == "__main__":
    main()
