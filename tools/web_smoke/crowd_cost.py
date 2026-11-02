"""What a zombie crowd costs in the browser, system by system (issue #105).

Exports a copy of the project that starts on `game/tests/captures/crowd_cost_bench.tscn` (the real project's export
leaves `tests/` out), loads it once per cell in a fresh browser, and prints, for each crowd size and each system left
out, the milliseconds a frame the bench's clocks read: the director's brains and bodies, the navigation paths, the wire
format's encode, decode and the views' update, the animation, and the rest of the frame (the drawing and the engine).

    uv run --with playwright==1.64.1 python tools/web_smoke/crowd_cost.py <godot> <work folder> \\
        [--browser chrome|firefox] [--throttle 4] [--zombies 0 20 40] [--ablate none draw animation navigation views] \\
        [--runs 2] [--build <folder of an earlier export>]

`<godot>` is the pinned Godot (`gds tool path godot`). `chrome` is the installed Chrome with this machine's GPU and
the display's frame limit lifted; `--throttle N` slows its processor N times (`Emulation.setCPUThrottlingRate`, a rough
stand-in for a weak laptop's CPU, not its GPU); `firefox` is Playwright's Firefox (`playwright install firefox`), with
its timer precision restored (a browser rounds `performance.now()` to a millisecond otherwise, which would turn the
bench's per-stage clocks into noise). Writes `rows.json` and `summary.json` into the work folder.
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

BENCH_SCENE = "res://tests/captures/crowd_cost_bench.tscn"
TIMEOUT_S = 240
FIREFOX_PREFS = {"privacy.reduceTimerPrecision": False, "privacy.resistFingerprinting": False}


def run_cell(playwright, browser_name: str, throttle: float, url: str) -> dict:
    """One page load: the bench's report, or an error."""
    if browser_name == "firefox":
        browser = playwright.firefox.launch(headless=True, firefox_user_prefs=FIREFOX_PREFS)
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.UNPACED)
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        if throttle > 1 and browser_name != "firefox":
            cdp = page.context.new_cdp_session(page)
            cdp.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            report = page.evaluate("window.__bench || null")
            if report:
                return report
            time.sleep(0.5)
        return {"error": "the bench never reported", "page_errors": errors[:3]}
    finally:
        browser.close()


def per_zombie(report: dict) -> dict:
    """The stages a frame pays, as a share of the crowd: microseconds a zombie, per frame (and per tick for the sim)."""
    alive = max(report["alive"], 1.0)
    return {key: round(ms * 1000.0 / alive, 1) for key, ms in report["ms_per_frame"].items()}


def summarise(rows: list[dict]) -> dict:
    """Medians over the runs of a cell, keyed `zombies/ablate`."""
    cells: dict[str, list[dict]] = {}
    for row in rows:
        if "error" in row:
            continue
        cells.setdefault(f"{row['zombies_asked']}/{row['ablate'] or 'none'}", []).append(row)
    out = {}
    for key, runs in cells.items():
        stages = {
            stage: round(statistics.median(r["ms_per_frame"][stage] for r in runs), 3)
            for stage in runs[0]["ms_per_frame"]
        }
        out[key] = {
            "runs": len(runs),
            "alive": round(statistics.median(r["alive"] for r in runs), 1),
            "frame_mean_ms": round(statistics.median(r["frame_mean_ms"] for r in runs), 2),
            "frame_p95_ms": round(statistics.median(r["frame_p95_ms"] for r in runs), 2),
            "ticks_per_frame": round(statistics.median(r["ticks_per_frame"] for r in runs), 2),
            "draw_calls": round(statistics.median(r["draw_calls"] for r in runs), 1),
            "advanced_per_frame": round(statistics.median(r["animations_advanced_per_frame"] for r in runs), 1),
            "ms_per_frame": stages,
        }
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--browser", choices=("chrome", "firefox"), default="chrome")
    parser.add_argument("--throttle", type=float, default=1.0)
    parser.add_argument("--zombies", type=int, nargs="+", default=[0, 20, 40])
    parser.add_argument("--ablate", nargs="+", default=["none"])
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--frames", type=int, default=400)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, BENCH_SCENE)
    server, port = smoke.serve(web)
    rows: list[dict] = []
    try:
        with sync_playwright() as p:
            for ablate in args.ablate:
                for zombies in args.zombies:
                    for _ in range(args.runs):
                        query = f"zombies={zombies}&frames={args.frames}&warmup=8"
                        if ablate != "none":
                            query += f"&ablate={ablate}"
                        row = run_cell(p, args.browser, args.throttle, f"http://127.0.0.1:{port}/index.html?{query}")
                        row.update({"browser": args.browser, "throttle": args.throttle})
                        rows.append(row)
                        print(json.dumps(row), flush=True)
    finally:
        server.shutdown()
    (args.work / "rows.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    summary = summarise(rows)
    (args.work / "summary.json").write_text(json.dumps(summary, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
