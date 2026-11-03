"""Films the six perks in the web build, from the player's camera (issue #687): each machine with its prompt card and its
pour, and each effect (the shock shader on the dead, faster fire and reload with their measured numbers, three weapons,
a faster revive and the solo self-revive), the same cases as the desktop sheet (`game/tests/captures/perks_sheet.tscn`).

Exports a copy of the project that starts on the sheet (the real project's export leaves `tests/` out), loads it in a
fresh Chrome once for each group, follows `window.__perks` (which case is on) and writes `web_<case>.png` into the output
folder, plus the console errors and the longest frame of each group.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/perks_capture.py <godot> <work folder> <out folder> \
        [--gl gpu|software] [--groups machines,shock,...] [--build <folder of an earlier export>]
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

SCENE = "res://tests/captures/perks_sheet.tscn"
GROUPS = ["machines", "shock", "fire", "reload", "third", "revive", "self"]
TIMEOUT_S = 420
# How long after a case is announced the screenshot is taken: the sheet holds each shot for 45 physics frames.
SHOT_AFTER_S = 0.6


def film(playwright, gl: str, url: str, out: Path, group: str) -> dict:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    result: dict = {"group": group, "shots": [], "errors": []}
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        page.on("pageerror", lambda error: result["errors"].append(str(error)))
        page.on("console", lambda m: result["errors"].append(m.text) if m.type == "error" else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        seen = 0
        while time.monotonic() < deadline:
            state = page.evaluate("window.__perks || null")
            if state and state.get("done"):
                break
            if state and state.get("index", 0) > seen:
                seen = state["index"]
                name = state["case"]
                time.sleep(SHOT_AFTER_S)
                page.screenshot(path=str(out / f"web_{name}.png"))
                result["shots"].append(name)
            time.sleep(0.05)
        else:
            result["errors"].append("never finished")
        return result
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--groups", default=",".join(GROUPS))
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    results = []
    try:
        with sync_playwright() as p:
            for group in args.groups.split(","):
                url = f"http://127.0.0.1:{port}/index.html?group={group}"
                outcome = film(p, args.gl, url, args.out, group)
                print(group, len(outcome["shots"]), "shots", outcome["errors"][:3], flush=True)
                results.append(outcome)
    finally:
        server.shutdown()
    (args.out / "web_result.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 1 if any(r["errors"] for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
