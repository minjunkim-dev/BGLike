"""Draw the skill and common action icons pixel by pixel in the item icon style (#384).

Same rules as draw_item_icons.py: 64px design grid on the 48px canvas, the item palette, upper-left light, 2px dark outline,
no anti-aliasing and no generative model. Attack and potion reuse the item sword and potion.
"""
import argparse
import json
import math
from pathlib import Path

from draw_item_icons import BRASS, INDIGO, LEATHER, RED, SIZE, STEEL, TEAL, WOOD, outlined, potion, sword

WHITE = STEEL[4]


def inside(px, py, polygon):
    hit = False
    for (x1, y1), (x2, y2) in zip(polygon, polygon[1:] + polygon[:1]):
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def near_segment(px, py, segment, width):
    sx, sy, ex, ey = segment
    t = max(0.0, min(1.0, ((px - sx) * (ex - sx) + (py - sy) * (ey - sy)) / ((ex - sx) ** 2 + (ey - sy) ** 2)))
    return math.hypot(px - (sx + t * (ex - sx)), py - (sy + t * (ey - sy))) <= width


def rotated(x, y, cx, cy):
    """Diagonal frame around (cx, cy): u points to the upper right, v to the lower right."""
    dx, dy = x + 0.5 - cx, y + 0.5 - cy
    return (dx - dy) / math.sqrt(2), (dx + dy) / math.sqrt(2)


