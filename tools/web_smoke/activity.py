"""The web build loaded the way a Discord Activity loads it, in headless Chromium, without Discord.

A local HTTPS server stands in for `<id>.discordsays.com`: the page and its files come from the web build, `/api/...`
goes to the platform backend with the prefix kept (Discord forwards it as it is), the Discord bridge is replaced by a
stub (there is no Discord client to sign in with, so the game signs in as a guest, as it does when Discord refuses),
and the API answers can be compressed the way Discord's proxy does it. The run opens the Activity's address
(`?frame_id=...&instance_id=...`), waits for the Play together screen to land in a night and fails when it shows an
error instead.

    uv run --with playwright==1.64.1 --with cryptography python tools/web_smoke/activity.py <web folder or URL> <backend https address> <out folder>

`--encoding gzip` (default), `identity` and `chunked-gzip` choose how the API answers travel. Before `HttpJson` set
`accept_gzip = false`, a gzip answer made every call fail with "Could not reach the game's servers" (Godot decoded a body
the browser had decoded already). The WebSocket to the game server is not covered: it needs a Discord proxy.

`--embed plain|gamepad|denied` loads the Activity in an iframe of another origin (as Discord's client does) without an
`allow` attribute, with `allow="gamepad"`, or with the Activity's own answer saying `Permissions-Policy: gamepad=()`;
`--pad` gives the page a virtual gamepad. The run prints what the page's gamepad probe reports and the line the Play
together screen shows (`GamepadProbe`). A pointer lock is stubbed: the run never takes the real mouse.
"""

from __future__ import annotations

import argparse
import datetime
import gzip
import ssl
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import rooms
import smoke

HOST = "123456.discordsays.com"
# The page around the Activity (Discord's client): another origin, as the iframe the browser client makes.
PARENT = "discord-client.example"
PORT = 8443
KINDS = {
    ".wasm": "application/wasm",
    ".js": "text/javascript",
    ".html": "text/html",
    ".png": "image/png",
    ".pck": "application/octet-stream",
}
# The page asks for the mouse when a night starts; here nothing is locked.
NO_POINTER_LOCK = "Element.prototype.requestPointerLock = function () { return Promise.resolve(); };"
# A pad the page can list, as a browser with a controller plugged in would.
VIRTUAL_PAD = (
    "const pad = {id: 'Virtual pad', index: 0, connected: true, mapping: 'standard', timestamp: 1,"
    " axes: [0, 0, 0, 0], buttons: Array.from({length: 17}, () => ({pressed: false, touched: false, value: 0}))};"
    "Object.defineProperty(navigator, 'getGamepads', {value: () => [pad, null, null, null]});"
)
# What the bridge leaves on the page when it cannot sign in: the game then plays as a guest.
BRIDGE_STUB = (
    b"window.deadnightDiscord = {ready: true, code: '', error: 'no Discord client here', instanceId: 'emu-1'};"
)


def self_signed(folder: Path) -> tuple[Path, Path]:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, HOST)])
    now = datetime.datetime.now(datetime.UTC)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=1))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(HOST), x509.DNSName(PARENT)]), critical=False)
        .sign(key, hashes.SHA256())
    )
    key_file, cert_file = folder / "key.pem", folder / "cert.pem"
    key_file.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()
        )
    )
    cert_file.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    return cert_file, key_file


