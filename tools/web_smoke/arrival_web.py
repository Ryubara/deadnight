"""The helicopter drop of a player's arrival in the web build (#1057): it plays on the page that asked for it, the HUD
gives way to it, the night's draw calls are counted through the show and after it, a press skips it, and nothing
the page logs is an error.

A page that asks for the probes skips the show (the probes drive the night from its first frame), so this page asks for it
with `?arrival`. It plays Solo from the menu, on the drive-in lot or (`--map small_indoor`) the second map, and
watches `window.deadnight.arriving` (game/core/web_probe.gd):

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/arrival_web.py build/web build/arrival \\
        [--map small_indoor] [--gpu] [--skip] [--size 844x390]
        [--late --godot <the pinned Godot>] [--unasked] [--video]

It saves a screenshot every second of the show (and one after), counts the WebGL calls in each page frame during the
show and during the same number of seconds of the night after it (`smoke.trace`), and writes `result.json`. With
`--skip` it presses a key two seconds in and checks the show ended at once. With `--late` it starts a game server of
this machine (headless) and a bot client that plays the night, and joins from the Join screen once the night is a round
in, so the page is a late joiner (the show is `late_seconds` long and has no fly-in). Exits 1 on a console error, a show that
never began or never ended, or a HUD that did not give way.
"""

from __future__ import annotations

import argparse
import json
import socket
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import online
import smoke

GAME = Path(__file__).resolve().parents[2] / "game"
# Seconds the bot has to be in the night before the page joins: the intro break (12 s) and a moment into round 1.
BOT_HEAD_START_S = 30

LOT = "drive_in"
SECOND = "small_indoor"
SHOW_TIMEOUT_S = 20
# The show is shorter than this opening a night (`ArrivalTuning.night_seconds` is 6.5): a page that is still showing
# it after this has not left it.
SHOW_LONGEST_S = 12.0
# Messages a page logs that are not the game's.
IGNORED = ("A user gesture is required to request Pointer Lock",)


def parse_size(text: str) -> dict:
    width, height = text.lower().split("x")
    return {"width": int(width), "height": int(height)}


def arriving(page) -> bool:
    return bool(page.evaluate("() => window.deadnight ? window.deadnight.arriving : false"))


def pick_second_map(page) -> None:
    """On the Play screen: the second map's card (found by its name), then back to Start."""
    smoke.focus_control(page, LOT, "ArrowUp")
    smoke.focus_control(page, SECOND, "ArrowDown", tries=1)
    smoke.press(page, "Enter")
    page.wait_for_timeout(400)
    smoke.focus_control(page, "Start", "ArrowDown")


def start(page, second_map: bool) -> None:
    smoke.menu_item(page, "Play", 2)
    smoke.press(page, "Enter")
    smoke.wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", smoke.SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    if second_map:
        pick_second_map(page)
    smoke.press(page, "Enter")


def start_server(args: argparse.Namespace, out: Path) -> tuple[list[subprocess.Popen], str]:
    """A game server and a bot client, both headless, on a port the OS gave: their processes (to stop) and the address."""
    with socket.socket() as probe_socket:
        probe_socket.bind(("127.0.0.1", 0))
        port = probe_socket.getsockname()[1]
    address = f"ws://127.0.0.1:{port}"
    base = [args.godot, "--headless", "--path", str(GAME), "--"]
    server = subprocess.Popen(
        [*base, "--server", "--port", str(port)], stdout=(out / "server.log").open("w"), stderr=subprocess.STDOUT
    )
    time.sleep(8)
    bot = subprocess.Popen(
        [*base, "--connect", address, "--bot"], stdout=(out / "bot.log").open("w"), stderr=subprocess.STDOUT
    )
    time.sleep(BOT_HEAD_START_S)
    return [bot, server], address


def run(args: argparse.Namespace, url: str, out: Path) -> dict:
    """Plays the page; the server and the bot of `--late` are stopped whatever happens."""
    processes: list[subprocess.Popen] = []
    address = ""
    try:
        if args.late:
            processes, address = start_server(args, out)
        return play(args, url, out, address)
    finally:
        for process in processes:
            process.terminate()


