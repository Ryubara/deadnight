"""A host's lobby settings reach the night, from the web build, in headless Chromium (Deadnight #944).

One page makes a night of its own (Play together, Create a night), so the page is the host of a lobby. On the lobby
screen it picks the second map, three bots of the veteran skill and 3x intensity by clicking the panel's own controls,
waits for the change to reach the backend, presses Start the night and reads what the running night says: the map the
world was built on, the rules the server runs and the bots seated. A setting lost anywhere between the panel and the
night fails the run, naming it.

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/lobby_settings.py <web build folder | deployed web URL> <out folder> [--label before]

A folder is served on this machine and the page uses the backend of its own default (`?backend=<address>` with
`--backend`). A URL is a deployed build: with the live backend it plays against the live game server, and the night it
makes is left when the page closes. Writes `<label>-result.json`, `<label>-lobby.png` and `<label>-night.png`; exits 1
when a setting did not reach the night.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

IGNORED = ("A user gesture is required to request Pointer Lock",)
SECOND_MAP = "small_indoor"
WANTED_RULES = "3x|Auto|"  # the intensity, the cap and the break start the text; the bots follow
WANTED_BOTS = 3


def full(page) -> dict:
    """Everything the game publishes (`smoke.probe` keeps a subset)."""
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : null") or {}


def wait_for(page, what: str, test, seconds: float) -> dict:
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = full(page)
        if test(seen):
            return seen
        time.sleep(0.25)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def spot(state: dict, name: str) -> tuple[float, float]:
    for entry in str(state.get("spots", "")).split("|"):
        key, _, at = entry.rpartition(":")
        if key == name:
            x, _, y = at.partition(",")
            return float(x) * smoke.VIEWPORT["width"], float(y) * smoke.VIEWPORT["height"]
    raise RuntimeError(f"no {name!r} on screen: {state.get('spots')!r}")


def click_spot(page, name: str, times: int = 1) -> None:
    for _ in range(times):
        x, y = spot(full(page), name)
        page.mouse.click(x, y)
        page.wait_for_timeout(400)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("build", help="folder with the web export, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--label", default="after")
    parser.add_argument(
        "--port", type=int, default=0, help="the port a folder is served on (a backend allows its origin)"
    )
    parser.add_argument("--backend", default="", help="the backend address the page uses instead of its default")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    if deployed:
        server, port = None, 0
    elif args.port:
        handler = functools.partial(smoke.Quiet, directory=str(Path(args.build)))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = args.port
    else:
        server, port = smoke.serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    if args.backend:
        url += ("&" if "?" in url else "?") + f"backend={args.backend}"
    problems: list[str] = []
    result: dict = {"url": url, "label": args.label}
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
            page = browser.new_context(viewport=smoke.VIEWPORT).new_page()
            page.on(
                "pageerror",
                lambda e: None if any(t in str(e) for t in IGNORED) else problems.append(f"[pageerror] {e}"),
            )
            page.goto(url, wait_until="commit")
            smoke.reach_menu(page)
            smoke.open_together(page)
            smoke.press(page, "ArrowDown")  # Quick join -> Create a night
            smoke.press(page, "Enter")
            smoke.give_name(page, "Ann")
            wait_for(
                page,
                "the lobby",
                lambda s: s.get("screen") == "lobby_screen" and bool(s.get("room_code")),
                60,
            )
            page.wait_for_timeout(1500)
            result["rules_at_open"] = full(page).get("lobby_rules")
            result["map_at_open"] = full(page).get("lobby_map")

            # The host sets the night: the second map, 3x, three bots and the veteran skill.
            click_spot(page, f"map_{SECOND_MAP}")
            click_spot(page, "count_multiplier:end", 2)
            click_spot(page, "bots:end", WANTED_BOTS)
            click_spot(page, "bot_skill:end")  # regular -> veteran (the selector wraps, so one press)
            panel = wait_for(
                page,
                "the panel to show the choices",
                lambda s: (
                    str(s.get("lobby_rules", "")).startswith(WANTED_RULES)
                    and str(s.get("lobby_rules", "")).endswith(f"|{WANTED_BOTS} bots|veteran")
                    and s.get("lobby_map") == SECOND_MAP
                ),
                20,
            )
            result["rules_on_panel"], result["map_on_panel"] = panel.get("lobby_rules"), panel.get("lobby_map")
            # Long enough for the change to be sent while the lobby waits (the panel sends once the host pauses).
            page.wait_for_timeout(2500)
            result["note_after_change"] = full(page).get("lobby_note", "")
            page.screenshot(path=args.out / f"{args.label}-lobby.png")

            page.mouse.click(*spot(full(page), "Start the night"))
            wait_for(
                page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
            )
            page.wait_for_timeout(3000)
            night = full(page)
            result["night_rules"] = night.get("night_rules")
            result["night_map"] = night.get("night_map")
            result["night_bots"] = night.get("bots")
            page.screenshot(path=args.out / f"{args.label}-night.png")
            browser.close()
    except (TimeoutError, PlaywrightError, RuntimeError) as error:  # report, do not hide behind a stack
        problems.append(f"{type(error).__name__}: {error}")
    finally:
        if server:
            server.shutdown()
    # What the night says, setting by setting.
    if result.get("night_map") != SECOND_MAP:
        problems.append(f"the night is on {result.get('night_map')!r}, the host picked {SECOND_MAP!r}")
    rules = str(result.get("night_rules", ""))
    if not rules.startswith(WANTED_RULES):
        problems.append(f"the night runs {rules!r}, the host picked 3x intensity")
    if f"|{WANTED_BOTS} bots" not in rules:
        problems.append(f"the night runs {rules!r}, the host asked for {WANTED_BOTS} bots")
    if not rules.endswith("|veteran"):
        problems.append(f"the night runs {rules!r}, the host picked the veteran skill")
    if result.get("night_bots") != WANTED_BOTS:
        problems.append(f"{result.get('night_bots')} bots are in the night, the host asked for {WANTED_BOTS}")
    result["problems"] = problems
    (args.out / f"{args.label}-result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
