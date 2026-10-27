"""#363 comparison prototype: redraw hard-to-read skill icons pixel by pixel in the item icon style.

Same rules as draw_item_icons.py: 64px canvas, item palette, upper-left light, 2px dark outline,
no anti-aliasing and no generative model. Not wired into the game; run with a destination folder.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image

OUTLINE = (18, 13, 22)
STEEL = [(70, 66, 84), (89, 82, 92), (133, 115, 108), (197, 178, 159), (245, 235, 219)]
LEATHER = [(69, 39, 35), (110, 67, 52), (181, 126, 86)]
BRASS = [(155, 99, 51), (204, 142, 77), (235, 186, 132)]
WOOD = [(92, 50, 36), (123, 73, 47), (160, 108, 70), (204, 150, 107)]
RED = [(68, 27, 25), (118, 38, 28), (174, 76, 46), (200, 110, 66)]
STONE = [(98, 82, 66), (150, 128, 98), (200, 180, 142)]
WHITE = STEEL[4]
SIZE = 64
ROOT2 = math.sqrt(2)


def diagonal(x, y, cx=32, cy=32):
    dx, dy = x + 0.5 - cx, y + 0.5 - cy
    return (dx - dy) / ROOT2, (dx + dy) / ROOT2


def heart(px, py, cx, cy, r):
    """Classic heart from two circles and a triangle, scaled by r."""
    lx = ((px - (cx - r * 0.55)) / r) ** 2 + ((py - cy) / r) ** 2 <= 0.36
    rx = ((px - (cx + r * 0.55)) / r) ** 2 + ((py - cy) / r) ** 2 <= 0.36
    tri = py >= cy and abs(px - cx) <= (cy + r * 1.25 - py) * 0.9
    return lx or rx or tri


def second_wind(x, y):
    px, py = x + 0.5, y + 0.5
    # Breath: two curls at the upper left, white then pale steel.
    for oy, color, length in ((12, WHITE, 20), (22, STEEL[3], 13)):
        if abs(py - oy) <= 1.6 and 4 <= px <= 4 + length:
            return color
        cx, cy = 4 + length, oy - 5
        d = math.hypot(px - cx, py - cy)
        if 3.4 <= d <= 6.6 and not (px < cx and py < cy + 1):
            return color
    if heart(px, py, 38, 34, 20):
        light = math.hypot(px - 30, py - 30)
        edge = not heart(px, py, 38, 34, 17.5)
        if edge:
            return RED[0]
        if light < 4:
            return RED[3]
        return RED[2] if light < 12 else RED[1]
    return None


def surge(x, y):
    px, py = x + 0.5, y + 0.5
    u, v = diagonal(x, y)
    # Short sword through the middle.
    if -6 <= u <= 22 and abs(v) <= min(3.0, (22 - u) * 0.7):
        return STEEL[4] if v < -1.6 else STEEL[3] if v < 0.4 else STEEL[2]
    if -9.5 <= u < -6 and abs(v) <= 8:
        return BRASS[2] if u >= -7.5 else BRASS[1]
    if -19 <= u < -9.5 and abs(v) <= 2.2:
        return LEATHER[1] if int((u + 19) // 3) % 2 else LEATHER[0]
    # Refill ring: three quarters of a circle with an arrow head, clockwise.
    d = math.hypot(px - 32, py - 32)
    angle = math.degrees(math.atan2(py - 32, px - 32)) % 360
    if 24 <= d <= 29 and not (300 <= angle <= 360):
        return BRASS[2] if d < 25.5 else BRASS[1] if d < 27.5 else BRASS[0]
    head = [(58, 22), (48, 12), (62, 8)]
    if inside(px, py, head):
        return BRASS[2] if py < 14 else BRASS[1]
    return None


def inside(px, py, poly):
    hit = False
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def jump(x, y):
    px, py = x + 0.5, y + 0.5
    # Low step on the left, high step on the right.
    for left, top, right in ((3, 50, 22), (40, 38, 61)):
        if left <= px <= right and top <= py <= 61:
            return STONE[2] if py < top + 3 else STONE[0] if px > right - 3 else STONE[1]
    # Boot lifting off from the low step.
    boot = (12 <= px <= 21 and 26 <= py <= 42) or (12 <= px <= 28 and 36 <= py <= 44)
    if boot:
        if py > 42:
            return LEATHER[0]
        if py < 29:
            return BRASS[1]
        return LEATHER[2] if px < 15 else LEATHER[1]
    # Arc arrow from the boot to the high step.
    d = math.hypot((px - 36) / 22, (py - 30) / 20)
    if 0.86 <= d <= 1.0 and py < 30 and px > 18:
        return WHITE
    if inside(px, py, [(50, 22), (62, 28), (54, 36)]):
        return WHITE
    return None


def outlined(draw):
    image = Image.new("RGBA", (SIZE, SIZE))
    filled = set()
    for y in range(SIZE):
        for x in range(SIZE):
            color = draw(x, y)
            if color is not None:
                image.putpixel((x, y), (*color, 255))
                filled.add((x, y))
    for x, y in [(x, y) for y in range(SIZE) for x in range(SIZE) if (x, y) not in filled]:
        if any((x + dx, y + dy) in filled for dx in range(-2, 3) for dy in range(-2, 3)
               if abs(dx) + abs(dy) <= 3):
            image.putpixel((x, y), (*OUTLINE, 255))
    return image


ICONS = {"second_wind": second_wind, "surge": surge, "jump": jump}
parser = argparse.ArgumentParser()
parser.add_argument("destination", type=Path)
args = parser.parse_args()
args.destination.mkdir(parents=True, exist_ok=True)
for name, draw in ICONS.items():
    image = outlined(draw)
    assert image.getbbox(), name
    image.save(args.destination / f"{name}.png")
    print(json.dumps({"icon": name, "canvas": [SIZE, SIZE], "content": image.getbbox()}))
