"""The web build loaded the way a Discord Activity loads it, in headless Chromium, without Discord.

A local HTTPS server stands in for `<id>.discordsays.com`: the page and its files come from the web build, `/api/...`
goes to the platform backend with the prefix kept (Discord forwards it as it is), the Discord bridge is replaced by a
stub (there is no Discord client to sign in with, so the game signs in as a guest, as it does when Discord refuses),
and the API answers can be compressed the way Discord's proxy does it. The run opens the Activity's address
(`?frame_id=...&instance_id=...`), waits for the main menu, signed in, presses Play together and checks that the screen
is the website's (the code field and the create button) and that the backend was asked for no lobby at all (#1178: the
instance id used to find or make the voice channel's lobby, so two players each got their own). It then presses Create a
night and checks that exactly one lobby is made, with a code. It fails when the Activity opens on Play together, when
any lobby is asked for before Create, or when it shows an error instead. `--website` runs the same steps as the
website (a plain host, no instance id) for the capture beside it: `together_activity.png` and `together_website.png`.

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
only Ctrl+C is left. With `--embed none` (a plain tab) the clipboard layer is the paste half only (Ctrl+V pastes the
clipboard's text on the first press, #534) and the engine's own copy puts the code on the clipboard. It exits 1 when a
check fails. It needs the headless shell (the
default): its clipboard lives in the browser, so the run never touches the person's own.

`--share --share-client shared|closed|refused|error|silent|unreadable` checks Share in Discord (#627). The Discord
bridge is replaced by a stub that runs the real `deploy/web/discord-share.js` on a stand-in for the SDK that answers
`shareLink` the way a client can: `shared` (the window sends after a while), `closed` (the player closes it),
`refused` (success false at once), `error` (the client rejects with its own `{code, message}`, as the SDK passes it
on), `silent` (no answer ever: a window may be up) and `unreadable` (a frame the SDK cannot parse: its promise never
settles). `--invite-fails` makes `openInviteDialog` fail too. The run makes a night, presses Share in Discord and reads
the lobby's sentence and probe line until the client has answered (6 s after the press): the hint to pick who to send
it to must show only while Discord has not refused, a refusal must say Discord opened nothing and point to Copy the
code, and the probe line must carry Discord's answer.

`--share --real-bridge [DIR]` runs the whole chain with nothing stubbed on the Activity's side (#627, which the stand-in
clients above passed while the real press failed: they faked Discord's answers and so never met the one refusal that
matters). DIR (default `deploy/web`) holds `discord-bridge.js` and `discord-share.js`; they are bundled with the real
`@discord/embedded-app-sdk` by esbuild at the versions of `deploy/web/Dockerfile`, as the web image builds them. The page
around the frame is `fake_discord_client.js`, a Discord client that refuses every command with RPC error 4006 ("Not
authenticated or invalid scope", the frame the real client sent) until the Activity has run `authenticate` with the access
token of its sign-in. The backend is a local one (`--local-backend`, DISCORD_MODE=stub: the code of AUTHORIZE is swapped
for a token). `--host-mode strict` expects the share to go through (SDK frames: AUTHORIZE, AUTHENTICATE, SHARE_LINK; the
lobby says it was sent); `reject-token` has the client refuse the token (4009) and `refuse-authorize` has it refuse the
sign-in (the game plays as a guest): both must end with the lobby saying the Activity is not signed in with Discord, with
Discord's 4006 and the sign-in state on the probe line. Pointed at the bridge of the commit before the fix, `strict`
fails with the maintainer's own line: `error rpc 4006: Not authenticated or invalid scope`.
"""

from __future__ import annotations

import argparse
import datetime
import gzip
import json
import os
import re
import secrets
import shutil
import socket
import ssl
import subprocess
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
import page_closing
import rooms
import smoke

