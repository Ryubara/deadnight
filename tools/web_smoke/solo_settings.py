"""Solo offers the match settings a room host sets (#620), in the web build, in headless Chromium.

Two runs, each from a fresh page: a desktop window (1280 x 720, the keyboard) and a phone held sideways (844 x 390,
mobile emulation, a finger sent as `Input.dispatchTouchEvent`). Each presses Solo on the menu's Play tab and expects
the Play screen (the same panel the room host's lobby has), moves the settings (3x, a cap, a break and 3 bots), starts
the night and reads the rules the running night holds: they must be the ones the panel showed (`window.deadnight.play_rules`
against `night_rules`), and the night must have seated the 3 bots (`bots`, `players`: 4 in the frame). A build before the change goes straight into the night; `--expect-none` accepts that and only
takes the screenshots (the "before" half of the pull request's captures).

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/solo_settings.py build/web build/solo-settings [--label after] [--expect-none]

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
USUAL = "1x|Auto|5 s"
# The browser refuses a pointer lock that is not asked for inside a click or key press; the game goes on.
IGNORED = ("A user gesture is required to request Pointer Lock",)


def full(page: Page) -> dict:
    """Everything the game publishes (`smoke.probe` keeps the few fields the other probes read)."""
    return page.evaluate("() => ({ ...window.deadnight })") or {}


def spot(state: dict, name: str, size: dict) -> tuple[float, float]:
    """Where the button or control `name` is on the Play tab or the Play screen, in CSS pixels of the window."""
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


def desktop_run(page: Page, out: Path, label: str, result: dict) -> None:
    smoke.menu_item(page, "Play", 2)
    smoke.press(page, "Enter")
    result["screen_after_solo"] = after_solo(page)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / f"{label}-desktop-solo.png")
    if result["screen_after_solo"] != "play_screen":
        return
    result["play_rules_at_open"] = full(page).get("play_rules")
    # Start has the focus. Each setting's control is found by its name (`window.deadnight.focus`), never by counting
    # presses, so a control added to the screen leaves this walk as it is (#743).
    # The walk goes up from Start: Down from the break slider lands on the skill selector beside the bot count, which
    # only Up from the skill reaches.
    smoke.focus_control(page, "bots", "ArrowUp")
    smoke.step_value(page, "bots", "ArrowRight", 3)  # 0 -> 3 bots
    smoke.focus_control(page, "break_seconds", "ArrowUp")
    smoke.step_value(page, "break_seconds", "ArrowRight", 4)  # a break set
    smoke.focus_control(page, "max_alive", "ArrowUp")
    smoke.step_value(page, "max_alive", "ArrowRight", 8)  # a cap of 8
    smoke.focus_control(page, "count_multiplier", "ArrowUp")
    smoke.step_value(page, "count_multiplier", "ArrowRight", 2)  # 1x -> 3x
    page.wait_for_timeout(600)
    result["play_rules"] = full(page).get("play_rules")
    page.screenshot(path=out / f"{label}-desktop-solo-3x.png")
    smoke.focus_control(page, "Start", "ArrowDown")
    smoke.press(page, "Enter")
    smoke.wait_for_night(page)
    result["night_rules"] = full(page).get("night_rules")
    page.wait_for_timeout(2500)
    result["night_bots"] = full(page).get("bots")
    result["night_players"] = full(page).get("players")
    page.screenshot(path=out / f"{label}-desktop-night.png")


def touch_run(page: Page, client: CDPSession, out: Path, label: str, result: dict) -> None:
    if "spots" in full(page):
        tap(client, spot(full(page), "Solo", PHONE))
    else:  # a build from before the probe published the taps' places (a "before" run): the menu's keys
        smoke.menu_item(page, "Play", 2)
        smoke.press(page, "Enter")
    result["screen_after_solo"] = after_solo(page)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / f"{label}-touch-solo.png")
    if result["screen_after_solo"] != "play_screen":
        return
    state = full(page)
    result["play_rules_at_open"] = state.get("play_rules")
    for _ in range(2):
        tap(client, spot(state, "count_multiplier:end", PHONE))  # the selector's arrow: 1x -> 2x -> 3x
        page.wait_for_timeout(300)
    tap(client, spot(state, "max_alive", PHONE))  # the middle of the cap's slider
    page.wait_for_timeout(300)
    tap(client, spot(state, "break_seconds", PHONE))
    page.wait_for_timeout(300)
    for _ in range(3):
        tap(client, spot(state, "bots:end", PHONE))  # 0 -> 3 bots
        page.wait_for_timeout(300)
    page.wait_for_timeout(300)
    result["play_rules"] = full(page).get("play_rules")
    page.screenshot(path=out / f"{label}-touch-solo-3x.png")
    tap(client, spot(full(page), "Start the night", PHONE))
    smoke.wait_for_night(page)
    result["night_rules"] = full(page).get("night_rules")
    page.wait_for_timeout(2500)
    result["night_bots"] = full(page).get("bots")
    result["night_players"] = full(page).get("players")
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
        page.goto(url + ("?touch=1" if phone else ""), wait_until="commit")
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
    offered = result.get("screen_after_solo") == "play_screen"
    if expect_none:
        return [] if not offered else [f"[{device}] Solo opened the Play screen, a build without it was expected"]
    if not offered:
        return [f"[{device}] Solo opened {result.get('screen_after_solo')!r}, not the Play screen"]
    wrong = []
    if result.get("play_rules_at_open") != USUAL:
        wrong.append(f"[{device}] the Play screen opened on {result.get('play_rules_at_open')!r}, not {USUAL!r}")
    if not str(result.get("play_rules", "")).startswith("3x|") or result.get("play_rules") == USUAL:
        wrong.append(f"[{device}] the settings did not move: {result.get('play_rules')!r}")
    if not str(result.get("play_rules", "")).endswith("|3 bots"):
        wrong.append(f"[{device}] the Bots row did not reach 3: {result.get('play_rules')!r}")
    if result.get("night_bots") != 3 or result.get("night_players") != 4:
        wrong.append(
            f"[{device}] the night seated {result.get('night_bots')!r} bots in {result.get('night_players')!r} players, not 3 in 4"
        )
    if result.get("night_rules") != result.get("play_rules"):
        wrong.append(
            f"[{device}] the night runs {result.get('night_rules')!r}, the panel showed {result.get('play_rules')!r}"
        )
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("build", help="folder with the web export, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--label", default="after")
    parser.add_argument("--expect-none", action="store_true", help="the build has no Play screen (a 'before' run)")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
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
