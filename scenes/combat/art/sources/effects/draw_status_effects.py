#!/usr/bin/env python3
"""Draw the status effects (stun, burn, poison, fallen, ignite) as RGBA PNGs (docs/design/pixel-art.md, 상태 이상 효과 절).

Usage: python3 scenes/combat/art/sources/effects/draw_status_effects.py <output-directory>
Writes <output-directory>/<effect>/000.png ... for stun, burn, poison, ignite (64x64, 4 frames each) and
fallen (64x64, 3 frames).

Standard library only. The PNG encoder is the one in draw_hit_effects.py and the Canvas and palette come from
draw_skill_effects.py, so the same command writes the same bytes without Pillow. No anti-aliasing: every pixel is
fully opaque or fully transparent. Settings are recorded in status_effect_generation.json.
"""

from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from draw_skill_effects import (  # noqa: E402
    BRASS, GREEN, GREEN_DARK, GREEN_LIGHT, LIGHT, RED, RED_LIGHT, STEEL, STEEL_MID, WHITE, Canvas,
)


def star(canvas, x, y, color):
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        canvas.put(x + dx, y + dy, color)


def stun_frame(index):
    canvas = Canvas(64, 64)
    # Three stars circle over the head (unit frames put the head at about y=14).
    for number in range(3):
        angle = (index * 0.5 + number * 2.0 / 3.0) * math.pi
        x = 32 + round(math.cos(angle) * 14)
        y = 12 + round(math.sin(angle) * 4)
        star(canvas, x, y, WHITE if number == index % 3 else (LIGHT if number % 2 else BRASS))
    canvas.outline()
    return canvas


def flame(canvas, cx, base, height, color, tip):
    for row in range(height):
        half = max(0, (height - row) // 3 + (1 if row < height // 2 else 0))
        for x in range(cx - half, cx + half + 1):
            canvas.put(x, base - row, color if row < height - 2 else tip)


def burn_frame(index):
    canvas = Canvas(64, 64)
    # Small flames lick up the body; heights shift every frame so they flicker.
    heights = ((8, 12, 7), (11, 8, 10), (7, 13, 9), (10, 9, 6))[index]
    for number, (cx, base) in enumerate(((22, 52), (32, 46), (42, 52))):
        flame(canvas, cx, base, heights[number], RED, RED_LIGHT)
        flame(canvas, cx, base, max(2, heights[number] - 5), RED_LIGHT, LIGHT)
    if index % 2:
        canvas.put(27, 30 - index, LIGHT)
        canvas.put(38, 26 - index, WHITE)
    canvas.outline()
    return canvas


def bubble(canvas, x, y, radius, fill, shine):
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy <= radius * radius + 1:
                canvas.put(x + dx, y + dy, fill)
    if radius >= 2:
        canvas.put(x - 1, y - 1, shine)


def poison_frame(index):
    canvas = Canvas(64, 64)
    # Bubbles rise from the feet and shrink; a dark puddle ring stays at the ground.
    for dx in range(-14, 15):
        for dy in range(-3, 4):
            if (dx / 14.0) ** 2 + (dy / 3.0) ** 2 <= 1.0 and index != 3:
                canvas.put(32 + dx, 54 + dy, GREEN_DARK)
    rise = index * 7
    for number, (x, y, radius) in enumerate(((22, 50, 3), (34, 44, 2), (42, 48, 3), (28, 38, 2))):
        top = y - rise
        if top >= 6:
            bubble(canvas, x, top, radius - (1 if index == 3 and radius > 2 else 0),
                   GREEN if (number + index) % 2 == 0 else GREEN_LIGHT, WHITE)
    canvas.outline()
    return canvas


def fallen_frame(index):
    canvas = Canvas(64, 64)
    # A dust cloud bursts at the feet, spreads sideways and thins out.
    spread = (6, 12, 17)[index]
    for side in (-1, 1):
        for step in range(3):
            x = 32 + side * (spread - step * 4)
            y = 54 - step * (2 if index < 2 else 1)
            bubble(canvas, x, y, 3 - step if index < 2 else 2 - min(step, 1), STEEL if step % 2 == 0 else STEEL_MID, WHITE)
    if index == 0:
        for dx in (-2, 0, 2):
            canvas.put(32 + dx, 50, WHITE)
    canvas.outline()
    return canvas


def ignite_frame(index):
    canvas = Canvas(64, 64)
    # A pillar of fire bursts from the oil tile: it climbs, widens at the base and then breaks into sparks.
    heights = (14, 28, 36, 24)[index]
    width = (6, 9, 11, 9)[index]
    base = 54
    for row in range(heights):
        half = max(1, round(width * (1.0 - row / (heights + 6.0))))
        wobble = ((row + index) % 3) - 1 if row > 6 else 0
        for x in range(32 - half + wobble, 32 + half + wobble + 1):
            if index == 3 and (x + row) % 3 == 0:
                continue
            color = RED if row < heights * 0.5 else (RED_LIGHT if row < heights - 4 else LIGHT)
            canvas.put(x, base - row, color)
    for row in range(0, heights // 2, 2):
        canvas.put(32, base - row, WHITE if index < 3 else LIGHT)
    for x, y in ((18, 40), (46, 36), (24, 24), (42, 22)):
        if index >= 2:
            canvas.put(x, y - (index - 2) * 4, LIGHT)
            canvas.put(x + 1, y - (index - 2) * 4, BRASS)
    canvas.outline()
    return canvas


EFFECTS = (
    ("stun", 4, stun_frame),
    ("burn", 4, burn_frame),
    ("poison", 4, poison_frame),
    ("fallen", 3, fallen_frame),
    ("ignite", 4, ignite_frame),
)


def main(argv):
    if len(argv) != 2:
        print("usage: draw_status_effects.py <output-directory>", file=sys.stderr)
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
