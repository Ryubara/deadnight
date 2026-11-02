"""The soldier's smoothness on the screen, measured in the browser (issues #353 and #344).

Opens the web build (a folder, served here, or a URL), starts a night, strafes the soldier and records, for every
frame the browser draws, where the soldier's chest is on the screen as the renderer draws it (game/core/judder_probe.gd
writes the rows into `window.deadnight.frames`). Then it reports, for the stretches of steady strafing:

- `wander_px`: how far the chest wandered on the screen (a steady strafe holds it still: the camera follows);
- `resid_rms_px`: the RMS of how far each frame's position is from the straight line between its neighbours, drawn at
  the frames' own times (so a slow or uneven frame does not count; a body that steps does);
- the frame times and how many physics ticks fell in each frame.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/judder.py build/web build/judder
    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/judder.py https://... build/judder --gpu --unpaced
    python tools/web_smoke/judder.py build/judder/frames.csv -   # the numbers again from a run's rows

`--gpu` uses the installed Chrome and the machine's GPU (the headless shell is software only, 10 to 15 fps);
`--unpaced` lifts the display's frame limit so the browser draws as fast as it can; `--flag X` adds a Chromium flag.
Writes `frames.csv`, `result.json` and a screenshot into the output folder.
"""

from __future__ import annotations

import argparse
import base64
import bisect
import itertools
import json
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright
from smoke import (
    SOFTWARE_GL,
    UNPACED,
    VIEWPORT,
    gl_info,
    probe,
    reach_menu,
    serve,
    start_solo,
    wait_for_night,
)

ROW = 8  # numbers per frame, see judder_probe.gd
CLIP_COLUMNS = 8

# Keeps what the canvas shows in each of the next `max` frames, cropped, in one sheet. The browser's frame callbacks are
# wrapped so that the copy is made right after the game drew, in the same task, when the canvas still holds the frame.
CLIP_INIT_JS = """
(() => {
  const grab = { on: false, n: 0, max: 0, sheet: null, crop: null, columns: 8 };
  window.__clip = grab;
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (callback) => raf((time) => {
    callback(time);
    if (!grab.on) return;
    const canvas = document.querySelector('canvas');
    const [sx, sy, sw, sh] = grab.crop;
    const ctx = grab.sheet.getContext('2d');
    const w = grab.sheet.width / grab.columns, h = grab.sheet.height / Math.ceil(grab.max / grab.columns);
    ctx.drawImage(canvas, sx, sy, sw, sh, (grab.n % grab.columns) * w, Math.floor(grab.n / grab.columns) * h, w, h);
    grab.n += 1;
    if (grab.n >= grab.max) grab.on = false;
  });
})();
"""

CLIP_ARM_JS = """
([frames, fractions, columns]) => {
  const canvas = document.querySelector('canvas');
  const [x0, y0, x1, y1] = fractions;
  const crop = [x0 * canvas.width, y0 * canvas.height, (x1 - x0) * canvas.width, (y1 - y0) * canvas.height];
  const grab = window.__clip;
  grab.crop = crop;
  grab.columns = columns;
  grab.max = frames;
  grab.n = 0;
  grab.sheet = document.createElement('canvas');
  grab.sheet.width = Math.round(crop[2]) * columns;
  grab.sheet.height = Math.round(crop[3]) * Math.ceil(frames / columns);
  grab.on = true;
  return [Math.round(crop[2]), Math.round(crop[3])];
}
"""

CLIP_READ_JS = "() => window.__clip.n >= window.__clip.max ? window.__clip.sheet.toDataURL('image/png') : null"
LEG_S = 3.0  # one strafe direction, in seconds
LEGS = 6
SETTLE_S = 1.2  # after a turn the soldier and the camera need this long to be at a steady pace
STEADY = 0.9
HALF_WINDOW_MS = 100.0
# a frame whose x is further than this from the stretch's median is the camera pushed in by a wall or a prop
OUTLIER_PX = 20.0
MIN_FRAMES = 60  # a frame is in a stretch while the soldier moves at this share of its top speed or more


def play(page, url: str) -> None:
    page.goto(url, wait_until="commit")
    reach_menu(page)
    start_solo(page)
    wait_for_night(page)
    page.wait_for_timeout(2000)


