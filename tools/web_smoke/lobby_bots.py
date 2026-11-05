"""The Bots setting in a room's lobby, from the web build, in headless Chromium (#643).

Starts the platform backend from `spikes/backend` on this machine (memory store, guests only), serves the export, and
opens two pages. Page A creates a night (the lobby, A the host); page B opens the invite link and joins. A clicks the
Bots row's next arrow three times: A's panel and B's read-only panel must both read `3 bots` (B within a poll), and
both lobbies must show the two open seats as bots, never more than the seats the two people leave free.

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/lobby_bots.py build/web build/lobby-bots

The first argument is a folder with the export. Writes `result.json`, `a_lobby_bots.png` and `b_lobby_bots.png`; exits 1
when a check fails. Needs `npm ci` done in `spikes/backend` and node 24.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

BACKEND = Path(__file__).resolve().parents[2] / "spikes" / "backend"
WEB_PORT = 8081
BACKEND_PORT = 3100
IGNORED = ("A user gesture is required to request Pointer Lock",)


def probe(page: Page) -> dict:
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : null") or {}


def wait_for(page: Page, what: str, test, seconds: float) -> dict:
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = probe(page)
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


def start_backend() -> subprocess.Popen:
    env = dict(os.environ)
    env.update(
        DISCORD_MODE="off",
        GUEST_SIGN_IN="1",
        PORT=str(BACKEND_PORT),
        HOST="127.0.0.1",
        LOG_LEVEL="warn",
        CORS_ORIGINS=f"http://127.0.0.1:{WEB_PORT}",
        SESSION_SECRET="s" * 32 + "-session",
        TICKET_SECRET="t" * 32 + "-ticket",
        GAME_SERVER_SECRET="g" * 32 + "-server",
    )
    process = subprocess.Popen(["node", "src/main.ts"], cwd=BACKEND, env=env)
    time.sleep(3)
    return process


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("web", help="folder with the export")
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    result: dict = {}
    backend = start_backend()
    handler = functools.partial(smoke.Quiet, directory=str(Path(args.web)))
    web = http.server.ThreadingHTTPServer(("127.0.0.1", WEB_PORT), handler)
    threading.Thread(target=web.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{WEB_PORT}/index.html?backend=http://127.0.0.1:{BACKEND_PORT}"
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)

            def page_for(url: str) -> Page:
                page = browser.new_context(viewport=smoke.VIEWPORT).new_page()
                page.on(
                    "pageerror",
                    lambda e: None if any(t in str(e) for t in IGNORED) else problems.append(f"[pageerror] {e}"),
                )
                page.goto(url, wait_until="commit")
                return page

            a = page_for(base)
            wait_for(a, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
            a.mouse.click(5, 5)
            a.wait_for_timeout(2500)
            smoke.menu_item(a, "Play")
            smoke.press(a, "Enter")
            wait_for(a, "Play together", lambda s: s.get("screen") == "together_screen", smoke.SCREEN_TIMEOUT_S)
            a.wait_for_timeout(1500)
            smoke.press(a, "ArrowDown")  # Server browser -> Create a night
            smoke.press(a, "Enter")
            smoke.give_name(a, "Ann")
            alone = wait_for(a, "A's lobby", lambda s: s.get("screen") == "lobby_screen" and s.get("room_code"), 60)
            code = alone["room_code"]

            b = page_for(f"{base}&room={code}")
            smoke.give_name(b, "Bo", 240)
            wait_for(b, "B's preview", lambda s: s.get("screen") == "lobby_screen", 240)
            b.mouse.click(5, 5)
            smoke.press(b, "Enter")  # Join
            wait_for(
                a,
                "A sees two people",
                lambda s: sum("(open)" not in x for x in s.get("lobby_seats", "").split("|")) == 2,
                60,
            )

            # A asks for three bots by clicking the next arrow of the Bots row.
            state = probe(a)
            for _ in range(3):
                x, y = spot(state, "bots:end")
                a.mouse.click(x, y)
                a.wait_for_timeout(400)
            a_state = wait_for(
                a, "A's panel at 3 bots", lambda s: str(s.get("lobby_rules", "")).endswith("|3 bots"), 20
            )
            b_state = wait_for(
                b, "B's panel at 3 bots", lambda s: str(s.get("lobby_rules", "")).endswith("|3 bots"), 20
            )
            a.wait_for_timeout(1000)
            a_state, b_state = probe(a), probe(b)
            result["rules_a"], result["rules_b"] = a_state.get("lobby_rules"), b_state.get("lobby_rules")
            result["seats_a"], result["seats_b"] = a_state.get("lobby_seats"), b_state.get("lobby_seats")
            for who, state in (("A", a_state), ("B", b_state)):
                seats = str(state.get("lobby_seats", "")).split("|")
                if sum(seat.endswith("BOT") for seat in seats) != 2:
                    problems.append(f"{who} should see two bot seats (3 asked, 2 people): {seats}")
            a.screenshot(path=args.out / "a_lobby_bots.png")
            b.screenshot(path=args.out / "b_lobby_bots.png")
            browser.close()
    except (TimeoutError, PlaywrightError, RuntimeError) as error:  # report, do not hide behind a stack
        problems.append(f"{type(error).__name__}: {error}")
    finally:
        web.shutdown()
        backend.terminate()
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
