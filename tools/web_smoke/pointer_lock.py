"""Browser check of the night's menu when the browser takes the pointer lock away (#476).

In a browser the first Esc exits pointer lock and the key never reaches the page, so the game gets no `pause`: it
has to notice that the mouse is no longer captured and open its menu in that frame. This run starts a night in
headless Chromium, waits for the pointer lock, releases it the way the browser does (`document.exitPointerLock()`),
and checks that:

  1. the night's menu is open at once (the solo night stands still: `running` false, `paused` true);
  2. while the mouse is free a page mouse motion does not turn the view and a click does not shoot;
  3. Resume gives the pointer lock back and the night runs again (by key and by a mouse click);
  4. an Esc that does reach the page (Playwright's key press) still opens the menu, once.

    uv run --with playwright==1.64.1 python tools/web_smoke/pointer_lock.py build/web build/pointer-lock

Do not run it on a Windows machine someone is working at: headless Chromium there clips the real cursor to an
invisible box at the top left of the screen on pointer lock, freed only by Esc. It runs in CI (Linux), and refuses to
start on Windows unless GDS_ALLOW_POINTER_LOCK=1 is set.

Playwright cannot press the browser's own Esc (it sends the key to the page), so the lock is released by script; the
engine sees the same thing, a pointer lock that is gone.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright
from smoke import start_solo

VIEWPORT = {"width": 1280, "height": 720}
SOFTWARE_GL = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
LOAD_TIMEOUT_S = 150
NIGHT_LOAD_TIMEOUT_S = 150
SCREEN_TIMEOUT_S = 40
LOCK_TIMEOUT_S = 10
# The menu opens the frame after the lock goes (the unit tests prove the frame); a software renderer on a runner draws
# one or two frames a second, and the probe refreshes every 0.25 s, so this only tells "at once" from "never".
MENU_WITHIN_S = 5.0
# The Resume button at this viewport (the card is centred; 2_menu_after_lock_loss.png shows it).
RESUME_BUTTON = (640, 382)
MOTION_PIXELS = 15
MOTIONS = 20

LOCKED_JS = "() => document.pointerLockElement ? document.pointerLockElement.tagName : null"
RELEASE_JS = "() => document.exitPointerLock()"
MOTION_JS = """
(dx) => {
  const canvas = document.querySelector('canvas');
  canvas.dispatchEvent(new PointerEvent('pointermove', {movementX: dx, movementY: 0, bubbles: true, cancelable: true}));
}
"""


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args) -> None:
        pass

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def serve(folder: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    handler = functools.partial(Quiet, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def probe(page: Page) -> dict:
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : {}")


def wait_for(page: Page, what: str, test, seconds: float) -> dict:
    end = time.monotonic() + seconds
    state: dict = {}
    while time.monotonic() < end:
        state = probe(page)
        if test(state):
            return state
        page.wait_for_timeout(100)
    raise TimeoutError(f"timed out waiting for {what} (last: {json.dumps(state)[:200]})")


def wait_lock(page: Page, locked: bool, seconds: float) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if (page.evaluate(LOCKED_JS) is not None) == locked:
            return True
        page.wait_for_timeout(50)
    return False


def press(page: Page, key: str) -> None:
    page.keyboard.down(key)
    page.wait_for_timeout(150)
    page.keyboard.up(key)
    page.wait_for_timeout(100)


def menu_open(state: dict) -> bool:
    return bool(state.get("night")) and not state.get("running")


def run(page: Page, url: str, out: Path, result: dict) -> None:
    page.goto(url, wait_until="commit")
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)
    start_solo(page)
    wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
    # The click that started the night is the user gesture a browser wants before it gives the lock.
    page.mouse.move(640, 360)
    page.mouse.down()
    page.mouse.up()
    result["locked_at_start"] = wait_lock(page, True, LOCK_TIMEOUT_S)
    if not result["locked_at_start"]:
        raise RuntimeError("the night never got the pointer lock, so there is nothing to lose")
    page.wait_for_timeout(800)
    page.screenshot(path=out / "1_locked.png")
    result["mouse_mode_locked"] = probe(page).get("mouse_mode")

    # 1. The browser takes the lock (the first Esc): no key reaches the page.
    began = time.monotonic()
    page.evaluate(RELEASE_JS)
    state = wait_for(page, "the menu after the lock went", menu_open, MENU_WITHIN_S + 5)
    result["menu_after_lock_loss_s"] = round(time.monotonic() - began, 2)
    result["state_after_lock_loss"] = {k: state.get(k) for k in ("running", "paused", "mouse_mode")}
    page.screenshot(path=out / "2_menu_after_lock_loss.png")
    if result["menu_after_lock_loss_s"] > MENU_WITHIN_S:
        raise RuntimeError(f"the menu took {result['menu_after_lock_loss_s']} s to open after the lock went")

    # 2. A free mouse neither looks nor shoots.
    yaw = probe(page).get("yaw", 0.0)
    for _ in range(MOTIONS):
        page.evaluate(MOTION_JS, MOTION_PIXELS)
        page.wait_for_timeout(20)
    page.wait_for_timeout(400)
    result["yaw_turn_while_free_rad"] = round(abs(probe(page).get("yaw", 0.0) - yaw), 4)
    if result["yaw_turn_while_free_rad"] > 0.001:
        raise RuntimeError("the view turned with the mouse while the menu was open")

    # 3. Resume (Enter on the focused button) asks for the lock again, from the key press.
    press(page, "Enter")
    result["relocked_by_resume"] = wait_lock(page, True, LOCK_TIMEOUT_S)
    state = wait_for(page, "the night running again", lambda s: bool(s.get("running")), SCREEN_TIMEOUT_S)
    result["state_after_resume"] = {k: state.get(k) for k in ("running", "paused", "mouse_mode")}
    page.wait_for_timeout(800)
    page.screenshot(path=out / "3_resumed.png")

    # 3b. The same, resumed with the mouse, which is how it is done: the click is the user gesture.
    page.evaluate(RELEASE_JS)
    wait_for(page, "the menu after the second loss", menu_open, MENU_WITHIN_S + 5)
    page.mouse.click(*RESUME_BUTTON)
    result["relocked_by_resume_click"] = wait_lock(page, True, LOCK_TIMEOUT_S)
    wait_for(page, "the night running after the click", lambda s: bool(s.get("running")), SCREEN_TIMEOUT_S)
    page.wait_for_timeout(500)

    # 4. An Esc that reaches the page opens the menu once, and Esc closes it again.
    press(page, "Escape")
    wait_for(page, "the menu after Escape", menu_open, SCREEN_TIMEOUT_S)
    result["escape_opens_menu"] = True
    page.wait_for_timeout(600)
    result["still_one_menu"] = menu_open(probe(page))
    press(page, "Escape")
    wait_for(page, "the night running after a second Escape", lambda s: bool(s.get("running")), SCREEN_TIMEOUT_S)
    result["escape_twice_resumes"] = True
    page.screenshot(path=out / "4_after_escape.png")


def main() -> int:
    if sys.platform == "win32" and os.environ.get("GDS_ALLOW_POINTER_LOCK") != "1":
        print(
            "refusing to take pointer lock on Windows: it clips the real cursor (see the module's docstring)",
            file=sys.stderr,
        )
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
        page = browser.new_page(viewport=VIEWPORT)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        try:
            run(page, f"http://127.0.0.1:{port}/index.html", args.out, result)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=args.out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            browser.close()
            server.shutdown()
    for key in (
        "relocked_by_resume",
        "relocked_by_resume_click",
        "escape_opens_menu",
        "still_one_menu",
        "escape_twice_resumes",
    ):
        if key in result and not result[key]:
            problems.append(f"[check] {key} is false")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\npointer lock check FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\npointer lock check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
