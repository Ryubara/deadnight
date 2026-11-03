"""The menu soldier's grip on every showcase weapon, in the browser (issue #621).

Serves the web export (a folder, or opens a URL), opens the Loadout tab and steps the showcase weapon with Right
through the whole row, once round: a screenshot of the stage after each step, named by the position in the row. The
row's order is the catalogue's (`WeaponCatalog.IDS`), starting at the saved weapon, which a fresh browser has as the
rifle; `--names` gives the file names in the order they are shot. The shot shows the weapon's name in the picker, so a
wrong order is visible in the picture.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/menu_grips.py build/web build/menu-grips

Fails on any console error. The hands' contact with each weapon is measured by `tests/ui/test_menu_grips.gd`; this
shows the same menu in the browser's renderer.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError
from smoke import SOFTWARE_GL, UNPACED, menu_item, mute_args, press, reach_menu, serve

VIEWPORT = {"width": 1280, "height": 720}
# The row from the rifle on, round the whole row (the catalogue order is pistol, smg, shotgun, rifle, flare gun, ...).
ROW_FROM_RIFLE = ["rifle", "flare_gun", "crowbar", "baseball_bat", "fire_axe", "pistol", "smg", "shotgun"]
# The stage eases the soldier and the camera; wait for both to settle after a step.
SETTLE_MS = 2500


def shoot_row(page: Page, out: Path, names: list[str]) -> None:
    menu_item(page, "Loadout")
    page.wait_for_timeout(SETTLE_MS)
    for index, name in enumerate(names):
        page.screenshot(path=out / f"{index}_{name}.png")
        press(page, "ArrowRight")
        page.wait_for_timeout(SETTLE_MS)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or the URL of a deployed build")
    parser.add_argument("out", type=Path, help="folder for the screenshots and result.json")
    parser.add_argument(
        "--names", default=",".join(ROW_FROM_RIFLE), help="file names, in the row's order from the rifle"
    )
    parser.add_argument("--gpu", action="store_true", help="use the machine's GPU instead of a software renderer")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []

    def on_console(message: ConsoleMessage) -> None:
        if message.type == "error":
            problems.append(f"[console] {message.text}")

    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True, args=[*UNPACED, *mute_args()])
        else:
            browser = p.chromium.launch(headless=True, args=[*SOFTWARE_GL, *mute_args()])
        page = browser.new_page(viewport=VIEWPORT)
        page.on("console", on_console)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        try:
            page.goto(url, wait_until="commit")
            reach_menu(page)
            shoot_row(page, args.out, args.names.split(","))
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=args.out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            browser.close()
            if server:
                server.shutdown()
    (args.out / "result.json").write_text(json.dumps({"problems": problems}, indent=2) + "\n", encoding="utf-8")
    for line in problems:
        print(line, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
