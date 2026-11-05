"""The phone move stick's walk and its sprint latch in a real browser (#1276): real touches on a landscape page.

Opens the exported game (`?touch=1`) in Chrome with mobile emulation at 844 x 390 and at 667 x 375 CSS pixels, starts a
night with the keyboard, and sends what a thumb does through the DevTools protocol:

- no finger on the left: the stick reports nothing down (the capture shows nothing drawn there);
- a drag to the ring's edge: the player walks at `run_speed` and does not sprint, and the phone is not buzzed;
- a drag past the edge by the margin: the player sprints at `sprint_speed`, the phone is buzzed once, and the sprint
  stays on when the finger goes back inside the ring and to its middle, until it lifts (and a full push on any side
  sprints at `sprint_speed`);
- a new press walks; a drag past the edge to the right and on a diagonal sprints as well;
- a second finger that opens the pause menu while the sprint is latched leaves the stick clear afterwards.

The ring and the margin are CSS pixels, so the page's own size is what is measured: the distance in CSS pixels at which
the sprint starts is read at both sizes and must be the same. `navigator.vibrate` is replaced by a counter before the
page loads (a headless Chrome buzzes nothing), which is how the buzz is counted.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_sprint.py build/web build/touch_sprint

The first argument is the exported folder or a URL; the second is where the screenshots and `result.json` go. Exits 1
when any of the above fails.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

VIEWPORTS = {"844x390": {"width": 844, "height": 390}, "667x375": {"width": 667, "height": 375}}
DEVICE_SCALE = 3
LOAD_TIMEOUT_S = 240
STEPS = 12
STEP_PERIOD_S = 0.03
# How long a finger holds after a drag before the speed is read, and how often the page is asked meanwhile.
SETTLE_S = 1.6
POLL_S = 0.2
# The speeds the player is meant to reach (game/gameplay/player/player_tuning.gd): read from the file so they follow it.
_TUNING = (Path(__file__).parents[2] / "game/gameplay/player/player_tuning.gd").read_text(encoding="utf-8")
RUN_SPEED = float(re.search(r"var run_speed := ([0-9.]+)", _TUNING).group(1))
SPRINT_SPEED = float(re.search(r"var sprint_speed := ([0-9.]+)", _TUNING).group(1))
SPEED_TOLERANCE = 0.04
FINGER = 1

VIBRATE_JS = """
() => {
  window.__buzz = [];
  navigator.vibrate = function (pattern) { window.__buzz.push([performance.now(), pattern]); return true; };
}
"""
NO_POINTER_LOCK_JS = """
() => { Element.prototype.requestPointerLock = function () {}; }
"""


def touch(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    client.send(
        "Input.dispatchTouchEvent",
        {"type": kind, "touchPoints": [{"id": i, "x": x, "y": y} for i, x, y in points]},
    )


class Thumb:
    """One finger on the stick, at CSS pixels."""

    def __init__(
        self, client: CDPSession, origin: tuple[float, float], also: list[tuple[int, float, float]] | None = None
    ):
        self.client = client
        self.home = origin
        self.origin = origin
        self.at = origin
        self.also = also or []

    def points(self) -> list[tuple[int, float, float]]:
        return [(FINGER, *self.at), *self.also]

    def rebase(self, dx: float, dy: float) -> None:
        """The ring followed the finger by (dx, dy): moves are measured from the ring now."""
        self.origin = (self.origin[0] + dx, self.origin[1] + dy)

    def down(self) -> None:
        self.origin = self.home
        self.at = self.home
        touch(self.client, "touchStart", self.points())
        time.sleep(STEP_PERIOD_S)

    def to(self, dx: float, dy: float) -> None:
        """Moves to `origin + (dx, dy)` in even steps."""
        start = self.at
        end = (self.origin[0] + dx, self.origin[1] + dy)
        for step in range(1, STEPS + 1):
            self.at = (start[0] + (end[0] - start[0]) * step / STEPS, start[1] + (end[1] - start[1]) * step / STEPS)
            touch(self.client, "touchMove", self.points())
            time.sleep(STEP_PERIOD_S)

    def up(self) -> None:
        touch(self.client, "touchEnd", [])
        time.sleep(0.3)


def read(page: Page) -> dict:
    """Everything the game publishes as `window.deadnight` (`smoke.probe` keeps only a few keys)."""
    return page.evaluate("() => { const d = window.deadnight; return d ? Object.assign({}, d) : {}; }") or {}


def stick(page: Page) -> dict:
    """What the game says of the stick: `down,sprint,vx,vy,radius,margin` (canvas units) and the player's speed."""
    state = read(page)
    parts = str(state.get("touch_stick", "")).split(",")
    out = {"speed": float(state.get("ground_speed", 0.0)), "sprinting": bool(state.get("sprinting"))}
    if len(parts) == 6:
        out |= {
            "down": parts[0] == "1",
            "latched": parts[1] == "1",
            "vx": float(parts[2]),
            "vy": float(parts[3]),
            "radius_units": float(parts[4]),
            "margin_units": float(parts[5]),
        }
    return out | {"paused": bool(state.get("paused")), "layout": state.get("layout", "")}


