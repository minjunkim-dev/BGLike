"""Draw the skill and common action icons pixel by pixel in the item icon style (#384).

Same rules as draw_item_icons.py: 64px design grid on the 48px canvas, the item palette, upper-left light, 2px dark outline,
no anti-aliasing and no generative model. Attack and potion reuse the item sword and potion.

#517: lines inside a picture (blades, shafts, white effect lines, arcs) are at least 3px wide on the 48px canvas, so every
icon keeps at least 10% of the canvas as coloured pixels inside its outline. Cross slash is a large X and the opportunity
attack is a large eye, so neither reads as the item sword.
"""
import argparse
import json
import math
from pathlib import Path

from draw_item_icons import BRASS, INDIGO, LEATHER, RED, ROOT2, SIZE, STEEL, TEAL, WOOD, outlined, potion, sword

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


def short_sword(u, v, length, half=3.0):
    """Steel blade along +u from a brass guard at u=0, leather grip below. None outside."""
    if 0 <= u <= length and abs(v) <= min(half, (length - u) * 0.7):
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


def sweep(x, y):
    px, py = x + 0.5, y + 0.5
    # Short sword pointing up-right at the lower right; a white half-moon trail sweeps from the left over the top.
    u, v = rotated(x, y, 40, 46)
    blade = short_sword(u + 2, v, 22, 4.0)
    if blade is not None:
        return blade
    ring = math.hypot(px - 30, py - 38)
    if 20 <= ring <= 25.5 and py <= 38 and px <= 44:
        return WHITE if ring >= 22.5 else STEEL[3]
    return None


def cross_slash(x, y):
    # Two short swords crossed in an X; the up-right blade lies on top.
    for mirrored in (x, 63 - x):
        u, v = rotated(mirrored, y, 32, 28)
        blade = short_sword(u + 14, v, 34, 4.2)
        if blade is not None:
            return blade
    return None


def steel_charge(x, y):
    px, py = x + 0.5, y + 0.5
    # Short sword thrusting to the right with white speed lines trailing on the left.
    blade = short_sword(px - 26, py - 30, 34, 4.0)
    if blade is not None:
        return blade
    for line_y, start, length in ((13, 4, 18), (47, 2, 14), (55, 8, 18)):
        if abs(py - line_y) <= 2.0 and start <= px <= start + length:
            return WHITE
    return None


def holy_veil(x, y):
    px, py = x + 0.5, y + 0.5
    # Heater shield: steel rim, indigo face and a brass cross.
    if not inside(px, py, [(12, 6), (52, 6), (52, 32), (32, 60), (12, 32)]):
        return None
    if not inside(px, py, [(16, 10), (48, 10), (48, 31), (32, 54), (16, 31)]):
        return STEEL[4] if px + py < 50 else STEEL[3] if px + py < 76 else STEEL[2]
    if abs(px - 32) <= 2.6 and 14 <= py <= 48 or abs(py - 24) <= 2.6 and 20 <= px <= 44:
        return BRASS[2] if px + py < 56 else BRASS[1]
    return INDIGO[1] if px + py < 60 else INDIGO[0]


def battle_cry(x, y):
    px, py = x + 0.5, y + 0.5
    # Red banner on a wooden pole with a brass knob, white shout lines on the right.
    if math.hypot(px - 16, py - 11) <= 3.5:
        return BRASS[2] if px + py < 27 else BRASS[1]
    if 14 <= px <= 18 and 14 <= py <= 58:
        return WOOD[3] if px < 16 else WOOD[1]
    if inside(px, py, [(18, 16), (44, 18), (37, 27), (44, 36), (18, 35)]):
        return RED[3] if py < 20 else RED[2] if py < 29 else RED[1]
    for segment in ((47, 20, 54, 15), (48, 28, 56, 28), (47, 36, 54, 41)):
        if near_segment(px, py, segment, 1.5):
            return WHITE
    return None


def opportunity(x, y):
    px, py = x + 0.5, y + 0.5
    # Watching eye across the upper half: almond white, teal iris, dark pupil with a glint.
    ex, ey = 32, 19
    if abs(px - ex) <= 19 and abs(py - ey) <= 11 * max(0.0, 1 - ((px - ex) / 19) ** 2) ** 0.5:
        iris = math.hypot(px - ex, py - ey)
        if iris <= 4.5:
            return WHITE if math.hypot(px - (ex - 2), py - (ey - 2)) <= 1.4 else INDIGO[0]
        if iris <= 8.5:
            return TEAL[1] if px + py < ex + ey else TEAL[0]
        return WHITE if py < ey else STEEL[3]
    # A small sword below the eye, blade pointing down-left: the strike it waits to make.
    u, v = rotated(x, y, 40, 45)
    return short_sword(-u, v, 16, 3.4)


