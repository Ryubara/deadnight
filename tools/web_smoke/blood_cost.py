"""What hit blood costs a frame in the browser (issue #618).

Exports a copy of the project that starts on `game/tests/captures/blood_cost_bench.tscn` (the real project's export
leaves `tests/` out), loads it once per cell in a fresh headless browser, and prints the milliseconds a frame takes
while the N zombies nearest the camera are hit `--hits` times a second each (`?blood=1`: splashes and marks drawn)
against the same hits with no blood drawn (`?blood=0`), in a crowd of `--zombies`.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/blood_cost.py <godot> <work folder> \\
        [--gl gpu|software] [--throttle 4] [--zombies 20] [--hits 4] [--runs 3] [--build <folder of an earlier export>]

`gpu` is the installed Chrome with this machine's GPU and the display's frame limit lifted; `software` is Chromium on
SwiftShader (what CI draws with, and a stand-in for a weak GPU: every pixel is paid for); `--throttle N` slows the
processor N times. Writes `rows.json` into the work folder.
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

BENCH_SCENE = "res://tests/captures/blood_cost_bench.tscn"
TIMEOUT_S = 400


def run_cell(playwright, gl: str, throttle: float, url: str) -> dict:
    """One page load: the bench's report, or an error."""
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.UNPACED, *smoke.mute_args()])
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        if throttle > 1:
            page.context.new_cdp_session(page).send("Emulation.setCPUThrottlingRate", {"rate": throttle})
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            report = page.evaluate("window.__bench || null")
            if report:
                report["console_errors"] = errors[:3]
                return report
            time.sleep(0.5)
        return {"error": "the bench never reported", "page_errors": errors[:3]}
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--throttle", type=float, default=1.0)
    parser.add_argument("--zombies", type=int, default=20)
    parser.add_argument("--hits", type=float, default=4.0)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--frames", type=int, default=400)
    parser.add_argument("--warmup", type=int, default=8)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, BENCH_SCENE)
    server, port = smoke.serve(web)
    rows: list[dict] = []
    try:
        with sync_playwright() as p:
            # Interleaved, so a slow minute of the machine hits every cell alike.
            for _ in range(args.runs):
                for blood in (0, 1):
                    query = (
                        f"zombies={args.zombies}&targets={args.zombies}&hits={args.hits}&frames={args.frames}"
                        f"&warmup={args.warmup}&blood={blood}"
                    )
                    row = run_cell(p, args.gl, args.throttle, f"http://127.0.0.1:{port}/index.html?{query}")
                    row.update({"gl": args.gl, "throttle": args.throttle})
                    rows.append(row)
                    print(json.dumps({k: v for k, v in row.items() if k != "ms_per_frame"}), flush=True)
    finally:
        server.shutdown()
    (args.work / "rows.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    print(f"{'blood':>5} {'frame ms':>9} {'p95 ms':>8} {'draw calls':>11} {'gpu ms':>7} {'splashes':>9} {'marks':>6}")
    for blood in (False, True):
        cells = [r for r in rows if r.get("blood") is blood and "error" not in r]
        if not cells:
            continue
        print(
            f"{int(blood):>5} "
            f"{statistics.median(r['frame_mean_ms'] for r in cells):>9.2f} "
            f"{statistics.median(r['frame_p95_ms'] for r in cells):>8.2f} "
            f"{statistics.median(r['draw_calls'] for r in cells):>11.1f} "
            f"{statistics.median(r['gpu_ms'] for r in cells):>7.3f} "
            f"{statistics.median(r['splashes_alive'] for r in cells):>9.1f} "
            f"{statistics.median(r['marks_alive'] for r in cells):>6.1f}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
