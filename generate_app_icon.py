#!/usr/bin/env python3
"""
Generate the Ortus app icon — "First Light" brand system.

Draws the Ortus sunmark (a clean white half-sun, horizon, and rays) on a dawn-sky
gradient squircle (predawn indigo → mauve → coral → gold) and writes every size
in Assets.xcassets/AppIcon.appiconset. build.sh turns these into AppIcon.icns so
the icon shows in Finder. Also exports a 512px PNG for the landing page.

Everything is drawn supersampled (4×) and downsampled with LANCZOS for crisp
edges and round caps. Run:  python3 generate_app_icon.py
"""

import math
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "Ortus", "Assets.xcassets")
APPICON_DIR = os.path.join(ASSETS, "AppIcon.appiconset")

SS = 4  # supersample factor

# Dawn gradient stops (position 0..1, RGB)
DAWN = [
    (0.00, (43, 41, 77)),    # #2B294D predawn indigo
    (0.45, (168, 69, 125)),  # #A8457D mauve
    (0.75, (227, 99, 51)),   # #E36333 coral
    (1.00, (247, 188, 99)),  # #F7BC63 gold
]
WHITE = (255, 255, 255, 255)

APP_ICON_SIZES = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_color(pos):
    for i in range(len(DAWN) - 1):
        p0, c0 = DAWN[i]
        p1, c1 = DAWN[i + 1]
        if p0 <= pos <= p1:
            t = (pos - p0) / (p1 - p0) if p1 > p0 else 0
            return lerp(c0, c1, t)
    return DAWN[-1][1]


def vertical_gradient(size):
    """Diagonal-ish dawn sky: blend by (0.35*x + 0.65*y) for a soft top-left light."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            pos = (0.30 * (x / size) + 0.70 * (y / size))
            px[x, y] = gradient_color(min(1.0, pos))
    return img


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def draw_sunmark(draw, ox, oy, q, color, stroke, filled_sun):
    """Draw the sunmark within a q×q box at (ox, oy)."""
    cx = ox + q / 2
    horizon_y = oy + q * 0.62
    sun_r = q * 0.185
    cap = stroke / 2

    def line(x1, y1, x2, y2):
        draw.line([(x1, y1), (x2, y2)], fill=color, width=int(round(stroke)))
        draw.ellipse([x1 - cap, y1 - cap, x1 + cap, y1 + cap], fill=color)
        draw.ellipse([x2 - cap, y2 - cap, x2 + cap, y2 + cap], fill=color)

    # Sun (filled half-disc or outline arc)
    bbox = [cx - sun_r, horizon_y - sun_r, cx + sun_r, horizon_y + sun_r]
    if filled_sun:
        draw.pieslice(bbox, start=180, end=360, fill=color)
    else:
        draw.arc(bbox, start=180, end=360, fill=color, width=int(round(stroke)))

    # Horizon with a gap where the sun sits
    gap = sun_r * 1.45
    inset = q * 0.07
    line(ox + inset, horizon_y, cx - gap, horizon_y)
    line(cx + gap, horizon_y, ox + q - inset, horizon_y)

    # Rays
    angles = [-90, -126, -54, -158, -22]
    lens = [0.95, 0.78, 0.78, 0.58, 0.58]
    for a, ln in zip(angles, lens):
        rad = math.radians(a)
        start = sun_r + sun_r * 0.34
        end = start + sun_r * ln
        line(cx + start * math.cos(rad), horizon_y + start * math.sin(rad),
             cx + end * math.cos(rad), horizon_y + end * math.sin(rad))


def build_app_icon(size):
    S = size * SS
    # Dawn sky clipped to a macOS squircle (inset with padding).
    inset = int(S * 0.085)
    q = S - 2 * inset
    radius = int(q * 0.225)

    sky = vertical_gradient(S)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, inset + q - 1, inset + q - 1], radius=radius, fill=255)

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(sky, (0, 0), mask)

    # Subtle top inner highlight on the squircle for a glassy lip.
    hi = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hi)
    hd.rounded_rectangle([inset, inset, inset + q - 1, inset + q - 1],
                         radius=radius, outline=(255, 255, 255, 60), width=max(1, int(S * 0.004)))
    icon = Image.alpha_composite(icon, hi)

    # White sunmark centered in the squircle.
    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    draw_sunmark(gd, inset, inset, q, WHITE, stroke=q * 0.046, filled_sun=True)
    icon = Image.alpha_composite(icon, glyph)

    return icon.resize((size, size), Image.LANCZOS)


def main():
    print("Generating Ortus app icon (dawn sky + white sunmark)…")
    master = build_app_icon(1024)
    for filename, px in APP_ICON_SIZES:
        icon = master if px == 1024 else master.resize((px, px), Image.LANCZOS)
        icon.save(os.path.join(APPICON_DIR, filename))
        print(f"  {filename} ({px}px)")

    # Export a 512 brand mark PNG for the landing/README too.
    build_app_icon(512).save(os.path.join(HERE, "landing", "assets", "app-icon.png"))
    print("  landing/assets/app-icon.png (512px)")
    print("Done.")


if __name__ == "__main__":
    main()
