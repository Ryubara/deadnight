"""Says what makes up the night's canvas item count, by part of the screen (issue #1216).

    python3 tools/perf/canvas_parts.py <report.json> [<report.json> ...] [--markdown]

`<report.json>` is a run of the budget's command with `--canvasparts=1` added (`game/tools/bench/perf_sampler.gd`
writes `canvas_parts` into every row). For the steady rows, the ones `check_budget.py` judges, it prints each part's
least, mean and most items and the total's, so the part that makes the peak is named. With more than one report it
also prints the peak of each, which shows how much the peak moves between runs of one commit.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_budget import steady_rows


def table(report: dict, budget: dict) -> list[tuple[str, int, float, int]]:
    """(part, least, mean, most) of the steady rows, the biggest first."""
    rows = [row for row in steady_rows(report["samples"], budget) if "canvas_parts" in row]
    if not rows:
        return []
    names = sorted({name for row in rows for name in row["canvas_parts"]})
    out = []
    for name in names:
        counts = [row["canvas_parts"].get(name, 0) for row in rows]
        out.append((name, min(counts), statistics.fmean(counts), max(counts)))
    out.sort(key=lambda entry: (-entry[3], entry[0]))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--budget", type=Path, default=HERE / "budget.json")
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    budget = json.loads(args.budget.read_text())
    peaks = []
    for path in args.reports:
        report = json.loads(path.read_text())
        rows = steady_rows(report["samples"], budget)
        peak = max(row["canvas_items"] for row in rows)
        peaks.append(peak)
        print(f"{path.name}: {len(rows)} steady rows, canvas_items peak {peak}")
    first = json.loads(args.reports[0].read_text())
    entries = table(first, budget)
    if entries:
        print()
        head = "| Part | Least | Mean | Most |" if args.markdown else "part  least  mean  most"
        print(head)
        if args.markdown:
            print("| --- | ---: | ---: | ---: |")
        for name, least, mean, most in entries:
            if args.markdown:
                print(f"| {name} | {least} | {mean:.1f} | {most} |")
            else:
                print(f"{name}  {least}  {mean:.1f}  {most}")
        total = sum(most for _, _, _, most in entries)
        print(f"(sum of the parts' most: {total}; the peak of the whole is {peaks[0]})")
    if len(peaks) > 1:
        print(f"peaks: {peaks} (spread {max(peaks) - min(peaks)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
