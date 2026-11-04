"""A signed-in solo night sends its XP to the account's profile slot (#1106), in a real browser against the real backend.

The script starts the platform backend (`spikes/backend`, run by Node with memory storage, guest sign-in on) on a free
port, serves the web export, and opens the page with `?autopilot&signin=1`: the game signs in as a guest and the
autopilot plays a solo night (`AutopilotRun`, `game/tools/bench/autopilot_run.gd`) until the rounds asked for are played.
It then signs in to the same account with the credential the page kept (the guest credential in the browser's
IndexedDB, the way `guest_account.py` does) and reads the `profile` slot:

1. the slot holds the XP the night earned (more than 0), the opening night and the day of the first game, on revision 1
   or more (a stale revision or a refusal would have left it empty);
2. the profile file the page keeps (`user://profile.json`) agrees: the same XP, and nothing left in the queue unless
   the backend refused a write (then the XP is in the account and the queue together, never lost or counted twice).

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/solo_profile.py build/web build/solo-profile [--gpu] [--rounds 2] [--returning]

With `--returning` the page is not told to sign in (no `signin=1`): a first visit makes the Guest account by Play
together (the way a player does, the credential kept in the browser's storage), then the same browser opens the game
again for a solo night and the game signs in at start-up by itself (`StartupSignIn`, #1122). The checks above hold, and
the account the night's XP went to is the first visit's, not a new one.

The first argument is a folder with the export. Writes `result.json`, `console.txt` and screenshots; exits 1 when a
check fails.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import guest_account
import smoke

BACKEND_DIR = Path(__file__).resolve().parents[2] / "spikes" / "backend"
USER_DIR = "/userfs/godot/app_userdata/Deadnight"
PROFILE_FILE = f"{USER_DIR}/profile.json"
SECRETS = {
    "SESSION_SECRET": "session-secret-of-at-least-32-characters-a",
    "TICKET_SECRET": "ticket-secret-of-at-least-32-characters-b",
    "GAME_SERVER_SECRET": "server-secret-of-at-least-32-characters-c",
}
# A fresh account has no profile yet: reading it is a 404 the browser logs, and the game takes as "nothing saved".
IGNORED = ("A user gesture is required to request Pointer Lock", "/saves/profile")


def free_port() -> int:
    import socket

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def start_backend(origin: str) -> tuple[subprocess.Popen, str]:
    """Node running the backend on a free port, allowing the page's origin; returns the process and its address."""
    port = free_port()
    env = {
        **os.environ,
        **SECRETS,
        "HOST": "127.0.0.1",
        "PORT": str(port),
        "DISCORD_MODE": "off",
        "GUEST_SIGN_IN": "1",
        "NODE_ENV": "test",
        "LOG_LEVEL": "warn",
        "CORS_ORIGINS": origin,
    }
    node = shutil.which("node") or "node"
    process = subprocess.Popen([node, str(BACKEND_DIR / "src" / "main.ts")], env=env)
    address = f"http://127.0.0.1:{port}"
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{address}/health", timeout=2) as answer:
                if answer.status == 200:
                    return process, address
        except OSError:
            time.sleep(0.2)
    process.terminate()
    raise TimeoutError("the backend did not come up")


