"""The numbers of many CI web smoke runs, without downloading them (issue #989).

A `web-smoke` artifact is 34 MB (screenshots of every probe) and `smoke/result.json` in it is 60 KB. This reads just the
zip's index and that one file from GitHub's storage with HTTP range requests (about 70 KB an artifact, a second each),
and appends one JSON line per artifact to a file, so a question about 1 000 runs takes a minute and no disk. The lines
carry the artifact's run, branch, commit and time beside the whole `result.json` (without the per-second samples and the
loading steps); a line that is already in the file is not fetched again.

    python -I tools/web_smoke/smoke_history.py --repo Ryubara/deadnight --since 2026-11-03 --out scratch/history.jsonl
    python -I tools/web_smoke/smoke_history.py --out scratch/history.jsonl --summary

`--summary` prints, by hour, the runs, the median idle menu frame (`menu_frames`) and the share at 120 ms or more, and
by CPU model (`machine.cpu_model`, recorded by the smoke from #989 on) the same. Needs the `gh` CLI, signed in.
"""

from __future__ import annotations

import argparse
import io
import json
import statistics
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile
from collections import defaultdict
from concurrent import futures
from pathlib import Path

RESULT_IN_ZIP = "smoke/result.json"
# Fields of `result.json` that are long and say nothing about a run's speed.
DROPPED = ("night_samples",)
DROPPED_LOADING = ("steps", "busiest_frames")
SLOW_IDLE_MS = 120.0


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def list_artifacts(repo: str, since: str) -> list[dict]:
    """Every `web-smoke` artifact created on or after `since` (a date), newest first."""
    out = gh(
        "api",
        "--paginate",
        f"repos/{repo}/actions/artifacts?name=web-smoke&per_page=100",
        "--jq",
        ".artifacts[]|select(.expired|not)|{id,created_at,run:.workflow_run.id,branch:.workflow_run.head_branch,"
        "sha:.workflow_run.head_sha}|tojson",
    )
    found = [json.loads(line) for line in out.splitlines()]
    return [a for a in found if a["created_at"][:10] >= since]


def storage_url(repo: str, artifact_id: int, token: str) -> str:
    """The signed address GitHub redirects an artifact download to (it needs no token, and answers range requests)."""
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/actions/artifacts/{artifact_id}/zip",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
    )
    try:
        urllib.request.build_opener(_NoRedirect).open(request)
    except urllib.error.HTTPError as error:
        if error.code in (301, 302):
            return error.headers["Location"]
        raise
    raise RuntimeError("the artifact download did not redirect")


class RangeFile(io.RawIOBase):
    """A read-only file over an address that answers `Range`: a zip reads its index and one member from it."""

    def __init__(self, url: str) -> None:
        self.url = url
        with urllib.request.urlopen(urllib.request.Request(url, headers={"Range": "bytes=0-0"})) as reply:
            self.size = int(reply.headers["Content-Range"].split("/")[1])
        self.pos = 0
        self.fetched = 0

    def seekable(self) -> bool:
        return True

    def readable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = 0) -> int:
        self.pos = (offset, self.pos + offset, self.size + offset)[whence]
        return self.pos

    def read(self, size: int = -1) -> bytes:
        if size < 0 or self.pos + size > self.size:
            size = self.size - self.pos
        if size <= 0:
            return b""
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + size - 1}"})
        with urllib.request.urlopen(request) as reply:
            data = reply.read()
        self.pos += len(data)
        self.fetched += len(data)
        return data

    def readinto(self, buffer) -> int:
        data = self.read(len(buffer))
        buffer[: len(data)] = data
        return len(data)


def reduce_one(repo: str, token: str, artifact: dict) -> dict:
    line = {key: artifact[key] for key in ("id", "created_at", "run", "branch", "sha")}
    try:
        remote = RangeFile(storage_url(repo, artifact["id"], token))
        with zipfile.ZipFile(io.BufferedReader(remote, 65536)) as archive:
            if RESULT_IN_ZIP not in archive.namelist():
                line["error"] = "no result.json"
                return line
            result = json.loads(archive.read(RESULT_IN_ZIP))
        for key in DROPPED:
            result.pop(key, None)
        for key in DROPPED_LOADING:
            result.get("loading", {}).pop(key, None)
        line["result"] = result
        line["bytes_fetched"] = remote.fetched
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError) as error:
        line["error"] = repr(error)[:200]
    return line


def fetch(args: argparse.Namespace) -> None:
    token = gh("auth", "token").strip()
    have: set[int] = set()
    if args.out.exists():
        for text in args.out.read_text(encoding="utf-8").splitlines():
            line = json.loads(text)
            if "error" not in line:
                have.add(line["id"])
    todo = [a for a in list_artifacts(args.repo, args.since) if a["id"] not in have]
    print(f"{len(todo)} artifacts to read ({len(have)} already in {args.out})", flush=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("a", encoding="utf-8") as out, futures.ThreadPoolExecutor(args.workers) as pool:
        for n, line in enumerate(pool.map(lambda a: reduce_one(args.repo, token, a), todo), 1):
            out.write(json.dumps(line) + "\n")
            if n % 50 == 0:
                print(f"{n} of {len(todo)}", flush=True)


def share_slow(values: list[float]) -> str:
    return f"{sum(v >= SLOW_IDLE_MS for v in values)}/{len(values)}"


def summary(path: Path) -> None:
    runs = [json.loads(text) for text in path.read_text(encoding="utf-8").splitlines()]
    by_hour: dict[str, list[float]] = defaultdict(list)
    by_cpu: dict[str, list[float]] = defaultdict(list)
    for run in runs:
        frames = run.get("result", {}).get("menu_frames")
        if not frames:
            continue
        by_hour[run["created_at"][:13]].append(frames["mean_ms"])
        cpu = run["result"].get("machine", {}).get("cpu_model")
        if cpu:
            by_cpu[cpu].append(frames["mean_ms"])
    print("by hour (UTC) of the artifact: runs, median idle ms, runs at or over 120 ms")
    for hour, values in sorted(by_hour.items()):
        print(f"  {hour}  {len(values):3d}  {statistics.median(values):6.1f}  {share_slow(values)}")
    print("by CPU model: runs, median idle ms, runs at or over 120 ms")
    for cpu, values in sorted(by_cpu.items()):
        print(f"  {cpu:40s} {len(values):3d}  {statistics.median(values):6.1f}  {share_slow(values)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", default="Ryubara/deadnight")
    parser.add_argument("--since", default="2000-01-01", help="a date: only artifacts created on or after it")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--summary", action="store_true", help="print the table of --out and fetch nothing")
    args = parser.parse_args()
    if args.summary:
        summary(args.out)
    else:
        fetch(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
