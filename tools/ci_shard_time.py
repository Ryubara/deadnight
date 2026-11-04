"""A `godot` job shard's time: read it from its GdUnit4 log, hold it to a share of the job's limit, keep the times file.

    python3 tools/ci_shard_time.py check --log tests.log --shard 3 --elapsed 412   # in the job, after the tests
    python3 tools/ci_shard_time.py update --root game logs/*.log                   # new seconds per script from logs
    python3 tools/ci_shard_time.py web --elapsed 1400 --steps web-steps.txt          # the `web` job, last step
    python3 tools/ci_shard_time.py --self-test

The `godot` job has a limit of `JOB_LIMIT_SECONDS` and is cancelled at it with no failing test (#524, #676, #775, #1015).
`check` warns when a shard's job (setup and suites) passes `WARN_SHARE` of the limit and fails when it passes
`FAIL_SHARE`, so a shard that drifts is red on the pull request that pushed it, a few minutes before it would time out.
`update` rewrites `tools/ci_test_times.json`, the seconds per script that `tools/ci_test_shards.py` balances by, from
the `Statistics:` lines of one or more test logs (the mean when a script is in several logs).

The `web` job has a limit of `WEB_JOB_LIMIT_SECONDS` (#1111): it takes 1,100 to 1,700 s on `main`, nearly all of it
browser probes, and was cancelled at 30 minutes when a slow mirror made the browser's install take 471 s. `web` warns
past `WEB_WARN_SHARE` of the limit (the old 30 minutes) and fails past `WEB_FAIL_SHARE`, and lists the install steps
(their seconds are in a file the steps append to), naming any past `WEB_SLOW_STEP_SECONDS`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path

# The `godot` job's `timeout-minutes` in .github/workflows/ci.yml (ci_test_shards.py --self-test holds the two equal).
JOB_LIMIT_SECONDS = 15 * 60
# A shard job (setup, import, suites) that passes 60 % of the limit (9 min) is annotated; one that passes 80 % (12 min)
# fails. A balanced shard takes 6 to 9 minutes on the slowest runners seen, so the failure is real drift, not noise.
WARN_SHARE = 0.60
FAIL_SHARE = 0.80
# The `web` job's `timeout-minutes` (ci_test_shards.py --self-test holds the two equal). Annotated past 30 minutes, which
# was the limit when a slow install cancelled the job; failed past 36, four minutes before the cancel.
WEB_JOB_LIMIT_SECONDS = 40 * 60
WEB_WARN_SHARE = 0.75
WEB_FAIL_SHARE = 0.90
# An install step (system packages, browser) past this is named in the annotation. Warm it takes 5 to 30 s, cold 13 to
# 153 s on `main`, 471 s on the slow mirror.
WEB_SLOW_STEP_SECONDS = 180
TIMES_FILE = Path(__file__).with_name("ci_test_times.json")

ANSI = re.compile(r"\x1b\[[0-9;]*m")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ")
SUITE = re.compile(r"Run Test Suite:\s*res://tests/(\S+)")
DURATION = re.compile(r"(\d+)\s*(h|min|ms|s)\b")
UNIT_SECONDS = {"h": 3600.0, "min": 60.0, "s": 1.0, "ms": 0.001}


def seconds_of(text: str) -> float:
    """`1min 44s 758ms` -> 104.758."""
    return sum(int(n) * UNIT_SECONDS[unit] for n, unit in DURATION.findall(text))


def suite_times(log: str) -> dict[str, float]:
    """Seconds per test script from a GdUnit4 log: the duration on the `Statistics:` line that follows each suite."""
    found: dict[str, float] = {}
    current = None
    for raw in log.splitlines():
        line = STAMP.sub("", ANSI.sub("", raw)).strip()
        match = SUITE.search(line)
        if match:
            current = match.group(1)
        elif line.startswith("Statistics:") and current:
            found[current] = round(seconds_of(line.rsplit("|", 1)[-1]), 3)
            current = None
    return found


def check(log: str, shard: str, elapsed: float) -> tuple[str, int, str]:
    """(report, exit code, annotation) for one shard's log and the seconds its job has run so far."""
    times = suite_times(log)
    total = sum(times.values())
    share = elapsed / JOB_LIMIT_SECONDS
    slowest = sorted(times.items(), key=lambda kv: -kv[1])[:8]
    warn_at = WARN_SHARE * JOB_LIMIT_SECONDS
    fail_at = FAIL_SHARE * JOB_LIMIT_SECONDS
    lines = [
        f"### godot shard {shard}: {elapsed / 60:.1f} min, {share:.0%} of the {JOB_LIMIT_SECONDS // 60} min limit",
        "",
        f"The job has run {elapsed:.0f} s; {len(times)} suites took {total:.0f} s of it.",
        f"Warn at {WARN_SHARE:.0%} ({warn_at:.0f} s), fail at {FAIL_SHARE:.0%} ({fail_at:.0f} s).",
        "",
        "| Slowest suites | Seconds |",
        "| --- | --- |",
        *[f"| `{name}` | {seconds:.1f} |" for name, seconds in slowest],
    ]
    hint = (
        "Rebalance: download the tests.log of this run's shards, run `python3 tools/ci_shard_time.py update`, then "
        "`python3 tools/ci_test_shards.py --report` (docs/research/ci-time.md, 'Keeping the shards balanced')."
    )
    ran = f"shard {shard} ran {elapsed / 60:.1f} min, over"
    limit = f"of the {JOB_LIMIT_SECONDS // 60} min limit. {hint}"
    if share > FAIL_SHARE:
        message = f"{ran} {FAIL_SHARE:.0%} {limit}"
        return "\n".join(lines), 1, f"::error title=godot shard {shard} is too slow::{message}"
    if share > WARN_SHARE:
        message = f"{ran} {WARN_SHARE:.0%} {limit}"
        return "\n".join(lines), 0, f"::warning title=godot shard {shard} is getting slow::{message}"
    return "\n".join(lines), 0, ""


