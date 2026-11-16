#!/usr/bin/env python3
"""Draw the 3-frame hit flash as 48x48 RGBA PNGs (docs/PIXEL_ART.md, 타격 이펙트 절).

Usage: python3 scenes/combat/art/sources/effects/draw_hit_effects.py <output-directory>
Writes <output-directory>/hit_flash/000.png .. 002.png.

Standard library only (zlib, struct, binascii), so the same command writes the same bytes
without Pillow. The palette is copied from draw_item_icons.py. No anti-aliasing: every pixel is
fully opaque or fully transparent. Settings are recorded in hit_effect_generation.json.
"""

from pathlib import Path
import binascii
import struct
import sys
import zlib

SIZE = 48
CENTER = 24
OUTLINE = (18, 13, 22)
WHITE = (245, 235, 219)
LIGHT = (235, 186, 132)
BRASS = (204, 142, 77)
DARK = (155, 99, 51)
FRAMES = ("000.png", "001.png", "002.png")


def put(canvas, x, y, color):
    if 2 <= x < SIZE - 2 and 2 <= y < SIZE - 2:
        canvas[(x, y)] = color


def disc(canvas, radius, color):
    for y in range(-radius, radius + 1):
        for x in range(-radius, radius + 1):
            if x * x + y * y <= radius * radius:
                put(canvas, CENTER + x, CENTER + y, color)


def arm(canvas, dx, dy, length, color):
    """A 2px wide ray from the center, tapering by leaving the last pixels thin."""
    for step in range(length):
        for wide in (0, 1):
            if dx == 0:
                put(canvas, CENTER + wide - 1, CENTER + dy * step, color)
            elif dy == 0:
                put(canvas, CENTER + dx * step, CENTER + wide - 1, color)
            else:
                put(canvas, CENTER + dx * step + wide - 1, CENTER + dy * step, color)


def frame_small_star():
    canvas = {}
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        arm(canvas, dx, dy, 8, OUTLINE)
    disc(canvas, 4, OUTLINE)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        arm(canvas, dx, dy, 6, WHITE)
    disc(canvas, 3, WHITE)
    return canvas


def frame_big_flash():
    canvas = {}
    rays = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1))
    for dx, dy in rays:
        length = 20 if dx == 0 or dy == 0 else 12
        arm(canvas, dx, dy, length, OUTLINE)
    disc(canvas, 9, OUTLINE)
    for dx, dy in rays:
        length = 18 if dx == 0 or dy == 0 else 10
        arm(canvas, dx, dy, length, BRASS)
        arm(canvas, dx, dy, length - 5, LIGHT)
    disc(canvas, 8, LIGHT)
    disc(canvas, 5, WHITE)
    return canvas


def frame_scatter():
    canvas = {}
    pieces = ((12, 0, LIGHT), (-12, 1, BRASS), (0, -13, LIGHT), (1, 12, BRASS),
              (9, 9, DARK), (-9, 9, LIGHT), (9, -9, BRASS), (-9, -9, DARK),
              (17, -3, WHITE), (-17, 3, WHITE), (-4, -18, WHITE), (4, 18, WHITE))
    for x, y, color in pieces:
        for ox in range(2):
            for oy in range(2):
                put(canvas, CENTER + x + ox, CENTER + y + oy, OUTLINE if color == DARK else color)
        put(canvas, CENTER + x, CENTER + y, color)
    return canvas


def png_chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)


def encode_png(canvas):
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter type: none
        for x in range(SIZE):
            color = canvas.get((x, y))
            raw.extend((*color, 255) if color else (0, 0, 0, 0))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + png_chunk(b"IEND", b""))


def main(argv):
    if len(argv) != 2:
        print("usage: draw_hit_effects.py <output-directory>", file=sys.stderr)
        return 2
    output = Path(argv[1]) / "hit_flash"
    output.mkdir(parents=True, exist_ok=True)
    for name, canvas in zip(FRAMES, (frame_small_star(), frame_big_flash(), frame_scatter())):
        (output / name).write_bytes(encode_png(canvas))
        print(output / name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
