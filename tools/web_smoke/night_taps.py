"""Browser check that a night is pressable on a phone (#1192, #1217), in the units a finger meets.

A phone's page is 844 x 390 CSS px with a pixel ratio of 2 (the page caps the ratio, `PhoneRender`), so the engine's
window is 1688 x 780. A night runs at the interface size alone, where one unit is 0.36 CSS px (0.29 at the smallest
interface size, `--ui 0.8`):

- every hit area of the touch layer (the probe's `touch_hits`, fractions of the window) is at least 44 CSS px across;
  a real touch just inside the edge of Ping, Melee and Pause presses that button (the
  probe's `touch_held`), and one just outside the edge presses none;
- the pause card's buttons (Resume, Settings, Leave night) are at least 44 CSS px high, and a finger that lands just
  inside the top edge of one presses it (the probe's `menu_button_sizes`).

The finger is a real touch event through the DevTools protocol. `--ui` writes the interface size into the page's saved
settings and reloads, as the Settings screen's "Interface size" would.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/night_taps.py build/web build/night-taps [--ui 0.8]

Screenshots and `result.json` go to the second argument. Exits 1 on any check that fails.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
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
# A finger this far inside a hit area's edge presses it, and this far outside it presses nothing (#1217).
INSIDE_HIT_CSS_PX = 1.0
OUTSIDE_HIT_CSS_PX = 1.5
# The buttons tried at the edge of their hit areas. Pause opens the menu, so the caller taps it last.
EDGE_BUTTONS = ("ping", "quick_melee")
SETTINGS_FILE = "/userfs/godot/app_userdata/Deadnight/settings.cfg"
# Godot's web build mirrors `user://` into IndexedDB `/userfs`, store `FILE_DATA`, one record a file.
WRITE_FILE_JS = """([path, text]) => new Promise((resolve) => {
  const open = indexedDB.open('/userfs');
  open.onerror = () => resolve(false);
  open.onsuccess = () => {
    const db = open.result;
    const transaction = db.transaction('FILE_DATA', 'readwrite');
    transaction.objectStore('FILE_DATA').put(
      { timestamp: new Date(), mode: 33206, contents: new TextEncoder().encode(text) }, path);
    transaction.oncomplete = () => { db.close(); resolve(true); };
    transaction.onerror = () => { db.close(); resolve(false); };
  };
})"""


def sizes(state: dict) -> dict[str, tuple[float, float]]:
    """Each shown button's size in CSS px: the probe's shares of the window times the page's size."""
    found = {}
    for entry in str(state.get("menu_button_sizes", "")).split("|"):
        name, _, share = entry.partition(":")
        if name:
            w, _, h = share.partition(",")
            found[name] = (float(w) * PHONE["width"], float(h) * PHONE["height"])
    return found


def hits(state: dict) -> dict[str, tuple[float, float, float, float]]:
    """Each touch hit area as (x, y, radius, radius before the fingertip rule) in CSS px."""
    found = {}
    for entry in str(state.get("touch_hits", "")).split("|"):
        name, _, numbers = entry.partition(":")
        if name:
            x, y, hit, was = (float(n) for n in numbers.split(","))
            found[name] = (x * PHONE["width"], y * PHONE["height"], hit * PHONE["height"], was * PHONE["height"])
    return found


def room(spot: tuple[float, float], skip: str, found: dict) -> float:
    """How far `spot` is outside every other hit area (negative: inside one), in CSS px."""
    least = float("inf")
    for name, (x, y, hit, _) in found.items():
        if name != skip:
            least = min(least, math.hypot(spot[0] - x, spot[1] - y) - hit)
    return least


def spot_at(name: str, found: dict, offset: float) -> tuple[float, float]:
    """A point `offset` CSS px past the edge of `name`'s hit area (inside when negative), in the direction on the page
    with the most room from the other hit areas."""
    x, y, hit, _ = found[name]
    best, best_room = (x, y), -float("inf")
    for step in range(48):
        angle = math.tau * step / 48
        spot = (x + math.cos(angle) * (hit + offset), y + math.sin(angle) * (hit + offset))
        if not (0 <= spot[0] <= PHONE["width"] and 0 <= spot[1] <= PHONE["height"]):
            continue
        free = room(spot, name, found)
        if free > best_room:
            best, best_room = spot, free
    return best


def held_after_touch(page, client, spot: tuple[float, float], expect_held: bool) -> str:
    """Puts a finger down on `spot`, reads which touch buttons the game says are held, and lifts the finger."""
    menu.smoke_touch(client, "touchStart", [(1, *spot)])
    end = time.monotonic() + 1.5
    held = ""
    while time.monotonic() < end:
        held = str(menu.probe(page).get("touch_held", ""))
        if bool(held) == expect_held:
            break
        page.wait_for_timeout(80)
    menu.smoke_touch(client, "touchEnd", [])
    page.wait_for_timeout(300)
    return held


