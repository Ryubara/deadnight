"""Quick join from the main menu, in the web build, in headless Chromium: no Play together screen, a night at once.

Page C presses Quick join on the main menu (the Play tab's second item) and lands in a night; page D does the same and
lands in C's night (both read two players). The probe is read the whole time: a page that ever reports the
`together_screen` fails the run, because Quick join must go straight in, and the card's words (`quick_join`) are kept
(*Finding a night...*). Page E points the game at a backend that is not there: the card says the network text and
offers Create a night and Close, and the page stays on the main menu.

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/quick_join.py build/web https://backend.example build/quick-join

The first argument is a folder with the export (served on a fixed local port, which the backend must list in
`CORS_ORIGINS`) or the URL of a deployed build. Writes `result.json`, `console.txt` and screenshots (`c_searching.png`
when the card was caught searching, `c_night.png`, `d_night.png`, `e_failed.png`).
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
SEARCHING = "Finding a night..."
NETWORK_TEXT = "Could not reach the game's servers. Check your connection."
# The browser refuses a pointer lock that is not asked for inside a click or key press; the game goes on.
IGNORED = ("A user gesture is required to request Pointer Lock",)
# Nothing here is on port 9: the connection is refused at once.
DEAD_BACKEND = "http://127.0.0.1:9"


def open_page(browser: Browser, url: str, console: list[str], problems: list[str], label: str) -> Page:
    page = browser.new_context(viewport=smoke.VIEWPORT).new_page()
    page.on("console", lambda m: console.append(f"[{label}] [{m.type}] {m.text}"))
    page.on(
        "pageerror",
        lambda e: None if any(text in str(e) for text in IGNORED) else problems.append(f"[{label}] [pageerror] {e}"),
    )
    page.goto(url, wait_until="commit")
    return page


def in_night(state: dict) -> bool:
    return bool(state.get("night") and state.get("running"))


def press_quick_join(page: Page) -> None:
    """The main menu's Play tab: Play together, then Quick join (one step down)."""
    smoke.reach_menu(page)
    smoke.menu_item(page, "Play", 1)
    smoke.press(page, "Enter")


def follow_into_night(page: Page, label: str, out: Path, seen: dict, problems: list[str]) -> None:
    """Watches the probe from the press until the night runs: which screens showed, and what the card said."""
    deadline = time.monotonic() + NIGHT_TIMEOUT_S
    captured = False
    screens: list[str] = seen.setdefault(f"{label}_screens", [])
    words: list[str] = seen.setdefault(f"{label}_card", [])
    while time.monotonic() < deadline:
        state = smoke.probe(page)
        if state.get("screen") and (not screens or screens[-1] != state["screen"]):
            screens.append(state["screen"])
        text = state.get("quick_join", "")
        if text and text not in words:
            words.append(text)
        if text == SEARCHING and not captured:
            page.screenshot(path=out / f"{label.lower()}_searching.png")
            captured = True
        if in_night(state):
            break
        time.sleep(0.1)
    else:
        raise TimeoutError(f"{label} never reached a running night; screens seen {screens}")
    if "together_screen" in screens:
        problems.append(f"{label} passed through the Play together screen: {screens}")
    if "lobby_screen" in screens:
        problems.append(f"{label} was shown a lobby screen: Quick join has no waiting room: {screens}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's https address")
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
    # `bot`: the autopilot plays, so nobody idles and dies while the other page loads.
    query = f"backend={args.backend}&bot"
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True)
        else:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        try:
            # C presses Quick join: a night, with the card over the menu and no screen between.
            c = open_page(browser, f"{base}?{query}", console, problems, "C")
            press_quick_join(c)
            follow_into_night(c, "C", args.out, result, problems)
            wait_players(c, 1)
            # D presses Quick join and is put in C's night.
            d = open_page(browser, f"{base}?{query}", console, problems, "D")
            press_quick_join(d)
            follow_into_night(d, "D", args.out, result, problems)
            for name, page in (("c", c), ("d", d)):
                result[f"{name}_players"] = wait_players(page, 2)
                page.wait_for_timeout(2500)
                page.screenshot(path=args.out / f"{name}_night.png")
            # E: nothing to reach. The card says so, offers Create a night, and the page stays on the menu.
            e = open_page(browser, f"{base}?backend={DEAD_BACKEND}", console, problems, "E")
            press_quick_join(e)
            failed = smoke.wait_for(
                e, "the failure text", lambda s: s.get("quick_join") not in ("", SEARCHING), smoke.SCREEN_TIMEOUT_S
            )
            e.wait_for_timeout(800)
            e.screenshot(path=args.out / "e_failed.png")
            result["e_card"] = failed["quick_join"]
            result["e_screen"] = failed["screen"]
            if failed["quick_join"] != NETWORK_TEXT:
                problems.append(f"E should read the network text, read {failed['quick_join']!r}")
            if failed["screen"] != "main_menu":
                problems.append(f"E should stay on the main menu, is on {failed['screen']}")
            smoke.press(e, "Escape")  # the card's Close: back to the menu with nothing over it
            gone = smoke.wait_for(e, "the card to close", lambda s: s.get("quick_join") == "", smoke.SCREEN_TIMEOUT_S)
            if gone["screen"] != "main_menu":
                problems.append(f"E should be on the main menu after Close, is on {gone['screen']}")
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            for name, page in {"c": locals().get("c"), "d": locals().get("d"), "e": locals().get("e")}.items():
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


def wait_players(page: Page, count: int) -> int:
    seen = smoke.wait_for(page, f"{count} players", lambda s: s.get("players", 0) >= count, 120)
    return seen["players"]


if __name__ == "__main__":
    sys.exit(main())
