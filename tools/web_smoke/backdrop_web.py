"""The small map's outside backdrop in the web build (issue #638): photographs and frame cost.

Exports a copy of the project that starts on `game/tests/captures/smallmap_backdrop_tour.tscn` (the real project's
export leaves `tests/` out). Then, in a fresh headless browser each time:

- `shots`: loads each spot (the window, the broken wall, the doorway, the broken roof) with the backdrop shown and
  hidden, waits for the page to say it settled (`window.__backdrop`) and takes a screenshot;
- `bench`: holds the window spot and alternates blocks of frames with the backdrop shown and hidden, and prints the
  page's report (`window.__bench`): frame milliseconds, draw calls and primitives for each.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/backdrop_web.py <godot> <work folder> <out folder> \\
        [--gl gpu|software] [--runs 3] [--frames 600] [--build <folder of an earlier export>] [--no-shots]

`gpu` is the installed Chrome with this machine's GPU and the display's frame limit lifted (the bench needs it: a
paced page waits for the display); `software` is Chromium on SwiftShader, every pixel paid by the processor.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import smoke

SCENE = "res://tests/captures/smallmap_backdrop_tour.tscn"
SPOTS = ("window", "broken_wall", "door", "roof", "yard")
TIMEOUT_S = 300
HOLD_FRAMES = 60


def launch(playwright, gl: str):
    if gl == "software":
        return playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    return playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.UNPACED, *smoke.mute_args()])


def wait(page, expression: str) -> dict | None:
    deadline = time.monotonic() + TIMEOUT_S
    while time.monotonic() < deadline:
        value = page.evaluate(f"{expression} || null")
        if value:
            return value
        time.sleep(0.5)
    return None


def shoot(playwright, gl: str, url: str, out: Path) -> str:
    browser = launch(playwright, gl)
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.goto(url, wait_until="commit")
        if not wait(page, "window.__backdrop"):
            return f"never settled {errors[:2]}"
        time.sleep(0.5)
        page.screenshot(path=str(out))
        return "ok" + (f" (console errors: {errors[:2]})" if errors else "")
    finally:
        browser.close()


def bench(playwright, gl: str, url: str) -> dict:
    browser = launch(playwright, gl)
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(url, wait_until="commit")
        report = wait(page, "window.__bench")
        return report or {"error": "the bench never reported", "page_errors": errors[:3]}
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    parser.add_argument("--no-shots", action="store_true")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    base = f"http://127.0.0.1:{port}/index.html"
    rows = []
    try:
        with sync_playwright() as p:
            if not args.no_shots:
                for mode in ("on", "off"):
                    for spot in SPOTS:
                        query = f"spot={spot}&hold={HOLD_FRAMES}" + ("&off=1" if mode == "off" else "")
                        out = args.out / f"web_{args.gl}_{spot}_{mode}.png"
                        print(out.name, shoot(p, args.gl, f"{base}?{query}", out), flush=True)
            for _ in range(args.runs):
                row = bench(p, args.gl, f"{base}?bench=1&frames={args.frames}")
                rows.append(row)
                print("BENCH", json.dumps(row), flush=True)
    finally:
        server.shutdown()
    (args.out / f"bench_{args.gl}.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    good = [r for r in rows if "error" not in r]
    if good:
        for key in ("on", "off"):
            print(
                f"{key:>4}: mean {statistics.median(r[key + '_ms']['mean'] for r in good):.2f} ms, "
                f"p95 {statistics.median(r[key + '_ms']['p95'] for r in good):.2f} ms, "
                f"draws {statistics.median(r[key + '_draws'] for r in good):.0f}, "
                f"primitives {statistics.median(r[key + '_prims'] for r in good):.0f}"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
