"""What eight level tags cost to draw in the web build (issue #1060): the draw calls of `game/tools/captures/level_tags.tscn`
for eight icons from one atlas, from eight textures, as `TextureRect`s, and as whole tags with their words.

Exports a copy of the project that starts on the capture (the real one starts on the menu), loads it in
Chrome, and prints the counts and writes them as `web_level_tags.json`, with a screenshot of the tags, to the output
folder.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/level_tags_cost.py <godot> <work folder> <out folder> \\
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

SCENE = "res://tools/captures/level_tags.tscn"
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
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            state = page.evaluate("window.__level_tags || null")
            if state and state.get("done"):
                time.sleep(0.5)
                page.screenshot(path=str(out / "web_level_tags.png"))
                return {"counts": state["counts"], "errors": errors}
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
    (args.out / "web_level_tags.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
