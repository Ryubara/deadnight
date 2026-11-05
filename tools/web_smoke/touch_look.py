"""Touch look and the move stick in a real phone-sized browser (issue #470).

Opens the exported game (`?touch=1`) in Chrome with mobile emulation (844 x 390 CSS pixels, device pixel ratio 3, real
touch events sent through the DevTools protocol), starts a night with the keyboard, and sends what thumbs do:

- a finger on the move stick that wanders around: the view must not turn;
- a finger on the look area that drags a known distance: the view must turn by about the angle the touch design page
  promises (`TouchLook`), no more, with no single frame turning further than a small step.

It reads the camera's yaw from `window.deadnight` (game/core/web_probe.gd) every frame it can, and counts the
`pointermove` events the browser made for the touches (Godot's web runtime reads every `pointermove` of the window as
a mouse motion, a touch included: that was the cause of #470).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_look.py build/web build/touch_look

The first argument is the exported folder or a URL; the second is where the screenshots and `result.json` go. Exits 1
when the stick turns the view, when the look drag turns it by more than `MAX_TURN_RATIO` times what the design says, or
when one frame jumps by more than `MAX_FRAME_TURN_RAD`.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

VIEWPORT = {"width": 844, "height": 390}
DEVICE_SCALE = 3
LOAD_TIMEOUT_S = 240
# Where the fingers land, in CSS pixels: the stick zone is the left side below the top fifth, the look area is the rest.
STICK_FROM = (110.0, 300.0)
LOOK_FROM = (520.0, 110.0)
# The Aim button's centre on the 844 x 390 phone (read off the probe's screenshot), for the drag that starts on it.
AIM_FROM = (728.0, 202.0)
STEPS = 20
STEP_PERIOD_S = 0.03
# A look drag, in CSS pixels, and what the design promises for it: radians per screen height at sensitivity 1
# (game/ui/touch/touch_look.gd, `RADIANS_PER_HEIGHT`) at the slow-drag gain of 1.
LOOK_DRAG_PX = 100.0
RADIANS_PER_HEIGHT = 1.6
MAX_TURN_RATIO = 1.25
MAX_FLICK_GAIN = 1.6
AIM_TOLERANCE = 0.05
# How long the finger holds Aim before it drags: the aim eases in over about a second, and the look scale with it.
AIM_SETTLE_S = 1.5
# The look scale the game applies once the aim has eased in (`aim_sensitivity_scale`, game/gameplay/player).
ADS_LOOK_SCALE = float(
    re.search(
        r"aim_sensitivity_scale := ([0-9.]+)",
        (Path(__file__).parents[2] / "game/gameplay/player/player_tuning.gd").read_text(encoding="utf-8"),
    ).group(1)
)
# The view turned by the stick must be below this; a few thousandths is the hand-off noise.
MAX_STICK_TURN_RAD = 0.02
MAX_FRAME_TURN_RAD = 0.35

POINTER_JS = """
() => {
  window.__pointer = { touch: 0, mouse: 0, touchMovement: 0 };
  window.addEventListener('pointermove', (e) => {
    if (e.pointerType === 'touch') {
      window.__pointer.touch += 1;
      window.__pointer.touchMovement += Math.abs(e.movementX || 0);
    } else {
      window.__pointer.mouse += 1;
    }
  }, true);
}
"""

# Headless Chromium on Windows clips the real cursor to a box at the top left while a page holds pointer lock, so the
# run never lets it: the request is counted and dropped (`result["pointer_lock_requests"]`).
NO_POINTER_LOCK_JS = """
() => {
  window.__lockRequests = 0;
  Element.prototype.requestPointerLock = function () { window.__lockRequests += 1; };
}
"""

# Records the yaw the game reports on every animation frame, with the page's clock.
YAW_TRACE_JS = """
() => {
  window.__yaws = [];
  const tick = () => {
    const d = window.deadnight;
    if (d) window.__yaws.push([performance.now(), d.yaw]);
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}
"""


def touch(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    """One touch event: `points` are the fingers down after it, as (id, x, y) in CSS pixels."""
    client.send(
        "Input.dispatchTouchEvent",
        {"type": kind, "touchPoints": [{"id": i, "x": x, "y": y} for i, x, y in points]},
    )


def drag(client: CDPSession, finger: int, start: tuple[float, float], delta: tuple[float, float]) -> None:
    """A finger down at `start`, moved by `delta` in even steps, then lifted."""
    x, y = start
    touch(client, "touchStart", [(finger, x, y)])
    time.sleep(STEP_PERIOD_S)
    for step in range(1, STEPS + 1):
        touch(client, "touchMove", [(finger, x + delta[0] * step / STEPS, y + delta[1] * step / STEPS)])
        time.sleep(STEP_PERIOD_S)
    touch(client, "touchEnd", [])
    time.sleep(0.4)


def hold_then_drag(
    client: CDPSession, finger: int, start: tuple[float, float], delta: tuple[float, float], hold_s: float
) -> None:
    """A finger down at `start` that stays `hold_s` before it moves by `delta` in even steps and lifts."""
    x, y = start
    touch(client, "touchStart", [(finger, x, y)])
    time.sleep(hold_s)
    for step in range(1, STEPS + 1):
        touch(client, "touchMove", [(finger, x + delta[0] * step / STEPS, y + delta[1] * step / STEPS)])
        time.sleep(STEP_PERIOD_S)
    touch(client, "touchEnd", [])
    time.sleep(0.4)


def wander(client: CDPSession, finger: int, start: tuple[float, float], shot=None) -> None:
    """A stick finger that pushes right by 120 px and comes back half way, as a thumb steering does."""
    x, y = start
    touch(client, "touchStart", [(finger, x, y)])
    time.sleep(STEP_PERIOD_S)
    for dx in (120.0, -60.0):
        for step in range(1, STEPS + 1):
            touch(client, "touchMove", [(finger, x + dx * step / STEPS, y)])
            time.sleep(STEP_PERIOD_S)
        x += dx
        if shot is not None:
            shot()
            shot = None
    touch(client, "touchEnd", [])
    time.sleep(0.4)


def two_thumbs(client: CDPSession, stick: tuple[float, float], look: tuple[float, float], shot=None) -> None:
    """The stick finger wanders while the look finger drags `LOOK_DRAG_PX` to the right, both moving in every event
    (#497: with two fingers down the first drag of each had a wrong `relative` and the view flicked round)."""
    sx, sy = stick
    lx, ly = look
    touch(client, "touchStart", [(1, sx, sy)])
    time.sleep(STEP_PERIOD_S)
    touch(client, "touchStart", [(1, sx, sy), (2, lx, ly)])
    time.sleep(STEP_PERIOD_S)
    for step in range(1, STEPS + 1):
        stick_at = (sx + 80.0 * math.sin(step / 4.0), sy - 30.0 * step / STEPS)
        look_at = (lx + LOOK_DRAG_PX * step / STEPS, ly)
        touch(client, "touchMove", [(1, *stick_at), (2, *look_at)])
        time.sleep(STEP_PERIOD_S)
        if shot is not None and step == STEPS // 2:
            shot()
    touch(client, "touchEnd", [])
    time.sleep(0.4)


def yaw(page: Page) -> float:
    return float(smoke.probe(page).get("yaw", 0.0))


def turns(page: Page) -> tuple[float, float]:
    """The largest yaw change between two reported frames since the trace began, and the total travel."""
    trace = page.evaluate("window.__yaws") or []
    biggest = 0.0
    for before, after in itertools.pairwise(trace):
        step = abs(math.remainder(after[1] - before[1], math.tau))
        biggest = max(biggest, step)
    return biggest, len(trace)


def use_the_keyboard(page: Page, client: CDPSession) -> None:
    """A finger types on the keypad of Play together and on the name field's keyboard, and leaves the screen: what a
    player who joined by a code does before a night (issue #1183). The touch controls must work after it."""
    import phone_keyboard as pk
    import rooms

    smoke.open_together(page)
    pk.tap_box(page, client, pk.css_box(page, "fields", "Code"))
    smoke.wait_for(page, "the keypad", lambda s: "Delete" in str(rooms.read_probe(page).get("spots", "")), 20)
    page.wait_for_timeout(600)
    for letter in "AB2":
        x, y = pk.key_point(page, letter)
        pk.tap(page, client, x, y)
        page.wait_for_timeout(150)
    page.wait_for_timeout(600)  # the game publishes its state every 0.25 s
    typed = rooms.read_probe(page).get("code_text")
    if typed != "AB2":
        page.screenshot(path="keypad_failed.png")
        raise SystemExit(f"the keypad did not type the code: the field holds {typed!r}")
    x, y = pk.key_point(page, "Join")
    pk.tap(page, client, x, y)
    smoke.wait_for(page, "the name prompt", lambda s: bool(rooms.read_probe(page).get("naming")), 30)
    page.wait_for_timeout(1000)
    pk.tap(page, client, 40, 40)
    page.wait_for_timeout(600)
    pk.tap_box(page, client, pk.css_box(page, "fields", "PlayerName"))
    page.wait_for_timeout(1000)
    page.keyboard.insert_text("Cal")
    page.wait_for_timeout(500)
    pk.tap(page, client, 40, 40)
    page.wait_for_timeout(600)
    smoke.back_to_menu(page)


def start_night(page: Page, client: CDPSession | None = None, keyboard: bool = False) -> None:
    smoke.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    if keyboard and client is not None:
        use_the_keyboard(page, client)
    smoke.start_solo(page)
    smoke.wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), 240)
    page.wait_for_timeout(2500)


