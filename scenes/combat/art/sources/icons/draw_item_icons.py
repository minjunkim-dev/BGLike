"""Draw the temporary item icons pixel by pixel. Requires Pillow; no generative model."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image

# Colors sampled from the warrior/archer/scrap robot frames (median-cut quantize).
OUTLINE = (18, 13, 22)
STEEL = [(70, 66, 84), (89, 82, 92), (133, 115, 108), (197, 178, 159), (245, 235, 219)]
INDIGO = [(33, 34, 61), (56, 49, 71)]
LEATHER = [(69, 39, 35), (110, 67, 52), (181, 126, 86)]
BRASS = [(155, 99, 51), (204, 142, 77), (235, 186, 132)]
WOOD = [(92, 50, 36), (123, 73, 47), (160, 108, 70), (204, 150, 107)]
TEAL = [(34, 57, 64), (54, 93, 97)]
STRING = (241, 210, 169)
RED = [(68, 27, 25), (118, 38, 28), (174, 76, 46), (200, 110, 66)]
CORK = [(110, 67, 52), (160, 108, 70)]
# Shapes are drawn in a 64px design grid and sampled onto the 48px canvas (#362: 24 logical px at 0.5).
DESIGN = 64
SIZE = 48
# The 16 logical px potion counter on the preparation cards keeps the same 0.5 rule with its own canvas.
PIP_SIZE = 32
ROOT2 = math.sqrt(2)


def diagonal(x, y):
    """Pixel center in a frame whose u axis points to the upper right and v to the lower right."""
    dx, dy = x + 0.5 - 32, y + 0.5 - 32
    return (dx - dy) / ROOT2, (dx + dy) / ROOT2


def sword(x, y):
    u, v = diagonal(x, y)
    if -10 <= u <= 34 and abs(v) <= min(3.4, (34 - u) * 0.75):
        if v < -2.2:
            return STEEL[4]
        if v < -0.2:
            return STEEL[3]
        return STEEL[2] if v < 2.2 else STEEL[1]
    if -14.5 <= u < -10 and abs(v) <= 11:
        if abs(v) > 9.5 and abs(u + 12.25) > 1.5:
            return None
        return BRASS[2] if u >= -11.5 else BRASS[1] if u >= -13 else BRASS[0]
    if -28 <= u < -14.5 and abs(v) <= 2.6:
        band = LEATHER[1] if int((u + 28) // 3) % 2 else LEATHER[0]
        return LEATHER[2] if v < -1.2 and band == LEATHER[1] else band
    distance = math.hypot(u + 31.5, v)
    if distance <= 4.2:
        return BRASS[2] if u + 31.5 > 1 and v < 0 else BRASS[1] if distance <= 3 else BRASS[0]
    return None


def bow(x, y):
    u, v = diagonal(x, y)
    if abs(u) > 30:
        return None
    center = -11 * (1 - (u / 28) ** 2)
    # Tips curl back toward the string side for a recurve silhouette.
    if abs(u) > 24:
        center += (abs(u) - 24) * 0.6
    thickness = 4 if abs(u) <= 5 else 3.2 - abs(u) / 30
    offset = v - center
    if abs(offset) <= thickness:
        if abs(u) <= 5:
            return TEAL[1] if offset < 0 and int(u + 5) % 3 else TEAL[0]
        if offset < -thickness + 1.4:
            return WOOD[3]
        return WOOD[2] if offset < 0.6 else WOOD[1] if offset < thickness - 1.2 else WOOD[0]
    if abs(u) <= 27 and abs(v - 1.8) <= 0.75:
        return STRING
    return None


def armor(x, y):
    px, py = x + 0.5, y + 0.5
    left_pad = ((px - 17) / 9.5) ** 2 + ((py - 19) / 7.5) ** 2 <= 1
    right_pad = ((px - 47) / 9.5) ** 2 + ((py - 19) / 7.5) ** 2 <= 1
    neck = ((px - 32) / 7.5) ** 2 + ((py - 13) / 6.5) ** 2 <= 1
    half = 13 + 3 * min(1, (py - 14) / 10) - 3 * max(0, (py - 30) / 12) + 3 * max(0, (py - 46) / 9)
    torso = 14 <= py <= 56 and abs(px - 32) <= half and not neck
    if py > 46 and abs(px - 32) <= 1:
        torso = False
    if left_pad or right_pad:
        cx = 17 if left_pad else 47
        lx, ly = (px - cx) / 9.5, (py - 19) / 7.5
        # The pad rim over the torso falls through so the chest shading shows there.
        if lx * lx + ly * ly <= 0.62 or not torso:
            return STEEL[4] if lx + ly < -0.9 else STEEL[3] if lx + ly < 0.2 else STEEL[1]
    if not torso:
        return None
    if ((px - 32) / 10) ** 2 + ((py - 13) / 9) ** 2 <= 1:
        return INDIGO[1] if px < 32 else INDIGO[0]
    if 40 <= py <= 44.5:
        if abs(px - 32) <= 3:
            return BRASS[2] if py < 42 else BRASS[1]
        return LEATHER[1] if py < 42.5 else LEATHER[0]
    side = (px - 32) / half
    if py > 44.5 and int(py - 45) % 4 == 3:
        return STEEL[1]
    if -0.55 <= side <= -0.4:
        return STEEL[4]
    if side < 0.1:
        return STEEL[3]
    return STEEL[2] if side < 0.7 else STEEL[1]


def potion(x, y):
    px, py = x + 0.5, y + 0.5
    distance = math.hypot(px - 32, py - 40)
    body = distance <= 17
    neck = abs(px - 32) <= 5 and 15 <= py <= 26
    lip = abs(px - 32) <= 7 and 12 <= py <= 16
    cork = abs(px - 32) <= 4.5 and 5 <= py < 12
    if cork:
        return CORK[1] if px < 31 else CORK[0]
    if lip:
        return STEEL[3] if py < 14 else STEEL[2]
    if not (body or neck):
        return None
    angle = math.degrees(math.atan2(py - 40, px - 32))
    if body and 11 <= distance <= 13.5 and -160 <= angle <= -110:
        return STEEL[4]
    if body and py >= 31:
        if py < 33:
            return RED[3]
        light = math.hypot(px - 25, py - 35)
        if distance > 15:
            return RED[0]
        return RED[3] if light < 6 else RED[2] if light < 17 else RED[1]
    if neck and px < 30:
        return STEEL[3]
    return INDIGO[1] if px < 36 else INDIGO[0]


def outlined(draw, size=SIZE):
    image = Image.new("RGBA", (size, size))
    filled = set()
    step = DESIGN / size
    for y in range(size):
        for x in range(size):
            # Sample the design grid at this canvas pixel's centre; nothing is resampled afterwards.
            color = draw((x + 0.5) * step - 0.5, (y + 0.5) * step - 0.5)
            if color is not None:
                image.putpixel((x, y), (*color, 255))
                filled.add((x, y))
    # 2 source px equals the 1 logical px outline of the unit frames at scale 0.5.
    for x, y in [(x, y) for y in range(size) for x in range(size) if (x, y) not in filled]:
        if any((x + dx, y + dy) in filled for dx in range(-2, 3) for dy in range(-2, 3)
               if abs(dx) + abs(dy) <= 3):
            image.putpixel((x, y), (*OUTLINE, 255))
    return image


ICONS = {"sword": sword, "bow": bow, "armor": armor, "potion": potion}

# draw_skill_icons.py imports the palette, sword, potion and outlined from this file.
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    for name, draw in ICONS.items():
        image = outlined(draw)
        bounds = image.getbbox()
        assert bounds and min(bounds[:2]) >= 2 and max(bounds[2:]) <= SIZE - 2, (name, bounds)
        image.save(args.destination / f"{name}.png")
        print(json.dumps({"icon": name, "canvas": [SIZE, SIZE], "content": bounds}))
    pip = outlined(potion, PIP_SIZE)
    # The tiny counter has no extra margin; only the 2px outline itself must stay on the canvas.
    fill = [(x, y) for y in range(PIP_SIZE) for x in range(PIP_SIZE)
            if pip.getpixel((x, y))[3] and pip.getpixel((x, y))[:3] != OUTLINE]
    bounds = (min(x for x, _ in fill), min(y for _, y in fill), max(x for x, _ in fill) + 1, max(y for _, y in fill) + 1)
    assert bounds and min(bounds[:2]) >= 2 and max(bounds[2:]) <= PIP_SIZE - 2, ("potion_pip", bounds)
    pip.save(args.destination / "potion_pip.png")
    print(json.dumps({"icon": "potion_pip", "canvas": [PIP_SIZE, PIP_SIZE], "content": bounds}))
