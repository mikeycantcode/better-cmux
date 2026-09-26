#!/usr/bin/env python3
"""Generate the bmux terminal-box brand mark everywhere it ships.

Source art: design/bmux-logo-source.jpg (white mark on black, 1024x1024).
The white mark is extracted as a luminance mask, cropped tight, and
composited onto the tile:
- Tile: macOS-style squircle inset to 880/1024 (Apple template is 824),
  corner radius 229/1024, vertical gradient #1B1B1F -> #101014.
- Mark: MARK_W wide on the 1024 canvas, centered.
- Banner variants (DEV / NIGHTLY) shrink + raise the mark so it clears
  the bottom band.

Outputs:
  Assets.xcassets/AppIcon.appiconset/{16..512}@{1x,2x}.png (+ _dark twins)
  Assets.xcassets/AppIcon-Debug.appiconset/...   (orange DEV banner)
  Assets.xcassets/AppIcon-Nightly.appiconset/... (purple NIGHTLY banner)
  Assets.xcassets/AppIconLight.imageset/AppIconLight.png   (1024)
  Assets.xcassets/AppIconDark.imageset/AppIconDark.png     (1024)
  web/public/logo.png            (256)
  web/public/logo-nightly.png    (256, light variant with NIGHTLY banner)
  web/public/cmux-icon.svg       (512px PNG wrapped in SVG)

Usage: python3 scripts/generate-logo.py [--preview out.png]
"""

import argparse
import base64
import io
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024          # contract canvas
SS = 4            # supersampling factor
CORNER = 229      # squircle corner radius on the contract canvas
TILE = 880        # squircle span on the 1024 canvas (Apple template is 824; cmux runs a bit larger)
SOURCE_IMAGE = os.path.join(ROOT, "design", "bmux-logo-source.jpg")
MARK_W = 720      # mark width on the contract canvas (plain tile)
BANNER_MARK_W = 600
BANNER_CENTER_Y = 430

BG_TOP = (0x1B, 0x1B, 0x1F, 255)
BG_BOTTOM = (0x10, 0x10, 0x14, 255)
WHITE = (255, 255, 255, 255)
INK = (0x11, 0x11, 0x14, 255)  # stripes on light backgrounds


def _vertical_gradient(size, top, bottom):
    grad = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel(
            (0, y),
            tuple(round(a + (b - a) * t) for a, b in zip(top[:3], bottom[:3])) + (255,),
        )
    return grad.resize((size, size))


def _load_mark_mask():
    """White-on-black source art -> tight, noise-cleaned luminance mask."""
    src = Image.open(SOURCE_IMAGE).convert("L")
    # Levels: crush JPEG ringing in the black field, clip the white body.
    lo, hi = 40, 215
    src = src.point(lambda v: 0 if v <= lo else 255 if v >= hi else round((v - lo) * 255 / (hi - lo)))
    return src.crop(src.getbbox())


_MARK_MASK = None


def _mark_mask():
    global _MARK_MASK
    if _MARK_MASK is None:
        _MARK_MASK = _load_mark_mask()
    return _MARK_MASK


