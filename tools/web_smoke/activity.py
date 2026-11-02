"""The web build loaded the way a Discord Activity loads it, in headless Chromium, without Discord.

A local HTTPS server stands in for `<id>.discordsays.com`: the page and its files come from the web build, `/api/...`
goes to the platform backend with the prefix kept (Discord forwards it as it is), the Discord bridge is replaced by a
stub (there is no Discord client to sign in with, so the game signs in as a guest, as it does when Discord refuses),
and the API answers can be compressed the way Discord's proxy does it. The run opens the Activity's address
(`?frame_id=...&instance_id=...`), waits for the main menu with the voice channel's night already made, presses Play
together and checks it shows that same room code. It fails when the Activity opens on Play together, when the room could
not be made, or when it shows an error instead.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 --with cryptography python tools/web_smoke/activity.py <web folder or URL> <backend https address> <out folder>

`--encoding gzip` (default), `identity` and `chunked-gzip` choose how the API answers travel. Before `HttpJson` set
`accept_gzip = false`, a gzip answer made every call fail with "Could not reach the game's servers" (Godot decoded a body
the browser had decoded already). The WebSocket to the game server is not covered: it needs a Discord proxy.

`--embed plain|gamepad|denied` loads the Activity in an iframe of another origin (as Discord's client does) without an
`allow` attribute, with `allow="gamepad"`, or with the Activity's own answer saying `Permissions-Policy: gamepad=()`;
`--pad` gives the page a virtual gamepad. The run prints what the page's gamepad probe reports and the line the Play
together screen shows (`GamepadProbe`). A pointer lock is stubbed: the run never takes the real mouse.

`--embed clipboard-denied|clipboard` is the same for the clipboard: the Activity answering `Permissions-Policy:
clipboard-read=(), clipboard-write=()`, or an iframe with `allow="clipboard-read; clipboard-write"` and both
permissions granted to its origin (`plain` has no allow attribute, which already denies it, as Discord's frame may).
`--clipboard` then runs the clipboard check instead of waiting for a night: it reads what the frame's clipboard API,
`execCommand` and the policy answer, puts a code on the clipboard of the page around the frame, presses Ctrl+V in the
Play together code field (the field must hold the code), makes a night, presses Share in Discord (the stub bridge must
get the code) and Copy the code (the clipboard must hold the night's code; when a button cannot copy, the screen must
say so and Ctrl+C must), and prints the page's clipboard line. `--exec-refused` makes `execCommand` refuse too, so
only Ctrl+C is left. With `--embed none` (a plain tab) it checks the page is left alone: no clipboard layer, and the
engine's own copy puts the code on the clipboard. It exits 1 when a check fails. It needs the headless shell (the
default): its clipboard lives in the browser, so the run never touches the person's own.
"""

from __future__ import annotations

import argparse
import datetime
import gzip
import json
import ssl
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

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
    b"window.deadnightDiscord = {ready: true, code: '', error: 'no Discord client here', instanceId: 'emu-1',"
    b" canShare: true, share: (message, customId) => { window.deadnightShared = {message, customId};"
    b" return Promise.resolve(true); }};"
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


class Driver:
    """The page's keyboard and mouse with the Activity frame's game probe: what `rooms` and `smoke` call on a page."""

    def __init__(self, page: Page, frame) -> None:
        self.keyboard = page.keyboard
        self.mouse = page.mouse
        self.wait_for_timeout = page.wait_for_timeout
        self.evaluate = frame.evaluate