def css_per_unit(layout: str) -> float:
    return float(layout.split("|")[4])


def hold(page: Page, seconds: float = SETTLE_S) -> dict:
    """Waits with the finger still, asking the page; the fastest speed seen, and the last answer."""
    fastest = 0.0
    last: dict = {}
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        time.sleep(POLL_S)
        last = stick(page)
        fastest = max(fastest, last["speed"])
    return last | {"peak_speed": fastest}


def buzzes(page: Page) -> int:
    return len(page.evaluate("window.__buzz"))


def pause_spot(page: Page, size: dict) -> tuple[float, float]:
    """The Pause button's centre in CSS pixels, from the hit areas the game reports."""
    for entry in str(read(page).get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name == "pause":
            x, y = (float(n) for n in numbers.split(",")[:2])
            return x * size["width"], y * size["height"]
    raise RuntimeError("the game reported no Pause button")


def start_night(page: Page) -> None:
    smoke.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    smoke.start_solo(page)
    smoke.wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), 240)
    smoke.wait_for(page, "the arrival over", lambda s: not read(page).get("arriving", False), 120)
    page.wait_for_timeout(2500)


def run_size(url: str, label: str, size: dict, out: Path) -> dict:
    problems: list[str] = []
    result: dict = {"viewport": size, "problems": problems}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(viewport=size, device_scale_factor=DEVICE_SCALE, has_touch=True, is_mobile=True)
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.on("console", lambda m: problems.append(f"console {m.type}: {m.text}") if m.type == "error" else None)
        page.add_init_script("(" + VIBRATE_JS.strip() + ")();")
        page.add_init_script("(" + NO_POINTER_LOCK_JS.strip() + ")();")
        page.goto(f"{url}?touch=1", wait_until="commit")
        start_night(page)
        client = context.new_cdp_session(page)

        def shot(name: str) -> None:
            page.screenshot(path=str(out / f"{label}_{name}.png"))

        origin = (size["width"] * 0.13, size["height"] * 0.74)
        state = stick(page)
        per_unit = css_per_unit(state["layout"])
        result["css_per_unit"] = per_unit
        result["layout"] = state["layout"]
        result["rest"] = state
        shot("1_nothing_drawn")

        thumb = Thumb(client, origin)
        thumb.down()
        state = stick(page)
        radius_px = state["radius_units"] * per_unit
        margin_px = state["margin_units"] * per_unit
        result["radius_css_px"] = radius_px
        result["margin_css_px"] = margin_px
        result["sprint_edge_css_px"] = radius_px + margin_px
        shot("2_finger_down")

        # The ring's edge: a full walk.
        thumb.to(0.0, -radius_px)
        result["edge"] = hold(page, 1.0)
        result["edge"]["buzzes"] = buzzes(page)
        shot("3_walk_at_the_edge")
        # Past the ring but inside the margin: still a walk at full speed, no buzz.
        thumb.to(0.0, -(radius_px + margin_px - 3.0))
        result["inside_margin"] = hold(page, 0.3)
        result["inside_margin"]["buzzes"] = buzzes(page)
        # Past the margin: the sprint, one buzz. The ring follows the finger from here.
        thumb.to(0.0, -(radius_px + margin_px + 3.0))
        result["past_edge"] = hold(page, 0.4)
        result["past_edge"]["buzzes"] = buzzes(page)
        shot("4_sprint_past_the_edge")
        thumb.rebase(0.0, -(margin_px + 3.0))
        # Back inside the (moved) ring, to its middle, and out the other way: the latch holds.
        thumb.to(0.0, -radius_px * 0.7)
        result["back_inside"] = hold(page, 0.4)
        result["back_inside"]["buzzes"] = buzzes(page)
        shot("5_back_inside_still_sprinting")
        thumb.to(0.0, 0.0)
        result["at_middle"] = hold(page, 0.4)
        thumb.to(0.0, radius_px * 0.7)
        result["again"] = hold(page, 1.0)
        result["again"]["buzzes"] = buzzes(page)
        thumb.up()
        result["lifted"] = hold(page, 0.6)
        result["lifted"]["buzzes"] = buzzes(page)
        shot("6_lifted")

        # A new press walks, even to the edge.
        thumb.down()
        thumb.to(0.0, radius_px)
        result["second_press"] = hold(page, 0.8)
        result["second_press"]["buzzes"] = buzzes(page)
        thumb.up()

        # Every side of the edge sprints; one buzz each.
        sides = {"right": (1.0, 0.0), "down": (0.0, 1.0), "up_right": (0.7071, -0.7071)}
        result["sides"] = {}
        for name, (ux, uy) in sides.items():
            before = buzzes(page)
            thumb.down()
            reach = radius_px + margin_px + 4.0
            thumb.to(ux * reach, uy * reach)
            seen = hold(page, 0.6)
            seen["buzzes_made"] = buzzes(page) - before
            thumb.up()
            result["sides"][name] = seen

        # Sideways at the edge itself walks.
        thumb.down()
        thumb.to(radius_px, 0.0)
        result["sideways_edge"] = hold(page, 0.6)
        thumb.up()

        # A second finger opens the pause menu while the sprint is latched: the layer goes down and lets go.
        thumb.down()
        thumb.to(0.0, -(radius_px + margin_px + 4.0))
        time.sleep(0.4)
        pause = pause_spot(page, size)
        thumb.also = [(2, *pause)]
        touch(client, "touchStart", thumb.points())
        time.sleep(0.15)
        touch(client, "touchMove", [(FINGER, *thumb.at)])
        thumb.also = []
        touch(client, "touchEnd", [])  # both fingers lift
        time.sleep(1.0)
        result["after_pause"] = stick(page)
        shot("7_paused_with_the_sprint_latched")
        page.keyboard.press("Escape")
        page.wait_for_timeout(1200)
        result["resumed"] = stick(page)
        result["resumed"]["paused_now"] = bool(read(page).get("paused"))
        result["resumed"]["buzzes"] = buzzes(page)
        # A press after it walks.
        thumb.down()
        thumb.to(0.0, radius_px)
        result["after_menu_press"] = hold(page, 0.8)
        thumb.up()
        result["buzz_log_total"] = buzzes(page)
        browser.close()
    return result