def play(args: argparse.Namespace, url: str, out: Path, address: str) -> dict:
    result: dict = {"map": args.map, "size": args.size, "late": args.late}
    errors: list[str] = []
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
        else:
            browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
        page = browser.new_page(
            viewport=parse_size(args.size), record_video_dir=str(out / "video") if args.video else None
        )
        page.on(
            "console",
            lambda m: errors.append(m.text) if m.type == "error" and not any(i in m.text for i in IGNORED) else None,
        )
        page.on("pageerror", lambda e: errors.append(str(e)))
        if args.late:
            page.goto(f"{url}?arrival&dev", wait_until="commit")
            online.join(page, address, out)
        else:
            page.goto(url if args.unasked else f"{url}?arrival", wait_until="commit")
            smoke.reach_menu(page)
            start(page, args.map == SECOND)
        began = time.monotonic()
        # The show begins before the night is "running" for a probe's eye: wait for either.
        smoke.wait_for(
            page,
            "the show or a running night",
            lambda s: bool(s.get("night") and s.get("running")),
            smoke.NIGHT_LOAD_TIMEOUT_S,
        )
        result["load_s"] = round(time.monotonic() - began, 1)
        result["arriving_when_running"] = arriving(page)
        result["arrival_seconds"] = page.evaluate("() => window.deadnight.arrival_seconds")
        if not result["arriving_when_running"]:
            browser.close()
            result["skipped_on_a_probe_page"] = args.unasked
            result["errors"] = errors
            return result
        shot = 0
        shown_since = time.monotonic()
        result["hud_hidden"] = not page.evaluate("() => window.deadnight.hud_visible")
        result["map_in_night"] = page.evaluate("() => window.deadnight.night_map")
        trace = None
        skipped_at = None
        while arriving(page) and time.monotonic() - shown_since < SHOW_LONGEST_S:
            page.screenshot(path=out / f"show_{shot:02d}.png")
            shot += 1
            if trace is None:
                # Three seconds of the show's page frames, counted.
                trace = smoke.trace(page, 3.0)
            if args.skip and skipped_at is None and time.monotonic() - shown_since > 2.0:
                smoke.press(page, "Space")
                skipped_at = time.monotonic()
            page.wait_for_timeout(700)
        result["show_s"] = round(time.monotonic() - shown_since, 1)
        result["still_arriving"] = arriving(page)
        if skipped_at is not None:
            result["skip_to_end_s"] = round(time.monotonic() - skipped_at, 1)
        result["screenshots"] = shot
        result["trace_show"] = trace
        page.wait_for_timeout(1500)
        page.screenshot(path=out / "after.png")
        result["hud_back"] = bool(page.evaluate("() => window.deadnight.hud_visible"))
        result["trace_after"] = smoke.trace(page, 3.0)
        result["gl"] = smoke.gl_info(page)
        browser.close()
    result["errors"] = errors
    return result


def verdict(result: dict) -> list[str]:
    problems = []
    if result.get("skipped_on_a_probe_page"):
        # `--unasked`: a page that asks for the probes and not for the show must not play it.
        return [f"console error: {e}" for e in result.get("errors", [])]
    if not result.get("arriving_when_running"):
        problems.append("the show never began")
    if result.get("still_arriving"):
        problems.append("the show did not end")
    if result.get("late") and result.get("arrival_seconds", 0) > 5.0:
        problems.append("a late join played the night's opening show")
    if not result.get("hud_hidden"):
        problems.append("the HUD did not give way to the show")
    if not result.get("hud_back"):
        problems.append("the HUD did not come back")
    problems += [f"console error: {e}" for e in result.get("errors", [])]
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported build folder")
    parser.add_argument("out", help="where the report and screenshots go")
    parser.add_argument("--map", default=LOT, choices=[LOT, SECOND])
    parser.add_argument("--gpu", action="store_true", help="this machine's Chrome and GPU instead of SwiftShader")
    parser.add_argument("--skip", action="store_true", help="press a key two seconds in")
    parser.add_argument("--size", default="1280x720")
    parser.add_argument("--video", action="store_true", help="record the page to <out>/video (webm)")
    parser.add_argument("--unasked", action="store_true", help="no ?arrival: the probe page must not play the show")
    parser.add_argument("--late", action="store_true", help="join a night a bot is already playing")
    parser.add_argument("--godot", default="", help="the pinned Godot, for --late's server and bot")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    server, port = smoke.serve(Path(args.build))
    try:
        result = run(args, f"http://127.0.0.1:{port}/", out)
    finally:
        server.shutdown()
    problems = verdict(result)
    result["problems"] = problems
    (out / "result.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("trace_show", "trace_after")}, indent=1))
    for key in ("trace_show", "trace_after"):
        calls = (result.get(key) or {}).get("gl_calls_per_frame", {})
        print(key, json.dumps(calls))
    for problem in problems:
        print("FAIL", problem)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
