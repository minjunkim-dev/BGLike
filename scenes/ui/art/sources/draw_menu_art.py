#!/usr/bin/env python3
"""Draw the slider pictures and the title logo (docs/design/pixel-art.md, UI 절, #557).

Usage: python3 scenes/ui/art/sources/draw_menu_art.py <output-root>

Writes <root>/frames/slider_track.png, slider_grabber.png, slider_grabber_highlight.png and
<root>/title/logo.png. Standard library only, so the same command writes the same bytes.
The specification is recorded in menu_art_generation.json next to this script.
"""

from pathlib import Path
import binascii
import struct
import sys
import zlib

CLEAR = (0, 0, 0, 0)


def rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


# Slider track: grayscale like the 9-slice frames; the color comes from modulate_color.
TRACK_SIZE = (8, 8)
GRAY_OUTLINE, GRAY_FACE, GRAY_BRIGHT = 64, 191, 255
# Grabber: colored in the file because TextureRect-like icons have no modulate.
GRABBER_SIZE = (8, 12)
GRABBER_OUTLINE = rgb("#18292D")
GRABBER_FACE = rgb("#C5B29F")
GRABBER_BRIGHT = rgb("#F5EBDB")
GRABBER_HIGHLIGHT_FACE = rgb("#EBBA84")
# Logo.
LOGO_TEXT = "BGLike"
LOGO_SIZE = (108, 24)
CELL = 3
GLYPH_COLS, GLYPH_ROWS = 5, 7
GAP_CELLS = 1
ORIGIN = (1, 1)
LOGO_FACE = rgb("#EBBA84")
LOGO_BRIGHT = rgb("#F5EBDB")
LOGO_OUTLINE = rgb("#18292D")
LOGO_SHADOW = rgb("#0B1215")
GLYPHS = {
    "B": ["XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
    "G": [".XXX.", "X...X", "X....", "X.XXX", "X...X", "X...X", ".XXX."],
    "L": ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
    "i": ["..X..", ".....", ".XX..", "..X..", "..X..", "..X..", ".XXX."],
    "k": ["X....", "X....", "X..X.", "X.X..", "XX...", "X.X..", "X..X."],
    "e": [".....", ".....", ".XXX.", "X...X", "XXXXX", "X....", ".XXXX"],
}


def framed(size, outline, face, bright, gray=False):
    """A box with a 1px outline, a bright top/left inner edge and 1px cut corners."""
    width, height = size
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            corner = y in (0, height - 1) and x in (0, width - 1)
            if corner:
                row.append(CLEAR)
            elif y in (0, height - 1) or x in (0, width - 1):
                row.append(outline)
            elif gray and x == 1 and y > 1:
                row.append(face)  # the track only has a bright top edge
            elif y == 1 or x == 1:
                row.append(bright if (y == 1 and x <= width - 2) or (x == 1 and y <= height - 2) else face)
            else:
                row.append(face)
        rows.append(row)
    return rows


def track_pixels():
    gray = lambda value: (value, value, value, 255)
    return framed(TRACK_SIZE, gray(GRAY_OUTLINE), gray(GRAY_FACE), gray(GRAY_BRIGHT), gray=True)


def grabber_pixels(face):
    return framed(GRABBER_SIZE, GRABBER_OUTLINE, face, GRABBER_BRIGHT)


def logo_pixels():
    width, height = LOGO_SIZE
    face = [[False] * width for _ in range(height)]
    pitch = (GLYPH_COLS + GAP_CELLS) * CELL
    for index, letter in enumerate(LOGO_TEXT):
        for cy, line in enumerate(GLYPHS[letter]):
            for cx, mark in enumerate(line):
                if mark != "X":
                    continue
                for dy in range(CELL):
                    for dx in range(CELL):
                        face[ORIGIN[1] + cy * CELL + dy][ORIGIN[0] + index * pitch + cx * CELL + dx] = True

    def around(y, x):
        return (0 <= y < height and 0 <= x < width) and face[y][x]

    outline = [[not face[y][x] and any(around(y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1))
                for x in range(width)] for y in range(height)]
    silhouette = [[face[y][x] or outline[y][x] for x in range(width)] for y in range(height)]
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            if face[y][x]:
                row.append(LOGO_FACE if around(y - 1, x) else LOGO_BRIGHT)
            elif outline[y][x]:
                row.append(LOGO_OUTLINE)
            elif y > 0 and x > 0 and silhouette[y - 1][x - 1]:
                row.append(LOGO_SHADOW)
            else:
                row.append(CLEAR)
        rows.append(row)
    return rows


def png_chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)


def encode_png(rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type: none
        for pixel in row:
            raw.extend(pixel)
    header = struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + png_chunk(b"IEND", b""))


def main(argv):
    if len(argv) != 2:
        print("usage: draw_menu_art.py <output-root>", file=sys.stderr)
        return 2
    root = Path(argv[1])
    outputs = {
        "frames/slider_track.png": track_pixels(),
        "frames/slider_grabber.png": grabber_pixels(GRABBER_FACE),
        "frames/slider_grabber_highlight.png": grabber_pixels(GRABBER_HIGHLIGHT_FACE),
        "title/logo.png": logo_pixels(),
    }
    for name, rows in outputs.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(encode_png(rows))
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
