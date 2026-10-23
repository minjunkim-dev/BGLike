"""Download and verify one explicit unpublished Draft without remote writes."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

from draft_release import inputs, main_source, read_request, request_artifact, verify_bundle
from package_pck import command


class GitHub:
    repo = "minjunkim-dev/BGLike"

    def request(self, method, path):
        if method != "GET":
            raise ValueError("Verification only supports GET")
        result = subprocess.run(["gh", "api", "--method", "GET", f"repos/{self.repo}/{path}".rstrip("/")],
                                check=True, capture_output=True, timeout=60)
        return json.loads(result.stdout)

    def asset(self, asset_id):
        return self.download(f"releases/assets/{asset_id}", "application/octet-stream")

    def download(self, path, accept="application/json"):
        return subprocess.run(["gh", "api", "--method", "GET", "-H", f"Accept: {accept}",
                               f"repos/{self.repo}/{path}"],
                              check=True, capture_output=True, timeout=60).stdout


def runs(api, request_id, build_id, version, source_sha):
    if request_id is None and build_id is None:
        return {}
    if any(type(value) is not int or value < 1 for value in (request_id, build_id)):
        raise ValueError("Provide positive request and build run IDs together")
    records = {}
    for role, run_id, event, workflow in (("request", request_id, "workflow_dispatch", "draft-release.yml"),
                                          ("build", build_id, "workflow_run", "draft-build.yml")):
        run = api.request("GET", f"actions/runs/{run_id}")
        expected = {"id": run_id, "event": event, "head_branch": "main", "status": "completed",
                    "conclusion": "success", "path": f".github/workflows/{workflow}"}
        if any(run.get(key) != value for key, value in expected.items()) or run.get("head_repository", {}).get("full_name") != api.repo:
            raise ValueError(f"Invalid {role} run")
        main_source(api, run["head_sha"])
        records[role] = run
    attempt = records["request"]["run_attempt"]
    _, artifact = request_artifact(api, request_id, attempt)
    data = api.download(f"actions/artifacts/{artifact['id']}/zip")
    with tempfile.TemporaryDirectory(prefix="bglike-request-") as folder:
        directory = Path(folder)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            if archive.namelist() != ["request.json"] or archive.getinfo("request.json").file_size > 4096:
                raise ValueError("Unexpected request artifact files")
            (directory / "request.json").write_bytes(archive.read("request.json"))
        if read_request(api, directory, request_id, attempt) != (version, source_sha):
            raise ValueError("Request source or version mismatch")
    jobs = api.request("GET", f"actions/runs/{build_id}/jobs?filter=latest&per_page=100")
    if type(jobs.get("total_count")) is not int or not 0 <= jobs["total_count"] <= 100 or len(jobs.get("jobs", [])) != jobs["total_count"]:
        raise ValueError("Incomplete build jobs")
    for name in ("build", "draft"):
        selected = [job for job in jobs["jobs"] if job.get("name") == name]
        if len(selected) != 1 or selected[0].get("status") != "completed" or selected[0].get("conclusion") != "success":
            raise ValueError(f"Unsuccessful {name} job")
    return records


def smoke(archive, godot, output):
    with tempfile.TemporaryDirectory(prefix="bglike-draft-") as folder:
        temporary = Path(folder)
        engine = command([godot, "--version"], temporary)
        if not engine.startswith("4.7.2.stable.official."):
            raise ValueError("Expected official Godot 4.7.2")
        with zipfile.ZipFile(archive) as bundle:
            notices = bundle.read("THIRD_PARTY_NOTICES.md").decode("utf-8")
            if "System Reference Document 5.1" not in notices or "creativecommons.org/licenses/by/4.0" not in notices:
                raise ValueError("Missing SRD attribution")
            pck = temporary / "bglike.pck"
            pck.write_bytes(bundle.read("bglike.pck"))
        home = temporary / "home"
        home.mkdir()
        environment = {"PATH": os.defpath, "HOME": str(home), "TMPDIR": str(temporary),
                       "XDG_CONFIG_HOME": str(home / "config"), "XDG_DATA_HOME": str(home / "data"),
                       "XDG_CACHE_HOME": str(home / "cache")}
        try:
            result = subprocess.run([godot, "--headless", "--main-pack", str(pck), "--quit-after", "3"],
                                    cwd=temporary, env=environment, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=30, check=False)
        except subprocess.TimeoutExpired as error:
            (output / "runtime.log").write_bytes(error.stdout or b"")
            raise ValueError("Headless smoke timed out") from None
        (output / "runtime.log").write_text(result.stdout, encoding="utf-8")
        if result.returncode or re.search(r"(?:ERROR|WARNING|SCRIPT ERROR):", result.stdout):
            raise ValueError("Headless smoke failed; inspect runtime.log")
        return engine


def verify(api, release_id, version, source_sha, output, godot, request_id=None, build_id=None):
    inputs(version, source_sha)
    if type(release_id) is not int or release_id < 1:
        raise ValueError("Expected positive release ID")
    checkout = Path(__file__).resolve().parents[1]
    if output.is_symlink() or output.resolve().is_relative_to(checkout):
        raise ValueError("Output must be outside the checkout and not a symlink")
    output.mkdir(parents=True, exist_ok=True)
    # Clear an earlier success before any new network or runtime check can fail.
    report = output / "result.json"
    if report.is_symlink():
        raise ValueError("Unexpected result symlink")
    if report.exists():
        report.unlink()
    release = api.request("GET", f"releases/{release_id}")
    expected = {"id": release_id, "draft": True, "prerelease": True, "target_commitish": source_sha,
                "name": version, "tag_name": version}
    if any(type(release.get(key)) is not type(value) or release.get(key) != value for key, value in expected.items()):
        raise ValueError("Draft identity mismatch")
    names = {f"bglike-{version}-pck.zip", "SHA256SUMS"}
    assets = release.get("assets", [])
    if len(assets) != 2 or {asset.get("name") for asset in assets} != names:
        raise ValueError("Unexpected Draft assets")
    for asset in assets:
        if type(asset.get("id")) is not int or asset["id"] < 1 or type(asset.get("size")) is not int or not 0 < asset["size"] <= 256 * 1024 * 1024 or asset.get("state") != "uploaded":
            raise ValueError("Invalid Draft asset")
    main_source(api, source_sha)
    run_records = runs(api, request_id, build_id, version, source_sha)
    identity = dict(expected, request_run_id=request_id, build_run_id=build_id,
                    assets=sorted(({key: asset.get(key) for key in ("id", "name", "size", "state", "digest")}
                                   for asset in assets), key=lambda asset: asset["name"]))
    manifest = output / "identity.json"
    if manifest.is_symlink() or (manifest.exists() and json.loads(manifest.read_text()) != identity):
        raise ValueError("Output belongs to another Draft or changed assets")
    if not manifest.exists():
        if any(output.iterdir()):
            raise ValueError("Expected empty output directory")
        with manifest.open("x", encoding="utf-8") as stream:
            json.dump(identity, stream, indent=2, sort_keys=True)
    for name, record in (("release.json", release), ("runs.json", run_records)):
        target = output / name
        if target.is_symlink():
            raise ValueError("Unexpected evidence symlink")
        target.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    directory = output / "assets"
    if directory.is_symlink():
        raise ValueError("Unexpected assets symlink")
    directory.mkdir(exist_ok=True)
    for asset in assets:
        path = directory / asset["name"]
        if path.is_symlink():
            raise ValueError("Unexpected asset symlink")
        if not path.exists():
            data = api.asset(asset["id"])
            if len(data) != asset["size"]:
                raise ValueError("Downloaded asset size mismatch")
            with path.open("xb") as stream:
                stream.write(data)
        data = path.read_bytes()
        digest = "sha256:" + hashlib.sha256(data).hexdigest()
        if len(data) != asset["size"] or (asset.get("digest") and digest != asset["digest"]):
            raise ValueError("Asset size or GitHub digest mismatch; preserve evidence and use a new folder")
    pins = dict(line.split("=", 1) for line in Path(__file__).with_name("godot.env").read_text().splitlines() if "=" in line and not line.startswith("#"))
    files = verify_bundle(directory, version, source_sha, pins["GODOT_LINUX_X86_64_SHA256"])
    if (output / "runtime.log").is_symlink():
        raise ValueError("Unexpected runtime log symlink")
    engine = smoke(files[0], godot, output)
    result = dict(release_id=release_id, version=version, source_sha=source_sha,
                  request_run_id=request_id, build_run_id=build_id, engine=engine,
                  zip_sha256=hashlib.sha256(files[0].read_bytes()).hexdigest(), status="passed",
                  smoke="isolated headless; no human play verification")
    report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-id", type=int, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--request-run-id", type=int)
    parser.add_argument("--build-run-id", type=int)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(GitHub(), args.release_id, args.version, args.source_sha, args.output,
                                args.godot, args.request_run_id, args.build_run_id), indent=2))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Draft verification failed: {error}\n")
