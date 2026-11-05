"""Browser check that the night's pause card is pressable on a phone (#1192), in the units a finger meets.

A phone's page is 844 x 390 CSS px with a pixel ratio of 2 (the page caps the ratio, `PhoneRender`), so the engine's
window is 1688 x 780. A night runs at the interface size alone, where one unit is 0.36 CSS px: the pause card's buttons
(Resume, Settings, Leave night) must be at least 44 CSS px high, and a finger that lands just inside the top edge of one
presses it. The sizes come from the probe's `menu_button_sizes` (fractions of the window); the finger is a real touch
event through the DevTools protocol.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/night_taps.py build/web build/night-taps

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import ingame_menu as menu
import smoke

PHONE = {"width": 844, "height": 390}
TAP_CSS_PX = 44.0
# A finger this far inside the top edge of a button presses it.
EDGE_CSS_PX = 4.0


def sizes(state: dict) -> dict[str, tuple[float, float]]:
    """Each shown button's size in CSS px: the probe's shares of the window times the page's size."""
    found = {}
    for entry in str(state.get("menu_button_sizes", "")).split("|"):
        name, _, share = entry.partition(":")
        if name:
            w, _, h = share.partition(",")
            found[name] = (float(w) * PHONE["width"], float(h) * PHONE["height"])
    return found


def run(browser_type, url: str, out: Path, result: dict) -> None:
    browser = browser_type.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport=PHONE, device_scale_factor=3, has_touch=True, is_mobile=True)
    page = context.new_page()
    problems = result["problems"]
    page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
    page.add_init_script("Element.prototype.requestPointerLock = function () {};")
    page.goto(f"{url}?touch=1", wait_until="commit")
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    smoke.start_solo(page)
    menu.wait_for(
        page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
    )
    page.wait_for_timeout(2500)
    result["page_ratio"] = page.evaluate("() => window.devicePixelRatio")
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    client = context.new_cdp_session(page)
    menu.tap(client, (menu.PAUSE_BUTTON[0] * PHONE["width"], menu.PAUSE_BUTTON[1] * PHONE["height"]))
    state = menu.wait_for(page, "the menu after the pause button", menu.menu_open)
    page.wait_for_timeout(500)
    page.screenshot(path=out / "phone_pause_card.png")
    found = sizes(state)
    result["button_css_px"] = {name: [round(w, 1), round(h, 1)] for name, (w, h) in found.items()}
    for name in ("Resume", "Settings", "Leave night"):
        if name not in found:
            problems.append(f"[check] no {name} button in the pause card (has {sorted(found)})")
        elif min(found[name]) < TAP_CSS_PX - 0.5:
            problems.append(f"[check] {name} is {found[name][0]:.1f} x {found[name][1]:.1f} CSS px, under {TAP_CSS_PX}")
    # A finger just inside the top edge of Leave night presses it: the night ends and the Play screen comes back.
    if "Leave night" in found:
        x, y = menu.spot(state, "Leave night", PHONE)
        menu.tap(client, (x, y - found["Leave night"][1] / 2 + EDGE_CSS_PX))
        left = menu.wait_for(page, "the screen before the night", lambda s: not s.get("night"))
        result["leave_night_by_its_top_edge"] = left.get("screen") == "play_screen"
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    quiet = os.environ.get("GDS_QUIET") == "1" or os.environ.get("GDS_ALLOW_POINTER_LOCK") == "1"
    if sys.platform == "win32" and not quiet:
        print("refusing to run outside `gds quiet` (it takes pointer lock)", file=sys.stderr)
        return 2
    args.out.mkdir(parents=True, exist_ok=True)
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    result: dict = {"problems": []}
    with sync_playwright() as p:
        try:
            run(p.chromium, url, args.out, result)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            result["problems"].append(f"[run] {error}")
        finally:
            if server:
                server.shutdown()
    if not result.get("leave_night_by_its_top_edge"):
        result["problems"].append("[check] leave_night_by_its_top_edge is not true")
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["problems"]:
        print(f"\nnight taps check FAILED with {len(result['problems'])} problem(s)", file=sys.stderr)
        return 1
    print("\nnight taps check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
