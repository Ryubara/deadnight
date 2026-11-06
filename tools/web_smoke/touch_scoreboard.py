"""A finger held on the players' column shows the scoreboard, with real touches in a phone-sized browser (#1287).

Opens the exported game (`?touch=1&probe=flash`) in Chrome with mobile emulation (a page of 844 x 390 or 667 x 375 CSS
px at a pixel ratio of 2, real touch events through the DevTools protocol), starts a solo night (with `--bots` bots
beside the player, as many as the Play screen offers) and reads the probe's `touch_zones`, `touch_buttons`,
`scoreboard` and `touch_held`:

- there is no Scoreboard circle, and the column is a place of the HUD's touch zones, at least 44 CSS px wide and
  high, on the side of the screen the hand asks for (`--left`), clear of every button;
- a finger held on it holds `scoreboard` and the ticket is up, inside the page and under no drawn button, the weapon
  places or the column; a finger that drags off it while held turns nothing and walks nowhere (the view and the body
  stay still), and lifting hides the ticket;
- a finger on a weapon's place beside the column still takes its own tap, and the ticket stays down.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_scoreboard.py build/web build/board \\
        [--page 844|667] [--left] [--ui 0.8|1.0|1.25] [--bots 0..7] [--label after]

Screenshots (`<label>-<step>.png`) and `<label>-result.json` go to the second argument. Exits 1 on any check that
fails. Run it under `gds quiet`.
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
REACT_S = 8.0
# The body may be pushed a little by a night's own business; a stick would take it metres in a second.
MAX_WALK_M = 0.6
MAX_STILL_RAD = 0.01
# How long the frames after a touch are given to draw before a screenshot is read.
SETTLE_S = 0.6


def parse(state: dict, key: str) -> dict[str, tuple[float, ...]]:
    """`name:a,b,c...` entries of the probe as numbers; the first two are fractions of the width and the height."""
    found = {}
    for entry in str(state.get(key, "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            found[name] = tuple(float(n) for n in numbers.split(","))
    return found


def zones(state: dict, page: dict) -> dict[str, dict]:
    """Each place of the HUD as {x, y, w, h} in CSS px (the centre and the size)."""
    return {
        name: {
            "x": v[0] * page["width"],
            "y": v[1] * page["height"],
            "w": v[2] * page["width"],
            "h": v[3] * page["height"],
        }
        for name, v in parse(state, "touch_zones").items()
    }


def buttons(state: dict, page: dict) -> dict[str, tuple[float, float, float]]:
    """Each drawn button as (x, y, radius) in CSS px."""
    return {
        name: (v[0] * page["width"], v[1] * page["height"], v[2] * page["height"])
        for name, v in parse(state, "touch_buttons").items()
    }


def ticket(state: dict, page: dict) -> dict | None:
    """The ticket's box as {left, top, right, bottom} in CSS px, None while it is down."""
    text = str(state.get("scoreboard", ""))
    if not text:
        return None
    x, y, w, h = (float(n) for n in text.split(","))
    return {
        "left": x * page["width"],
        "top": y * page["height"],
        "right": (x + w) * page["width"],
        "bottom": (y + h) * page["height"],
    }


def box_of(zone: dict) -> dict:
    return {
        "left": zone["x"] - zone["w"] / 2,
        "top": zone["y"] - zone["h"] / 2,
        "right": zone["x"] + zone["w"] / 2,
        "bottom": zone["y"] + zone["h"] / 2,
    }


def overlap(a: dict, b: dict) -> bool:
    return a["left"] < b["right"] and b["left"] < a["right"] and a["top"] < b["bottom"] and b["top"] < a["bottom"]


def hidden(state: dict, name: str) -> bool:
    """Whether the button is not drawn now: Interact only with a prompt (the probe's own check skips it
    by name), Strike only with a dead in reach."""
    return name == "interact" or (name == "quick_melee" and not state.get("touch_strike"))


def gap_to(box: dict, button: tuple[float, float, float]) -> float:
    """How far the button's rim is from the box, CSS px (negative when they overlap)."""
    cx = min(max(button[0], box["left"]), box["right"])
    cy = min(max(button[1], box["top"]), box["bottom"])
    return math.hypot(button[0] - cx, button[1] - cy) - button[2]


def finger(client, kind: str, point: tuple[float, float] | None) -> None:
    menu.smoke_touch(client, kind, [(1, *point)] if point else [])


def drag(client, start: tuple[float, float], delta: tuple[float, float]) -> tuple[float, float]:
    end = (start[0] + delta[0], start[1] + delta[1])
    for step in range(1, STEPS + 1):
        finger(client, "touchMove", (start[0] + delta[0] * step / STEPS, start[1] + delta[1] * step / STEPS))
        time.sleep(STEP_PERIOD_S)
    return end


def yaw(page) -> float:
    page.wait_for_timeout(400)  # the probe refreshes the game's numbers every 0.25 s
    return float(menu.probe(page).get("yaw", 0.0))


def turned(a: float, b: float) -> float:
    return abs(math.remainder(b - a, math.tau))