def near(value: float, wanted: float) -> bool:
    return abs(value - wanted) <= wanted * SPEED_TOLERANCE


def verdict(label: str, r: dict) -> list[str]:
    wrong = [f"{label}: {p}" for p in r["problems"]]

    def need(ok: bool, text: str) -> None:
        if not ok:
            wrong.append(f"{label}: {text}")

    need(not r["rest"].get("down", True), "a stick was down with no finger on it")
    need(abs(r["radius_css_px"] - 40.0) < 0.5, f"the ring is {r['radius_css_px']:.2f} CSS px, wanted 40")
    need(abs(r["margin_css_px"] - 18.0) < 0.5, f"the margin is {r['margin_css_px']:.2f} CSS px, wanted 18")
    edge = r["edge"]
    need(near(edge["peak_speed"], RUN_SPEED), f"the edge walked at {edge['peak_speed']:.2f} m/s, wanted {RUN_SPEED}")
    need(not edge["latched"] and not edge["sprinting"], "a drag to the edge sprinted")
    need(edge["buzzes"] == 0, f"the phone buzzed {edge['buzzes']} times before the sprint")
    inside = r["inside_margin"]
    need(not inside["latched"] and inside["buzzes"] == 0, "a drag inside the margin sprinted")
    past = r["past_edge"]
    need(past["latched"] and past["sprinting"], "a drag past the edge did not sprint")
    need(past["buzzes"] == 1, f"the phone buzzed {past['buzzes']} times at the sprint, wanted 1")
    need(r["back_inside"]["latched"] and r["back_inside"]["sprinting"], "easing back into the ring ended the sprint")
    need(r["at_middle"]["latched"], "the middle of the ring ended the sprint")
    need(r["again"]["latched"] and r["again"]["buzzes"] == 1, "the sprint broke or buzzed again inside the ring")
    # The speed follows the push (the stick is analog): 0.667 of a push at a sprint is clearly faster than that push walking.
    walk_at_push = abs(r["again"]["vy"]) * RUN_SPEED
    need(
        r["again"]["sprinting"] and r["again"]["peak_speed"] > walk_at_push * 1.1,
        f"the latched sprint at a {abs(r['again']['vy']):.2f} push was {r['again']['peak_speed']:.2f} m/s, "
        f"a walk is {walk_at_push:.2f}",
    )
    need(not r["lifted"]["latched"] and not r["lifted"]["sprinting"], "the sprint outlived the finger")
    need(r["second_press"]["buzzes"] == 1 and not r["second_press"]["latched"], "a new press did not start walking")
    for name, seen in r["sides"].items():
        need(seen["latched"] and seen["buzzes_made"] == 1, f"a drag past the edge to the {name} did not sprint once")
        need(near(seen["peak_speed"], SPRINT_SPEED), f"a sprint to the {name} ran {seen['peak_speed']:.2f} m/s")
    need(not r["sideways_edge"]["latched"], "a sideways drag to the edge sprinted")
    need(not r["after_pause"].get("down", True) and not r["after_pause"]["latched"], "the pause left the stick down")
    need(not r["after_menu_press"]["latched"], "a press after the menu started sprinting")
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    wrong: list[str] = []
    results: dict = {"run_speed": RUN_SPEED, "sprint_speed": SPRINT_SPEED}
    try:
        for label, size in VIEWPORTS.items():
            results[label] = run_size(url, label, size, args.out)
            wrong += verdict(label, results[label])
    finally:
        if server:
            server.shutdown()
    if len(VIEWPORTS) == 2:
        first, second = (results[k] for k in VIEWPORTS)
        for key in ("radius_css_px", "sprint_edge_css_px"):
            if abs(first[key] - second[key]) > 0.5:
                wrong.append(f"{key} differs between the two phones: {first[key]:.2f} and {second[key]:.2f}")
    results["wrong"] = wrong
    (args.out / "result.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2))
    for line in wrong:
        print("FAILED:", line)
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
