"""The Server Browser, in the web build, in headless Chromium, against a real backend (Deadnight #1180).

Page A hosts a night and starts it (a night in progress: a *match* row in the list); page B makes a waiting lobby and
leaves it waiting (a *lobby* row). Page C opens the browser from the main menu's Play tab (the second item), reads the
list (both nights, the people count out of 8) and presses A's row with the keyboard: it lands in A's night, two
players. Page D does the same and lands there too (three). Page F presses B's row: it lands in B's lobby, the code on
its screen. Page E points the game at a backend that is not there: the browser says the network text and offers Try
again, and Esc takes it back to the main menu. The probe is read the whole time: a page that is shown the Play together
screen on the way fails the run, because a row goes straight in.

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/server_browser.py build/web https://backend.example build/server-browser

The first argument is a folder with the export (served on a fixed local port, which the backend must list in
`CORS_ORIGINS`, or `--cors-shim` adds the headers on the way) or the URL of a deployed build. Writes `result.json`,
`console.txt` and screenshots (`c_list.png`, `c_night.png`, `d_night.png`, `f_lobby.png`, `e_failed.png`).
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
NETWORK_TEXT = "Could not reach the game's servers. Check your connection."
# The browser refuses a pointer lock that is not asked for inside a click or key press; the game goes on.
IGNORED = ("A user gesture is required to request Pointer Lock",)
# Nothing here is on port 9: the connection is refused at once.
DEAD_BACKEND = "http://127.0.0.1:9"


CORS_HEADERS = {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
    "access-control-allow-headers": "content-type, authorization",
}
# Set by `--cors-shim`: the backend whose answers the browser is given CORS headers for.
SHIMMED: list[str] = []


def shim_cors(context, backend: str) -> None:
    """Lets a build served from this machine call a deployed backend that only lists its own web page in
    `CORS_ORIGINS`: the answers pass through the probe, which adds the headers. The requests themselves, and the game
    server the ticket names, are the deployed ones."""

    def handle(route) -> None:
        if route.request.method == "OPTIONS":
            route.fulfill(status=204, headers=CORS_HEADERS)
            return
        response = route.fetch()
        route.fulfill(response=response, headers={**response.headers, **CORS_HEADERS})

    context.route(f"{backend}/**", handle)


def open_page(browser: Browser, url: str, console: list[str], problems: list[str], label: str) -> Page:
    context = browser.new_context(viewport=smoke.VIEWPORT)
    for backend in SHIMMED:
        shim_cors(context, backend)
    page = context.new_page()
    page.on("console", lambda m: console.append(f"[{label}] [{m.type}] {m.text}"))
    page.on(
        "pageerror",
        lambda e: None if any(text in str(e) for text in IGNORED) else problems.append(f"[{label}] [pageerror] {e}"),
    )
    page.goto(url, wait_until="commit")
    return page


def read_probe(page: Page) -> dict:
    """The whole probe (`smoke.probe` keeps the few fields the shared helpers need)."""
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : null") or {}


def wait_for(page: Page, what: str, test, seconds: float) -> dict:
    """Polls the whole probe until `test` holds (`smoke.wait_for` reads the few fields of `smoke.probe`)."""
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = read_probe(page)
        if test(seen):
            return seen
        time.sleep(0.25)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def in_night(state: dict) -> bool:
    return bool(state.get("night") and state.get("running"))


def rows_of(state: dict) -> list[dict]:
    """The browser's rows as the probe publishes them: `CODE kind people/seats map host`, top to bottom."""
    out = []
    for text in filter(None, str(state.get("browser", "")).split("|")):
        code, kind, people, map_id, host = (text.split(" ", 4) + [""])[:5]
        out.append({"code": code, "kind": kind, "people": people, "map": map_id, "host": host})
    return out


def open_browser(page: Page) -> None:
    """From the main menu, the Play tab's Server browser (one step down from Play together), and its list."""
    smoke.menu_item(page, "Play", 1)
    smoke.press(page, "Enter")
    wait_for(page, "the Server Browser", lambda s: s.get("screen") == "server_browser_screen", smoke.SCREEN_TIMEOUT_S)


def press_row(page: Page, code: str, problems: list[str], label: str) -> list[str]:
    """Waits for the list to hold the night `code`, walks the keyboard down to its row (the first has the focus when the
    list arrives) and presses it. Returns the screens that showed from the press on."""
    state = wait_for(
        page,
        f"{label}'s list to hold {code}",
        lambda s: any(row["code"] == code for row in rows_of(s)),
        smoke.SCREEN_TIMEOUT_S,
    )
    rows = rows_of(state)
    wait_for(page, "the first row to have the focus", lambda s: s.get("focus") == f"Night_{rows[0]['code']}", 20)
    for _ in range([row["code"] for row in rows].index(code)):
        smoke.press(page, "ArrowDown")
    wait_for(page, "the row to have the focus", lambda s: s.get("focus") == f"Night_{code}", 20)
    smoke.press(page, "Enter")
    screens: list[str] = []
    deadline = time.monotonic() + NIGHT_TIMEOUT_S
    while time.monotonic() < deadline:
        now = read_probe(page)
        if now.get("screen") and (not screens or screens[-1] != now["screen"]):
            screens.append(now["screen"])
        if in_night(now) or now.get("screen") == "lobby_screen":
            break
        time.sleep(0.1)
    if "together_screen" in screens:
        problems.append(f"{label} was shown the Play together screen on the way: {screens}")
    return screens


