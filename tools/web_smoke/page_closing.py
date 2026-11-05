"""A player alone on the waiting room closes the tab, in the real web build (Deadnight #1188).

Page A opens the game (the website: a page on one origin, the platform backend on another, as the web build is deployed),
goes to Play together and creates a night. A stand-in for the Server Browser (a plain guest asking the backend's list and
a code's preview) then watches that night while A:

1. **switches tab or app**: the page is told it is hidden and `pagehide` arrives with `persisted` true (the browser keeps the
   page to show again). The page must send nothing and the night must stay listed;
2. **goes quiet** (a host pasting the invite in another tab): A's polls are held back for longer than the list's quiet time
   (`memberQuietMs`, 15 s). The night must leave the list, its code must still open it (a friend can join), and when the polls
   come back it must be listed again with A still on its lobby screen;
3. **closes the tab** for real (`page.close()`, the browser's own close): the night must be gone from the list within
   `--within` seconds and its code must answer `not_found`.

`closing_checks` is also run by `activity.py --closing`, for the Activity behind the Discord proxy stand-in.

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/page_closing.py build/web build/closing

Starts a local backend (a free port, `CORS_ORIGINS` naming the page) and serves the export on a fixed local port. Writes
`closing.json` and screenshots. Exits 1 when a check fails.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import lobby
import smoke

REPO = Path(__file__).resolve().parents[2]
PAGE_PORT = 8082
QUIET_SECONDS = 20  # longer than the backend's `memberQuietMs` (15 s) with room for a poll in flight
HIDDEN_JS = """() => {
  Object.defineProperty(document, 'visibilityState', {value: 'hidden', configurable: true});
  Object.defineProperty(document, 'hidden', {value: true, configurable: true});
  document.dispatchEvent(new Event('visibilitychange'));
  window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted: true}));
}"""
VISIBLE_JS = """() => {
  Object.defineProperty(document, 'visibilityState', {value: 'visible', configurable: true});
  Object.defineProperty(document, 'hidden', {value: false, configurable: true});
  document.dispatchEvent(new Event('visibilitychange'));
  window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted: true}));
}"""


class Backend:
    """What a Server Browser does with the backend: a guest who lists the nights and looks a code up. Joins nobody."""

    def __init__(self, address: str) -> None:
        self.address = address.rstrip("/")
        self.token = self._post("/auth/guest", {})["token"]

    def _post(self, path: str, body: dict) -> dict:
        data, status = self.call("POST", path, body)
        return {**data, "status": status}

    def call(self, method: str, path: str, body: dict | None = None) -> tuple[dict, int]:
        request = urllib.request.Request(
            self.address + path,
            data=json.dumps(body).encode() if body is not None else None,
            method=method,
            headers={
                "Content-Type": "application/json",
                **({"Authorization": f"Bearer {self.token}"} if hasattr(self, "token") else {}),
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as answer:
                return json.loads(answer.read() or b"{}"), answer.status
        except urllib.error.HTTPError as error:
            return json.loads(error.read() or b"{}"), error.code

    def listed(self, code: str) -> bool:
        data, status = self.call("GET", "/lobbies")
        assert status == 200, f"the list answered {status}: {data}"
        return any(row["code"] == code for row in data["nights"])

    def preview_status(self, code: str) -> int:
        return self.call("POST", "/lobbies/preview", {"code": code})[1]


def wait_until(test, seconds: float, step: float = 0.1) -> float | None:
    """Seconds until `test()` held, or None when it did not within `seconds`."""
    began = time.monotonic()
    while time.monotonic() - began < seconds:
        if test():
            return time.monotonic() - began
        time.sleep(step)
    return None


def closing_checks(
    page: Page, frame, backend: Backend, code: str, out: Path, within: float = 3.0, control: bool = False
) -> tuple[list[str], bool]:
    """The three steps in the docstring, on a page that shows the lobby with `code`; the lines and whether all held.
    `frame` is where the game runs (the page itself, or the Activity's iframe); `page` closes."""
    lines: list[str] = []
    failures: list[str] = []

    def check(ok: bool, what: str) -> None:
        lines.append(f"{what}: {'ok' if ok else 'FAILED'}")
        if not ok:
            failures.append(what)

    def sent() -> int:
        return int(frame.evaluate("window.deadnightClosing ? window.deadnightClosing.sent : -1"))

    armed = frame.evaluate("window.deadnightClosing ? window.deadnightClosing.url : ''")
    check(
        wait_until(lambda: backend.listed(code), 6) is not None,
        "the night is listed while its host is on the lobby screen",
    )
    check(
        bool(re.search(r"/lobbies/[0-9a-f-]{36}/page-closed$", armed or "")),
        f"the page holds its word for this lobby ({armed!r})",
    )

    # 1. A tab or app switch: hidden, and `pagehide` with persisted true. Nothing is sent, the night stays.
    frame.evaluate(HIDDEN_JS)
    time.sleep(2.5)
    check(sent() == 0, "a page that is only hidden (a tab or app switch) sent nothing")
    check(backend.listed(code), "the night is still listed after the switch")
    frame.evaluate(VISIBLE_JS)

    # 2. A host in another tab: the polls stop for longer than the list's quiet time.
    # Held, not refused: a refused request is an error the game waits ten seconds on, and a tab in the background fails
    # nothing, it simply does not ask. The polls that come while held wait here and are let go when the host is back.
    holding = {"on": True}
    held: list = []

    def hold(route) -> None:
        if holding["on"] and route.request.method == "GET":
            held.append(route)
        else:
            route.fallback()

    page.context.route(re.compile(r".*/lobbies/[0-9a-f-]{36}$"), hold)
    gone_from_list = wait_until(lambda: not backend.listed(code), QUIET_SECONDS + 10, 0.8)
    check(
        gone_from_list is not None,
        f"the night left the list once nobody had been heard from (after {gone_from_list and round(gone_from_list, 1)} s)",
    )
    check(backend.preview_status(code) == 200, "while it was out of the list its code still opened it")
    page.screenshot(path=out / "quiet.png")
    holding["on"] = False
    for route in held:
        try:
            route.fallback()
        except PlaywrightError:  # the game gave up on that poll after ten seconds
            pass
    back = wait_until(lambda: backend.listed(code), 10, 0.8)
    check(
        back is not None,
        f"the night was listed again when the host's polls came back (after {back and round(back, 1)} s)",
    )
    check(
        str(smoke_probe(frame).get("room_code", "")) == code, "the host is still on the same lobby, with the same code"
    )
    check(sent() == 0, "the page had still sent nothing")
    page.context.unroute(re.compile(r".*/lobbies/[0-9a-f-]{36}$"))

    # 3. The tab is closed for real.
    if control:
        # The word is taken back first (a page the system threw away says nothing): the night must stay listed for a
        # while, which shows the checks below measure the word, and then leave the list by itself, the fallback.
        frame.evaluate("window.deadnightClosing.url = ''")
        started = time.monotonic()
        page.close()
        time.sleep(5)
        check(backend.listed(code), "with no word sent the night was still listed 5 s after the tab closed")
        gone = wait_until(lambda: not backend.listed(code), 25, 0.8)
        check(
            gone is not None,
            f"and it left the list by itself {round(time.monotonic() - started, 1)} s after the close (nobody polls it)",
        )
        check(backend.preview_status(code) == 200, "its code still opens it: the lobby is not ended, only hidden")
        return lines, not failures
    started = time.monotonic()
    page.close()
    ended = wait_until(lambda: not backend.listed(code), within + 5, 0.05)
    took = None if ended is None else time.monotonic() - started
    check(
        took is not None and took <= within,
        f"the night was gone from the list {took and round(took, 2)} s after the tab closed (at most {within} s)",
    )
    check(backend.preview_status(code) == 404, "its code says it is gone")
    return lines, not failures


def smoke_probe(frame) -> dict:
    return frame.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : {}") or {}


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def start_backend() -> tuple[subprocess.Popen, str]:
    port = free_port()
    env = {
        **os.environ,
        "DISCORD_MODE": "off",
        "GUEST_SIGN_IN": "1",
        "SESSION_SECRET": secrets.token_hex(24),
        "TICKET_SECRET": secrets.token_hex(24),
        "GAME_SERVER_SECRET": secrets.token_hex(24),
        "CORS_ORIGINS": f"http://127.0.0.1:{PAGE_PORT}",
        "HOST": "127.0.0.1",
        "PORT": str(port),
        "LOG_LEVEL": "info",
    }
    env.pop("NODE_ENV", None)
    node = shutil.which("node")
    if not node:
        raise SystemExit("needs node on the PATH")
    process = subprocess.Popen([node, "src/main.ts"], cwd=REPO / "spikes" / "backend", env=env)
    url = f"http://127.0.0.1:{port}"
    for _ in range(100):
        try:
            urllib.request.urlopen(f"{url}/health", timeout=1).read()
            return process, url
        except OSError:
            if process.poll() is not None:
                raise SystemExit("the local backend exited (did `npm ci --prefix spikes/backend` run?)")
            time.sleep(0.2)
    process.terminate()
    raise SystemExit("the local backend never answered /health")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path, help="folder with the export")
    parser.add_argument("out", type=Path)
    parser.add_argument(
        "--backend", help="a deployed backend whose CORS_ORIGINS names http://127.0.0.1:8082, instead of a local one"
    )
    parser.add_argument("--control", action="store_true", help="send no word on the close: the fallback alone")
    parser.add_argument("--within", type=float, default=3.0, help="seconds the closed tab's night may stay listed")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", PAGE_PORT), functools.partial(smoke.Quiet, directory=str(args.web))
    )
    threading.Thread(target=server.serve_forever, daemon=True).start()
    process, address = (None, args.backend.rstrip("/")) if args.backend else start_backend()
    console: list[str] = []
    problems: list[str] = []
    lines: list[str] = []
    ok = False
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL + smoke.mute_args())
            page = lobby.open_page(
                browser, f"http://127.0.0.1:{PAGE_PORT}/index.html?backend={address}&probe", console, problems, "A"
            )
            lobby.to_together(page)
            smoke.press(page, "ArrowDown")  # Quick join -> Create a night
            smoke.press(page, "Enter")
            smoke.give_name(page, "Ann")
            state = lobby.wait_for(
                page, "A's lobby", lambda s: s.get("screen") == "lobby_screen" and s.get("room_code", "") != "", 60
            )
            code = state["room_code"]
            lines.append(f"A made the night {code}")
            page.wait_for_timeout(1500)
            page.screenshot(path=args.out / "lobby.png")
            checked, ok = closing_checks(page, page, Backend(address), code, args.out, args.within, args.control)
            lines += checked
            browser.close()
    finally:
        if process is not None:
            process.terminate()
        server.shutdown()
    (args.out / "console.txt").write_text("\n".join(console), encoding="utf-8")
    (args.out / "closing.json").write_text(json.dumps({"lines": lines, "problems": problems, "ok": ok}, indent=2))
    print("\n".join(lines))
    if problems:
        print("page problems:", *problems, sep="\n  ")
    print("tab closed on the waiting room:", "held" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
