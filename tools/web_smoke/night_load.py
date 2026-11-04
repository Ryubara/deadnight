"""The web smoke's gate on the time a night takes to load (issues #873 and #966, docs/research/web-export.md
"Loading a night").

The gate is the night's load divided by the same run's load to the menu, with the menu's time floored at the menu a
runner usually takes (`menu_floor_s`): the web job's runner moves the same build by a factor of three (25 to 95 s for
the night, 8 to 18 s for the menu), and the menu follows it a little. The floor keeps the gate from moving when the
menu itself loads faster or slower for a reason of the game's (#920 made it load in 7 s where it took 9 to 18, and the
night over the menu went over the limit with the night unchanged). A hard ceiling stays as a backstop, so a hang still
fails. The limits live in `night_load_baseline.json`; what the gate cannot see is held by the frame count in
`tests/night/test_load_cost.gd`.

Replay a set of results (the gate's reading of runs that already happened); `--scale 1.5` makes every night 50 %
longer first (a stand-in for a regression), `--baseline <file>` reads other limits:

    python -I tools/web_smoke/night_load.py [--scale F] [--baseline FILE] <result.json> [<result.json> ...]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BASELINE_FILE = Path(__file__).with_name("night_load_baseline.json")


def read_baseline() -> dict:
    return json.loads(BASELINE_FILE.read_text(encoding="utf-8"))


def reading(night_s: float, menu_s: float | None, baseline: dict) -> dict:
    """The numbers the gate looks at: both times, the ratio, and the two limits."""
    # A menu faster than the floor (a lucky page load) would make the ratio jump with nothing wrong.
    floor = baseline["menu_floor_s"]
    ratio = None if menu_s is None else round(night_s / max(menu_s, floor), 2)
    return {
        "night_s": night_s,
        "menu_s": menu_s,
        "ratio": ratio,
        "ratio_limit": baseline["max_ratio"],
        "ceiling_s": baseline["ceiling_s"],
    }


def problems_for(night_s: float, menu_s: float | None, baseline: dict) -> list[str]:
    seen = reading(night_s, menu_s, baseline)
    out: list[str] = []
    if night_s > baseline["ceiling_s"]:
        out.append(
            f"[loading] the night took {night_s} s to load, over the backstop of {baseline['ceiling_s']} s "
            "(tools/web_smoke/night_load_baseline.json): no runner seen was this slow, so something hangs or the "
            "load grew by far more than a slow runner explains (docs/research/web-export.md, 'Loading a night')"
        )
    if seen["ratio"] is not None and seen["ratio"] > baseline["max_ratio"]:
        out.append(
            f"[loading] the night took {night_s} s to load, {seen['ratio']}x the {menu_s} s this run took to reach "
            f"the menu (limit {baseline['max_ratio']}x, tools/web_smoke/night_load_baseline.json): the same runner "
            "loaded the menu at its usual speed and the night slower, so the night's loading grew "
            "(docs/research/web-export.md, 'Loading a night')"
        )
    return out


def night_load_problems(result: dict, gpu: bool, deployed: bool) -> list[str]:
    """The night's load against the limits, for the software renderer (no GPU, a build served here)."""
    night_s = result.get("loading", {}).get("seconds")
    if night_s is None or gpu or deployed or not BASELINE_FILE.exists():
        return []
    baseline = read_baseline()
    seen = reading(night_s, result.get("load_to_menu_s"), baseline)
    result["night_load"] = seen
    return problems_for(night_s, result.get("load_to_menu_s"), baseline)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Replay the night-load gate on saved web smoke results.")
    parser.add_argument("results", nargs="+", help="result.json files of web smoke runs")
    parser.add_argument("--scale", type=float, default=1.0, help="multiply every night's load time by this first")
    parser.add_argument("--baseline", type=Path, default=BASELINE_FILE, help="limits to read (default: the gate's)")
    parser.add_argument("--quiet", action="store_true", help="print the count only")
    args = parser.parse_args(argv)
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    failed = 0
    seen_runs = 0
    for path in args.results:
        result = json.loads(Path(path).read_text(encoding="utf-8"))
        night_s = result.get("loading", {}).get("seconds")
        if night_s is None:
            continue
        night_s = round(night_s * args.scale, 2)
        menu_s = result.get("load_to_menu_s")
        seen = reading(night_s, menu_s, baseline)
        problems = problems_for(night_s, menu_s, baseline)
        seen_runs += 1
        failed += bool(problems)
        if not args.quiet:
            print(
                f"{'FAIL' if problems else 'ok  '} night {night_s:6} s  menu {menu_s:5} s  ratio {seen['ratio']}  {path}"
            )
    print(
        f"{failed} of {seen_runs} would fail at night x{args.scale} "
        f"(ratio limit {baseline['max_ratio']} over the menu, floor {baseline['menu_floor_s']} s, "
        f"ceiling {baseline['ceiling_s']} s)"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