def record(page, legs: int, leg_s: float, clip: dict | None = None) -> list[float]:
    page.evaluate("() => { window.deadnight.frames.length = 0; window.deadnight.record = true; }")
    keys = ("d", "a")
    for leg in range(legs):
        key = keys[leg % 2]
        page.keyboard.down(key)
        if clip is not None and leg == 1:
            # the soldier is at a steady pace in the middle of the second leg: take the frames there
            page.wait_for_timeout(int(leg_s * 1000 * 0.6))
            clip["size"] = page.evaluate(CLIP_ARM_JS, [clip["frames"], clip["crop"], CLIP_COLUMNS])
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                clip["sheet"] = page.evaluate(CLIP_READ_JS)
                if clip["sheet"]:
                    break
                page.wait_for_timeout(50)
            page.wait_for_timeout(int(leg_s * 1000 * 0.2))
        else:
            page.wait_for_timeout(int(leg_s * 1000))
        page.keyboard.up(key)
    page.evaluate("() => { window.deadnight.record = false; }")
    return page.evaluate("() => window.deadnight.frames.slice()")


def rows_of(flat: list[float]) -> list[list[float]]:
    return [flat[i : i + ROW] for i in range(0, len(flat) - ROW + 1, ROW)]


def residual(rows: list[list[float]]) -> list[float]:
    """Each frame's screen x against the straight line between its neighbours, at the frames' own times."""
    out = []
    for i in range(1, len(rows) - 1):
        t0, t1, t2 = rows[i - 1][0], rows[i][0], rows[i + 1][0]
        if t2 <= t0:
            continue
        expected = rows[i - 1][1] + (rows[i + 1][1] - rows[i - 1][1]) * (t1 - t0) / (t2 - t0)
        out.append(rows[i][1] - expected)
    return out


def rms(values: list[float]) -> float:
    return (sum(v * v for v in values) / len(values)) ** 0.5 if values else float("nan")


def steady_stretches(rows: list[list[float]]) -> list[list[list[float]]]:
    """Runs of frames in which the soldier moves at a steady, full pace, away from the turns."""
    # speed over 200 ms of frames: the body of an unfixed build moves in 60 Hz steps, so a shorter window is noisy
    times = [r[0] for r in rows]
    smooth = []
    for i, row in enumerate(rows):
        first = bisect.bisect_left(times, row[0] - HALF_WINDOW_MS)
        last = min(bisect.bisect_right(times, row[0] + HALF_WINDOW_MS), len(rows)) - 1
        dt = (rows[last][0] - rows[first][0]) / 1000.0
        dist = ((rows[last][6] - rows[first][6]) ** 2 + (rows[last][7] - rows[first][7]) ** 2) ** 0.5
        smooth.append(dist / dt if dt > 0 else 0.0)
    top = percentile(smooth, 0.9) if smooth else 0.0
    stretches, current = [], []
    for row, speed in zip(rows, smooth, strict=True):
        if top > 0.5 and speed >= STEADY * top:
            current.append(row)
        elif current:
            stretches.append(current)
            current = []
    if current:
        stretches.append(current)
    # drop the first SETTLE_S of each stretch: the camera is still catching up after the turn
    trimmed = []
    for stretch in stretches:
        start = stretch[0][0] + SETTLE_S * 1000.0
        kept = [r for r in stretch if r[0] >= start]
        # the camera pushed in by a wall or a prop is not the blend: cut the stretch there
        middle = statistics.median(r[1] for r in kept) if kept else 0.0
        run: list[list[float]] = []
        for r in [*kept, None]:
            if r is not None and abs(r[1] - middle) < OUTLIER_PX:
                run.append(r)
                continue
            if len(run) > MIN_FRAMES:
                trimmed.append(run)
            run = []
    return trimmed


def percentile(values: list[float], share: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * share))]


