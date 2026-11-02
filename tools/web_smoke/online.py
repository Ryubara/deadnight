"""Joins a game server from the web build, the way a player does, and reports what the page saw.

Opens the deployed (or a served) web build in headless Chromium, goes to Join on the main menu, types the server's
address, presses Join, and then plays the night for a while (walking a square, firing). Every second it reads the game's
probe (`window.deadnight`, game/core/web_probe.gd): the players in the frame, the zombies alive, the round, and the
round trip the page measures to the server. A second player (a headless desktop client with `--bot`, or another page)
shows as `players` 2 or more.

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/online.py \\
        https://web-production-f401d1.up.railway.app wss://deadnight-server-production.up.railway.app build/online

Writes `result.json`, `console.txt` and screenshots (`join.png`, `night.png`, `night_<n>.png`) into the folder.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

sys.path.insert(0, str(Path(__file__).parent))
import smoke

# Joining builds the lot and warms it up behind the loading screen (docs/research/first-use-hitches.md): slow with a
# software renderer.
JOIN_TIMEOUT_S = 400
SHOT_EVERY_S = 20


# The whole object the game publishes, so a new field (the players, the round trip) needs no change here.
WHOLE_PROBE_JS = "() => window.deadnight ? Object.assign({}, window.deadnight) : null"


def read_probe(page: Page) -> dict:
    return page.evaluate(WHOLE_PROBE_JS) or {}


def probe_after(page: Page, seconds: float, what: str, test) -> dict:
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = read_probe(page)
        if test(seen):
            return seen
        time.sleep(0.2)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def open_address(page: Page) -> None:
    """Menu, Play together, its developer button for the server address: the join screen (the page is opened with
    `?dev`). Shared with `startup_check.py`, which fails when the menu or that screen changes under it."""
    smoke.open_together(page)
    # The server address is the last control of the Play together screen: Quick join, Create a night, the code field,
    # Join, Back, then the address button.
    for _ in range(5):
        smoke.press(page, "ArrowDown")
    smoke.press(page, "Enter")
    smoke.wait_for(page, "the join screen", lambda s: s.get("screen") == "join_screen", smoke.SCREEN_TIMEOUT_S)
    page.wait_for_timeout(2000)


def join(page: Page, server: str, out: Path) -> None:
    """Menu, Play together, its developer button for the server address, then the address and Enter."""
    smoke.reach_menu(page)
    open_address(page)
    # The address field has the focus with its text selected: typing replaces it.
    page.keyboard.type(server, delay=40)
    page.wait_for_timeout(500)
    page.screenshot(path=out / "join.png")
    smoke.press(page, "Enter")


def play(page: Page, out: Path, seconds: float, result: dict) -> None:
    page.mouse.move(640, 360)
    page.mouse.down()
    began = time.monotonic()
    walking = ""
    next_shot = SHOT_EVERY_S
    shots = 0
    samples: list[dict] = []
    while time.monotonic() - began < seconds:
        elapsed = time.monotonic() - began
        key = smoke.WALK_KEYS[int(elapsed / smoke.WALK_LEG_S) % len(smoke.WALK_KEYS)]
        if key != walking:
            if walking:
                page.keyboard.up(walking)
            page.keyboard.down(key)
            walking = key
        samples.append({"t": round(elapsed, 1), **read_probe(page)})
        if elapsed >= next_shot:
            shots += 1
            next_shot += SHOT_EVERY_S
            page.screenshot(path=out / f"night_{shots}.png")
        page.wait_for_timeout(1000)
    page.mouse.up()
    if walking:
        page.keyboard.up(walking)
    page.screenshot(path=out / "night_end.png")
    result["samples"] = samples
    rtts = [s["rtt_ms"] for s in samples if s.get("rtt_ms", -1) >= 0]
    result["rtt_ms"] = (
        {
            "n": len(rtts),
            "mean": round(statistics.fmean(rtts), 1),
            "p95": round(sorted(rtts)[int(len(rtts) * 0.95)], 1),
            "max": max(rtts),
        }
        if rtts
        else {}
    )
    result["max_players_seen"] = max((s.get("players", 0) for s in samples), default=0)
    result["max_zombies_seen"] = max((s.get("alive", 0) for s in samples), default=0)
    result["rounds_seen"] = sorted({s.get("round", 0) for s in samples})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="URL of the web build, or a folder with the export (served locally)")
    parser.add_argument("server", help="the game server, as a player types it (wss://host)")
    parser.add_argument("out", type=Path)
    parser.add_argument("--seconds", type=float, default=60.0, help="how long to play once joined")
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU, not a software renderer")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"server": args.server}

    def on_console(message: ConsoleMessage) -> None:
        console.append(f"[{message.type}] {message.text}")
        if message.type == "error":
            problems.append(console[-1])

    local = None
    url = args.web
    if not args.web.startswith(("http://", "https://")):
        local, port = smoke.serve(Path(args.web))
        url = f"http://127.0.0.1:{port}/index.html"
    # `?dev` shows the server address button of the Play together screen on the web.
    url += ("&" if "?" in url else "?") + "dev"
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True)
        else:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        page = browser.new_page(viewport=smoke.VIEWPORT)
        page.on("console", on_console)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        try:
            started = time.monotonic()
            page.goto(url, wait_until="commit")
            join(page, args.server, args.out)
            joined = probe_after(
                page, JOIN_TIMEOUT_S, "a running online night", lambda s: bool(s.get("night") and s.get("running"))
            )
            result["join_to_running_s"] = round(time.monotonic() - started, 1)
            result["joined_as"] = joined.get("player_id")
            page.wait_for_timeout(1500)
            page.screenshot(path=args.out / "night.png")
            play(page, args.out, args.seconds, result)
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=args.out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            browser.close()
            if local:
                local.shutdown()
    (args.out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    summary = {k: v for k, v in result.items() if k != "samples"}
    print(json.dumps(summary, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
