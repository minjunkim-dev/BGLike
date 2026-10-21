"""Trusted-main-only, fail-closed creation of an unpublished verification Draft."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request
import zipfile


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self, repo, token):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
            raise ValueError("Invalid repository")
        self.repo = repo
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, method, path, data=None, missing=False, upload=False):
        host = "https://uploads.github.com" if upload else "https://api.github.com"
        body = data if isinstance(data, bytes) else (json.dumps(data).encode() if data is not None else None)
        url = f"{host}/repos/{self.repo}" + (f"/{path}" if path else "")
        req = urllib.request.Request(url, data=body, method=method,
                                     headers={"Authorization": f"Bearer {self.token}", "Accept": "application/vnd.github+json",
                                              "X-GitHub-Api-Version": "2022-11-28",
                                              "Content-Type": "application/octet-stream" if upload else "application/json"})
        try:
            with self.opener.open(req, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            raise ValueError(f"GitHub API failed with HTTP {error.code}") from None

    def all(self, path):
        records = []
        for page in range(1, 21):
            separator = "&" if "?" in path else "?"
            result = self.request("GET", f"{path}{separator}per_page=100&page={page}")
            if not isinstance(result, list):
                raise ValueError("Unexpected paginated response")
            records.extend(result)
            if len(result) < 100:
                return records
        raise ValueError("Pagination bound exceeded")


def inputs(version, sha):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)-(?:alpha|beta)\.[1-9][0-9]*", version):
        raise ValueError("Expected prerelease version")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Expected full lowercase commit SHA")


def eligibility(api, version, sha):
    inputs(version, sha)
    if api.request("GET", "").get("default_branch") != "main":
        raise ValueError("Unexpected default branch")
    if api.request("GET", f"commits/{sha}").get("sha") != sha:
        raise ValueError("Source commit mismatch")
    comparison = api.request("GET", f"compare/{sha}...main")
    if comparison.get("status") not in {"ahead", "identical"} or comparison.get("merge_base_commit", {}).get("sha") != sha:
        raise ValueError("Source is not contained in main")
    workflow = api.request("GET", "actions/workflows/godot.yml")
    if workflow.get("state") != "active" or workflow.get("path") != ".github/workflows/godot.yml":
        raise ValueError("Trusted CI workflow unavailable")
    result = api.request("GET", f"actions/workflows/godot.yml/runs?event=push&branch=main&head_sha={sha}&per_page=100")
    runs = result.get("workflow_runs", [])
    if not runs or result.get("total_count", 0) > 100:
        raise ValueError("No bounded exact-source CI evidence")
    run = max(runs, key=lambda item: item["run_number"])
    if any(run.get(key) != value for key, value in {"head_sha": sha, "head_branch": "main", "event": "push",
           "status": "completed", "conclusion": "success", "workflow_id": workflow["id"]}.items()):
        raise ValueError("Latest exact-source main CI did not succeed")
    jobs = api.request("GET", f"actions/runs/{run['id']}/jobs?filter=latest&per_page=100")
    if jobs.get("total_count", 0) > 100:
        raise ValueError("Too many CI jobs")
    aggregates = [job for job in jobs.get("jobs", []) if job.get("name") == "CI"]
    if len(aggregates) != 1 or aggregates[0].get("status") != "completed" or aggregates[0].get("conclusion") != "success":
        raise ValueError("Required aggregate CI missing or unsuccessful")
    if api.request("GET", f"git/ref/tags/{version}", missing=True) is not None:
        raise ValueError("Version tag already exists")
    if api.request("GET", f"releases/tags/{version}", missing=True) is not None:
        raise ValueError("Release already exists")
    if any(release.get("tag_name") == version or release.get("name") == version for release in api.all("releases")):
        raise ValueError("Draft or release version collision")
    return run["id"]


def check_source(api, version, sha, output):
    run_id = eligibility(api, version, sha)
    with output.open("a", encoding="utf-8") as stream:
        stream.write(f"source-sha={sha}\n")
    return run_id


def verify_bundle(directory, version, sha, engine_hash):
    inputs(version, sha)
    name = f"bglike-{version}-pck.zip"
    if {p.name for p in directory.iterdir()} != {name, "SHA256SUMS"}:
        raise ValueError("Unexpected artifact files")
    archive = directory / name
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if (directory / "SHA256SUMS").read_text() != f"{digest}  {name}\n":
        raise ValueError("Artifact checksum mismatch")
    with zipfile.ZipFile(archive) as bundle:
        expected = {"bglike.pck", "metadata.json", "RUN.txt", "COPYRIGHT.md", "THIRD_PARTY_NOTICES.md", "kenney_license.txt"}
        if set(bundle.namelist()) != expected or len(bundle.namelist()) != len(expected) or bundle.testzip() is not None:
            raise ValueError("Unexpected or corrupt archive members")
        metadata = json.loads(bundle.read("metadata.json"))
        if metadata.get("version") != version or metadata.get("source_sha") != sha or metadata.get("engine_archive_sha256") != engine_hash:
            raise ValueError("Package provenance mismatch")
        if not metadata.get("engine", "").startswith("4.7.2.stable.official.") or metadata.get("preset") != "Verification PCK":
            raise ValueError("Package engine or preset mismatch")
        names = expected - {"metadata.json", "RUN.txt"}
        if set(metadata.get("files", {})) != names:
            raise ValueError("Missing package checksums")
        for member in names:
            if hashlib.sha256(bundle.read(member)).hexdigest() != metadata["files"][member]:
                raise ValueError("Package member checksum mismatch")
    return [archive, directory / "SHA256SUMS"]


def create_draft(api, directory, version, sha, engine_hash):
    files = verify_bundle(directory, version, sha, engine_hash)
    run_id = eligibility(api, version, sha)
    release = api.request("POST", "releases", {"tag_name": version, "target_commitish": sha,
        "name": version, "draft": True, "prerelease": True, "generate_release_notes": False,
        "body": f"Verification PCK only. Godot 4.7.2 Standard is required separately.\nSource: `{sha}`\nCI run: {run_id}\nNo OS support or release readiness is declared."})
    release_id = release.get("id")
    if type(release_id) is not int or release.get("draft") is not True or release.get("prerelease") is not True or release.get("target_commitish") != sha or release.get("tag_name") != version or release.get("assets"):
        raise ValueError("Created Draft state mismatch; inspect GitHub manually")
    expected = {}
    for path in files:
        data = path.read_bytes()
        digest = "sha256:" + hashlib.sha256(data).hexdigest()
        asset = api.request("POST", f"releases/{release_id}/assets?name={urllib.parse.quote(path.name, safe='')}", data, upload=True)
        if asset.get("name") != path.name or asset.get("size") != len(data) or asset.get("state") != "uploaded" or (asset.get("digest") and asset["digest"] != digest):
            raise ValueError("Uploaded asset mismatch; inspect Draft manually")
        expected[path.name] = (len(data), digest)
    final = api.request("GET", f"releases/{release_id}")
    if final.get("draft") is not True or final.get("prerelease") is not True or final.get("target_commitish") != sha or final.get("tag_name") != version:
        raise ValueError("Draft changed during creation; inspect GitHub manually")
    assets = final.get("assets", [])
    if len(assets) != len(expected) or {asset.get("name") for asset in assets} != set(expected):
        raise ValueError("Final Draft asset collision")
    for asset in assets:
        size, digest = expected[asset["name"]]
        if asset.get("size") != size or asset.get("state") != "uploaded" or (asset.get("digest") and asset["digest"] != digest):
            raise ValueError("Final Draft asset mismatch")
    # GitHub has no transaction spanning tag checks, release creation and uploads.
    if api.request("GET", f"git/ref/tags/{version}", missing=True) is not None:
        raise ValueError("Tag appeared during Draft creation; inspect manually")
    releases = [item for item in api.all("releases") if item.get("tag_name") == version or item.get("name") == version]
    if len(releases) != 1 or releases[0].get("id") != release_id:
        raise ValueError("Concurrent Draft collision; inspect manually")
    return release_id


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["check", "create"])
    parser.add_argument("--artifact", type=Path)
    args = parser.parse_args()
    try:
        if os.environ.get("GITHUB_REF") != "refs/heads/main" or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
            raise ValueError("Draft workflow must run from main by manual dispatch")
        version, sha = os.environ["RELEASE_VERSION"], os.environ["SOURCE_SHA"]
        api = GitHub(os.environ["GITHUB_REPOSITORY"], os.environ["GH_TOKEN"])
        if args.mode == "check":
            print(f"Eligible CI run: {check_source(api, version, sha, Path(os.environ['GITHUB_OUTPUT']))}")
        else:
            config = dict(line.split("=", 1) for line in Path("scripts/godot.env").read_text().splitlines() if line and not line.startswith("#"))
            print(f"Unpublished Draft ID: {create_draft(api, args.artifact, version, sha, config['GODOT_LINUX_X86_64_SHA256'])}")
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, urllib.error.URLError):
        raise SystemExit("Draft validation failed; inspect any partially created Draft manually. No cleanup or publication was attempted.")
