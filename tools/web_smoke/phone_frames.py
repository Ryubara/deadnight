"""Frame times of the web build on a phone-class stand-in, over minutes (issue #689).

A phone is a small screen with a pixel ratio of 3, a weak processor and a GPU that throttles when it gets hot. This
script loads the exported build in Chrome as a mobile device (844 x 390 CSS pixels, ratio 3, touch, a phone's user
agent), slows its processor with `Emulation.setCPUThrottlingRate`, lets the autopilot play a night from the page's
address (`?autopilot`, so the crowd grows like a real night) and records every `requestAnimationFrame` delta for the
whole run. It prints the median, the 95th, 99th and 99.9th percentile and the worst frame, for the run and for each
minute of it (a rise from minute to minute is a leak or a growing crowd; a phone's heating is not in it), together
with the draw calls, triangles and script time the game published next to the frames.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/phone_frames.py build/web <out folder> \\
        [--minutes 10] [--throttle 4] [--dpr 3] [--size 844x390] [--unpaced] [--software] [--label NAME] \\
        [--query "alive=24&count=2"]

`--unpaced` lifts the display's limit so a frame is its work (without it the frame is held to 60 Hz and a fast
frame reads 16.7 ms); `--software` uses the headless shell's SwiftShader (the pixels are then drawn by the processor,
which is where the resolution shows). What it
cannot show: a phone GPU's own bandwidth and thermal limits, a mobile browser's compositor and Discord's webview. It
is a stand-in; the numbers rank changes, they are not a phone's.
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

CHROME_FLAGS = ["--enable-precise-memory-info"]
PHONE_AGENT = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/156.0.0.0 Mobile Safari/537.36"
)
NIGHT_WAIT_S = 420.0
DRAIN_S = 5.0
SAMPLE_S = 5.0
# With `--gc`, the page's garbage is collected this often and the heap read after it.
GC_EVERY_S = 60.0
# A frame longer than this is a visible hitch at 60 Hz (two frames).
HITCH_MS = 33.4

RECORDER_JS = """
() => {
  window.__d = [];
  window.deadnight_bench = 1;
  let last = performance.now();
  function frame(now) {
    window.__d.push(now, Math.round((now - last) * 100) / 100);
    last = now;
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
"""

DRAIN_JS = "() => { const d = window.__d; window.__d = []; return d; }"
# Switches the stand-in to an arm: the pixel ratio the page reports (the build's cap) and the 3D anti-aliasing.
SWITCH_JS = """
([cap, msaa, batch]) => {
  if (window.deadnightPixels) { window.deadnightPixels.cap = cap; }
  window.deadnight_msaa = msaa;
  if (batch >= 0) { window.deadnight_batch = batch; }
  window.dispatchEvent(new Event('resize'));
  return performance.now();
}
"""
SETTLE_S = 4.0
SAMPLE_JS = """
() => {
  const d = window.deadnight || {};
  const m = performance.memory ? performance.memory.usedJSHeapSize / 1048576 : -1;
  const perf = {};
  for (const k in d) { if (k.startsWith('perf.')) perf[k] = d[k]; }
  return {perf: perf, running: !!d.running, alive: d.alive || 0, round: d.round || 0, draw_calls: d.draw_calls || 0, draw_calls_3d: d.draw_calls_3d || 0,
          primitives: d.primitives || 0, objects: d.objects || 0, process_ms: d.process_ms || 0,
          physics_ms: d.physics_ms || 0,
          mem: {static_mb: d.mem_static_mb || 0, objects: d.mem_objects || 0, nodes: d.mem_nodes || 0, orphans: d.mem_orphans || 0,
                resources: d.mem_resources || 0, texture_mb: d.mem_texture_mb || 0, buffer_mb: d.mem_buffer_mb || 0},
          render_cpu_ms: d.render_cpu_ms || 0, render_gpu_ms: d.render_gpu_ms || 0, canvas: [d.canvas_w || 0, d.canvas_h || 0], heap_mb: m};
}
"""


def percentile(ordered: list[float], share: float) -> float:
    return ordered[min(int(len(ordered) * share), len(ordered) - 1)] if ordered else 0.0


def describe(deltas: list[float]) -> dict:
    ordered = sorted(deltas)
    if not ordered:
        return {"frames": 0}
    return {
        "frames": len(ordered),
        "mean_ms": round(statistics.fmean(ordered), 2),
        "p50_ms": round(percentile(ordered, 0.5), 2),
        "p95_ms": round(percentile(ordered, 0.95), 2),
        "p99_ms": round(percentile(ordered, 0.99), 2),
        "p999_ms": round(percentile(ordered, 0.999), 2),
        "max_ms": round(ordered[-1], 1),
        "over_33ms": sum(1 for d in ordered if d > HITCH_MS),
        "fps_mean": round(1000.0 / statistics.fmean(ordered), 1),
    }


def parse_arms(text: str) -> list[tuple[str, float, int, int]]:
    """`native:3:2,capped:2:2:1` -> [(name, pixel ratio cap, msaa, batch)], the arms a run alternates between.

    `batch` is 0 or 1 (draw the map from the nodes it is written with, or from its batches; the page needs
    `batch=toggle` in its query), and -1 when the arm leaves it as it was.
    """
    if not text:
        return [("run", 0.0, 2, -1)]
    arms = []
    for part in text.split(","):
        fields = part.split(":")
        name, cap, msaa = fields[:3]
        arms.append((name, float(cap), int(msaa), int(fields[3]) if len(fields) > 3 else -1))
    return arms


def parse_size(text: str) -> dict:
    width, height = text.lower().split("x")
    return {"width": int(width), "height": int(height)}


def run(args: argparse.Namespace) -> dict:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    server, port = smoke.serve(Path(args.build))
    query = f"autopilot&rounds=99&hold=0&seconds={int(args.minutes * 60 + 240)}&{args.query}"
    if args.real:
        query = args.query  # the real menu and a solo night, no autopilot
    url = f"http://127.0.0.1:{port}/index.html?{query}"
    flags = [*CHROME_FLAGS, *(smoke.UNPACED if args.unpaced else []), *smoke.mute_args()]
    errors: list[str] = []
    per_minute: list[list[float]] = [[] for _ in range(int(args.minutes) + 2)]
    everything: list[float] = []
    samples: list[dict] = []
    try:
        with sync_playwright() as p:
            if args.software:
                browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *flags])
            else:
                browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
            context = browser.new_context(
                viewport=parse_size(args.size),
                device_scale_factor=args.dpr,
                is_mobile=True,
                has_touch=True,
                user_agent=PHONE_AGENT,
            )
            page = context.new_page()
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: errors.append(str(e)))
            session = context.new_cdp_session(page)
            page.add_init_script("(" + RECORDER_JS.strip() + ")();")
            page.goto(url, wait_until="commit")
            if args.real:
                smoke.reach_menu(page)
                page.screenshot(path=out / f"{args.label}_menu.png")
                smoke.start_solo(page)
            began = time.monotonic()
            while time.monotonic() - began < NIGHT_WAIT_S:
                if smoke.probe(page).get("running"):
                    break
                time.sleep(1.0)
            else:
                raise TimeoutError("the night never ran")
            if args.throttle > 1.0:
                # After the load: a phone's load is long, but a probe that spends minutes loading a night at a
                # quarter of the speed has no minutes left to measure it (#728).
                session.send("Emulation.setCPUThrottlingRate", {"rate": args.throttle})
            page.evaluate(DRAIN_JS)  # the loading frames are not the night
            page.screenshot(path=out / f"{args.label}_start.png")
            gl = smoke.gl_info(page)
            run_began = time.monotonic()
            next_sample = run_began
            next_gc = run_began + GC_EVERY_S
            arms = parse_arms(args.arms)
            arm_deltas: dict[str, list[float]] = {name: [] for name, *_ in arms}
            arm_minutes: dict[str, dict[int, list[float]]] = {name: {} for name, *_ in arms}
            block = 0
            order_rng = random.Random(728)
            order: list[int] = []
            while time.monotonic() - run_began < args.minutes * 60:
                if block % len(arms) == 0:
                    # Each round takes the arms in a new order: a night has its own beat (a wave about every
                    # minute), and a fixed order of 30 s blocks falls on it the same way every time.
                    order = list(range(len(arms)))
                    order_rng.shuffle(order)
                name, cap, msaa, batch = arms[order[block % len(arms)]]
                switched = page.evaluate(SWITCH_JS, [cap, msaa, batch]) if args.arms else 0.0
                block += 1
                block_began = time.monotonic()
                block_end = time.monotonic() + (args.block if args.arms else args.minutes * 60)
                while time.monotonic() < min(block_end, run_began + args.minutes * 60):
                    time.sleep(DRAIN_S)
                    if time.monotonic() >= next_sample:
                        sample = page.evaluate(SAMPLE_JS)
                        sample["t"] = round(time.monotonic() - run_began, 1)
                        if args.gc and time.monotonic() >= next_gc:
                            # What the page holds once the collector has run: a rise here is a leak, a rise in
                            # `heap_mb` alone is garbage waiting.
                            session.send("HeapProfiler.collectGarbage")
                            sample["heap_gc_mb"] = page.evaluate(
                                "() => performance.memory ? performance.memory.usedJSHeapSize / 1048576 : -1"
                            )
                            next_gc += GC_EVERY_S
                        sample["arm"] = name
                        sample["since_switch"] = time.monotonic() - block_began
                        samples.append(sample)
                        next_sample += SAMPLE_S
                    elapsed = time.monotonic() - run_began
                    if int(elapsed) % 120 < DRAIN_S + 0.5 and elapsed > 1:
                        page.screenshot(path=out / f"{args.label}_{name}_{int(elapsed):04d}s.png")
                    flat = page.evaluate(DRAIN_JS)
                    minute = int(elapsed / 60.0)
                    for now, delta in zip(flat[0::2], flat[1::2], strict=True):
                        if now < switched + SETTLE_S * 1000.0:
                            continue  # the canvas is being resized and the GPU reallocates
                        arm_deltas[name].append(delta)
                        arm_minutes[name].setdefault(minute, []).append(delta)
                        per_minute[min(minute, len(per_minute) - 1)].append(delta)
                        everything.append(delta)
            page.screenshot(path=out / f"{args.label}_end.png")
            browser.close()
    finally:
        server.shutdown()
    live = [s for s in samples if s["running"]]

    def mean_of(key: str) -> float:
        return round(statistics.fmean(s[key] for s in live), 2) if live else 0.0

    return {
        "label": args.label,
        "gl": gl,
        "settings": {
            "minutes": args.minutes,
            "throttle": args.throttle,
            "dpr": args.dpr,
            "size": args.size,
            "unpaced": args.unpaced,
            "software": args.software,
            "query": args.query,
            "real": args.real,
        },
        "overall": describe(everything),
        "per_minute": [dict(minute=i, **describe(d)) for i, d in enumerate(per_minute) if d],
        "arms": {
            name: {
                **describe(d),
                "render": {
                    key: round(
                        statistics.fmean(
                            [s[key] for s in live if s.get("arm") == name and s.get("since_switch", 0) > SETTLE_S]
                            or [0.0]
                        ),
                        2,
                    )
                    for key in (
                        "alive",
                        "draw_calls",
                        "draw_calls_3d",
                        "primitives",
                        "objects",
                        "process_ms",
                        "physics_ms",
                        "render_cpu_ms",
                    )
                },
                "minutes": [dict(minute=m, **describe(v)) for m, v in sorted(arm_minutes[name].items())],
            }
            for name, d in arm_deltas.items()
        }
        if args.arms
        else {},
        "render": {
            "draw_calls_mean": mean_of("draw_calls"),
            "draw_calls_3d_mean": mean_of("draw_calls_3d"),
            "primitives_mean": mean_of("primitives"),
            "objects_mean": mean_of("objects"),
            "process_ms_mean": mean_of("process_ms"),
            "physics_ms_mean": mean_of("physics_ms"),
            "render_cpu_ms_mean": mean_of("render_cpu_ms"),
            "render_gpu_ms_mean": mean_of("render_gpu_ms"),
            "alive_mean": mean_of("alive"),
            "alive_peak": max((s["alive"] for s in live), default=0),
            "round_end": live[-1]["round"] if live else 0,
            "canvas": live[-1]["canvas"] if live else [0, 0],
            "perf_ms": {
                key: round(statistics.fmean(s["perf"].get(key, 0.0) for s in live), 3)
                for key in sorted({k for s in live for k in s["perf"]})
            },
            "memory": [
                {
                    "t": s["t"],
                    "heap_mb": round(s["heap_mb"], 1),
                    "heap_gc_mb": round(s.get("heap_gc_mb", -1), 1),
                    **s["mem"],
                }
                for s in live
                if "heap_gc_mb" in s
            ],
            "heap_mb_first": live[0]["heap_mb"] if live else -1,
            "heap_mb_last": live[-1]["heap_mb"] if live else -1,
        },
        "samples": samples,
        "console_errors": errors[:5],
        "_deltas": everything,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported build folder")
    parser.add_argument("out", help="where the report and screenshots go")
    parser.add_argument("--minutes", type=float, default=10.0)
    parser.add_argument("--throttle", type=float, default=4.0, help="processor slow-down; 1 is none")
    parser.add_argument("--dpr", type=float, default=3.0)
    parser.add_argument("--size", default="844x390")
    parser.add_argument("--unpaced", action="store_true")
    parser.add_argument("--software", action="store_true")
    parser.add_argument(
        "--gc", action="store_true", help="collect the page's garbage every minute and read the heap after it"
    )
    parser.add_argument("--real", action="store_true", help="go through the menu to a solo night, no autopilot")
    parser.add_argument(
        "--arms",
        default="",
        help="alternate in one page between name:pixel-ratio-cap:msaa arms, e.g. native:3:2,capped:2:2,capped_no_msaa:2:0",
    )
    parser.add_argument("--block", type=float, default=20.0, help="seconds in each arm before the next")
    parser.add_argument("--label", default="run")
    parser.add_argument("--query", default="count=1", help="more address arguments for the autopilot")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = run(args)
    path = Path(args.out) / f"{args.label}.json"
    path.write_text(json.dumps({k: v for k, v in report.items() if k != "_deltas"}, indent=1))
    print(json.dumps({k: v for k, v in report.items() if k not in ("samples", "_deltas")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
