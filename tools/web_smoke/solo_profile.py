"""A signed-in solo night sends its XP to the account's profile slot (#1106) and its challenge board to the `challenges`
slot (#1124), in a real browser against the real backend.

The script starts the platform backend (`spikes/backend`, run by Node with memory storage, guest sign-in on) on a free
port, serves the web export, and opens the page with `?autopilot&signin=1`: the game signs in as a guest and the
autopilot plays a solo night (`AutopilotRun`, `game/tools/bench/autopilot_run.gd`) until the rounds asked for are played.
It then signs in to the same account with the credential the page kept (the guest credential in the browser's
IndexedDB, the way `guest_account.py` does) and reads the `profile` slot:

1. the slot holds the XP the night earned (more than 0), the opening night and the day of the first game, on revision 1
   or more (a stale revision or a refusal would have left it empty);
2. the profile file the page keeps (`user://profile.json`) agrees: the same XP, and nothing left in the queue unless
   the backend refused a write (then the XP is in the account and the queue together, never lost or counted twice).
3. the `challenges` slot holds the night's board (kills counted, the day's dailies), the file the page keeps names the
   account and agrees with it, and a second page of the same browser opens the menu on the Challenges tab (the shot).

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/solo_profile.py build/web build/solo-profile [--gpu] [--rounds 2]

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
CHALLENGE_FILE = f"{USER_DIR}/challenges.json"
SECRETS = {
    "SESSION_SECRET": "session-secret-of-at-least-32-characters-a",
    "TICKET_SECRET": "ticket-secret-of-at-least-32-characters-b",
    "GAME_SERVER_SECRET": "server-secret-of-at-least-32-characters-c",
}
# A fresh account has no profile yet: reading it is a 404 the browser logs, and the game takes as "nothing saved".
IGNORED = ("A user gesture is required to request Pointer Lock", "/saves/profile", "/saves/challenges")


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


def check_board(page: Page, backend: str, token: str, account: str, result: dict, problems: list[str]) -> None:
    """The night's challenge board is in the account's `challenges` slot, and the file the page keeps is its cache:
    the same kills, the account's name and the slot's revision (#1124)."""
    status, saved = guest_account.request("GET", f"{backend}/saves/challenges", token=token)
    result["challenges_slot"] = [status, {key: saved.get(key) for key in ("revision", "schemaVersion")}]
    held = saved.get("data", {}) if status == 200 else {}
    kills = held.get("lifetime", {}).get("kills", 0)
    result["kills_in_account"] = kills
    if status != 200:
        problems.append(f"the challenges slot is empty: {status} {saved}")
        return
    if not kills > 0:
        problems.append(f"the challenges slot should hold the night's kills: {held.get('lifetime')}")
    if not held.get("dailies"):
        problems.append("the challenges slot should hold the day's dailies")
    text = stored_text(page, CHALLENGE_FILE)
    local = json.loads(text) if text else {}
    result["challenges_file"] = {key: local.get(key) for key in ("account", "accountRevision", "revision")}
    if local.get("account") != account:
        problems.append(f"the board file should name the account {account}: {local.get('account')!r}")
    if local.get("data", {}).get("lifetime", {}).get("kills") != kills:
        problems.append(
            f"the board file's kills should be the account's ({kills}): {local.get('data', {}).get('lifetime')}"
        )


def show_challenges_tab(context, origin: str, backend: str, out: Path, result: dict, problems: list[str]) -> None:
    """A second page of the same browser: the menu's Challenges tab shows what the night counted."""
    page = context.new_page()
    page.goto(f"{origin}/index.html?backend={backend}", wait_until="commit")
    smoke.reach_menu(page)
    smoke.menu_item(page, "Challenges")
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "challenges-tab.png")
    result["menu_tab"] = smoke.probe(page).get("tab")
    if result["menu_tab"] != "Challenges":
        problems.append(f"the menu should be on the Challenges tab: {result['menu_tab']!r}")
    page.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    parser.add_argument("--rounds", type=int, default=2, help="play until this round has started")
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
    url = f"{origin}/index.html?backend={backend}&autopilot&signin=1&rounds={args.rounds}&hold=6&break=3&seconds=900"
    try:
        with sync_playwright() as p:
            browser = (
                p.chromium.launch(channel="chrome", headless=True)
                if args.gpu
                else p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
            )
            try:
                # One context for both pages: the second page finds the first one's files and credential.
                context = browser.new_context(viewport=smoke.VIEWPORT)
                page = context.new_page()
                page.on("console", lambda m: console.append(f"[{m.type}] {m.text} {m.location.get('url', '')}"))
                page.on(
                    "pageerror",
                    lambda e: None if any(text in str(e) for text in IGNORED) else problems.append(f"[pageerror] {e}"),
                )
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
                check_board(page, backend, signed.get("token"), account, result, problems)
                page.close()
                show_challenges_tab(context, origin, backend, args.out, result, problems)
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
