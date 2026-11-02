"""Start-up of every web probe against a build (issue #484): the menu paths they walk, each once, and nothing else.

The probes reach their night, the Play together screen, the settings or the join screen through the shared helpers of
`smoke.py` (`reach_menu`, `start_solo`, `open_together`, `open_settings`, `back_to_menu`) and `online.open_address`.
When the menu changes (the rework of #466 broke two probes that kept their own key walks), the helper is the one edit,
and this run, in the CI `web` job, fails on the change instead of a probe failing the next time somebody runs it:

1. the menu, then the Loadout tab and back (`smoke.py`)
2. Play together, and back (`rooms.py`, `online.py`, `activity.py`)
3. settings, and back (`resolution_scale.py`)
4. Solo: a running night (`smoke.py`, `judder.py` and so `flash.py` and `hip_fire.py`, `first_use.py`, `skin_tour.py`,
   `touch_look.py`, `resolution_scale.py`, `flare_first.py`)
5. a second page with `?dev`: Play together, then its server address button: the join screen (`online.py`, `freeze.py`)
6. on that page, pointed at a backend that is not there: Quick join on the main menu opens its card (and never the Play
   together screen), the card ends in the network text, and Esc closes it (`quick_join.py`)

`kill_spike.py` (`?bench`) and `menu_stage.py` (`?stage`) start from the address, `audio_load.py`, `door_swap.py`,
`touch_assist.py` and `gun_levels_web.py` from their own scene: they walk no menu.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/startup_check.py build/web [build/startup-check]

Exits 1 and names the step that failed (with a screenshot, `failure.png`, in the output folder); 0 when all pass.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import online
import smoke
from playwright.sync_api import Browser, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

# Nothing listens on port 9: the connection is refused at once.
DEAD_BACKEND = "http://127.0.0.1:9"


class Steps:
    """Runs named steps in order; the first failure stops the run and keeps its name and a screenshot."""

    def __init__(self, page: Page, out: Path) -> None:
        self.page = page
        self.out = out
        self.done: list[dict] = []
        self.failed: str | None = None

    def run(self, name: str, step) -> bool:
        started = time.monotonic()
        try:
            step()
        except (TimeoutError, PlaywrightError) as error:
            self.failed = f"{name}: {error}"
            self.done.append({"step": name, "ok": False, "error": str(error)})
            try:
                self.page.screenshot(path=self.out / "failure.png")
            except PlaywrightError:
                pass
            return False
        self.done.append({"step": name, "ok": True, "seconds": round(time.monotonic() - started, 1)})
        return True


def expect_screen(page: Page, screen: str) -> None:
    state = smoke.probe(page)
    if state.get("screen") != screen:
        raise TimeoutError(f"expected the {screen} screen, the game reports {state}")


def main_page(page: Page, url: str, steps: Steps) -> None:
    page.goto(url, wait_until="commit")
    ok = steps.run("the main menu", lambda: smoke.reach_menu(page))
    ok = ok and steps.run(
        "the Loadout tab and back", lambda: (smoke.menu_item(page, "Loadout"), smoke.menu_item(page, "Play"))
    )
    ok = ok and steps.run("Play together", lambda: smoke.open_together(page))
    ok = ok and steps.run("back to the menu", lambda: (smoke.back_to_menu(page), expect_screen(page, "main_menu")))
    ok = ok and steps.run("settings", lambda: smoke.open_settings(page))
    ok = ok and steps.run("back to the menu", lambda: (smoke.back_to_menu(page), expect_screen(page, "main_menu")))
    ok = ok and steps.run("Solo", lambda: (smoke.start_solo(page), smoke.wait_for_night(page)))


def quick_join_card(page: Page) -> None:
    """Quick join on the Play tab: the card shows (the backend is not there, so it ends in the network text), the page
    never leaves the main menu, and Esc closes the card."""
    smoke.menu_item(page, "Play", 1)
    smoke.press(page, "Enter")
    smoke.wait_for(page, "the Quick join card", lambda s: s.get("quick_join", "") != "", smoke.SCREEN_TIMEOUT_S)
    seen = smoke.wait_for(
        page,
        "the card's failure text",
        lambda s: s.get("quick_join", "").startswith("Could not"),
        smoke.SCREEN_TIMEOUT_S,
    )
    if seen.get("screen") != "main_menu":
        raise TimeoutError(f"Quick join left the main menu, the game reports {seen}")
    smoke.press(page, "Escape")
    smoke.wait_for(page, "the card to close", lambda s: s.get("quick_join", "") == "", smoke.SCREEN_TIMEOUT_S)
    expect_screen(page, "main_menu")


def join_page(page: Page, url: str, steps: Steps) -> None:
    page.goto(url + ("&" if "?" in url else "?") + "dev&backend=" + DEAD_BACKEND, wait_until="commit")
    ok = steps.run("the main menu (?dev)", lambda: smoke.reach_menu(page))
    ok = ok and steps.run("the join screen", lambda: online.open_address(page))
    ok = ok and steps.run("the join screen is the screen", lambda: expect_screen(page, "join_screen"))
    ok = ok and steps.run("back to the menu", lambda: (smoke.back_to_menu(page), expect_screen(page, "main_menu")))
    if ok:
        steps.run("Quick join", lambda: quick_join_card(page))


def check(browser: Browser, url: str, out: Path) -> dict:
    result: dict = {"pages": []}
    for name, run in (("main", main_page), ("dev", join_page)):
        page = browser.new_page(viewport=smoke.VIEWPORT)
        steps = Steps(page, out)
        try:
            run(page, url, steps)
        finally:
            page.close()
        result["pages"].append({"page": name, "steps": steps.done, "failed": steps.failed})
        if steps.failed:
            result["failed"] = steps.failed
            break
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or the URL of a deployed build")
    parser.add_argument("out", type=Path, nargs="?", default=Path("startup-check"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        try:
            result = check(browser, url, args.out)
        finally:
            browser.close()
            if server is not None:
                server.shutdown()
    result["ok"] = "failed" not in result
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    if not result["ok"]:
        print(f"START-UP FAILED at {result['failed']}", file=sys.stderr)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
