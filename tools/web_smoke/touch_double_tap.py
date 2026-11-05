"""The double tap that changes shoulder, with real touches in a phone-sized browser (#1288).

Opens the exported game (`?touch=1&probe`) in Chrome with mobile emulation (a page of 844 x 390 or 667 x 375 CSS px at a
pixel ratio of 2, real touch events through the DevTools protocol, real time between them), starts a solo night and
reads the probe's `shoulder_side` (+1 or -1), `yaw`, `touch_held` and `touch_slop` (the finger's slop in canvas units):

- two quick taps on free ground change shoulder; a swap is undone by a second double tap;
- one tap, two taps 450 ms apart, two long touches (300 ms) and two taps that each slid 16 CSS px do not;
- two taps that each shook 6 CSS px (inside the slop) do;
- a look that begins right after a tap turns the view as a plain look does, and changes nothing;
- a fast flick turns the view by what it made and never counts as a tap;
- two taps on the stick's side, on Reload, on Fire, on a weapon's place of the HUD, or on the pause menu do not;
- a finger on the stick (walking) or on Fire (held) does not stop a second finger's double tap, and is not disturbed;
- a second finger's look drag, with a finger already on the stick, turns the view whole.

It keeps screenshots of each shoulder and of the first-run hints, and prints the numbers. `--left` is the left-handed
layout (the stick on the right, free ground on the left).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_double_tap.py build/web out \\
        [--page 844|667] [--left]

Exits 1 on any check that fails. Run it under `gds quiet`.
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
TAP_S = 0.07
GAP_S = 0.12
SETTLE_S = 0.6
STEP_PERIOD_S = 0.03
RADIANS_PER_HEIGHT = 1.6
# A look drag of this many CSS px turns the view this much at a gain of 1 (`TouchLook`): the canvas is 1080 units for
# the page's height, whatever the page.
LOOK_PX = 100.0
LOOK_STEPS = 12
FLICK_PX = 200.0
FLICK_STEPS = 4
# A turn within these shares of the design's is "whole": the smoothing and the flick gain are inside them.
TURN_LOW = 0.8
TURN_HIGH = 1.7


def spots(state: dict, key: str, size: dict) -> dict[str, tuple[float, float]]:
    """The probe's `name:x,y,...` lists as CSS px centres."""
    found = {}
    for entry in str(state.get(key, "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y = (float(n) for n in numbers.split(",")[:2])
            found[name] = (x * size["width"], y * size["height"])
    return found


class Hands:
    """Fingers on the page: one `touchStart`/`touchMove`/`touchEnd` per event, as a browser would send them."""

    def __init__(self, client, page) -> None:
        self.client = client
        self.page = page
        self.down: dict[int, tuple[float, float]] = {}

    def _send(self, kind: str) -> None:
        points = [(i, x, y) for i, (x, y) in self.down.items()]
        menu.smoke_touch(self.client, kind, points)

    def press(self, finger: int, at: tuple[float, float]) -> None:
        self.down[finger] = at
        self._send("touchStart")

    def move(self, finger: int, at: tuple[float, float]) -> None:
        self.down[finger] = at
        self._send("touchMove")

    def lift(self, finger: int) -> None:
        # touchEnd lists the fingers that STAY down.
        self.down.pop(finger)
        self._send("touchEnd")

    def tap(self, at, held=TAP_S, after=GAP_S, finger=1, slide=0.0) -> None:
        self.press(finger, at)
        if slide:
            self.move(finger, (at[0] + slide, at[1]))
            self.move(finger, at)
        time.sleep(held)
        self.lift(finger)
        time.sleep(after)

    def double_tap(self, at, **kwargs) -> None:
        self.tap(at, **kwargs)
        self.tap(at, **kwargs)

    def drag(self, finger: int, start, delta, steps=LOOK_STEPS, period=STEP_PERIOD_S) -> None:
        self.press(finger, start)
        for step in range(1, steps + 1):
            self.move(finger, (start[0] + delta[0] * step / steps, start[1] + delta[1] * step / steps))
            time.sleep(period)

    def state(self) -> dict:
        self.page.wait_for_timeout(450)  # the probe refreshes the game's numbers every 0.25 s
        return menu.probe(self.page)


def turn(a: float, b: float) -> float:
    return abs(math.remainder(b - a, math.tau))


def seed_settings(page, left: bool) -> None:
    text = f"[controls]\n\nleft_handed={'true' if left else 'false'}\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def run(browser_type, url: str, out: Path, result: dict, size: dict, left: bool, before: bool = False) -> None:
    problems = result["problems"]
    browser = browser_type.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport=size, device_scale_factor=RATIO, has_touch=True, is_mobile=True)
    page = context.new_page()
    page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
    page.add_init_script("Element.prototype.requestPointerLock = function () {};")
    target = f"{url}?touch=1&probe=flash"
    page.goto(target, wait_until="commit")
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    if left:
        seed_settings(page, left)
        page.goto(target, wait_until="commit")
        menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
        page.wait_for_timeout(3000)
    smoke.start_solo(page)
    menu.wait_for(
        page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
    )
    page.wait_for_timeout(2500)
    client = context.new_cdp_session(page)
    hands = Hands(client, page)
    state = menu.wait_for(page, "the touch layer", lambda s: bool(s.get("touch_hits")), 30)
    hits = spots(state, "touch_hits", size)
    zones = spots(state, "touch_zones", size)
    result["page_css_px"] = size
    result["left_handed"] = left
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    result["touch_slop_units"] = state.get("touch_slop")
    result["buttons"] = sorted(hits)
    if before:
        # The build before the change: the screenshots, and what two taps on free ground do there (nothing).
        free = (size["width"] * (0.38 if left else 0.62), size["height"] * 0.30)
        page.screenshot(path=out / "before_1_night.png")
        side = float(menu.probe(page).get("shoulder_side", 0.0))
        Hands(client, page).double_tap(free)
        page.wait_for_timeout(900)
        result["side_before_and_after_two_taps"] = [side, float(menu.probe(page).get("shoulder_side", 0.0))]
        browser.close()
        return
    if "swap_shoulder" in hits:
        problems.append("[check] the Side button is still on the glass")
    # Free ground: the look area, away from every button and card the finger could hit, a third down from the top.
    free = (size["width"] * (0.38 if left else 0.62), size["height"] * 0.30)
    stick_side = (size["width"] * (0.86 if left else 0.14), size["height"] * 0.66)
    result["free_ground"] = free
    result["stick_side"] = stick_side

    # The first-run hints: the move and look hints, then (after a look) the shoulder hint.
    page.screenshot(path=out / "1_first_run.png")
    hands.drag(1, free, (-30.0 if left else 30.0, 0.0), steps=6)
    hands.lift(1)
    page.wait_for_timeout(900)
    page.screenshot(path=out / "2_shoulder_hint.png")
    page.wait_for_timeout(500)

    def side() -> float:
        return float(hands.state().get("shoulder_side", 0.0))

    start_side = side()
    result["start_side"] = start_side
    result["steps"] = {}

    def expect(name: str, flips: int, act) -> dict:
        before = hands.state()
        act()
        time.sleep(SETTLE_S)
        after = hands.state()
        flipped = (float(after.get("shoulder_side", 0.0)) != float(before.get("shoulder_side", 0.0))) and 1 or 0
        record = {
            "side_before": before.get("shoulder_side"),
            "side_after": after.get("shoulder_side"),
            "turn_rad": round(turn(before["yaw"], after["yaw"]), 3),
            "held": str(after.get("touch_held", "")),
        }
        result["steps"][name] = record
        if flipped != flips:
            problems.append(f"[check] {name}: expected {'a swap' if flips else 'no swap'}, {record}")
        # Time for the camera's glide and the press's release before the next gesture.
        time.sleep(0.4)
        return record

    # The gesture.
    page.screenshot(path=out / "3_shoulder_a.png")
    expect("double tap swaps", 1, lambda: hands.double_tap(free))
    page.wait_for_timeout(700)
    page.screenshot(path=out / "4_shoulder_b.png")
    expect("a second double tap swaps back", 1, lambda: hands.double_tap(free))
    expect("one tap does nothing", 0, lambda: hands.tap(free))
    time.sleep(0.5)
    expect("two taps 450 ms apart do nothing", 0, lambda: (hands.tap(free, after=0.45), hands.tap(free)))
    time.sleep(0.5)
    expect("two long touches (300 ms) do nothing", 0, lambda: hands.double_tap(free, held=0.3))
    expect("two taps that slid 16 CSS px do nothing", 0, lambda: hands.double_tap(free, slide=16.0))
    expect("two taps that shook 6 CSS px are still taps", 1, lambda: hands.double_tap(free, slide=6.0))
    expect("three taps are one pair and a first", 1, lambda: (hands.double_tap(free), hands.tap(free)))
    time.sleep(0.5)

    # The look.
    design = RADIANS_PER_HEIGHT * LOOK_PX / size["height"]
    flick_design = RADIANS_PER_HEIGHT * FLICK_PX / size["height"]
    way = -1.0 if left else 1.0
    plain = expect("a plain look drag", 0, lambda: (hands.drag(1, free, (way * LOOK_PX, 0.0)), hands.lift(1)))
    after_tap = expect(
        "a look right after a tap",
        0,
        lambda: (hands.tap(free, after=0.05), hands.drag(1, free, (way * LOOK_PX, 0.0)), hands.lift(1)),
    )
    flick = expect(
        "a fast flick",
        0,
        lambda: (hands.drag(1, free, (way * FLICK_PX, 0.0), steps=FLICK_STEPS, period=0.012), hands.lift(1)),
    )
    time.sleep(0.5)
    result["look_design_rad"] = round(design, 3)
    result["flick_design_rad"] = round(flick_design, 3)
    for name, record, wanted in (
        ("plain", plain, design),
        ("after a tap", after_tap, design),
        ("flick", flick, flick_design),
    ):
        if not TURN_LOW * wanted <= record["turn_rad"] <= TURN_HIGH * wanted:
            problems.append(f"[check] a look drag {name} turned {record['turn_rad']} rad, the design says {wanted:.3f}")
    if plain["turn_rad"] and abs(after_tap["turn_rad"] / plain["turn_rad"] - 1.0) > 0.25:
        problems.append(f"[check] a look after a tap turned {after_tap['turn_rad']}, a plain one {plain['turn_rad']}")
    expect("a tap right after a flick is a first tap", 0, lambda: (hands.tap(free), time.sleep(0.5)))

    # What never counts.
    expect("two taps on the stick's side", 0, lambda: hands.double_tap(stick_side))
    for button in ("reload", "fire"):
        if button in hits:
            expect(f"two taps on {button}", 0, lambda b=button: hands.double_tap(hits[b]))
    expect(
        "a free tap between two taps on Reload",
        0,
        lambda: (hands.tap(free), hands.tap(hits["reload"]), hands.tap(free)),
    )
    time.sleep(0.5)
    if zones:
        place = next(iter(zones.values()))
        expect("two taps on a weapon's place of the HUD", 0, lambda: hands.double_tap(place))

    # Other fingers down.
    def walking_then_tapping() -> None:
        hands.press(2, stick_side)
        for step in range(1, 5):
            hands.move(2, (stick_side[0], stick_side[1] - 8.0 * step))
            time.sleep(0.03)
        hands.double_tap(free, finger=1)

    expect("a double tap while the other thumb walks", 1, walking_then_tapping)
    hands.lift(2)
    time.sleep(0.5)

    def holding_fire_then_tapping() -> None:
        hands.press(2, hits["fire"])
        time.sleep(0.2)
        record = hands.state().get("touch_held", "")
        result["held_with_a_finger_on_fire"] = str(record)
        hands.double_tap(free, finger=1)

    record = expect("a double tap while a finger holds Fire", 1, holding_fire_then_tapping)
    if "fire" not in record["held"]:
        problems.append(f"[check] Fire was not held through the double tap: {record['held']!r}")
    hands.lift(2)
    time.sleep(0.5)

    def walking_then_looking() -> None:
        hands.press(2, stick_side)
        hands.move(2, (stick_side[0], stick_side[1] - 20.0))
        hands.drag(1, free, (way * LOOK_PX, 0.0))
        hands.lift(1)

    walk_look = expect("a look with a finger already on the stick", 0, walking_then_looking)
    hands.lift(2)
    if not TURN_LOW * design <= walk_look["turn_rad"] <= TURN_HIGH * design:
        problems.append(f"[check] a look with the stick held turned {walk_look['turn_rad']}, design {design:.3f}")

    # The pause menu: the layer is down, two taps on the card change nothing.
    pause = hits["pause"]
    menu.tap(client, pause)
    opened = menu.wait_for(page, "the menu", menu.menu_open)
    before_pause = float(opened.get("shoulder_side", 0.0))
    page.wait_for_timeout(500)
    centre = (size["width"] * 0.5, size["height"] * 0.5)
    hands.double_tap(centre)
    page.wait_for_timeout(600)
    page.screenshot(path=out / "5_pause_card.png")
    if float(menu.probe(page).get("shoulder_side", 0.0)) != before_pause:
        problems.append("[check] two taps on the pause menu changed shoulder")

    # The Touch tab says it too.
    menu.tap(client, menu.spot(menu.probe(page), "Settings", size))
    menu.wait_for(page, "the settings in the menu", lambda s: bool(s.get("settings_open")))
    page.wait_for_timeout(900)
    try:
        menu.tap(client, menu.spot(menu.probe(page), "Touch", size))
        page.wait_for_timeout(900)
        page.screenshot(path=out / "6_touch_tab.png")
    except RuntimeError as error:
        problems.append(f"[check] no Touch tab button to tap: {error}")
    menu.tap(client, menu.spot(menu.probe(page), "Back", size))
    menu.tap(client, menu.spot(menu.probe(page), "Resume", size))
    menu.wait_for(page, "the night running again", lambda s: bool(s.get("running")))
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="844", help="the phone's page, 844 x 390 or 667 x 375")
    parser.add_argument("--left", action="store_true", help="the left-handed layout")
    parser.add_argument("--before", action="store_true", help="the build before the change: screenshots only")
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
            run(p.chromium, url, args.out, result, PAGES[args.page], args.left, args.before)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\ndouble tap check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\ndouble tap check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
