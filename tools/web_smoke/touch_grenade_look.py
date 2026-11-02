"""A thumb that holds the Grenade button turns the view by dragging, in a phone-sized browser (issue #599).

Opens the exported game (`?touch=1`) in Chrome with mobile emulation (779 x 360 CSS pixels at a pixel ratio of 3, a
1168 x 540 unit canvas, real touch events through the DevTools protocol), starts a night with the keyboard, puts a finger
on the Grenade button and keeps it there while the pin is out (`HOLD_S`), then drags it `DRAG_PX` to the right. The
game reports the camera's yaw (`window.deadnight.yaw`, game/core/web_probe.gd): the run reads it before the hold, at the
end of the hold and after the drag, and takes a screenshot at each. Before #599 the view stayed where it was; the drag
from Grenade now turns it like a drag from Fire or Aim.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_grenade_look.py build/web build/grenade_look

The first argument is the exported folder or a URL; the second is where the screenshots and `result.json` go. Exits 1
when the drag turned the view by less than `MIN_TURN_RAD` (use `--expect-still` to check the opposite on an older build).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke
import touch_look

VIEWPORT = {"width": 779, "height": 360}
DEVICE_SCALE = 3
# The Grenade button's centre in CSS pixels, read off a screenshot of the 779 x 360 phone (the canvas is scaled, so the
# layout's offsets in units do not map by a plain ratio).
GRENADE_FROM = (606.0, 305.0)
HOLD_S = 1.2
DRAG_PX = 100.0
STEPS = 20
STEP_PERIOD_S = 0.03
SETTLE_S = 0.8
MIN_TURN_RAD = 0.1


def yaw(page: Page) -> float:
    page.wait_for_timeout(400)  # the probe refreshes the game's numbers every 0.25 s
    return float(smoke.probe(page).get("yaw", 0.0))


def run(url: str, out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    result: dict = {"viewport": VIEWPORT, "device_scale_factor": DEVICE_SCALE}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
        context = browser.new_context(
            viewport=VIEWPORT, device_scale_factor=DEVICE_SCALE, has_touch=True, is_mobile=True
        )
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.add_init_script("(" + touch_look.NO_POINTER_LOCK_JS.strip() + ")();")
        page.goto(f"{url}?touch=1", wait_until="commit")
        touch_look.start_night(page)
        client = context.new_cdp_session(page)
        x, y = GRENADE_FROM
        before = yaw(page)
        page.screenshot(path=str(out / "1_before_hold.png"))
        touch_look.touch(client, "touchStart", [(1, x, y)])
        time.sleep(HOLD_S)
        held = yaw(page)
        page.screenshot(path=str(out / "2_held.png"))
        for step in range(1, STEPS + 1):
            touch_look.touch(client, "touchMove", [(1, x + DRAG_PX * step / STEPS, y)])
            time.sleep(STEP_PERIOD_S)
        time.sleep(SETTLE_S)
        dragged = yaw(page)
        page.screenshot(path=str(out / "3_dragged_still_held.png"))
        touch_look.touch(client, "touchEnd", [])
        time.sleep(0.5)
        page.screenshot(path=str(out / "4_thrown.png"))
        browser.close()
    result.update(
        {
            "yaw_before_hold": before,
            "yaw_held": held,
            "yaw_after_drag": dragged,
            "hold_turn_rad": abs(math.remainder(held - before, math.tau)),
            "drag_turn_rad": abs(math.remainder(dragged - held, math.tau)),
            "problems": problems,
        }
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--expect-still", action="store_true", help="exit 1 when the drag DID turn the view")
    args = parser.parse_args()
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    try:
        result = run(url, args.out)
    finally:
        if server:
            server.shutdown()
    wrong = list(result["problems"])
    turned = result["drag_turn_rad"]
    if args.expect_still and turned >= MIN_TURN_RAD:
        wrong.append(f"the drag from Grenade turned the view {turned:.3f} rad")
    if not args.expect_still and turned < MIN_TURN_RAD:
        wrong.append(f"the drag from Grenade turned the view only {turned:.3f} rad")
    result["wrong"] = wrong
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    for line in wrong:
        print("FAILED:", line)
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
