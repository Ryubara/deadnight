"""The boarded outline (`BoardOutline`) on the phone's page: it draws, and it links one program more.

Exports a copy of the project that starts on `game/tests/captures/board_outline.tscn` (the real project's export
leaves `tests/` out) and loads it once per cell in a fresh Chrome with a phone's screen (pixel ratio 3, touch, the
mobile agent): an entry with all its boards gone, with the outline and without. Each cell saves a screenshot, the
`SHOT` line the capture printed (draw calls, primitives, the screen share the outlines cover) and the WebGL programs the
page linked, so the cost of the one new shader shows as the difference between the two.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/board_outline_web.py <godot> <work folder> \
        [--gl gpu|software] [--cells small:start_2 lot:e] [--size 844x390] [--dpr 3] [--build <earlier export>]

`gpu` is the installed Chrome with this machine's GPU; `software` is Chromium on SwiftShader (every pixel on the
processor, a stand-in for a weak GPU, what CI draws with). Writes `rows.json` and the screenshots into the folder.
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
import first_use
import smoke

GAME = Path(__file__).resolve().parents[2] / "game"
SCENE = "res://tests/captures/board_outline.tscn"
SKIP = shutil.ignore_patterns(".godot", "reports", "build")
TIMEOUT_S = 300
PHONE_AGENT = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/156.0.0.0 Mobile Safari/537.36"
)


def export(godot: str, work: Path) -> Path:
    """A copy of the project that starts on the capture; returns the web folder."""
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


def parse_size(text: str) -> dict:
    width, height = text.split("x")
    return {"width": int(width), "height": int(height)}


def run_cell(playwright, args, url: str, shot: Path) -> dict:
    flags = [*smoke.mute_args()]
    if args.gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *flags])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=flags)
    try:
        context = browser.new_context(
            viewport=parse_size(args.size),
            device_scale_factor=args.dpr,
            is_mobile=True,
            has_touch=True,
            user_agent=PHONE_AGENT,
        )
        page = context.new_page()
        page.add_init_script(f"({first_use.GL_HOOK_JS})()")
        errors: list[str] = []
        lines: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: lines.append(m.text))
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            if page.evaluate("window.__done === true"):
                page.screenshot(path=str(shot))
                links = page.evaluate("window.__links || []")
                shots = [line for line in lines if line.startswith("SHOT")]
                errors += [line for line in lines if "ERROR" in line]
                return {
                    "shot": shots[-1] if shots else "",
                    "programs": len(links),
                    "link_ms": round(sum(ms for _t, ms, _defs in links), 1),
                    "errors": errors[:3],
                }
            time.sleep(0.5)
        return {"error": "the capture never reported", "page_errors": errors[:3], "console": lines[-5:]}
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--cells", nargs="+", default=["small:start_2", "lot:e"])
    parser.add_argument("--size", default="844x390")
    parser.add_argument("--dpr", type=float, default=3.0)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    web = args.build or export(args.godot, args.work)
    server, port = smoke.serve(web)
    rows: list[dict] = []
    try:
        with sync_playwright() as p:
            for cell in args.cells:
                map_name, entry = cell.split(":")
                for outline in (True, False):
                    query = f"map={map_name}&ids={entry}&boards=0&stand=3" + ("" if outline else "&without")
                    shot = args.work / f"web_{map_name}_{entry}_{'with' if outline else 'without'}_{args.gl}.png"
                    row = run_cell(p, args, f"http://127.0.0.1:{port}/index.html?{query}", shot)
                    row.update({"cell": cell, "outline": outline, "gl": args.gl})
                    rows.append(row)
                    print(json.dumps(row), flush=True)
    finally:
        server.shutdown()
    (args.work / f"rows_{args.gl}.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
