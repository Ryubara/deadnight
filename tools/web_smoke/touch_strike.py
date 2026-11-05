"""The Strike button of the phone in a real phone-sized browser, with real touches (issue #1285).

Opens the exported game (`?touch=1`) in Chrome with mobile emulation (a page of 844 x 390 or 667 x 375 CSS px at a pixel
ratio of 2, real touch events through the DevTools protocol), starts a solo night and plays what a right thumb does:

- with no dead near, there is no Strike button (the probe's `touch_strike` is false) and a finger on its place holds
  nothing; the screenshot with the fingers lifted shows no sixth circle;
- the dead come for the player on their own; when one is within reach of the quick melee the button is there (a
  screenshot with the fingers lifted, the hint "STRIKE" beside it), a finger on its centre holds `quick_melee` (a
  screenshot with the finger down) and the thumb taps again while the button shows: each tap is a blow the game counts
  (`quick_melees`; whether it lands depends on where the view looks, as the blow goes along it);
- every reading of the whole fight obeys the rule: the button is up with a dead inside the blow's 1.6 m and down with
  none (the probe publishes `dead_gap_m` beside `touch_strike`), and it goes when the last dead is killed;
- the button's hit area is at least 44 CSS px across, on the hand's side of the screen, inside the page, and clear of
  every other button's hit area.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_strike.py build/web out \\
        [--page 844|667] [--left]

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
SLACK_CSS_PX = 0.5
# A dead walks to the player on its own: how long to wait for the first and for the next.
DEAD_TIMEOUT_S = 150.0
REACT_S = 8.0
HOLD_S = 0.3
MAX_TAPS = 24
STRIKE = "quick_melee"
# The quick melee's reach and how much farther a dead may go before the button goes (`StrikeReach`), and the slack
# for the frame between the probe's two numbers.
REACH_M = 1.6
LEAVE_M = 0.3
EDGE_M = 0.15


def hit_areas(state: dict, page: dict) -> dict[str, tuple[float, float, float]]:
    """Each button's hit area as (x, y, radius) in CSS px, from the probe's `touch_hits`."""
    found = {}
    for entry in str(state.get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, hit, _was = (float(n) for n in numbers.split(","))
            found[name] = (x * page["width"], y * page["height"], hit * page["height"])
    return found


def finger(client, kind: str, point: tuple[float, float] | None) -> None:
    menu.smoke_touch(client, kind, [(1, *point)] if point else [])


def seed_settings(page, left: bool) -> None:
    text = f"[controls]\n\nleft_handed={'true' if left else 'false'}\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def sample(page, samples: list) -> dict:
    """One probe reading, kept as (gap in metres to the nearest dead, whether Strike shows)."""
    state = menu.probe(page)
    samples.append((round(float(state.get("dead_gap_m", -1.0)), 2), bool(state.get("touch_strike"))))
    return state


def check_sample(gap: float, up: bool) -> str:
    """The rule: up with a dead inside the blow's reach, down with none (or past the reach and the margin)."""
    if 0 <= gap < REACH_M - EDGE_M and not up:
        return f"the strike button was down with a dead {gap} m away (reach {REACH_M} m)"
    if (gap < 0 or gap > REACH_M + LEAVE_M + EDGE_M) and up:
        return f"the strike button was up with the nearest dead {gap} m away (reach {REACH_M} m, leaves at {REACH_M + LEAVE_M} m)"
    return ""


def wait_strike(page, up: bool, seconds: float, samples: list | None = None) -> dict:
    """The probe once `touch_strike` is `up`, polled every 50 ms (the button can stand only a moment)."""
    end = time.monotonic() + seconds
    state: dict = {}
    while time.monotonic() < end:
        state = menu.probe(page) if samples is None else sample(page, samples)
        if bool(state.get("touch_strike")) == up:
            return state
        page.wait_for_timeout(50)
    raise TimeoutError(f"touch_strike never became {up} in {seconds:.0f} s (kills {state.get('kills')})")


