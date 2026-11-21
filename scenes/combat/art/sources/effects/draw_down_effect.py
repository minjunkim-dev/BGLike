#!/usr/bin/env python3
"""Draw the knockout burst (down) as RGBA PNGs (docs/design/pixel-art.md, 전투 불능 효과 절).

Usage: python3 scenes/combat/art/sources/effects/draw_down_effect.py <output-directory>
Writes <output-directory>/down/000.png ... 003.png (64x64, 4 frames).

Standard library only. The PNG encoder is the one in draw_hit_effects.py and the Canvas and palette come from
draw_skill_effects.py, so the same command writes the same bytes without Pillow. No anti-aliasing: every pixel is
fully opaque or fully transparent. Settings are recorded in down_effect_generation.json.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from draw_skill_effects import LIGHT, STEEL, STEEL_MID, WHITE, Canvas  # noqa: E402
from draw_status_effects import bubble  # noqa: E402

# Feet anchor is (32, 56) like every unit effect; the ring is drawn 2px above it (FEET_Y).
FEET_X, FEET_Y = 32, 54
RING_RADIUS = (5, 11, 17, 22)
SHARD_RISE = (4, 12, 20, 28)
SHARDS = ((-10, 0), (-3, -3), (5, -1), (12, 2), (0, 3))


def down_frame(index):
    canvas = Canvas(64, 64)
    # A dust ring bursts outward along the ground and thins into a few puffs.
    radius = RING_RADIUS[index]
    for side in (-1, 1):
        for step in range(3 if index < 3 else 2):
            x = FEET_X + side * (radius - step * 3)
            y = FEET_Y - step
            size = 3 - (1 if index >= 2 else 0) - (1 if step == 2 else 0)
            bubble(canvas, x, y, max(1, size), STEEL if step % 2 == 0 else STEEL_MID, WHITE)
    # Small shards scatter upward and drift apart.
    for number, (dx, dy) in enumerate(SHARDS):
        x = FEET_X + dx * (1 + index // 2)
        y = FEET_Y - 8 + dy - SHARD_RISE[index]
        if index < 3 or number % 2 == 0:
            canvas.put(x, y, WHITE if index == 0 else LIGHT)
            canvas.put(x + 1, y, STEEL)
    if index == 0:
        for dx in (-3, 0, 3):
            canvas.put(FEET_X + dx, FEET_Y - 4, WHITE)
    canvas.outline()
    return canvas


def main(argv):
    if len(argv) != 2:
        print("usage: draw_down_effect.py <output-directory>", file=sys.stderr)
        return 2
    output = Path(argv[1]) / "down"
    output.mkdir(parents=True, exist_ok=True)
    for index in range(4):
        path = output / ("%03d.png" % index)
        path.write_bytes(down_frame(index).png())
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
