"""How smoothly a slow touch look turns the camera, measured in a phone-sized browser (issue #598).

Opens the exported game (`?touch=1`) in Chrome with mobile emulation (779 x 360 CSS pixels, a 1168 x 540 unit canvas, device pixel ratio 3, real
touch events sent through the DevTools protocol), starts a night with the keyboard, and holds one finger on the look area
while it moves at a steady slow speed. For every frame the browser draws, the game reports the camera's yaw and pitch
(`window.deadnight.viewRows`, game/core/view_web_probe.gd). The run reports, for the frames the finger moved in:

- `back_steps`: frames whose turn went the opposite way of the drag (a smooth look has none);
- `zero_frames`: frames with no turn in the middle of the drag (the view stood still while the finger moved);
- `cv`: the standard deviation of the per-frame turn divided by its mean (0 is perfectly even);
- `rate_cv`: the same for the turn per second, so a slow frame does not count as a jerk;
- `max_over_mean`: the biggest frame's turn over the mean.

The finger sends one `touchMove` every period (a phone's touch sampling: 8.3 ms for 120 Hz, 16.7 ms for 60 Hz),
`--speed` CSS pixels per second apart, with the page's main thread slowed by a CPU throttle (`--config PERIOD:THROTTLE`,
repeat for more): a phone draws fewer frames than touch samples, and not an even number of samples per frame. The run
also reports the frame times the browser drew at and how many look motions the touch layer sent in each frame.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_look_smooth.py build/web build/smooth
    ... touch_look_smooth.py build/web build/smooth --gpu --speed 20 --config 8.3:4
    ... touch_look_smooth.py --table build/smooth     # the numbers again from a run's frames

Writes `result.json`, `frames.csv` and a screenshot. Exits 1 when `--gate` is given and a case has a back step or more
than `MAX_CV` of variance.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke
import touch_look

# A phone as the maintainer plays: 779 x 360 CSS pixels at a pixel ratio of 3 is a 2337 x 1080 canvas, and the window's
# content scale of 2 on a phone makes it 1168 x 540 units (docs/research/touch-look-smoothness.md).
VIEWPORT = {"width": 779, "height": 360}
DEVICE_SCALE = touch_look.DEVICE_SCALE
LOOK_FROM = (520.0, 110.0)
DEFAULT_SPEEDS = (20.0, 60.0)
# (touch period in ms, CPU throttle): a 60 Hz and a 120 Hz touch screen, on this machine and with its main thread slowed
# the way a mid-range phone's is (frames of 20 to 30 ms, so several touch samples fall in one frame and not always the
# same number).
DEFAULT_CONFIGS = ((16.7, 1.0), (8.3, 1.0), (8.3, 4.0))
HOLD_S = 3.0
SETTLE_S = 0.6
# What a smooth look has to stay under (the gate).
MAX_CV = 0.5

TOUCH_LOG_JS = """
() => {
  window.__moves = [];
  window.addEventListener('touchmove', (e) => {
    const t = e.touches[0];
    window.__moves.push([performance.now(), t.clientX, t.clientY]);
  }, true);
}
"""


def touch_event(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    touch_look.touch(client, kind, points)


def steady_drag(
    client: CDPSession, start: tuple[float, float], direction: tuple[float, float], speed: float, period_s: float
) -> int:
    """A finger down at `start` that moves along `direction` (a unit vector) at `speed` CSS px/s for HOLD_S, one
    `touchMove` every `period_s`, then lifts. Returns how many moves it sent."""
    x, y = start
    touch_event(client, "touchStart", [(1, x, y)])
    time.sleep(SETTLE_S)
    began = time.perf_counter()
    sent = 0
    next_at = began
    while True:
        now = time.perf_counter()
        elapsed = now - began
        if elapsed >= HOLD_S:
            break
        if now < next_at:
            time.sleep(max(0.0, min(0.002, next_at - now)))
            continue
        next_at += period_s
        distance = speed * (next_at - period_s - began)
        touch_event(client, "touchMove", [(1, x + direction[0] * distance, y + direction[1] * distance)])
        sent += 1
    touch_event(client, "touchEnd", [])
    return sent


def read_rows(page: Page) -> list[list[float]]:
    flat = page.evaluate("() => { const d = window.deadnight; d.viewRecord = false; return d.viewRows.slice(); }")
    size = int(page.evaluate("() => window.deadnight.viewRow"))
    return [flat[i : i + size] for i in range(0, len(flat) - size + 1, size)]


def angle_step(after: float, before: float) -> float:
    return math.remainder(after - before, math.tau)


# Columns of a probe row (game/core/view_web_probe.gd): the clock, then the view's yaw and pitch, the look motions the
# touch layer turned the view by, and (newer builds) the look samples the fingers made.
CLOCK, YAW, PITCH, SENT, SAMPLES = 0, 7, 8, 9, 10
# The first and last stretch of a drag are left out: the view takes a moment to settle into a steady drag, and the
# question is whether a steady drag turns it evenly.
TRIM_S = 0.3


def analyse(rows: list[list[float]], axis: int) -> dict:
    """The per-frame turn of the column `axis` over the frames in which the finger was moving, without the first and
    last `TRIM_S`."""
    finger = SAMPLES if rows and len(rows[0]) > SAMPLES else SENT
    active = [i for i, row in enumerate(rows) if row[finger] > 0]
    if len(active) < 4:
        return {"frames": len(active)}
    began, ended = rows[active[0]][CLOCK] + TRIM_S * 1000.0, rows[active[-1]][CLOCK] - TRIM_S * 1000.0
    inside = [i for i in range(active[0], active[-1] + 1) if began <= rows[i][CLOCK] <= ended]
    if len(inside) < 4:
        return {"frames": len(inside)}
    steps = []
    rates = []
    for i in inside:
        dt = (rows[i][CLOCK] - rows[i - 1][CLOCK]) / 1000.0
        step = angle_step(rows[i][axis], rows[i - 1][axis])
        steps.append(step)
        rates.append(step / dt if dt > 0 else 0.0)
    total = sum(steps)
    sign = 1.0 if total >= 0 else -1.0
    mean = statistics.fmean(steps)
    deviation = statistics.pstdev(steps)
    rate_mean = statistics.fmean(rates)
    rate_dev = statistics.pstdev(rates)
    return {
        "frames": len(steps),
        "total_rad": total,
        "mean_step_rad": mean,
        "std_step_rad": deviation,
        "cv": deviation / abs(mean) if mean else None,
        "rate_cv": rate_dev / abs(rate_mean) if rate_mean else None,
        "back_steps": sum(1 for s in steps if s * sign < -1e-9),
        "zero_frames": sum(1 for s in steps if abs(s) < 1e-9),
        "max_over_mean": max(abs(s) for s in steps) / abs(mean) if mean else None,
    }


def frame_report(rows: list[list[float]]) -> dict:
    times = [rows[i][0] - rows[i - 1][0] for i in range(1, len(rows))]
    sent = [row[SENT] for row in rows]
    return {
        "frames": len(rows),
        "frame_ms_median": statistics.median(times) if times else None,
        "frame_ms_p95": sorted(times)[int(len(times) * 0.95)] if times else None,
        "looks_per_frame_mean": statistics.fmean(sent) if sent else None,
        "frames_with_0_looks": sum(1 for s in sent if s == 0),
        "frames_with_2_plus_looks": sum(1 for s in sent if s >= 2),
    }


def run(url: str, out: Path, speeds: list[float], configs: list[tuple[float, float]], gpu: bool, unpaced: bool) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    result: dict = {"viewport": VIEWPORT, "device_scale_factor": DEVICE_SCALE, "cases": []}
    args = [*smoke.mute_args()]
    if not gpu:
        args += smoke.SOFTWARE_GL
    if unpaced:
        args += smoke.UNPACED
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True, args=args)
        context = browser.new_context(
            viewport=VIEWPORT, device_scale_factor=DEVICE_SCALE, has_touch=True, is_mobile=True
        )
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.add_init_script("(" + touch_look.NO_POINTER_LOCK_JS.strip() + ")();")
        page.add_init_script("(" + TOUCH_LOG_JS.strip() + ")();")
        page.goto(f"{url}?touch=1", wait_until="commit")
        touch_look.start_night(page)
        client = context.new_cdp_session(page)
        result["canvas"] = page.evaluate(
            "() => { const c = document.querySelector('canvas'); return [c.width, c.height]; }"
        )
        page.screenshot(path=str(out / "night_touch.png"))
        for period_ms, throttle in configs:
            client.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
            time.sleep(1.0)
            for direction_name, direction in (("horizontal", (1.0, 0.0)), ("diagonal", (0.8, 0.6))):
                for speed in speeds:
                    page.evaluate("() => { const d = window.deadnight; d.viewRows.length = 0; d.viewRecord = true; }")
                    page.evaluate("window.__moves.length = 0")
                    sent = steady_drag(client, LOOK_FROM, direction, speed, period_ms / 1000.0)
                    time.sleep(0.3)
                    rows = read_rows(page)
                    name = f"{direction_name}_{int(speed)}_p{period_ms:g}_t{throttle:g}"
                    case = {
                        "name": name,
                        "period_ms": period_ms,
                        "cpu_throttle": throttle,
                        "direction": direction_name,
                        "speed_px_s": speed,
                        "moves_sent": sent,
                        "browser_touchmoves": page.evaluate("window.__moves.length"),
                        "yaw": analyse(rows, YAW),
                        "pitch": analyse(rows, PITCH),
                        "frames": frame_report(rows),
                        "game": {
                            key: smoke.probe(page).get(key)
                            for key in ("screen", "night", "running", "paused", "mouse_mode", "touch")
                        },
                    }
                    page.screenshot(path=str(out / f"after_{name}.png"))
                    result["cases"].append(case)
                    (out / f"frames_{name}.csv").write_text(
                        "t_ms,yaw,pitch,looks\n"
                        + "\n".join(f"{r[0]:.2f},{r[YAW]:.6f},{r[PITCH]:.6f},{int(r[SENT])}" for r in rows),
                        encoding="utf-8",
                    )
        client.send("Emulation.setCPUThrottlingRate", {"rate": 1})
        browser.close()
    result["problems"] = problems
    return result


def verdict(result: dict) -> list[str]:
    wrong = list(result["problems"])
    for case in result["cases"]:
        for channel in ("yaw", "pitch"):
            stats = case[channel]
            if case["direction"] == "horizontal" and channel == "pitch":
                continue
            label = f"{case['name']} {channel}"
            if "cv" not in stats:
                wrong.append(f"{label}: the view did not turn ({stats['frames']} frames)")
                continue
            if stats["back_steps"]:
                wrong.append(f"{label}: {stats['back_steps']} back steps")
            if stats["cv"] is not None and stats["cv"] > MAX_CV:
                wrong.append(f"{label}: frame-to-frame variance {stats['cv']:.2f} over {MAX_CV}")
    return wrong


def table(folder: Path) -> str:
    """The numbers of a finished run (its `frames_*.csv`), one line per case."""
    lines = [f"{'case':34} {'axis':5} {'frames':>6} {'cv':>6} {'rate_cv':>7} {'zero':>5} {'back':>4} {'max/mean':>8}"]
    for path in sorted(folder.glob("frames_*.csv")):
        rows = []
        for line in path.read_text(encoding="utf-8").splitlines()[1:]:
            t, yaw, pitch, looks = line.split(",")
            row = [0.0] * 11
            row[CLOCK], row[YAW], row[PITCH] = float(t), float(yaw), float(pitch)
            row[SENT] = row[SAMPLES] = int(looks)
            rows.append(row)
        for axis, name in ((YAW, "yaw"), (PITCH, "pitch")):
            stats = analyse(rows, axis)
            if "cv" not in stats or ("diagonal" not in path.name and name == "pitch"):
                continue
            lines.append(
                f"{path.stem[7:]:34} {name:5} {stats['frames']:6d} {stats['cv']:6.2f} {stats['rate_cv']:7.2f} "
                f"{stats['zero_frames']:5d} {stats['back_steps']:4d} {stats['max_over_mean']:8.2f}"
            )
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--table":
        print(table(Path(sys.argv[2])))
        return 0
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported web folder, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--speed", type=float, action="append", help="finger speed in CSS px/s (repeat for more)")
    parser.add_argument("--config", action="append", help="PERIOD_MS:CPU_THROTTLE, e.g. 8.3:4 (repeat for more)")
    parser.add_argument("--gpu", action="store_true", help="leave Chrome's GPU choice alone (a desktop with a card)")
    parser.add_argument("--unpaced", action="store_true", help="lift the display's frame limit")
    parser.add_argument("--gate", action="store_true", help="exit 1 on a back step or too much variance")
    args = parser.parse_args()
    server = None
    if args.build.startswith(("http://", "https://")):
        url = args.build
    else:
        server, port = smoke.serve(Path(args.build))
        url = f"http://127.0.0.1:{port}/index.html"
    try:
        configs = (
            [(float(a), float(b)) for a, b in (c.split(":") for c in args.config)]
            if args.config
            else list(DEFAULT_CONFIGS)
        )
        result = run(url, args.out, args.speed or list(DEFAULT_SPEEDS), configs, args.gpu, args.unpaced)
    finally:
        if server:
            server.shutdown()
    wrong = verdict(result)
    result["wrong"] = wrong
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    for line in wrong:
        print("FAILED:" if args.gate else "NOTE:", line)
    return 1 if (wrong and args.gate) else 0


if __name__ == "__main__":
    sys.exit(main())