def counter(x, y):
    px, py = x + 0.5, y + 0.5
    # White return arrow at the top right: in from the left, round the right end and back to the left.
    ring = math.hypot(px - 42, py - 14)
    if 6.5 <= ring <= 11 and px >= 42:
        return WHITE if ring >= 8.7 else STEEL[3]
    if 3 <= py <= 7.5 and 24 <= px < 42:
        return WHITE
    if 20.5 <= py <= 25 and 34 <= px < 42:
        return STEEL[3]
    if inside(px, py, [(22, 22.75), (36, 14), (36, 31.5)]):
        return WHITE if py < 22.5 else STEEL[3]
    # Short sword striking back up to the right from the lower left.
    u, v = rotated(x, y, 20, 47)
    return short_sword(u, v, 15, 4.0)


def aegisal(x, y):
    px, py = x + 0.5, y + 0.5
    # Two short arrows (aegisal) flying up-right side by side: wooden shaft, steel head, teal fletching.
    for cx, cy in ((24, 30), (36, 42)):
        u, v = rotated(x, y, cx, cy)
        if -12 <= u <= 6 and abs(v) <= 2.8:
            return WOOD[3] if v < 0 else WOOD[1]
        if 6 < u <= 15 and abs(v) <= (15 - u) * 1.0:
            return STEEL[4] if v < 0 else STEEL[2]
        if -16 <= u <= -9 and 2.8 < abs(v) <= 7:
            return TEAL[1] if v < 0 else TEAL[0]
    # Brass half tube (tongah) that guides the short arrow, along the lower left.
    u, v = rotated(x, y, 22, 46)
    if -12 <= u <= 10 and 3.5 <= v <= 9 and px > 4:
        return BRASS[2] if v < 6.2 else BRASS[1]
    return None


def bow_bash(x, y):
    px, py = x + 0.5, y + 0.5
    # Wooden bow limb swung like a club: an arc in the upper left with a brass grip and a thin string.
    ring = math.hypot(px - 46, py - 46)
    if 24 <= ring <= 32 and px <= 46 and py <= 46:
        if math.hypot(px - 26, py - 26) <= 5.5:
            return BRASS[2] if px + py < 52 else BRASS[1]
        return WOOD[3] if ring < 27.5 else WOOD[1]
    if near_segment(px, py, (46, 17, 17, 46), 1.8):
        return STEEL[3]
    # White impact lines where the limb strikes at the lower right.
    for segment in ((50, 30, 58, 26.5), (50, 40, 58.5, 42), (44, 50, 51, 57)):
        if near_segment(px, py, segment, 1.9):
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


def oil_throw(x, y):
    px, py = x + 0.5, y + 0.5
    # Glass bottle tipped mouth-down toward the lower right: u runs along the axis from base to mouth, v across it.
    cx, cy = 25, 17
    u = (px - cx + py - cy) / ROOT2
    v = (py - cy - (px - cx)) / ROOT2
    lip = 12 <= u <= 15 and abs(v) <= 5.2
    neck = 5 <= u < 12 and abs(v) <= 3.6
    body = -13 <= u < 5 and abs(v) <= 8.2 and not (u < -9 and abs(v) > 8.2 - (-9 - u) * 1.6)
    if lip:
        return STEEL[3] if v < 0 else STEEL[2]
    if neck or body:
        edge = abs(v) > (3.6 if neck else 8.2) - 1.6
        if v < -(3.6 if neck else 8.2) + 1.6 and u < 10:
            return STEEL[4] if v < -(3.6 if neck else 8.2) + 0.8 else STEEL[3]
        # Oil settles on the low side of the tipped bottle.
        if py > 19 and not edge:
            return BRASS[2] if py < 22 else BRASS[1]
        return TEAL[1] if edge and v > 0 else TEAL[0] if v > 0 else INDIGO[1]
    # Oil stream falling from the mouth and the stain on the floor.
    if 31.5 <= px <= 35.5 and 28 <= py <= 48:
        return BRASS[2] if px < 33 else BRASS[1]
    stain = math.hypot((px - 36) / 21, (py - 50) / 6.5)
    if stain <= 1:
        if stain > 0.82:
            return BRASS[0]
        return BRASS[2] if py < 48 and px < 30 else BRASS[1]
    if math.hypot((px - 18) / 5, (py - 54) / 2.5) <= 1:
        return BRASS[0]
    return None


