"""Seam: the public CLI of scenes/combat/art/sources/effects/draw_down_effect.py (docs/design/pixel-art.md, 전투 불능 효과 절)."""

from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

from test_draw_hit_effects import read_rgba

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scenes/combat/art/sources/effects/draw_down_effect.py"
RECORD = ROOT / "scenes/combat/art/sources/effects/down_effect_generation.json"
COMMITTED = ROOT / "scenes/combat/art/effects"
FRAMES = 4
SIZE = (64, 64)
MARGIN = 2
NAMES = ["%03d.png" % index for index in range(FRAMES)]


def run_generator(output):
    subprocess.run([sys.executable, str(GENERATOR), str(output)], check=True, capture_output=True)


class DrawDownEffectTest(unittest.TestCase):
    def test_writes_only_the_down_folder_with_four_frames(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            self.assertEqual([path.name for path in Path(output).iterdir()], ["down"])
            self.assertEqual(sorted(path.name for path in (Path(output) / "down").iterdir()), NAMES)

    def test_same_command_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            run_generator(Path(first))
            run_generator(Path(second))
            for name in NAMES:
                self.assertEqual((Path(first) / "down" / name).read_bytes(),
                                 (Path(second) / "down" / name).read_bytes(), name)

    def test_frames_have_the_recorded_size_rgba_hard_alpha_and_margin(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in NAMES:
                width, height, rows = read_rgba(Path(output) / "down" / name)
                self.assertEqual((width, height), SIZE, name)
                alphas = {pixel[3] for row in rows for pixel in row}
                self.assertTrue(alphas <= {0, 255}, name)
                self.assertIn(255, alphas, name)
                for y, row in enumerate(rows):
                    for x, pixel in enumerate(row):
                        if pixel[3] and not (MARGIN <= x < width - MARGIN and MARGIN <= y < height - MARGIN):
                            self.fail("margin: %s (%d, %d)" % (name, x, y))

    def test_colors_stay_inside_the_recorded_palette(self):
        record = json.loads(RECORD.read_text())
        palette = {tuple(color) for color in record["effects"]["down"]["palette"]}
        self.assertTrue(palette)
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in NAMES:
                _, _, rows = read_rgba(Path(output) / "down" / name)
                for row in rows:
                    for red, green, blue, alpha in row:
                        if alpha:
                            self.assertIn((red, green, blue), palette, name)

    def test_record_matches_folder_and_frame_count(self):
        record = json.loads(RECORD.read_text())
        self.assertEqual(list(record["effects"]), ["down"])
        entry = record["effects"]["down"]
        self.assertEqual(len(entry["frames"]), FRAMES)
        self.assertEqual(entry["canvas"], list(SIZE))

    def test_committed_pngs_equal_the_script_output(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for name in NAMES:
                committed = COMMITTED / "down" / name
                self.assertTrue(committed.exists(), name)
                self.assertEqual(committed.read_bytes(), (Path(output) / "down" / name).read_bytes(), name)


if __name__ == "__main__":
    unittest.main()