HOST = "123456.discordsays.com"
# `--website`: a host that is not Discord's, so the game is the website's (`TogetherScreen.in_discord` is false).
WEBSITE_HOST = "play.example.test"
# The page around the Activity (Discord's client): another origin, as the iframe the browser client makes.
# `discord.com`: one of the origins the Embedded App SDK takes messages from (the name only resolves in this browser).
PARENT = "discord.com"
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
# What the bridge leaves on the page when it cannot sign in: the game then plays as a guest. The share half is the real
# `deploy/web/discord-share.js` on a stand-in for the SDK (`SHARE_CLIENTS`): the harness runs the code that ships.
SHARE_SOURCE = Path(__file__).resolve().parents[2] / "deploy" / "web" / "discord-share.js"
SHARE_CLIENTS = ("shared", "closed", "refused", "error", "silent", "unreadable")
HOST_MODES = ("strict", "reject-token", "refuse-authorize")
REPO = Path(__file__).resolve().parents[2]
FAKE_CLIENT = Path(__file__).with_name("fake_discord_client.js")
HOST_WINDOW_MS = 3000  # how long the fake client's share window stays open before it reports a send
BRIDGE_STUB = """
import {{ makeShare }} from "./discord-share.js";
const mode = {mode};
const STAND_IN_DELAY_MS = 6000; // the window is open this long before the player acts
const state = {{ ready: true, code: "", error: "no Discord client here", instanceId: "emu-1", guildId: "", canShare: true }};
window.deadnightDiscord = state;
const later = (ms, then) => new Promise((resolve, reject) => setTimeout(() => then(resolve, reject), ms));
const nothing = {{ success: false, didCopyLink: false, didSendMessage: false }};
const answers = {{
  shared: () => later(STAND_IN_DELAY_MS, (ok) => ok({{ success: true, didCopyLink: false, didSendMessage: true }})),
  closed: () => later(STAND_IN_DELAY_MS, (ok) => ok(nothing)),
  refused: () => Promise.resolve(nothing),
  // The SDK rejects with the client's own {{code, message}} object, not an Error.
  error: () => Promise.reject({{ code: 4002, message: "Invalid command: SHARE_LINK" }}),
  silent: () => new Promise(() => {{}}),
  // A reply the SDK cannot parse: it logs "Failed to parse" and the command's promise never settles. Only the
  // frame on the page's `message` events shows it.
  unreadable: () => {{
    const frame = [1, {{ cmd: "SHARE_LINK", evt: null, nonce: "n", data: {{ success: true }} }}];
    setTimeout(() => window.postMessage(frame, "*"), STAND_IN_DELAY_MS);
    return new Promise(() => {{}});
  }},
}};
const sdk = {{ commands: {{
  shareLink: (args) => {{ window.deadnightShared = {{ message: args.message, customId: args.custom_id }}; return answers[mode](); }},
  openInviteDialog: () => {{
    window.deadnightInvited = (window.deadnightInvited || 0) + 1;
    return {invite};
  }},
}} }};
makeShare(sdk, state);
"""


def bridge_stub(mode: str, invite_fails: bool) -> bytes:
    invite = 'Promise.reject({ code: 50013, message: "Missing Permissions" })' if invite_fails else "Promise.resolve()"
    return BRIDGE_STUB.format(mode=json.dumps(mode), invite=invite).encode()


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


def build_bridge(source: Path) -> bytes:
    """`discord-bridge.js` of `source` bundled with the real SDK, as `deploy/web/Dockerfile` does (same versions)."""
    dockerfile = (REPO / "deploy" / "web" / "Dockerfile").read_text(encoding="utf-8")
    versions = re.search(r"@discord/embedded-app-sdk@([\w.-]+) esbuild@([\w.-]+)", dockerfile)
    if not versions:
        raise SystemExit("deploy/web/Dockerfile no longer names the SDK and esbuild versions the harness bundles with")
    sdk, esbuild = versions.groups()
    work = Path(tempfile.gettempdir()) / f"deadnight-bridge-{sdk}-{esbuild}"
    work.mkdir(exist_ok=True)
    npm, npx = shutil.which("npm"), shutil.which("npx")
    if not npm or not npx:
        raise SystemExit("--real-bridge needs node (npm and npx on the PATH)")
    if not (work / "node_modules" / "@discord").is_dir():
        subprocess.run(
            [
                npm,
                "install",
                "--no-save",
                "--no-audit",
                "--no-fund",
                f"@discord/embedded-app-sdk@{sdk}",
                f"esbuild@{esbuild}",
            ],
            cwd=work,
            check=True,
            timeout=300,
        )
    for name in ("discord-bridge.js", "discord-share.js"):
        shutil.copyfile(source / name, work / name)
    out = work / "discord-bridge.out.js"
    subprocess.run(
        [
            npx,
            "--no-install",
            "esbuild",
            "discord-bridge.js",
            "--bundle",
            "--format=esm",
            "--target=es2022",
            f"--outfile={out.name}",
        ],
        cwd=work,
        check=True,
        timeout=120,
    )
    return out.read_bytes()