def make_handler(
    web: str, backend: str, encoding: str, log: list[str], embed: str, activity_url: str
) -> type[BaseHTTPRequestHandler]:
    cache: dict[str, tuple[int, str, bytes]] = {}

    def fetch(url: str, **kwargs) -> tuple[int, dict, bytes]:
        request = urllib.request.Request(url, **kwargs)
        try:
            response = urllib.request.urlopen(request, timeout=90)
        except urllib.error.HTTPError as error:
            response = error
        return response.status if hasattr(response, "status") else response.code, response.headers, response.read()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args) -> None:
            pass

        def do_GET(self) -> None:
            self.serve()

        do_POST = do_OPTIONS = do_GET

        def serve(self) -> None:
            if self.headers.get("host", "").startswith(PARENT):
                allow = ' allow="gamepad"' if embed == "gamepad" else ""
                page = f'<!doctype html><body style="margin:0"><iframe src="{activity_url}" width="1280" height="720"{allow}></iframe>'
                return self.reply(200, "text/html", page.encode())
            size = int(self.headers.get("content-length") or 0)
            body = self.rfile.read(size) if size else None
            if self.path.startswith("/api"):
                return self.api(body)
            path = self.path.split("?")[0]
            if path.endswith("discord-bridge.js"):
                status, kind, content = 200, "text/javascript", BRIDGE_STUB
            else:
                if path not in cache:
                    if web.startswith("http"):
                        code, headers, content = fetch(
                            web.rstrip("/") + (path or "/"), headers={"accept-encoding": "identity"}
                        )
                        cache[path] = (code, headers.get("content-type", "application/octet-stream"), content)
                    else:
                        file = Path(web) / (path.lstrip("/") or "index.html")
                        cache[path] = (
                            (200, KINDS.get(file.suffix, "application/octet-stream"), file.read_bytes())
                            if file.is_file()
                            else (404, "text/plain", b"")
                        )
                status, kind, content = cache[path]
            self.reply(status, kind, content)

        def api(self, body: bytes | None) -> None:
            wanted = ("content-type", "authorization")
            headers = {k: v for k, v in self.headers.items() if k.lower() in wanted}
            status, answer_headers, content = fetch(
                backend + self.path, data=body, headers=headers, method=self.command
            )
            kind = answer_headers.get("content-type", "application/json")
            packed = encoding != "identity" and "gzip" in self.headers.get("accept-encoding", "")
            if packed:
                content = gzip.compress(content)
            log.append(
                f"{self.command} {self.path.split('?')[0]} -> {status}, {len(content)} bytes{', gzip' if packed else ''}"
            )
            self.reply(status, kind, content, "gzip" if packed else None, chunked=encoding == "chunked-gzip")

        def reply(
            self, status: int, kind: str, content: bytes, encoding_name: str | None = None, chunked: bool = False
        ):
            self.send_response(status)
            self.send_header("content-type", kind)
            if embed == "denied" and kind == "text/html":
                self.send_header("permissions-policy", "gamepad=()")
            if encoding_name:
                self.send_header("content-encoding", encoding_name)
            if chunked:
                self.send_header("transfer-encoding", "chunked")
                self.end_headers()
                self.wfile.write(f"{len(content):x}\r\n".encode() + content + b"\r\n0\r\n\r\n")
            else:
                self.send_header("content-length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's https address")
    parser.add_argument("out", type=Path)
    parser.add_argument("--encoding", choices=["gzip", "identity", "chunked-gzip"], default="gzip")
    parser.add_argument(
        "--embed",
        choices=["none", "plain", "gamepad", "denied"],
        default="none",
        help="load the Activity in an iframe of another origin: plain (no allow attribute), with allow=gamepad, or denied"
        " (the Activity's own answer says `Permissions-Policy: gamepad=()`, as a host that blocks it would)",
    )
    parser.add_argument("--pad", action="store_true", help="give the page a virtual gamepad (navigator.getGamepads)")
    parser.add_argument("--seconds", type=float, default=120.0, help="how long to wait for the night")
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    log: list[str] = []
    console: list[str] = []
    # One night for each run: a voice channel's night holds four, and earlier runs sit in the one of an old instance.
    instance = f"emu-{int(time.time())}"
    activity_url = f"https://{HOST}/?frame_id=1&instance_id={instance}&guild_id=1&channel_id=1"
    with tempfile.TemporaryDirectory() as folder:
        cert, key = self_signed(Path(folder))
        server = ThreadingHTTPServer(
            ("127.0.0.1", PORT),
            make_handler(args.web, args.backend.rstrip("/"), args.encoding, log, args.embed, activity_url),
        )
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert), str(key))
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        flags = [f"--host-resolver-rules=MAP {HOST} 127.0.0.1:{PORT}, MAP {PARENT} 127.0.0.1:{PORT}"]
        with sync_playwright() as p:
            if args.gpu:
                browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
            else:
                browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL + flags)
            browser_context = browser.new_context(viewport=smoke.VIEWPORT, ignore_https_errors=True)
            # Never take the real mouse: a pointer lock in headless Chromium on Windows clips the person's cursor.
            browser_context.add_init_script(NO_POINTER_LOCK)
            if args.pad:
                browser_context.add_init_script(VIRTUAL_PAD)
            page = browser_context.new_page()
            page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))
            if args.embed == "none":
                page.goto(activity_url, wait_until="commit")
                frame = page
            else:
                page.goto(f"https://{PARENT}/", wait_until="commit")
                waited = time.monotonic()
                while len(page.frames) < 2:
                    if time.monotonic() - waited > 30:
                        raise SystemExit(f"the parent page never showed the Activity's frame: {page.content()[:300]!r}")
                    page.wait_for_timeout(200)  # lets Playwright see the frame
                frame = page.frames[1]
            deadline = time.monotonic() + args.seconds
            state: dict = {}
            failed = ""
            while time.monotonic() < deadline:
                state = rooms.read_probe(frame)
                if state.get("room_code"):
                    break
                status = str(state.get("room_status", ""))
                if state.get("screen") == "together_screen" and status.startswith("Could not"):
                    failed = status
                    break
                time.sleep(1)
            page.wait_for_timeout(2000)
            gamepad = frame.evaluate("window.deadnightGamepad ? window.deadnightGamepad() : ''")
            note = rooms.read_probe(frame).get("gamepad", "")
            page.screenshot(path=args.out / f"activity_{args.encoding}_{args.embed}{'_pad' if args.pad else ''}.png")
            browser.close()
        server.shutdown()
    (args.out / "console.txt").write_text("\n".join(console), encoding="utf-8")
    print("\n".join(log))
    print(f"gamepad page report: {gamepad}\ngamepad note: {note or '(none)'}")
    if state.get("room_code"):
        print(f"{args.encoding}: the Activity is in its night (room {state['room_code']})")
        return 0
    print(f"{args.encoding}: the Activity did not get a night: {failed or state}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