def stored_text(page: Page, path: str) -> str | None:
    return (page.evaluate(guest_account.READ_FILE_JS, path) or {}).get("text")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    parser.add_argument("--rounds", type=int, default=2, help="play until this round has started")
    parser.add_argument(
        "--returning", action="store_true", help="a returning Guest: sign in at start-up, not by `signin=1`"
    )
    parser.add_argument("--timeout", type=float, default=600, help="seconds to wait for the night")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    console: list[str] = []
    problems: list[str] = []
    result: dict = {}

    server, port = smoke.serve(Path(args.web))
    origin = f"http://127.0.0.1:{port}"
    backend_process, backend = start_backend(origin)
    result["backend"] = backend
    signin = "" if args.returning else "&signin=1"
    url = f"{origin}/index.html?backend={backend}&autopilot{signin}&rounds={args.rounds}&hold=6&break=3&seconds=900"
    try:
        with sync_playwright() as p:
            browser = (
                p.chromium.launch(channel="chrome", headless=True)
                if args.gpu
                else p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
            )
            try:
                first_account = ""
                if args.returning:
                    # Visit one: Play together makes the Guest account and the browser keeps its credential.
                    _, page = guest_account.open_context(
                        browser, f"{origin}/index.html?backend={backend}&probe", console, problems, "visit 1"
                    )
                    first = guest_account.to_lobby(page, "Ann")
                    first_account = first.get("account_id", "")
                    result["first_visit_account"] = first_account
                    for _ in range(40):
                        if guest_account.stored_credential(page, backend):
                            break
                        page.wait_for_timeout(250)
                else:
                    page = browser.new_page(viewport=smoke.VIEWPORT)
                page.on("console", lambda m: console.append(f"[{m.type}] {m.text} {m.location.get('url', '')}"))
                page.on(
                    "pageerror",
                    lambda e: None if any(text in str(e) for text in IGNORED) else problems.append(f"[pageerror] {e}"),
                )
                # Visit two (or the only one): the game opens for a solo night.
                page.goto(url, wait_until="commit")
                deadline = time.monotonic() + args.timeout
                shot = False
                report = None
                while time.monotonic() < deadline:
                    state = smoke.probe(page)
                    if not shot and state.get("night") and state.get("running") and state.get("round", 0) >= 1:
                        page.screenshot(path=args.out / "night.png")
                        shot = True
                    text = page.evaluate("() => window.deadnightRounds || null")
                    if text:
                        report = json.loads(text)
                        break
                    time.sleep(1)
                if not report:
                    raise TimeoutError(
                        f"the autopilot never finished its rounds; the game last said {smoke.probe(page)}"
                    )
                page.screenshot(path=args.out / "night-end.png")
                # Let the last write land: the round's end sends it without waiting for anything.
                page.wait_for_timeout(3000)
                credential = ""
                for _ in range(40):
                    credential = guest_account.stored_credential(page, backend)
                    if credential:
                        break
                    page.wait_for_timeout(250)
                if not credential:
                    raise TimeoutError("the guest credential never reached the page's storage")
                status, signed = guest_account.request("POST", f"{backend}/auth/guest", {"guestToken": credential})
                account = signed.get("user", {}).get("id", "")
                result["account_id"] = account
                if args.returning and account != first_account:
                    problems.append(f"the night's XP should go to the first visit's account {first_account}: {account}")
                if status != 200 or not account:
                    problems.append(f"the stored credential should sign in: {status} {signed}")
                status, saved = guest_account.request("GET", f"{backend}/saves/profile", token=signed.get("token"))
                result["profile_slot"] = [status, saved]
                held = saved.get("data", {}) if status == 200 else {}
                if status != 200:
                    problems.append(f"the profile slot is empty: {status} {saved}")
                elif not held.get("xp", 0) > 0:
                    problems.append(f"the profile slot holds no XP: {saved}")
                elif not held.get("opening_night"):
                    problems.append(f"the profile slot should hold the opening night: {saved}")
                file_text = stored_text(page, PROFILE_FILE)
                local = json.loads(file_text) if file_text else {}
                result["profile_file"] = local
                waiting = sum(int(write.get("xp", 0)) for write in local.get("queue", []))
                result["xp_in_account"] = held.get("xp", 0)
                result["xp_waiting"] = waiting
                if local.get("data", {}).get("xp") != held.get("xp", 0) + waiting:
                    problems.append(
                        f"the file's XP ({local.get('data', {}).get('xp')}) should be the account's ({held.get('xp', 0)}) "
                        f"plus what waits ({waiting})"
                    )
                if local.get("account") != account:
                    problems.append(f"the file should name the account {account}: {local.get('account')!r}")
                result["round_reached"] = report.get("round_reached")
                result["night_seconds"] = report.get("seconds")
            except (TimeoutError, PlaywrightError) as error:
                problems.append(f"[run] {error}")
                try:
                    browser.contexts[0].pages[0].screenshot(path=args.out / "failure.png")
                except (PlaywrightError, IndexError):
                    pass
            finally:
                browser.close()
    finally:
        server.shutdown()
        backend_process.terminate()
        try:
            backend_process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            backend_process.kill()

    errors = [line for line in console if line.startswith("[error]") and not any(text in line for text in IGNORED)]
    result["console_errors"] = errors
    problems.extend(f"console: {line}" for line in errors)
    result["problems"] = problems
    (args.out / "console.txt").write_text("\n".join(console), encoding="utf-8")
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
