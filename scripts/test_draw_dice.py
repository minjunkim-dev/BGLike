"""Seam: the public CLI of scenes/combat/art/sources/dice/draw_dice.py (docs/design/combat/dice-presentation.md, 도트 디자인 절)."""

from pathlib import Path
import hashlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scenes/combat/art/sources/dice/draw_dice.py"
SHEET = ROOT / "docs/design/combat/images/dice_states.png"
SIDES = (4, 6, 8, 10, 12, 20)
STATES = ("rolling", "success", "failure", "absolute_success", "absolute_failure")
SUCCESS = (0x70, 0xC7, 0x6D)
FAILURE = (0xDF, 0x62, 0x56)
GOLD = (0xF4, 0xCF, 0x69)
PURPLE = (0x4A, 0x2A, 0x5C)


def run_generator(*args):
    subprocess.run([sys.executable, str(GENERATOR), *map(str, args)], check=True, capture_output=True)


def read_pixels(path):
    """Return (width, height, rows of (r, g, b, a)) from an 8-bit RGBA PNG written by the generator."""
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


def opaque(rows):
    return {(x, y) for y, row in enumerate(rows) for x, pixel in enumerate(row) if pixel[3] > 0}


def colors(rows):
    return {pixel[:3] for row in rows for pixel in row if pixel[3] > 0}


ROLLING_FRAMES = ("rolling", "rolling_1", "rolling_2", "rolling_3")
ART = ROOT / "scenes/combat/art/dice"


def names():
    return ([f"d{sides}_{state}.png" for sides in SIDES for state in STATES]
            + [f"d{sides}_rolling_{frame}.png" for sides in SIDES for frame in (1, 2, 3)]
            + [f"d{sides}_liquid.png" for sides in SIDES])


class DrawDiceTest(unittest.TestCase):
    def test_same_command_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            run_generator(first)
            run_generator(second)
            for name in names():
                digest_first = hashlib.sha256((Path(first) / name).read_bytes()).hexdigest()
                digest_second = hashlib.sha256((Path(second) / name).read_bytes()).hexdigest()
                self.assertEqual(digest_first, digest_second, name)

    def test_writes_54_files_of_48_by_48_rgba(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(output)
            self.assertEqual(sorted(path.name for path in Path(output).iterdir()), sorted(names()))
            self.assertEqual(len(names()), 54)
            for name in names():
                width, height, _ = read_pixels(Path(output) / name)
                self.assertEqual((width, height), (48, 48), name)

    def test_liquid_mask_stays_inside_the_body(self):
        with tempfile.TemporaryDirectory() as output:
            for_sides = Path(output)
            run_generator(output)
            for sides in SIDES:
                _, _, mask = read_pixels(for_sides / f"d{sides}_liquid.png")
                _, _, body = read_pixels(for_sides / f"d{sides}_success.png")
                mask_pixels = opaque(mask)
                self.assertTrue(mask_pixels, sides)
                self.assertTrue(all(6 <= x <= 41 and 6 <= y <= 41 for x, y in mask_pixels), sides)
                self.assertTrue(mask_pixels <= opaque(body), sides)

    def test_states_differ_by_color_and_bytes(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(output)
            for sides in SIDES:
                found = {}
                for state in STATES:
                    _, _, rows = read_pixels(Path(output) / f"d{sides}_{state}.png")
                    found[state] = colors(rows)
                self.assertIn(SUCCESS, found["success"], sides)
                self.assertIn(FAILURE, found["failure"], sides)
                self.assertIn(GOLD, found["absolute_success"], sides)
                self.assertIn(PURPLE, found["absolute_failure"], sides)
                digests = {hashlib.sha256((Path(output) / f"d{sides}_{state}.png").read_bytes()).hexdigest()
                           for state in STATES}
                self.assertEqual(len(digests), 5, sides)

    def test_rolling_frames_differ_and_all_outputs_match_the_repository(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(output)
            for sides in SIDES:
                digests = set()
                for frame in ROLLING_FRAMES:
                    path = Path(output) / f"d{sides}_{frame}.png"
                    digests.add(hashlib.sha256(path.read_bytes()).hexdigest())
                    _, _, rows = read_pixels(path)
                    _, _, body = read_pixels(Path(output) / f"d{sides}_liquid.png")
                    trail = opaque(rows) - opaque(read_pixels(Path(output) / f"d{sides}_success.png")[2])
                    self.assertTrue(trail, f"{sides} {frame}: 몸체 밖 잔상 픽셀")
                self.assertEqual(len(digests), 4, sides)
            for name in names():
                self.assertEqual((Path(output) / name).read_bytes(), (ART / name).read_bytes(), name)

    def test_sheet_is_6_rows_by_5_columns_and_matches_the_repository_copy(self):
        with tempfile.TemporaryDirectory() as output:
            first = Path(output) / "first.png"
            second = Path(output) / "second.png"
            run_generator("--sheet", first)
            run_generator("--sheet", second)
            width, height, _ = read_pixels(first)
            self.assertEqual((width, height), (4 * 48 * 5, 4 * 48 * 6))
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(first.read_bytes(), SHEET.read_bytes(), "docs/design/combat/images/dice_states.png를 다시 만든다")


if __name__ == "__main__":
    unittest.main()
