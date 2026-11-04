"""The idle main menu in the browser, frame by frame, for two or more builds side by side (issue #989).

The web smoke reads the menu's frames for three seconds (`menu_frames`) with the stage a still, and a still should cost
nothing. This opens each build in a new Chromium (SwiftShader, as CI), lets the menu settle as the smoke does (click,
2.5 s), then follows `--seconds` of the page's own `requestAnimationFrame` deltas and, in each frame, the WebGL calls
the engine made (`smoke.trace`: draws, clears, framebuffer blits and bindings, texture uploads). The counts do not
depend on the machine: a frame that draws the 3D stage again shows in them, a runner that is merely slow does not.
The browser processes' CPU seconds are read before and after (CDP `SystemInfo.getProcessInfo`); the GPU process runs
SwiftShader's threads, which spin while they wait, so that figure says whether two builds ask the same of the CPU,
not how much work a frame is. The builds take turns, `--pairs` times each, so a drifting machine hits both alike.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/menu_idle.py before=build/web_before after=build/web_after \\
        --out scratch/menu-idle --pairs 4

`--throttle N` slows the page's CPU by N (Chrome's emulation), `--flag` adds a Chrome flag, `--query ?stage=still
--screen menu_stage_screen` opens the stage alone. To pin the whole run to some cores (a runner has two), start it from
a process whose affinity is set: the browser inherits it.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright
from smoke import (
    FRAME_TIMES_JS,
    LOAD_TIMEOUT_S,
    MENU_FRAME_SECONDS,
    SOFTWARE_GL,
    VIEWPORT,
    probe,
    serve,
    stats,
    trace,
    wait_for,
)

SETTLE_MS = 2500


def process_cpu(cdp) -> dict[str, float]:
    """CPU seconds used so far by the browser's processes, by kind (browser, renderer, GPU)."""
    totals: dict[str, float] = {}
    for info in cdp.send("SystemInfo.getProcessInfo")["processInfo"]:
        totals[info["type"]] = totals.get(info["type"], 0.0) + info["cpuTime"]
    return totals


def run_one(
    build: Path, seconds: float, shot_path: Path, throttle: float, query: str, screen: str, flags: list[str]
) -> dict:
    server, port = serve(build)
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL + flags)
            page = browser.new_page(viewport=VIEWPORT)
            if throttle > 1:  # a slower CPU, as the runner's: every task of the page takes this many times as long
                cdp = page.context.new_cdp_session(page)
                cdp.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
            browser_cdp = browser.new_browser_cdp_session()
            started = time.monotonic()
            page.goto(f"http://127.0.0.1:{port}/index.html{query}", wait_until="commit")
            wait_for(page, f"the {screen} screen", lambda s: s.get("screen") == screen, LOAD_TIMEOUT_S)
            load_s = round(time.monotonic() - started, 2)
            page.mouse.click(5, 5)
            page.wait_for_timeout(SETTLE_MS)
            # What the smoke does before its window (it reads the probe and takes a screenshot), then the window itself
            # with no wrapped WebGL calls, so its `menu_frames` can be read beside the trace. A build whose menu is
            # still busy answers differently with and without these two calls (#989).
            probe(page)
            page.screenshot(path=shot_path)
            gate = stats(page.evaluate(FRAME_TIMES_JS, MENU_FRAME_SECONDS))
            cpu_before = process_cpu(browser_cdp)
            followed = trace(page, seconds)
            cpu_after = process_cpu(browser_cdp)
            state = page.evaluate("window.deadnight || {}")
            browser.close()
    finally:
        server.shutdown()
    frames = followed["frames"]
    return {
        "stage": state.get("stage"),
        "load_to_menu_s": load_s,
        "cpu_ms_per_frame": {
            kind: round((cpu_after[kind] - cpu_before.get(kind, 0.0)) * 1000 / frames, 2) for kind in cpu_after
        },
        "mean_ms": round(seconds * 1000 / frames, 1),
        "menu_frames": gate,
        **followed,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("builds", nargs="+", help="label=folder of a web export")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pairs", type=int, default=3)
    parser.add_argument("--seconds", type=float, default=12.0)
    parser.add_argument("--query", default="", help="the page's query, e.g. ?stage=still (the stage on its own)")
    parser.add_argument("--screen", default="main_menu", help="the screen the probe reports once the page is up")
    parser.add_argument(
        "--flag", action="append", default=[], help="a Chrome flag, e.g. --flag=--js-flags=--no-liftoff"
    )
    parser.add_argument("--throttle", type=float, default=1.0, help="CPU slowdown factor (Chrome's emulation)")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    builds = [(b.split("=", 1)[0], Path(b.split("=", 1)[1])) for b in args.builds]
    results: dict[str, list[dict]] = {label: [] for label, _ in builds}
    for n in range(args.pairs):
        order = builds if n % 2 == 0 else list(reversed(builds))
        for label, folder in order:
            shot = args.out / f"{label}_{n}.png"
            result = run_one(folder, args.seconds, shot, args.throttle, args.query, args.screen, args.flag)
            results[label].append(result)
            print(
                f"pair {n} {label}: load={result['load_to_menu_s']} gate_window={result['menu_frames']['mean_ms']} frames={result['frames']} "
                f"mean={result['mean_ms']} each_second={result['mean_ms_each_second']} "
                f"gl_per_frame={ {k: v['mean'] for k, v in result['gl_calls_per_frame'].items()} } "
                f"cpu_ms_per_frame={result['cpu_ms_per_frame']}",
                flush=True,
            )
    (args.out / "menu_idle.json").write_text(json.dumps(results), encoding="utf-8")
    medians = {label: statistics.median(r["mean_ms"] for r in rs) for label, rs in results.items()}
    print(f"median of the runs' mean frame (ms): {medians}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
