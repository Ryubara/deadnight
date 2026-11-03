"""The web smoke's gate on the time a night takes to load (issue #873, docs/research/web-export.md "Loading a night").

The gate is the night's load divided by the same run's load to the menu, not a number of seconds: the web job's runner
moves the same build by a factor of three (24.8 to 75.3 s for the night, 8.6 to 17.5 s for the menu), and both times
move with it. A hard ceiling stays as a backstop, so a hang still fails. The limits live in
`night_load_baseline.json`.

Replay a set of results (the gate's reading of runs that already happened):

    python -I tools/web_smoke/night_load.py <result.json> [<result.json> ...]
"""

from __future__ import annotations

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


def main(paths: list[str]) -> int:
    baseline = read_baseline()
    failed = 0
    for path in paths:
        result = json.loads(Path(path).read_text(encoding="utf-8"))
        night_s = result.get("loading", {}).get("seconds")
        if night_s is None:
            continue
        menu_s = result.get("load_to_menu_s")
        seen = reading(night_s, menu_s, baseline)
        problems = problems_for(night_s, menu_s, baseline)
        failed += bool(problems)
        print(f"{'FAIL' if problems else 'ok  '} night {night_s:6} s  menu {menu_s:5} s  ratio {seen['ratio']}  {path}")
    print(
        f"{failed} of {len(paths)} would fail (ratio limit {baseline['max_ratio']}, ceiling {baseline['ceiling_s']} s)"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
