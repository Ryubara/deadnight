"""The HUD's weapons and grenades as the phone's weapon controls, with real touches in a phone-sized browser (#1280).

Opens the exported game (`?touch=1&probe=flash`) in Chrome with mobile emulation (a page of 844 x 390 or 667 x 375 CSS
px at a pixel ratio of 2, real touch events through the DevTools protocol), starts a solo night and reads the probe's
`touch_zones` (the HUD's weapon places, as fractions of the window):

- every place is at least 44 CSS px wide and high, on the side of the screen the hand asks for (`--left`), and clear of
  every button's hit area (`touch_hits`); there is no Swap and no Grenade button;
- a finger that lands on a weapon's place takes that weapon (the pistol and the crowbar, the crowbar given through the
  flash probe), and one that drags off it turns nothing: the view does not move and no other button is held;
- a finger on the grenades' place holds the throw (the server says the pin is out), turns the view while it drags, and
  the lift throws it (the count drops and the cook ends).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_weapon_places.py build/web build/places \\
        [--page 844|667] [--left] [--ui 0.8|1.0|1.25]

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails. Run it under `gds quiet`.
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
TAP_CSS_PX = 44.0
# A place's size is rounded up to whole units, a CSS px is a third of one: this much under is rounding.
SLACK_CSS_PX = 0.5
DRAG_PX = 120.0
STEPS = 12
STEP_PERIOD_S = 0.03
HOLD_S = 1.0
MIN_TURN_RAD = 0.1
MAX_STILL_RAD = 0.01
REACT_S = 8.0
ROUND_TIMEOUT_S = 120.0
SLOTS = ("weapon_slot_1", "weapon_slot_2", "weapon_slot_3")


def zones(state: dict, page: dict) -> dict[str, dict]:
    """Each weapon place as {x, y, w, h} in CSS px (the centre and the size)."""
    found = {}
    for entry in str(state.get("touch_zones", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, w, h = (float(n) for n in numbers.split(","))
            found[name] = {
                "x": x * page["width"],
                "y": y * page["height"],
                "w": w * page["width"],
                "h": h * page["height"],
            }
    return found


def hit_areas(state: dict, page: dict) -> dict[str, tuple[float, float, float]]:
    """Each button's hit area as (x, y, radius) in CSS px, from the probe's `touch_hits`."""
    found = {}
    for entry in str(state.get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, hit, _was = (float(n) for n in numbers.split(","))
            found[name] = (x * page["width"], y * page["height"], hit * page["height"])
    return found


def gap_to(zone: dict, hit: tuple[float, float, float]) -> float:
    """How far the circle (x, y, radius) is from the place's box, CSS px (negative when they overlap)."""
    cx = min(max(hit[0], zone["x"] - zone["w"] / 2), zone["x"] + zone["w"] / 2)
    cy = min(max(hit[1], zone["y"] - zone["h"] / 2), zone["y"] + zone["h"] / 2)
    return math.hypot(hit[0] - cx, hit[1] - cy) - hit[2]


def yaw(page) -> float:
    page.wait_for_timeout(400)  # the probe refreshes the game's numbers every 0.25 s
    return float(menu.probe(page).get("yaw", 0.0))


def turned(a: float, b: float) -> float:
    return abs(math.remainder(b - a, math.tau))


def finger(client, kind: str, point: tuple[float, float] | None) -> None:
    menu.smoke_touch(client, kind, [(1, *point)] if point else [])


def drag(client, start: tuple[float, float], delta: tuple[float, float]) -> tuple[float, float]:
    end = (start[0] + delta[0], start[1] + delta[1])
    for step in range(1, STEPS + 1):
        finger(client, "touchMove", (start[0] + delta[0] * step / STEPS, start[1] + delta[1] * step / STEPS))
        time.sleep(STEP_PERIOD_S)
    return end