def where(page) -> tuple[float, float]:
    state = menu.probe(page)
    return float(state.get("body_x", 0.0)), float(state.get("body_z", 0.0))


def seed_settings(page, ui_size: float, left: bool) -> None:
    """The saved settings the next load reads: what the Settings screen writes for the interface size and the hand."""
    text = f"[accessibility]\n\nui_scale={ui_size}\n\n[controls]\n\nleft_handed={'true' if left else 'false'}\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def spot(state: dict, name: str, size: dict) -> tuple[float, float]:
    """Where the button or control `name` is on the menu's tab or the Play screen, in CSS px of the window."""
    for entry in str(state.get("spots", "")).split("|"):
        key, _, point = entry.rpartition(":")
        if key == name:
            x, _, y = point.partition(",")
            return float(x) * size["width"], float(y) * size["height"]
    raise RuntimeError(f"no {name!r} on screen (the page has: {state.get('spots')!r})")


def reach(page, client, name: str, size: dict) -> tuple[float, float]:
    """Where `name` is once it is on the page: a control scrolled out of view is swiped into it (a short page's Play
    screen scrolls); the swipe turns round when it took the control farther."""
    way = -1.0
    middle = 0.4 * size["height"]
    at = spot(menu.probe(page), name, size)
    for _ in range(10):
        if 0.12 * size["height"] < at[1] < 0.66 * size["height"] and 0 < at[0] < size["width"]:
            return at
        start = (size["width"] * 0.5, size["height"] * 0.5)
        finger(client, "touchStart", start)
        drag(client, start, (0.0, way * size["height"] * 0.25))
        finger(client, "touchEnd", None)
        page.wait_for_timeout(600)
        now = spot(menu.probe(page), name, size)
        if abs(now[1] - middle) >= abs(at[1] - middle):
            way = -way
        at = now
    raise RuntimeError(f"{name!r} never came on the page (last at {at})")


def keys_used(page) -> bool:
    """Whether the keyboard has the Start button (the bots were set with keys)."""
    return smoke.focused_control(page) == "Start"


def start_with_bots(page, client, size: dict, bots: int, shot: Path) -> None:
    """Solo from the menu, `bots` bots set on the Play screen by taps on the selector's arrow, then Start."""
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(2500)
    menu.tap(client, (size["width"] - 4, size["height"] / 2))  # a first tap wakes the page's audio
    state = menu.wait_for(page, "the menu's taps", lambda s: "Solo" in str(s.get("spots", "")), menu.SCREEN_TIMEOUT_S)
    menu.tap(client, spot(state, "Solo", size))
    state = menu.wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", 60)
    page.wait_for_timeout(1500)
    if bots:
        try:
            for _ in range(bots):
                menu.tap(client, reach(page, client, "bots:end", size))
                page.wait_for_timeout(300)
        except RuntimeError:
            # The Bots row is under the footer of a short page's Play screen and does not scroll into reach: the
            # keyboard sets it, as the Play screen's own tests do. The night's touch layer is the page's own.
            smoke.focus_control(page, "bots", "ArrowUp")
            smoke.step_value(page, "bots", "ArrowRight", bots)
            page.wait_for_timeout(300)
            smoke.focus_control(page, "Start", "ArrowDown")
    state = menu.probe(page)
    page.screenshot(path=shot)
    if bots and not str(state.get("play_rules", "")).endswith(f"|{bots} bots"):
        raise RuntimeError(f"the Play screen shows {state.get('play_rules')!r}, not {bots} bots")
    start = next(k for k in (e.rpartition(":")[0] for e in str(state.get("spots", "")).split("|")) if "tart" in k)
    if bots and keys_used(page):
        smoke.press(page, "Enter")
    else:
        menu.tap(client, spot(state, start, size))