def run(url: str, out: Path, keyboard: bool = False) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    result: dict = {"viewport": VIEWPORT, "device_scale_factor": DEVICE_SCALE}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(
            viewport=VIEWPORT, device_scale_factor=DEVICE_SCALE, has_touch=True, is_mobile=True
        )
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.on(
            "console",
            lambda m: problems.append(f"console {m.type}: {m.text}") if m.type == "error" else None,
        )
        page.add_init_script("(" + POINTER_JS.strip() + ")();")
        page.add_init_script("(" + NO_POINTER_LOCK_JS.strip() + ")();")
        page.goto(f"{url}?touch=1", wait_until="commit")
        client = context.new_cdp_session(page)
        start_night(page, client, keyboard)
        page.evaluate(YAW_TRACE_JS)
        result["pointer_lock_requests"] = page.evaluate("window.__lockRequests")
        result["probe_touch"] = smoke.probe(page).get("touch")
        page.screenshot(path=str(out / "night_touch.png"))

        before = yaw(page)
        wander(client, 1, STICK_FROM, lambda: page.screenshot(path=str(out / "stick_held.png")))
        result["stick_turn_rad"] = abs(math.remainder(yaw(page) - before, math.tau))
        result["stick_pointer"] = page.evaluate("window.__pointer")
        page.screenshot(path=str(out / "after_stick.png"))

        page.evaluate("window.__yaws.length = 0; window.__pointer = { touch: 0, mouse: 0, touchMovement: 0 };")
        before = yaw(page)
        drag(client, 2, LOOK_FROM, (LOOK_DRAG_PX, 0.0))
        result["look_turn_rad"] = abs(math.remainder(yaw(page) - before, math.tau))
        result["look_pointer"] = page.evaluate("window.__pointer")
        result["look_biggest_frame_turn_rad"], result["look_frames"] = turns(page)
        result["look_expected_rad"] = RADIANS_PER_HEIGHT * LOOK_DRAG_PX / VIEWPORT["height"]
        page.screenshot(path=str(out / "after_look.png"))
        page.evaluate("window.__yaws.length = 0")
        before = yaw(page)
        two_thumbs(client, STICK_FROM, LOOK_FROM, lambda: page.screenshot(path=str(out / "two_thumbs.png")))
        result["two_turn_rad"] = abs(math.remainder(yaw(page) - before, math.tau))
        result["two_biggest_frame_turn_rad"], result["two_frames"] = turns(page)

        page.evaluate("window.__yaws.length = 0")
        before = yaw(page)
        hold_then_drag(client, 3, AIM_FROM, (LOOK_DRAG_PX, 0.0), AIM_SETTLE_S)
        result["aim_turn_rad"] = abs(math.remainder(yaw(page) - before, math.tau))
        result["pointer_lock_requests"] = page.evaluate("window.__lockRequests")
        browser.close()
    result["problems"] = problems
    return result


