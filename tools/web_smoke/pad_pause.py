"""Browser check that a gamepad's Start pauses and resumes the night (#494), on a virtual pad.

A browser lists a pad to a page, and the page's Godot turns the standard mapping's Start (button 9) into its
`JOY_BUTTON_START`, which the input map binds to `pause`. Start is also `ui_accept`, and the router once spent it on
giving a menu its focus, so the night never saw it. This run starts a solo night in headless Chromium with a virtual pad
(`navigator.getGamepads`, a standard-mapping pad with 17 buttons and 4 axes), where the page never gets the pointer lock
(`requestPointerLock` is stubbed, as it is for a player on a pad: a gamepad button is no user gesture), and checks that:

  1. the engine lists the pad and sees Start go down (`pad_start_presses`) and the `pause` action with it;
  2. Start opens the night's menu and the night stands still (`paused` true, `running` false);
  3. a second Start resumes it, and the pad then turns the view with the right stick although the mouse has no lock;
  4. Start, then B, also resumes.

    uv run --with playwright==1.64.1 python tools/web_smoke/pad_pause.py build/web build/pad-pause

Run it through `gds quiet` on Windows like every browser probe (docs/godot/web-export.md).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright
from pointer_lock import SOFTWARE_GL, VIEWPORT, probe, serve, wait_for
from smoke import probing, start_solo

LOAD_TIMEOUT_S = 150
# The night's load on a CI runner took 82 s to 107 s, and over 150 s on a slow one (see smoke.py).
NIGHT_LOAD_TIMEOUT_S = 300
# A software renderer draws one or two frames a second on a runner, and the game polls a pad once a frame: a button is
# held long enough for several frames, and the probe refreshes every 0.25 s.
HOLD_MS = 900
REACT_S = 8.0
TURN_HOLD_MS = 1500
TURN_RADIANS = 0.05

# Standard mapping: 0 A, 1 B, 9 Start; axes 0-1 the left stick, 2-3 the right one.
START = 9
B = 1
RIGHT_STICK_X = 2

# A pad the page can list, as a browser with a controller plugged in would, and a way to hold its buttons and sticks.
VIRTUAL_PAD = """
(() => {
  const pad = {id: 'Virtual pad', index: 0, connected: true, mapping: 'standard', timestamp: 1,
    axes: [0, 0, 0, 0], buttons: Array.from({length: 17}, () => ({pressed: false, touched: false, value: 0}))};
  Object.defineProperty(navigator, 'getGamepads', {value: () => [pad, null, null, null]});
  window.__padButton = (index, down) => {
    pad.buttons[index] = {pressed: down, touched: down, value: down ? 1 : 0};
    pad.timestamp += 1;
  };
  window.__padAxis = (index, value) => { pad.axes[index] = value; pad.timestamp += 1; };
})();
"""
# The page asks for the mouse when a night starts; here nothing is ever locked, as for a player on a pad.
NO_POINTER_LOCK = "Element.prototype.requestPointerLock = function () { return Promise.resolve(); };"


def tap(page: Page, button: int) -> None:
    page.evaluate("([i]) => window.__padButton(i, true)", [button])
    page.wait_for_timeout(HOLD_MS)
    page.evaluate("([i]) => window.__padButton(i, false)", [button])
    page.wait_for_timeout(300)


def reacted(page: Page, what: str, test) -> dict:
    return wait_for(page, what, test, REACT_S)


def run(page: Page, url: str, out: Path, result: dict) -> None:
    page.goto(probing(url), wait_until="commit")
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)
    start_solo(page)
    wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
    page.wait_for_timeout(1500)
    # A browser lists a pad after a button press on a page that has the focus: wake it before the first Start.
    page.evaluate("() => window.__padButton(0, true)")
    page.wait_for_timeout(HOLD_MS)
    page.evaluate("() => window.__padButton(0, false)")
    result["pads_listed"] = wait_for(page, "the engine to list the pad", lambda s: s.get("pad_count", 0) >= 1, REACT_S)[
        "pad_count"
    ]

    before = probe(page)
    result["start_1"] = {"night_running": before.get("running"), "paused": before.get("paused")}
    tap(page, START)
    after = probe(page)
    result["start_1"].update(
        engine_saw_start=after.get("pad_start_presses", 0) - before.get("pad_start_presses", 0),
        engine_saw_pause_action=after.get("pause_presses", 0) - before.get("pause_presses", 0),
    )
    try:
        reacted(page, "Start to pause the night", lambda s: bool(s.get("paused")) and not s.get("running"))
        result["start_pauses"] = True
    except TimeoutError:
        result["start_pauses"] = False
    page.screenshot(path=out / "1_after_start.png")

    tap(page, START)
    try:
        reacted(page, "a second Start to resume", lambda s: bool(s.get("running")) and not s.get("paused"))
        result["second_start_resumes"] = True
    except TimeoutError:
        result["second_start_resumes"] = False

    # The pad plays after the resume although the mouse never got its lock.
    yaw = probe(page).get("yaw", 0.0)
    page.evaluate("([i]) => window.__padAxis(i, 1.0)", [RIGHT_STICK_X])
    page.wait_for_timeout(TURN_HOLD_MS)
    page.evaluate("([i]) => window.__padAxis(i, 0.0)", [RIGHT_STICK_X])
    page.wait_for_timeout(500)
    turned = abs(probe(page).get("yaw", 0.0) - yaw)
    result["right_stick_turn_radians"] = round(turned, 3)
    result["pad_turns_the_view"] = turned > TURN_RADIANS
    page.screenshot(path=out / "2_after_resume.png")

    tap(page, START)
    try:
        reacted(page, "Start to pause again", lambda s: bool(s.get("paused")))
        tap(page, B)
        reacted(page, "B to resume", lambda s: bool(s.get("running")) and not s.get("paused"))
        result["b_resumes"] = True
    except TimeoutError:
        result["b_resumes"] = False
    result["final"] = {k: probe(page).get(k) for k in ("pad_count", "pad_start_presses", "pause_presses", "paused")}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html inside)")
    parser.add_argument("out", type=Path, help="where the captures and result.json go")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = serve(args.build)
    problems: list[str] = []
    result: dict = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        context = browser.new_context(viewport=VIEWPORT)
        context.add_init_script(VIRTUAL_PAD + NO_POINTER_LOCK)
        page = context.new_page()
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
    for key in ("start_pauses", "second_start_resumes", "pad_turns_the_view", "b_resumes"):
        if key in result and not result[key]:
            problems.append(f"[check] {key} is false")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\npad pause check FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\npad pause check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
