"""Shots land on the crosshair in a real browser, at phone size, with real touches (#601).

The run exports a copy of the project that starts on `game/tests/captures/shot_bench.tscn` (the real project's export
leaves `tests/` out): the game's own night screen with the touch layer on, a phone's safe area given by the query, and
a wall that the bench puts square across the reticle at the distance this script asks for. In a headless Chrome
with touch emulation at 844 x 390 (the night's canvas is 540 units high there) it then touches the Fire button, from
the hip and with the Aim button held, at close, middle and far range, and reads what the game measured for every
shot (`window.__shot.results`): how far in canvas units the camera draws the end of the shot from the reticle.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/shot_on_crosshair.py <godot> <work folder> [--out <folder>]

`<godot>` is the pinned Godot (`gds tool path godot`); the copy and its export are made in `<work folder>`. The runs:
no safe area (a desktop or an Android phone without a notch) and an iPhone held sideways (59 CSS pixels each side,
21 under the picture for the home bar). It fails when a shot lands further than `TOLERANCE` canvas units from the
reticle, when a touch fires no shot, when the browser logs an error, when the night is paused, or when the canvas is
not the phone's 540 units high.
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

BENCH_SCENE = "res://tests/captures/shot_bench.tscn"
VIEWPORT = {"width": 844, "height": 390}
CANVAS_HEIGHT = 540.0
READY_TIMEOUT_S = 240
ORDER_TIMEOUT_S = 15
SHOT_TIMEOUT_S = 8
AIM_EASE_S = 1.0
TAP_S = 0.12
IMPACT_S = 0.12
# The same bound the suite holds (`test_shot_on_crosshair.gd`): well under the reticle's own gap.
TOLERANCE = 1.5
DISTANCES = (4.0, 10.0, 22.0)
RUNS = {
    "no_insets": "insets=0,0,0,0",
    "iphone": "insets=59,0,59,21",
}


def shot_state(page: Page) -> dict:
    return page.evaluate("window.__shot || {}") or {}


def touch(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    client.send(
        "Input.dispatchTouchEvent",
        {"type": kind, "touchPoints": [{"id": i, "x": x, "y": y} for i, x, y in points]},
    )


def wait_for(page: Page, test, seconds: float, what: str) -> dict:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        seen = shot_state(page)
        if seen.get("failed"):
            raise RuntimeError(seen["failed"])
        if test(seen):
            return seen
        time.sleep(0.05)
    raise TimeoutError(f"gave up waiting for {what}: {json.dumps(shot_state(page))[:300]}")


def fire_once(page: Page, client: CDPSession, seq: int, metres: float, aimed: bool, shot: Path | None) -> dict:
    """Puts the wall `metres` away, aims (a finger held on Aim) or not, taps Fire; returns the shot measured."""
    page.evaluate(f"window.__shotWant = {{seq: {seq}, metres: {metres}}}")
    ready = wait_for(page, lambda s: s.get("ready") == seq, ORDER_TIMEOUT_S, f"the wall at {metres} m")
    shots_before = len(ready["results"])
    if aimed:
        touch(client, "touchStart", [(2, *ready["aim"])])
        time.sleep(AIM_EASE_S)
    touch(client, "touchStart", [(2, *ready["aim"]), (1, *ready["fire"])] if aimed else [(1, *ready["fire"])])
    time.sleep(TAP_S)
    touch(client, "touchEnd", [(2, *ready["aim"])] if aimed else [])
    seen = wait_for(page, lambda s: len(s["results"]) > shots_before, SHOT_TIMEOUT_S, "the shot")
    time.sleep(IMPACT_S)
    if shot is not None:
        page.screenshot(path=str(shot))
    if aimed:
        touch(client, "touchEnd", [])
    time.sleep(0.4)
    return {**seen["results"][-1], "paused": seen["paused"]}


def run_once(url: str, label: str, query: str, out: Path | None) -> dict:
    problems: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(viewport=VIEWPORT, has_touch=True, is_mobile=True)
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.on(
            "console",
            lambda m: problems.append(f"console {m.type}: {m.text}") if m.type == "error" else None,
        )
        page.goto(f"{url}?{query}", wait_until="commit")
        wait_for(page, lambda s: bool(s.get("fire")), READY_TIMEOUT_S, "the bench to start")
        time.sleep(3.0)  # the shoulder camera eases into place
        client = context.new_cdp_session(page)
        if out is not None:
            out.mkdir(parents=True, exist_ok=True)
        seen = shot_state(page)
        shots: dict[str, dict] = {}
        seq = 0
        for aimed in (False, True):
            for metres in DISTANCES:
                seq += 1
                key = f"{'aimed' if aimed else 'hip'} {metres:.0f} m"
                path = out / f"shot_{label}_{key.replace(' ', '_')}.png" if out is not None else None
                shots[key] = fire_once(page, client, seq, metres, aimed, path)
        browser.close()
    return {
        "problems": problems,
        "canvas": seen["canvas"],
        "insets": seen["insets"],
        "reticle": seen["reticle"],
        "shots": shots,
    }


def verdict(runs: dict[str, dict]) -> list[str]:
    wrong: list[str] = []
    for label, result in runs.items():
        wrong += [f"{label}: {p}" for p in result["problems"]]
        if abs(result["canvas"][1] - CANVAS_HEIGHT) > 0.5:
            wrong.append(f"{label}: the canvas is {result['canvas'][1]} units high, not the phone's {CANVAS_HEIGHT}")
        for key, shot in result["shots"].items():
            if shot["paused"]:
                wrong.append(f"{label}: the night paused at {key}")
            if shot["off"] >= TOLERANCE:
                wrong.append(
                    f"{label}: {key}: the shot is drawn {shot['off']:.2f} units off the reticle "
                    f"({shot['degrees']:.2f} degrees)"
                )
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="where the screenshots go")
    parser.add_argument("--only", choices=sorted(RUNS), default=None, help="run one of the safe-area cases")
    args = parser.parse_args()
    web = touch_assist.export_bench(args.godot, args.work, BENCH_SCENE)
    server, port = smoke.serve(web)
    runs: dict[str, dict] = {}
    try:
        for label, query in RUNS.items():
            if args.only in (None, label):
                runs[label] = run_once(f"http://127.0.0.1:{port}/index.html", label, query, args.out)
    finally:
        server.shutdown()
    (args.work / "shot_on_crosshair.json").write_text(json.dumps(runs, indent=1) + "\n", encoding="utf-8")
    for label, result in runs.items():
        print(label, "canvas", result["canvas"], "insets", [round(v, 1) for v in result["insets"]])
        for key, shot in result["shots"].items():
            print(f"  {key:>10}: {shot['off']:.3f} units off, {shot['degrees']:.3f} degrees")
    wrong = verdict(runs)
    for line in wrong:
        print("FAILED:", line)
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