def short_sword(u, v, length):
    """Steel blade along +u from a brass guard at u=0, leather grip below. None outside."""
    if 0 <= u <= length and abs(v) <= min(3.0, (length - u) * 0.7):
        return STEEL[4] if v < -1.6 else STEEL[3] if v < 0.4 else STEEL[2]
    if -3.5 <= u < 0 and abs(v) <= 8:
        return BRASS[2] if u >= -1.5 else BRASS[1] if u >= -2.5 else BRASS[0]
    if -13 <= u < -3.5 and abs(v) <= 2.2:
        return LEATHER[1] if int((u + 13) // 3) % 2 else LEATHER[0]
    if math.hypot(u + 15.5, v) <= 3:
        return BRASS[2] if v < 0 else BRASS[1]
    return None


def boot(px, py, left, top):
    """Leather boot 22 wide and 24 tall with a rounded toe to the right and a dark sole."""
    lx, ly = px - left, py - top
    shaft = 1 <= lx <= 12 and 0 <= ly <= 16
    instep = 1 <= lx <= 16 and 12 <= ly <= 21
    toe = math.hypot((lx - 15) / 7, (ly - 17) / 5) <= 1 and ly <= 21
    sole = 0 <= lx <= 21 and 21 < ly <= 24 and not (lx > 19 and ly > 23)
    if sole:
        return LEATHER[0]
    if not (shaft or instep or toe):
        return None
    if ly < 4:
        return BRASS[2] if lx < 6 else BRASS[1]
    return LEATHER[2] if lx < 4 or (toe and ly < 15) else LEATHER[1]


def attack(x, y):
    return sword(x, y)


def second_wind(x, y):
    px, py = x + 0.5, y + 0.5
    # Two breath curls at the upper left.
    for oy, color, length in ((14, WHITE, 18), (23, STEEL[3], 12)):
        if abs(py - oy) <= 1.6 and 3 <= px <= 3 + length:
            return color
        cx, cy = 3 + length, oy - 5
        distance = math.hypot(px - cx, py - cy)
        if 3.4 <= distance <= 6.6 and not (px < cx and py < cy + 1):
            return color
    # Heart: two lobes and a point, lit from the upper left.
    left = math.hypot(px - 30, py - 30) <= 11.5
    right = math.hypot(px - 50, py - 30) <= 11.5
    point = py >= 30 and abs(px - 40) <= (60 - py) * 0.75
    if not (left or right or point):
        return None
    inner = (math.hypot(px - 30, py - 30) <= 9.5 or math.hypot(px - 50, py - 30) <= 9.5
             or (py >= 30 and abs(px - 40) <= (57 - py) * 0.75))
    if not inner:
        return RED[0]
    if math.hypot(px - 27, py - 27) < 3.5:
        return RED[3]
    return RED[2] if px + py < 72 else RED[1]


def surge(x, y):
    px, py = x + 0.5, y + 0.5
    u, v = rotated(x, y, 31, 33)
    blade = short_sword(u + 4, v, 22)
    if blade is not None:
        return blade
    # Refill ring: three quarters of a circle that ends in an arrow head at the upper right.
    distance = math.hypot(px - 32, py - 32)
    angle = math.degrees(math.atan2(py - 32, px - 32)) % 360
    if 24 <= distance <= 29.5 and not 290 <= angle <= 345:
        return BRASS[2] if distance < 25.6 else BRASS[1] if distance < 28 else BRASS[0]
    if inside(px, py, [(45, 7), (60, 10), (53, 22)]):
        return BRASS[2] if px + py < 66 else BRASS[1]
    return None


def parry(x, y):
    px, py = x + 0.5, y + 0.5
    # Enemy sword coming from the upper right; its tip glances off the rim with sparks.
    u, v = rotated(x, y, 46, 18)
    blade = short_sword(-u, v, 15)
    if blade is not None:
        return blade
    for segment in ((32, 12, 36, 4), (46, 30, 54, 34), (28, 18, 22, 14)):
        if near_segment(px, py, segment, 1.3):
            return BRASS[2]
    # Round shield: steel rim, indigo face, brass boss.
    distance = math.hypot(px - 26, py - 38)
    if distance > 22:
        return None
    if distance > 18.5:
        return STEEL[4] if px + py < 58 else STEEL[3] if px + py < 70 else STEEL[2]
    if distance <= 4.5:
        return BRASS[2] if px + py < 63 else BRASS[1]
    if abs(px - 26) <= 1.2 or abs(py - 38) <= 1.2:
        return STEEL[2]
    return INDIGO[1] if px + py < 64 else INDIGO[0]


def opportunity(x, y):
    px, py = x + 0.5, y + 0.5
    # Watching eye at the upper left.
    ex, ey = 17, 14
    if abs(px - ex) <= 14 and abs(py - ey) <= 8 * max(0.0, 1 - ((px - ex) / 14) ** 2) ** 0.5:
        iris = math.hypot(px - ex, py - ey)
        if iris <= 3:
            return INDIGO[0]
        if iris <= 6.5:
            return TEAL[1] if px + py < ex + ey else TEAL[0]
        return WHITE if py < ey else STEEL[3]
    # Sword with its blade pointing down-left and a white slash arc at the lower right.
    u, v = rotated(x, y, 46, 30)
    blade = short_sword(-u, v, 26)
    if blade is not None:
        return blade
    arc = math.hypot(px - 28, py - 28)
    if 30 <= arc <= 33 and px > 36 and py > 36 and px + py < 100:
        return WHITE
    return None


def mark(x, y):
    px, py = x + 0.5, y + 0.5
    # Arrow stuck in the centre, coming from the upper right.
    u, v = rotated(x, y, 30, 34)
    if 2 <= u <= 30 and abs(v) <= 1.3:
        return WOOD[2] if v < 0 else WOOD[1]
    if 22 <= u <= 31 and 1.3 < abs(v) <= 5.5 - (u - 22) * 0.35:
        return TEAL[1] if v < 0 else TEAL[0]
    # Target board.
    distance = math.hypot(px - 30, py - 34)
    if distance > 26:
        return None
    ring = int(distance // 5.2)
    if ring == 0:
        return RED[3] if px + py < 63 else RED[2]
    if ring % 2:
        return WHITE if px + py < 64 else STEEL[3]
    return RED[2] if px + py < 64 else RED[1]


def shock(x, y):
    px, py = x + 0.5, y + 0.5
    # Arrow flying to the upper right.
    u, v = rotated(x, y, 30, 34)
    if -26 <= u <= 14 and abs(v) <= 1.4:
        return WOOD[3] if v < 0 else WOOD[1]
    if 14 < u <= 26 and abs(v) <= (26 - u) * 0.55:
        return STEEL[4] if v < 0 else STEEL[2]
    if -28 <= u <= -16 and 1.4 < abs(v) <= 6 - (u + 28) * 0.25:
        return TEAL[1] if v < 0 else TEAL[0]
    # Lightning bolt beside the head.
    if inside(px, py, [(36, 30), (50, 30), (44, 40), (54, 40), (34, 62), (40, 46), (30, 46)]):
        return BRASS[2] if px < 42 else BRASS[1]
    return None


def disengage(x, y):
    px, py = x + 0.5, y + 0.5
    # Teal arrow pointing back to the left.
    if inside(px, py, [(2, 16), (18, 4), (18, 11), (44, 11), (44, 21), (18, 21), (18, 28)]):
        return TEAL[1] if py < 15 else TEAL[0]
    # Boot sliding back to the left, with speed lines trailing on the toe side.
    shoe = boot(px, py, 12, 34)
    if shoe is not None:
        return shoe
    for line_y, start in ((40, 38), (48, 40), (56, 38)):
        if abs(py - line_y) <= 1.2 and start <= px <= start + 18:
            return WHITE
    return None


def shove(x, y):
    px, py = x + 0.5, y + 0.5
    # Open leather glove, palm forward: four fingers split by 1px gaps, a thumb and a brass cuff.
    if 10 <= px <= 34 and 54 <= py <= 61:
        return BRASS[2] if py < 56 else BRASS[1]
    for left, top in ((10, 14), (16, 9), (22, 8), (28, 12)):
        if left <= px <= left + 5 and top <= py <= 32:
            if py < top + 3 and (px < left + 1 or px > left + 4):
                return None
            return LEATHER[2] if px < left + 2 else LEATHER[1]
    if 10 <= px <= 34 and 30 <= py < 54:
        return LEATHER[2] if px < 15 else LEATHER[1] if py < 47 else LEATHER[0]
    if inside(px, py, [(34, 36), (44, 28), (47, 32), (36, 46)]):
        return LEATHER[1]
    for segment in ((46, 14, 56, 8), (48, 42, 60, 42), (44, 56, 54, 61)):
        if near_segment(px, py, segment, 1.5):
            return WHITE
    return None


def jump(x, y):
    px, py = x + 0.5, y + 0.5
    # Low step on the left, high step on the right.
    for left, top, right in ((3, 52, 22), (42, 40, 61)):
        if left <= px <= right and top <= py <= 61:
            return WOOD[3] if py < top + 3 else WOOD[0] if px > right - 3 else WOOD[2]
    shoe = boot(px, py, 2, 24)
    if shoe is not None:
        return shoe
    # Arc from the boot to the high step.
    ring = math.hypot((px - 37) / 21, (py - 32) / 22)
    if 0.84 <= ring <= 1.0 and py < 32 and px > 22:
        return WHITE
    if inside(px, py, [(50, 24), (63, 30), (54, 38)]):
        return WHITE
    return None


def fitted(draw):
    """Shrink a full-canvas drawing about the centre so it and its outline fit the item margin (asserted below)."""
    scale = 31.5 / 28
    return lambda x, y: draw(32 + (x + 0.5 - 32) * scale - 0.5, 32 + (y + 0.5 - 32) * scale - 0.5)


ICONS = {"attack": attack, "second_wind": fitted(second_wind), "surge": fitted(surge), "parry": fitted(parry),
         "opportunity": fitted(opportunity), "mark": fitted(mark), "shock": fitted(shock),
         "disengage": fitted(disengage), "shove": fitted(shove), "jump": fitted(jump), "potion": potion}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    record = json.loads((Path(__file__).parent / "skill_icon_generation.json").read_text())
    assert [icon["id"] for icon in record["icons"]] == list(ICONS)
    args.destination.mkdir(parents=True, exist_ok=True)
    for action, draw in ICONS.items():
        image = outlined(draw)
        bounds = image.getbbox()
        assert bounds and min(bounds[:2]) >= 2 and max(bounds[2:]) <= SIZE - 2, (action, bounds)
        image.save(args.destination / f"{action}.png")
    print(json.dumps({"icons": len(ICONS), "canvas": [SIZE, SIZE]}))
