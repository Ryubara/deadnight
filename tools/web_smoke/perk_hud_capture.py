"""Films the perk badges and the DOWN card's self-revive in the web build (issue #707): no perks, one, four, down alone with
the revive perk (the card counts the self-revive down), up again, and down with a teammate (the perks gone), the same
stages as the desktop tour (`game/tests/captures/perk_hud_tour.tscn`).

Exports a copy of the project that starts on the tour (the real project's export leaves `tests/` out), loads it in
Chrome once for each viewport and writes `web_<viewport>_<stage>.png` into the output folder, plus the console errors.
A phone viewport runs with touch (the touch controls and the phone layout); `--viewports` takes `WIDTHxHEIGHT` and a
trailing `t` for touch, e.g. `1280x720,844x390t`.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/perk_hud_capture.py <godot> <work folder> <out folder> \\
        [--gl gpu|software] [--viewports 1280x720,1920x1080,844x390t] [--build <folder of an earlier export>]
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

SCENE = "res://tests/captures/perk_hud_tour.tscn"
VIEWPORTS = "1280x720,1920x1080,2560x1440,844x390t"
TIMEOUT_S = 420
# How long after a stage is announced the screenshot is taken: the tour holds each stage for 45 physics frames.
SHOT_AFTER_S = 0.6


def film(playwright, gl: str, url: str, out: Path, width: int, height: int, touch: bool) -> dict:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    result: dict = {"viewport": f"{width}x{height}", "touch": touch, "shots": [], "errors": []}
    try:
        page = browser.new_page(viewport={"width": width, "height": height}, has_touch=touch)
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
                page.screenshot(path=str(out / f"web_{width}x{height}_{name}.png"))
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
    parser.add_argument("--viewports", default=VIEWPORTS)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    results = []
    try:
        with sync_playwright() as p:
            for spec in args.viewports.split(","):
                touch = spec.endswith("t")
                width, height = (int(part) for part in spec.rstrip("t").split("x"))
                query = "?touch=1" if touch else ""
                outcome = film(p, args.gl, f"http://127.0.0.1:{port}/index.html{query}", args.out, width, height, touch)
                print(spec, len(outcome["shots"]), "shots", outcome["errors"][:3], flush=True)
                results.append(outcome)
    finally:
        server.shutdown()
    (args.out / "web_result.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 1 if any(r["errors"] for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
