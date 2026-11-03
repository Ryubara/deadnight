"""Films the blood of a zombie hit in the web build, from the player's camera (issue #618): the same cases as the
desktop sheet (`game/tests/captures/blood_sheet.tscn`: each gun on the body and on the head, a blow with a crowbar),
with the blood on and off, as a video of the page and a screenshot a moment after each shot.

Exports a copy of the project that starts on the sheet (the real project's export leaves `tests/` out), loads it in a
fresh headless browser with a video recorder, follows `window.__blood` (which case is on) and writes `blood_on.webm`,
`blood_off.webm` and `<mode>_<case>.png` into the output folder.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/blood_capture.py <godot> <work folder> <out folder> \\
        [--gl gpu|software] [--frames 70] [--build <folder of an earlier export>]
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import smoke

SCENE = "res://tests/captures/blood_sheet.tscn"
TIMEOUT_S = 400
# How long after a case starts the screenshot is taken: the shot is on frame 6, the blood lives half a second.
SHOT_AFTER_S = 0.25


def film(playwright, gl: str, url: str, out: Path, mode: str) -> str:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    video_dir = out / f"video_{mode}"
    shutil.rmtree(video_dir, ignore_errors=True)
    try:
        context = browser.new_context(
            viewport=smoke.VIEWPORT, record_video_dir=str(video_dir), record_video_size=smoke.VIEWPORT
        )
        page = context.new_page()
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        seen = ""
        while time.monotonic() < deadline:
            state = page.evaluate("window.__blood || null")
            if state and state.get("done"):
                break
            if state and state.get("case") and state["case"] != seen:
                seen = state["case"]
                time.sleep(SHOT_AFTER_S)
                page.screenshot(path=str(out / f"{mode}_{seen}.png"))
            time.sleep(0.05)
        else:
            context.close()
            return f"never finished {errors[:2]}"
        time.sleep(0.5)
        video = page.video
        context.close()
        shutil.move(video.path(), out / f"blood_{mode}.webm")
        shutil.rmtree(video_dir, ignore_errors=True)
        return "ok" + (f" (console errors: {errors[:3]})" if errors else "")
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--frames", type=int, default=70)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    try:
        with sync_playwright() as p:
            for mode in ("on", "off"):
                blood = "on" if mode == "on" else "off"
                url = f"http://127.0.0.1:{port}/index.html?frames={args.frames}&blood={blood}"
                print(mode, film(p, args.gl, url, args.out, mode), flush=True)
    finally:
        server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