def web_steps(text: str) -> list[tuple[float, str]]:
    """(seconds, label) for each `<seconds> <label>` line the web job's install steps wrote."""
    found = []
    for line in text.splitlines():
        seconds, _, label = line.strip().partition(" ")
        if seconds.isdigit() and label:
            found.append((float(seconds), label))
    return found


def check_web(steps: list[tuple[float, str]], elapsed: float) -> tuple[str, int, str]:
    """(report, exit code, annotation) for the web job's recorded install steps and the seconds it has run."""
    share = elapsed / WEB_JOB_LIMIT_SECONDS
    warn_at = WEB_WARN_SHARE * WEB_JOB_LIMIT_SECONDS
    fail_at = WEB_FAIL_SHARE * WEB_JOB_LIMIT_SECONDS
    slow = [(seconds, label) for seconds, label in steps if seconds > WEB_SLOW_STEP_SECONDS]
    lines = [
        f"### web job: {elapsed / 60:.1f} min, {share:.0%} of the {WEB_JOB_LIMIT_SECONDS // 60} min limit",
        "",
        f"The job has run {elapsed:.0f} s.",
        f"Warn at {WEB_WARN_SHARE:.0%} ({warn_at:.0f} s), fail at {WEB_FAIL_SHARE:.0%} ({fail_at:.0f} s).",
        "",
        "| Install step | Seconds |",
        "| --- | --- |",
        *[f"| {label} | {seconds:.0f} |" for seconds, label in steps],
    ]
    if not steps:
        lines.append("| (no install step finished) | |")
    cause = ""
    if slow:
        names = ", ".join(f"'{label}' took {seconds:.0f} s" for seconds, label in slow)
        cause = f" Slow install: {names} (a cold cache and a slow mirror; the run after this one is warm)."
    hint = "Which probe grew: the step times of the job (docs/research/ci-time.md, 'The web job')."
    ran = f"the web job ran {elapsed / 60:.1f} min, over"
    limit = f"of the {WEB_JOB_LIMIT_SECONDS // 60} min limit.{cause} {hint}"
    if share > WEB_FAIL_SHARE:
        return "\n".join(lines), 1, f"::error title=web job is too slow::{ran} {WEB_FAIL_SHARE:.0%} {limit}"
    if share > WEB_WARN_SHARE:
        return "\n".join(lines), 0, f"::warning title=web job is getting slow::{ran} {WEB_WARN_SHARE:.0%} {limit}"
    if slow:
        return "\n".join(lines), 0, f"::warning title=web install was slow::{cause.strip()}"
    return "\n".join(lines), 0, ""


