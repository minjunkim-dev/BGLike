"""Build and smoke a verification-only PCK, with source and dependency evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


def command(argv, cwd):
    result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=300, check=False)
    if result.returncode or re.search(r"(?:ERROR|WARNING|SCRIPT ERROR):", result.stdout + result.stderr):
        raise ValueError(f"Command failed validation: {argv[0]}")
    return result.stdout.strip()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def package(root, output, version, source_sha, godot, engine_hash):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-(?:alpha|beta)\.[1-9][0-9]*", version):
        raise ValueError("Expected vX.Y.Z-alpha.N or vX.Y.Z-beta.N")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or command(["git", "rev-parse", "HEAD"], root) != source_sha:
        raise ValueError("Build checkout differs from full source SHA")
    if command(["git", "status", "--porcelain", "--untracked-files=all"], root):
        raise ValueError("Build checkout has uncommitted files")
    if not re.fullmatch(r"[0-9a-f]{64}", engine_hash):
        raise ValueError("Invalid engine archive checksum")
    engine = command([godot, "--version"], root)
    if not engine.startswith("4.7.2.stable.official."):
        raise ValueError("Expected official Godot 4.7.2")
    lfs_files = command(["git", "lfs", "ls-files", "--long"], root)
    command(["git", "lfs", "fsck"], root)
    for name in command(["git", "ls-files"], root).splitlines():
        path = root / name
        if path.is_file() and path.read_bytes().startswith(b"version https://git-lfs.github.com/spec/v1\n"):
            raise ValueError("Unresolved LFS pointer")
    command([godot, "--headless", "--path", str(root), "--import"], root)
    with tempfile.TemporaryDirectory(prefix="bglike-pck-") as folder:
        temporary = Path(folder)
        pck = temporary / "bglike.pck"
        command([godot, "--headless", "--path", str(root), "--export-pack", "Verification PCK", str(pck)], root)
        if not pck.is_file() or not pck.stat().st_size:
            raise ValueError("Export did not create a PCK")
        item_hash = sha256((root / "scenes/combat/item_data.json").read_bytes())
        probe = temporary / "verify.gd"
        probe.write_text('''extends SceneTree
func _initialize() -> void:
    var path := "res://scenes/combat/item_data.json"
    if not FileAccess.file_exists(path):
        quit(1)
        return
    var data := FileAccess.get_file_as_bytes(path)
    var hash := HashingContext.new()
    hash.start(HashingContext.HASH_SHA256)
    hash.update(data)
    if hash.finish().hex_encode() != "%s":
        quit(1)
        return
    if ResourceLoader.load("res://scenes/main.tscn") == null or ResourceLoader.load("res://scenes/combat/audio/hit.ogg") == null:
        quit(1)
        return
    print("PCK_CONTENT_VERIFIED")
    quit()
''' % item_hash, encoding="utf-8")
        verified = command([godot, "--headless", "--main-pack", str(pck), "--script", str(probe)], temporary)
        if "PCK_CONTENT_VERIFIED" not in verified:
            raise ValueError("Missing PCK content verification")
        command([godot, "--headless", "--main-pack", str(pck), "--quit-after", "3"], temporary)
        files = {"bglike.pck": pck.read_bytes(), "COPYRIGHT.md": (root / "COPYRIGHT.md").read_bytes(),
                 "THIRD_PARTY_NOTICES.md": (root / "THIRD_PARTY_NOTICES.md").read_bytes(),
                 "kenney_license.txt": (root / "scenes/combat/audio/kenney_license.txt").read_bytes()}
        metadata = {"version": version, "source_sha": source_sha, "engine": engine,
                    "engine_archive_sha256": engine_hash, "preset": "Verification PCK",
                    "preset_sha256": sha256((root / "export_presets.cfg").read_bytes()),
                    "lfs_files": lfs_files.splitlines(), "lfs_fsck": "passed", "item_data_sha256": item_hash,
                    "smoke": "headless isolated main-pack and resource verification passed",
                    "files": {name: sha256(data) for name, data in files.items()}}
        files["metadata.json"] = (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode()
        files["RUN.txt"] = b"Verification package. Install official Godot 4.7.2 Standard separately.\nRun: Godot --main-pack bglike.pck\nNo OS support or release readiness is declared. No engine binary is included.\n"
        output.mkdir(parents=True, exist_ok=True)
        archive = output / f"bglike-{version}-pck.zip"
        if archive.exists() or (output / "SHA256SUMS").exists():
            raise ValueError("Package output already exists")
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as bundle:
            for name, data in files.items():
                bundle.writestr(name, data)
        (output / "SHA256SUMS").write_text(f"{sha256(archive.read_bytes())}  {archive.name}\n", encoding="utf-8")
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        print(package(Path.cwd(), args.output, os.environ["RELEASE_VERSION"], os.environ["SOURCE_SHA"],
                      os.environ["GODOT"], os.environ["ENGINE_ARCHIVE_SHA256"]))
    except (ValueError, OSError, subprocess.SubprocessError, KeyError):
        raise SystemExit("PCK package validation failed")
