"""What the zombies' navigation costs in the browser: the lot's setup and every door bought, with the saved meshes
(`LotNavmeshes`, what the game does) and with every mesh baked at run time (what it did before, #335).

The browser has no worker threads, so a bake runs inside one frame of the page: this shows how long that frame is.
The run exports a copy of the project that starts on `game/tests/captures/door_swap_bench.tscn` (the real project's
export leaves `tests/` out), plays it in a fresh headless Chrome with the machine's GPU, and prints the milliseconds.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/door_swap.py <godot> <work folder> [--runs 3]

`<godot>` is the pinned Godot (`gds tool path godot`); the copy and its export are made in `<work folder>`.
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
import smoke

GAME = Path(__file__).resolve().parents[2] / "game"
BENCH_SCENE = "res://tests/captures/door_swap_bench.tscn"
SKIP = shutil.ignore_patterns(".godot", "reports", "build")
TIMEOUT_S = 180


def export_bench(godot: str, work: Path, scene: str = BENCH_SCENE) -> Path:
    """A copy of the project whose main scene is the bench and whose export keeps `tests/`; returns the web folder."""
    project = work / "game"
    if project.exists():
        shutil.rmtree(project)
    shutil.copytree(GAME, project, ignore=SKIP)
    settings = project / "project.godot"
    settings.write_text(
        re.sub(r'run/main_scene=".*"', f'run/main_scene="{scene}"', settings.read_text(encoding="utf-8")),
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


def run_once(url: str) -> list[dict]:
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        page = browser.new_page(viewport=smoke.VIEWPORT)
        page.goto(url, wait_until="commit")
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            report = page.evaluate("window.__bench || null")
            if report:
                browser.close()
                return report
            time.sleep(0.5)
        browser.close()
    raise TimeoutError("the bench never reported")


def summarise(runs: list[list[dict]]) -> dict:
    """Medians over every run (and every door), by phase."""
    out: dict = {}
    for phase in ("saved", "runtime_bake"):
        phases = [ph for run in runs for ph in run if ph["phase"] == phase]
        doors = [d for ph in phases for d in ph["doors"]]
        out[phase] = {
            "setup_ms": statistics.median(ph["setup_ms"] for ph in phases),
            "load_res_ms": statistics.median(ph["load_res_ms"] for ph in phases),
            "door_open_call_ms": statistics.median(d["open_call_ms"] for d in doors),
            "door_longest_frame_ms": statistics.median(d["max_frame_ms_after"] for d in doors),
            "door_worst_frame_ms": max(d["max_frame_ms_after"] for d in doors),
            "meshes_in_region_per_door": statistics.median(d["meshes_in_region"] for d in doors),
        }
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()
    web = export_bench(args.godot, args.work)
    server, port = smoke.serve(web)
    try:
        runs = [run_once(f"http://127.0.0.1:{port}/index.html") for _ in range(args.runs)]
    finally:
        server.shutdown()
    (args.work / "door_swap.json").write_text(json.dumps(runs, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(summarise(runs), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