def wait_players(page: Page, count: int, label: str) -> None:
    wait_for(page, f"{label} to see {count} players", lambda s: read_probe(page).get("players", 0) >= count, 120)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's https address")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    parser.add_argument(
        "--cors-shim",
        action="store_true",
        help="add CORS headers to the backend's answers, to run a local build against a deployed backend",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    console: list[str] = []
    problems: list[str] = []
    result: dict = {"backend": args.backend}

    if args.cors_shim:
        SHIMMED.append(args.backend.rstrip("/"))
    local = None
    base = args.web
    if not args.web.startswith(("http://", "https://")):
        handler = functools.partial(smoke.Quiet, directory=str(Path(args.web)))
        local = http.server.ThreadingHTTPServer(("127.0.0.1", LOCAL_PORT), handler)
        threading.Thread(target=local.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{LOCAL_PORT}/index.html"
    # `bot`: the autopilot plays, so nobody idles and dies while the other pages load.
    query = f"backend={args.backend}&bot&probe"
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True)
        else:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        try:
            # A hosts a night and starts it; B makes a lobby and leaves it waiting.
            a = open_page(browser, f"{base}?{query}", console, problems, "A")
            smoke.reach_menu(a)
            smoke.open_together(a)
            smoke.press(a, "ArrowDown")  # Server browser -> Create a night
            smoke.press(a, "Enter")
            smoke.give_name(a, "Ann")
            code_a = wait_for(a, "A's lobby", lambda s: s.get("room_code", "") != "", 60)["room_code"]
            smoke.press(a, "Enter")  # Start the night
            wait_for(a, "A in the night", in_night, NIGHT_TIMEOUT_S)
            b = open_page(browser, f"{base}?{query}", console, problems, "B")
            smoke.reach_menu(b)
            smoke.open_together(b)
            smoke.press(b, "ArrowDown")
            smoke.press(b, "Enter")
            smoke.give_name(b, "Bo")
            code_b = wait_for(b, "B's lobby", lambda s: s.get("room_code", "") != "", 60)["room_code"]
            result["night_code"], result["lobby_code"] = code_a, code_b

            # C opens the browser: both nights are listed, one a match in progress, one a lobby waiting.
            c = open_page(browser, f"{base}?{query}", console, problems, "C")
            smoke.reach_menu(c)
            open_browser(c)
            listed = wait_for(
                c,
                "both nights in C's list",
                lambda s: {code_a, code_b} <= {row["code"] for row in rows_of(s)},
                smoke.SCREEN_TIMEOUT_S,
            )
            rows = {row["code"]: row for row in rows_of(listed)}
            result["list"] = rows
            if rows[code_a]["kind"] != "match" or rows[code_b]["kind"] != "lobby":
                problems.append(f"the list should show A's night as a match and B's as a lobby, shows {rows}")
            c.wait_for_timeout(1200)
            c.screenshot(path=args.out / "c_list.png")
            result["c_screens"] = press_row(c, code_a, problems, "C")
            wait_for(c, "C in the night", in_night, NIGHT_TIMEOUT_S)
            wait_players(c, 2, "C")
            # D does the same and is put in A's night: three players.
            d = open_page(browser, f"{base}?{query}", console, problems, "D")
            smoke.reach_menu(d)
            open_browser(d)
            result["d_screens"] = press_row(d, code_a, problems, "D")
            wait_for(d, "D in the night", in_night, NIGHT_TIMEOUT_S)
            wait_players(d, 3, "D")
            for name, page in (("c", c), ("d", d)):
                page.wait_for_timeout(2000)
                page.screenshot(path=args.out / f"{name}_night.png")
            result["c_players"], result["d_players"] = (read_probe(c).get("players"), read_probe(d).get("players"))

            # F presses B's waiting lobby: its lobby screen, with B's code.
            f = open_page(browser, f"{base}?{query}", console, problems, "F")
            smoke.reach_menu(f)
            open_browser(f)
            result["f_screens"] = press_row(f, code_b, problems, "F")
            seen = wait_for(f, "F in B's lobby", lambda s: s.get("room_code") == code_b, smoke.SCREEN_TIMEOUT_S)
            f.wait_for_timeout(800)
            f.screenshot(path=args.out / "f_lobby.png")
            result["f_seats"] = seen.get("lobby_seats", "")

            # E: nothing to reach. The browser says so in words and offers Try again; Esc is back to the menu.
            e = open_page(browser, f"{base}?backend={DEAD_BACKEND}&probe", console, problems, "E")
            smoke.reach_menu(e)
            open_browser(e)
            failed = wait_for(
                e,
                "the failure text",
                lambda s: s.get("browser_status", "") == NETWORK_TEXT,
                smoke.SCREEN_TIMEOUT_S,
            )
            e.wait_for_timeout(800)
            e.screenshot(path=args.out / "e_failed.png")
            result["e_status"] = failed["browser_status"]
            smoke.press(e, "Escape")
            gone = wait_for(e, "the menu again", lambda s: s.get("screen") == "main_menu", smoke.SCREEN_TIMEOUT_S)
            result["e_after_escape"] = gone["screen"]
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            for name, page in {
                "a": locals().get("a"),
                "b": locals().get("b"),
                "c": locals().get("c"),
                "d": locals().get("d"),
                "e": locals().get("e"),
                "f": locals().get("f"),
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
