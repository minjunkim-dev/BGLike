#!/usr/bin/env python3
"""Draw the skill effects (shield, heal, buff, sweep trail) as RGBA PNGs (docs/design/pixel-art.md, 스킬 효과 절).

Usage: python3 scenes/combat/art/sources/effects/draw_skill_effects.py <output-directory>
Writes <output-directory>/<effect>/000.png ... for shield, heal, buff (64x64, 4 frames each) and
sweep_front, sweep_back (128x64, 3 frames each).

Standard library only. The PNG encoder is the one in draw_hit_effects.py, so the same command writes the same
bytes without Pillow. Palettes come from draw_hit_effects.py and draw_item_icons.py plus the heal green of
CombatUnit.HEAL_COLOR. No anti-aliasing: every pixel is fully opaque or fully transparent. Settings are recorded in
skill_effect_generation.json.
"""

from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from draw_hit_effects import encode_png  # noqa: E402

MARGIN = 2
OUTLINE = (18, 13, 22)
WHITE = (245, 235, 219)
LIGHT = (235, 186, 132)
BRASS = (204, 142, 77)
GREEN = (112, 199, 109)
GREEN_DARK = (60, 128, 72)
GREEN_LIGHT = (176, 230, 150)
RED = (174, 76, 46)
RED_LIGHT = (200, 110, 66)
STEEL = (197, 178, 159)
STEEL_MID = (133, 115, 108)


class Canvas:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.pixels = {}

    def put(self, x, y, color):
        if MARGIN <= x < self.width - MARGIN and MARGIN <= y < self.height - MARGIN:
            self.pixels[(x, y)] = color

    def outline(self):
        """Dark outline on every empty 4-neighbour of a filled pixel."""
        edge = set()
        for x, y in self.pixels:
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) not in self.pixels:
                    edge.add((nx, ny))
        for x, y in edge:
            self.put(x, y, OUTLINE)

    def flipped_vertically(self):
        flipped = Canvas(self.width, self.height)
        for (x, y), color in self.pixels.items():
            flipped.put(x, self.height - 1 - y, color)
        return flipped

    def png(self):
        return encode_png(self.pixels, self.width, self.height)


def ring_value(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2


def shield_frame(index):
    canvas = Canvas(64, 64)
    cx, cy, rx, ry = 32, 34, 24, 24
    for y in range(64):
        for x in range(64):
            d = ring_value(x + 0.5, y + 0.5, cx, cy, rx, ry)
            angle = math.atan2(y + 0.5 - cy, x + 0.5 - cx)
            if index == 0:
                # The dome rises from the ground: only the lower half, thin brass rim.
                if 0.80 <= d <= 1.0 and y >= cy + 4:
                    canvas.put(x, y, BRASS)
            elif index == 1:
                if 0.78 <= d <= 1.0:
                    canvas.put(x, y, LIGHT)
                if 0.80 <= d <= 1.0 and angle < -1.9 and angle > -2.9:
                    canvas.put(x, y, WHITE)
            elif index == 2:
                if 0.74 <= d <= 1.0:
                    canvas.put(x, y, WHITE if d >= 0.88 else LIGHT)
                elif d < 0.74 and (x + y) % 6 == 0:
                    canvas.put(x, y, BRASS)
            else:
                # The rim breaks into dashes that drift outward and fade.
                if 0.86 <= d <= 1.12 and int((angle + math.pi) / (2 * math.pi) * 16) % 2 == 0:
                    canvas.put(x, y, LIGHT if d < 1.0 else BRASS)
    if index == 3:
        for x, y in ((10, 16), (52, 20), (14, 50), (50, 46), (32, 6)):
            canvas.put(x, y, WHITE)
            canvas.put(x + 1, y, WHITE)
    canvas.outline()
    return canvas


def plus(canvas, x, y, color):
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        canvas.put(x + dx, y + dy, color)


def heal_frame(index):
    canvas = Canvas(64, 64)
    # Ground glow: an ellipse ring at the feet that grows and then thins out.
    radius = (10, 14, 18, 20)[index]
    for y in range(64):
        for x in range(64):
            d = ring_value(x + 0.5, y + 0.5, 32, 54, radius, radius / 3.0)
            if 0.72 <= d <= 1.0:
                canvas.put(x, y, GREEN_DARK if index == 3 else GREEN)
    # Crosses rise past the body; later frames have fewer and smaller ones.
    crosses = ((22, 48), (42, 44), (32, 40), (26, 36))
    lift = index * 7
    for number, (x, y) in enumerate(crosses):
        if index == 3 and number % 2:
            continue
        top = y - lift
        if top >= 6:
            plus(canvas, x, top, WHITE if (number + index) % 2 == 0 else GREEN_LIGHT)
    for x, y in ((18, 40), (46, 36), (36, 28)):
        canvas.put(x, y - lift, GREEN_LIGHT)
    canvas.outline()
    return canvas


def chevron(canvas, top, color):
    for step in range(-7, 8):
        for thick in (0, 1):
            canvas.put(32 + step, top + abs(step) + thick, color)


def buff_frame(index):
    canvas = Canvas(64, 64)
    # Two red chevrons climb over the head; the colors blink from frame to frame.
    colors = (RED, RED_LIGHT) if index % 2 == 0 else (RED_LIGHT, WHITE if index == 3 else RED)
    tops = ((24, 12), (18, 24), (12, 18), (8, 12))[index]
    chevron(canvas, tops[0], colors[0])
    if index >= 1:
        chevron(canvas, tops[1], colors[1])
    canvas.outline()
    return canvas


def sweep_front_frame(index):
    canvas = Canvas(128, 64)
    cx, rx, ry = 64, 58, 28
    outer_cy, inner_cy = 26, 17
    for y in range(64):
        for x in range(128):
            if y < outer_cy:
                continue
            outer = ring_value(x + 0.5, y + 0.5, cx, outer_cy, rx, ry)
            inner = ring_value(x + 0.5, y + 0.5, cx, inner_cy, rx, ry)
            if outer > 1.0 or inner <= 1.0:
                continue
            u = (x - (cx - rx)) / (2.0 * rx)
            if index == 0:
                if u < 0.4:
                    canvas.put(x, y, WHITE if inner > 1.12 else STEEL)
            elif index == 1:
                canvas.put(x, y, WHITE if inner > 1.12 else STEEL)
            elif u > 0.3 and (x // 3 + y // 3) % 2 == 0:
                canvas.put(x, y, STEEL if inner > 1.12 else STEEL_MID)
    canvas.outline()
    return canvas


def sweep_back_frame(index):
    return sweep_front_frame(index).flipped_vertically()


EFFECTS = (
    ("shield", 4, shield_frame),
    ("heal", 4, heal_frame),
    ("buff", 4, buff_frame),
    ("sweep_front", 3, sweep_front_frame),
    ("sweep_back", 3, sweep_back_frame),
)


def main(argv):
    if len(argv) != 2:
        print("usage: draw_skill_effects.py <output-directory>", file=sys.stderr)
        return 2
    for folder, count, draw in EFFECTS:
        output = Path(argv[1]) / folder
        output.mkdir(parents=True, exist_ok=True)
        for index in range(count):
            path = output / ("%03d.png" % index)
            path.write_bytes(draw(index).png())
            print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
