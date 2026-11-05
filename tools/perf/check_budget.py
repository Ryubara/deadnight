"""Holds the late-round worst case to its budget (issue #906).

    python3 tools/perf/check_budget.py <report.json> [<budget.json>] [--markdown <file>]

`<report.json>` is what the autopilot run writes with `--sample=1 --out=...` (`game/tools/bench/autopilot_run.gd`
and `perf_sampler.gd`): one row a second of the monitors and counts of a night. The budget (default `budget.json`
beside this file) names, for one case, the most each count may reach while the crowd stands, how much a count may
grow over the steady seconds (a leak), and how many times a fixed piece of GDScript (`calibration_ms`) one frame may
cost; how many times a tick a counted piece of work (`PerfProbe.count`) happens, and what share of the frame a timed
piece of work (`PerfProbe.end`, a row's `labels_ms`) takes. A count is the same on every machine at the same seed, so it
is held tight. The frame is held as a ratio of the calibration, which a slow runner and a busy machine both scale, so
it is held loose and is a regression catcher, not a frame-rate promise. A timed piece of work of a few microseconds is
held as a share of the frame instead: on the runners it moved with the frame (a slope of 0.98 in the logs) and hardly
with the calibration (0.35), so a ratio of the calibration swung by a factor of two between runners that ran the same
code (docs/research/performance.md, "What the label limits mean").

Exits 1 and prints every limit that is broken, with the number and the limit.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def steady_rows(samples: list[dict], budget: dict) -> list[dict]:
    """The rows where the crowd stands: the round the case starts at or later, alive at least `crowd_share` of the cap."""
    share = budget.get("crowd_share", 0.9)
    first = budget.get("round_from", 1)
    rows = [
        row
        for row in samples
        if row["frames"] > 0 and row["cap"] > 0 and row["round"] >= first and row["alive"] >= share * row["cap"]
    ]
    return rows[budget.get("skip_rows", 0) :]


def slope_per_minute(rows: list[dict], key: str) -> float:
    """How much `key` grows a minute over the rows: the least-squares line through (t, value)."""
    if len(rows) < 3:
        return 0.0
    times = [row["t"] for row in rows]
    values = [row[key] for row in rows]
    mean_t = statistics.fmean(times)
    mean_v = statistics.fmean(values)
    spread = sum((t - mean_t) ** 2 for t in times)
    if spread == 0:
        return 0.0
    return 60.0 * sum((t - mean_t) * (v - mean_v) for t, v in zip(times, values, strict=True)) / spread


def judge(report: dict, budget: dict) -> tuple[list[str], list[str]]:
    """(the broken limits, the lines of what was measured)."""
    broken: list[str] = []
    lines: list[str] = []
    rows = steady_rows(report["samples"], budget)
    minimum = budget.get("min_steady_rows", 10)
    lines.append(f"steady rows: {len(rows)} (at least {minimum})")
    if len(rows) < minimum:
        broken.append(f"the crowd stood for {len(rows)} seconds, under {minimum}: it never formed, or the night ended")
        return broken, lines
    for key, limit in budget.get("max", {}).items():
        peak = max(row[key] for row in rows)
        lines.append(f"{key}: peak {peak} (limit {limit})")
        if peak > limit:
            broken.append(f"{key} peaked at {peak}, over its limit {limit}")
    for key, limit in budget.get("growth_per_minute", {}).items():
        slope = slope_per_minute(rows, key)
        lines.append(f"{key}: grows {slope:.1f} a minute (limit {limit})")
        if slope > limit:
            broken.append(f"{key} grows {slope:.1f} a minute over the steady rows, over its limit {limit}")
    for key, limit in budget.get("max_per_tick", {}).items():
        # Work counted by `PerfProbe.count` (a decode, a list built): the same on every machine.
        ticks = sum(row["frames"] for row in rows)
        per_tick = sum(row.get("counts", {}).get(key, 0) for row in rows) / max(ticks, 1)
        lines.append(f"{key}: {per_tick:.2f} a tick (limit {limit})")
        if per_tick > limit:
            broken.append(f"{key} happens {per_tick:.2f} times a tick, over its limit {limit}")
    for label, limit in budget.get("max_label_share_of_frame", {}).items():
        # A piece of work timed by `PerfProbe` (a row's `labels_ms`: the mean milliseconds a frame), held as a share
        # of the frame the same rows took (`frame_ms`, the mean wall time of a frame): both are cut the same way by a
        # slow or a busy host, which a fixed loop of arithmetic is not.
        frame = statistics.median(row["frame_ms"] for row in rows)
        spent = statistics.median(row.get("labels_ms", {}).get(label, 0.0) for row in rows)
        share = spent / frame
        lines.append(f"{label}: median {share:.5f} of the frame, {spent:.4f} ms of {frame:.1f} ms (limit {limit})")
        if share > limit:
            broken.append(f"{label} takes {share:.5f} of a frame, over its limit {limit}")
    for key, limit in budget.get("max_ratio_of_calibration", {}).items():
        calibration = statistics.median(row["calibration_ms"] for row in rows)
        ratio = statistics.median(row[key] for row in rows) / calibration
        lines.append(f"{key}: median {ratio:.2f} times the calibration {calibration:.1f} ms (limit {limit})")
        if ratio > limit:
            broken.append(f"{key} is {ratio:.2f} times the calibration, over its limit {limit}")
    return broken, lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("report", type=Path)
    parser.add_argument("budget", type=Path, nargs="?", default=HERE / "budget.json")
    parser.add_argument("--markdown", type=Path, help="also write the measured lines there (a job summary)")
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    budget = json.loads(args.budget.read_text(encoding="utf-8"))
    broken, lines = judge(report, budget)
    print("\n".join(lines))
    if args.markdown:
        body = "\n".join(f"- {line}" for line in lines)
        args.markdown.write_text(f"### Late-round budget\n\n{body}\n", encoding="utf-8")
    if broken:
        print("\nOVER BUDGET:", *broken, sep="\n  ", file=sys.stderr)
        return 1
    print("within the budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
