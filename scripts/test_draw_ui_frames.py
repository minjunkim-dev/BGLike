"""Seam A: the public CLI of scenes/ui/art/sources/draw_ui_frames.py (docs/PIXEL_ART.md, UI 절)."""

from pathlib import Path
import hashlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scenes/ui/art/sources/draw_ui_frames.py"
FRAMES = ("panel", "accent_panel", "button")


def run_generator(output):
    subprocess.run([sys.executable, str(GENERATOR), str(output)], check=True, capture_output=True)


def read_pixels(path):
    """Return (width, height, rows of (gray, alpha)) from an 8-bit RGBA PNG written by the generator."""
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
        pixels = []
        for x in range(width):
            red, _, _, alpha = line[1 + x * 4:5 + x * 4]
            pixels.append((red, alpha))
        rows.append(pixels)
    return width, height, rows


class DrawUiFramesTest(unittest.TestCase):
    def test_same_command_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            run_generator(Path(first))
            run_generator(Path(second))
            for name in FRAMES:
                digest_first = hashlib.sha256((Path(first) / f"{name}.png").read_bytes()).hexdigest()
                digest_second = hashlib.sha256((Path(second) / f"{name}.png").read_bytes()).hexdigest()
                self.assertEqual(digest_first, digest_second, name)

    def test_frames_are_16_by_16_rgba(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in FRAMES:
                width, height, _ = read_pixels(Path(output) / f"{name}.png")
                self.assertEqual((width, height), (16, 16), name)

    def test_outline_is_unbroken_along_each_side(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in FRAMES:
                _, _, rows = read_pixels(Path(output) / f"{name}.png")
                edges = [rows[0], rows[15], [row[0] for row in rows], [row[15] for row in rows]]
                for side in edges:
                    # The 2x2 corner cuts make the first and last pixel of each side transparent;
                    # the middle twelve must be opaque outline (gray 0.25 = 64).
                    middle = side[2:14]
                    self.assertTrue(all(alpha == 255 and gray == 64 for gray, alpha in middle), name)


if __name__ == "__main__":
    unittest.main()
