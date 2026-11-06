"""The challenge card on a phone's page in the web build, with a full room's HUD (issue #1299).

Exports a copy of the project that starts on `game/tests/captures/challenge_card_phone.tscn` (the real project's export
leaves `tests/` out): the real HUD and touch controls, eight people and seven bots, every perk, the point gains up, and
the card of a daily challenge with three lines, at each interface size (0.8, 1.0, 1.25). Opens it in Chrome as a phone
(a page of 844 x 390 or 667 x 375 CSS px at a pixel ratio of 2, touch), reads what the scene publishes
(`window.__card`) and checks, in CSS px of the page, that the card:

- is inside the page and clear of every part of the HUD and of every touch button and place;
- is short of the middle of the screen (the reticle's box) and the crosshair.

Screenshots (`<page>-<hand>-<case>.png`) and `result.json` go to the out folder. Exits 1 on any check that fails.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/challenge_card_phone.py <godot> <work folder> \\
        <out folder> [--pages 844,667] [--hands right,left] [--build <folder of an earlier export>]
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

SCENE = "res://tests/captures/challenge_card_phone.tscn"
PAGES = {"844": (844, 390), "667": (667, 375)}
RATIO = 2
TIMEOUT_S = 300
# How long after a case is published the screenshot is taken: the scene holds each case until it is told.
SHOT_AFTER_S = 0.5
# The reticle's clear box, canvas units, either side of the middle.
CLEAR = 80.0


def rect(text: str) -> tuple[float, float, float, float]:
    x, y, w, h = (float(n) for n in text.split(","))
    return x, y, x + w, y + h


def meets(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def faults(case: dict) -> list[str]:
    """What is wrong with the card of one published case, in canvas units."""
    canvas_w, canvas_h = (float(n) for n in case["canvas"].split(","))
    card = rect(case["card"])
    found = []
    if card[0] < 0 or card[1] < 0 or card[2] > canvas_w or card[3] > canvas_h:
        found.append(f"the card {card} leaves the canvas")
    middle = (canvas_w / 2 - CLEAR, canvas_h / 2 - CLEAR, canvas_w / 2 + CLEAR, canvas_h / 2 + CLEAR)
    if meets(card, middle):
        found.append(f"the card {card} is over the middle of the screen")
    for entry in filter(None, case["parts"].split("|")):
        name, _, text = entry.partition(":")
        if meets(card, rect(text)):
            found.append(f"the card {card} overlaps {name} {rect(text)}")
    for text in filter(None, case["held"].split("|")):
        if meets(card, rect(text)):
            found.append(f"the card {card} is over the touch box {rect(text)}")
    return found


def film(playwright, url: str, out: Path, tag: str, width: int, height: int) -> dict:
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
            state = page.evaluate("window.__card || null")
            if state and state.get("done"):
                break
            if state and state.get("index", 0) > seen:
                seen = state["index"]
                time.sleep(SHOT_AFTER_S)
                page.screenshot(path=str(out / f"{tag}-{state['case']}.png"))
                page.evaluate(f"window.__card_ack = {seen}")
                problems = faults(state)
                result["cases"].append({"case": state["case"], "card": state["card"], "canvas": state["canvas"]})
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
                    query = "?touch=1" + ("&left=1" if hand == "left" else "")
                    width, height = PAGES[key]
                    outcome = film(
                        p, f"http://127.0.0.1:{port}/index.html{query}", args.out, f"{key}-{hand}", width, height
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
