"""Browser check that the night shows its crosshair from the first running frame (#517).

A player who starts a night from the main menu must see the reticle at once, not only after an Esc and a Resume. This
run starts a solo night in headless Chromium the way a player does (or, with `--server`, joins the night of a game
server through Play together: `godot --headless --path game -- --server --port 8911`), and reads whether the HUD's
reticle is shown (`window.deadnight.reticle`) on the first running frames, after the menu is opened with Esc and Resume
is pressed, and takes a capture of each.

    uv run --with playwright==1.64.1 python tools/web_smoke/crosshair.py build/web build/crosshair [--server ws://127.0.0.1:8911]

Run it through `gds quiet` on Windows like every browser probe (docs/godot/web-export.md).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from online import join
from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright
from pointer_lock import SOFTWARE_GL, VIEWPORT, press, probe, serve, wait_for
from smoke import start_solo

LOAD_TIMEOUT_S = 150
# The night's load on a CI runner took 82 s to 107 s, and over 150 s on a slow one (see smoke.py).
NIGHT_LOAD_TIMEOUT_S = 300
REACT_S = 8.0
# The Resume button at this viewport (the card is centred, three buttons: Resume, Settings, Leave night; see pointer_lock.py).
RESUME_BUTTON = (640, 350)


def run(page: Page, url: str, out: Path, result: dict, server: str) -> None:
    if server:
        # The server address is a developer setting: the page is opened with `?dev`.
        page.goto(url + "?dev", wait_until="commit")
        join(page, server, out)
    else:
        page.goto(url, wait_until="commit")
        wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
        page.mouse.click(5, 5)
        page.wait_for_timeout(2500)
        start_solo(page)
    first = wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
    result["first_running_frame"] = {k: first.get(k) for k in ("running", "paused", "reticle", "mouse_mode")}
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "1_first_running_frames.png")
    result["after_1_5_s"] = {k: probe(page).get(k) for k in ("running", "paused", "reticle", "mouse_mode")}

    press(page, "Escape")
    wait_for(page, "the menu to open", lambda s: bool(s.get("paused")), REACT_S)
    page.mouse.click(*RESUME_BUTTON)
    wait_for(page, "the night to run again", lambda s: bool(s.get("running")), REACT_S)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "2_after_resume.png")
    result["after_resume"] = {k: probe(page).get(k) for k in ("running", "paused", "reticle", "mouse_mode")}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html inside)")
    parser.add_argument("out", type=Path, help="where the captures and result.json go")
    parser.add_argument("--server", default="", help="join this game server (ws://host:port) instead of playing alone")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = serve(args.build)
    problems: list[str] = []
    result: dict = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        page = browser.new_page(viewport=VIEWPORT)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        try:
            run(page, f"http://127.0.0.1:{port}/index.html", args.out, result, args.server)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=args.out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            browser.close()
            server.shutdown()
    for key in ("first_running_frame", "after_1_5_s", "after_resume"):
        if key in result and result[key].get("reticle") is False:
            problems.append(f"[check] the reticle is hidden in {key}")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\ncrosshair check FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\ncrosshair check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