def update(times_file: Path, logs: list[str], root: Path) -> dict[str, float]:
    """Merge the logs' suite times into the times file (mean over the logs); scripts without a file are dropped."""
    data = json.loads(times_file.read_text(encoding="utf-8")) if times_file.exists() else {}
    seconds: dict[str, float] = dict(data.get("seconds", {}))
    runs: dict[str, list[float]] = {}
    for text in logs:
        for name, value in suite_times(text).items():
            runs.setdefault(name, []).append(value)
    for name, values in runs.items():
        seconds[name] = round(sum(values) / len(values), 1)
    tests = root / "tests"
    seconds = {name: value for name, value in seconds.items() if (tests / name).is_file()}
    data["seconds"] = dict(sorted(seconds.items()))
    data.setdefault("default_seconds", 10)
    return data


def write_times(times_file: Path, data: dict) -> None:
    """One script per line, so a rebalance is a readable diff."""
    head = {key: value for key, value in data.items() if key != "seconds"}
    lines = ["{"]
    for key, value in head.items():
        lines.append(f"  {json.dumps(key)}: {json.dumps(value)},")
    lines.append('  "seconds": {')
    items = list(data["seconds"].items())
    for index, (name, value) in enumerate(items):
        comma = "," if index < len(items) - 1 else ""
        lines.append(f"    {json.dumps(name)}: {value}{comma}")
    lines += ["  }", "}"]
    times_file.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def self_test() -> None:
    assert seconds_of("PASSED 1min 44s 758ms") == 104.758
    assert seconds_of("PASSED 758ms") == 0.758
    assert seconds_of("FAILED 2s 765ms") == 2.765
    log = (
        "2026-11-04T06:45:37.5Z \x1b[0mRun Test Suite: \x1b[0mres://tests/night/test_a.gd\n"
        "noise | 3 | 4\n"
        "2026-11-04T06:47:22.2Z Statistics: 3 test cases | 0 errors | 0 failures | 0 orphans | PASSED 1min 44s 758ms\n"
        "Run Test Suite: res://tests/ui/test_b.gd\n"
        "Statistics: 6 test cases | 0 errors | 1 failures | 0 orphans | FAILED 758ms\n"
        "Run Test Suite: res://tests/ui/test_c.gd\n"
    )
    assert suite_times(log) == {"night/test_a.gd": 104.758, "ui/test_b.gd": 0.758}, suite_times(log)
    slow = f"Run Test Suite: res://tests/x/test_x.gd\nStatistics: 1 test cases | PASSED {30}s 0ms\n"
    assert check(slow, "1", JOB_LIMIT_SECONDS * 0.5)[1:] == (0, "")
    assert check(slow, "1", JOB_LIMIT_SECONDS * 0.7)[2].startswith("::warning")
    report, code, annotation = check(slow, "1", JOB_LIMIT_SECONDS * 0.9)
    assert code == 1 and annotation.startswith("::error") and "test_x.gd" in report
    steps = web_steps("12 install-deps (cache hit: true)\n471 playwright install (cache hit: false)\nnoise\n")
    assert steps == [(12.0, "install-deps (cache hit: true)"), (471.0, "playwright install (cache hit: false)")], steps
    report, code, annotation = check_web(steps[:1], WEB_JOB_LIMIT_SECONDS * 0.5)
    assert (code, annotation) == (0, "") and "install-deps" in report
    report, code, annotation = check_web(steps, WEB_JOB_LIMIT_SECONDS * 0.5)
    assert code == 0 and annotation.startswith("::warning") and "playwright install" in annotation, annotation
    assert check_web(steps[:1], WEB_JOB_LIMIT_SECONDS * 0.8)[2].startswith("::warning title=web job is getting slow")
    report, code, annotation = check_web(steps, WEB_JOB_LIMIT_SECONDS * 0.95)
    assert code == 1 and annotation.startswith("::error") and "'playwright install" in annotation, annotation
    assert check_web([], 60)[1] == 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "tests" / "night").mkdir(parents=True)
        for name in ("test_a.gd", "test_kept.gd"):
            (root / "tests" / "night" / name).write_text("", encoding="utf-8")
        file = root / "times.json"
        file.write_text(
            json.dumps({"default_seconds": 7, "seconds": {"night/test_kept.gd": 5, "night/test_gone.gd": 9}}),
            encoding="utf-8",
        )
        merged = update(file, [log, log.replace("1min 44s 758ms", "2min")], root)
        assert merged["seconds"] == {"night/test_a.gd": 112.4, "night/test_kept.gd": 5}, merged
        assert merged["default_seconds"] == 7
        write_times(file, merged)
        assert json.loads(file.read_text(encoding="utf-8")) == merged
    print("ok: ci_shard_time")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    chk = sub.add_parser("check", help="warn or fail when a shard's job passes a share of the job limit")
    chk.add_argument("--log", type=Path, required=True)
    chk.add_argument("--shard", required=True)
    chk.add_argument("--elapsed", type=float, required=True, help="seconds the job has run (setup included)")
    chk.add_argument("--summary", type=Path, help="appended to (the job summary file)")
    web = sub.add_parser("web", help="warn or fail when the web job passes a share of its limit; name a slow install")
    web.add_argument("--elapsed", type=float, required=True, help="seconds the job has run (setup included)")
    web.add_argument("--steps", type=Path, required=True, help="lines `<seconds> <label>` the install steps wrote")
    web.add_argument("--summary", type=Path, help="appended to (the job summary file)")
    upd = sub.add_parser("update", help="rewrite tools/ci_test_times.json from test logs")
    upd.add_argument("--root", type=Path, default=Path("game"))
    upd.add_argument("--times", type=Path, default=TIMES_FILE)
    upd.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.command == "check":
        text = args.log.read_text(encoding="utf-8", errors="replace") if args.log.exists() else ""
        if "Executed test suites" not in ANSI.sub("", text):
            print("no finished test run in the log: the tests step reports its own failure")
            return
        report, code, annotation = check(text, args.shard, args.elapsed)
        print(report)
        if annotation:
            print(annotation)
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as summary:
                summary.write(report + "\n")
        sys.exit(code)
    elif args.command == "web":
        text = args.steps.read_text(encoding="utf-8", errors="replace") if args.steps.exists() else ""
        report, code, annotation = check_web(web_steps(text), args.elapsed)
        print(report)
        if annotation:
            print(annotation)
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as summary:
                summary.write(report + "\n")
        sys.exit(code)
    elif args.command == "update":
        logs = [path.read_text(encoding="utf-8", errors="replace") for path in args.logs]
        data = update(args.times, logs, args.root)
        write_times(args.times, data)
        print(f"{len(data['seconds'])} scripts, {sum(data['seconds'].values()):.0f} s, written to {args.times}")
    else:
        parser.error("check, web, update or --self-test")


if __name__ == "__main__":
    main()
