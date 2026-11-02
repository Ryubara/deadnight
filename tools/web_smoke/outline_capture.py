"""Photographs the outline through walls in the web build (issue #523): the same three spots as the desktop tour
(`game/tests/captures/outline_tour.tscn`), with the outline on and off.

Exports a copy of the project that starts on the tour (the real project's export leaves `tests/` out), loads it once
per spot and mode in a fresh headless browser, waits for the page to say the spot has settled (`window.__outline`) and
takes a screenshot of the page.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/outline_capture.py <godot> <work folder> <out folder> \\
        [--gl gpu|software] [--build <folder of an earlier export>]
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import smoke

SCENE = "res://tests/captures/outline_tour.tscn"
SPOTS = ("near", "far", "open")
TIMEOUT_S = 300
HOLD_FRAMES = 60


def shoot(playwright, gl: str, url: str, out: Path) -> str:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            if page.evaluate("window.__outline || null"):
                time.sleep(0.5)
                page.screenshot(path=str(out))
                return "ok" + (f" (console errors: {errors[:2]})" if errors else "")
            time.sleep(0.5)
        return f"never settled {errors[:2]}"
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    try:
        with sync_playwright() as p:
            for mode in ("on", "off"):
                for spot in SPOTS:
                    query = f"spot={spot}&hold={HOLD_FRAMES}" + ("&off=1" if mode == "off" else "")
                    out = args.out / f"web_{args.gl}_{spot}_{mode}.png"
                    print(out.name, shoot(p, args.gl, f"http://127.0.0.1:{port}/index.html?{query}", out), flush=True)
    finally:
        server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