def trick_arrow(x, y):
    # One arrow flying up-right with a two-colour head (red fire half, teal water half) and teal fletching.
    u, v = rotated(x, y, 28, 36)
    if -16 <= u <= 6 and abs(v) <= 3.6:
        return WOOD[3] if v < 0 else WOOD[1]
    if 6 < u <= 19 and abs(v) <= (19 - u) * 1.25:
        return RED[3] if v < 0 else TEAL[1]
    if -20 <= u <= -11 and 3.6 < abs(v) <= 9:
        return TEAL[1] if v < 0 else TEAL[0]
    # Two small question-mark-like sparks (the unreliable magic) at the lower left.
    px, py = x + 0.5, y + 0.5
    for cx, cy in ((10, 18), (16, 10)):
        if math.hypot(px - cx, py - cy) <= 4.2:
            return WHITE
    return None


def firework_arrow(x, y):
    px, py = x + 0.5, y + 0.5
    # Arrow rising up-right toward a starburst: the head sits inside a ring of rays.
    u, v = rotated(x, y, 20, 44)
    if -14 <= u <= 10 and abs(v) <= 2.2:
        return WOOD[3] if v < 0 else WOOD[1]
    if 10 < u <= 18 and abs(v) <= (18 - u) * 0.8:
        return STEEL[4] if v < 0 else STEEL[2]
    if -18 <= u <= -11 and 2.2 < abs(v) <= 6:
        return TEAL[1] if v < 0 else TEAL[0]
    # Burst at the upper right: eight rays with a brass core.
    cx, cy = 44, 20
    if math.hypot(px - cx, py - cy) <= 4:
        return BRASS[2] if px + py < cx + cy else BRASS[1]
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        norm = math.hypot(dx, dy)
        segment = (cx + dx / norm * 7, cy + dy / norm * 7, cx + dx / norm * 15, cy + dy / norm * 15)
        if near_segment(px, py, segment, 2.1):
            return RED[3] if dx * dy else WHITE
    return None


def whistle(x, y):
    px, py = x + 0.5, y + 0.5
    # Whistling arrow (hyoshi) flying up-right: wooden shaft, steel head, a brass hollow bulb behind the head and teal fletching.
    u, v = rotated(x, y, 28, 36)
    if math.hypot((u - 6) / 7.2, v / 5.2) <= 1:
        return LEATHER[0] if math.hypot(u - 6, v - 2.6) <= 1.3 else (BRASS[2] if v < 0 else BRASS[1])
    if -16 <= u <= 12 and abs(v) <= 3.4:
        return WOOD[3] if v < 0 else WOOD[1]
    if 12 < u <= 20 and abs(v) <= (20 - u) * 1.2:
        return STEEL[4] if v < 0 else STEEL[2]
    if -20 <= u <= -11 and 3.4 < abs(v) <= 8.5:
        return TEAL[1] if v < 0 else TEAL[0]
    # Two sound arcs leaving the bulb hole toward the lower right.
    cx, cy = 28 + 6 / math.sqrt(2), 36 - 6 / math.sqrt(2)
    dx, dy = px - cx, py - cy
    radius = math.hypot(dx, dy)
    if radius > 0 and (dx + dy) / math.sqrt(2) / radius >= math.cos(math.radians(38)):
        for ring in (10, 15.5):
            if abs(radius - ring) <= 1.8:
                return WHITE
    return None


def fitted(draw):
    """Shrink a full-canvas drawing about the centre so it and its outline fit the item margin (asserted below)."""
    scale = 31.5 / 28
    return lambda x, y: draw(32 + (x + 0.5 - 32) * scale - 0.5, 32 + (y + 0.5 - 32) * scale - 0.5)


ICONS = {"attack": attack, "second_wind": fitted(second_wind), "sweep": fitted(sweep), "cross_slash": fitted(cross_slash),
         "steel_charge": fitted(steel_charge), "holy_veil": fitted(holy_veil), "battle_cry": fitted(battle_cry),
         "opportunity": fitted(opportunity), "counter": fitted(counter), "aegisal": fitted(aegisal),
         "bow_bash": fitted(bow_bash), "shove": fitted(shove), "jump": fitted(jump), "potion": potion,
         "oil_throw": oil_throw, "trick_arrow": fitted(trick_arrow), "firework_arrow": fitted(firework_arrow),
         "whistle": fitted(whistle)}

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