def run(
    browser_type, url: str, out: Path, label: str, result: dict, size: dict, left: bool, ui_size: float, bots: int
) -> None:
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
    client = context.new_cdp_session(page)
    start_with_bots(page, client, size, bots, out / f"{label}-0_play.png")
    menu.wait_for(
        page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
    )
    page.wait_for_timeout(2500)
    state = menu.wait_for(page, "the column's place", lambda s: "scoreboard" in str(s.get("touch_zones", "")), REACT_S)
    result["page_css_px"] = size
    result["interface_size"] = ui_size
    result["left_handed"] = left
    result["bots"] = bots
    result["players"] = state.get("players")
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    found = zones(state, size)
    column = found["scoreboard"]
    result["column_css_px"] = [round(column["w"], 1), round(column["h"], 1)]
    page.screenshot(path=out / f"{label}-1_idle.png")

    # The layout: no Scoreboard circle, the column at a fingertip's size, on its hand's side, clear of the buttons.
    drawn = buttons(state, size)
    if "scoreboard" in drawn:
        problems.append("[check] the touch layer still has a Scoreboard button")
    if any(entry.startswith("scoreboard:") for entry in str(state.get("touch_hits", "")).split("|")):
        problems.append("[check] the touch layer still has a Scoreboard hit area")
    if min(column["w"], column["h"]) < TAP_CSS_PX - SLACK_CSS_PX:
        problems.append(f"[check] the column is {column['w']:.1f} x {column['h']:.1f} CSS px, under {TAP_CSS_PX}")
    if (column["x"] < size["width"] / 2) == left:
        problems.append(f"[check] the column is on the wrong side for left_handed={left}")
    box = box_of(column)
    for name, button in drawn.items():
        if not hidden(state, name) and gap_to(box, button) <= 0:
            problems.append(f"[check] the column is under the {name} button")
    if not (0 <= box["left"] and box["right"] <= size["width"] and 0 <= box["top"] and box["bottom"] <= size["height"]):
        problems.append("[check] the column leaves the page")

    # A finger held on the column: the ticket is up, fits the page, is under no button or place; a drag off the column
    # turns nothing and walks nowhere; the lift takes the ticket down.
    yaw_before = yaw(page)
    body_before = where(page)
    at = (column["x"], column["y"])
    finger(client, "touchStart", at)
    held_state = menu.wait_for(
        page, "the ticket", lambda s: bool(s.get("scoreboard")) and s.get("touch_held") == "scoreboard", REACT_S
    )
    page.wait_for_timeout(int(SETTLE_S * 1000))
    held_state = menu.probe(page)
    page.screenshot(path=out / f"{label}-2_held.png")
    card = ticket(held_state, size)
    result["held"] = {"touch_held": held_state.get("touch_held"), "ticket_css_px": card}
    if card is None:
        problems.append("[check] a finger held on the column did not show the ticket")
    else:
        if not (
            0 <= card["left"]
            and card["right"] <= size["width"]
            and 0 <= card["top"]
            and card["bottom"] <= size["height"]
        ):
            problems.append(f"[check] the ticket leaves the page: {card}")
        for name, button in buttons(held_state, size).items():
            if not hidden(held_state, name) and gap_to(card, button) <= 0:
                problems.append(f"[check] the ticket is under the {name} button")
        for name, zone in zones(held_state, size).items():
            if overlap(card, box_of(zone)):
                problems.append(f"[check] the ticket is over the {name} place")
    end = drag(client, at, (DRAG_PX if not left else -DRAG_PX, -DRAG_PX / 2))
    page.wait_for_timeout(500)
    dragged = menu.probe(page)
    page.screenshot(path=out / f"{label}-3_dragged.png")
    if dragged.get("touch_held") != "scoreboard" or not dragged.get("scoreboard"):
        problems.append(
            f"[check] after a drag off the column the finger holds {dragged.get('touch_held')!r}, "
            f"ticket {'up' if dragged.get('scoreboard') else 'down'}"
        )
    still = turned(yaw_before, yaw(page))
    body_after = where(page)
    walked = math.hypot(body_after[0] - body_before[0], body_after[1] - body_before[1])
    finger(client, "touchEnd", None)
    lifted = menu.wait_for(page, "the ticket gone", lambda s: not s.get("scoreboard"), REACT_S)
    page.wait_for_timeout(int(SETTLE_S * 1000))
    page.screenshot(path=out / f"{label}-4_lifted.png")
    result["drag"] = {
        "ended_at": [round(end[0]), round(end[1])],
        "turn_rad": round(still, 4),
        "walked_m": round(walked, 3),
        "touch_held_after_lift": lifted.get("touch_held"),
    }
    if still > MAX_STILL_RAD:
        problems.append(f"[check] a finger dragging from the column turned the view {still:.3f} rad")
    if walked > MAX_WALK_M:
        problems.append(f"[check] a finger dragging from the column walked the body {walked:.2f} m (the stick started)")
    if lifted.get("touch_held"):
        problems.append(f"[check] a lifted finger still holds {lifted.get('touch_held')!r}")

    # The weapon places beside the column keep their own taps: the strip's press, and no ticket.
    strip = found.get("weapon_slot_1")
    if strip is None:
        problems.append("[check] no weapon_slot_1 place beside the column")
    else:
        finger(client, "touchStart", (strip["x"], strip["y"]))
        tapped = menu.wait_for(page, "the weapon place held", lambda s: s.get("touch_held") == "weapon_slot_1", REACT_S)
        result["strip_tap"] = {"touch_held": tapped.get("touch_held"), "ticket_up": bool(tapped.get("scoreboard"))}
        if tapped.get("scoreboard"):
            problems.append("[check] a finger on a weapon's place showed the ticket")
        finger(client, "touchEnd", None)
        page.wait_for_timeout(300)
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="844", help="the phone's page, 844 x 390 or 667 x 375")
    parser.add_argument("--left", action="store_true", help="the left-handed layout")
    parser.add_argument("--ui", type=float, default=1.0, help="the interface size (0.8, 1.0 or 1.25)")
    parser.add_argument("--bots", type=int, default=0, help="bots beside the player, 0 to 7")
    parser.add_argument("--label", default="after")
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
            run(p.chromium, url, args.out, args.label, result, PAGES[args.page], args.left, args.ui, args.bots)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    (args.out / f"{args.label}-result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nscoreboard column check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nscoreboard column check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
