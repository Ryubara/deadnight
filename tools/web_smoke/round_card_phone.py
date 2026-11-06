"""The round card and the players' column in a real night on a phone's page (issue #1305).

Opens the exported game (`?touch=1`) in Chrome as a phone (a page of 844 x 390 or 667 x 375 CSS px at a pixel ratio of
2, touch), sets the interface size and the hand the way the Settings screen saves them, walks Play > Solo, sets the Bots
row to the most (7, by the keys: at 1.25 the panel is wider than a 667 px page), starts the night and, once the arrival
is over, reads the HUD's cards from the probe (`hud_cards`, fractions of the window) and takes a screenshot of the world
with the HUD over it. It checks, in the canvas's units (864, 1080 or 1350 high at 1.25, 1.0 and 0.8):

- the round card is one row high (at most 96 units; the card in three lines is 160);
- the players' column is under the objective, with the gap, and over the health card.

The column's rectangle is in `result.json` (its height says one box to a row or pairs).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/round_card_phone.py <web folder> <out folder> \\
        [--page 844|667] [--ui 0.8|1.0|1.25] [--left] [--bots 7] [--before]

`<web folder>` is an export of the real project; `--export <godot>` exports this checkout into `<out folder>/export` and
runs that (give `-` as the folder); `--game <folder>` exports a copy of the game folder instead, a "before" build with
the change taken out. `--before` skips the check on the card's height. Screenshots and `result.json` go to the out
folder. Exits 1 on any check that fails. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import night_taps
import smoke
import solo_settings

PAGES = {"844": {"width": 844, "height": 390}, "667": {"width": 667, "height": 375}}
RATIO = 2
CANVAS_HEIGHT = 1080.0
ONE_ROW_MAX = 96.0
GAP = 6.0
MAIN_SCENE = "res://main.tscn"


def cards(state: dict, canvas_w: float, canvas_h: float) -> dict[str, tuple[float, float, float, float]]:
    """The HUD's cards as (left, top, width, height) in canvas units; the probe gives fractions of the window."""
    found = {}
    for entry in str(state.get("hud_cards", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, w, h = (float(n) for n in numbers.split(","))
            found[name] = (x * canvas_w, y * canvas_h, w * canvas_w, h * canvas_h)
    return found


def seed_settings(page, ui_size: float, left: bool) -> None:
    text = f"[accessibility]\n\nui_scale={ui_size}\n\n[controls]\n\nleft_handed={'true' if left else 'false'}\ntouch_hints_seen=255\n"
    if not page.evaluate(night_taps.WRITE_FILE_JS, [night_taps.SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def run(url: str, out: Path, result: dict, size: dict, ui_size: float, left: bool, bots: int, args) -> None:
    problems = result["problems"]
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(viewport=size, device_scale_factor=RATIO, has_touch=True, is_mobile=True)
        page = context.new_page()
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        page.add_init_script("Element.prototype.requestPointerLock = function () {};")
        target = f"{url}?touch=1"
        page.goto(target, wait_until="commit")
        smoke.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
        page.wait_for_timeout(3000)
        seed_settings(page, ui_size, left)
        page.goto(target, wait_until="commit")
        smoke.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
        page.wait_for_timeout(3000)
        # Solo, then the Play screen, where the Bots row is set.
        smoke.menu_item(page, "Play", 2)
        smoke.press(page, "Enter")
        smoke.wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", smoke.SCREEN_TIMEOUT_S)
        page.wait_for_timeout(1500)
        # The Bots row is walked to with the keys (at 1.25 the panel is wider than a 667 px page: a tap would miss).
        smoke.focus_control(page, "bots", "ArrowUp")
        smoke.step_value(page, "bots", "ArrowRight", bots)
        page.wait_for_timeout(600)
        result["play_rules"] = solo_settings.full(page).get("play_rules")
        smoke.focus_control(page, "Start", "ArrowDown")
        smoke.press(page, "Enter")
        smoke.wait_for_night(page)
        # The arrival show and the HUD's fade-in are over after a few seconds, and the first round starts after its break
        # (the objective card is not in a live night yet: only a capture sets an area).
        deadline = time.monotonic() + 90
        while not (
            "Points" in str(solo_settings.full(page).get("hud_cards", "")) and solo_settings.full(page).get("round", 0)
        ):
            if time.monotonic() > deadline:
                raise TimeoutError("the first round never started")
            page.wait_for_timeout(200)
        page.wait_for_timeout(3000)
        state = solo_settings.full(page)
        canvas_h = CANVAS_HEIGHT / ui_size
        found = cards(state, canvas_h * size["width"] / size["height"], canvas_h)
        result["canvas_h"] = canvas_h
        result["bots"] = state.get("bots")
        result["players"] = state.get("players")
        if state.get("bots") != bots:
            problems.append(f"[check] the night seated {state.get('bots')!r} bots, not the {bots} asked for")
        result["cards_units"] = {k: [round(v, 1) for v in rect] for k, rect in found.items()}
        result["round_card_css_px"] = round(found["Round"][3] * size["height"] / canvas_h, 1)
        page.screenshot(path=out / "night.png")
        round_card, objective, column, health = (found.get(n) for n in ("Round", "Objective", "Points", "Health"))
        if round_card is None or column is None:
            problems.append(f"[check] the HUD has no round card or column (cards: {sorted(found)})")
            browser.close()
            return
        if not args.before and round_card[3] > ONE_ROW_MAX:
            problems.append(f"[check] the round card is {round_card[3]:.1f} units high, over one row ({ONE_ROW_MAX})")
        if objective is not None and column[1] < objective[1] + objective[3] + GAP - 0.5:
            problems.append(f"[check] the column's top {column[1]:.1f} is not a gap under the objective")
        if health is not None and column[1] + column[3] > health[1] + 0.5:
            problems.append("[check] the column runs into the health card")
        result["column_units"] = [round(v, 1) for v in column]
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder of the real project")
    parser.add_argument("out", type=Path)
    parser.add_argument("--page", choices=sorted(PAGES), default="667")
    parser.add_argument("--ui", type=float, default=1.25)
    parser.add_argument("--left", action="store_true")
    parser.add_argument("--bots", type=int, default=7)
    parser.add_argument("--before", action="store_true", help="a build from before the change: no check on the card")
    parser.add_argument("--export", metavar="GODOT", help="export this checkout first, with the given Godot")
    parser.add_argument("--game", type=Path, help="with --export: a copy of the game folder to export instead")
    args = parser.parse_args()
    quiet = os.environ.get("GDS_QUIET") == "1" or os.environ.get("GDS_ALLOW_POINTER_LOCK") == "1"
    if sys.platform == "win32" and not quiet:
        print("refusing to run outside `gds quiet` (it takes pointer lock)", file=sys.stderr)
        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    web = Path(args.build)
    if args.game:
        door_swap.GAME = args.game
    if args.export:
        web = door_swap.export_bench(args.export, args.out / "export", MAIN_SCENE)
    server, port = smoke.serve(web)
    result: dict = {"problems": [], "page": args.page, "interface_size": args.ui, "left": args.left}
    try:
        run(
            f"http://127.0.0.1:{port}/index.html",
            args.out,
            result,
            PAGES[args.page],
            args.ui,
            args.left,
            args.bots,
            args,
        )
    except (TimeoutError, RuntimeError, PlaywrightError, KeyError) as error:
        result["problems"].append(f"[run] {error!r}")
    finally:
        server.shutdown()
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nround card check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nround card check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
