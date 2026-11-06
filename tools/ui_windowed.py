"""Run the `tests/ui` GdUnit suites in a window, one Godot process per suite, and report the ones that fail there.

    python3 tools/ui_windowed.py run --out out --headless-godot "$godot" -- xvfb-run -a "$godot"
    python3 tools/ui_windowed.py report --out out --job-result success --markdown out/summary.md --issue out/issue.md
    python3 tools/ui_windowed.py --self-test

CI runs every GdUnit suite headless, where the game switches that a window turns the other way are off (the helicopter
drop, the loading screen, a 64 pixel window that never makes the menu shell a phone's, #1187, #1196). The scheduled
`ui-windowed` workflow runs the suites in a window under a virtual display and this script does the work:

- `run` starts the launcher (the words after `--`, then the Godot arguments) once for every `tests/ui/test_*.gd`, with
  its own timeout, so one suite that hangs (docs/lessons/2026-11-04-a-windowed-gdunit-run-hung-the-night-suites-after-a-ui-suite.md
  in the kit) costs its timeout and nothing after it. A suite that does not pass in the window is run again headless,
  as CI runs it, to say whether the window is what differs. It writes `result.json` and one log a suite into `--out`.
  It exits 0 whatever the suites did and non-zero only when it could not run at all.
- `report` reads `result.json` and the result of the job that made it, writes the job summary and the text of an issue,
  and prints `state=clean|failing|could-not-run|known-only` for the workflow to act on. A missing or empty result is
  `could-not-run`, never `clean`: a job that goes quiet is what #1196 exists to stop.

`ui_windowed_known.json` lists the suites that fail in a window on purpose-for-now, each with the issue that fixes it.
A listed suite that fails is `known`; a listed suite that passes is `stale` (remove the entry) and is reported as a
problem, so the list cannot hide a regression for good.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KNOWN_FILE = Path(__file__).with_name("ui_windowed_known.json")
UI_FOLDER = "tests/ui"

# Suites that read pixels and skip headless (the renderer is a dummy). They are the reason to run in a window: one that
# skips there or runs no test case is reported as `not-run`, not as a pass.
PIXEL_SUITES = ("test_level_ink", "test_poster_art_pixels")

# A known-file entry that starts with one of these is a suite the runner cannot judge: `llvmpipe:` (its software GL is too
# slow, or the suite counts frames in real time) or `xvfb:` (the virtual display has no window manager, so a window
# cannot be minimized, moved or focused by the engine). It is run when asked for and shown, never a reason to open an
# issue, and passing is not stale.
SOFTWARE_GL = ("llvmpipe:", "xvfb:")

# One suite's own limit. The longest suite takes about a minute on a developer's GPU; a hang costs this much, once.
SUITE_TIMEOUT_SECONDS = 300
HEADLESS_TIMEOUT_SECONDS = 180

ANSI = re.compile(r"\x1b\[[0-9;]*m")
SUMMARY = re.compile(
    r"Overall Summary:\s*(\d+) test cases \| (\d+) errors \| (\d+) failures \| (\d+) flaky \| (\d+) skipped"
)
BAD_CASE = re.compile(r">\s*(test_\w+)\s+(FAILED|ERROR)")

# Outcomes of a window run. `passed` and `known` are quiet; the rest are what the report is for.
PASSED, FAILED, TIMEOUT, CRASHED, NOT_RUN = "passed", "failed", "timeout", "crashed", "not-run"


def clean(text: str) -> str:
    return ANSI.sub("", text)


def parse_summary(log: str) -> dict[str, int] | None:
    """The counts on GdUnit4's `Overall Summary:` line, or None when the run never printed one."""
    found = SUMMARY.search(clean(log))
    if not found:
        return None
    cases, errors, failures, flaky, skipped = (int(n) for n in found.groups())
    return {"cases": cases, "errors": errors, "failures": failures, "flaky": flaky, "skipped": skipped}


