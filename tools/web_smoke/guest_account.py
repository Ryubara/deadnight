"""A Guest account lasts across visits (#1080), in a real browser: load the web build, sign in as a guest, write a save
to the account, reload the page, and read the same account (and the same save) back.

The credential the backend hands a guest is kept in `user://guest_account.json`, which on the web build is the browser's
IndexedDB. The run proves that, not the backend alone:

1. Visit one (a context with empty storage): the game signs in as a guest through Play together. The script then reads
   the credential file out of the page's IndexedDB (`/userfs`), signs in with it (the same call the game makes) and
   writes a save under the account.
2. The page is reloaded (a new process of the game in the same browser storage). The game signs in again and the probe
   (`window.deadnight`) says it found the same account again (`account_id` is the same, `account_returning` is true),
   with the name it had; the script reads the save back with the credential the second visit kept.
3. A second context with empty storage (another browser) signs in to a different account that has no save: the
   credential is the only thing that makes the guest the same.

Run it under the quiet launcher (headless Chromium under pointer lock clips the real cursor, docs/godot/no-focus.md):

    uv run --project ../gdstudio/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/guest_account.py build/web http://127.0.0.1:3000 build/guest-account

The first argument is a folder with the export (served on a fixed local port, which the backend must list in
`CORS_ORIGINS`) or the URL of a deployed build; the second is the platform backend (guest sign-in on). Writes
`result.json`, `console.txt` and screenshots (`visit1.png`, `visit2.png`, `fresh.png`).
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from playwright.sync_api import Browser, BrowserContext, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

sys.path.insert(0, str(Path(__file__).parent))
import smoke

LOCAL_PORT = 8087
CREDENTIAL_FILE = "/userfs/godot/app_userdata/Deadnight/guest_account.json"
NAME = "Ann"
# A profile the backend takes (it reads the `profile` slot: every field, and XP no faster than a person earns it).
SAVE = {"xp": 50, "equipped": {}, "done": [], "opening_night": True, "bonus_day": -1}
# The browser refuses a pointer lock that is not asked for inside a click or key press; the flow under test goes on.
IGNORED = ("A user gesture is required to request Pointer Lock",)

# The credential file as the browser keeps it: Godot's web build mirrors `user://` into IndexedDB `/userfs`, store
# `FILE_DATA`, one record a file with its bytes in `contents`.
READ_FILE_JS = """(path) => new Promise((resolve) => {
  const open = indexedDB.open('/userfs');
  open.onerror = () => resolve({ error: 'open failed' });
  open.onsuccess = () => {
    const db = open.result;
    if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); resolve({ error: 'no FILE_DATA store', stores: [...db.objectStoreNames] }); return; }
    const store = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA');
    const keys = store.getAllKeys();
    keys.onerror = () => { db.close(); resolve({ error: 'keys failed' }); };
    keys.onsuccess = () => {
      const get = store.get(path);
      get.onerror = () => { db.close(); resolve({ error: 'get failed', keys: keys.result }); };
      get.onsuccess = () => {
        const record = get.result;
        db.close();
        resolve({ keys: keys.result, text: record && record.contents ? new TextDecoder().decode(record.contents) : null });
      };
    };
  };
})"""


def read_probe(page: Page) -> dict:
    """Everything the game publishes (`smoke.probe` reads only the keys the other probes need)."""
    return page.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : null") or {}


def wait_for(page: Page, what: str, test, seconds: float) -> dict:
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = read_probe(page)
        if test(seen):
            return seen
        time.sleep(0.25)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def request(method: str, url: str, body: dict | None = None, token: str | None = None) -> tuple[int, dict]:
    """One JSON call to the backend, as the game makes it; `(status, json)`."""
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, data=data, headers=headers, method=method), timeout=20
        ) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"{}")


def stored_file(page: Page) -> dict:
    """What the page's IndexedDB holds for the credential file: `{"text": <the file or None>, "keys": [...]}`."""
    return page.evaluate(READ_FILE_JS, CREDENTIAL_FILE) or {}


def stored_credential(page: Page, backend: str) -> str:
    """The guest credential the page's own storage holds for `backend`, or ''."""
    text = stored_file(page).get("text")
    if not text:
        return ""
    return json.loads(text).get("accounts", {}).get(backend.rstrip("/"), "")


def open_context(
    browser: Browser, url: str, console: list[str], problems: list[str], label: str
) -> tuple[BrowserContext, Page]:
    context = browser.new_context(viewport=smoke.VIEWPORT)
    page = context.new_page()
    page.on("console", lambda m: console.append(f"[{label}] [{m.type}] {m.text}"))
    page.on(
        "pageerror",
        lambda e: None if any(text in str(e) for text in IGNORED) else problems.append(f"[{label}] [pageerror] {e}"),
    )
    page.goto(url, wait_until="commit")
    return context, page


