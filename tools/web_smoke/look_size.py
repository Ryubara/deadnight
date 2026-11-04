"""Browser check that one mouse pixel turns the view the same at every canvas size (#928).

The project stretches the canvas to a 1920 x 1080 base, and the engine hands a mouse motion to the game in the canvas's
units: `relative` is the browser's `movementX` times `1920 / canvas width`. The player turns by `screen_relative`
(the unscaled motion), so the same 300 pixels of the hand turn the view the same in a 1280 pixel wide window, a 1920
one or an 800 one, and on a screen with a pixel ratio of 2. This run starts a night in headless Chromium, takes the
pointer lock, resizes the page's viewport, sends 20 pointer moves of 15 pixels (the way `smoke.py` does) at each size,
reads the yaw the game publishes (`window.deadnight.yaw`) and fails when the turns differ by more than 3 percent. It
runs at a device pixel ratio of 1 and of 2: the web runtime reports device pixels, which the look divides out.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/look_size.py build/web build/look-size

Run it under `gds quiet`: headless Chromium on Windows clips the real cursor to an invisible box at the top left of the
screen on pointer lock, freed only by Esc. It refuses to start there outside `gds quiet` (`GDS_QUIET=1`).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright
from pointer_lock import MOTION_JS, SOFTWARE_GL, probe, serve, wait_lock
from smoke import reach_menu, start_solo, wait_for_night

# At a pixel ratio of 2 the canvas is twice as many pixels each way, which a software renderer draws at a frame or two a
# second and then loses motions to: only the small viewports are run at 2.
SIZES = {
    1: [(1280, 720), (1920, 1080), (800, 450), (1000, 1400)],
    2: [(1280, 720), (800, 450)],
}
MOTION_PIXELS = 15
MOTIONS = 20
SAME_WITHIN = 0.03
LOCK_TIMEOUT_S = 10


def yaw_turn(page: Page) -> float:
    """How far the view turned (radians) for MOTIONS moves of MOTION_PIXELS."""
    before = probe(page).get("yaw", 0.0)
    for _ in range(MOTIONS):
        page.evaluate(MOTION_JS, MOTION_PIXELS)
        page.wait_for_timeout(30)
    # Wait until the yaw stops moving (a slow frame may still be holding the last motions).
    after = probe(page).get("yaw", 0.0)
    for _ in range(40):
        page.wait_for_timeout(500)
        latest = probe(page).get("yaw", 0.0)
        if latest == after:
            break
        after = latest
    return math.remainder(after - before, 2 * math.pi)


def run(browser, url: str, out: Path, result: dict) -> None:
    for ratio, sizes in SIZES.items():
        context = browser.new_context(viewport={"width": 1280, "height": 720}, device_scale_factor=ratio)
        page = context.new_page()
        try:
            page.goto(url, wait_until="commit")
            reach_menu(page)
            start_solo(page)
            wait_for_night(page)
            page.mouse.move(640, 360)
            page.mouse.down()
            page.mouse.up()
            if not wait_lock(page, True, LOCK_TIMEOUT_S):
                raise RuntimeError("the night never got the pointer lock")
            page.wait_for_timeout(800)
            for width, height in sizes:
                page.set_viewport_size({"width": width, "height": height})
                page.wait_for_timeout(1500)
                turn = yaw_turn(page)
                result[f"turn_rad_{width}x{height}_dpr{ratio}"] = round(turn, 4)
                page.screenshot(path=out / f"{width}x{height}_dpr{ratio}.png", timeout=120000)
        finally:
            context.close()


def main() -> int:
    quiet = os.environ.get("GDS_QUIET") == "1" or os.environ.get("GDS_ALLOW_POINTER_LOCK") == "1"
    if sys.platform == "win32" and not quiet:
        print("refusing to take pointer lock on Windows outside `gds quiet` (see the docstring)", file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", type=Path, help="the exported web folder")
    parser.add_argument("out", type=Path, help="where the report and screenshots go")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    result: dict = {}
    server, port = serve(args.build)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        try:
            run(browser, f"http://127.0.0.1:{port}/index.html", args.out, result)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
        finally:
            browser.close()
            server.shutdown()
    turns = [v for k, v in result.items() if k.startswith("turn_rad_")]
    if turns:
        first = abs(turns[0])
        if first < 0.1:
            problems.append(f"[check] the view barely turned ({first} rad)")
        for key, value in result.items():
            if key.startswith("turn_rad_") and abs(abs(value) - first) > SAME_WITHIN * first:
                problems.append(f"[check] {key} = {value} differs from the first size's {turns[0]}")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\nlook size check FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\nlook size check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
