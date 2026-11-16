"""Draw the passive slot icons pixel by pixel in the item icon style (#517).

Same rules as draw_item_icons.py: 64px design grid sampled on a 32px canvas (shown at 0.5, 16 logical px), the item palette,
upper-left light, 2px dark outline, no anti-aliasing and no generative model. Requires Pillow.
"""
import argparse
import json
import math
from pathlib import Path

from draw_item_icons import BRASS, INDIGO, LEATHER, PIP_SIZE, STEEL, TEAL, WOOD, outlined
from draw_skill_icons import inside, near_segment

WHITE = STEEL[4]


def shield(px, py, left, top, face):
    """Heater shield 30 wide and 40 tall: steel rim, flat face, None outside."""
    outer = [(left, top), (left + 30, top), (left + 30, top + 18), (left + 15, top + 40), (left, top + 18)]
    if not inside(px, py, outer):
        return None
    inner = [(left + 4, top + 4), (left + 26, top + 4), (left + 26, top + 17), (left + 15, top + 33), (left + 4, top + 17)]
    if not inside(px, py, inner):
        return STEEL[4] if px - left + py - top < 26 else STEEL[3] if px - left + py - top < 44 else STEEL[2]
    return face[1] if px - left + py - top < 30 else face[0]


def phalanx(x, y):
    px, py = x + 0.5, y + 0.5
    # Front indigo shield over a back teal shield, shifted up and to the right.
    front = shield(px, py, 8, 14, INDIGO)
    if front is not None:
        return front
    return shield(px, py, 26, 6, TEAL)


def brawn(x, y):
    px, py = x + 0.5, y + 0.5
    # Leather fist seen from the front: four knuckles on top, a thumb across the fingers, a brass cuff above.
    if 20 <= px <= 44 and 4 <= py <= 14:
        return BRASS[2] if py < 7 else BRASS[1]
    if 18 <= px <= 46 and 14 <= py <= 38:
        for line in (25, 32, 39):
            if abs(px - line) <= 0.8 and 14 <= py <= 26:
                return LEATHER[0]
        if abs(py - 27) <= 0.8 and 18 <= px <= 46:
            return LEATHER[0]
        return LEATHER[2] if px < 24 else LEATHER[1] if py < 32 else LEATHER[0]
    if 22 <= px <= 42 and 38 < py <= 42:
        return LEATHER[0]
    # White impact lines under the fist.
    for segment in ((10, 54, 22, 48), (32, 58, 32, 48), (54, 54, 42, 48)):
        if near_segment(px, py, segment, 1.8):
            return WHITE
    return None


def moving_shot(x, y):
    px, py = x + 0.5, y + 0.5
    # Arrow flying to the right: steel head, wooden shaft, teal fletching on the left.
    if inside(px, py, [(46, 20), (57, 26), (46, 32)]):
        return STEEL[4] if py < 26 else STEEL[3]
    if 12 <= px < 46 and abs(py - 26) <= 2:
        return WOOD[3] if py < 25.5 else WOOD[2]
    if inside(px, py, [(6, 17), (16, 17), (20, 26), (12, 26)]) or inside(px, py, [(6, 35), (16, 35), (20, 26), (12, 26)]):
        return TEAL[1]
    # White leap arc under the arrow with an arrow tip on the right.
    ring = math.hypot((px - 30) / 22, (py - 56) / 14)
    if 0.78 <= ring <= 1.0 and py < 54:
        return WHITE
    if inside(px, py, [(48, 40), (56, 50), (44, 50)]):
        return WHITE
    return None


ICONS = {"phalanx": phalanx, "brawn": brawn, "moving_shot": moving_shot}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    record = json.loads((Path(__file__).parent / "passive_icon_generation.json").read_text())
    assert [icon["id"] for icon in record["icons"]] == list(ICONS)
    args.destination.mkdir(parents=True, exist_ok=True)
    for name, draw in ICONS.items():
        image = outlined(draw, PIP_SIZE)
        fill = [(x, y) for y in range(PIP_SIZE) for x in range(PIP_SIZE)
                if image.getpixel((x, y))[3] and image.getpixel((x, y))[:3] != (18, 13, 22)]
        bounds = (min(x for x, _ in fill), min(y for _, y in fill), max(x for x, _ in fill) + 1, max(y for _, y in fill) + 1)
        assert min(bounds[:2]) >= 2 and max(bounds[2:]) <= PIP_SIZE - 2, (name, bounds)
        image.save(args.destination / f"{name}.png")
        print(json.dumps({"icon": name, "canvas": [PIP_SIZE, PIP_SIZE], "content": bounds}))
