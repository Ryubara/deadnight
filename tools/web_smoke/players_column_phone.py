"""The players' column on a phone's page in the web build, with a full room's HUD (issue #1301).

Exports a copy of the project that starts on `game/tests/captures/players_column_phone.tscn` (the real project's export
leaves `tests/` out): the real HUD and touch controls, eight people and seven bots, every perk, the objective on its two
lines, two people down, at each interface size (0.8, 1.0, 1.25). Opens it in Chrome as a phone (a page of 844 x 390 or
667 x 375 CSS px at a pixel ratio of 2, touch), reads what the scene publishes (`window.__column`) and checks, in the
canvas's units, that the column (the HUD's Points part):

- is inside the page;
- is clear of the round, the objective, the health card, the perk badges and the weapon strip.

It also reports each case's type size for a teammate's points in CSS px of the page, and checks the round card is one
row high (at most 96 units; `--oldcard` puts it back in its three lines, 160 units, and turns that check off: the
Before pictures of #1305). `--nofit` opens the scene with the column's room taken away once it has settled: the column
as it was before the change (the Before pictures, which are expected to fail the check). Screenshots
(`<page>-<hand>-<case>.png`) and `result.json` go to the out folder. Exits 1 on any check that fails.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/players_column_phone.py <godot> <work folder> \\
        <out folder> [--pages 844,667] [--hands right,left] [--nofit] [--oldcard] [--bots 7] [--people 8] [--build <folder of an earlier export>]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import smoke

SCENE = "res://tests/captures/players_column_phone.tscn"
PAGES = {"844": (844, 390), "667": (667, 375)}
RATIO = 2
TIMEOUT_S = 300
# How long after a case is published the screenshot is taken: the scene holds each case until it is told.
SHOT_AFTER_S = 0.5
NEIGHBOURS = ("Round", "Objective", "Health", "Perks", "Slots")
# The round card on one row (#1305) stands about this high, canvas units; in three lines it is 160.
ONE_ROW_MAX = 96.0


def rect(text: str) -> tuple[float, float, float, float]:
    x, y, w, h = (float(n) for n in text.split(","))
    return x, y, x + w, y + h


def meets(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def parts_of(case: dict) -> dict[str, tuple[float, float, float, float]]:
    found = {}
    for entry in filter(None, case["parts"].split("|")):
        name, _, text = entry.partition(":")
        found[name] = rect(text)
    return found


def faults(case: dict, one_row: bool = True) -> list[str]:
    """What is wrong with the column (and, with `one_row`, the round card) of one published case, canvas units."""
    canvas_w, canvas_h = (float(n) for n in case["canvas"].split(","))
    parts = parts_of(case)
    column = parts["Points"]
    found = []
    if column[0] < 0 or column[1] < 0 or column[2] > canvas_w or column[3] > canvas_h:
        found.append(f"the column {column} leaves the canvas")
    for name in NEIGHBOURS:
        if name in parts and meets(column, parts[name]):
            found.append(f"the column {column} overlaps {name} {parts[name]}")
    if one_row and parts["Round"][3] - parts["Round"][1] > ONE_ROW_MAX:
        found.append(f"the round card {parts['Round']} is taller than one row ({ONE_ROW_MAX})")
    return found


def film(playwright, url: str, out: Path, tag: str, width: int, height: int, one_row: bool) -> dict:
    browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    result: dict = {"tag": tag, "cases": [], "errors": [], "faults": []}
    try:
        page = browser.new_page(
            viewport={"width": width, "height": height}, device_scale_factor=RATIO, is_mobile=True, has_touch=True
        )
        page.on("pageerror", lambda error: result["errors"].append(str(error)))
        page.on("console", lambda m: result["errors"].append(m.text) if m.type == "error" else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        seen = 0
        while time.monotonic() < deadline:
            state = page.evaluate("window.__column || null")
            if state and state.get("done"):
                break
            if state and state.get("index", 0) > seen:
                seen = state["index"]
                time.sleep(SHOT_AFTER_S)
                page.screenshot(path=str(out / f"{tag}-{state['case']}.png"))
                page.evaluate(f"window.__column_ack = {seen}")
                problems = faults(state, one_row)
                canvas_h = float(state["canvas"].split(",")[1])
                column = parts_of(state)["Points"]
                result["cases"].append(
                    {
                        "case": state["case"],
                        "canvas": state["canvas"],
                        "pairs": state["pairs"],
                        "round_card_units": round(parts_of(state)["Round"][3] - parts_of(state)["Round"][1], 1),
                        "column": list(column),
                        "mate_type_css_px": round(state["mate_type"] * height / canvas_h, 1),
                    }
                )
                result["faults"].extend(f"{tag} {state['case']}: {p}" for p in problems)
            time.sleep(0.05)
        else:
            result["errors"].append("never finished")
        return result
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--pages", default="844,667")
    parser.add_argument("--hands", default="right,left")
    parser.add_argument("--nofit", action="store_true", help="the column as it was before the change")
    parser.add_argument("--bots", type=int, default=7, help="bots on top of the people (the chips)")
    parser.add_argument("--people", type=int, default=8)
    parser.add_argument("--oldcard", action="store_true", help="the round card in three lines (the Before pictures)")
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    results = []
    try:
        with sync_playwright() as p:
            for key in args.pages.split(","):
                for hand in args.hands.split(","):
                    query = (
                        "?touch=1&down=1"
                        + ("&left=1" if hand == "left" else "")
                        + ("&nofit=1" if args.nofit else "")
                        + ("&oldcard=1" if args.oldcard else "")
                        + f"&bots={args.bots}&people={args.people}"
                    )
                    width, height = PAGES[key]
                    outcome = film(
                        p,
                        f"http://127.0.0.1:{port}/index.html{query}",
                        args.out,
                        f"{key}-{hand}",
                        width,
                        height,
                        not args.oldcard,
                    )
                    print(
                        outcome["tag"],
                        len(outcome["cases"]),
                        "cases",
                        outcome["faults"][:3],
                        outcome["errors"][:3],
                        flush=True,
                    )
                    results.append(outcome)
    finally:
        server.shutdown()
    (args.out / "result.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 1 if any(r["errors"] or r["faults"] for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
