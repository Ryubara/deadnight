"""The bot command wheel in a real browser (#642): a held key, a virtual pad and real touches.

The run exports a copy of the project that starts on `game/tests/captures/bot_wheel_bench.tscn` (the real project's
export leaves `tests/` out): the game's own night screen with the orders going to a recorder (`BotOrders` is #641's).
In headless Chrome it sends what a player would, through the browser, and reads what the game reports
(`window.__wheel`): whether the wheel is open, over which entry, which orders were heard, whether the view turned.

  1. keyboard and mouse: hold Q, move the mouse toward each entry, let go of Q: that order is heard; a tap of Q is not;
     the view does not turn while Q is held;
  2. a virtual pad (`navigator.getGamepads`, the standard mapping): hold the d-pad's left (button 14), push the right
     stick toward each entry, let go: that order is heard; the stick does not turn the view meanwhile;
  3. touch (a phone-sized page, `Input.dispatchTouchEvent`): a finger on the BOTS button held and dragged toward each
     entry, a second finger on the stick the whole time, lifted: that order is heard; a tap gives none; then a tap on
     the PING button marks a place; every button lies inside the page.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/bot_wheel.py <godot> <work folder> [--out <folder>]

`<godot>` is the pinned Godot (`gds tool path godot`). It fails when the browser logs an error, when the night pauses,
when an order is not the one asked for or a tap gives one, when the view turns under the wheel, or when a button leaves
the page.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke
import touch_assist

BENCH_SCENE = "res://tests/captures/bot_wheel_bench.tscn"
DESKTOP = {"width": 1280, "height": 720}
PHONE = {"width": 844, "height": 390}
READY_TIMEOUT_S = 240
HOLD_S = 0.5
# The entries by name and where the pointer must go (x right, y down, a unit disc), as the game draws them.
ENTRIES = {"follow": (0.0, -1.0), "roam": (0.866, 0.5), "hold": (-0.866, 0.5)}
# Moving the mouse this many page pixels toward an entry takes the pointer to the rim (the game's reach is 120 canvas
# units; the page is 1280 wide for a canvas 1920 wide).
MOUSE_PX = 100
# A finger's drag toward an entry: 40 page pixels is about 55 canvas units, 0.6 of the game's reach of 90, which is well
# past the middle and short enough for a thumb on the left edge (a left hand) to stay on the page.
TOUCH_PX = 40
RIGHT_STICK_X = 2
RIGHT_STICK_Y = 3
DPAD_LEFT = 14
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
NO_POINTER_LOCK = "Element.prototype.requestPointerLock = function () { return Promise.resolve(); };"


def state(page: Page) -> dict:
    return page.evaluate("window.__wheel || {}") or {}


def wait_ready(page: Page, label: str) -> None:
    deadline = time.monotonic() + READY_TIMEOUT_S
    while time.monotonic() < deadline and not state(page).get("ready"):
        time.sleep(0.5)
    if not state(page).get("ready"):
        raise TimeoutError(f"{label}: the bench never got ready: {state(page)}")
    time.sleep(1.0)


def wait_for(page: Page, label: str, test, seconds: float = 8.0) -> dict:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        now = state(page)
        if test(now):
            return now
        time.sleep(0.1)
    raise TimeoutError(f"{label}: never happened: {state(page)}")


def new_page(playwright, viewport: dict, touch: bool, init: list[str]):
    browser = playwright.chromium.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport=viewport, has_touch=touch, is_mobile=touch)
    for script in init:
        context.add_init_script(script)
    problems: list[str] = []
    page = context.new_page()
    page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
    page.on("console", lambda m: problems.append(f"console {m.type}: {m.text}") if m.type == "error" else None)
    return browser, context, page, problems


def heard(page: Page) -> list[str]:
    return [h["order"] for h in state(page).get("heard", [])]


def shot(page: Page, out: Path | None, name: str) -> None:
    if out is not None:
        out.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(out / name))


def keyboard_run(url: str, out: Path | None) -> dict:
    result: dict = {"orders": {}, "wrong": []}
    with sync_playwright() as p:
        browser, _context, page, problems = new_page(p, DESKTOP, False, [NO_POINTER_LOCK])
        page.goto(f"{url}?touch=0", wait_until="commit")
        wait_ready(page, "keyboard")
        page.mouse.click(5, 5)
        page.wait_for_timeout(300)
        centre_x, centre_y = DESKTOP["width"] / 2, DESKTOP["height"] / 2
        yaw_before = state(page)["yaw"]
        for name, (dx, dy) in ENTRIES.items():
            before = len(heard(page))
            page.mouse.move(centre_x, centre_y)
            page.keyboard.down("q")
            wait_for(page, "the wheel to open", lambda s: bool(s.get("open")))
            page.mouse.move(centre_x + dx * MOUSE_PX, centre_y + dy * MOUSE_PX, steps=8)
            seen = wait_for(page, f"the wheel over {name}", lambda s, n=name: s.get("hovered") == n)
            if name == "hold":
                shot(page, out, "desktop_open.png")
            result.setdefault("turned_while_held", abs(seen["yaw"] - yaw_before))
            page.keyboard.up("q")
            page.wait_for_timeout(300)
            got = heard(page)[before:]
            result["orders"][name] = got
            if got != [name]:
                result["wrong"].append(f"Q held over {name} gave {got}")
        # A tap of Q gives nothing, whatever the mouse did.
        before = len(heard(page))
        page.keyboard.down("q")
        page.wait_for_timeout(60)
        page.mouse.move(centre_x + MOUSE_PX, centre_y, steps=4)
        page.keyboard.up("q")
        page.wait_for_timeout(300)
        result["tap"] = heard(page)[before:]
        if result["tap"]:
            result["wrong"].append(f"a tap of Q gave {result['tap']}")
        if result["turned_while_held"] > 0.01:
            result["wrong"].append(f"the view turned {result['turned_while_held']:.3f} rad under the wheel")
        result["end"] = state(page)
        result["problems"] = problems
        browser.close()
    return result


def pad_run(url: str, out: Path | None) -> dict:
    result: dict = {"orders": {}, "wrong": []}
    with sync_playwright() as p:
        browser, _context, page, problems = new_page(p, DESKTOP, False, [VIRTUAL_PAD, NO_POINTER_LOCK])
        page.goto(f"{url}?touch=0", wait_until="commit")
        wait_ready(page, "pad")
        page.mouse.click(5, 5)
        # A browser lists a pad after a button press on a page that has the focus: wake it.
        page.evaluate("() => window.__padButton(0, true)")
        page.wait_for_timeout(600)
        page.evaluate("() => window.__padButton(0, false)")
        page.wait_for_timeout(300)
        yaw_before = state(page)["yaw"]
        for name, (dx, dy) in ENTRIES.items():
            before = len(heard(page))
            page.evaluate("([i]) => window.__padButton(i, true)", [DPAD_LEFT])
            wait_for(page, "the wheel to open", lambda s: bool(s.get("open")))
            page.evaluate("([x, y]) => { window.__padAxis(2, x); window.__padAxis(3, y); }", [dx, dy])
            seen = wait_for(page, f"the wheel over {name}", lambda s, n=name: s.get("hovered") == n)
            if name == "roam":
                shot(page, out, "pad_open.png")
            result.setdefault("turned_while_held", abs(seen["yaw"] - yaw_before))
            page.evaluate("([i]) => window.__padButton(i, false)", [DPAD_LEFT])
            page.wait_for_timeout(400)
            page.evaluate("() => { window.__padAxis(2, 0); window.__padAxis(3, 0); }")
            got = heard(page)[before:]
            result["orders"][name] = got
            if got != [name]:
                result["wrong"].append(f"the pad held over {name} gave {got}")
        if result["turned_while_held"] > 0.01:
            result["wrong"].append(
                f"the right stick turned the view {result['turned_while_held']:.3f} rad under the wheel"
            )
        result["end"] = state(page)
        result["problems"] = problems
        browser.close()
    return result


def touch_run(url: str, query: str, out: Path | None, label: str) -> dict:
    result: dict = {"orders": {}, "wrong": []}
    with sync_playwright() as p:
        browser, context, page, problems = new_page(p, PHONE, True, [])
        page.goto(f"{url}?{query}", wait_until="commit")
        wait_ready(page, label)
        client: CDPSession = context.new_cdp_session(page)
        time.sleep(0.5)
        end = state(page)
        buttons = end["buttons"]
        for name, (bx, by, radius) in buttons.items():
            if bx - radius < 0 or by - radius < 0 or bx + radius > PHONE["width"] or by + radius > PHONE["height"]:
                result["wrong"].append(
                    f"the {name} button ({bx:.0f}, {by:.0f}, r {radius:.0f}) leaves the {PHONE} page"
                )
        bx, by, _ = buttons["bot_wheel"]
        stick = (150.0, 260.0)
        yaw_before = state(page)["yaw"]
        for name, (dx, dy) in ENTRIES.items():
            before = len(heard(page))
            touch_assist.touch(client, "touchStart", [(2, *stick), (1, bx, by)])
            wait_for(page, "the wheel to open", lambda s: bool(s.get("open")))
            for step in range(1, 7):
                k = step / 6.0
                touch_assist.touch(
                    client, "touchMove", [(2, *stick), (1, bx + dx * TOUCH_PX * k, by + dy * TOUCH_PX * k)]
                )
                time.sleep(0.03)
            seen = wait_for(page, f"the wheel over {name}", lambda s, n=name: s.get("hovered") == n)
            if name == "hold":
                shot(page, out, f"touch_open_{label}.png")
            result.setdefault("turned_while_held", abs(seen["yaw"] - yaw_before))
            touch_assist.touch(client, "touchEnd", [(2, *stick)])
            page.wait_for_timeout(400)
            touch_assist.touch(client, "touchEnd", [])
            got = heard(page)[before:]
            result["orders"][name] = got
            if got != [name]:
                result["wrong"].append(f"a finger dragged to {name} gave {got}")
        before = len(heard(page))
        touch_assist.touch(client, "touchStart", [(1, bx, by)])
        time.sleep(0.07)
        touch_assist.touch(client, "touchEnd", [])
        page.wait_for_timeout(400)
        result["tap"] = heard(page)[before:]
        if result["tap"]:
            result["wrong"].append(f"a tap on the BOTS button gave {result['tap']}")
        if result["turned_while_held"] > 0.01:
            result["wrong"].append(f"the view turned {result['turned_while_held']:.3f} rad under the wheel")
        px, py, _ = buttons["ping"]
        pings = state(page).get("pings", 0)
        touch_assist.touch(client, "touchStart", [(1, px, py)])
        time.sleep(0.15)
        touch_assist.touch(client, "touchEnd", [])
        try:
            wait_for(page, "a ping mark", lambda s, n=pings: s.get("pings", 0) > n)
            result["ping"] = True
        except TimeoutError:
            result["ping"] = False
            result["wrong"].append("a tap on the PING button marked nothing")
        result["end"] = state(page)
        if result["end"].get("paused"):
            result["wrong"].append("the night paused")
        result["problems"] = problems
        browser.close()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="where the screenshots go")
    args = parser.parse_args()
    touch_assist.BENCH_SCENE = BENCH_SCENE
    web = touch_assist.export_bench(args.godot, args.work)
    server, port = smoke.serve(web)
    url = f"http://127.0.0.1:{port}/index.html"
    failed: list[str] = []
    runs = [
        ("keyboard", lambda: keyboard_run(url, args.out)),
        ("pad", lambda: pad_run(url, args.out)),
        ("touch right hand", lambda: touch_run(url, "touch=1&left=0", args.out, "right")),
        ("touch left hand", lambda: touch_run(url, "touch=1&left=1", args.out, "left")),
    ]
    try:
        for label, run in runs:
            try:
                result = run()
                end = result.pop("end", {})
                print(label, json.dumps({k: v for k, v in result.items() if k != "problems"}))
                failed += [f"{label}: {w}" for w in result["wrong"]]
                failed += [f"{label}: {p}" for p in result["problems"]]
                if end.get("paused"):
                    failed.append(f"{label}: the night paused")
            except (RuntimeError, TimeoutError) as error:
                failed.append(f"{label}: {error}")
    finally:
        server.shutdown()
    for line in failed:
        print("FAILED:", line)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
