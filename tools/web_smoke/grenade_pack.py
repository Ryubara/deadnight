"""Films a grenade thrown into a pack of the dead in the web build (issue #680).

The same run as the desktop capture (`game/tests/captures/grenade_pack.tscn`: four zombies stand in a bunch down the open
way, the throw key goes in as a key event, the grenade flies low, a zombie stops it, it drops at the pack's feet, beeps
faster and faster and goes off among them), in a browser. Exports a copy of the project that starts on that scene (the
real project's export leaves `tests/` out), loads it in a fresh headless browser with a video recorder, follows
`window.__pack` (the stage the run is in, how many beeps the grenade's sounds made and their gaps) and writes `pack.webm`
and `<n>_<stage>.png` into the output folder, plus `result.json`. Exits 1 when no zombie stopped the grenade, the
grenade did not go off, or the beeps' gaps did not shrink.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/grenade_pack.py <godot> <work folder> <out folder> \\
        [--gl gpu|software] [--build <folder of an earlier export>] [--side]
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import door_swap
import smoke

SCENE = "res://tests/captures/grenade_pack.tscn"
TIMEOUT_S = 400
# A screenshot is taken this long after a stage begins, so the stage is on the screen.
SHOT_AFTER_S = 0.12
# The stages that get a screenshot, by the text the scene publishes.
SHOT_STAGES = ("the pack stands", "key up", "a zombie stops", "the blast")


def film(playwright, gl: str, url: str, out: Path) -> dict:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
    video_dir = out / "video"
    shutil.rmtree(video_dir, ignore_errors=True)
    result: dict = {"stages": []}
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
        state: dict = {}
        while time.monotonic() < deadline:
            state = page.evaluate("window.__pack || null") or {}
            if state.get("done"):
                break
            stage = state.get("stage", "")
            if stage and stage != seen:
                seen = stage
                result["stages"].append(stage)
                if stage.startswith(SHOT_STAGES):
                    time.sleep(SHOT_AFTER_S)
                    number = len(result["stages"])
                    page.screenshot(path=str(out / f"{number}_{stage.split(' ')[0]}_{stage.split(' ')[1]}.png"))
            time.sleep(0.03)
        else:
            context.close()
            result["problem"] = f"never finished (last stage {seen!r}) {errors[:2]}"
            return result
        time.sleep(0.5)
        page.screenshot(path=str(out / "end.png"))
        video = page.video
        context.close()
        shutil.move(video.path(), out / "pack.webm")
        shutil.rmtree(video_dir, ignore_errors=True)
        result.update(state)
        result["console_errors"] = errors[:5]
        return result
    finally:
        browser.close()


def problems_of(result: dict) -> list[str]:
    found: list[str] = []
    if result.get("problem"):
        return [result["problem"]]
    if result.get("struck", -1) < 0:
        found.append("no zombie stopped the grenade")
    if not result.get("exploded"):
        found.append("the grenade did not go off")
    gaps = result.get("gaps", [])
    if len(gaps) < 8 or not gaps[0] > gaps[-1] * 2:
        found.append(f"the beeps did not quicken: {gaps}")
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    parser.add_argument("--side", action="store_true", help="look from above and beside the throw")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    args.out.mkdir(parents=True, exist_ok=True)
    web = args.build or door_swap.export_bench(args.godot, args.work, SCENE)
    server, port = smoke.serve(web)
    try:
        with sync_playwright() as p:
            url = f"http://127.0.0.1:{port}/index.html" + ("?side" if args.side else "")
            result = film(p, args.gl, url, args.out)
    finally:
        server.shutdown()
    result["problems"] = problems_of(result)
    (args.out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 1 if result["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
