"""The lobby, from the web build, in headless Chromium: wait, start, and join in the middle of the night.

Page A opens the game, goes to Play together and creates a night: the lobby screen shows a code, A as the host and three
open seats. Page B opens the invite link (`?room=CODE`): it reads *Waiting room* first, presses Join, and both pages show
the two seats within a few seconds; B has no Start. A presses Start: A goes into the night and B's lobby says the night
started, B presses Play and goes in. Page C, which opened the same link at the start and left its preview open, is told by the
screen itself: *Night in progress*; C presses Join and goes straight into the night, and A and B both see three players and the notice "... JOINED". The script reads
the game's probe (`window.deadnight`) on every page and fails on a console error or a seat, line or notice that is not
what the lobby promises.

Run it under the quiet launcher (headless Chromium under pointer lock clips the real cursor, docs/godot/no-focus.md):

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \
        tools/web_smoke/lobby.py build/web https://backend.example build/lobby

The first argument is a folder with the export (served on a fixed local port, which the backend must list in
`CORS_ORIGINS`) or the URL of a deployed build. Writes `result.json`, `console.txt` and screenshots: `a_lobby_alone.png`,
`a_lobby_two.png`, `b_lobby_two.png`, `b_started.png`, `c_preview.png`, `a_night.png`, `b_night.png`, `c_night.png`.
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

from playwright.sync_api import Browser, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

sys.path.insert(0, str(Path(__file__).parent))
import smoke

LOCAL_PORT = 8081
NIGHT_TIMEOUT_S = 400
# The browser refuses a pointer lock that is not asked for inside a click or key press; the game goes on, so this is
# noted, not a failure of the flow under test.
IGNORED = ("A user gesture is required to request Pointer Lock",)


def read_probe(page: Page) -> dict:
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : null") or {}


def wait_for(page: Page, what: str, test, seconds: float) -> dict:
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = read_probe(page)
        if test(seen):
            return seen
        time.sleep(0.25)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def open_page(browser: Browser, url: str, console: list[str], problems: list[str], label: str) -> Page:
    page = browser.new_context(viewport=smoke.VIEWPORT).new_page()
    page.on("console", lambda m: console.append(f"[{label}] [{m.type}] {m.text}"))
    page.on(
        "pageerror",
        lambda e: None if any(text in str(e) for text in IGNORED) else problems.append(f"[{label}] [pageerror] {e}"),
    )
    page.goto(url, wait_until="commit")
    return page


def to_together(page: Page) -> None:
    """From the main menu to the Play together screen (the first item of the Play tab)."""
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)  # gives the canvas the keyboard
    page.wait_for_timeout(2500)
    smoke.menu_item(page, "Play")
    smoke.press(page, "Enter")
    wait_for(page, "the Play together screen", lambda s: s.get("screen") == "together_screen", smoke.SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)


def in_night(state: dict) -> bool:
    return bool(state.get("night") and state.get("running"))


def seats(state: dict) -> list[str]:
    return [seat for seat in state.get("lobby_seats", "").split("|") if seat]


def taken(state: dict) -> int:
    """How many seats of the lobby on screen have someone in them."""
    return sum("(open)" not in seat for seat in seats(state))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's address")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    console: list[str] = []
    problems: list[str] = []
    result: dict = {"backend": args.backend}

    local = None
    base = args.web
    if not args.web.startswith(("http://", "https://")):
        handler = functools.partial(smoke.Quiet, directory=str(Path(args.web)))
        local = http.server.ThreadingHTTPServer(("127.0.0.1", LOCAL_PORT), handler)
        threading.Thread(target=local.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{LOCAL_PORT}/index.html"
    query = f"backend={args.backend}&bot"  # the autopilot plays, so nobody idles and dies while the others load
    pages: dict[str, Page] = {}
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True)
        else:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        try:
            # A creates a night: the lobby, with A as the host and nobody else.
            a = pages["a"] = open_page(browser, f"{base}?{query}", console, problems, "A")
            to_together(a)
            smoke.press(a, "ArrowDown")  # Quick join -> Create a night
            smoke.press(a, "Enter")
            alone = wait_for(
                a, "A's lobby", lambda s: s.get("screen") == "lobby_screen" and s.get("room_code", "") != "", 60
            )
            code = alone["room_code"]
            result["code"] = code
            a.wait_for_timeout(800)
            a.screenshot(path=args.out / "a_lobby_alone.png")
            if (
                not seats(alone)
                or "HOST" not in seats(alone)[0]
                or seats(alone)[1:] != ["2  (open)", "3  (open)", "4  (open)"]
            ):
                problems.append(f"A alone should hold seat 1 as host and three open seats: {seats(alone)}")
            if alone.get("lobby_buttons") != "Start":
                problems.append(f"A, the host, should be offered Start: {alone.get('lobby_buttons')!r}")

            # C opens the link now and leaves the preview open: loading takes minutes in this browser, and the two in
            # the night would not outlast it, idle. The preview follows the night by itself.
            c = pages["c"] = open_page(browser, f"{base}?{query}&room={code}", console, problems, "C")
            early = wait_for(c, "C's first preview", lambda s: s.get("screen") == "lobby_screen", 240)
            if "Waiting room" not in early.get("room_status", ""):
                problems.append(f"C should first read a waiting room: {early.get('room_status')!r}")

            # B opens the link: a waiting room to look at, then Join.
            b = pages["b"] = open_page(browser, f"{base}?{query}&room={code}", console, problems, "B")
            preview = wait_for(b, "B's preview", lambda s: s.get("screen") == "lobby_screen", 120)
            if "Waiting room" not in preview.get("room_status", ""):
                problems.append(f"B should read a waiting room before joining: {preview.get('room_status')!r}")
            if preview.get("lobby_buttons") != "Join":
                problems.append(f"B should be offered Join: {preview.get('lobby_buttons')!r}")
            b.mouse.click(5, 5)  # the click a browser needs before the game may take the mouse
            smoke.press(b, "Enter")  # Join
            wait_for(b, "B in the lobby", lambda s: s.get("screen") == "lobby_screen" and taken(s) == 2, 60)
            two_a = wait_for(a, "A sees two seats", lambda s: taken(s) == 2, 20)
            two_b = read_probe(b)
            a.screenshot(path=args.out / "a_lobby_two.png")
            b.screenshot(path=args.out / "b_lobby_two.png")
            result["seats_a"] = seats(two_a)
            result["seats_b"] = seats(two_b)
            if seats(two_a)[:2] != seats(two_b)[:2]:
                problems.append(f"A and B should see the same two seats: {seats(two_a)} / {seats(two_b)}")
            if two_b.get("lobby_buttons") != "":
                problems.append(f"B, a guest, must not be offered Start or Play yet: {two_b.get('lobby_buttons')!r}")
            if "Waiting for" not in two_b.get("room_status", ""):
                problems.append(f"B should be waiting for the host: {two_b.get('room_status')!r}")

            # A presses Start and goes in; B is told and presses Play.
            smoke.press(a, "Enter")
            started = wait_for(b, "B told the night started", lambda s: s.get("lobby_buttons") == "Play", 30)
            b.screenshot(path=args.out / "b_started.png")
            if "started the night" not in started.get("room_status", ""):
                problems.append(f"B should be told the host started: {started.get('room_status')!r}")
            smoke.press(b, "Enter")
            wait_for(a, "A in the night", in_night, NIGHT_TIMEOUT_S)
            wait_for(b, "B in the night", in_night, NIGHT_TIMEOUT_S)
            for name in ("a", "b"):
                wait_for(pages[name], f"{name} sees two players", lambda s: s.get("players", 0) >= 2, 60)

            # C's preview, left open, now says the night is in progress; Join goes straight in.
            late = wait_for(
                c, "C's preview to follow the night", lambda s: "Night in progress" in s.get("room_status", ""), 30
            )
            c.wait_for_timeout(800)
            c.screenshot(path=args.out / "c_preview.png")
            result["c_preview"] = late.get("room_status")
            if "Night in progress" not in late.get("room_status", ""):
                problems.append(f"C should read a night in progress: {late.get('room_status')!r}")
            if late.get("lobby_buttons") != "Join":
                problems.append(f"C should be offered Join: {late.get('lobby_buttons')!r}")
            c.mouse.click(5, 5)
            smoke.press(c, "Enter")
            # While C loads, A and B are watched for the night's notice of the newcomer (it shows for a few seconds).
            heard: set[str] = set()
            deadline = time.monotonic() + NIGHT_TIMEOUT_S
            while time.monotonic() < deadline:
                for name in ("a", "b"):
                    heard.update(n for n in read_probe(pages[name]).get("notice_log", "").split("|") if n)
                if read_probe(c).get("night") and all(read_probe(pages[n]).get("players", 0) >= 3 for n in "abc"):
                    break
                time.sleep(0.25)
            else:
                raise TimeoutError("C never got into the night with A and B seeing three players")
            result["notices_heard"] = sorted(heard)
            if not any(n.endswith("JOINED") for n in heard):
                problems.append(f"A and B should read that someone JOINED in the night's notices: {sorted(heard)}")
            for name in ("a", "b", "c"):
                pages[name].wait_for_timeout(2000)
                pages[name].screenshot(path=args.out / f"{name}_night.png")
                result[f"{name}_player_id"] = read_probe(pages[name]).get("player_id")
            if sorted(result[f"{n}_player_id"] for n in "abc") != [1, 2, 3]:
                problems.append(f"the three should be players 1, 2 and 3: {[result[f'{n}_player_id'] for n in 'abc']}")
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            for name, page in pages.items():
                try:
                    page.screenshot(path=args.out / f"failure_{name}.png")
                except PlaywrightError:
                    pass
        finally:
            browser.close()
            if local:
                local.shutdown()
    (args.out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
