"""Seam: the public CLI of scenes/combat/art/sources/effects/draw_status_effects.py (docs/design/pixel-art.md, 상태 이상 효과 절)."""

from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

from test_draw_hit_effects import read_rgba

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scenes/combat/art/sources/effects/draw_status_effects.py"
RECORD = ROOT / "scenes/combat/art/sources/effects/status_effect_generation.json"
COMMITTED = ROOT / "scenes/combat/art/effects"
# folder -> (frame count, (width, height))
EFFECTS = {
    "stun": (4, (64, 64)),
    "burn": (4, (64, 64)),
    "poison": (4, (64, 64)),
    "fallen": (3, (64, 64)),
    "ignite": (4, (64, 64)),
}
MARGIN = 2


def run_generator(output):
    subprocess.run([sys.executable, str(GENERATOR), str(output)], check=True, capture_output=True)


def names(count):
    return ["%03d.png" % index for index in range(count)]


class DrawStatusEffectsTest(unittest.TestCase):
    def test_writes_exactly_the_five_status_folders_with_their_frames(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            self.assertEqual(sorted(path.name for path in Path(output).iterdir()), sorted(EFFECTS))
            for folder, (count, _) in EFFECTS.items():
                found = sorted(path.name for path in (Path(output) / folder).iterdir())
                self.assertEqual(found, names(count), folder)

    def test_same_command_writes_same_bytes(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            run_generator(Path(first))
            run_generator(Path(second))
            for folder, (count, _) in EFFECTS.items():
                for name in names(count):
                    self.assertEqual((Path(first) / folder / name).read_bytes(),
                                     (Path(second) / folder / name).read_bytes(), (folder, name))

    def test_frames_have_the_recorded_size_rgba_hard_alpha_and_margin(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for folder, (count, size) in EFFECTS.items():
                for name in names(count):
                    width, height, rows = read_rgba(Path(output) / folder / name)
                    self.assertEqual((width, height), size, (folder, name))
                    alphas = {pixel[3] for row in rows for pixel in row}
                    self.assertTrue(alphas <= {0, 255}, (folder, name))
                    self.assertIn(255, alphas, (folder, name))
                    for y, row in enumerate(rows):
                        for x, pixel in enumerate(row):
                            if pixel[3] and not (MARGIN <= x < width - MARGIN and MARGIN <= y < height - MARGIN):
                                self.fail("margin: %s/%s (%d, %d)" % (folder, name, x, y))

    def test_colors_stay_inside_the_recorded_palette(self):
        record = json.loads(RECORD.read_text())
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for folder, (count, _) in EFFECTS.items():
                palette = {tuple(color) for color in record["effects"][folder]["palette"]}
                self.assertTrue(palette, folder)
                for name in names(count):
                    _, _, rows = read_rgba(Path(output) / folder / name)
                    for row in rows:
                        for red, green, blue, alpha in row:
                            if alpha:
                                self.assertIn((red, green, blue), palette, (folder, name))

    def test_record_matches_folders_and_frame_counts(self):
        record = json.loads(RECORD.read_text())
        self.assertEqual(sorted(record["effects"]), sorted(EFFECTS))
        for folder, (count, size) in EFFECTS.items():
            entry = record["effects"][folder]
            self.assertEqual(len(entry["frames"]), count, folder)
            self.assertEqual(entry["canvas"], list(size), folder)

    def test_frame_counts_match_the_game_table(self):
        gd = (ROOT / "scenes/combat/hit_effects.gd").read_text()
        start = gd.index("const STATUS_FRAME_COUNTS")
        line = gd[start:gd.index("\n", start)]
        for folder, (count, _) in EFFECTS.items():
            self.assertIn('"%s": %d' % (folder, count), line, folder)

    def test_committed_pngs_equal_the_script_output(self):
        with tempfile.TemporaryDirectory() as output:
            run_generator(Path(output))
            for folder, (count, _) in EFFECTS.items():
                for name in names(count):
                    committed = COMMITTED / folder / name
                    self.assertTrue(committed.exists(), (folder, name))
                    self.assertEqual(committed.read_bytes(), (Path(output) / folder / name).read_bytes(), (folder, name))


if __name__ == "__main__":
    unittest.main()
