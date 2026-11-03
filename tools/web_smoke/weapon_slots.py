"""Browser check of the weapon slot keys and strip (#682).

Starts a solo night in headless Chromium the way a player does, then presses the number keys the way a keyboard
sends them: 1 takes the first weapon carried in hand, 2 the second; the key of the weapon already in hand and the key
of an empty slot change nothing (a solo night starts with the pistol alone, so those are the keys it can press). After each press it reads what the game says is in hand and in which slot
(`window.deadnight.weapon`, `weapon_slots`, `weapon_slot_held`, game/core/web_probe.gd) and takes a capture, so the
strip over the ammo card can be looked at in the browser at the viewport asked for.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/weapon_slots.py build/web build/weapon-slots \\
        [--viewport 1280x720] [--touch]

Run it through `gds quiet` on Windows like every browser probe (docs/godot/web-export.md).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright
from pointer_lock import SOFTWARE_GL, press, probe, serve, wait_for
from smoke import start_solo

LOAD_TIMEOUT_S = 150
NIGHT_LOAD_TIMEOUT_S = 300
REACT_S = 8.0
KEYS = {1: "Digit1", 2: "Digit2", 3: "Digit3"}
SNAPSHOT_KEYS = ("weapon", "weapon_slots", "weapon_slot_held", "running")


def seen(page: Page) -> dict:
    state = probe(page)
    return {key: state.get(key) for key in SNAPSHOT_KEYS}


def run(page: Page, url: str, out: Path, result: dict, problems: list[str]) -> None:
    page.goto(url, wait_until="commit")
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)
    start_solo(page)
    wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
    page.wait_for_timeout(2000)
    start = wait_for(page, "the strip's weapons", lambda s: bool(s.get("weapon_slots")), REACT_S)
    slots = str(start["weapon_slots"]).split(",")
    result["slots"] = slots
    result["start"] = seen(page)
    page.screenshot(path=out / "1_start.png")

    # (key, the weapon that must be in hand afterwards). A solo night starts with the pistol alone, so the keys
    # a player can press are the one of the weapon in hand and the ones of empty slots: none of them may change
    # anything. With two weapons carried (a night that gave one) the keys pick, as the desktop run shows.
    if len(slots) >= 2:
        steps = [(1, slots[0]), (2, slots[1]), (2, slots[1]), (3, slots[1]), (1, slots[0]), (1, slots[0])]
    else:
        steps = [(1, slots[0]), (2, slots[0]), (3, slots[0]), (1, slots[0])]
    for index, (slot, expected) in enumerate(steps, start=2):
        press(page, KEYS[slot])
        page.wait_for_timeout(700)
        state = seen(page)
        name = f"{index}_key_{slot}"
        result[name] = state
        page.screenshot(path=out / f"{name}.png")
        if state["weapon"] != expected:
            problems.append(f"[check] after key {slot} the weapon in hand is {state['weapon']}, expected {expected}")
        if state["weapon_slot_held"] != slots.index(expected) + 1:
            problems.append(f"[check] after key {slot} the lit slot is {state['weapon_slot_held']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("build", type=Path, help="the web export folder (index.html inside)")
    parser.add_argument("out", type=Path, help="where the captures and result.json go")
    parser.add_argument("--viewport", default="1280x720", help="the page size, WIDTHxHEIGHT")
    parser.add_argument("--touch", action="store_true", help="a touch device (the phone's controls and layout)")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    width, height = (int(part) for part in args.viewport.split("x"))
    server, port = serve(args.build)
    problems: list[str] = []
    result: dict = {"viewport": args.viewport, "touch": args.touch}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        page = browser.new_page(viewport={"width": width, "height": height}, has_touch=args.touch)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        try:
            run(page, f"http://127.0.0.1:{port}/index.html", args.out, result, problems)
        except (TimeoutError, RuntimeError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=args.out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            browser.close()
            server.shutdown()
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\nweapon slots check FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
