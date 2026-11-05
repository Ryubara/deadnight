"""Which test scripts a `godot` job shard runs, so the suite is split across parallel jobs (#524, #775, #1015).

    python3 tools/ci_test_shards.py --root game --shard 2      # prints "-a res://tests/net/test_x.gd -a ..."
    python3 tools/ci_test_shards.py --root game --self-test    # every script is in exactly one shard; the workflow agrees
    python3 tools/ci_test_shards.py --root game --report       # the seconds each shard is expected to take

Every `tests/**/test_*.gd` is one item of work with a weight: its seconds in `tools/ci_test_times.json` (measured from
the CI logs by `tools/ci_shard_time.py update`), or `default_seconds` for a script that is not in the file yet. The items
are dealt out by weight, heaviest first, to the shard with the least so far (the longest-processing-time rule), so the
shards are balanced by measured seconds, not by folder or file count, and a new script lands in the lightest shard
without anyone naming it. The result depends only on the file list and the times file, so every shard's job agrees.

To rebalance (a shard's job passed `ci_shard_time.py`'s warning, or the suite grew): download `tests.log` from the
`gdunit4-report-N` artifacts of two or three recent runs of `main`, run `python3 tools/ci_shard_time.py update <logs>`,
commit the new times file, and add a shard (`SHARDS` here and the matrix in the workflow) when `--report` says the
heaviest shard is over `REPORT_SHARD_BUDGET` seconds of suites. `docs/research/ci-time.md` has the method and numbers.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from ci_shard_time import JOB_LIMIT_SECONDS, WEB_JOB_LIMIT_SECONDS

# Ten shards (nine before #1193 added the worst-room budget run to shard 1: 4,319 s of suites and extras is 432 s each).
# Nine shards had 3,880 s of suites on the runner (3,710 to 4,020 s in four green `main` runs) is 431 s each, about 8 to 9
# minutes in all with the setup, against a limit of 15; the rule of thumb is total / 480 s, rounded up, with a margin for
# a slow runner and for growth (the suite grew 5 % in a day, #1015; 8 % in a day, #1151). Eight were enough for 3,250 s
# (#1091). The workflow's matrix must list them.
SHARDS = 10
# Seconds the once-per-run steps of shard 1 take beyond the setup every shard does (main scene, a night, the late-round
# budget run: 54 to 112 s for the budget run alone, 91 s on average in six `main` runs, 100 s with the rest, #1265;
# and the worst-room budget run of 8 people and 7 bots, 137 s on its first CI run, #1193), so shard 1 is dealt that much
# less test time. It was 60 and shard 1's job ran 85 s longer than a shard's mean.
EXTRA_SECONDS = {1: 240.0}
# `--report` flags a shard whose suites are expected to take more than this (a slow runner takes 15 % more; the check
# in ci_shard_time.py fails the job at 12 minutes of setup and suites together).
REPORT_SHARD_BUDGET = 440.0
TIMES_FILE = Path(__file__).with_name("ci_test_times.json")
WORKFLOW = Path(".github/workflows/ci.yml")


def scripts(root: Path) -> list[str]:
    """Every test script, as a path under tests/ (what GdUnit4 finds: `test_*.gd`, in any subfolder)."""
    tests = root / "tests"
    return sorted(path.relative_to(tests).as_posix() for path in tests.rglob("test_*.gd"))


def weights(root: Path, times_file: Path = TIMES_FILE) -> dict[str, float]:
    data = json.loads(times_file.read_text(encoding="utf-8"))
    known = data["seconds"]
    default = float(data["default_seconds"])
    return {name: float(known.get(name, default)) for name in scripts(root)}


def deal(weight: dict[str, float], shards: int = SHARDS) -> tuple[dict[str, int], list[float]]:
    """Longest first to the lightest shard. Returns (shard of each script, expected seconds of each shard's job)."""
    load = [EXTRA_SECONDS.get(shard, 0.0) for shard in range(1, shards + 1)]
    shard_of: dict[str, int] = {}
    for name, seconds in sorted(weight.items(), key=lambda item: (-item[1], item[0])):
        lightest = min(range(shards), key=lambda index: (load[index], index))
        load[lightest] += seconds
        shard_of[name] = lightest + 1
    return shard_of, load


def paths(root: Path, shard: int, times_file: Path = TIMES_FILE) -> list[str]:
    if not 1 <= shard <= SHARDS:
        sys.exit(f"shard {shard} is not between 1 and {SHARDS}")
    shard_of, _ = deal(weights(root, times_file))
    return [f"res://tests/{name}" for name in sorted(shard_of) if shard_of[name] == shard]


def report(root: Path, times_file: Path = TIMES_FILE) -> str:
    weight = weights(root, times_file)
    shard_of, load = deal(weight)
    known = json.loads(times_file.read_text(encoding="utf-8"))["seconds"]
    unknown = sorted(name for name in weight if name not in known)
    lines = [f"{len(weight)} scripts, {sum(weight.values()):.0f} s of suites, {SHARDS} shards"]
    for shard, seconds in enumerate(load, start=1):
        count = sum(1 for value in shard_of.values() if value == shard)
        flag = "  <- over the budget: add a shard" if seconds > REPORT_SHARD_BUDGET else ""
        lines.append(f"  shard {shard}: {seconds:5.0f} s expected, {count:3d} scripts{flag}")
    lines.append(f"{len(unknown)} scripts have no time yet (counted at the default); the slowest suites:")
    for name, seconds in sorted(weight.items(), key=lambda item: -item[1])[:10]:
        lines.append(f"  {seconds:6.1f} s  shard {shard_of[name]}  {name}")
    return "\n".join(lines)


def workflow_text(root: Path) -> str | None:
    path = root.resolve().parent / WORKFLOW
    return path.read_text(encoding="utf-8") if path.is_file() else None


def self_test(root: Path) -> None:
    every = scripts(root)
    assert every, "no test scripts found"
    seen: list[str] = []
    for shard in range(1, SHARDS + 1):
        found = paths(root, shard)
        assert found, f"shard {shard} runs nothing"
        seen.extend(found)
    assert sorted(seen) == sorted(f"res://tests/{name}" for name in every), "a script is in no shard, or in two"
    data = json.loads(TIMES_FILE.read_text(encoding="utf-8"))
    assert data["default_seconds"] > 0
    assert all(seconds >= 0 for seconds in data["seconds"].values()), "a negative time in the times file"
    # The workflow runs the shards this file deals: its matrix and its job limit are the ones the check assumes.
    text = workflow_text(root)
    if text is not None:
        job = text.split("\n  godot:\n", 1)[1].split("\n  bots-soak:\n", 1)[0]
        matrix = re.search(r"shard: \[([\d, ]+)\]", job)
        assert matrix, "the workflow's godot job has no `shard: [...]` matrix"
        listed = [int(n) for n in matrix.group(1).split(",")]
        assert listed == list(range(1, SHARDS + 1)), f"the workflow runs shards {listed}, this file deals {SHARDS}"
        limit = re.search(r"timeout-minutes: (\d+)", job)
        assert limit and int(limit.group(1)) * 60 == JOB_LIMIT_SECONDS, (
            "ci_shard_time.JOB_LIMIT_SECONDS is not the job's"
        )
        # The run goes through the warm-up that keeps scripts from staying in use at exit (#1231): the plain tool leaks
        # by the mix of suites in a shard, and the leak check below it fails the job with every test green.
        assert "-s res://tools/ci/warm_GdUnitCmdTool.gd" in job, (
            "the godot job must run GdUnit through tools/ci/warm_GdUnitCmdTool.gd"
        )
        assert "-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd" not in job, "the godot job runs the plain GdUnit tool"
        assert re.search(r'! grep -E "leaked at exit\|still in use" tests\.log', job), (
            "the leak check on tests.log is gone"
        )
        web = text.split("\n  web:\n", 1)[1].split("\n  deploy:\n", 1)[0]
        web_limit = re.search(r"\n    timeout-minutes: (\d+)", web)
        assert web_limit and int(web_limit.group(1)) * 60 == WEB_JOB_LIMIT_SECONDS, (
            "ci_shard_time.WEB_JOB_LIMIT_SECONDS is not the web job's"
        )
    print(f"ok: {len(every)} scripts in {SHARDS} shards")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("game"), help="the Godot project folder")
    parser.add_argument("--shard", type=int)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test(args.root)
    elif args.report:
        print(report(args.root))
    elif args.shard is None:
        parser.error("--shard, --report or --self-test")
    else:
        print(" ".join(f"-a {entry}" for entry in paths(args.root, args.shard)))


if __name__ == "__main__":
    main()
