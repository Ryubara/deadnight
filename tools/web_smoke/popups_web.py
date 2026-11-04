"""What the popup lane costs a frame in the web build (issue #1064): `game/tools/captures/popup_web.tscn` puts up a
HUD with a round banner and a boss bar, then four stacks of cards in real time, and reads the length of every frame.

Exports a copy of the project that starts on the capture (the real one starts on the menu), loads it in
Chrome, and prints the numbers and writes them as `web_popups.json`, with a screenshot of the cards, to the output
folder. The run fails on a page error, or when the longest frame with cards up is more than `MAX_JUMP_MS` over the
longest of the quiet HUD.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/popups_web.py <godot> <work folder> <out folder> \\
        [--gl gpu|software] [--build <folder of an earlier export>]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import smoke

SCENE = "res://tools/captures/popup_web.tscn"
MAX_JUMP_MS = 40.0
TIMEOUT_S = 300


def measure(playwright, gl: str, url: str, out: Path) -> dict:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    errors: list[str] = []
    try:
        page = browser.new_page(viewport={"width": 1760, "height": 960})
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.goto(url, wait_until="commit")
        shot_taken = False
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            state = page.evaluate("window.__popups || null")
            if state and state.get("done"):
                return {"counts": state["counts"], "errors": errors}
            if state and state.get("stage") == 3 and not shot_taken:
                time.sleep(1.2)
                page.screenshot(path=str(out / "web_popups.png"))
                shot_taken = True
            time.sleep(0.1)
        errors.append("never finished")
        return {"counts": {}, "errors": errors}
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
            result = measure(p, args.gl, f"http://127.0.0.1:{port}/index.html", args.out)
    finally:
        server.shutdown()
    print(json.dumps(result, indent=2), flush=True)
    (args.out / "web_popups.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    counts = result["counts"]
    if counts and counts["busy_max_ms"] - counts["quiet_max_ms"] > MAX_JUMP_MS:
        print(
            f"a frame with cards up is {counts['busy_max_ms'] - counts['quiet_max_ms']:.1f} ms over the quiet HUD's longest"
        )
        return 1
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
