"""The bots' order as a tag on the HUD, with real touches in a phone-sized browser (#1286).

Opens the exported game (`?touch=1&probe`) in Chrome with mobile emulation (a page of 844 x 390 or 667 x 375 CSS px at
a pixel ratio of 2, real touch events through the DevTools protocol), starts a solo night with `--bots` bots from the
Play screen (by touches) and reads the probe (`touch_zones`, `bot_order`, `bot_tag`, `touch_hints`, `notice_log`):

- the bots' tag is a place a finger presses (`bot_order_next`), at least 44 CSS px wide and high, on the side of the
  screen the hand asks for (`--left`), on the page and clear of every button's hit area; there is no bot wheel button;
- the first-run hint says what it does (`bots` among the hints on screen) before the first tap, and is gone after it;
- a tap gives the next order of Follow, Roam, Hold as the server's frame says it (`bot_order`, the word on the tag) and
  the feed says the bots' state (`BOTS: HOLDING POSITION`, `FOLLOWING YOU`, `ROAMING`);
- two taps inside the server's half second give one order: the refused one changes nothing and says nothing;
- a finger on the tag that drags away starts no stick, holds nothing but the tag and turns no view;
- with `--bots 0` there is no tag, no zone and no hint.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_bot_tag.py build/web build/tag \\
        [--page 844|667] [--left] [--ui 0.8|1.0|1.25] [--bots 3]

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
ACTION = "bot_order_next"
# The orders in the round a tap walks, and what the feed says once each stands.
ROUND = ("roam", "hold", "follow")
NOTICES = {"follow": "BOTS: FOLLOWING YOU", "roam": "BOTS: ROAMING", "hold": "BOTS: HOLDING POSITION"}
WORDS = {"follow": "FOLLOW", "roam": "ROAM", "hold": "HOLD"}
# The server lets a person give an order every half second; a tap waits this long after the last one.
SPACING_S = 0.9
REACT_S = 8.0
DRAG_PX = 120.0
STEPS = 10
STEP_PERIOD_S = 0.03
MAX_STILL_RAD = 0.01


def full(page) -> dict:
    return page.evaluate("() => ({ ...window.deadnight })") or {}


def spot(state: dict, name: str, size: dict) -> tuple[float, float]:
    for entry in str(state.get("spots", "")).split("|"):
        key, _, at = entry.rpartition(":")
        if key == name:
            x, _, y = at.partition(",")
            return float(x) * size["width"], float(y) * size["height"]
    raise RuntimeError(f"no {name!r} on screen (the page has: {state.get('spots')!r})")


def zones(state: dict, page: dict) -> dict[str, dict]:
    """Each place a finger presses as {x, y, w, h} in CSS px (the centre and the size)."""
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
    found = {}
    for entry in str(state.get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, hit, _was = (float(n) for n in numbers.split(","))
            found[name] = (x * page["width"], y * page["height"], hit * page["height"])
    return found


def gap_to(zone: dict, hit: tuple[float, float, float]) -> float:
    cx = min(max(hit[0], zone["x"] - zone["w"] / 2), zone["x"] + zone["w"] / 2)
    cy = min(max(hit[1], zone["y"] - zone["h"] / 2), zone["y"] + zone["h"] / 2)
    return math.hypot(hit[0] - cx, hit[1] - cy) - hit[2]


def finger(client, kind: str, point: tuple[float, float] | None) -> None:
    menu.smoke_touch(client, kind, [(1, *point)] if point else [])


def tap(client, point: tuple[float, float], hold_s: float = 0.08) -> None:
    finger(client, "touchStart", point)
    time.sleep(hold_s)
    finger(client, "touchEnd", None)


def seed_settings(page, ui_size: float, left: bool) -> None:
    text = f"[accessibility]\n\nui_scale={ui_size}\n\n[controls]\n\nleft_handed={'true' if left else 'false'}\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def bot_lines(state: dict) -> list[str]:
    return [line for line in str(state.get("notice_log", "")).split("|") if line.startswith("BOTS")]


def wait_order(page, order: str, label: str) -> dict:
    return menu.wait_for(
        page, label, lambda s, o=order: s.get("bot_order") == o and s.get("bot_tag") == WORDS[o], REACT_S
    )


def start_night(page, client, size: dict, bots: int) -> None:
    menu.tap(client, (size["width"] - 4, size["height"] / 2))
    state = full(page)
    menu.tap(client, spot(state, "Solo", size))
    menu.wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", 60)
    page.wait_for_timeout(1500)
    for _ in range(bots):
        menu.tap(client, spot(full(page), "bots:end", size))
    page.wait_for_timeout(300)
    menu.tap(client, spot(full(page), "Start the night", size))
    smoke.wait_for_night(page)


def run(browser_type, url: str, out: Path, result: dict, size: dict, left: bool, ui_size: float, bots: int) -> None:
    problems = result["problems"]
    browser = browser_type.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
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
    client = context.new_cdp_session(page)
    start_night(page, client, size, bots)
    page.wait_for_timeout(2500)
    result.update(page_css_px=size, interface_size=ui_size, left_handed=left, bots=bots)
    state = full(page)
    result["bots_in_room"] = state.get("bots")
    found = zones(state, size)
    hits = hit_areas(state, size)
    if "bot_wheel" in hits:
        problems.append("[check] the touch layer still has a bot_wheel button")

    if bots == 0:
        if ACTION in found or state.get("bot_tag"):
            problems.append(
                f"[check] a room without bots has a tag (zones {sorted(found)}, tag {state.get('bot_tag')!r})"
            )
        if "bots" in str(state.get("touch_hints", "")):
            problems.append("[check] a room without bots shows the bots hint")
        page.screenshot(path=out / "0_no_bots.png")
        browser.close()
        return

    if int(state.get("bots", 0)) != bots:
        problems.append(f"[check] {state.get('bots')} bots in the room, {bots} asked for")
    if ACTION not in found:
        problems.append(f"[check] no tag among the places {sorted(found)}")
        page.screenshot(path=out / "1_no_tag.png")
        browser.close()
        return
    tag = found[ACTION]
    result["tag_css_px"] = [round(tag["w"], 1), round(tag["h"], 1)]
    result["tag_centre_css_px"] = [round(tag["x"], 1), round(tag["y"], 1)]
    if min(tag["w"], tag["h"]) < TAP_CSS_PX - SLACK_CSS_PX:
        problems.append(f"[check] the tag is {tag['w']:.1f} x {tag['h']:.1f} CSS px, under {TAP_CSS_PX}")
    if (tag["x"] < size["width"] / 2) == left:
        problems.append(f"[check] the tag is on the wrong side for left_handed={left}")
    if not (0 <= tag["x"] - tag["w"] / 2 and tag["x"] + tag["w"] / 2 <= size["width"]):
        problems.append("[check] the tag leaves the page sideways")
    if not (0 <= tag["y"] - tag["h"] / 2 and tag["y"] + tag["h"] / 2 <= size["height"]):
        problems.append("[check] the tag leaves the page vertically")
    for button, hit in hits.items():
        if gap_to(tag, hit) <= 0:
            problems.append(f"[check] the tag is under the {button} button's hit area")
    for name, zone in found.items():
        if (
            name != ACTION
            and abs(zone["x"] - tag["x"]) < (zone["w"] + tag["w"]) / 2
            and abs(zone["y"] - tag["y"]) < (zone["h"] + tag["h"]) / 2
        ):
            problems.append(f"[check] the tag overlaps the {name} place")

    # The first-run hint is up before any tap, and the tag starts on the order that stands (Roam).
    hints = str(state.get("touch_hints", ""))
    result["hints_before_tap"] = hints
    if "bots" not in hints:
        problems.append(f"[check] the first time bots are in the room the hint is not up (hints: {hints!r})")
    page.screenshot(path=out / "1_hint_and_tag.png")
    state = wait_order(page, "roam", "the tag on Roam")
    result["start"] = {"order": state.get("bot_order"), "tag": state.get("bot_tag")}

    # A tap walks Roam -> Hold -> Follow -> Roam, the feed says the state once it stands.
    at = (tag["x"], tag["y"])
    result["taps"] = []
    seen_lines = len(bot_lines(full(page)))
    for number, order in enumerate(ROUND[1:] + ROUND[:1], start=1):
        page.wait_for_timeout(int(SPACING_S * 1000))
        tap(client, at)
        state = wait_order(page, order, f"the order {order} after tap {number}")
        page.wait_for_timeout(500)
        state = full(page)
        lines = bot_lines(state)
        result["taps"].append(
            {"order": order, "tag": state.get("bot_tag"), "feed": lines[seen_lines:], "notices": state.get("notices")}
        )
        if lines[seen_lines:] != [NOTICES[order]]:
            problems.append(
                f"[check] tap {number} to {order}: the feed said {lines[seen_lines:]}, not {[NOTICES[order]]}"
            )
        seen_lines = len(lines)
        page.screenshot(path=out / f"{number + 1}_tap_{number}_{order}.png")
        if number == 1 and "bots" in str(state.get("touch_hints", "")):
            problems.append("[check] the hint is still up after the first tap")

    # A refused order: two taps inside the server's half second give one order, and say one thing.
    page.wait_for_timeout(int(SPACING_S * 1000))
    before = full(page)
    first = ROUND[(ROUND.index(before["bot_order"]) + 1) % 3]
    lines_before = len(bot_lines(before))
    tap(client, at)
    page.wait_for_timeout(60)
    tap(client, at)
    page.wait_for_timeout(1500)
    after = full(page)
    result["refused"] = {
        "before": before.get("bot_order"),
        "after": after.get("bot_order"),
        "tag": after.get("bot_tag"),
        "feed": bot_lines(after)[lines_before:],
    }
    if after.get("bot_order") != first or after.get("bot_tag") != WORDS[first]:
        problems.append(
            f"[check] two taps inside the half second left {after.get('bot_order')!r}, not the first order {first!r}"
        )
    if bot_lines(after)[lines_before:] != [NOTICES[first]]:
        problems.append(f"[check] the refused tap changed the feed: {bot_lines(after)[lines_before:]}")
    page.screenshot(path=out / "5_two_quick_taps.png")

    # A finger that lands on the tag and drags away starts no stick, holds only the tag and turns no view.
    page.wait_for_timeout(int(SPACING_S * 1000))
    yaw_before = full(page).get("yaw", 0.0)
    finger(client, "touchStart", at)
    page.wait_for_timeout(300)
    held = str(full(page).get("touch_held", ""))
    for step in range(1, STEPS + 1):
        finger(
            client,
            "touchMove",
            (at[0] + DRAG_PX * step / STEPS * (-1 if left else 1), at[1] - DRAG_PX * 0.3 * step / STEPS),
        )
        time.sleep(STEP_PERIOD_S)
    page.wait_for_timeout(500)
    mid = full(page)
    turned = abs(math.remainder(mid.get("yaw", 0.0) - yaw_before, math.tau))
    result["drag_from_tag"] = {"held": held, "stick": mid.get("touch_stick"), "turn_rad": round(turned, 4)}
    page.screenshot(path=out / "6_drag_from_tag.png")
    finger(client, "touchEnd", None)
    page.wait_for_timeout(500)
    if held != ACTION:
        problems.append(f"[check] a finger on the tag held {held!r}")
    if mid.get("touch_stick"):
        problems.append("[check] a finger dragged from the tag started the move stick")
    if turned > MAX_STILL_RAD:
        problems.append(f"[check] a finger dragged from the tag turned the view {turned:.3f} rad")
    if str(full(page).get("touch_held", "")):
        problems.append(f"[check] a lifted finger left {full(page).get('touch_held')!r} held")
    result["end"] = {k: full(page).get(k) for k in ("bot_order", "bot_tag", "notices", "paused")}
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="844", help="the phone's page, 844 x 390 or 667 x 375")
    parser.add_argument("--left", action="store_true", help="the left-handed layout")
    parser.add_argument("--ui", type=float, default=1.0, help="the interface size (0.8, 1.0 or 1.25)")
    parser.add_argument("--bots", type=int, default=3, help="bots in the room (0 proves there is no tag)")
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
            run(p.chromium, url, args.out, result, PAGES[args.page], args.left, args.ui, args.bots)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nbot tag check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nbot tag check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