def edge_taps(page, client, state: dict, result: dict) -> None:
    """Real touches at the edge of each grown hit area: just inside presses that button, just outside presses none."""
    found = hits(state)
    problems = result["problems"]
    result["hit_area_css_px"] = {name: round(hit * 2, 1) for name, (_, _, hit, _) in found.items()}
    result["old_hit_area_css_px"] = {name: round(was * 2, 1) for name, (_, _, _, was) in found.items()}
    for name, (_, _, hit, _) in found.items():
        if hit * 2 < TAP_CSS_PX - 0.5:
            problems.append(f"[check] the {name} hit area is {hit * 2:.1f} CSS px, under {TAP_CSS_PX}")
    result["edge_taps"] = {}
    for name in EDGE_BUTTONS:
        if name not in found:
            problems.append(f"[check] the touch layer has no {name} button (has {sorted(found)})")
            continue
        inside = held_after_touch(page, client, spot_at(name, found, -INSIDE_HIT_CSS_PX), True)
        outside = held_after_touch(page, client, spot_at(name, found, OUTSIDE_HIT_CSS_PX), False)
        result["edge_taps"][name] = {"inside": inside, "outside": outside}
        if inside != name:
            problems.append(f"[check] a touch just inside the {name} hit area pressed {inside!r}")
        if outside:
            problems.append(f"[check] a touch just outside the {name} hit area pressed {outside!r}")


def seed_interface_size(page, size: float) -> None:
    """The saved setting the next load reads: what the Settings screen's "Interface size" writes."""
    text = f"[accessibility]\n\nui_scale={size}\n"
    if not page.evaluate(WRITE_FILE_JS, [SETTINGS_FILE, text]):
        raise RuntimeError("could not write the settings file into the page's storage")


def run(browser_type, url: str, out: Path, result: dict, ui_size: float) -> None:
    browser = browser_type.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport=PHONE, device_scale_factor=3, has_touch=True, is_mobile=True)
    page = context.new_page()
    problems = result["problems"]
    page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
    page.add_init_script("Element.prototype.requestPointerLock = function () {};")
    page.goto(f"{url}?touch=1", wait_until="commit")
    menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(3000)
    if ui_size != 1.0:
        seed_interface_size(page, ui_size)
        page.goto(f"{url}?touch=1", wait_until="commit")
        menu.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
        page.wait_for_timeout(3000)
    smoke.start_solo(page)
    menu.wait_for(
        page, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S
    )
    page.wait_for_timeout(2500)
    result["interface_size"] = ui_size
    result["page_ratio"] = page.evaluate("() => window.devicePixelRatio")
    result["canvas_px"] = page.evaluate(
        "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
    )
    client = context.new_cdp_session(page)
    layer = menu.wait_for(page, "the touch layer", lambda s: bool(s.get("touch_hits")))
    page.screenshot(path=out / "phone_touch_layer.png")
    edge_taps(page, client, layer, result)
    # Pause by a finger just inside its hit area's edge, where the added margin is.
    found = hits(layer)
    if "pause" in found:
        menu.tap(client, spot_at("pause", found, -INSIDE_HIT_CSS_PX))
    else:
        problems.append("[check] the touch layer has no pause button")
    state = menu.wait_for(page, "the menu after the pause button", menu.menu_open)
    page.wait_for_timeout(500)
    page.screenshot(path=out / "phone_pause_card.png")
    found_sizes = sizes(state)
    result["button_css_px"] = {name: [round(w, 1), round(h, 1)] for name, (w, h) in found_sizes.items()}
    for name in ("Resume", "Settings", "Leave night"):
        if name not in found_sizes:
            problems.append(f"[check] no {name} button in the pause card (has {sorted(found_sizes)})")
        elif min(found_sizes[name]) < TAP_CSS_PX - 0.5:
            problems.append(
                f"[check] {name} is {found_sizes[name][0]:.1f} x {found_sizes[name][1]:.1f} CSS px, under {TAP_CSS_PX}"
            )
    # A finger just inside the top edge of Leave night presses it: the night ends and the Play screen comes back.
    if "Leave night" in found_sizes:
        x, y = menu.spot(state, "Leave night", PHONE)
        menu.tap(client, (x, y - found_sizes["Leave night"][1] / 2 + EDGE_CSS_PX))
        left = menu.wait_for(page, "the screen before the night", lambda s: not s.get("night"))
        result["leave_night_by_its_top_edge"] = left.get("screen") == "play_screen"
    browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--ui", type=float, default=1.0, help="the interface size to run at (0.8, 1.0 or 1.25)")
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
            run(p.chromium, url, args.out, result, args.ui)
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
