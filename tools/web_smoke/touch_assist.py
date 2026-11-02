"""The touch aim assist in a real browser (#286): real touches on a phone-sized page, with the assist off and on.

The run exports a copy of the project that starts on `game/tests/captures/touch_assist_bench.tscn` (the real project's
export leaves `tests/` out): the game's own night screen with the touch layer forced on, one zombie held beside the
crosshair. In a headless Chrome with touch emulation it then sends what a thumb would, through the DevTools protocol:
a finger on the look area that drags toward the zombie and stops short, then a finger on the Aim button. It reads what
the game reports (`window.__assist`): how far the crosshair is from the zombie's chest, the shots fired, the kills,
and the longest frame.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/touch_assist.py <godot> <work folder> [--out <folder>]

`<godot>` is the pinned Godot (`gds tool path godot`); the copy and its export are made in `<work folder>`. It fails
when the browser logs an error, when the night is paused, when the bench does not start with the crosshair off the
zombie (there would be nothing to drag), when the look drag does not turn the view and bring the crosshair beside the
zombie (the yaw and the distance at every drag step are in the message), when the assist does not bring the crosshair
nearer than the unhelped thumb gets, or when auto-fire is off and a shot is fired anyway.
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

from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

GAME = Path(__file__).resolve().parents[2] / "game"
BENCH_SCENE = "res://tests/captures/touch_assist_bench.tscn"
SKIP = shutil.ignore_patterns(".godot", "reports", "build")
VIEWPORT = {"width": 844, "height": 390}
READY_TIMEOUT_S = 240
DRAG_STEPS = 60
# The bench starts the crosshair at least this far (metres) beyond where the drag stops, or there is nothing to drag.
MIN_TO_DRAG_M = 0.2
STEP_PERIOD_S = 0.1
AIM_HOLD_S = 4.0
# The runs: the page's query and what each must show.
RUNS = {
    "off": "touch=1&assist=0&auto=0",
    "assist": "touch=1&assist=0.5&auto=1",
}


def export_bench(godot: str, work: Path, scene: str = BENCH_SCENE) -> Path:
    """A copy of the project whose main scene is `scene` and whose export keeps `tests/`; returns the web folder."""
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


def touch(client: CDPSession, kind: str, points: list[tuple[int, float, float]]) -> None:
    """One touch event: `points` are the fingers down after it, as (id, x, y) in page pixels."""
    client.send(
        "Input.dispatchTouchEvent",
        {"type": kind, "touchPoints": [{"id": i, "x": x, "y": y} for i, x, y in points]},
    )


def state(page: Page) -> dict:
    return page.evaluate("window.__assist || {}") or {}


def thumb(page: Page, client: CDPSession, shot: Path | None = None) -> dict:
    """Drag toward the zombie until the crosshair is near it, then hold Aim; returns what the game saw at the end.

    `trace` is one (yaw, distance in metres) per drag step, the first being the view before the finger moved.
    """
    first = state(page)
    trace = [(first["yaw"], first["lateral"])]
    if first["lateral"] < first["stop"] + MIN_TO_DRAG_M:
        raise RuntimeError(
            f"the bench starts with the crosshair {first['lateral']:.2f} m from the chest, "
            f"{first['stop']:.2f} m is where the drag stops: nothing to drag"
        )
    x, y = first["look_from"]
    touch(client, "touchStart", [(1, x, y)])
    for _ in range(DRAG_STEPS):
        seen = state(page)
        if seen["lateral"] < seen["stop"]:
            break
        dx, dy = seen["step_px"]
        x, y = x + dx, y + dy
        touch(client, "touchMove", [(1, x, y)])
        time.sleep(STEP_PERIOD_S)
        trace.append((state(page)["yaw"], state(page)["lateral"]))
    touch(client, "touchEnd", [])
    dragged = state(page)
    if shot is not None:
        page.screenshot(path=str(shot))
    aim_x, aim_y = dragged["aim"]
    touch(client, "touchStart", [(2, aim_x, aim_y)])
    time.sleep(AIM_HOLD_S)
    after = state(page)
    touch(client, "touchEnd", [])
    return {"before_aim": dragged, "after": after, "trace": trace, "start": first}


def run_once(url: str, label: str, query: str, out: Path | None) -> dict:
    problems: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(viewport=VIEWPORT, has_touch=True, is_mobile=True)
        page = context.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.on(
            "console",
            lambda m: problems.append(f"console {m.type}: {m.text}") if m.type == "error" else None,
        )
        page.goto(f"{url}?{query}", wait_until="commit")
        deadline = time.monotonic() + READY_TIMEOUT_S
        while time.monotonic() < deadline and not state(page).get("ready"):
            if state(page).get("failed"):
                raise RuntimeError(state(page)["failed"])
            time.sleep(0.5)
        if not state(page).get("ready"):
            seen = state(page)
            raise TimeoutError(
                f"{label}: the bench never got ready (paused {seen.get('paused')}, "
                f"mouse lost {seen.get('grip_lost')} times, {seen.get('zombies_seen')} zombies)"
            )
        client = context.new_cdp_session(page)
        if out is not None:
            out.mkdir(parents=True, exist_ok=True)
        result = thumb(page, client, out / f"touch_assist_{label}_dragged.png" if out is not None else None)
        if out is not None:
            page.screenshot(path=str(out / f"touch_assist_{label}.png"))
        browser.close()
    result["problems"] = problems
    return result


def drag_problems(label: str, result: dict) -> list[str]:
    """What is wrong with the look drag of a run: the night paused, or the view did not turn to the zombie."""
    trace = result["trace"]
    steps = " ".join(f"{yaw:.3f}/{lateral:.2f}" for yaw, lateral in trace)
    wrong: list[str] = []
    if result["after"].get("paused"):
        wrong.append(f"{label}: the night paused ({result['after'].get('grip_lost')} times the mouse was lost)")
    if trace[-1][0] == trace[0][0]:
        wrong.append(f"{label}: the look drag never turned the view; yaw/metres per step: {steps}")
    elif result["before_aim"]["lateral"] >= result["before_aim"]["stop"]:
        wrong.append(
            f"{label}: the drag ended {result['before_aim']['lateral']:.2f} m off; yaw/metres per step: {steps}"
        )
    return wrong


def verdict(runs: dict[str, dict]) -> list[str]:
    """What is wrong with the runs, in words; empty when the assist did what it should."""
    wrong: list[str] = []
    for label, result in runs.items():
        wrong += [f"{label}: {p}" for p in result["problems"]]
        wrong += drag_problems(label, result)
        if not result["after"].get("touch"):
            wrong.append(f"{label}: the game never saw a finger as the last input")
    off, helped = runs["off"]["after"], runs["assist"]["after"]
    if off["shots"] != 0:
        wrong.append(f"off: {off['shots']} shots fired with auto-fire off")
    if helped["lateral"] >= off["lateral"] and not helped["kills"]:
        wrong.append(
            f"assist: the crosshair is {helped['lateral']:.2f} m from the chest, off had {off['lateral']:.2f} m"
        )
    if helped["shots"] == 0:
        wrong.append("assist: auto-fire never pulled the trigger")
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("godot")
    parser.add_argument("work", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="where the screenshots go")
    parser.add_argument("--runs", type=int, default=1, help="how many times to repeat both runs on the one export")
    args = parser.parse_args()
    web = export_bench(args.godot, args.work)
    server, port = smoke.serve(web)
    failed = 0
    try:
        for number in range(1, args.runs + 1):
            runs: dict[str, dict] = {}
            wrong: list[str] = []
            try:
                for label, query in RUNS.items():
                    shots = args.out / f"run{number}" if args.out is not None and args.runs > 1 else args.out
                    runs[label] = run_once(f"http://127.0.0.1:{port}/index.html", label, query, shots)
                wrong = verdict(runs)
            except (RuntimeError, TimeoutError) as error:
                wrong = [str(error)]
            (args.work / f"touch_assist_{number}.json").write_text(json.dumps(runs, indent=1) + "\n", encoding="utf-8")
            print(f"run {number}/{args.runs}:", json.dumps({k: v["after"] for k, v in runs.items()}))
            for line in wrong:
                print("FAILED:", line)
            failed += 1 if wrong else 0
    finally:
        server.shutdown()
    if args.runs > 1:
        print(f"{args.runs - failed} of {args.runs} runs passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
