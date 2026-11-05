"""A phone joins a friend's night by its room code, typed with a finger (issue #1183).

`phone_keyboard.py` checks each way of typing; this walks the whole flow against the real platform backend
(`spikes/backend`, run locally with the guest sign-in). A host (plain HTTP calls) makes a night and gets its room code.
The phone, a Chromium page with a phone's size, touch and user agent, opens the web export on Play together, taps the
code field, types the code on the keypad, presses the keypad's Join, answers the name prompt on the system keyboard's
path (a tap on the field, then the typed name), and must land on that night's preview with the host's code, then press
Join and sit in the night's lobby beside the host.

    npm ci --prefix spikes/backend
    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/phone_join.py <web folder> <out folder>

It exits 1 when a step fails. The keyboard itself is not drawn by an emulated browser (`phone_keyboard.py`).
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import phone_keyboard as pk
import rooms
import smoke

REPO = Path(__file__).resolve().parents[2]
NAME = "Alex"


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def start_backend(origin: str) -> tuple[subprocess.Popen, str]:
    """The platform backend on a free port, guest sign-in on, calls from `origin` allowed."""
    port = free_port()
    env = {
        **os.environ,
        "DISCORD_MODE": "off",
        "GUEST_SIGN_IN": "1",
        "CORS_ORIGINS": origin,
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
        raise SystemExit("needs node on the PATH")
    process = subprocess.Popen([node, "src/main.ts"], cwd=REPO / "spikes" / "backend", env=env)
    url = f"http://127.0.0.1:{port}"
    for _ in range(100):
        try:
            urllib.request.urlopen(f"{url}/health", timeout=1).read()
            return process, url
        except OSError:
            if process.poll() is not None:
                raise SystemExit("the backend exited (did `npm ci --prefix spikes/backend` run?)")
            time.sleep(0.2)
    process.terminate()
    raise SystemExit("the backend never answered /health")


def call(url: str, path: str, body: dict, token: str = "") -> dict:
    request = urllib.request.Request(
        url + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})},
    )
    with urllib.request.urlopen(request, timeout=10) as answer:
        return json.loads(answer.read())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    check = pk.Checks()
    server, port = smoke.serve(args.web)
    backend, url = start_backend(f"http://127.0.0.1:{port}")
    try:
        signed = call(url, "/auth/guest", {"name": "Hostess"})
        night = call(url, "/lobbies", {}, signed["token"])
        code = night["code"]
        print(f"the host made a night: code {code}")
        with sync_playwright() as p:
            browser = p.chromium.launch(args=smoke.SOFTWARE_GL + smoke.mute_args())
            context = browser.new_context(
                viewport={"width": 844, "height": 390},
                device_scale_factor=3,
                has_touch=True,
                is_mobile=True,
                user_agent=pk.PHONE_AGENT,
            )
            context.add_init_script(pk.SPY)
            page = context.new_page()
            cdp = context.new_cdp_session(page)
            page.goto(f"http://127.0.0.1:{port}/?probe&backend={url}", wait_until="commit")
            smoke.reach_menu(page)
            smoke.open_together(page)
            tap = pk.tap_box
            tap(page, cdp, pk.css_box(page, "fields", "Code"))
            page.wait_for_timeout(1200)
            page.screenshot(path=args.out / "1_keypad.png")
            for letter in code:
                x, y = pk.key_point(page, letter)
                pk.tap(page, cdp, x, y)
                page.wait_for_timeout(150)
            page.wait_for_timeout(500)
            typed = rooms.read_probe(page).get("code_text")
            check(typed == code, "the keypad types the host's code", f"field {typed!r}, code {code!r}")
            page.screenshot(path=args.out / "2_code_typed.png")
            x, y = pk.key_point(page, "Join")
            pk.tap(page, cdp, x, y)
            smoke.wait_for(page, "the name prompt", lambda _s: bool(rooms.read_probe(page).get("naming")), 30)
            page.wait_for_timeout(1200)
            pk.tap(page, cdp, 40, 40)
            page.wait_for_timeout(800)
            pk.tap_box(page, cdp, pk.css_box(page, "fields", "PlayerName"))
            page.wait_for_timeout(1200)
            focused = page.evaluate(pk.STATE)
            check(focused["editable"], "a tap on the name field raises the system keyboard's input", focused["active"])
            page.screenshot(path=args.out / "3_name.png")
            page.keyboard.insert_text(NAME)
            page.wait_for_timeout(500)
            page.keyboard.press("Enter")
            state = smoke.wait_for(
                page,
                "the night's preview",
                lambda _s: rooms.read_probe(page).get("screen") == "lobby_screen",
                60,
            )
            state = rooms.read_probe(page)
            check(state.get("screen") == "lobby_screen", "the code opens the host's night", str(state.get("screen")))
            check(state.get("room_code") == code, "it is the host's night", f"shows {state.get('room_code')!r}")
            page.wait_for_timeout(1500)
            page.screenshot(path=args.out / "4_preview.png")
            spots = pk.parse_spots(str(state.get("spots", "")))
            joins = [name for name in spots if name.lower().startswith("join")]
            check(bool(joins), "the preview has a Join button", f"buttons {sorted(spots)}")
            if joins:
                pk.tap_box(page, cdp, pk.css_box(page, "spots", joins[0]))
                page.wait_for_timeout(4000)
                seats = str(rooms.read_probe(page).get("lobby_seats", ""))
                check(
                    NAME in seats and "Hostess" in seats,
                    "Join puts the phone in the lobby beside the host",
                    f"seats {seats!r}",
                )
                page.screenshot(path=args.out / "5_joined.png")
            browser.close()
    finally:
        backend.terminate()
        server.shutdown()
    print("all held" if not check.failed else "FAILED: " + "; ".join(check.failed))
    return 1 if check.failed else 0


if __name__ == "__main__":
    sys.exit(main())