def verdict(result: dict) -> list[str]:
    wrong = list(result["problems"])
    if result["stick_turn_rad"] > MAX_STICK_TURN_RAD:
        wrong.append(f"the move stick turned the view by {result['stick_turn_rad']:.3f} rad")
    if result["look_turn_rad"] > result["look_expected_rad"] * MAX_TURN_RATIO:
        wrong.append(
            f"a {LOOK_DRAG_PX:.0f} px look drag turned the view {result['look_turn_rad']:.3f} rad, "
            f"the design says {result['look_expected_rad']:.3f}"
        )
    if result["look_turn_rad"] < result["look_expected_rad"] / MAX_TURN_RATIO:
        wrong.append(f"a look drag turned the view only {result['look_turn_rad']:.3f} rad")
    if result["look_biggest_frame_turn_rad"] > MAX_FRAME_TURN_RAD:
        wrong.append(f"one frame turned the view {result['look_biggest_frame_turn_rad']:.3f} rad")
    expected = result["look_expected_rad"]
    # A fast flick gains up to MAX_GAIN, so two thumbs may turn more than the slow design, but not by a whole screen.
    if result["two_turn_rad"] > expected * MAX_TURN_RATIO * MAX_FLICK_GAIN:
        wrong.append(f"two thumbs: a {LOOK_DRAG_PX:.0f} px look drag turned the view {result['two_turn_rad']:.3f} rad")
    if result["two_turn_rad"] < expected / MAX_TURN_RATIO:
        wrong.append(f"two thumbs: the look drag turned the view only {result['two_turn_rad']:.3f} rad")
    if result["two_biggest_frame_turn_rad"] > MAX_FRAME_TURN_RAD:
        wrong.append(f"two thumbs: one frame turned the view {result['two_biggest_frame_turn_rad']:.3f} rad")
    # Aiming slows the look by the camera's own ADS scale once the aim has eased in (the drag waits for that).
    aimed = expected * ADS_LOOK_SCALE
    if abs(result["aim_turn_rad"] - aimed) > aimed * AIM_TOLERANCE:
        wrong.append(
            f"a drag from the Aim button turned the view {result['aim_turn_rad']:.3f} rad, "
            f"the design says {aimed:.3f} ({expected:.3f} x the ADS scale {ADS_LOOK_SCALE})"
        )
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument(
        "--after-keyboard",
        action="store_true",
        help="type on Play together's keypad and keyboard first (#1183), then start the night",
    )
    args = parser.parse_args()
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    try:
        result = run(url, args.out, args.after_keyboard)
    finally:
        if server:
            server.shutdown()
    wrong = verdict(result)
    result["wrong"] = wrong
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    for line in wrong:
        print("FAILED:", line)
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
