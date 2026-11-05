"""Which request a tab can still send while it closes, measured in real browsers (Deadnight #1188, which #1177 left open).

#1177 found that a `pagehide` request with an `Authorization` header cannot be relied on. This measures it: a page on one
origin (the website) signs in to the platform backend on another (as the web build does), makes a lobby, and on `pagehide`
sends the backend one of these, then the tab is closed for real (`page.close()`, the browser's own close, not a
script's `window.close()`) and a second page watches whether the lobby went away:

- `fetch+header`: `fetch(url, {keepalive: true, headers: {Authorization: ...}})`. The header makes it a request that needs
  a CORS preflight (an OPTIONS the browser sends first and waits for), which a closing page may not get to finish.
- `beacon+text`: `navigator.sendBeacon(url, json)` with a **string**, the token in the body (the browser types it
  `text/plain;charset=UTF-8`). A simple request: no preflight, and the browser queues it for the page.
- `beacon+blob`: the same with `new Blob([json], {type: 'text/plain'})`, the form most examples show. Firefox does not
  send it when the tab is closed (the Blob is read after the page is gone); a string it sends.
- `fetch+text`: `fetch(url, {keepalive: true, headers: {'Content-Type': 'text/plain'}, body: json})`: the same simple request.
- `beacon+json`: `sendBeacon` with an `application/json` Blob: not a simple request either (a preflight, which the beacon
  API is not allowed to wait for in some browsers).

`--backend URL` runs against a deployed backend instead (the network's own latency: the Railway test service of
Deadnight #1188, from this machine). `--delay-ms N` puts a proxy in front of the backend that holds every request N ms before forwarding it (a loopback call
takes about 2 ms, a player's takes 50 to 300, and a preflight is a second round trip a closing tab may not wait for).
Each is tried `--runs` times in each browser (Chromium, Firefox, WebKit: Playwright's builds). The report is a table of
how many of the runs ended the lobby and how long after the close the backend had heard it.

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/page_closing_transport.py <out folder> [--runs 5] [--browsers chromium,firefox,webkit] [--delay-ms 0]

The backend is a local one on a free port, the page is served from another (so the calls are cross-origin, which the
website's are); `CORS_ORIGINS` lists the page. Writes `transport.json`. Exits 1 when `beacon+text` does not arrive in every
run of every browser: that is the one the game sends.
"""

from __future__ import annotations

import argparse
import http.client
import http.server
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from playwright.sync_api import Browser, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

REPO = Path(__file__).resolve().parents[2]
PAGE_PORT = 8097
PAGE = "<!doctype html><title>transport</title><p>page</p>"
VARIANTS = ("fetch+header", "beacon+text", "beacon+blob", "fetch+text", "beacon+json")
WAIT_S = 4.0

# What the page installs: on `pagehide` (not a bfcache one) it sends the variant's request, once.
INSTALL_JS = """
([variant, url, token]) => {
  const body = JSON.stringify({token});
  window.addEventListener('pagehide', (event) => {
    if (event.persisted) return;
    if (variant === 'fetch+header') {
      fetch(url, {method: 'POST', keepalive: true, headers: {Authorization: 'Bearer ' + token}});
    } else if (variant === 'beacon+text') {
      navigator.sendBeacon(url, body);
    } else if (variant === 'beacon+blob') {
      navigator.sendBeacon(url, new Blob([body], {type: 'text/plain;charset=UTF-8'}));
    } else if (variant === 'fetch+text') {
      fetch(url, {method: 'POST', keepalive: true, headers: {'Content-Type': 'text/plain;charset=UTF-8'}, body});
    } else if (variant === 'beacon+json') {
      navigator.sendBeacon(url, new Blob([body], {type: 'application/json'}));
    }
  });
}
"""

# The page makes its lobby with the session it is given (the backend lets one address sign in as a guest 30 times an
# hour, and a run makes more tabs than that; a player's tab has one session too).
MAKE_LOBBY_JS = """
async ([backend, token]) => {
  const lobby = await (await fetch(backend + '/lobbies', {method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + token}, body: '{}'})).json();
  return {token, id: lobby.id, code: lobby.code};
}
"""


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
        "LOG_LEVEL": "warn",
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


