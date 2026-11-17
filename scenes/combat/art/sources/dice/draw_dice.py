#!/usr/bin/env python3
"""Draw the dice state pictures (docs/design/combat/dice-presentation.md, 도트 디자인 절).

Usage:
    python3 scenes/combat/art/sources/dice/draw_dice.py <output-directory>
    python3 scenes/combat/art/sources/dice/draw_dice.py --sheet <png-path>

The first form writes d{4,6,8,10,12,20}_{rolling,success,failure,absolute_success,absolute_failure}.png
and d{N}_liquid.png (a white mask of the inside of the body) as 48x48 RGBA PNGs. The second form writes
a 4x comparison sheet (rows: sides, columns: states) with an example liquid level and threshold line.
No numbers are drawn. Standard library only (zlib, struct, binascii), so the same command writes the
same bytes without Pillow. Settings are recorded in dice_generation.json next to this script.
Colors are copied by value: CombatUnit.HEAL_COLOR / ENEMY_COLOR and CombatDiceRollView
NEUTRAL_COLOR / ABSOLUTE_COLOR / DIE_FILL (scenes/combat/unit.gd, dice_roll_view.gd). The outline
color is the unit frames' #120d16.
"""

from pathlib import Path
import binascii
import math
import struct
import sys
import zlib

SIZE = 48
CENTER = 24.0
RADIUS = 17.9  # pixel centers stay inside 6..41, the central 36x36
SIDES = (4, 6, 8, 10, 12, 20)
STATES = ("rolling", "success", "failure", "absolute_success", "absolute_failure")

OUTLINE = (0x12, 0x0D, 0x16)
GLASS = (0x20, 0x2B, 0x35)
NEUTRAL = (0xF4, 0xEA, 0xD1)
SUCCESS = (0x70, 0xC7, 0x6D)
FAILURE = (0xDF, 0x62, 0x56)
GOLD = (0xF4, 0xCF, 0x69)
GOLD_GLASS = (0x4A, 0x3C, 0x1E)
PURPLE = (0x4A, 0x2A, 0x5C)
PURPLE_GLASS = (0x1A, 0x10, 0x24)
CRACK = (0xB8, 0x92, 0x3E)
SHEET_BACKGROUND = (0x21, 0x22, 0x3D)
SCALE = 4
# Example margins for the success and failure cells of the sheet (docs/design/combat/dice-presentation.md).
SHEET_MARGINS = {"success": 2, "failure": -3}
GAUGE_RANGE = 6


def polygon(sides):
    """Silhouette vertices around the canvas center, in the family of CombatDiceRollView.shape_points."""
    def ring(count):
        return [(CENTER + RADIUS * math.cos(math.radians(-90 + 360 * i / count)),
                 CENTER + RADIUS * math.sin(math.radians(-90 + 360 * i / count))) for i in range(count)]
    if sides == 4:
        return ring(3)
    if sides == 6:
        return [(CENTER - 16, CENTER - 16), (CENTER + 16, CENTER - 16), (CENTER + 16, CENTER + 16), (CENTER - 16, CENTER + 16)]
    if sides == 8:
        return [(CENTER, CENTER - RADIUS), (CENTER + 14, CENTER), (CENTER, CENTER + RADIUS), (CENTER - 14, CENTER)]
    if sides == 10:
        return [(CENTER, CENTER - RADIUS), (CENTER + 14, CENTER - 3), (CENTER, CENTER + RADIUS), (CENTER - 14, CENTER - 3)]
    if sides == 12:
        return ring(5)
    return ring(6)


def inside(points, x, y):
    result = False
    for index, (x1, y1) in enumerate(points):
        x2, y2 = points[(index + 1) % len(points)]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            result = not result
    return result


def body_mask(sides):
    points = polygon(sides)
    return {(x, y) for y in range(SIZE) for x in range(SIZE) if inside(points, x + 0.5, y + 0.5)}


def erode(mask, steps):
    for _ in range(steps):
        mask = {(x, y) for x, y in mask
                if all(p in mask for p in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))}
    return mask


def line(start, end):
    """Integer points on a straight line, both ends included."""
    (x1, y1), (x2, y2) = start, end
    count = max(abs(x2 - x1), abs(y2 - y1), 1)
    return [(round(x1 + (x2 - x1) * i / count), round(y1 + (y2 - y1) * i / count)) for i in range(count + 1)]


def lighter(color):
    return tuple(min(255, value + 56) for value in color)


def detail_lines(sides, glass):
    """Facet lines inside the glass: d6 top face, d20 center triangle."""
    points = [(round(x), round(y)) for x, y in polygon(sides)]
    if sides == 6:
        return {p for p in line((12, 14), (35, 14))} & glass
    if sides == 20:
        found = set()
        for a, b in ((0, 2), (2, 4), (4, 0)):
            found.update(line(points[a], points[b]))
        return found & glass
    return set()


def put(canvas, pixels, color):
    for x, y in pixels:
        if 0 <= x < SIZE and 0 <= y < SIZE:
            canvas[(x, y)] = color


