#!/usr/bin/env python3
"""Draw the three 16x16 UI 9-slice frames as grayscale RGBA PNGs (docs/PIXEL_ART.md, UI 절).

Usage: python3 scenes/ui/art/sources/draw_ui_frames.py <output-directory>

Standard library only (zlib, struct, binascii), so the same command writes the same bytes
without Pillow. The colors come from StyleBoxTexture.modulate_color at runtime; the files
stay grayscale. Settings are recorded in ui_frame_generation.json next to this script.
"""

from pathlib import Path
import binascii
import struct
import sys
import zlib

SIZE = 16
OUTLINE = 0.25
FACE = 0.75
BRIGHT = 1.0
# 2x2 corner cuts, as (y, x) pixels that become transparent. The inner (1, 1) pixel stays bright.
CORNER_CUTS = {
    (0, 0), (0, 1), (1, 0),
    (0, 14), (0, 15), (1, 15),
    (14, 0), (15, 0), (15, 1),
    (14, 15), (15, 14), (15, 15),
}
FRAMES = ("panel", "accent_panel", "button")


def frame_pixels():
    """Return rows of (gray, alpha) for the shared 9-slice geometry."""
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            if (y, x) in CORNER_CUTS:
                row.append((0.0, 0))
            elif y in (0, SIZE - 1) or x in (0, SIZE - 1):
                row.append((OUTLINE, 255))
            elif (y == 1 and x <= SIZE - 3) or (x == 1 and y <= SIZE - 3):
                # Light comes from the top-left: the inner top and left edges are the bright ones.
                row.append((BRIGHT, 255))
            else:
                row.append((FACE, 255))
        rows.append(row)
    return rows


def png_chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)


def encode_png(rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type: none
        for gray, alpha in row:
            value = round(gray * 255)
            raw.extend((value, value, value, alpha))
    header = struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + png_chunk(b"IEND", b""))


def main(argv):
    if len(argv) != 2:
        print("usage: draw_ui_frames.py <output-directory>", file=sys.stderr)
        return 2
    output = Path(argv[1])
    output.mkdir(parents=True, exist_ok=True)
    data = encode_png(frame_pixels())
    for name in FRAMES:
        (output / f"{name}.png").write_bytes(data)
        print(output / f"{name}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