def make_handler(
    web: str,
    backend: str,
    encoding: str,
    log: list[str],
    embed: str,
    activity_url: str,
    parent_focus: bool = False,
    fake_start: bool = False,
) -> type[BaseHTTPRequestHandler]:
    cache: dict[str, tuple[int, str, bytes]] = {}
    made: dict = {}  # the lobby the backend just made, for `fake_start`

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
                allow = {"gamepad": ' allow="gamepad"', "clipboard": ' allow="clipboard-read; clipboard-write"'}.get(
                    embed, ""
                )
                # A text box beside the frame that takes the keyboard focus back every 0.7 s, as a client that keeps it would.
                chat = '<input id="chat" autofocus style="display:block;margin:4px">' if parent_focus else ""
                page = (
                    f'<!doctype html><body style="margin:0"><iframe src="{activity_url}" width="1280" height="720"{allow}>'
                    f"</iframe>{chat}<script>window.onload=function(){{var c=document.getElementById('chat');if(c)setInterval(function(){{c.focus()}},700)}}</script>"
                )
                return self.reply(200, "text/html", page.encode(), parent=True)
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
            if fake_start and self.path.endswith("/start") and made:
                # The clipboard check needs a night's code, not a game server: starting one would use up the live
                # backend's servers for every other player. The lobby is answered as started, with its own code.
                status, answer_headers = 200, {"content-type": "application/json"}
                content = json.dumps({**made, "state": "started"}).encode()
            else:
                status, answer_headers, content = fetch(
                    backend + self.path, data=body, headers=headers, method=self.command
                )
                if fake_start and self.path.split("?")[0].endswith("/lobbies") and status < 300:
                    made.update(json.loads(content))
            kind = answer_headers.get("content-type", "application/json")
            packed = encoding != "identity" and "gzip" in self.headers.get("accept-encoding", "")
            if packed:
                content = gzip.compress(content)
            log.append(
                f"{self.command} {self.path.split('?')[0]} -> {status}, {len(content)} bytes{', gzip' if packed else ''}"
            )
            self.reply(status, kind, content, "gzip" if packed else None, chunked=encoding == "chunked-gzip")

        def reply(
            self,
            status: int,
            kind: str,
            content: bytes,
            encoding_name: str | None = None,
            chunked: bool = False,
            parent: bool = False,
        ):
            self.send_response(status)
            self.send_header("content-type", kind)
            if embed == "denied" and kind == "text/html":
                self.send_header("permissions-policy", "gamepad=()")
            if embed == "clipboard-denied" and kind == "text/html" and not parent:
                self.send_header("permissions-policy", "clipboard-read=(), clipboard-write=()")
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


# What the frame's clipboard can do, asked of the browser itself (after a click, which is the user gesture).
CLIPBOARD_CAPS = """async () => {
  const r = {iframe: window.top !== window};
  const policy = document.permissionsPolicy || document.featurePolicy;
  for (const name of ['clipboard-read', 'clipboard-write']) {
    try { r['policy ' + name] = policy ? policy.allowsFeature(name) : null; } catch (e) { r['policy ' + name] = e.name; }
    try { r['permission ' + name] = (await navigator.permissions.query({name})).state; } catch (e) { r['permission ' + name] = e.name; }
  }
  try { await navigator.clipboard.writeText('x'); r.writeText = 'ok'; } catch (e) { r.writeText = e.name; }
  try { await navigator.clipboard.readText(); r.readText = 'ok'; } catch (e) { r.readText = e.name; }
  try {
    const box = document.createElement('textarea'); box.value = 'x'; document.body.appendChild(box); box.select();
    r.execCommand = document.execCommand('copy') ? 'ok' : 'refused'; box.remove();
  } catch (e) { r.execCommand = e.name; }
  return r;
}"""
# Counts what reaches the page when Ctrl+V is pressed: the key, whether the engine ate it, and the paste event.
CLIPBOARD_SPY = """window.deadnightSpy = {ctrl_v: 0, ctrl_v_eaten: 0, paste: 0, copy: 0};
addEventListener('keydown', e => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'v') {
  deadnightSpy.ctrl_v++; setTimeout(() => { if (e.defaultPrevented) deadnightSpy.ctrl_v_eaten++; }, 0); } });
addEventListener('paste', () => deadnightSpy.paste++, true);
addEventListener('copy', () => deadnightSpy.copy++, true);"""
PASTED = "QZXW2345"