def effect_pixels(state, body):
    """Pixels outside the body that tell the state: spin trail, light rays, shards."""
    found = set()
    if state == "rolling":
        for i in range(8):
            angle = math.radians(i * 45 + 20)
            x, y = round(CENTER + 21 * math.cos(angle)), round(CENTER + 21 * math.sin(angle))
            found.update({(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)})
    elif state == "absolute_success":
        for degrees in (-90, -60, -120, -30, -150):
            angle = math.radians(degrees)
            found.update(line((round(CENTER + 20 * math.cos(angle)), round(CENTER + 20 * math.sin(angle))),
                              (round(CENTER + 23 * math.cos(angle)), round(CENTER + 23 * math.sin(angle)))))
    elif state == "absolute_failure":
        for x, y in ((14, 43), (15, 43), (15, 44), (24, 44), (25, 44), (24, 45), (34, 43), (33, 43), (33, 44)):
            found.add((x, y))
    return {p for p in found if 0 <= p[0] < SIZE and 0 <= p[1] < SIZE and p not in body}


def draw_body(sides, state):
    """Return a canvas dict {(x, y): (r, g, b)} for one body picture."""
    body = body_mask(sides)
    band_outer = erode(body, 2)
    glass = erode(body, 4)
    edge, fill = {
        "rolling": (NEUTRAL, GLASS), "success": (SUCCESS, GLASS), "failure": (FAILURE, GLASS),
        "absolute_success": (GOLD, GOLD_GLASS), "absolute_failure": (PURPLE, PURPLE_GLASS),
    }[state]
    canvas = {}
    put(canvas, body, OUTLINE)
    # Two source px of dark outline on the outside, then a two px colored band, then the glass.
    for p in band_outer:
        x, y = p
        canvas[p] = lighter(edge) if (x + y < 46 and p not in glass and p not in erode(body, 3)) else edge
    put(canvas, glass, fill)
    facets = detail_lines(sides, glass)
    put(canvas, facets, lighter(fill) if state != "rolling" else edge)
    if state == "absolute_failure":
        crack = line((24, 8), (21, 17)) + line((21, 17), (26, 25)) + line((26, 25), (22, 34))
        put(canvas, [p for p in crack if p in band_outer], CRACK)
    shade = NEUTRAL if state == "rolling" else edge
    put(canvas, effect_pixels(state, body), shade if state != "absolute_failure" else PURPLE)
    return canvas


def liquid_mask(sides):
    return erode(body_mask(sides), 4)


def png_chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)


def encode_png(width, height, pixel_at):
    """pixel_at(x, y) returns (r, g, b, a)."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type: none
        for x in range(width):
            raw.extend(pixel_at(x, y))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + png_chunk(b"IEND", b""))


def canvas_png(canvas):
    return encode_png(SIZE, SIZE, lambda x, y: (*canvas[(x, y)], 255) if (x, y) in canvas else (0, 0, 0, 0))


def sheet_cell(sides, state):
    """A body picture with the example liquid and threshold line composited, for the sheet."""
    canvas = draw_body(sides, state)
    mask = liquid_mask(sides)
    top = min(y for _, y in mask)
    bottom = max(y for _, y in mask)
    if state in SHEET_MARGINS:
        margin = max(-GAUGE_RANGE, min(GAUGE_RANGE, SHEET_MARGINS[state]))
        surface = bottom + 1 - round((bottom + 1 - top) * (margin + GAUGE_RANGE) / (2 * GAUGE_RANGE))
        color = SUCCESS if state == "success" else FAILURE
    elif state == "absolute_success":
        surface, color = top, SUCCESS
    elif state == "absolute_failure":
        surface, color = bottom, FAILURE
    else:
        return canvas
    put(canvas, [p for p in mask if p[1] >= surface], color)
    threshold = (top + bottom + 1) // 2
    put(canvas, [p for p in mask if p[1] == threshold], NEUTRAL)
    return canvas


def sheet_png():
    cells = {(row, column): sheet_cell(sides, state)
             for row, sides in enumerate(SIDES) for column, state in enumerate(STATES)}

    def pixel_at(x, y):
        cell = cells[(y // (SIZE * SCALE), x // (SIZE * SCALE))]
        local = ((x % (SIZE * SCALE)) // SCALE, (y % (SIZE * SCALE)) // SCALE)
        return (*cell.get(local, SHEET_BACKGROUND), 255)
    return encode_png(SIZE * SCALE * len(STATES), SIZE * SCALE * len(SIDES), pixel_at)


def main(argv):
    if len(argv) == 3 and argv[1] == "--sheet":
        Path(argv[2]).parent.mkdir(parents=True, exist_ok=True)
        Path(argv[2]).write_bytes(sheet_png())
        print(argv[2])
        return 0
    if len(argv) != 2 or argv[1].startswith("--"):
        print("usage: draw_dice.py <output-directory> | --sheet <png-path>", file=sys.stderr)
        return 2
    output = Path(argv[1])
    output.mkdir(parents=True, exist_ok=True)
    for sides in SIDES:
        for state in STATES:
            path = output / f"d{sides}_{state}.png"
            path.write_bytes(canvas_png(draw_body(sides, state)))
            print(path)
        path = output / f"d{sides}_liquid.png"
        path.write_bytes(canvas_png({p: (255, 255, 255) for p in liquid_mask(sides)}))
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
