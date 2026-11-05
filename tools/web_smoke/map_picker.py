"""The map picker (#624) in the web build, in headless Chromium.

Two runs, each from a fresh page: a desktop window (1280 x 720, the keyboard and a mouse) and a phone held sideways
(844 x 390, mobile emulation, a finger sent as `Input.dispatchTouchEvent`). Each presses Solo on the menu's Play tab and
expects the Play screen with the map picker (`window.deadnight.play_map` is the chosen map, `focus` the name of the control
with the keyboard), chooses the second map's card (keyboard, mouse or a finger) and the lot's again, chooses the second
map, starts the night and reads the map the running night was built on (`night_map`: the second map, #792). A build before the change has no picker;
`--expect-none` accepts that and only takes the screenshots (the "before" half of the pull request's captures).

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/map_picker.py build/web build/map-picker [--label after] [--expect-none]

The first argument is a folder with the export (served locally) or the URL of a deployed build. Writes
`<label>-<device>-<step>.png` and `<label>-result.json`; exits 1 when a run fails.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

sys.path.insert(0, str(Path(__file__).parent))
import smoke

DESKTOP = {"width": 1280, "height": 720}
PHONE = {"width": 844, "height": 390}
PHONE_DPR = 3
LOT = "drive_in"
SECOND = "small_indoor"
# The browser refuses a pointer lock that is not asked for inside a click or key press; the game goes on.
IGNORED = ("A user gesture is required to request Pointer Lock",)


def full(page: Page) -> dict:
    """Everything the game publishes (`smoke.probe` keeps the few fields the other probes read)."""
    return page.evaluate("() => ({ ...window.deadnight })") or {}


def spot(state: dict, name: str, size: dict) -> tuple[float, float]:
    """Where the button or control `name` is on the Play screen, in CSS pixels of the window."""
    for entry in str(state.get("spots", "")).split("|"):
        key, _, at = entry.rpartition(":")
        if key == name:
            x, _, y = at.partition(",")
            return float(x) * size["width"], float(y) * size["height"]
    raise RuntimeError(f"no {name!r} on screen (the page has: {state.get('spots')!r})")


def tap(client: CDPSession, at: tuple[float, float]) -> None:
    """A finger down and up at `at`, held long enough for a frame."""
    for kind, points in (("touchStart", [{"id": 1, "x": at[0], "y": at[1]}]), ("touchEnd", [])):
        client.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": points})
        time.sleep(0.15)


def after_solo(page: Page) -> str:
    """Which screen Solo led to: the Play screen, or (a build before the change) the night."""
    state = smoke.wait_for(
        page, "the Play screen or a night", lambda s: s.get("screen") in ("play_screen", "night_screen"), 60
    )
    return str(state["screen"])


def has_picker(state: dict) -> bool:
    return "play_map" in state and any(entry.startswith("map_") for entry in str(state.get("spots", "")).split("|"))


def desktop_run(page: Page, out: Path, label: str, result: dict) -> None:
    smoke.menu_item(page, "Play", 2)
    smoke.press(page, "Enter")
    result["screen_after_solo"] = after_solo(page)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / f"{label}-desktop-solo.png")
    if result["screen_after_solo"] != "play_screen" or not has_picker(full(page)):
        return
    state = full(page)
    result["map_at_open"] = state.get("play_map")
    # Start has the focus: Up walks the settings to the map cards; the lot's card is found by its name (a card is
    # named by its map's id), and Down reaches the second map's card (#743).
    smoke.focus_control(page, LOT, "ArrowUp")
    walked = [smoke.focused_control(page)]
    smoke.focus_control(page, SECOND, "ArrowDown", tries=1)
    walked.append(smoke.focused_control(page))
    result["keyboard_focus"] = walked
    smoke.press(page, "Enter")  # on the second map's card: it is chosen
    page.wait_for_timeout(500)
    result["map_after_second_enter"] = full(page).get("play_map")
    page.screenshot(path=out / f"{label}-desktop-second-card.png")
    # The mouse: a click on the lot's card chooses the lot again, a click on the second map's chooses it.
    page.mouse.click(*spot(full(page), f"map_{LOT}", DESKTOP))
    page.wait_for_timeout(400)
    result["map_after_lot_click"] = full(page).get("play_map")
    page.mouse.click(*spot(full(page), f"map_{SECOND}", DESKTOP))
    page.wait_for_timeout(400)
    result["map_after_second_click"] = full(page).get("play_map")
    page.mouse.click(*spot(full(page), "Start the night", DESKTOP))
    smoke.wait_for_night(page)
    result["night_map"] = full(page).get("night_map")
    page.wait_for_timeout(2500)
    page.screenshot(path=out / f"{label}-desktop-night.png")


def touch_run(page: Page, client: CDPSession, out: Path, label: str, result: dict) -> None:
    if "spots" in full(page):
        tap(client, spot(full(page), "Solo", PHONE))
    else:  # a build from before the probe published the taps' places: the menu's keys
        smoke.menu_item(page, "Play", 2)
        smoke.press(page, "Enter")
    result["screen_after_solo"] = after_solo(page)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / f"{label}-touch-solo.png")
    if result["screen_after_solo"] != "play_screen" or not has_picker(full(page)):
        return
    state = full(page)
    result["map_at_open"] = state.get("play_map")
    tap(client, spot(state, f"map_{SECOND}", PHONE))
    page.wait_for_timeout(500)
    result["map_after_second_tap"] = full(page).get("play_map")
    page.screenshot(path=out / f"{label}-touch-second-card.png")
    tap(client, spot(full(page), f"map_{LOT}", PHONE))
    page.wait_for_timeout(500)
    result["map_after_lot_tap"] = full(page).get("play_map")
    tap(client, spot(full(page), f"map_{SECOND}", PHONE))
    page.wait_for_timeout(500)
    result["map_after_second_retap"] = full(page).get("play_map")
    tap(client, spot(full(page), "Start the night", PHONE))
    smoke.wait_for_night(page)
    result["night_map"] = full(page).get("night_map")
    page.wait_for_timeout(2500)
    page.screenshot(path=out / f"{label}-touch-night.png")


def run_device(url: str, out: Path, label: str, device: str, problems: list[str]) -> dict:
    result: dict = {"device": device}
    phone = device == "touch"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        if phone:
            context = browser.new_context(viewport=PHONE, device_scale_factor=PHONE_DPR, has_touch=True, is_mobile=True)
        else:
            context = browser.new_context(viewport=DESKTOP)
        page = context.new_page()
        smoke.give_level(page, 10)  # the second map is the back rooms, which a fresh player has not opened
        page.on(
            "pageerror",
            lambda e: None if any(t in str(e) for t in IGNORED) else problems.append(f"[{device}] {e}"),
        )
        page.on(
            "console",
            lambda m: (
                problems.append(f"[{device}] {m.text}")
                if m.type == "error" and not any(t in m.text for t in IGNORED)
                else None
            ),
        )
        page.goto(url + ("&touch=1" if phone and "?" in url else "?touch=1" if phone else ""), wait_until="commit")
        smoke.reach_menu(page)
        try:
            if phone:
                touch_run(page, context.new_cdp_session(page), out, label, result)
            else:
                desktop_run(page, out, label, result)
        except (TimeoutError, PlaywrightError, RuntimeError) as error:
            problems.append(f"[{device}] {error}")
            page.screenshot(path=out / f"{label}-{device}-failure.png")
        browser.close()
    return result


def verdict(result: dict, expect_none: bool) -> list[str]:
    device = result["device"]
    offered = "map_at_open" in result
    if expect_none:
        return [] if not offered else [f"[{device}] the Play screen has a map picker, a build without it was expected"]
    if not offered:
        return [f"[{device}] no map picker on the Play screen (it opened {result.get('screen_after_solo')!r})"]
    wrong = []
    if result.get("map_at_open") != LOT:
        wrong.append(f"[{device}] the picker opened on {result.get('map_at_open')!r}, not {LOT!r}")
    for key, want in (
        ("map_after_second_enter", SECOND),
        ("map_after_lot_click", LOT),
        ("map_after_second_click", SECOND),
        ("map_after_second_tap", SECOND),
        ("map_after_lot_tap", LOT),
        ("map_after_second_retap", SECOND),
    ):
        if key in result and result[key] != want:
            wrong.append(f"[{device}] {key} is {result[key]!r}, expected {want!r}")
    walked = result.get("keyboard_focus")
    if walked is not None and (LOT not in walked or walked[-1] != SECOND):
        wrong.append(f"[{device}] the arrows did not walk the cards: focus went {walked!r}")
    if result.get("night_map") != SECOND:
        wrong.append(f"[{device}] the night was built on {result.get('night_map')!r}, not {SECOND!r}")
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("build", help="folder with the web export, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--label", default="after")
    parser.add_argument("--expect-none", action="store_true", help="the build has no map picker (a 'before' run)")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    url = smoke.probing(args.build) if deployed else f"http://127.0.0.1:{port}/index.html"
    problems: list[str] = []
    results = [run_device(url, args.out, args.label, device, problems) for device in ("desktop", "touch")]
    if server:
        server.shutdown()
    for result in results:
        problems += verdict(result, args.expect_none)
    report = json.dumps({"runs": results, "problems": problems}, indent=2)
    (args.out / f"{args.label}-result.json").write_text(report)
    print(report)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
