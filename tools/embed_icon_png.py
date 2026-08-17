#!/usr/bin/env python3
"""Regenerate assets/icon.svg from the raster master assets/icon.png.

The icon pipeline (tools/gen_icons.py) takes a single SVG master and rescales it
to every output size with rsvg-convert. When the artwork is a raster rather than
vector, this script wraps it: the PNG is embedded as a base64 data URI in a
full-bleed <image>, so gen_icons.py needs no special-casing and rsvg-convert
still does the resampling.

Run this after replacing assets/icon.png:

    python3 tools/embed_icon_png.py

The PNG should be square and at least 512x512 (the PS5 homescreen icon size);
anything smaller will be upscaled and look soft on the tile.
"""
import base64
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PNG = os.path.join(ROOT, "assets", "icon.png")
SVG = os.path.join(ROOT, "assets", "icon.svg")
VIEWBOX = 1024
MIN_SIZE = 512

TEMPLATE = '''<?xml version="1.0" encoding="UTF-8"?>
<svg id="jailbreak_icon" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {vb} {vb}">
  <defs>
    <!-- Master art is the raster in assets/icon.png, embedded here as a data URI
         so the whole icon pipeline keeps a single SVG master and rsvg-convert can
         rescale it to every output size. Regenerate with tools/embed_icon_png.py
         after replacing assets/icon.png. -->
  </defs>
  <image x="0" y="0" width="{vb}" height="{vb}" preserveAspectRatio="xMidYMid slice"
         xlink:href="data:image/png;base64,{b64}"/>
</svg>
'''


def png_size(data):
    """(width, height) from the IHDR chunk, without needing Pillow."""
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        sys.exit("Error: assets/icon.png is not a PNG file.")
    return struct.unpack(">II", data[16:24])


def main():
    if not os.path.isfile(PNG):
        sys.exit(f"Error: {os.path.relpath(PNG, ROOT)} not found.")

    with open(PNG, "rb") as f:
        data = f.read()

    w, h = png_size(data)
    if w != h:
        print(f"Warning: icon.png is {w}x{h}, not square — it will be centre-cropped.")
    if min(w, h) < MIN_SIZE:
        print(f"Warning: icon.png is {w}x{h}; below {MIN_SIZE}x{MIN_SIZE} the PS5 tile will look soft.")

    svg = TEMPLATE.format(vb=VIEWBOX, b64=base64.b64encode(data).decode("ascii"))
    with open(SVG, "w", newline="\n") as f:
        f.write(svg)

    print(f"Wrote {os.path.relpath(SVG, ROOT)} "
          f"({len(svg)} bytes) from {w}x{h} {os.path.relpath(PNG, ROOT)}.")
    print("Now run `make icons` (needs rsvg-convert) to regenerate the derived assets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
