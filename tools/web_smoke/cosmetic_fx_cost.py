"""What a top-tier cosmetic effect costs in the browser and on the desktop (issue #1053).

Exports a copy of the project that starts on `game/tests/captures/cosmetic_fx_bench.tscn` (the real project's export
leaves `tests/` out): four Soldiers in view, each in one of the bench's arms (see the scene's script). Each page load
reports the engine's own numbers (`window.__bench`: frame time, draw calls, GPU and render CPU time) and, for the
frames after the bench settles, the WebGL calls the engine made (`smoke.trace`: they do not move with the machine).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/cosmetic_fx_cost.py <godot> <work folder> \\
        [--target gpu|software|phone] [--arms base wings flame gpu cpu halo glow full] [--runs 3] [--shots]

Targets: `gpu` the installed Chrome on this machine's GPU with the display's frame limit lifted, 1280x720; `software`
Chromium on SwiftShader (what CI draws with; every pixel is paid for), 1280x720; `phone` a phone-sized page (844x390
at a pixel ratio of 2, touch) on the GPU with the processor slowed 4 times, the stand-in the kit page names for a phone's
CPU side. Arms run interleaved in rounds so a slow minute hits every arm alike. `--shots` saves a PNG of the page for the
`gpu` and `glow` arms, twice for `gpu`, and prints how many pixels each pair differs by, which shows whether the engine's
glow reaches the WebGL canvas. Writes `rows.json` into the work folder.
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

BENCH_SCENE = "res://tests/captures/cosmetic_fx_bench.tscn"
TIMEOUT_S = 600
PHONE = {"viewport": {"width": 844, "height": 390}, "device_scale_factor": 2, "is_mobile": True, "has_touch": True}
DESKTOP = {"viewport": smoke.VIEWPORT, "device_scale_factor": 1}


def run_cell(playwright, target: str, url: str, trace_s: float, shot: Path | None) -> dict:
    """One page load: the bench's report with the WebGL counts of `trace_s` seconds after it settled, or an error."""
    if target == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.UNPACED, *smoke.mute_args()])
    try:
        page = browser.new_page(**(PHONE if target == "phone" else DESKTOP))
        if target == "phone":
            page.context.new_cdp_session(page).send("Emulation.setCPUThrottlingRate", {"rate": 4})
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline and not page.evaluate("window.__settled || false"):
            time.sleep(0.25)
        counts = smoke.trace(page, trace_s)
        if shot is not None:
            page.screenshot(path=str(shot))
        while time.monotonic() < deadline:
            report = page.evaluate("window.__bench || null")
            if report:
                report["webgl"] = counts
                return report
            time.sleep(0.5)
        return {"error": "the bench never reported", "page_errors": errors[:3]}
    finally:
        browser.close()


def summarise(rows: list[dict], arms: list[str]) -> list[dict]:
    out = []
    for arm in arms:
        cells = [r for r in rows if r.get("arm") == arm and "error" not in r]
        if not cells:
            continue
        gl = [r["webgl"] for r in cells if r.get("webgl")]
        out.append(
            {
                "arm": arm,
                "runs": len(cells),
                "frame_ms": statistics.median(r["frame_median_ms"] for r in cells),
                "p95_ms": statistics.median(r["frame_p95_ms"] for r in cells),
                "engine_draws": statistics.median(r["draw_calls"] for r in cells),
                "triangles": statistics.median(r["triangles"] for r in cells),
                "gl_draws": statistics.median(g["gl_calls_per_frame"]["draws"]["mean"] for g in gl) if gl else None,
                "gl_clears": statistics.median(g["gl_calls_per_frame"]["clears"]["mean"] for g in gl) if gl else None,
                "gl_blits": statistics.median(g["gl_calls_per_frame"]["blits"]["mean"] for g in gl) if gl else None,
                "gl_fbo_binds": statistics.median(g["gl_calls_per_frame"]["fbo_binds"]["mean"] for g in gl)
                if gl
                else None,
                "gl_programs": statistics.median(g["gl_calls_per_frame"]["programs"]["mean"] for g in gl)
                if gl
                else None,
            }
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--target", choices=("gpu", "software", "phone"), default="gpu")
    parser.add_argument("--arms", nargs="+", default=["base", "wings", "flame", "gpu", "cpu", "halo", "glow", "full"])
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--frames", type=int, default=300)
    parser.add_argument("--settle", type=int, default=150)
    parser.add_argument("--trace", type=float, default=3.0)
    parser.add_argument("--shots", action="store_true")
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, BENCH_SCENE)
    server, port = smoke.serve(web)
    rows: list[dict] = []
    try:
        with sync_playwright() as p:
            for round_index in range(args.runs):
                for arm in args.arms:
                    url = f"http://127.0.0.1:{port}/index.html?arm={arm}&frames={args.frames}&settle={args.settle}"
                    row = run_cell(p, args.target, url, args.trace, None)
                    row["target"] = args.target
                    rows.append(row)
                    print(json.dumps({k: v for k, v in row.items() if k != "webgl"}), flush=True)
            if args.shots:
                for name, arm in (("gpu_a", "gpu"), ("gpu_b", "gpu"), ("glow", "glow"), ("base", "base")):
                    url = f"http://127.0.0.1:{port}/index.html?arm={arm}&frames=20&settle={args.settle}"
                    run_cell(p, args.target, url, 0.5, args.work / f"{args.target}_{name}.png")
    finally:
        server.shutdown()
    (args.work / "rows.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    table = summarise(rows, args.arms)
    (args.work / "summary.json").write_text(json.dumps(table, indent=1) + "\n", encoding="utf-8")
    print(
        f"{'arm':>7} {'frame ms':>9} {'p95':>7} {'engine':>7} {'gl draw':>8} {'clear':>6} {'blit':>5} {'fbo':>5} {'prog':>5}"
    )
    for r in table:
        print(
            f"{r['arm']:>7} {r['frame_ms']:>9.2f} {r['p95_ms']:>7.2f} {r['engine_draws']:>7.0f} "
            f"{r['gl_draws']!s:>8} {r['gl_clears']!s:>6} {r['gl_blits']!s:>5} {r['gl_fbo_binds']!s:>5} {r['gl_programs']!s:>5}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
