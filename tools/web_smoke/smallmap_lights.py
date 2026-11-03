"""What the small-map kit's light cards cost a frame in the browser, and what they look like there (issue #636).

Exports a copy of the project that starts on `game/tests/captures/smallmap_lights.tscn` (the real project's export
leaves `tests/` out), with the blockout's wall pieces copied into it (`tools/blender/build_kit_blockout.py --gltf`
writes them), and loads it once per cell in a fresh headless Chrome: the room or the corridor, with the cards and
without, from the shoulder camera. Each cell prints the frame times the scene measured and the GL programs the page
linked while it measured, and saves a screenshot.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/smallmap_lights.py <godot> <work folder> \\
        --pieces <blockout folder>/gltf [--gl gpu|software] [--runs 3] [--build <folder of an earlier export>]

`gpu` is the installed Chrome with this machine's GPU and the display's frame limit lifted (so a frame's time is its
work); `software` is Chromium on SwiftShader (what CI draws with). Writes `rows.json` and the screenshots into the work
folder.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import first_use
import smoke

GAME = Path(__file__).resolve().parents[2] / "game"
SCENE = "res://tests/captures/smallmap_lights.tscn"
SKIP = shutil.ignore_patterns(".godot", "reports", "build")
PIECES = ("wall_door_narrow", "wall_window_boarded")
TIMEOUT_S = 240


def export(godot: str, work: Path, pieces: Path) -> Path:
    """A copy of the project that starts on the capture, with the blockout's pieces in it; returns the web folder."""
    project = work / "game"
    if project.exists():
        shutil.rmtree(project)
    shutil.copytree(GAME, project, ignore=SKIP)
    target = project / "tests" / "captures" / "kit_pieces"
    target.mkdir(parents=True, exist_ok=True)
    for name in PIECES:
        for suffix in (".gltf", ".bin"):
            shutil.copy2(pieces / f"{name}{suffix}", target / f"{name}{suffix}")
    shutil.copy2(pieces / "kit_palette.png", target / "kit_palette.png")
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


def run_cell(playwright, gl: str, url: str, shot: Path) -> dict:
    if gl == "software":
        browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    else:
        browser = playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.UNPACED, *smoke.mute_args()])
    try:
        page = browser.new_page(viewport=smoke.VIEWPORT)
        page.add_init_script(f"({first_use.GL_HOOK_JS})()")
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda m: errors.append(m.text) if "ERROR" in m.text else None)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            report = page.evaluate("window.__bench || null")
            if report:
                page.screenshot(path=str(shot))
                start = page.evaluate("window.__measure_from || 0")
                links = page.evaluate("window.__links || []")
                report["links_while_measured"] = sum(1 for t, _ms, _defs in links if t >= start)
                report["links_in_all"] = len(links)
                report["console_errors"] = errors[:3]
                return report
            time.sleep(0.5)
        return {"error": "the capture never reported", "page_errors": errors[:3]}
    finally:
        browser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--pieces", type=Path, required=True)
    parser.add_argument("--gl", choices=("gpu", "software"), default="gpu")
    parser.add_argument("--spots", nargs="+", default=["room", "corridor"])
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--build", type=Path, help="a folder an earlier run exported; skips the export")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    web = args.build or export(args.godot, args.work, args.pieces)
    server, port = smoke.serve(web)
    rows: list[dict] = []
    try:
        with sync_playwright() as p:
            # Interleaved, so a slow minute of the machine hits every cell alike.
            for run in range(args.runs):
                for spot in args.spots:
                    for cards in (0, 1):
                        query = f"spot={spot}&cards={cards}&frames={args.frames}&unpaced"
                        shot = args.work / f"web_{spot}_cards{cards}_{args.gl}_{run}.png"
                        row = run_cell(p, args.gl, f"http://127.0.0.1:{port}/index.html?{query}", shot)
                        row.update({"gl": args.gl, "run": run, "spot_asked": spot, "cards_asked": cards})
                        rows.append(row)
                        print(json.dumps(row), flush=True)
    finally:
        server.shutdown()
    (args.work / f"rows_{args.gl}.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    print(f"{'spot':>9} {'cards':>5} {'mean ms':>8} {'p50 ms':>7} {'p95 ms':>7} {'links':>5}")
    for spot in args.spots:
        for cards in (0, 1):
            cells = [r for r in rows if r["spot_asked"] == spot and r["cards_asked"] == cards and "error" not in r]
            if cells:
                print(
                    f"{spot:>9} {cards:>5} "
                    f"{statistics.median(r['mean_ms'] for r in cells):>8.2f} "
                    f"{statistics.median(r['p50_ms'] for r in cells):>7.2f} "
                    f"{statistics.median(r['p95_ms'] for r in cells):>7.2f} "
                    f"{max(r['links_while_measured'] for r in cells):>5}"
                )
    return 0


if __name__ == "__main__":
    sys.exit(main())
