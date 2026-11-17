"""Seam A: the public CLI of scenes/ui/art/sources/draw_menu_art.py (docs/design/pixel-art.md, UI 절, #557)."""

from pathlib import Path
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scenes/ui/art/sources/draw_menu_art.py"
SPEC = json.loads((ROOT / "scenes/ui/art/sources/menu_art_generation.json").read_text(encoding="utf-8"))
FILES = ("frames/slider_track.png", "frames/slider_grabber.png",
         "frames/slider_grabber_highlight.png", "title/logo.png")


def run_generator(output):
    subprocess.run([sys.executable, str(GENERATOR), str(output)], check=True, capture_output=True)


def hex_rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


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


class DrawMenuArtTest(unittest.TestCase):
    def test_same_command_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            run_generator(Path(first))
            run_generator(Path(second))
            for name in FILES:
                digest_first = hashlib.sha256((Path(first) / name).read_bytes()).hexdigest()
                digest_second = hashlib.sha256((Path(second) / name).read_bytes()).hexdigest()
                self.assertEqual(digest_first, digest_second, name)

    def test_sizes_are_8_bit_rgba_as_specified(self):
        expected = {
            "frames/slider_track.png": tuple(SPEC["slider"]["track_size"]),
            "frames/slider_grabber.png": tuple(SPEC["slider"]["grabber_size"]),
            "frames/slider_grabber_highlight.png": tuple(SPEC["slider"]["grabber_size"]),
            "title/logo.png": tuple(SPEC["logo"]["size"]),
        }
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name, size in expected.items():
                width, height, _ = read_pixels(Path(output) / name)
                self.assertEqual((width, height), size, name)

    def test_track_outline_is_unbroken_along_each_side(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            _, _, rows = read_pixels(Path(output) / "frames/slider_track.png")
            outline = round(SPEC["slider"]["track_gray"]["outline"] * 255)
            last = len(rows) - 1
            edges = [rows[0], rows[last], [row[0] for row in rows], [row[last] for row in rows]]
            for side in edges:
                # The 1px corner cuts make the first and last pixel of each side transparent.
                self.assertEqual(side[0][3], 0)
                self.assertEqual(side[-1][3], 0)
                self.assertTrue(all(p[3] == 255 and p[0] == outline for p in side[1:-1]))

    def test_track_is_grayscale(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            _, _, rows = read_pixels(Path(output) / "frames/slider_track.png")
            allowed = {round(v * 255) for v in SPEC["slider"]["track_gray"].values()}
            for row in rows:
                for r, g, b, a in row:
                    if a:
                        self.assertTrue(r == g == b and r in allowed, (r, g, b))

    def test_grabbers_use_only_spec_colors(self):
        colors = SPEC["slider"]["grabber_colors"]
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name, face in (("slider_grabber", "face"), ("slider_grabber_highlight", "highlight_face")):
                _, _, rows = read_pixels(Path(output) / f"frames/{name}.png")
                allowed = {hex_rgb(colors[key]) for key in ("outline", face, "bright_edge")}
                used = {p[:3] for row in rows for p in row if p[3] == 255}
                self.assertTrue(used <= allowed, (name, used - allowed))
                self.assertIn(hex_rgb(colors[face]), used, name)
                self.assertTrue(all(p[3] in (0, 255) for row in rows for p in row), name)

    def test_logo_uses_only_palette_colors(self):
        palette = {hex_rgb(v) for v in SPEC["logo"]["palette"].values()}
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            _, _, rows = read_pixels(Path(output) / "title/logo.png")
            self.assertTrue(all(p[3] in (0, 255) for row in rows for p in row))
            used = {p[:3] for row in rows for p in row if p[3] == 255}
            self.assertTrue(used <= palette, used - palette)

    def test_logo_spells_the_specified_text(self):
        logo = SPEC["logo"]
        cell = logo["cell"]
        cols, cell_rows = logo["glyph_cells"]
        pitch = (cols + logo["gap_cells"]) * cell
        face = hex_rgb(logo["palette"]["face"])
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            _, _, rows = read_pixels(Path(output) / "title/logo.png")
        for index, letter in enumerate(logo["text"]):
            for cy in range(cell_rows):
                for cx in range(cols):
                    x = logo["origin"][0] + index * pitch + cx * cell + cell // 2
                    y = logo["origin"][1] + cy * cell + cell // 2
                    pixel = rows[y][x]
                    filled = pixel[3] == 255 and pixel[:3] == face
                    wanted = logo["glyphs"][letter][cy][cx] == "X"
                    self.assertEqual(filled, wanted, f"{letter} cell ({cx},{cy})")


if __name__ == "__main__":
    unittest.main()
