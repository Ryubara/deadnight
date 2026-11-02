"""The muzzle flash in the browser, measured (issue #408).

Opens the web build with `?probe=flash` (game/core/flash_web_probe.gd), starts a night, and for each weapon gives it
to the soldier, fires one shot and records, for every frame the browser draws while the flash is up: the page's clock,
the frame time, the flash's age, and what the flash did to the picture (game/core/flash_meter.gd draws the frame again
without the flash and compares, so the size and brightness are the flash's own pixels, in the renderer the game is
played in). Then it fires once more with the canvas copied frame by frame around the muzzle, for the frame sheet.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/flash.py build/web build/flash
    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/flash.py build/web build/flash --gpu --unpaced
    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/flash.py https://... build/flash --weapons pistol,rifle

Writes `rows.json` (every row), `result.json` (the numbers per weapon and the floors they were held to),
`clip_<weapon>/frame_NNNN.png` and `sheet.png` into the output folder. Exits 1 when a weapon's flash is under a floor
of `game/tests/captures/flash_floors.json` (the same floors the desktop probe and the unit test hold it to).
`--gpu` uses the installed Chrome and the machine's GPU (the headless shell is software only, 10 to 15 fps);
`--unpaced` lifts the display's frame limit; `--no-pixels` records the timings only (no frame is drawn twice, so the
frame times are the game's own).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from judder import CLIP_ARM_JS, CLIP_COLUMNS, CLIP_INIT_JS, CLIP_READ_JS, play, save_clip
from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright
from smoke import FRAME_TIMES_JS, LINKS_PER_FRAME_JS, SOFTWARE_GL, UNPACED, VIEWPORT, gl_info, probe, serve, stats

FLOORS = Path(__file__).resolve().parents[2] / "game" / "tests" / "captures" / "flash_floors.json"
WEAPONS = ["pistol", "smg", "rifle", "shotgun", "flare_gun"]
CLIP_FRAMES = 30
SHEET_FRAMES = 8
EQUIP_SETTLE_MS = 2500
SHOT_WAIT_MS = 900


def read_rows(page) -> list[dict]:
    return [json.loads(row) for row in page.evaluate("() => window.deadnight.flashRows.slice()")]


def fire(page, weapon: str, pixels: bool, clip: dict | None = None) -> list[dict]:
    """Gives `weapon`, fires once (a short press) and returns the rows of the frames the flash was up."""
    page.evaluate("(id) => { window.deadnight.flashGive = id; }", weapon)
    for _ in range(100):
        if page.evaluate("() => window.deadnight.flashHave") == weapon:
            break
        page.wait_for_timeout(100)
    page.wait_for_timeout(EQUIP_SETTLE_MS)
    page.evaluate(
        "(pixels) => { const d = window.deadnight; d.flashRows.length = 0; d.flashPixels = pixels; d.flashRecord = true; }",
        pixels,
    )
    if clip is not None:
        clip["size"] = page.evaluate(CLIP_ARM_JS, [clip["frames"], clip["crop"], CLIP_COLUMNS])
    page.mouse.move(640, 360)
    page.mouse.down()
    page.wait_for_timeout(60)
    page.mouse.up()
    page.wait_for_timeout(SHOT_WAIT_MS)
    page.evaluate("() => { window.deadnight.flashRecord = false; }")
    if clip is not None:
        clip["sheet"] = page.evaluate(CLIP_READ_JS)
    return read_rows(page)


def bench(page, weapon: str, seconds: float) -> dict:
    """Holds the trigger for `seconds` and reports the frame times and the GL programs linked meanwhile."""
    page.evaluate("(id) => { window.deadnight.flashGive = id; }", weapon)
    for _ in range(100):
        if page.evaluate("() => window.deadnight.flashHave") == weapon:
            break
        page.wait_for_timeout(100)
    page.wait_for_timeout(EQUIP_SETTLE_MS)
    page.evaluate("() => { window.__linkFrames = []; }")
    page.mouse.move(640, 360)
    page.mouse.down()
    deltas = page.evaluate(FRAME_TIMES_JS, seconds)
    page.mouse.up()
    links = page.evaluate("() => window.__linkFrames")
    out = stats(deltas)
    out["programs_linked"] = sum(row[1] for row in links)
    out["frames_over_50ms"] = sum(1 for d in deltas if d > 50)
    return out


def first_flash(rows: list[dict]) -> list[dict]:
    """The rows of the first flash: consecutive frames with the flash up."""
    run: list[dict] = []
    for row in rows:
        if row.get("up"):
            if run and row["frame"] - run[-1]["frame"] > 1:
                break
            run.append(row)
        elif run:
            break
    return run


def summarise(run: list[dict]) -> dict:
    """The same figures as FlashFloors.summarise in game/tests/captures/flash_floors.gd."""
    seen = [r for r in run if r.get("quad_px", 0) > 0]
    out = {
        "frames_up": len(run),
        "frames_seen": len(seen),
        "up_ms": round(run[-1]["t"] - run[0]["t"] + run[-1]["delta_ms"], 1) if run else 0.0,
        "frame_ms_mean": round(sum(r["delta_ms"] for r in run) / len(run), 1) if run else 0.0,
    }
    if run and "screen_h" in run[0]:
        out["height_pct"] = round(max(r.get("quad_h_seen", 0) / r["screen_h"] for r in run) * 100, 2)
        out["area_pct"] = round(max(r.get("quad_px", 0) / r["screen_px"] for r in run) * 100, 3)
        out["peak_luma"] = round(max(r.get("peak", 0.0) for r in run), 1)
        out["mean_rise"] = round(max(r.get("mean_rise", 0.0) for r in run), 1)
        out["hot_px"] = max(r.get("hot_px", 0) for r in run)
        out["light_px"] = max(r.get("light_px", 0) for r in run)
        out["screen_gain"] = round(max(r.get("screen_gain", 0.0) for r in run), 2)
    return out


def problems(weapon: str, summary: dict, floors: dict) -> list[str]:
    out = []
    minimum = {**floors["min"], **floors.get("web", {}).get("min", {})}
    for key, floor in minimum.items():
        if key in summary and summary[key] < floor:
            out.append(f"{weapon}: {key} {summary[key]} is under the floor {floor}")
    for key, ceiling in floors["max"].items():
        if key in summary and summary[key] > ceiling:
            out.append(f"{weapon}: {key} {summary[key]} is over the ceiling {ceiling}")
    return out


def first_lit(frames: list) -> int:
    """The index of the first frame of the clip in which the flash shows: warm hot pixels, or the picture suddenly brighter."""
    from PIL import ImageStat

    base = ImageStat.Stat(frames[0].convert("L")).mean[0]
    for i, frame in enumerate(frames):
        if ImageStat.Stat(frame.convert("L")).mean[0] - base > 6:
            return i
        pixels = (
            frame.convert("RGB").get_flattened_data()
            if hasattr(frame, "get_flattened_data")
            else frame.convert("RGB").getdata()
        )
        if sum(1 for r, g, b in pixels if r > 235 and g > 170 and b < 200) >= 3:
            return i
    return 0


def make_sheet(out: Path, weapons: list[str]) -> None:
    """One row per weapon: the frame before the flash shows, then the next frames."""
    from PIL import Image, ImageDraw

    rows = []
    for weapon in weapons:
        frames = [Image.open(f) for f in sorted((out / f"clip_{weapon}" / "clip").glob("frame_*.png"))]
        if frames:
            start = max(first_lit(frames) - 1, 0)
            rows.append((weapon, frames[start : start + SHEET_FRAMES]))
    if not rows:
        return
    width, height = rows[0][1][0].size
    sheet = Image.new("RGB", (width * SHEET_FRAMES, height * len(rows)))
    draw = ImageDraw.Draw(sheet)
    for r, (weapon, frames) in enumerate(rows):
        for c, frame in enumerate(frames):
            sheet.paste(frame, (c * width, r * height))
            draw.text((c * width + 4, r * height + 4), f"{weapon} {c - 1:+d}", fill=(255, 255, 255))
    sheet.save(out / "sheet.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--weapons", default=",".join(WEAPONS))
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--unpaced", action="store_true")
    parser.add_argument("--no-pixels", action="store_true", help="timings only: no frame is drawn twice")
    parser.add_argument("--no-clip", action="store_true", help="skip the frame sheet")
    parser.add_argument("--bench", type=float, default=0.0, help="hold the trigger this many seconds per weapon")
    parser.add_argument("--label", default="")
    parser.add_argument("--flag", action="append", default=[], help="an extra Chromium flag")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    weapons = [w for w in args.weapons.split(",") if w]
    floors = json.loads(FLOORS.read_text(encoding="utf-8"))
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    base = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    url = base + ("&" if "?" in base else "?") + "probe=flash"
    result: dict = {"build": args.build, "label": args.label, "gpu": args.gpu, "weapons": {}, "floors": floors}
    all_rows: dict[str, list[dict]] = {}
    found: list[str] = []
    with sync_playwright() as p:
        if args.gpu:
            flags = (UNPACED if args.unpaced else []) + args.flag
            browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL + args.flag)
        page = browser.new_page(viewport=VIEWPORT)
        page.add_init_script(CLIP_INIT_JS)
        page.add_init_script("(" + LINKS_PER_FRAME_JS.strip() + ")();")
        try:
            play(page, url)
            result["gl"] = gl_info(page)
            for weapon in weapons if args.bench else []:
                result["weapons"][weapon] = bench(page, weapon, args.bench)
            for weapon in [] if args.bench else weapons:
                rows = fire(page, weapon, not args.no_pixels)
                all_rows[weapon] = rows
                run = first_flash(rows)
                summary = summarise(run)
                result["weapons"][weapon] = summary
                found += problems(weapon, summary, floors) if not args.no_pixels else []
                if not run:
                    found.append(f"{weapon}: no flash was drawn")
                if args.no_clip or not run or "muzzle_x" not in run[0]:
                    continue
                # a second shot, the canvas copied frame by frame round the muzzle
                row = run[0]
                half_w, half_h = 0.11, 0.17
                fx, fy = row["muzzle_x"] / row["screen_w"], row["muzzle_y"] / row["screen_h"]
                crop = [max(fx - half_w, 0), max(fy - half_h, 0), min(fx + half_w, 1), min(fy + half_h, 1)]
                clip = {"frames": CLIP_FRAMES, "crop": crop}
                fire(page, weapon, False, clip)
                if clip.get("sheet"):
                    folder = args.out / f"clip_{weapon}"
                    folder.mkdir(exist_ok=True)
                    save_clip(clip, folder)
            page.screenshot(path=args.out / "night.png")
            result["state"] = probe(page)
        except (TimeoutError, PlaywrightError) as error:
            found.append(f"[run] {error}")
        finally:
            browser.close()
            if server:
                server.shutdown()
    (args.out / "rows.json").write_text(json.dumps(all_rows) + "\n", encoding="utf-8")
    result["problems"] = found
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if not args.no_clip:
        make_sheet(args.out, weapons)
    print(json.dumps(result, indent=2))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
