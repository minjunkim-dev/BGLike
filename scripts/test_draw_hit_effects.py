"""Seam A: the public CLI of scenes/combat/art/sources/effects/draw_hit_effects.py (docs/design/pixel-art.md, 타격 이펙트 절)."""

from pathlib import Path
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scenes/combat/art/sources/effects/draw_hit_effects.py"
RECORD = ROOT / "scenes/combat/art/sources/effects/hit_effect_generation.json"
FRAMES = ("000.png", "001.png", "002.png")


def run_generator(output):
    subprocess.run([sys.executable, str(GENERATOR), str(output)], check=True, capture_output=True)


def read_rgba(path):
    """Return (width, height, rows of (r, g, b, a)) from an 8-bit RGBA PNG without filters."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError("PNG 서명이 없음")
    position = 8
    header = None
    compressed = b""
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        body = data[position + 8:position + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed += body
        position += 12 + length
    width, height, depth, color, _, _, _ = header
    if (depth, color) != (8, 6):
        raise AssertionError("8비트 RGBA가 아님")
    raw = zlib.decompress(compressed)
    stride = width * 4 + 1
    rows = []
    for y in range(height):
        line = raw[y * stride:(y + 1) * stride]
        if line[0] != 0:
            raise AssertionError("필터 종류가 0이 아님")
        rows.append([tuple(line[1 + x * 4:5 + x * 4]) for x in range(width)])
    return width, height, rows


class DrawHitEffectsTest(unittest.TestCase):
    def test_writes_exactly_the_three_flash_frames(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            names = sorted(path.name for path in (Path(output) / "hit_flash").iterdir())
            self.assertEqual(names, list(FRAMES))

    def test_same_command_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            run_generator(Path(first))
            run_generator(Path(second))
            for name in FRAMES:
                self.assertEqual((Path(first) / "hit_flash" / name).read_bytes(),
                                 (Path(second) / "hit_flash" / name).read_bytes(), name)

    def test_frames_are_48_square_rgba_with_hard_alpha(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in FRAMES:
                width, height, rows = read_rgba(Path(output) / "hit_flash" / name)
                self.assertEqual((width, height), (48, 48), name)
                alphas = {pixel[3] for row in rows for pixel in row}
                self.assertTrue(alphas <= {0, 255}, name)
                self.assertIn(255, alphas, name)

    def test_art_stays_inside_the_center_44_and_uses_the_recorded_palette(self):
        palette = {tuple(color) for color in json.loads(RECORD.read_text())["spec"]["palette"]}
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in FRAMES:
                _, _, rows = read_rgba(Path(output) / "hit_flash" / name)
                for y, row in enumerate(rows):
                    for x, (red, green, blue, alpha) in enumerate(row):
                        if alpha == 0:
                            continue
                        self.assertTrue(2 <= x < 46 and 2 <= y < 46, (name, x, y))
                        self.assertIn((red, green, blue), palette, (name, x, y))

    def test_committed_flash_pngs_equal_the_script_output(self):
        committed = ROOT / "scenes/combat/art/effects/hit_flash"
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in FRAMES:
                self.assertEqual((committed / name).read_bytes(), (Path(output) / "hit_flash" / name).read_bytes(), name)


if __name__ == "__main__":
    unittest.main()
