"""Browser check of the night's menu with the settings in it (#471), on a desktop and on a phone in landscape.

Desktop (Chromium, 1280 x 720, keyboard and mouse): Esc opens the menu (the solo night stands still, the mouse is
free), Settings opens the same screen as the main menu's inside it, Esc goes back one step to the menu, Resume
takes the pointer lock back, and Leave night returns to the main menu.

Phone (Chrome with mobile emulation, 844 x 390, real touch events through the DevTools protocol, `?touch=1`): the
pause button on the touch layer opens the menu, a finger taps Settings, Back and Resume (a finger each) give the night
back with the touch layer up again.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/ingame_menu.py build/web build/ingame-menu

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails. Run it under `gds quiet`:
the desktop run takes the pointer lock (pointer_lock.py explains why).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

sys.path.insert(0, str(Path(__file__).parent))
import smoke

DESKTOP = {"width": 1280, "height": 720}
PHONE = {"width": 844, "height": 390}
PHONE_SCALE = 3
SOFTWARE_GL = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
SCREEN_TIMEOUT_S = 40
LOCK_TIMEOUT_S = 10
LOCKED_JS = "() => document.pointerLockElement ? document.pointerLockElement.tagName : null"
# The pause button of the touch layer in the 844 x 390 landscape layout, as a fraction of the window (read off
# phone_1_night.png: the round bar at the top left, the pause button beside it; the scoreboard button is below it).
PAUSE_BUTTON = (0.189, 0.074)


def probe(page: Page) -> dict:
    """Everything the game publishes (smoke.probe keeps a few keys only)."""
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : {}")


def wait_for(page: Page, what: str, test, seconds: float = SCREEN_TIMEOUT_S) -> dict:
    end = time.monotonic() + seconds
    state: dict = {}
    while time.monotonic() < end:
        state = probe(page)
        if test(state):
            return state
        page.wait_for_timeout(100)
    keys = ("screen", "night", "running", "paused", "settings_open", "menu_buttons", "mouse_mode")
    raise TimeoutError(f"timed out waiting for {what} (last: { ({k: state.get(k) for k in keys}) })")


def wait_lock(page: Page, locked: bool, seconds: float) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if (page.evaluate(LOCKED_JS) is not None) == locked:
            return True
        page.wait_for_timeout(50)
    return False


def spot(state: dict, text: str, size: dict) -> tuple[float, float]:
    """Where the menu button `text` is, in CSS pixels of the window."""
    for entry in str(state.get("menu_buttons", "")).split("|"):
        name, _, at = entry.partition(":")
        if name == text:
            x, _, y = at.partition(",")
            return float(x) * size["width"], float(y) * size["height"]
    raise RuntimeError(f"no button {text!r} in the menu (it has: {state.get('menu_buttons')!r})")


def menu_open(state: dict) -> bool:
    return bool(state.get("night")) and "Resume:" in str(state.get("menu_buttons", ""))


def tap(client: CDPSession, at: tuple[float, float]) -> None:
    x, y = at
    smoke_touch(client, "touchStart", [(1, x, y)])
    time.sleep(0.08)
    smoke_touch(client, "touchEnd", [])
    time.sleep(0.4)


def smoke_touch(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    client.send(
        "Input.dispatchTouchEvent",
        {"type": kind, "touchPoints": [{"id": i, "x": x, "y": y} for i, x, y in points]},
    )


def desktop(browser, url: str, out: Path, result: dict) -> None:
    page = browser.new_page(viewport=DESKTOP)
    problems = result["problems"]
    page.on("pageerror", lambda error: problems.append(f"[desktop pageerror] {error}"))
    page.goto(url, wait_until="commit")
    smoke.reach_menu(page)
    smoke.start_solo(page)
    smoke.wait_for_night(page)
    page.mouse.move(640, 360)
    page.mouse.down()
    page.mouse.up()
    result["desktop_locked_at_start"] = wait_lock(page, True, LOCK_TIMEOUT_S)
    page.wait_for_timeout(800)
    page.screenshot(path=out / "desktop_1_night.png")

    smoke.press(page, "Escape")
    state = wait_for(page, "the menu after Escape", menu_open)
    result["desktop_menu_stops_the_night"] = state.get("paused") and not state.get("running")
    page.wait_for_timeout(500)
    page.screenshot(path=out / "desktop_2_menu.png")

    # Settings: the page's mouse click, as a player does it.
    page.mouse.click(*spot(probe(page), "Settings", DESKTOP))
    wait_for(page, "the settings in the menu", lambda s: bool(s.get("settings_open")))
    page.wait_for_timeout(900)
    page.screenshot(path=out / "desktop_3_settings.png")
    result["desktop_settings_open"] = True

    smoke.press(page, "Escape")
    state = wait_for(
        page, "the menu after Escape in the settings", lambda s: menu_open(s) and not s.get("settings_open")
    )
    result["desktop_escape_goes_back_one_step"] = bool(state.get("paused"))

    page.mouse.click(*spot(probe(page), "Resume", DESKTOP))
    result["desktop_relocked_by_resume"] = wait_lock(page, True, LOCK_TIMEOUT_S)
    state = wait_for(page, "the night running again", lambda s: bool(s.get("running")))
    page.wait_for_timeout(500)
    page.screenshot(path=out / "desktop_4_resumed.png")

    smoke.press(page, "Escape")
    wait_for(page, "the menu again", menu_open)
    page.mouse.click(*spot(probe(page), "Leave night", DESKTOP))
    wait_for(page, "the main menu after Leave night", lambda s: s.get("screen") == "main_menu")
    result["desktop_leave_night_returns_to_the_menu"] = True
    page.screenshot(path=out / "desktop_5_left.png")
    page.close()


def phone(browser_type, url: str, out: Path, result: dict) -> None:
    browser = browser_type.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport=PHONE, device_scale_factor=PHONE_SCALE, has_touch=True, is_mobile=True)
    page = context.new_page()
    problems = result["problems"]
    page.on("pageerror", lambda error: problems.append(f"[phone pageerror] {error}"))
    # A phone gives no pointer lock to a headless run, and the touch layer needs none.
    page.add_init_script("Element.prototype.requestPointerLock = function () {};")
    page.goto(f"{url}?touch=1", wait_until="commit")
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    smoke.start_solo(page)
    wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S)
    page.wait_for_timeout(2500)
    client = context.new_cdp_session(page)
    result["phone_touch_layer"] = bool(probe(page).get("touch"))
    page.screenshot(path=out / "phone_1_night.png")

    tap(client, (PAUSE_BUTTON[0] * PHONE["width"], PAUSE_BUTTON[1] * PHONE["height"]))
    state = wait_for(page, "the menu after the pause button", menu_open)
    result["phone_pause_button_opens_menu"] = bool(state.get("paused"))
    page.wait_for_timeout(500)
    page.screenshot(path=out / "phone_2_menu.png")

    tap(client, spot(probe(page), "Settings", PHONE))
    wait_for(page, "the settings in the menu", lambda s: bool(s.get("settings_open")))
    page.wait_for_timeout(900)
    page.screenshot(path=out / "phone_3_settings.png")
    result["phone_settings_open"] = True

    tap(client, spot(probe(page), "Back", PHONE))
    wait_for(page, "the menu after Back", lambda s: menu_open(s) and not s.get("settings_open"))
    tap(client, spot(probe(page), "Resume", PHONE))
    state = wait_for(page, "the night running again", lambda s: bool(s.get("running")))
    result["phone_resume_by_finger"] = not state.get("paused") and bool(state.get("touch"))
    page.wait_for_timeout(500)
    page.screenshot(path=out / "phone_4_resumed.png")
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--only", choices=("desktop", "phone"), help="run one of the two")
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
            if args.only != "phone":
                browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
                try:
                    desktop(browser, url, args.out, result)
                finally:
                    browser.close()
            if args.only != "desktop":
                phone(p.chromium, url, args.out, result)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    wanted = [
        "desktop_menu_stops_the_night",
        "desktop_settings_open",
        "desktop_escape_goes_back_one_step",
        "desktop_relocked_by_resume",
        "desktop_leave_night_returns_to_the_menu",
        "phone_pause_button_opens_menu",
        "phone_settings_open",
        "phone_resume_by_finger",
    ]
    for key in wanted:
        if args.only and not key.startswith(args.only):
            continue
        if not result.get(key):
            result["problems"].append(f"[check] {key} is not true")
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nin-game menu check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nin-game menu check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