def to_lobby(page: Page, name: str | None) -> dict:
    """Main menu, Play together, Create a night: signs the player in (a name prompt first, when asked), and returns the
    probe once the lobby shows its code."""
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)  # gives the canvas the keyboard
    page.wait_for_timeout(2500)
    smoke.menu_item(page, "Play")
    smoke.press(page, "Enter")
    wait_for(page, "the Play together screen", lambda s: s.get("screen") == "together_screen", smoke.SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    smoke.press(page, "ArrowDown")  # Server browser -> Create a night
    smoke.press(page, "Enter")
    if name is not None:
        smoke.give_name(page, name)  # a player with no saved name is asked first
    return wait_for(page, "the lobby", lambda s: s.get("screen") == "lobby_screen" and s.get("room_code", "") != "", 90)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the export, or the URL of a deployed web build")
    parser.add_argument("backend", help="the platform backend's address (guest sign-in on)")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true", help="use the machine's Chrome and GPU")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    backend = args.backend.rstrip("/")
    console: list[str] = []
    problems: list[str] = []
    result: dict = {"backend": backend}

    local = None
    base = args.web
    if not args.web.startswith(("http://", "https://")):
        handler = functools.partial(smoke.Quiet, directory=str(Path(args.web)))
        local = http.server.ThreadingHTTPServer(("127.0.0.1", LOCAL_PORT), handler)
        threading.Thread(target=local.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{LOCAL_PORT}/index.html"
    url = f"{base}?backend={backend}&probe"

    with sync_playwright() as p:
        browser = (
            p.chromium.launch(channel="chrome", headless=True)
            if args.gpu
            else p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        )
        try:
            # ---- Visit one: a new guest, its credential in the browser's storage, a save under the account.
            context, page = open_context(browser, url, console, problems, "visit 1")
            first = to_lobby(page, NAME)
            page.wait_for_timeout(800)
            page.screenshot(path=args.out / "visit1.png")
            account = first.get("account_id", "")
            result["visit1"] = {
                "account_id": account,
                "returning": first.get("account_returning"),
                "seats": first.get("lobby_seats"),
            }
            if not account:
                problems.append(f"visit 1: the probe has no account id: {first}")
            if first.get("account_returning"):
                problems.append("visit 1: a browser with empty storage cannot be a returning guest")
            credential = ""
            for _ in range(40):  # the storage is written from the page a moment after the sign-in
                credential = stored_credential(page, backend)
                if credential:
                    break
                page.wait_for_timeout(250)
            if not credential:
                problems.append(
                    f"visit 1: the credential never reached the page's IndexedDB ({CREDENTIAL_FILE}): {stored_file(page)}"
                )
            else:
                status, signed = request("POST", f"{backend}/auth/guest", {"guestToken": credential})
                if status != 200 or signed.get("user", {}).get("id") != account or not signed.get("returning"):
                    problems.append(
                        f"visit 1: the stored credential should sign in to account {account}: {status} {signed}"
                    )
                status, saved = request(
                    "PUT",
                    f"{backend}/saves/profile",
                    {"revision": 0, "schemaVersion": 1, "data": SAVE},
                    signed.get("token"),
                )
                result["save_written"] = [status, saved]
                if status != 200:
                    problems.append(f"visit 1: the save was refused: {status} {saved}")

            # The guest leaves its lobby (a player in a night cannot make another), as a player closing the tab would
            # be dropped for being away; then ---- visit two: the same page reloaded. Nothing of visit one is in memory
            # but the browser's storage.
            smoke.focus_control(page, "Leave", "ArrowRight")
            smoke.press(page, "Enter")
            wait_for(page, "the Play together screen", lambda s: s.get("screen") == "together_screen", 30)
            page.wait_for_timeout(1500)  # the request that gives the seat up goes out from the screen that is leaving
            page.reload(wait_until="commit")
            second = to_lobby(page, None)  # the name was kept in the profile: no prompt
            page.wait_for_timeout(800)
            page.screenshot(path=args.out / "visit2.png")
            result["visit2"] = {
                "account_id": second.get("account_id"),
                "returning": second.get("account_returning"),
                "seats": second.get("lobby_seats"),
            }
            if second.get("account_id") != account:
                problems.append(
                    f"visit 2: the reload should sign in to account {account}, not {second.get('account_id')!r}"
                )
            if not second.get("account_returning"):
                problems.append("visit 2: the sign-in should have found the account again with the stored credential")
            if NAME not in second.get("lobby_seats", ""):
                problems.append(f"visit 2: the lobby should seat {NAME!r}: {second.get('lobby_seats')!r}")
            kept = stored_credential(page, backend)
            result["credential_renewed"] = bool(kept) and kept != credential
            status, again = request("POST", f"{backend}/auth/guest", {"guestToken": kept})
            if status != 200 or again.get("user", {}).get("id") != account:
                problems.append(
                    f"visit 2: the credential it kept should sign in to account {account}: {status} {again}"
                )
            status, read = request("GET", f"{backend}/saves/profile", token=again.get("token"))
            result["save_read"] = [status, read]
            if status != 200 or read.get("data") != SAVE:
                problems.append(f"visit 2: the account's save should read back as {SAVE}: {status} {read}")
            context.close()

            # ---- Another browser (empty storage) is another guest with no save: the credential is what made the match.
            context, other = open_context(browser, url, console, problems, "fresh")
            fresh = to_lobby(other, "Bo")
            other.screenshot(path=args.out / "fresh.png")
            result["fresh"] = {"account_id": fresh.get("account_id"), "returning": fresh.get("account_returning")}
            if fresh.get("account_id") in ("", account):
                problems.append(
                    f"a browser with empty storage must be a new guest, not {account}: {fresh.get('account_id')!r}"
                )
            context.close()
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            for index, ctx in enumerate(browser.contexts):
                for page in ctx.pages:
                    try:
                        page.screenshot(path=args.out / f"failure_{index}.png")
                    except PlaywrightError:
                        pass
        finally:
            browser.close()
            if local:
                local.shutdown()

    console_errors = [line for line in console if "[error]" in line and not any(text in line for text in IGNORED)]
    result["console_errors"] = console_errors
    problems.extend(f"console: {line}" for line in console_errors)
    result["problems"] = problems
    (args.out / "console.txt").write_text("\n".join(console), encoding="utf-8")
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