def run(browser_type, url: str, out: Path, result: dict, size: dict, left: bool) -> None:
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
    state = menu.wait_for(page, "the touch layer", lambda s: bool(s.get("touch_hits")), REACT_S)
    result["page_css_px"] = size
    result["left_handed"] = left
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    hits = hit_areas(state, size)
    strike = hits.get(STRIKE)
    if strike is None:
        problems.append(f"[check] the layer has no {STRIKE} button (has {sorted(hits)})")
        browser.close()
        return
    result["strike_hit_css_px"] = [round(v, 1) for v in strike]

    # The place: a fingertip across, on the hand's side, inside the page, clear of every other hit area.
    if strike[2] * 2 < TAP_CSS_PX - SLACK_CSS_PX:
        problems.append(f"[check] the strike hit area is {strike[2] * 2:.1f} CSS px, under {TAP_CSS_PX}")
    if (strike[0] < size["width"] / 2) != left:
        problems.append(f"[check] the strike button is on the wrong side for left_handed={left}")
    if strike[0] - strike[2] < 0 or strike[0] + strike[2] > size["width"]:
        problems.append("[check] the strike hit area leaves the page sideways")
    if strike[1] - strike[2] < 0 or strike[1] + strike[2] > size["height"]:
        problems.append("[check] the strike hit area leaves the page vertically")
    for name, hit in hits.items():
        if name in (STRIKE, "interact"):
            continue
        gap = math.hypot(strike[0] - hit[0], strike[1] - hit[1]) - strike[2] - hit[2]
        if gap < -1.0:
            problems.append(f"[check] the strike hit area is {-gap:.1f} CSS px into the {name} hit area")

    # No dead near: no button, and a finger on its place holds nothing.
    samples: list = []
    state = sample(page, samples)
    result["at_the_start"] = {"touch_strike": state.get("touch_strike"), "alive": state.get("alive")}
    if state.get("touch_strike"):
        problems.append("[check] the strike button shows with no dead in reach at the start")
    page.screenshot(path=out / "1_no_dead_fingers_lifted.png")
    finger(client, "touchStart", (strike[0], strike[1]))
    page.wait_for_timeout(300)
    held = str(menu.probe(page).get("touch_held", ""))
    finger(client, "touchEnd", None)
    result["touch_on_the_empty_place_held"] = held
    if held:
        problems.append(f"[check] a finger on the hidden strike place held {held!r}")
    page.wait_for_timeout(300)

    # The dead come: the button is there, a finger on it strikes, the thumb taps again while the button shows (the
    # cooldown is 0.6 s), and with no dead left in reach the button goes. Every probe reading is a sample of
    # (gap to the nearest dead in metres, button up) and the whole fight must obey the rule (`check_sample`).
    state = wait_strike(page, True, DEAD_TIMEOUT_S, samples)
    kills_before = int(state.get("kills", 0))
    blows_before = int(state.get("quick_melees", 0))
    page.screenshot(path=out / "2_dead_in_reach_fingers_lifted.png")
    state = sample(page, samples)
    up_at_shot = bool(state.get("touch_strike"))
    taps = 0
    held = ""
    killed = kills_before
    blows = blows_before
    while taps < MAX_TAPS:
        state = sample(page, samples)
        if not state.get("touch_strike") or state.get("over"):
            break  # no dead in reach: the button is gone, as it should be
        circle = hit_areas(state, size).get(STRIKE, strike)
        finger(client, "touchStart", (circle[0], circle[1]))
        taps += 1
        end = time.monotonic() + 1.0
        seen = ""
        while time.monotonic() < end and seen != STRIKE:
            seen = str(menu.probe(page).get("touch_held", ""))
            page.wait_for_timeout(30)
        if taps == 1:
            held = seen
            page.screenshot(path=out / "3_finger_down_on_strike.png")
        else:
            page.wait_for_timeout(HOLD_S * 1000)
        finger(client, "touchEnd", None)
        page.wait_for_timeout(700)
        state = sample(page, samples)
        killed = int(state.get("kills", 0))
        blows = int(state.get("quick_melees", 0))
        if killed > kills_before and not state.get("touch_strike"):
            break
    gone = False
    end = time.monotonic() + REACT_S
    while time.monotonic() < end:
        state = sample(page, samples)
        if not state.get("touch_strike"):
            gone = True
            break
        page.wait_for_timeout(100)
    page.screenshot(path=out / "4_finger_lifted_after.png")
    final = menu.probe(page)
    result["fight"] = {
        "up_when_photographed": up_at_shot,
        "held": held,
        "taps": taps,
        "blows": blows - blows_before,
        "kills": killed - kills_before,
        "strike_gone_after": gone,
        "player_killed": bool(final.get("over")),
        "samples": len(samples),
        "samples_up": sum(1 for _gap, up in samples if up),
    }
    result["samples"] = samples
    if held != STRIKE:
        problems.append(f"[check] a finger on the strike button held {held!r}, not {STRIKE!r}")
    if blows <= blows_before:
        problems.append(f"[check] {taps} taps on the strike button made no blow (blows {blows_before} then {blows})")
    if not gone and not final.get("over"):
        problems.append("[check] the strike button never went with the dead killed or out of reach")
    for gap, up in samples:
        wrong = check_sample(gap, up)
        if wrong:
            problems.append(f"[check] {wrong}")
            break
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="844", help="the phone's page, 844 x 390 or 667 x 375")
    parser.add_argument("--left", action="store_true", help="the left-handed layout")
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
            run(p.chromium, url, args.out, result, PAGES[args.page], args.left)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nstrike check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nstrike check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
