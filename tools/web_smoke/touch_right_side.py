"""The right thumb's buttons in a real phone-sized browser, with real touches (issue #1277).

Opens the exported game (`?touch=1`) in Chrome with mobile emulation (a phone page of `--page` CSS pixels at a pixel
ratio of 2, as the page caps it), starts a night, and sends what a right thumb does through the DevTools protocol:

- every button of the right thumb (Fire, Aim, Reload, Jump, Crouch and the ones that wait for the audit's homes) is
  pressed by a finger on its centre, and the same finger is dragged `DRAG_PX` CSS pixels: the game says the button is
  held the whole time (`touch_held`) and the view turns (`yaw`), so a thumb on Reload turns the camera;
- there is no bot wheel button (the bots' order is the HUD's tag, `touch_bot_tag.py`);
- a finger that lands just outside Reload's hit area and drags across Reload turns the view and presses nothing;
- a tap on Crouch crouches and stays crouched (`crouching`), a second tap stands, and Jump from a crouch stands up;
- every button is at least 44 CSS px across (its hit area), the least a finger needs.

It takes a screenshot with the fingers lifted and one for each thing held, and measures where each button sits from the
thumb's rest (Fire's centre) in CSS px and millimetres of a 6 CSS px per mm phone.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_right_side.py build/web out [--page 844x390]

The first argument is the exported folder or a URL; the second is where the screenshots and `result.json` go. Exits 1
on any check that fails.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import ingame_menu as menu
import smoke
import touch_look

DEVICE_SCALE = 2
CSS_PX_PER_MM = 6.0
TAP_CSS_PX = 44.0
# The buttons a drag from which turns the view: every button of the right thumb.
LOOKING = ("fire", "aim", "reload", "jump", "crouch", "swap_shoulder", "quick_melee")
DRAG_PX = 90.0
STEPS = 15
STEP_PERIOD_S = 0.03
HOLD_S = 0.4
MIN_TURN_RAD = 0.1
# How far past the edge of Reload's hit area a look begins, in CSS px.
BESIDE_PX = 3.0


def circles(state: dict, page: dict) -> dict[str, dict]:
    """Each button's hit area from the probe's shares: centre and radius in CSS pixels."""
    found = {}
    for entry in str(state.get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, hit, was = (float(n) for n in numbers.split(","))
            found[name] = {
                "x": x * page["width"],
                "y": y * page["height"],
                "hit": hit * page["height"],
                "was": was * page["height"],
            }
    return found


def touch(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    client.send(
        "Input.dispatchTouchEvent",
        {"type": kind, "touchPoints": [{"id": i, "x": x, "y": y} for i, x, y in points]},
    )


def tap(client: CDPSession, at: tuple[float, float]) -> None:
    touch(client, "touchStart", [(1, *at)])
    time.sleep(0.12)
    touch(client, "touchEnd", [])
    time.sleep(0.3)


def state(page: Page) -> dict:
    page.wait_for_timeout(400)  # the probe refreshes the game's numbers every 0.25 s
    return menu.probe(page)


def turn(a: float, b: float) -> float:
    return abs(math.remainder(b - a, math.tau))


def drag_from(
    page: Page,
    client: CDPSession,
    start: tuple[float, float],
    delta: tuple[float, float],
    held: list[str] | None = None,
) -> dict:
    """A finger down at `start`, dragged by `delta`, lifted. Returns the yaw before and after and what was held."""
    before = state(page)
    touch(client, "touchStart", [(1, *start)])
    time.sleep(HOLD_S)
    at_press = state(page)
    for step in range(1, STEPS + 1):
        touch(client, "touchMove", [(1, start[0] + delta[0] * step / STEPS, start[1] + delta[1] * step / STEPS)])
        time.sleep(STEP_PERIOD_S)
        if held is not None and step in (STEPS // 2, STEPS):
            held.append(str(menu.probe(page).get("touch_held", "")))
    time.sleep(0.5)
    after = state(page)
    touch(client, "touchEnd", [])
    time.sleep(0.4)
    return {
        "yaw_before": before["yaw"],
        "yaw_after": after["yaw"],
        "turn_rad": round(turn(before["yaw"], after["yaw"]), 3),
        "held_at_press": str(at_press.get("touch_held", "")),
        "held_while_dragging": held or [],
    }


def run(url: str, out: Path, page_size: dict, tag: str, before: bool = False) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    result: dict = {"page": page_size, "device_scale_factor": DEVICE_SCALE, "problems": problems}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
        context = browser.new_context(
            viewport=page_size, device_scale_factor=DEVICE_SCALE, has_touch=True, is_mobile=True
        )
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.add_init_script("(" + touch_look.NO_POINTER_LOCK_JS.strip() + ")();")
        page.goto(f"{url}?touch=1", wait_until="commit")
        touch_look.start_night(page)
        client = context.new_cdp_session(page)
        layer = menu.wait_for(page, "the touch layer", lambda s: bool(s.get("touch_hits")), 60)
        found = circles(layer, page_size)
        result["button_count"] = len(found)
        result["canvas_px"] = page.evaluate(
            "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
        )
        page.wait_for_timeout(1500)
        page.screenshot(path=str(out / f"{tag}_1_fingers_lifted.png"))

        if before:
            # The build before the rework: the screenshots, and what a drag from Reload does there.
            reload_ = found["reload"]
            touch(client, "touchStart", [(1, reload_["x"], reload_["y"])])
            time.sleep(HOLD_S)
            page.screenshot(path=str(out / f"{tag}_2_thumb_on_reload.png"))
            yaw = state(page)["yaw"]
            for step in range(1, STEPS + 1):
                touch(client, "touchMove", [(1, reload_["x"] - 4.0 * step, reload_["y"] - 2.0 * step)])
                time.sleep(STEP_PERIOD_S)
            time.sleep(0.5)
            result["reload_drag_turn_rad"] = round(turn(yaw, state(page)["yaw"]), 3)
            touch(client, "touchEnd", [])
            browser.close()
            return result

        # Every button is at least a fingertip, and where each sits from the thumb's rest.
        fire = found["fire"]
        reach = {}
        for name, circle in found.items():
            if circle["hit"] * 2 < TAP_CSS_PX - 0.5:
                problems.append(f"[check] the {name} hit area is {circle['hit'] * 2:.1f} CSS px, under {TAP_CSS_PX}")
            gap = math.hypot(circle["x"] - fire["x"], circle["y"] - fire["y"])
            reach[name] = {"css_px": round(gap, 1), "mm": round(gap / CSS_PX_PER_MM, 1)}
        result["from_the_thumbs_rest"] = reach
        result["hit_area_css_px"] = {name: round(c["hit"] * 2, 1) for name, c in found.items()}

        # A finger on each button of the right thumb, dragged: held the whole way, the view turns.
        result["drags"] = {}
        for name in LOOKING:
            if name not in found:
                continue
            circle = found[name]
            held: list[str] = []
            seen = drag_from(page, client, (circle["x"], circle["y"]), (-DRAG_PX, -DRAG_PX * 0.25), held)
            result["drags"][name] = seen
            if seen["held_at_press"] != name:
                problems.append(f"[check] a finger on {name} held {seen['held_at_press']!r}")
            if any(h != name for h in held):
                problems.append(f"[check] dragging from {name} dropped the press: {held}")
            if seen["turn_rad"] < MIN_TURN_RAD:
                problems.append(f"[check] a drag from {name} turned the view {seen['turn_rad']} rad")
            # A crouch the drag started: put the body back on its feet.
            if name == "crouch" and state(page).get("crouching"):
                tap(client, (circle["x"], circle["y"]))
        # The wheel is gone from the glass (#1286): the bots' order is a tag on the HUD.
        if "bot_wheel" in found:
            problems.append("[check] the touch layer still has a bot_wheel button")

        # Screenshots with a thumb on Reload, then still on it while it turns the view.
        reload_ = found["reload"]
        touch(client, "touchStart", [(1, reload_["x"], reload_["y"])])
        time.sleep(HOLD_S)
        page.screenshot(path=str(out / f"{tag}_2_thumb_on_reload.png"))
        for step in range(1, STEPS + 1):
            touch(client, "touchMove", [(1, reload_["x"] - 4.0 * step, reload_["y"] - 2.0 * step)])
            time.sleep(STEP_PERIOD_S)
        page.screenshot(path=str(out / f"{tag}_3_thumb_on_reload_turning.png"))
        touch(client, "touchEnd", [])
        time.sleep(0.4)

        # A look that begins beside Reload, outside its hit area, across it: presses nothing, turns the view.
        away = (reload_["x"] - fire["x"], reload_["y"] - fire["y"])
        norm = math.hypot(*away)
        away = (away[0] / norm, away[1] / norm)
        start = (
            reload_["x"] + away[0] * (reload_["hit"] + BESIDE_PX),
            reload_["y"] + away[1] * (reload_["hit"] + BESIDE_PX),
        )
        held = []
        seen = drag_from(page, client, start, (-away[0] * 2.2 * reload_["hit"], -away[1] * 2.2 * reload_["hit"]), held)
        result["look_across_reload"] = seen
        if seen["held_at_press"] or any(held):
            problems.append(f"[check] a look beside Reload pressed {seen['held_at_press']!r} {held}")
        if seen["turn_rad"] < MIN_TURN_RAD:
            problems.append(f"[check] a look beside Reload turned the view only {seen['turn_rad']} rad")

        # Crouch is a toggle: a tap crouches and stays, a second tap stands, Jump from a crouch stands.
        crouch = (found["crouch"]["x"], found["crouch"]["y"])
        jump = (found["jump"]["x"], found["jump"]["y"])
        tap(client, crouch)
        crouched = bool(state(page).get("crouching"))
        page.screenshot(path=str(out / f"{tag}_4_crouch_toggled_on.png"))
        tap(client, crouch)
        stood = not state(page).get("crouching")
        tap(client, crouch)
        crouched_again = bool(state(page).get("crouching"))
        tap(client, jump)
        page.wait_for_timeout(600)
        stood_for_jump = not state(page).get("crouching")
        result["crouch"] = {
            "tap_crouches": crouched,
            "second_tap_stands": stood,
            "crouched_again": crouched_again,
            "jump_stands": stood_for_jump,
        }
        for key, ok in result["crouch"].items():
            if not ok:
                problems.append(f"[check] crouch: {key} did not hold")
        browser.close()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--before", action="store_true", help="the build before the rework: screenshots only")
    parser.add_argument("--page", default="844x390", help="the page in CSS px, 844x390 or 667x375")
    args = parser.parse_args()
    width, _, height = args.page.partition("x")
    page_size = {"width": int(width), "height": int(height)}
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    try:
        result = run(url, args.out, page_size, args.page, args.before)
    finally:
        if server:
            server.shutdown()
    (args.out / f"result_{args.page}.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    for line in result["problems"]:
        print("FAILED:", line)
    return 1 if result["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
