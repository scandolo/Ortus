#!/usr/bin/env python3
"""
Generate macOS app icon for Ortus — a focus/productivity app themed around sunrise.
Produces all required sizes for macOS AppIcon.appiconset.
"""

import math
from PIL import Image, ImageDraw

OUTPUT_DIR = "/Users/federico/fyxer/Ortus/Ortus/Assets.xcassets/AppIcon.appiconset"

# Colors
BG_COLOR = (250, 250, 248)       # #FAFAF8 warm off-white
GREEN = (61, 107, 68)            # #3D6B44 calm green

# Icon sizes: (filename, pixel_size)
ICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def draw_sunrise_icon(size=1024):
    """Draw the sunrise icon at the given size. Design at 1024x1024."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- Rounded rectangle background (macOS icon shape) ---
    # macOS icon corner radius is roughly 22.37% of the icon size
    corner_radius = int(size * 0.2237)
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=corner_radius,
        fill=BG_COLOR,
    )

    # --- Design area with padding ---
    padding = size * 0.18  # 18% padding on each side
    cx = size / 2  # center x
    cy = size / 2  # center y

    # The drawable area
    draw_left = padding
    draw_right = size - padding
    draw_width = draw_right - draw_left

    # --- Horizon line ---
    # Place the horizon slightly below center (55% down the icon)
    horizon_y = size * 0.55
    line_thickness = max(2, int(size * 0.02))

    draw.line(
        [(draw_left, horizon_y), (draw_right, horizon_y)],
        fill=GREEN,
        width=line_thickness,
    )

    # --- Half-circle sun sitting on the horizon ---
    sun_radius = draw_width * 0.20  # 20% of the drawable width
    sun_cx = cx
    sun_cy = horizon_y  # sun sits on the horizon

    # Draw upper half of the sun (a half-circle above the horizon)
    # We draw a full ellipse clipped to above the horizon using pieslice
    bbox = [
        sun_cx - sun_radius,
        sun_cy - sun_radius,
        sun_cx + sun_radius,
        sun_cy + sun_radius,
    ]
    draw.pieslice(bbox, start=180, end=360, fill=GREEN)

    # --- Sun rays ---
    # 5 rays emanating upward from the sun, spread evenly
    num_rays = 5
    ray_length = sun_radius * 1.05  # length of each ray
    ray_gap = sun_radius * 0.28     # gap between sun edge and ray start
    ray_thickness = max(2, int(size * 0.022))

    # Rays spread from -90 degrees (straight up) across 140 degrees total
    start_angle = -140  # degrees from horizontal (measured from right, going counterclockwise)
    end_angle = -40

    for i in range(num_rays):
        if num_rays > 1:
            angle_deg = start_angle + i * (end_angle - start_angle) / (num_rays - 1)
        else:
            angle_deg = -90
        angle_rad = math.radians(angle_deg)

        # Ray starts at a gap from the sun surface
        ray_start_dist = sun_radius + ray_gap
        ray_end_dist = sun_radius + ray_gap + ray_length

        x1 = sun_cx + ray_start_dist * math.cos(angle_rad)
        y1 = sun_cy + ray_start_dist * math.sin(angle_rad)
        x2 = sun_cx + ray_end_dist * math.cos(angle_rad)
        y2 = sun_cy + ray_end_dist * math.sin(angle_rad)

        draw.line([(x1, y1), (x2, y2)], fill=GREEN, width=ray_thickness)

        # Round the ends of rays for a polished look
        cap_radius = ray_thickness / 2
        draw.ellipse(
            [x1 - cap_radius, y1 - cap_radius, x1 + cap_radius, y1 + cap_radius],
            fill=GREEN,
        )
        draw.ellipse(
            [x2 - cap_radius, y2 - cap_radius, x2 + cap_radius, y2 + cap_radius],
            fill=GREEN,
        )

    return img


def main():
    print("Generating Ortus app icon at 1024x1024...")
    master = draw_sunrise_icon(1024)

    for filename, px_size in ICON_SIZES:
        output_path = f"{OUTPUT_DIR}/{filename}"
        if px_size == 1024:
            icon = master.copy()
        else:
            icon = master.resize((px_size, px_size), Image.LANCZOS)
        icon.save(output_path, "PNG")
        print(f"  Saved {filename} ({px_size}x{px_size})")

    print(f"\nAll icons saved to:\n  {OUTPUT_DIR}")
    print("Done!")


if __name__ == "__main__":
    main()