def hold_keys(page, *keys: str) -> None:
    """Chords like Ctrl+V: the modifier down, the last key held a few frames."""
    for key in keys[:-1]:
        page.keyboard.down(key)
    smoke.press(page, keys[-1])
    for key in reversed(keys[:-1]):
        page.keyboard.up(key)


def clipboard_flow(page, frame) -> tuple[list[str], bool]:
    """From the main menu to Play together, then the clipboard checks of `--clipboard`; the lines and whether both held."""
    lines: list[str] = []
    rooms.wait_for(frame, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)  # the user gesture, and the keyboard for the canvas
    page.wait_for_timeout(2500)
    smoke.menu_item(Driver(page, frame), "Play")
    smoke.press(page, "Enter")
    rooms.wait_for(frame, "the Play together screen", lambda s: s.get("screen") == "together_screen", 30)
    page.wait_for_timeout(1500)
    page.mouse.click(5, 5)
    tab = frame is page  # no iframe: a plain browser tab
    layer = frame.evaluate("typeof window.deadnightClipboard")
    lines.append(f"the clipboard layer in {'a tab' if tab else 'the frame'}: {layer}")
    caps = frame.evaluate(CLIPBOARD_CAPS)
    lines.append(f"the frame's clipboard: {caps}")
    page.mouse.click(5, 5)  # execCommand took the focus into a text box: back to the canvas
    page.wait_for_timeout(500)
    # The page around the frame writes the clipboard (it may: the permission was granted to its origin).
    page.evaluate(f"navigator.clipboard.writeText('{PASTED}')")
    smoke.press(page, "ArrowDown")  # Quick join -> Create a night
    smoke.press(page, "ArrowDown")  # -> the code field
    page.wait_for_timeout(500)
    hold_keys(page, "Control", "v")
    page.wait_for_timeout(1500)
    state = rooms.read_probe(frame)
    field = state.get("code_text", "")
    spy = frame.evaluate("window.deadnightSpy")
    lines.append(f"Ctrl+V reached the frame: {spy}")
    pasted = field == PASTED
    if tab:
        # A tab keeps the engine's own paste (it reads the clipboard through the API, and the first Ctrl+V gets the old
        # text): reported, not held to the code. What must hold is that the page was left alone.
        lines.append(f"paste in a tab (the engine's own, unchanged): the code field holds {field!r}")
        pasted = layer == "undefined"
    else:
        lines.append(f"paste: the code field holds {field!r}, wanted {PASTED!r}: {'ok' if pasted else 'FAILED'}")
    smoke.press(page, "ArrowUp")  # the code field -> Create a night
    smoke.press(page, "Enter")
    state = rooms.wait_for(frame, "a night's code", lambda s: bool(s.get("room_code")), 60)
    code = state["room_code"]
    page.wait_for_timeout(1500)
    for _ in range(3):
        smoke.press(page, "ArrowDown")  # Play -> Copy the link -> Copy the code -> Share in Discord
    smoke.press(page, "Enter")
    page.wait_for_timeout(500)
    shared = frame.evaluate("window.deadnightShared || null")
    sent = tab or (bool(shared) and code in shared.get("message", ""))
    lines.append(f"share in Discord: the SDK got {shared}: {'ok' if sent else 'FAILED'}")
    smoke.press(page, "ArrowUp")  # -> Copy the code
    page.evaluate("navigator.clipboard.writeText('before')")
    smoke.press(page, "Enter")
    page.wait_for_timeout(1500)
    state = rooms.read_probe(frame)
    held = page.evaluate("navigator.clipboard.readText()")
    status = str(state.get("room_status", ""))
    lines.append(f"the screen says {status!r}")
    copied = held == code
    if copied:
        lines.append(f"copy by the button: the clipboard holds {held!r}, the night's code: ok")
    else:
        # The button could not copy: the screen must not say it did, and must show the code selected for Ctrl+C.
        honest = "copied" not in status.lower() and "Ctrl+C" in status
        lines.append(f"copy by the button failed (the clipboard holds {held!r}); the screen says so: {honest}")
        page.evaluate("navigator.clipboard.writeText('before')")
        hold_keys(page, "Control", "c")
        page.wait_for_timeout(1000)
        held = page.evaluate("navigator.clipboard.readText()")
        copied = honest and held == code
        lines.append(f"copy by Ctrl+C: the clipboard holds {held!r}, wanted {code!r}: {'ok' if copied else 'FAILED'}")
    lines.append(f"the page's clipboard line: {state.get('clipboard', '(none)')} ({state.get('clipboard_detail', '')})")
    return lines, pasted and copied and sent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's https address")
    parser.add_argument("out", type=Path)
    parser.add_argument("--encoding", choices=["gzip", "identity", "chunked-gzip"], default="gzip")
    parser.add_argument(
        "--embed",
        choices=["none", "plain", "gamepad", "denied", "clipboard-denied", "clipboard"],
        default="none",
        help="load the Activity in an iframe of another origin: plain (no allow attribute), with allow=gamepad, or denied"
        " (the Activity's own answer says `Permissions-Policy: gamepad=()`, as a host that blocks it would)",
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="a real window (run it under `gds quiet`): headless Chromium fakes the focus",
    )
    parser.add_argument(
        "--parent-focus",
        action="store_true",
        help="the parent page keeps the focus in a text box, then the run clicks in the frame and reports the focus each time",
    )
    parser.add_argument(
        "--clipboard",
        action="store_true",
        help="check copy and paste in the Activity (the headless shell only) instead of waiting for a night",
    )
    parser.add_argument(
        "--exec-refused",
        action="store_true",
        help="with --clipboard: the frame's `document.execCommand` refuses too, so only a native Ctrl+C can copy",
    )
    parser.add_argument("--pad", action="store_true", help="give the page a virtual gamepad (navigator.getGamepads)")
    parser.add_argument("--seconds", type=float, default=120.0, help="how long to wait for the night")
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    log: list[str] = []
    stages: list[str] = []
    console: list[str] = []
    # One night for each run: a voice channel's night holds four, and earlier runs sit in the one of an old instance.
    instance = f"emu-{int(time.time())}"
    # The clipboard check starts on the main menu, as a player who made a night himself does: no instance to join.
    instance_part = "" if args.clipboard else f"&instance_id={instance}"
    activity_url = f"https://{HOST}/?frame_id=1{instance_part}&guild_id=1&channel_id=1"
    with tempfile.TemporaryDirectory() as folder:
        cert, key = self_signed(Path(folder))
        server = ThreadingHTTPServer(
            ("127.0.0.1", PORT),
            make_handler(
                args.web,
                args.backend.rstrip("/"),
                args.encoding,
                log,
                args.embed,
                activity_url,
                args.parent_focus,
                args.clipboard,
            ),
        )
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert), str(key))
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        flags = [f"--host-resolver-rules=MAP {HOST} 127.0.0.1:{PORT}, MAP {PARENT} 127.0.0.1:{PORT}"]
        with sync_playwright() as p:
            if args.gpu:
                browser = p.chromium.launch(channel="chrome", headless=not args.headed, args=flags + smoke.mute_args())
            else:
                browser = p.chromium.launch(
                    headless=not args.headed, args=smoke.SOFTWARE_GL + flags + smoke.mute_args()
                )
            browser_context = browser.new_context(viewport=smoke.VIEWPORT, ignore_https_errors=True)
            # Never take the real mouse: a pointer lock in headless Chromium on Windows clips the person's cursor.
            browser_context.add_init_script(NO_POINTER_LOCK)
            if args.pad:
                browser_context.add_init_script(VIRTUAL_PAD)
            if args.clipboard:
                if args.gpu or args.headed:
                    raise SystemExit("--clipboard needs the headless shell (its clipboard is the browser's own)")
                browser_context.add_init_script(CLIPBOARD_SPY)
                if args.exec_refused:
                    browser_context.add_init_script("document.execCommand = () => false;")
                # The page around the frame may use the clipboard; the Activity's origin is granted it only for `clipboard`.
                browser_context.grant_permissions(["clipboard-read", "clipboard-write"], origin=f"https://{PARENT}")
                if args.embed in ("clipboard", "none"):
                    browser_context.grant_permissions(["clipboard-read", "clipboard-write"], origin=f"https://{HOST}")
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
            if args.clipboard:
                lines, ok = clipboard_flow(page, frame)
                page.screenshot(path=args.out / f"clipboard_{args.embed}.png")
                browser.close()
                server.shutdown()
                (args.out / "console.txt").write_text(chr(10).join(console), encoding="utf-8")
                print(chr(10).join(log + lines))
                print(f"clipboard ({args.embed}): {'both held' if ok else 'FAILED'}")
                return 0 if ok else 1
            driver = Driver(page, frame)
            deadline = time.monotonic() + args.seconds
            state: dict = {}
            failed = ""
            # The Activity opens on the main menu with the voice channel's night already made (#495); Play together
            # then shows that same room.
            menu_code = ""
            while time.monotonic() < deadline:
                state = rooms.read_probe(frame)
                if state.get("screen") == "together_screen":
                    failed = "the Activity opened on Play together instead of the main menu"
                    break
                if state.get("screen") == "main_menu" and state.get("activity_room") == "failed":
                    failed = "the room could not be made ready on the menu"
                    break
                if state.get("screen") == "main_menu" and state.get("activity_room") == "ready":
                    menu_code = str(state.get("activity_code", ""))
                    break
                time.sleep(1)
            if menu_code:
                print(f"menu first: the main menu is up with room {menu_code} ready")
                page.wait_for_timeout(1500)
                page.screenshot(path=args.out / "activity_menu_first.png")
                rooms.to_together(driver)
                waited_until = time.monotonic() + 60
                while time.monotonic() < waited_until:
                    state = rooms.read_probe(frame)
                    if state.get("room_code"):
                        break
                    time.sleep(0.5)
                if state.get("room_code") != menu_code:
                    failed = f"Play together showed room {state.get('room_code')!r}, the menu had made {menu_code!r}"
                    state = {}
            page.wait_for_timeout(2000)
            if args.parent_focus and args.embed != "none":
                probe = "window.deadnightGamepad ? window.deadnightGamepad() : ''"
                stages.append(
                    f"before a click: top has focus {page.evaluate('document.hasFocus()')}, frame {frame.evaluate(probe)}"
                )
                page.mouse.click(100, 360)  # the empty side of the Activity's frame (CDP input: the real cursor stays)
                page.wait_for_timeout(1500)
                stages.append(
                    f"after a click in the frame: top has focus {page.evaluate('document.hasFocus()')}, frame {frame.evaluate(probe)}"
                )
                page.screenshot(full_page=True, path=args.out / "activity_after_click_without_focus.png")
                stages.append(
                    f"line: {rooms.read_probe(frame).get('gamepad', '')}"
                    f" (hint on every screen shown: {rooms.read_probe(frame).get('controller_hint')})"
                )
            gamepad = frame.evaluate("window.deadnightGamepad ? window.deadnightGamepad() : ''")
            note = rooms.read_probe(frame).get("gamepad", "")
            page.screenshot(
                full_page=True, path=args.out / f"activity_{args.encoding}_{args.embed}{'_pad' if args.pad else ''}.png"
            )
            browser.close()
        server.shutdown()
    (args.out / "console.txt").write_text("\n".join(console), encoding="utf-8")
    print("\n".join(log))
    print(chr(10).join(stages))
    print(f"gamepad page report: {gamepad}\ngamepad note: {note or '(none)'}")
    if state.get("room_code"):
        print(f"{args.encoding}: the Activity is in its night (room {state['room_code']})")
        return 0
    print(f"{args.encoding}: the Activity did not get a night: {failed or state}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
