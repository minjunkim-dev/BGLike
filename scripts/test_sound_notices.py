"""Every shipped sound effect must be listed in THIRD_PARTY_NOTICES.md with its origin."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def sound_files(root: Path = ROOT):
    """Sound effect OGGs under scenes/**/audio, not counting source material in sources/."""
    return sorted(path for path in (root / "scenes").rglob("audio/*.ogg"))


def unlisted(notices: str, root: Path = ROOT):
    """Files whose repo-relative path (or directory plus short name in a grouped row) is missing."""
    missing = []
    for path in sound_files(root):
        relative = path.relative_to(root).as_posix()
        short = f"`{path.name}`"
        directory = f"`{path.parent.relative_to(root).as_posix()}/{path.name}`"
        if directory not in notices and not any(
                short in row and f"`{path.parent.relative_to(root).as_posix()}/" in row
                for row in notices.splitlines()):
            missing.append(relative)
    return missing


class SoundNoticeTests(unittest.TestCase):
    def test_every_sound_is_listed(self):
        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        self.assertEqual(unlisted(notices), [])

    def test_missing_entry_is_reported(self):
        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        trimmed = re.sub(r"`step_water\.ogg`", "`gone`", notices)
        self.assertEqual(unlisted(trimmed), ["scenes/combat/audio/step_water.ogg"])

    def test_sounds_exist(self):
        self.assertGreater(len(sound_files()), 20)


if __name__ == "__main__":
    unittest.main()
