"""Screenshots of the drive-in lot's views in the browser (issue #686: nothing unfinished is seen, on the web too).

Exports a copy of the project that starts on `game/world/drive_in/capture_rig.tscn`, serves it, and loads it once per
view in a fresh headless Chrome: `index.html?view=<name>&doors=open`. The rig reads the page's query as the same
`--key=value` words it reads from the command line, and sets `window.lotViewReady` once it has drawn a few frames;
the screenshot is taken then. Views are the rig's own (`plaza`, `perk`, `door`, `roost`, ...).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/lot_views.py <godot> <work folder> \\
        [--views plaza perk door roost] [--gl gpu|software] [--build <folder of an earlier export>]

Writes `web_<view>.png` into the work folder and prints one JSON line per view (page errors included).
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

GAME = Path(__file__).resolve().parents[2] / "game"
SCENE = "res://world/drive_in/capture_rig.tscn"
SKIP = shutil.ignore_patterns(".godot", "reports", "build")
VIEWS = ["plaza", "perk", "door", "roost", "plaza_east", "plaza_west"]
TIMEOUT_S = 240


def export(godot: str, work: Path) -> Path:
    """A copy of the project that starts on the capture rig; returns the web folder."""
    project = work / "game"
    if project.exists():
        shutil.rmtree(project)
    shutil.copytree(GAME, project, ignore=SKIP)
    settings = project / "project.godot"
    settings.write_text(
        re.sub(r'run/main_scene=".*"', f'run/main_scene="{SCENE}"', settings.read_text(encoding="utf-8")),
        encoding="utf-8",
    )
    presets = project / "export_presets.cfg"
    presets.write_text(
        re.sub(
            r"exclude_filter=.*",
            'exclude_filter="addons/gdUnit4/*, addons/godot_mcp/*"',
            presets.read_text(encoding="utf-8"),
        ),
        encoding="utf-8",
    )
    web = work / "build" / "web"
    web.mkdir(parents=True, exist_ok=True)
    for step in (["--import"], ["--export-release", "Web"]):
        done = subprocess.run(
            [godot, "--headless", "--path", str(project), *step],
            check=False,
            capture_output=True,
            text=True,
            timeout=900,
        )
        errors = [line for line in (done.stdout + done.stderr).splitlines() if "ERROR" in line]
        if errors:
            raise RuntimeError("\n".join(errors[:5]))
    return web


def shoot(playwright, gl: str, url: str, shot: Path) -> dict:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.UNPACED, *smoke.mute_args()])
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: errors.append(m.text) if "ERROR" in m.text else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            if page.evaluate("window.lotViewReady === true"):
                time.sleep(0.5)  # a few more frames, so the view is the settled one
                page.screenshot(path=str(shot))
                return {"shot": shot.name, "errors": errors[:3]}
            time.sleep(0.5)
        return {"error": "the rig never reported ready", "errors": errors[:3]}
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--views", nargs="+", default=VIEWS)
    parser.add_argument("--gl", choices=("gpu", "software"), default="software")
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    web = args.build or export(args.godot, args.work)
    server, port = smoke.serve(web)
    failed = 0
    try:
        with sync_playwright() as p:
            for view in args.views:
                url = f"http://127.0.0.1:{port}/index.html?view={view}&doors=open"
                row = {"view": view, **shoot(p, args.gl, url, args.work / f"web_{view}.png")}
                failed += 1 if "error" in row or row["errors"] else 0
                print(json.dumps(row), flush=True)
    finally:
        server.shutdown()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
