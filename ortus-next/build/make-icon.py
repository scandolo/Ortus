#!/usr/bin/env python3
"""Generate tray-iconTemplate.png and @2x. Mac template images are black on
transparent; the system tints them based on dark/light menu bar."""
import struct, zlib, os, sys

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets")

def png(width, height, pixels):
    """pixels is a flat list of RGBA tuples row-major."""
    raw = b""
    for y in range(height):
        raw += b"\x00"
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw += bytes([r, g, b, a])
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")

def make_icon(size):
    """A simple half-disc rising over a baseline + horizon line."""
    pixels = []
    cx = size / 2
    horizon_y = size * 0.66
    sun_radius = size * 0.32
    line_thickness = max(1, size // 12)
    for y in range(size):
        for x in range(size):
            on = False
            # Sun (half disc above horizon).
            dx = x + 0.5 - cx
            dy = y + 0.5 - horizon_y
            if dy <= 0:
                dist = (dx * dx + dy * dy) ** 0.5
                if abs(dist - sun_radius) <= line_thickness * 0.6:
                    on = True
            # Horizon baseline.
            if abs((y + 0.5) - horizon_y) <= line_thickness * 0.55:
                # Skip a notch where the sun meets the baseline
                if abs(dx) > sun_radius - line_thickness:
                    on = True
            pixels.append((0, 0, 0, 255 if on else 0))
    return png(size, size, pixels)

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "tray-iconTemplate.png"), "wb") as f:
        f.write(make_icon(16))
    with open(os.path.join(OUT_DIR, "tray-iconTemplate@2x.png"), "wb") as f:
        f.write(make_icon(32))
    print("Wrote tray icons to", OUT_DIR)

if __name__ == "__main__":
    main()