def bad_cases(log: str) -> list[str]:
    """The names of the test cases that failed or errored, in order, once each."""
    seen: list[str] = []
    for name, _ in BAD_CASE.findall(clean(log)):
        if name not in seen:
            seen.append(name)
    return seen


def outcome_of(suite: str, counts: dict[str, int] | None, timed_out: bool) -> str:
    """One suite's outcome in the window from what its run printed."""
    if timed_out:
        return TIMEOUT
    if counts is None:
        return CRASHED
    if counts["errors"] or counts["failures"]:
        return FAILED
    if suite in PIXEL_SUITES and (counts["cases"] == 0 or counts["skipped"] > 0):
        return NOT_RUN
    return PASSED


def godot_args(project: str, suite: str, headless: bool) -> list[str]:
    """The arguments after the launcher: the GdUnit command line for one suite, windowed or as CI runs it headless."""
    args = ["--path", project, "--audio-driver", "Dummy"]
    if headless:
        args.insert(0, "--headless")
    args += ["-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "-a", f"res://{UI_FOLDER}/{suite}.gd", "-c"]
    if headless:
        args.append("--ignoreHeadlessMode")
    return args


def run_one(argv: list[str], timeout: float, log_path: Path) -> tuple[str, bool, float]:
    """Run a command in its own process group so a timeout ends the virtual display and the engine together."""
    start = time.monotonic()
    timed_out = False
    with log_path.open("wb") as handle:
        proc = subprocess.Popen(argv, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                if hasattr(os, "killpg"):
                    os.killpg(proc.pid, signal.SIGKILL)
                else:
                    proc.kill()
            except ProcessLookupError:
                pass
            proc.wait()
    return log_path.read_text(encoding="utf-8", errors="replace"), timed_out, time.monotonic() - start


def suites_in(project: Path, only: list[str]) -> list[str]:
    found = sorted(p.stem for p in (project / UI_FOLDER).glob("test_*.gd"))
    if not only:
        return found
    missing = [name for name in only if name not in found]
    if missing:
        raise SystemExit(f"no such suite in {UI_FOLDER}: {', '.join(missing)}")
    return only


def cmd_run(args: argparse.Namespace) -> int:
    out = Path(args.out)
    logs = out / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    project = Path(args.project)
    launcher = args.launcher[1:] if args.launcher[:1] == ["--"] else args.launcher
    if not launcher:
        raise SystemExit("run: give the launcher after `--`, for example: -- xvfb-run -a godot")
    requested = [s.strip() for s in args.suites.split(",") if s.strip()]
    names = suites_in(project, requested)
    if not requested:
        # The whole folder leaves out the suites the runner cannot judge (they cost 18 minutes of the
        # 45 and prove nothing); the report names them. Asking for them by name runs them.
        known = load_known(Path(args.known))
        names = [n for n in names if not known.get(n, "").startswith(SOFTWARE_GL)]
    started = time.time()
    results: list[dict] = []

    def write(complete: bool) -> None:
        # After every suite: a job that is stopped by its time limit still leaves what it ran, marked incomplete.
        body = {
            "started": started,
            "finished": time.time(),
            "complete": complete,
            "planned": len(names),
            "subset": bool(requested),
            "suites": results,
        }
        (out / "result.json").write_text(json.dumps(body, indent=1), encoding="utf-8")

    write(False)
    for index, name in enumerate(names, 1):
        log, timed_out, seconds = run_one(
            launcher + godot_args(args.project, name, False), args.timeout, logs / f"{name}.log"
        )
        counts = parse_summary(log)
        outcome = outcome_of(name, counts, timed_out)
        row = {"suite": name, "outcome": outcome, "seconds": round(seconds, 1), "counts": counts, "bad": bad_cases(log)}
        if outcome != PASSED and args.headless_godot:
            hlog, h_timeout, h_seconds = run_one(
                [args.headless_godot] + godot_args(args.project, name, True),
                args.headless_timeout,
                logs / f"{name}.headless.log",
            )
            h_outcome = outcome_of(name, parse_summary(hlog), h_timeout)
            # A pixel suite skips headless by design: that is not a failure of the suite there.
            row["headless"] = PASSED if h_outcome == NOT_RUN else h_outcome
            row["headless_seconds"] = round(h_seconds, 1)
        results.append(row)
        write(False)
        print(
            f"[{index}/{len(names)}] {name}: {outcome} in {seconds:.0f}s"
            + (f", headless {row['headless']}" if "headless" in row else ""),
            flush=True,
        )
    write(True)
    return 0


def load_known(path: Path = KNOWN_FILE) -> dict[str, str]:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def classify(result: dict, known: dict[str, str]) -> dict[str, list]:
    """Sort a run's suites into what the report says. `window_only` failed in the window and passed headless."""
    groups: dict[str, list] = {
        "window_only": [],
        "both": [],
        "not_run": [],
        "known": [],
        "software_gl": [],
        "stale": [],
        "passed": [],
    }
    for row in result["suites"]:
        name, outcome = row["suite"], row["outcome"]
        soft = known.get(name, "").startswith(SOFTWARE_GL)
        if outcome == PASSED:
            (groups["stale"] if name in known and not soft else groups["passed"]).append(row)
        elif soft and row.get("headless") == PASSED:
            groups["software_gl"].append(row)
        elif name in known and not soft:
            groups["known"].append(row)
        elif outcome == NOT_RUN:
            groups["not_run"].append(row)
        elif row.get("headless") == PASSED:
            groups["window_only"].append(row)
        else:
            groups["both"].append(row)
    return groups


def state_of(job_result: str, result: dict | None, groups: dict[str, list] | None) -> str:
    """`clean`, `known-only`, `failing` or `could-not-run`. Anything but a finished run of suites is `could-not-run`."""
    if (
        job_result != "success"
        or not result
        or not result.get("suites")
        or not result.get("complete")
        or groups is None
    ):
        return "could-not-run"
    if groups["window_only"] or groups["both"] or groups["not_run"] or groups["stale"]:
        return "failing"
    return "known-only" if groups["known"] else "clean"


def why_not(result: dict | None) -> str:
    """What the result file says about a run that did not finish."""
    if not result:
        return "its result file is missing"
    if not result.get("suites"):
        return "it ran no suite"
    if not result.get("complete"):
        return f"it stopped after {len(result['suites'])} of {result.get('planned', '?')} suites"
    return "its result file is complete"


def describe(row: dict) -> str:
    bits = [row["outcome"]]
    if row.get("bad"):
        bits.append("cases: " + ", ".join(row["bad"][:6]) + (" ..." if len(row["bad"]) > 6 else ""))
    if "headless" in row:
        bits.append(f"headless: {row['headless']}")
    return "; ".join(bits)


def render(
    state: str,
    job_result: str,
    result: dict | None,
    groups: dict[str, list] | None,
    known: dict[str, str],
    run_url: str,
) -> tuple[str, str]:
    """The job summary and the issue text (the same lines; the issue adds a pointer to the run)."""
    lines = ["## Windowed UI suites", ""]
    if result and result.get("subset"):
        lines += ["**A subset of the suites was run**: this speaks for those suites only.", ""]
    if state == "could-not-run":
        lines += [
            "**The windowed run could not run**, so nothing is known about the window today.",
            "",
            f"- The run job ended `{job_result}`; {why_not(result)}.",
            "- Read the failed step in the run's log: setup (packages, Godot, GdUnit4), the import, or the launcher.",
        ]
    else:
        assert groups is not None and result is not None
        suites = result["suites"]
        total = sum(row["seconds"] for row in suites)
        lines += [
            f"{len(suites)} suites run in a window, {total / 60:.1f} minutes of suite time. State: **{state}**.",
            "",
        ]
        sections = [
            ("window_only", "Fail in the window, pass headless (the reason for this job)"),
            ("both", "Fail in the window and headless too (main is red, or the runner is)"),
            ("not_run", "Pixel suites that did not run in the window"),
            ("stale", "Listed as known failures but pass now: remove them from `tools/ui_windowed_known.json`"),
            ("known", "Known failures, each with the issue that fixes it"),
            (
                "software_gl",
                "Not judged: the runner (its software GL or its virtual display) cannot tell, and they pass headless",
            ),
        ]
        for key, title in sections:
            rows = groups[key]
            if not rows:
                continue
            lines += [f"### {title} ({len(rows)})", ""]
            for row in rows:
                issue = f" ({known[row['suite']]})" if row["suite"] in known else ""
                lines.append(f"- `{row['suite']}`{issue}: {describe(row)}")
            lines.append("")
        ran = {r["suite"] for r in suites}
        left_out = [n for n, why in known.items() if why.startswith(SOFTWARE_GL) and n not in ran]
        if left_out and not result.get("subset"):
            lines += [
                f"### Not run here: the runner (its software GL or its virtual display) cannot judge them ({len(left_out)})",
                "",
            ]
            lines += [f"- `{n}` ({known[n]})" for n in left_out] + [""]
        slow = sorted(suites, key=lambda r: -r["seconds"])[:5]
        lines += ["Slowest: " + ", ".join(f"`{r['suite']}` {r['seconds']:.0f}s" for r in slow), ""]
        pixel = [r for r in suites if r["suite"] in PIXEL_SUITES]
        lines.append("Pixel suites: " + ", ".join(f"`{r['suite']}` {r['outcome']}" for r in pixel) + ".")
    summary = "\n".join(lines) + "\n"
    return summary, issue_body(summary, state, run_url)


def issue_body(summary: str, state: str, run_url: str, today: str | None = None) -> str:
    """The text of the issue the workflow opens: the task form's sections, and a marker that holds the state."""
    today = today or time.strftime("%Y-%m-%d", time.gmtime())
    findings = summary.split("\n", 2)[2] if summary.startswith("## ") else summary
    return (
        f"From: the ui-windowed workflow, {today}, the scheduled windowed run of tests/ui (#1196)\n\n"
        f"## Summary\n\n{findings.rstrip()}\n\n"
        + (f"Run: {run_url}\n\n" if run_url else "")
        + "The job rewrites this text on every run and closes the issue itself on the first clean one.\n\n"
        "## Area\n\nA-tests\n\n"
        '## What "done" means\n\n'
        "A scheduled run is clean: every suite passes in the window, or is listed in "
        "`tools/ui_windowed_known.json` with the issue that fixes it.\n\n"
        f"{state_marker(state)}\n"
    )


def state_marker(state: str) -> str:
    return f"<!-- ui-windowed-state: {state} -->"


def cmd_report(args: argparse.Namespace) -> int:
    out = Path(args.out)
    known = load_known(Path(args.known))
    result = None
    path = out / "result.json"
    if path.exists():
        try:
            result = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            result = None
    groups = classify(result, known) if result and result.get("suites") else None
    state = state_of(args.job_result, result, groups)
    summary, issue = render(state, args.job_result, result, groups, known, args.run_url)
    if args.markdown:
        Path(args.markdown).write_text(summary, encoding="utf-8")
    if args.issue:
        Path(args.issue).write_text(issue, encoding="utf-8")
    print(summary)
    print(f"state={state}")
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as handle:
            subset = "true" if result and result.get("subset") else "false"
            handle.write(f"state={state}\nsubset={subset}\n")
    return 0


def self_test() -> int:
    summary = "Overall Summary: 11 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |"
    assert parse_summary(summary) == {"cases": 11, "errors": 0, "failures": 0, "flaky": 0, "skipped": 0}
    assert parse_summary("\x1b[1m" + summary.replace("0 failures", "3 failures"))["failures"] == 3
    assert parse_summary("Godot Engine v4.7") is None
    log = "res://tests/ui/a.gd > test_x FAILED 3ms\nres://tests/ui/a.gd > test_x FAILED\n a.gd > test_y ERROR"
    assert bad_cases(log) == ["test_x", "test_y"]
    ok = {"cases": 4, "errors": 0, "failures": 0, "flaky": 0, "skipped": 0}
    assert outcome_of("test_a", ok, False) == PASSED
    assert outcome_of("test_a", {**ok, "failures": 1}, False) == FAILED
    assert outcome_of("test_a", {**ok, "errors": 1}, False) == FAILED
    assert outcome_of("test_a", None, False) == CRASHED
    assert outcome_of("test_a", ok, True) == TIMEOUT
    # A pixel suite that skipped every case, or ran none, passed nothing.
    assert outcome_of("test_level_ink", {**ok, "skipped": 4}, False) == NOT_RUN
    assert outcome_of("test_poster_art_pixels", {**ok, "cases": 0}, False) == NOT_RUN
    assert outcome_of("test_a", {**ok, "skipped": 4}, False) == PASSED
    assert "--headless" in godot_args("game", "test_a", True) and "--headless" not in godot_args(
        "game", "test_a", False
    )
    assert "--ignoreHeadlessMode" in godot_args("game", "test_a", True)
    rows = [
        {"suite": "test_ok", "outcome": PASSED, "seconds": 3.0},
        {"suite": "test_win", "outcome": FAILED, "seconds": 9.0, "headless": PASSED, "bad": ["test_x"]},
        {"suite": "test_red", "outcome": FAILED, "seconds": 9.0, "headless": FAILED},
        {"suite": "test_hang", "outcome": TIMEOUT, "seconds": 300.0, "headless": PASSED},
        {"suite": "test_known", "outcome": FAILED, "seconds": 9.0, "headless": PASSED},
        {"suite": "test_fixed", "outcome": PASSED, "seconds": 9.0},
        {"suite": "test_level_ink", "outcome": NOT_RUN, "seconds": 5.0, "headless": PASSED},
        {"suite": "test_slow", "outcome": TIMEOUT, "seconds": 300.0, "headless": PASSED},
        {"suite": "test_slow_ok", "outcome": PASSED, "seconds": 90.0},
        {"suite": "test_slow_red", "outcome": TIMEOUT, "seconds": 300.0, "headless": FAILED},
        {"suite": "test_nowm", "outcome": FAILED, "seconds": 2.0, "headless": PASSED},
    ]
    known = {
        "test_known": "#1",
        "test_fixed": "#2",
        "test_slow": "llvmpipe: draws 60 frames",
        "test_slow_ok": "llvmpipe: draws 60 frames",
        "test_slow_red": "llvmpipe: draws 60 frames",
        "test_nowm": "xvfb: no window manager to minimize a window",
    }
    groups = classify({"suites": rows, "complete": True}, known)
    assert [r["suite"] for r in groups["window_only"]] == ["test_win", "test_hang"]
    assert [r["suite"] for r in groups["both"]] == ["test_red", "test_slow_red"]
    assert [r["suite"] for r in groups["known"]] == ["test_known"]
    assert [r["suite"] for r in groups["stale"]] == ["test_fixed"]
    assert [r["suite"] for r in groups["not_run"]] == ["test_level_ink"]
    # A software-GL suite that times out is only shown; one that passes is not stale; one red headless too is red.
    assert [r["suite"] for r in groups["software_gl"]] == ["test_slow", "test_nowm"]
    assert "test_slow_ok" not in [r["suite"] for r in groups["stale"]]

    assert state_of("success", {"suites": rows, "complete": True}, groups) == "failing"
    only_known = classify({"suites": rows[:1] + rows[4:5], "complete": True}, known)
    assert (
        state_of(
            "success", {"suites": rows[:1], "complete": True}, classify({"suites": rows[:1], "complete": True}, known)
        )
        == "clean"
    )
    assert state_of("success", {"suites": rows[:1] + rows[4:5], "complete": True}, only_known) == "known-only"
    # Never `clean` when the job did not finish, or left no result, or an empty one.
    for job in ("failure", "cancelled", "skipped", ""):
        assert (
            state_of(
                job, {"suites": rows[:1], "complete": True}, classify({"suites": rows[:1], "complete": True}, known)
            )
            == "could-not-run"
        )
    # A run stopped part way (the step's time limit) is not a clean one, whatever it had run by then.
    assert (
        state_of("success", {"suites": rows[:1], "complete": False}, classify({"suites": rows[:1]}, known))
        == "could-not-run"
    )
    assert "stopped after 1 of 9 suites" in why_not({"suites": rows[:1], "complete": False, "planned": 9})
    assert state_of("success", None, None) == "could-not-run"
    assert state_of("success", {"suites": []}, None) == "could-not-run"
    text, issue = render("could-not-run", "failure", None, None, known, "https://x/run/1")
    assert "could not run" in text and "https://x/run/1" in issue
    body = issue_body(text, "failing", "https://x/run/2", "2026-11-05")
    assert body.startswith("From: the ui-windowed workflow, 2026-11-05") and "## Summary" in body
    assert "## Windowed UI suites" not in body and state_marker("failing") in body and "Run: https://x/run/2" in body
    few = {"suites": rows[:2], "complete": True}
    left, _ = render("failing", "success", few, classify(few, known), known, "")
    assert "Not run here" in left and "`test_slow_ok`" in left
    sub, _ = render("failing", "success", {"suites": rows, "complete": True, "subset": True}, groups, known, "")
    assert "A subset of the suites was run" in sub
    text, _ = render("failing", "success", {"suites": rows, "complete": True}, groups, known, "")
    assert "`test_win`" in text and "(#1)" in text and "test_x" in text and "`test_level_ink` not-run" in text
    # A timeout really ends a process group that holds a child (POSIX: the runner's; Windows has no process groups).
    if hasattr(os, "killpg"):
        with tempfile.TemporaryDirectory() as tmp:
            _, timed_out, seconds = run_one(["sh", "-c", "sleep 30 & sleep 30"], 1, Path(tmp) / "x.log")
            assert timed_out and seconds < 10, (timed_out, seconds)
    print("ui_windowed self-test ok")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run", help="run every suite in a window")
    run.add_argument("--project", default=str(ROOT / "game"))
    run.add_argument("--out", required=True)
    run.add_argument(
        "--suites", default="", help="comma-separated suite names (test_x), default every suite of tests/ui"
    )
    run.add_argument("--timeout", type=float, default=SUITE_TIMEOUT_SECONDS)
    run.add_argument("--headless-timeout", type=float, default=HEADLESS_TIMEOUT_SECONDS)
    run.add_argument("--known", default=str(KNOWN_FILE))
    run.add_argument("--headless-godot", default="", help="Godot to run a failed suite again headless; empty: do not")
    run.add_argument("launcher", nargs=argparse.REMAINDER, help="after `--`: the program that starts Godot in a window")
    run.set_defaults(func=cmd_run)
    report = sub.add_parser("report", help="classify a run and write the summary and the issue text")
    report.add_argument("--out", required=True)
    report.add_argument(
        "--job-result", required=True, help="the run job's result (success, failure, cancelled, skipped)"
    )
    report.add_argument("--known", default=str(KNOWN_FILE))
    report.add_argument("--markdown", default="")
    report.add_argument("--issue", default="")
    report.add_argument("--run-url", default="")
    report.add_argument("--github-output", default="", help="append `state=...` to this file (the step's output)")
    report.set_defaults(func=cmd_report)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