def preview_by_code(backend: str, code: str) -> dict:
    """What another player reads when they type `code` (a new guest, as on the website): the backend's preview."""

    def post(path: str, body: dict, token: str = "") -> dict:
        headers = {"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})}
        request = urllib.request.Request(
            backend.rstrip("/") + path, data=json.dumps(body).encode(), headers=headers, method="POST"
        )
        try:
            return json.loads(urllib.request.urlopen(request, timeout=30).read())
        except urllib.error.HTTPError as error:
            return {"error": error.code}

    guest = post("/auth/guest", {})
    return post("/lobbies/preview", {"code": code}, guest.get("token", ""))


def start_local_backend() -> tuple[subprocess.Popen, str]:
    """The platform backend (spikes/backend) on a free local port with the stub Discord sign-in: the code of the fake
    client's AUTHORIZE (`stub:<id>:<name>:...`) is swapped for the access token `stub-access-<id>`."""
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    env = {
        **os.environ,
        "DISCORD_MODE": "stub",
        "ALLOW_STUB_SIGN_IN": "1",
        "GUEST_SIGN_IN": "1",
        "SESSION_SECRET": secrets.token_hex(24),
        "TICKET_SECRET": secrets.token_hex(24),
        "GAME_SERVER_SECRET": secrets.token_hex(24),
        "HOST": "127.0.0.1",
        "PORT": str(port),
        "LOG_LEVEL": "warn",
    }
    env.pop("NODE_ENV", None)
    node = shutil.which("node")
    if not node:
        raise SystemExit("--local-backend needs node on the PATH")
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


def make_handler(
    web: str,
    backend: str,
    encoding: str,
    log: list[str],
    embed: str,
    activity_url: str,
    parent_focus: bool = False,
    fake_start: bool = False,
    share_client: str = "shared",
    invite_fails: bool = False,
    bridge_js: bytes | None = None,
    host_mode: str = "strict",
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

        do_POST = do_PUT = do_OPTIONS = do_GET

        def serve(self) -> None:
            if self.headers.get("host", "").startswith(PARENT):
                if self.path.startswith("/fake_discord_client.js"):
                    return self.reply(200, "text/javascript", FAKE_CLIENT.read_bytes(), parent=True)
                allow = {"gamepad": ' allow="gamepad"', "clipboard": ' allow="clipboard-read; clipboard-write"'}.get(
                    embed, ""
                )
                # A text box beside the frame that takes the keyboard focus back every 0.7 s, as a client that keeps it would.
                host = (
                    f"<script>window.discordHostOptions={json.dumps({'mode': host_mode, 'windowMs': HOST_WINDOW_MS})}</script>"
                    '<script src="/fake_discord_client.js"></script>'
                    if bridge_js is not None
                    else ""
                )
                chat = '<input id="chat" autofocus style="display:block;margin:4px">' if parent_focus else ""
                page = (
                    f'<!doctype html><body style="margin:0"><iframe src="{activity_url}" width="1280" height="720"{allow}>'
                    f"</iframe>{chat}{host}<script>window.onload=function(){{var c=document.getElementById('chat');if(c)setInterval(function(){{c.focus()}},700)}}</script>"
                )
                return self.reply(200, "text/html", page.encode(), parent=True)
            size = int(self.headers.get("content-length") or 0)
            body = self.rfile.read(size) if size else None
            if self.path.startswith("/api"):
                return self.api(body)
            path = self.path.split("?")[0]
            if path.endswith("discord-bridge.js"):
                content = bridge_js if bridge_js is not None else bridge_stub(share_client, invite_fails)
                status, kind = 200, "text/javascript"
            elif path.endswith("discord-share.js"):
                status, kind, content = 200, "text/javascript", SHARE_SOURCE.read_bytes()
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
                if status == 200 and path in ("", "/", "/index.html"):
                    # The test reads `window.deadnight`, which a player's page does not publish (#983).
                    content = content.replace(b"<head>", b"<head>" + smoke.PROBES_ON, 1)
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


def focus_on(page, frame, name: str, steps: int = 12) -> None:
    """Walks the keyboard focus to the control called `name`, which the probe reports as `focus`: Down, then Up, and at
    each stop a look to the right (two buttons share a row). Counting presses broke whenever a screen gained or lost a
    button."""

    def focused() -> str:
        page.wait_for_timeout(400)  # longer than the probe's period
        return str(rooms.read_probe(frame).get("focus", ""))

    seen = focused()
    for key in ("ArrowDown", "ArrowUp"):
        for _ in range(steps):
            if seen == name:
                return
            smoke.press(page, "ArrowRight")
            side = focused()
            if side == name:
                return
            if side != seen:
                smoke.press(page, "ArrowLeft")
                focused()
            smoke.press(page, key)
            seen = focused()
    raise TimeoutError(f"the keyboard never reached {name}; it is on {seen!r}")


def hold_keys(page, *keys: str) -> None:
    """Chords like Ctrl+V: the modifier down, the last key held a few frames."""
    for key in keys[:-1]:
        page.keyboard.down(key)
    smoke.press(page, keys[-1])
    for key in reversed(keys[:-1]):
        page.keyboard.up(key)


def start_together(page, frame) -> None:
    """From the main menu to the Play together screen, a click given (the user gesture, and the keyboard for the canvas)."""
    rooms.wait_for(frame, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)
    smoke.menu_item(Driver(page, frame), "Play")
    smoke.press(page, "Enter")
    rooms.wait_for(frame, "the Play together screen", lambda s: s.get("screen") == "together_screen", 30)
    page.wait_for_timeout(1500)
    page.mouse.click(5, 5)


def clipboard_flow(page, frame, out: Path) -> tuple[list[str], bool]:
    """From the main menu to Play together, then the clipboard checks of `--clipboard`; the lines and whether both held."""
    lines: list[str] = []
    start_together(page, frame)
    tab = frame is page  # no iframe: a plain browser tab
    layer = frame.evaluate("typeof window.deadnightClipboard")
    lines.append(f"the clipboard layer in {'a tab' if tab else 'the frame'}: {layer}")
    caps = frame.evaluate(CLIPBOARD_CAPS)
    lines.append(f"the frame's clipboard: {caps}")
    page.mouse.click(5, 5)  # execCommand took the focus into a text box: back to the canvas
    page.wait_for_timeout(500)
    # The page around the frame writes the clipboard (it may: the permission was granted to its origin).
    page.evaluate(f"navigator.clipboard.writeText('{PASTED}')")
    focus_on(page, frame, "Code")
    page.wait_for_timeout(500)
    hold_keys(page, "Control", "v")
    page.wait_for_timeout(1500)
    state = rooms.read_probe(frame)
    page.screenshot(path=out / f"paste_{'tab' if frame is page else 'frame'}.png")  # the code field after Ctrl+V
    field = state.get("code_text", "")
    spy = frame.evaluate("window.deadnightSpy")
    lines.append(f"Ctrl+V reached the frame: {spy}")
    pasted = field == PASTED
    where = "in a tab" if tab else "in the frame"
    lines.append(f"paste {where}: the code field holds {field!r}, wanted {PASTED!r}: {'ok' if pasted else 'FAILED'}")
    focus_on(page, frame, "CreateNight")
    smoke.press(page, "Enter")
    state = rooms.wait_for(frame, "a night's code", lambda s: bool(s.get("room_code")), 60)
    code = state["room_code"]
    page.wait_for_timeout(1500)
    shared = None
    if not tab:  # a tab has no Share in Discord button
        focus_on(page, frame, "ShareDiscord")
        smoke.press(page, "Enter")
        page.wait_for_timeout(500)
        shared = frame.evaluate("window.deadnightShared || null")
    sent = tab or (bool(shared) and code in shared.get("message", ""))
    lines.append(f"share in Discord: the SDK got {shared}: {'ok' if sent else 'FAILED'}")
    focus_on(page, frame, "CopyCode")
    page.evaluate("navigator.clipboard.writeText('before')")
    smoke.press(page, "Enter")
    page.wait_for_timeout(1500)
    state = rooms.read_probe(frame)
    held = page.evaluate("navigator.clipboard.readText()")
    # The lobby says it in its own note line under the standing line, which the next refresh rewrites.
    status = f"{state.get('room_status', '')} {state.get('lobby_note', '')}".strip()
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


HINT = "Pick who to send it to"


def share_flow(page, frame, out: Path, mode: str, invite_fails: bool) -> tuple[list[str], bool]:
    """Make a night, press Share in Discord and read the lobby until the stand-in client has answered (`--share`): what
    the lobby says and what its probe line quotes must follow what that client answered."""
    lines: list[str] = []
    start_together(page, frame)
    focus_on(page, frame, "CreateNight")
    smoke.press(page, "Enter")
    state = rooms.wait_for(frame, "a night's code", lambda s: bool(s.get("room_code")), 60)
    code = state["room_code"]
    page.wait_for_timeout(1500)
    focus_on(page, frame, "ShareDiscord")
    smoke.press(page, "Enter")
    # Every look at the lobby until the stand-in client has answered (or 8 s, for one that never does): its answers come
    # late (STAND_IN_DELAY_MS) so that a slow machine still sees the window open.
    seen: list[tuple[float, str, str]] = []
    started = time.monotonic()
    final = ("shared", "closed", "refused", "unreadable")
    while time.monotonic() - started < 8:
        state = rooms.read_probe(frame)
        # The lobby's own sentence under the button; a build without it says everything in the note line.
        says = state.get("share_says") or state.get("lobby_note", "")
        line = state.get("share_line", "")
        seen.append((time.monotonic() - started, says, line))
        if mode != "silent" and any(line.startswith(f"share: {verdict}") for verdict in final):
            break
        page.wait_for_timeout(250)
    for at, says, line in seen[:: max(1, len(seen) // 6)] + seen[-1:]:
        lines.append(f"after {at:.1f} s: the lobby says {says!r}; probe line {line!r}")
    page.screenshot(path=out / f"share_{mode}.png")
    shared = frame.evaluate("window.deadnightShared || null")
    lines.append(f"the SDK got {shared}; invite window asked {frame.evaluate('window.deadnightInvited || 0')} time(s)")
    failures: list[str] = []

    def check(ok: bool, what: str) -> None:
        lines.append(f"{what}: {'ok' if ok else 'FAILED'}")
        if not ok:
            failures.append(what)

    check(bool(shared) and code in shared.get("message", ""), "the SDK got the room's code")
    late, line_late = seen[-1][1], seen[-1][2]
    hint_any = any(HINT in look[1] for look in seen)
    hint_late = HINT in late
    # The looks while the client has been asked and has not answered: the hint belongs in each of them.
    open_looks = [look for look in seen if look[2].startswith("share: open")]
    hint_open = bool(open_looks) and all(HINT in look[1] for look in open_looks)
    check(HINT not in seen[0][1], "no hint to pick who to send it to before Discord has had a moment")
    if mode in ("refused", "error"):
        check(not hint_any, "no hint to pick who to send it to at any time after Discord refused")
        check(
            "did not open" in late and "Copy the code" in late,
            "the lobby says Discord opened nothing and points to Copy the code",
        )
        check(
            mode == "refused" or ("4002" in line_late and "Invalid command" in line_late),
            "the probe line quotes the client's error",
        )
        check("refused" in line_late, "the probe line says the verdict")
        wanted = "invite window: failed" if invite_fails else "invite window: opened"
        check(wanted in line_late, "the probe line says what the invite window did")
    elif mode == "silent":
        check(hint_open and hint_late, "the hint stays while Discord has not refused")
        check("open after" in line_late, "the probe line says the window may be open and no answer came")
    elif mode == "shared":
        check(hint_open, "the hint shows while the window is open")
        check("Sent" in late and not hint_late, "the lobby says it was sent when the window answered success")
        check("success=true" in line_late, "the probe line quotes the answer")
    elif mode == "closed":
        check(hint_open, "the hint shows while the window is open")
        check(
            "closed without sending" in late and "Sent" not in late, "the lobby says the window closed without sending"
        )
        check("success=false" in line_late, "the probe line quotes the answer")
    elif mode == "unreadable":
        check("could not be read" in late, "the lobby says the answer could not be read")
        check("Discord's frame" in line_late and "success" in line_late, "the probe line quotes the raw frame")
    return lines, not failures


SENT = "Sent through Discord."
NOT_SIGNED_IN = "not signed in with Discord"


def share_real_flow(page: Page, frame, out: Path, mode: str) -> tuple[list[str], bool]:
    """The Activity as Discord's client sees it (`--real-bridge`): from the main menu to a lobby made with Create a night,
    Share in Discord pressed once, and the commands the fake client received are read back from its page."""
    lines: list[str] = []
    rooms.wait_for(frame, "the main menu, ready", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    rooms.wait_for(frame, "the Activity signed in", lambda s: bool(s.get("signed_in")), 150)
    page.mouse.click(5, 5)
    page.wait_for_timeout(1500)
    rooms.to_together(Driver(page, frame))
    focus_on(page, frame, "CreateNight")
    smoke.press(page, "Enter")
    state = rooms.wait_for(
        frame, "the lobby with its code", lambda s: s.get("screen") == "lobby_screen" and bool(s.get("room_code")), 60
    )
    code = state["room_code"]
    page.wait_for_timeout(1500)
    # The host's lobby has the rules panel (a row of options for each rule), which the keyboard walks through first.
    focus_on(page, frame, "ShareDiscord", steps=40)
    smoke.press(page, "Enter")
    seen: list[tuple[float, str, str]] = []
    started = time.monotonic()
    final = ("shared", "closed", "refused", "unreadable")
    while time.monotonic() - started < 15:
        state = rooms.read_probe(frame)
        says = state.get("share_says") or state.get("lobby_note", "")
        line = state.get("share_line", "")
        seen.append((time.monotonic() - started, says, line))
        if any(line.startswith(f"share: {verdict}") for verdict in final) and "invite window: asking" not in line:
            break
        page.wait_for_timeout(250)
    for at, says, line in seen[:: max(1, len(seen) // 6)] + seen[-1:]:
        lines.append(f"after {at:.1f} s: the lobby says {says!r}; probe line {line!r}")
    page.screenshot(path=out / f"share_real_{mode}.png")
    host = page.evaluate("window.discordHost")
    sent = [c["cmd"] for c in host["commands"]]
    lines.append(
        f"Discord's client received {sent}; authenticated {host['authenticated']}; refusals {host['refusals']}"
    )
    lines.append(f"authorize asked for {host['authorizedScopes']}; invite window opened {host['invited']} time(s)")
    lines.append(f"commands (ms since the page opened): {[(c['cmd'], c['at']) for c in host['commands']]}")
    lines.append(
        f"the bridge's state: {frame.evaluate('JSON.stringify({...window.deadnightDiscord, code: !!(window.deadnightDiscord && window.deadnightDiscord.code)})')}"
    )
    failures: list[str] = []

    def check(ok: bool, what: str) -> None:
        lines.append(f"{what}: {'ok' if ok else 'FAILED'}")
        if not ok:
            failures.append(what)

    says_last, line_last = seen[-1][1], seen[-1][2]
    check("SHARE_LINK" in sent, "the Activity asked Discord's client for the share window")
    if mode == "strict":
        check(
            "AUTHENTICATE" in sent and sent.index("AUTHENTICATE") < sent.index("SHARE_LINK"),
            "the Activity authenticated before it asked for the share window",
        )
        check(host["refusals"] == 0, "Discord's client refused nothing")
        check(bool(host["shared"]) and code in host["shared"]["message"], "the client's window got the room's code")
        check(says_last == SENT, "the lobby says it was sent through Discord")
        check(
            "sign-in: ok" in line_last and "success=true" in line_last, "the probe line has the sign-in and the answer"
        )
        check(
            any(HINT in look[1] for look in seen), "the hint to pick who to send it to showed while the window was open"
        )
    else:
        refused = "AUTHENTICATE" in sent if mode == "reject-token" else "AUTHENTICATE" not in sent
        check(refused, "the Activity's sign-in went as the mode says")
        check("error rpc 4006: Not authenticated or invalid scope" in line_last, "the probe line has Discord's 4006")
        check(
            NOT_SIGNED_IN in says_last and "Copy the code" in says_last,
            "the lobby says the Activity is not signed in and points to Copy the code",
        )
        check(not any(HINT in look[1] for look in seen), "no hint to pick who to send it to after the refusal")
        check(
            "sign-in: failed (4009" in line_last if mode == "reject-token" else "sign-in: none" in line_last,
            "the probe line says how the sign-in went",
        )
    return lines, not failures


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
    parser.add_argument(
        "--share",
        action="store_true",
        help="check Share in Discord against a stand-in client (--share-client) instead of waiting for a night",
    )
    parser.add_argument(
        "--share-client", choices=SHARE_CLIENTS, default="shared", help="how the stand-in client answers shareLink"
    )
    parser.add_argument(
        "--real-bridge",
        nargs="?",
        const=str(REPO / "deploy" / "web"),
        metavar="DIR",
        help="with --share: run the real bridge and SDK (see the top of this file) from DIR (default deploy/web)",
    )
    parser.add_argument(
        "--host-mode", choices=HOST_MODES, default="strict", help="with --real-bridge: how Discord's client behaves"
    )
    parser.add_argument(
        "--local-backend",
        action="store_true",
        help="run spikes/backend with the stub Discord sign-in (backend argument: -)",
    )
    parser.add_argument(
        "--closing",
        action="store_true",
        help="after making a night, check what a tab closed on the waiting room does (#1188; tools/web_smoke/page_closing.py)",
    )
    parser.add_argument("--invite-fails", action="store_true", help="the stand-in client's openInviteDialog fails too")
    parser.add_argument("--pad", action="store_true", help="give the page a virtual gamepad (navigator.getGamepads)")
    parser.add_argument(
        "--website",
        action="store_true",
        help="load the page as the website (a plain host, no instance id) for the capture beside the Activity's",
    )
    parser.add_argument("--seconds", type=float, default=120.0, help="how long to wait for the night")
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.website:
        if args.share or args.clipboard:
            raise SystemExit("--website goes with the plain run")
        global HOST
        HOST = WEBSITE_HOST
        args.embed = "none"
    backend_process = None
    bridge_js = None
    if args.real_bridge:
        if not args.share:
            raise SystemExit("--real-bridge goes with --share")
        bridge_js = build_bridge(Path(args.real_bridge))
    if args.local_backend:
        backend_process, args.backend = start_local_backend()
    try:
        return run(args, bridge_js)
    finally:
        if backend_process is not None:
            backend_process.terminate()
            backend_process.wait(timeout=20)


def run(args: argparse.Namespace, bridge_js: bytes | None) -> int:
    log: list[str] = []
    stages: list[str] = []
    console: list[str] = []
    # A new instance id each run, in the address as Discord gives it; the game sends it nowhere (#1178).
    instance = f"emu-{int(time.time())}"
    # The clipboard check starts on the main menu, as a player who made a night himself does: no instance to join.
    # The real SDK needs an instance and a platform in the address, as Discord gives them.
    instance_part = (
        "" if ((args.clipboard or args.share) and bridge_js is None) else f"&instance_id={instance}&platform=desktop"
    )
    activity_url = f"https://{HOST}/?frame_id=1{instance_part}&guild_id=1&channel_id=1"
    if args.website:
        activity_url = f"https://{HOST}/?backend=https://{HOST}/api"
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
                (args.clipboard or args.share) and bridge_js is None,
                args.share_client,
                args.invite_fails,
                bridge_js,
                args.host_mode,
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
            if os.environ.get("ACTIVITY_CPU_THROTTLE"):
                # A slow runner (CI) loads the page and the bridge later than a fast machine: reproduces its timing.
                cdp = browser_context.new_cdp_session(page)
                cdp.send("Emulation.setCPUThrottlingRate", {"rate": float(os.environ["ACTIVITY_CPU_THROTTLE"])})
            page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))
            page.on("requestfailed", lambda r: console.append(f"[requestfailed] {r.method} {r.url} {r.failure}"))
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
            if args.share and bridge_js is not None:
                try:
                    lines, ok = share_real_flow(page, frame, args.out, args.host_mode)
                except Exception:
                    # What the page and the backend did up to the failure is the first thing to read.
                    page.screenshot(path=args.out / "share_real_failed.png")
                    (args.out / "console.txt").write_text(chr(10).join(console), encoding="utf-8")
                    print(chr(10).join(log))
                    raise
                browser.close()
                server.shutdown()
                (args.out / "console.txt").write_text(chr(10).join(console), encoding="utf-8")
                print(chr(10).join(log + lines))
                print(f"share, real bridge ({args.host_mode}): {'held' if ok else 'FAILED'}")
                return 0 if ok else 1
            if args.share:
                lines, ok = share_flow(page, frame, args.out, args.share_client, args.invite_fails)
                browser.close()
                server.shutdown()
                (args.out / "console.txt").write_text(chr(10).join(console), encoding="utf-8")
                print(chr(10).join(log + lines))
                print(f"share ({args.share_client}): {'held' if ok else 'FAILED'}")
                return 0 if ok else 1
            if args.clipboard:
                lines, ok = clipboard_flow(page, frame, args.out)
                page.screenshot(path=args.out / f"clipboard_{args.embed}.png")
                browser.close()
                server.shutdown()
                (args.out / "console.txt").write_text(chr(10).join(console), encoding="utf-8")
                print(chr(10).join(log + lines))
                print(f"clipboard ({args.embed}): {'both held' if ok else 'FAILED'}")
                return 0 if ok else 1
            deadline = time.monotonic() + args.seconds
            state: dict = {}
            failed = ""
            # The Activity opens on the main menu and signs in in the background (#495); Play together then shows the
            # website's screen and the backend is asked for no lobby until the player presses Create (#1178).
            kind = "website" if args.website else "activity"
            menu_ready = False
            while time.monotonic() < deadline:
                state = rooms.read_probe(frame)
                if state.get("screen") == "together_screen":
                    failed = "the Activity opened on Play together instead of the main menu"
                    break
                if state.get("screen") == "main_menu" and (args.website or state.get("signed_in")):
                    menu_ready = True
                    break
                time.sleep(1)
            if menu_ready:
                print(f"{kind}: the main menu is up{'' if args.website else ', signed in'}")
                page.wait_for_timeout(1500)
                page.screenshot(path=args.out / f"menu_{kind}.png")
                start_together(page, frame)
                page.wait_for_timeout(4000)  # long enough for anything the screen asks of the backend
                state = rooms.read_probe(frame)
                asked = [line for line in log if "/lobbies" in line]
                page.screenshot(path=args.out / f"together_{kind}.png")
                print(
                    f"{kind}: Play together is open; lobby calls so far: {asked or 'none'}; screen {state.get('screen')!r}"
                )
                if state.get("screen") != "together_screen" or state.get("room_code"):
                    failed = f"Play together did not stay on the website's screen: {state.get('screen')!r}"
                elif asked:
                    failed = f"opening Play together asked the backend for a lobby: {asked}"
                else:
                    focus_on(page, frame, "CreateNight")
                    smoke.press(page, "Enter")
                    if args.website:
                        # A player with no name is asked for one first (Discord has its own).
                        smoke.give_name(page, "Ann", 20)
                    waited_until = time.monotonic() + 60
                    while time.monotonic() < waited_until:
                        state = rooms.read_probe(frame)
                        if state.get("screen") == "lobby_screen" and state.get("room_code"):
                            break
                        time.sleep(0.5)
                    made = [line for line in log if line.startswith("POST /api/lobbies ")]
                    if state.get("screen") != "lobby_screen" or not state.get("room_code"):
                        failed = f"Create a night did not open a lobby: {state.get('screen')!r}"
                        state = {}
                    elif len(made) != 1:
                        failed = f"Create a night asked for {len(made)} lobbies: {made}"
                        state = {}
                    else:
                        print(f"lobby: {state.get('lobby_seats')} (code {state.get('room_code')}); made by {made}")
                        shown = preview_by_code(args.backend, state["room_code"])
                        print(f"a friend who types that code reads: {shown}")
                        if shown.get("code") != state["room_code"] or shown.get("state") != "open":
                            failed = f"the code shown in the lobby does not open that night: {shown}"
                            state = {}
                        page.screenshot(path=args.out / f"lobby_{kind}.png")
            if args.closing and state.get("room_code"):
                # The page behind the Discord stand-in: the list, a tab switch, a quiet host, then the page closed for real.
                lines, ok = page_closing.closing_checks(
                    page, frame, page_closing.Backend(args.backend), state["room_code"], args.out
                )
                server.shutdown()
                (args.out / "console.txt").write_text(chr(10).join(console), encoding="utf-8")
                print(chr(10).join(log + lines))
                print(f"closing ({kind}): {'held' if ok else 'FAILED'}")
                browser.close()
                return 0 if ok else 1
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
        print(f"{args.encoding}: {kind} held: Play together made no lobby until Create (room {state['room_code']})")
        return 0
    print(f"{args.encoding}: {kind} FAILED: {failed or state}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