def seed_settings(page, ui_size: float, left: bool) -> None:
    """The saved settings the next load reads: what the Settings screen writes for the interface size and the hand."""
    text = f"[accessibility]\n\nui_scale={ui_size}\n\n[controls]\n\nleft_handed={'true' if left else 'false'}\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def run(browser_type, url: str, out: Path, result: dict, size: dict, left: bool, ui_size: float) -> None:
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
    seed_settings(page, ui_size, left)
    page.goto(target, wait_until="commit")
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    smoke.start_solo(page)
    menu.wait_for(
        page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
    )
    page.wait_for_timeout(2500)
    client = context.new_cdp_session(page)
    state = menu.wait_for(page, "the weapon places", lambda s: bool(s.get("touch_zones")), REACT_S)
    result["page_css_px"] = size
    result["interface_size"] = ui_size
    result["left_handed"] = left
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    found = zones(state, size)
    result["places_css_px"] = {k: [round(v["w"], 1), round(v["h"], 1)] for k, v in found.items()}
    page.screenshot(path=out / "1_places.png")

    # The layout: no Swap or Grenade button, the places at a fingertip's size, on the right side, clear of the buttons.
    hits = hit_areas(state, size)
    for gone in ("swap_weapon", "throw_grenade"):
        if gone in hits:
            problems.append(f"[check] the touch layer still has a {gone} button")
    for name in ("weapon_slot_1", "weapon_slot_2", "throw_grenade"):
        if name not in found:
            problems.append(f"[check] no {name} place (has {sorted(found)})")
    for name, zone in found.items():
        if min(zone["w"], zone["h"]) < TAP_CSS_PX - SLACK_CSS_PX:
            problems.append(f"[check] the {name} place is {zone['w']:.1f} x {zone['h']:.1f} CSS px, under {TAP_CSS_PX}")
        on_left_half = zone["x"] < size["width"] / 2
        if on_left_half == left:
            problems.append(f"[check] the {name} place is on the wrong side for left_handed={left}")
        for button, hit in hits.items():
            if gap_to(zone, hit) <= 0:
                problems.append(f"[check] the {name} place is under the {button} button's hit area")
        if not (0 <= zone["x"] - zone["w"] / 2 and zone["x"] + zone["w"] / 2 <= size["width"]):
            problems.append(f"[check] the {name} place leaves the page sideways")
        if not (0 <= zone["y"] - zone["h"] / 2 and zone["y"] + zone["h"] / 2 <= size["height"]):
            problems.append(f"[check] the {name} place leaves the page vertically")

    # Two weapons: the crowbar is given and put in hand, so slot 1 is the pistol and slot 2 the crowbar.
    page.evaluate("() => { window.deadnight.flashGive = 'crowbar'; }")
    state = menu.wait_for(page, "the crowbar in hand", lambda s: s.get("weapon") == "crowbar", REACT_S)
    slots = str(state.get("weapon_slots", "")).split(",")
    result["slots"] = slots
    if len(slots) < 2:
        problems.append(f"[check] two weapons are carried, the strip has {slots}")
        browser.close()
        return
    page.wait_for_timeout(600)
    found = zones(menu.probe(page), size)
    page.screenshot(path=out / "2_two_weapons.png")
    yaw_before = yaw(page)
    result["taps"] = {}
    for index, name in ((0, "weapon_slot_1"), (1, "weapon_slot_2"), (0, "weapon_slot_1")):
        zone = found[name]
        at = (zone["x"], zone["y"])
        finger(client, "touchStart", at)
        held = ""
        end = time.monotonic() + 1.0
        while time.monotonic() < end and held != name:
            held = str(menu.probe(page).get("touch_held", ""))
            page.wait_for_timeout(60)
        finger(client, "touchEnd", None)
        state = menu.wait_for(page, f"{slots[index]} in hand", lambda s, w=slots[index]: s.get("weapon") == w, REACT_S)
        result["taps"][name] = {"held": held, "weapon": state.get("weapon"), "lit_slot": state.get("weapon_slot_held")}
        if held != name:
            problems.append(f"[check] a finger on {name} held {held!r}")
        if state.get("weapon_slot_held") != index + 1:
            problems.append(f"[check] after a tap on {name} the lit slot is {state.get('weapon_slot_held')}")
        page.screenshot(path=out / f"3_tapped_{name}_{slots[index]}.png")
        page.wait_for_timeout(300)

    # A finger that starts on a weapon and drags off it only picks it: the view does not move, nothing else is held.
    zone = found["weapon_slot_2"]
    at = (zone["x"], zone["y"])
    finger(client, "touchStart", at)
    page.wait_for_timeout(300)
    end = drag(client, at, (DRAG_PX, -DRAG_PX / 3))
    page.wait_for_timeout(500)
    held = str(menu.probe(page).get("touch_held", ""))
    still = turned(yaw_before, yaw(page))
    finger(client, "touchEnd", None)
    page.wait_for_timeout(500)
    result["drag_from_weapon"] = {"held": held, "turn_rad": round(still, 4), "ended_at": [round(end[0]), round(end[1])]}
    if held != "weapon_slot_2":
        problems.append(f"[check] a finger dragging from a weapon held {held!r}, not only its slot")
    if still > MAX_STILL_RAD:
        problems.append(f"[check] a finger dragging from a weapon turned the view {still:.3f} rad")

    # The grenades: press and hold cooks (the pin is out), the finger turns the view meanwhile, the lift throws. The
    # rules refuse a grenade until the first round is on.
    state = menu.wait_for(page, "the first round", lambda s: int(s.get("round", 0)) >= 1, ROUND_TIMEOUT_S)
    count_before = int(state.get("grenade_count", 0))
    zone = zones(state, size)["throw_grenade"]
    at = (zone["x"], zone["y"])
    yaw_before = yaw(page)
    finger(client, "touchStart", at)
    time.sleep(HOLD_S)
    state = menu.probe(page)
    cooking = bool(state.get("grenade_cooking"))
    held = str(state.get("touch_held", ""))
    page.screenshot(path=out / "4_grenade_held.png")
    end = drag(client, at, (-DRAG_PX if left else DRAG_PX, 0.0))
    page.wait_for_timeout(600)
    still_cooking = bool(menu.probe(page).get("grenade_cooking"))
    dragged = turned(yaw_before, yaw(page))
    page.screenshot(path=out / "5_grenade_dragged_still_held.png")
    finger(client, "touchEnd", None)
    thrown = menu.wait_for(page, "the grenade thrown", lambda s: not s.get("grenade_cooking"), REACT_S)
    page.wait_for_timeout(600)
    page.screenshot(path=out / "6_grenade_thrown.png")
    result["grenade"] = {
        "count_before": count_before,
        "count_after": int(thrown.get("grenade_count", 0)),
        "cooking_while_held": cooking,
        "held": held,
        "cooking_after_drag": still_cooking,
        "drag_turn_rad": round(dragged, 4),
    }
    if not cooking or held != "throw_grenade":
        problems.append(f"[check] a finger on the grenades did not cook (cooking={cooking}, held={held!r})")
    if not still_cooking:
        problems.append("[check] the grenade left the hand while the finger was still down")
    if dragged < MIN_TURN_RAD:
        problems.append(f"[check] a drag from the grenades turned the view only {dragged:.3f} rad")
    if int(thrown.get("grenade_count", 0)) >= count_before:
        problems.append(f"[check] the lift did not throw: grenades {count_before} then {thrown.get('grenade_count')}")
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="844", help="the phone's page, 844 x 390 or 667 x 375")
    parser.add_argument("--left", action="store_true", help="the left-handed layout")
    parser.add_argument("--ui", type=float, default=1.0, help="the interface size (0.8, 1.0 or 1.25)")
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
            run(p.chromium, url, args.out, result, PAGES[args.page], args.left, args.ui)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nweapon places check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nweapon places check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
