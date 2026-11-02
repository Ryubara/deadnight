"""Two friends, and two strangers, play together from the web build, in headless Chromium.

Page A opens the game, goes to Play together and creates a night: the screen shows a code and an invite link.
Page B opens that link (`?room=CODE`) and lands in A's night. Pages C and D never talk to A or B: each presses Quick
join, and they land together in a night of their own. The script reads the game's probe (`window.deadnight`) on every
page and fails unless A and B see two players, C and D see two players and A never sees more than two.

    uv run --with playwright==1.64.1 python tools/web_smoke/rooms.py build/web https://backend.example build/rooms

The first argument is a folder with the export (served on a fixed local port, which the backend must list in
`CORS_ORIGINS`) or the URL of a deployed build (then the backend's CORS already allows it). Writes `result.json`,
`console.txt` and screenshots (`a_invite.png`, `b_invite.png`, and `a_night.png` .. `d_night.png` a moment after each pair meets, `*_end.png` at the end).
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


# The browser refuses a pointer lock that is not asked for inside a click or key press, and a night takes half a
# minute to load after the press that started it. The game goes on (a click in the night takes the mouse), so this is
# noted, not a failure of the flow under test.
IGNORED = ("A user gesture is required to request Pointer Lock",)


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
    """From the main menu to the Play together screen (the second item)."""
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)  # gives the canvas the keyboard
    page.wait_for_timeout(2500)
    smoke.press(page, "ArrowDown")
    smoke.press(page, "Enter")
    wait_for(page, "the Play together screen", lambda s: s.get("screen") == "together_screen", smoke.SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)


def in_night(state: dict) -> bool:
    return bool(state.get("night") and state.get("running"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's https address")
    parser.add_argument("out", type=Path)
    parser.add_argument("--seconds", type=float, default=20.0, help="how long all four play once they are in")
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
    query = f"backend={args.backend}"
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True)
        else:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        try:
            # A creates a night and sees its code and link.
            a = open_page(browser, f"{base}?{query}", console, problems, "A")
            to_together(a)
            smoke.press(a, "ArrowDown")  # Quick join -> Create a night
            smoke.press(a, "Enter")
            invite = wait_for(a, "the invite", lambda s: s.get("room_code", "") != "", 60)
            code = invite["room_code"]
            result["code"] = code
            a.wait_for_timeout(800)
            a.screenshot(path=args.out / "a_invite.png")
            smoke.press(a, "Enter")  # Play
            # B opens the invite link and is in the same night.
            b = open_page(browser, f"{base}?{query}&room={code}", console, problems, "B")
            # The link finds the night; pressing Play is the click a browser needs before the game may take the mouse.
            wait_for(b, "B's invite", lambda s: s.get("room_code") == code, 120)
            b.mouse.click(5, 5)
            b.wait_for_timeout(800)
            b.screenshot(path=args.out / "b_invite.png")
            smoke.press(b, "Enter")
            wait_for(a, "A in the night", in_night, NIGHT_TIMEOUT_S)
            wait_for(b, "B in the night", in_night, NIGHT_TIMEOUT_S)
            # Each page's first seconds in the night: the other player stands beside the player's own.
            for name, page in (("a", a), ("b", b)):
                wait_for(page, f"{name} sees two players", lambda s: s.get("players", 0) >= 2, 60)
                page.wait_for_timeout(2500)
                page.screenshot(path=args.out / f"{name}_night.png")
            # C and D press Quick join and meet in a night of their own.
            c = open_page(browser, f"{base}?{query}", console, problems, "C")
            to_together(c)
            smoke.press(c, "Enter")  # Quick join is the first item
            wait_for(c, "C in the night", in_night, NIGHT_TIMEOUT_S)
            wait_for(c, "C sees a player", lambda s: s.get("players", 0) >= 1, 60)
            d = open_page(browser, f"{base}?{query}", console, problems, "D")
            to_together(d)
            smoke.press(d, "Enter")
            wait_for(d, "D in the night", in_night, NIGHT_TIMEOUT_S)
            for name, page in (("c", c), ("d", d)):
                wait_for(page, f"{name} sees two players", lambda s: s.get("players", 0) >= 2, 60)
                page.wait_for_timeout(2500)
                page.screenshot(path=args.out / f"{name}_night.png")
            # Everyone plays a while; the pages count who they see.
            seen = {name: 0 for name in "abcd"}
            began = time.monotonic()
            pages = {"a": a, "b": b, "c": c, "d": d}
            while time.monotonic() - began < args.seconds:
                for name, page in pages.items():
                    seen[name] = max(seen[name], read_probe(page).get("players", 0))
                time.sleep(1.0)
            for name, page in pages.items():
                page.screenshot(path=args.out / f"{name}_end.png")
                result[f"{name}_player_id"] = read_probe(page).get("player_id")
            result["players_seen"] = seen
            if seen["a"] != 2 or seen["b"] != 2:
                problems.append(f"A and B should see exactly two players each, saw {seen}")
            if seen["c"] != 2 or seen["d"] != 2:
                problems.append(f"C and D should see exactly two players each, saw {seen}")
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            for name, page in {
                "a": locals().get("a"),
                "b": locals().get("b"),
                "c": locals().get("c"),
                "d": locals().get("d"),
            }.items():
                if page is not None:
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