def delaying_proxy(target: str, delay_ms: int) -> tuple[http.server.ThreadingHTTPServer, str]:
    """A proxy on a free port that holds each request `delay_ms` before sending it on (and answers with CORS intact)."""
    upstream = urllib.parse.urlparse(target)

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def handle_any(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else None
            time.sleep(delay_ms / 1000)
            connection = http.client.HTTPConnection(upstream.hostname, upstream.port, timeout=10)
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")}
            connection.request(self.command, self.path, body=body, headers=headers)
            answer = connection.getresponse()
            data = answer.read()
            self.send_response(answer.status)
            for key, value in answer.getheaders():
                if key.lower() not in ("transfer-encoding", "connection", "content-length"):
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            connection.close()

        do_GET = do_POST = do_PUT = do_OPTIONS = handle_any

        def log_message(self, *_args) -> None:
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", free_port()), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


class PageHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        body = PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args) -> None:
        pass


def guest(backend: str) -> str:
    request = urllib.request.Request(
        f"{backend}/auth/guest", data=b"{}", headers={"Content-Type": "application/json"}, method="POST"
    )
    return json.loads(urllib.request.urlopen(request, timeout=5).read())["token"]


def lobby_alive(backend: str, observer_token: str, lobby_id: str) -> bool:
    """Whether the lobby still answers (a stranger cannot read it: 403 `not_member` means it exists, 404 means gone)."""
    request = urllib.request.Request(
        f"{backend}/lobbies/{lobby_id}", headers={"Authorization": f"Bearer {observer_token}"}
    )
    try:
        urllib.request.urlopen(request, timeout=3).read()
        return True
    except urllib.error.HTTPError as error:
        return error.code != 404


def one_run(browser: Browser, backend: str, real: str, observer_token: str, token: str, variant: str) -> float | None:
    """Seconds from closing the tab to the lobby being gone, or None when it was still there after WAIT_S."""
    context = browser.new_context()
    page = context.new_page()
    page.goto(f"http://127.0.0.1:{PAGE_PORT}/")
    made = page.evaluate(MAKE_LOBBY_JS, [backend, token])
    page.evaluate(INSTALL_JS, [variant, f"{backend}/lobbies/{made['id']}/page-closed", made["token"]])
    assert lobby_alive(real, observer_token, made["id"]), "the lobby must exist before the close"
    started = time.monotonic()
    page.close()
    gone: float | None = None
    while time.monotonic() - started < WAIT_S:
        if not lobby_alive(real, observer_token, made["id"]):
            gone = time.monotonic() - started
            break
        time.sleep(0.02)
    context.close()
    return gone


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=Path)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--browsers", default="chromium,firefox,webkit")
    parser.add_argument("--delay-ms", type=int, default=0)
    parser.add_argument(
        "--backend",
        help="a deployed backend (its CORS_ORIGINS must name http://127.0.0.1:8097) instead of a local one: real latency",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PAGE_PORT), PageHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    backend_process, real_backend = (None, args.backend.rstrip("/")) if args.backend else start_backend()
    proxy = None
    backend = real_backend
    if args.delay_ms > 0:
        proxy, backend = delaying_proxy(real_backend, args.delay_ms)
    results: dict[str, dict[str, dict]] = {}
    try:
        observer = guest(real_backend)
        with sync_playwright() as p:
            for name in args.browsers.split(","):
                launcher = getattr(p, name)
                options: dict = {}
                if name == "chromium":
                    options["args"] = smoke.mute_args()
                if name == "firefox":
                    options["firefox_user_prefs"] = smoke.mute_firefox_prefs()
                browser = launcher.launch(**options)
                token = guest(real_backend)
                results[name] = {"version": {"v": browser.version}}
                for variant in VARIANTS:
                    times = [
                        one_run(browser, backend, real_backend, observer, token, variant) for _ in range(args.runs)
                    ]
                    arrived = [t for t in times if t is not None]
                    results[name][variant] = {
                        "arrived": len(arrived),
                        "runs": args.runs,
                        "seconds": [round(t, 3) if t is not None else None for t in times],
                    }
                    print(
                        f"{name:9} {variant:13} arrived {len(arrived)}/{args.runs}  {results[name][variant]['seconds']}"
                    )
                browser.close()
    finally:
        if backend_process is not None:
            backend_process.terminate()
        server.shutdown()
        if proxy is not None:
            proxy.shutdown()
    (args.out / "transport.json").write_text(json.dumps(results, indent=2))
    bad = [name for name, row in results.items() if row["beacon+text"]["arrived"] != row["beacon+text"]["runs"]]
    if bad:
        print(f"FAIL: beacon+text did not arrive in every run in {bad}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
