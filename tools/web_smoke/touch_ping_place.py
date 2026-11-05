"""Ping under Pause, a thumb apart, with real touches in a phone-sized browser (issue #1289).

Opens the exported game (`?touch=1&probe`) in Chrome with mobile emulation (a page of 844 x 390 or 667 x 375 CSS px at a
pixel ratio of 2, real touch events through the DevTools protocol), starts a solo night with the interface size and hand
the options ask for, and reads the probe's `touch_hits` (every button's centre and hit area, as fractions of the page):

- Ping is straight under Pause, at least 54 CSS px (9 mm at 6 CSS px a millimetre) from its centre, with 12 CSS px (2 mm)
  of air between the rims of the two drawn buttons and none of the two hit areas touching;
- Pause is the only other control on the top edge;
- a finger walked down the line from Pause to Ping and past it, every `STEP_CSS_PX`, holds Ping while it is inside Ping's
  hit area and nothing in the gap (`touch_held`), and never Pause or the night's pause: nothing near one presses the other;
- a finger on Pause's edge that faces Ping pauses the night, and nothing else was held.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_ping_place.py build/web build/ping \\
        [--page 844|667] [--left] [--ui 0.8|1.0|1.25] [--shots-only]

Screenshots and `result.json` go to the second argument. `--shots-only` takes the screenshots and reads no layout (a
build from before the change). Exits 1 on any check that fails. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import ingame_menu as menu
import night_taps
import smoke

PAGES = {"844": {"width": 844, "height": 390}, "667": {"width": 667, "height": 375}}
RATIO = 2
CSS_PX_PER_MM = 6.0
LEAST_CENTRES_CSS = 9.0 * CSS_PX_PER_MM
LEAST_AIR_CSS = 2.0 * CSS_PX_PER_MM
STEP_CSS_PX = 4.0
HOLD_S = 0.35
# What the probe's rounding and the engine's whole units leave in a measurement, CSS px.
SLACK_CSS_PX = 0.6
# How far inside a hit area's edge a finger lands, CSS px.
INSIDE_CSS_PX = 2.0


def circles(state: dict, page: dict) -> dict[str, dict]:
    """Each button as {x, y, hit} in CSS px (the probe's fractions of the page; a radius is a share of the height)."""
    found = {}
    for entry in str(state.get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, hit, _was = (float(n) for n in numbers.split(","))
            found[name] = {"x": x * page["width"], "y": y * page["height"], "hit": hit * page["height"]}
    return found


def seed_settings(page, ui_size: float, left: bool) -> None:
    """The saved settings the next load reads: what the Settings screen writes for the interface size and the hand."""
    text = f"[accessibility]\n\nui_scale={ui_size}\n\n[controls]\n\nleft_handed={'true' if left else 'false'}\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def finger(client, kind: str, point: tuple[float, float] | None) -> None:
    menu.smoke_touch(client, kind, [(1, *point)] if point else [])


def held_at(page, client, point: tuple[float, float]) -> tuple[str, bool]:
    """A finger down at `point` for a moment: what the layer holds, and whether the night is paused. Then lifted."""
    finger(client, "touchStart", point)
    time.sleep(HOLD_S)
    state = menu.probe(page)
    seen = (str(state.get("touch_held", "")), bool(state.get("paused")))
    finger(client, "touchEnd", None)
    time.sleep(0.15)
    return seen


def run(
    browser_type, url: str, out: Path, result: dict, size: dict, left: bool, ui_size: float, shots_only: bool
) -> None:
    problems = result["problems"]
    browser = browser_type.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport=size, device_scale_factor=RATIO, has_touch=True, is_mobile=True)
    page = context.new_page()
    page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
    page.add_init_script("Element.prototype.requestPointerLock = function () {};")
    target = f"{url}?touch=1&probe"
    page.goto(target, wait_until="commit")
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    seed_settings(page, ui_size, left)
    page.goto(target, wait_until="commit")
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    smoke.start_solo(page)
    menu.wait_for(
        page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
    )
    page.wait_for_timeout(3500)
    client = context.new_cdp_session(page)
    result["page_css_px"] = size
    result["interface_size"] = ui_size
    result["left_handed"] = left
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    page.screenshot(path=out / "1_fingers_lifted.png")
    if shots_only:
        browser.close()
        return
    state = menu.wait_for(page, "the touch layer", lambda s: bool(s.get("touch_hits")), 30.0)
    found = circles(state, size)
    pause, ping = found["pause"], found["ping"]

    # The layout, in CSS px as the probe reports it.
    drop = ping["y"] - pause["y"]
    centres = math.hypot(ping["x"] - pause["x"], drop)
    result["pause"] = {k: round(v, 1) for k, v in pause.items()}
    result["ping"] = {k: round(v, 1) for k, v in ping.items()}
    result["centres_css_px"] = round(centres, 1)
    result["hit_gap_css_px"] = round(centres - pause["hit"] - ping["hit"], 1)
    if abs(ping["x"] - pause["x"]) > SLACK_CSS_PX or drop <= 0:
        problems.append(f"[check] Ping is not straight under Pause: {ping['x'] - pause['x']:.1f}, {drop:.1f} CSS px")
    if centres < LEAST_CENTRES_CSS - SLACK_CSS_PX:
        problems.append(f"[check] Ping is {centres:.1f} CSS px from Pause's centre, under {LEAST_CENTRES_CSS}")
    if result["hit_gap_css_px"] <= 0:
        problems.append(f"[check] the hit areas of Pause and Ping meet ({result['hit_gap_css_px']} CSS px apart)")
    top_edge = [
        name for name, circle in found.items() if abs(circle["y"] - pause["y"]) < pause["hit"] and name != "pause"
    ]
    result["on_the_top_edge_besides_pause"] = top_edge
    if top_edge:
        problems.append(f"[check] {top_edge} stand on the top edge with Pause")

    # A finger walked from above Pause's facing edge's far side down past Ping: Ping inside its hit area, nothing else.
    walk: list[dict] = []
    start = ping["y"] + ping["hit"] + 6.0
    stop = pause["y"] + pause["hit"] + 1.0  # the last step stays outside Pause's hit area
    y = start
    while y >= stop:
        held, paused = held_at(page, client, (ping["x"], y))
        inside = abs(y - ping["y"]) <= ping["hit"] - 0.5
        outside = abs(y - ping["y"]) > ping["hit"] + 0.5
        walk.append({"y": round(y, 1), "held": held, "paused": paused})
        if paused or "pause" in held:
            problems.append(f"[check] a finger at y={y:.1f} (outside Pause's hit area) paused the night: {held!r}")
        if inside and held != "ping":
            problems.append(f"[check] a finger at y={y:.1f} inside Ping's hit area held {held!r}, not 'ping'")
        if outside and held:
            problems.append(f"[check] a finger at y={y:.1f} in the gap held {held!r}")
        y -= STEP_CSS_PX
    result["walk"] = walk
    page.screenshot(path=out / "2_after_the_walk.png")

    # A thumb held on Ping, for the capture; then Pause's facing edge pauses and nothing else is held.
    finger(client, "touchStart", (ping["x"], ping["y"]))
    time.sleep(HOLD_S + 0.2)
    page.screenshot(path=out / "3_thumb_on_ping.png")
    held_on_ping = str(menu.probe(page).get("touch_held", ""))
    finger(client, "touchEnd", None)
    time.sleep(0.3)
    result["held_on_ping"] = held_on_ping
    if held_on_ping != "ping":
        problems.append(f"[check] a finger on Ping's centre held {held_on_ping!r}")
    edge = (pause["x"], pause["y"] + pause["hit"] - INSIDE_CSS_PX)
    held, paused = held_at(page, client, edge)
    result["pause_edge"] = {"held": held, "paused": paused}
    page.screenshot(path=out / "4_pause_pressed.png")
    if "pause" not in held and not paused:
        problems.append(f"[check] a finger on Pause's facing edge neither held pause nor paused ({held!r})")
    if "ping" in held:
        problems.append(f"[check] a finger on Pause's facing edge also held ping ({held!r})")
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="844", help="the phone's page, 844 x 390 or 667 x 375")
    parser.add_argument("--left", action="store_true", help="the left-handed layout")
    parser.add_argument("--ui", type=float, default=1.0, help="the interface size (0.8, 1.0 or 1.25)")
    parser.add_argument("--shots-only", action="store_true", help="screenshots only (a build before the change)")
    args = parser.parse_args()
    quiet = os.environ.get("GDS_QUIET") == "1" or os.environ.get("GDS_ALLOW_POINTER_LOCK") == "1"
    if sys.platform == "win32" and not quiet:
        print("refusing to run outside `gds quiet` (it takes pointer lock)", file=sys.stderr)
        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    result: dict = {"problems": []}
    with sync_playwright() as p:
        try:
            run(p.chromium, url, args.out, result, PAGES[args.page], args.left, args.ui, args.shots_only)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nping place check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nping place check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
