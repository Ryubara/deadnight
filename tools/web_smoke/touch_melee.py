"""The touch quick-melee button in a real browser (#588): real touches on a phone-sized landscape page.

The run exports a copy of the project that starts on `game/tests/captures/touch_melee_bench.tscn` (the real project's
export leaves `tests/` out): the game's own night screen with the touch layer forced on and one zombie held in reach
of the blow. In a headless Chrome with touch emulation it sends what a thumb would, through the DevTools protocol: a
tap on the MELEE button, then two more taps inside the cooldown, then a tap after it, once right-handed and once
left-handed. It reads what the game reports (`window.__melee`): the blows the server made, the zombies it hurt, whether
the night paused.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_melee.py <godot> <work folder> [--out <folder>]

`<godot>` is the pinned Godot (`gds tool path godot`). It fails when the browser logs an error, when the night is
paused, when a tap does not strike, when three taps inside 0.6 s make more than the one blow, or when a tap after the
cooldown does not strike again.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke
import touch_assist

BENCH_SCENE = "res://tests/captures/touch_melee_bench.tscn"
VIEWPORT = {"width": 844, "height": 390}
READY_TIMEOUT_S = 240
# The quick melee's cooldown is 0.6 s: taps closer than this are one blow, a tap after it is another.
COOLDOWN_S = 0.6
RUNS = {"right": "touch=1&left=0", "left": "touch=1&left=1"}


def state(page: Page) -> dict:
    return page.evaluate("window.__melee || {}") or {}


def tap(client: CDPSession, x: float, y: float, hold_s: float = 0.12) -> None:
    touch_assist.touch(client, "touchStart", [(1, x, y)])
    time.sleep(hold_s)
    touch_assist.touch(client, "touchEnd", [])


def run_once(url: str, label: str, query: str, out: Path | None) -> dict:
    problems: list[str] = []
    steps: dict[str, int] = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(viewport=VIEWPORT, has_touch=True, is_mobile=True)
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.on("console", lambda m: problems.append(f"console {m.type}: {m.text}") if m.type == "error" else None)
        page.goto(f"{url}?{query}", wait_until="commit")
        deadline = time.monotonic() + READY_TIMEOUT_S
        while time.monotonic() < deadline and not state(page).get("ready"):
            time.sleep(0.5)
        if not state(page).get("ready"):
            raise TimeoutError(f"{label}: the bench never got ready: {state(page)}")
        client = context.new_cdp_session(page)
        time.sleep(1.0)
        x, y = state(page)["melee"]
        if out is not None:
            out.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(out / f"touch_melee_{label}_before.png"))
        touch_assist.touch(client, "touchStart", [(1, x, y)])
        time.sleep(0.15)
        if out is not None:
            page.screenshot(path=str(out / f"touch_melee_{label}_tap.png"))
        touch_assist.touch(client, "touchEnd", [])
        time.sleep(0.3)
        steps["one_tap"] = state(page)["blows"]
        # Two more taps, 0.2 s apart: all inside the first blow's 0.6 s.
        for _ in range(2):
            tap(client, x, y, 0.1)
            time.sleep(0.1)
        time.sleep(0.2)
        steps["three_taps"] = state(page)["blows"]
        time.sleep(COOLDOWN_S + 0.6)
        tap(client, x, y)
        time.sleep(0.4)
        steps["after_cooldown"] = state(page)["blows"]
        result = {"steps": steps, "end": state(page), "problems": problems}
        browser.close()
    return result


def verdict(label: str, result: dict) -> list[str]:
    steps, end = result["steps"], result["end"]
    wrong = [f"{label}: {p}" for p in result["problems"]]
    if end.get("paused"):
        wrong.append(f"{label}: the night paused ({end.get('grip_lost')} times the mouse was lost)")
    if not end.get("touch"):
        wrong.append(f"{label}: the game never saw a finger as the last input")
    if steps["one_tap"] != 1:
        wrong.append(f"{label}: a tap made {steps['one_tap']} blows, wanted 1")
    if steps["three_taps"] != 1:
        wrong.append(f"{label}: three taps inside the cooldown made {steps['three_taps']} blows, wanted 1")
    if steps["after_cooldown"] != 2:
        wrong.append(f"{label}: a tap after the cooldown made {steps['after_cooldown']} blows in all, wanted 2")
    if end.get("hurt", 0) < 1:
        wrong.append(f"{label}: no blow hurt the zombie in reach")
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="where the screenshots go")
    args = parser.parse_args()
    touch_assist.BENCH_SCENE = BENCH_SCENE
    web = touch_assist.export_bench(args.godot, args.work)
    server, port = smoke.serve(web)
    failed: list[str] = []
    try:
        for label, query in RUNS.items():
            try:
                result = run_once(f"http://127.0.0.1:{port}/index.html", label, query, args.out)
                print(label, json.dumps({"steps": result["steps"], "end": result["end"]}))
                failed += verdict(label, result)
            except (RuntimeError, TimeoutError) as error:
                failed.append(str(error))
    finally:
        server.shutdown()
    for line in failed:
        print("FAILED:", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