def draw_mark(px, *, tile=True, stripe_color=WHITE, banner=None, rounded=True,
              bg_top=BG_TOP, bg_bottom=BG_BOTTOM, mark_w=MARK_W,
              center_y=S // 2):
    """Render the mark at px x px. Returns RGBA image."""
    scale = px * SS / S
    big = px * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    if tile:
        img.alpha_composite(_vertical_gradient(big, bg_top, bg_bottom))
    else:
        img.alpha_composite(Image.new("RGBA", (big, big), bg_top))

    mask = _mark_mask()
    mw = round(mark_w * scale)
    mh = round(mask.height * mw / mask.width)
    mask = mask.resize((mw, mh), Image.LANCZOS)
    fill = Image.new("RGBA", (mw, mh), stripe_color)
    img.paste(fill, ((big - mw) // 2, round(center_y * scale - mh / 2)), mask)

    d = ImageDraw.Draw(img)
    if banner is not None:
        label, color = banner
        band_h = round(big * 0.20)
        d.rectangle([0, big - band_h, big, big], fill=color)
        # Very small renders would need a sub-12px font, which FreeType
        # cannot measure reliably; the colored band alone reads fine there.
        font_size = round(band_h * 0.52)
        if font_size >= 12:
            font = _banner_font(font_size)
            tb = d.textbbox((0, 0), label, font=font)
            tw, th = tb[2] - tb[0], tb[3] - tb[1]
            d.text(
                ((big - tw) / 2 - tb[0], big - band_h + (band_h - th) / 2 - tb[1]),
                label,
                font=font,
                fill=(255, 255, 255, 255),
            )

    if rounded:
        mask = Image.new("L", (big, big), 0)
        md = ImageDraw.Draw(mask)
        mr = round(CORNER * big / S)
        md.rounded_rectangle([0, 0, big - 1, big - 1], radius=mr, fill=255)
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        img = out

    if tile and rounded:
        # Inset the squircle so the Dock/Finder icon matches the size of
        # every other macOS app icon instead of filling the whole slot.
        inner = round(px * TILE / S)
        tile_img = img.resize((inner, inner), Image.LANCZOS)
        out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        out.alpha_composite(tile_img, ((px - inner) // 2, (px - inner) // 2))
        return out

    return img.resize((px, px), Image.LANCZOS)


_BANNER_FONT_PATH = None


def _banner_font(size_px):
    global _BANNER_FONT_PATH
    if _BANNER_FONT_PATH is None:
        candidates = [
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        ]
        for path in candidates:
            if os.path.exists(path):
                _BANNER_FONT_PATH = path
                break
        else:
            _BANNER_FONT_PATH = candidates[-1]
    return ImageFont.truetype(_BANNER_FONT_PATH, size_px)


DEV_BANNER = (255, 107, 0, 255)      # sampled from the pre-rebrand DEV icon
NIGHTLY_BANNER = (140, 60, 220, 255)  # sampled from the pre-rebrand NIGHTLY icon


def _banner_colors():
    return {"DEV": DEV_BANNER, "NIGHTLY": NIGHTLY_BANNER}


# The catalog Contents.json expects exactly these ten slots per appearance.
APPICON_BASENAMES = [
    "16.png", "16@2x.png", "32.png", "32@2x.png", "128.png",
    "128@2x.png", "256.png", "256@2x.png", "512.png", "512@2x.png",
]


def write_png_set(out_dir, renderer):
    os.makedirs(out_dir, exist_ok=True)
    for name in APPICON_BASENAMES:
        base = int(name.split("@")[0].split(".")[0])
        px = base * (2 if "@2x" in name else 1)
        renderer(px).save(os.path.join(out_dir, name))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="OUT", help="write a contact sheet of key assets and exit")
    args = ap.parse_args()

    dev_banner = _banner_colors()["DEV"]
    nightly_banner = _banner_colors()["NIGHTLY"]

    renders = {
        "main": lambda px: draw_mark(px),
        "debug": lambda px: draw_mark(px, banner=("DEV", dev_banner),
                                      mark_w=BANNER_MARK_W, center_y=BANNER_CENTER_Y),
        "nightly": lambda px: draw_mark(px, banner=("NIGHTLY", nightly_banner),
                                        mark_w=BANNER_MARK_W, center_y=BANNER_CENTER_Y),
        "nightly-light": lambda px: draw_mark(
            px,
            tile=False,
            rounded=False,
            stripe_color=INK,
            bg_top=(255, 255, 255, 255),
            bg_bottom=(255, 255, 255, 255),
            banner=("NIGHTLY", nightly_banner),
            mark_w=BANNER_MARK_W,
            center_y=BANNER_CENTER_Y,
        ),
    }

    if args.preview:
        sheet = Image.new("RGBA", (4 * 264, 300), (40, 40, 44, 255))
        for i, key in enumerate(["main", "debug", "nightly", "nightly-light"]):
            sheet.alpha_composite(renders[key](256), (i * 264 + 4, 20))
        sheet.save(args.preview)
        print(f"preview -> {args.preview}")
        return

    assets = os.path.join(ROOT, "Assets.xcassets")

    # Light and dark appearances share the mark; the catalog expects both names.
    write_png_set(os.path.join(assets, "AppIcon.appiconset"), renders["main"])
    for name in [n.replace(".png", "_dark.png") for n in APPICON_BASENAMES]:
        src = name.replace("_dark", "")
        Image.open(os.path.join(assets, "AppIcon.appiconset", src)).save(
            os.path.join(assets, "AppIcon.appiconset", name)
        )

    write_png_set(os.path.join(assets, "AppIcon-Debug.appiconset"), renders["debug"])
    write_png_set(os.path.join(assets, "AppIcon-Nightly.appiconset"), renders["nightly"])

    renders["main"](1024).save(os.path.join(assets, "AppIconLight.imageset", "AppIconLight.png"))
    renders["main"](1024).save(os.path.join(assets, "AppIconDark.imageset", "AppIconDark.png"))

    web = os.path.join(ROOT, "web", "public")
    renders["main"](256).save(os.path.join(web, "logo.png"))
    renders["nightly-light"](256).save(os.path.join(web, "logo-nightly.png"))

    # The mark is raster art, so the SVG wraps a 512px PNG render.
    buf = io.BytesIO()
    renders["main"](512).save(buf, format="PNG")
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}">
  <image width="{S}" height="{S}" href="data:image/png;base64,{data}" />
</svg>
'''
    with open(os.path.join(web, "cmux-icon.svg"), "w") as f:
        f.write(svg)

    print("regenerated: AppIcon sets (main/debug/nightly), welcome imagesets, web/public logos, cmux-icon.svg")


if __name__ == "__main__":
    main()