def summarize(rows: list[list[float]]) -> dict:
    stretches = steady_stretches(rows)
    frames = [r for s in stretches for r in s]
    if not frames:
        return {"error": "no steady stretch of strafing was recorded", "frames_recorded": len(rows)}
    resid, wander, dts, ticks_per_frame = [], [], [], []
    for stretch in stretches:
        resid += residual(stretch)
        xs = [r[1] for r in stretch]
        wander.append(max(xs) - min(xs))
        dts += [r[5] for r in stretch]
        ticks_per_frame += [b[3] - a[3] for a, b in itertools.pairwise(stretch)]
    return {
        "frames_recorded": len(rows),
        "frames_measured": len(frames),
        "stretches": len(stretches),
        "fps_mean": round(1000.0 / statistics.fmean(dts), 1),
        "frame_ms_p50": round(percentile(dts, 0.5), 2),
        "frame_ms_p95": round(percentile(dts, 0.95), 2),
        "frame_ms_max": round(max(dts), 2),
        "ticks_per_frame": {str(int(k)): ticks_per_frame.count(k) for k in sorted(set(ticks_per_frame))},
        "wander_px": round(statistics.fmean(wander), 3),
        "resid_rms_px": round(rms(resid), 4),
        "resid_peak_px": round(max(abs(v) for v in resid), 3),
    }


def save_clip(clip: dict, out: Path) -> None:
    """Splits the sheet of consecutive frames into clip/frame_0000.png and so on."""
    from PIL import Image

    sheet_png = out / "clip_sheet.png"
    sheet_png.write_bytes(base64.b64decode(clip["sheet"].split(",", 1)[1]))
    sheet = Image.open(sheet_png)
    width, height = clip["size"]
    folder = out / "clip"
    folder.mkdir(exist_ok=True)
    for n in range(clip["frames"]):
        column, row = n % CLIP_COLUMNS, n // CLIP_COLUMNS
        sheet.crop((column * width, row * height, (column + 1) * width, (row + 1) * height)).save(
            folder / f"frame_{n:04d}.png"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true", help="the installed Chrome with the machine's GPU")
    parser.add_argument("--unpaced", action="store_true", help="with --gpu: do not wait for the display")
    parser.add_argument("--legs", type=int, default=LEGS)
    parser.add_argument("--leg-seconds", type=float, default=LEG_S)
    parser.add_argument(
        "--clip", type=int, default=0, help="also keep this many consecutive frames, cropped (needs Pillow)"
    )
    parser.add_argument(
        "--clip-crop", default="0.15,0.35,0.85,1.0", help="x0,y0,x1,y1 of the clip as shares of the canvas"
    )
    parser.add_argument("--label", default="")
    parser.add_argument("--flag", action="append", default=[], help="an extra Chromium flag")
    args = parser.parse_args()
    if args.build.endswith(".csv"):  # numbers again from a run's frames.csv
        with open(args.build, encoding="utf-8") as f:
            rows = [[float(v) for v in line.split(",")] for line in f.read().splitlines()[1:]]
        print(json.dumps(summarize(rows), indent=2))
        return 0
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    result: dict = {
        "build": args.build,
        "label": args.label,
        "gpu": args.gpu,
        "unpaced": args.unpaced,
        "flags": args.flag,
    }
    flat: list[float] = []
    with sync_playwright() as p:
        if args.gpu:
            flags = (UNPACED if args.unpaced else []) + args.flag
            browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL + args.flag)
        page = browser.new_page(viewport=VIEWPORT)
        clip = {"frames": args.clip, "crop": [float(v) for v in args.clip_crop.split(",")]} if args.clip else None
        if clip:
            page.add_init_script(CLIP_INIT_JS)
        try:
            play(page, url)
            flat = record(page, args.legs, args.leg_seconds, clip)
            page.screenshot(path=args.out / "night.png")
            result["gl"] = gl_info(page)
            result["state"] = probe(page)
        except (TimeoutError, PlaywrightError) as error:
            result["error"] = str(error)
        finally:
            browser.close()
            if server:
                server.shutdown()
    if clip and clip.get("sheet"):
        save_clip(clip, args.out)
    rows = rows_of(flat)
    result["measure"] = summarize(rows) if rows else {"error": "no frames recorded"}
    with open(args.out / "frames.csv", "w", encoding="utf-8") as f:
        f.write("ms,x,y,physics_frame,fraction,delta_ms,world_x,world_z\n")
        f.writelines(",".join(f"{v:.5f}" for v in r) + "\n" for r in rows)
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 1 if "error" in result or "error" in result["measure"] else 0


if __name__ == "__main__":
    sys.exit(main())
