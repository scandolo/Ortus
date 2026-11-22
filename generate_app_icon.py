#!/usr/bin/env python3
"""Resize the First Light app icon into every size the app and the extension use.

The master is the brand kit's app-icon-1024.png (brain/projects/ortus/brand/assets/app-icon),
kept in the repo as Ortus/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png.
Usage: python3 generate_app_icon.py [path/to/app-icon-1024.png]
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(ROOT, "Ortus", "Assets.xcassets", "AppIcon.appiconset")
MASTER = os.path.join(ICONSET, "icon_512x512@2x.png")

APP_SIZES = {"icon_16x16": 16, "icon_16x16@2x": 32, "icon_32x32": 32, "icon_32x32@2x": 64,
             "icon_128x128": 128, "icon_128x128@2x": 256, "icon_256x256": 256,
             "icon_256x256@2x": 512, "icon_512x512": 512}
EXTENSION_SIZES = [16, 32, 48, 128]


def resize(source, size, out):
    subprocess.run(["sips", "-z", str(size), str(size), source, "--out", out], check=True, capture_output=True)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        shutil.copyfile(sys.argv[1], MASTER)
    for name, size in APP_SIZES.items():
        resize(MASTER, size, os.path.join(ICONSET, name + ".png"))
    for size in EXTENSION_SIZES:
        resize(MASTER, size, os.path.join(ROOT, "BrowserExtension", f"icon-{size}.png"))
    print("Icons written.")
