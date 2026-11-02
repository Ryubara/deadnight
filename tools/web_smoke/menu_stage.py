"""Frame time of the main menu's live 3D stage, measured in the browser (issue #397).

Serves the web export (a folder, or opens a URL) and opens the stage on its own (`index.html?stage`, and
`?stage=still` for the still level, `game/ui/screens/menu_stage_screen.gd`), once for each case below. In each it walks
the camera round the five tabs with the Right key (a move every 2.5 s) and records the page's own
`requestAnimationFrame` deltas and the GL programs linked per frame. It also records today's main menu (the sky shader
and the sign) in the same browser, for a comparison, and writes a screenshot of each case.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/menu_stage.py build/web build/menu-stage
    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/menu_stage.py build/web build/menu-stage --gpu --unpaced

`--gpu` uses the installed Chrome and the machine's GPU (headless, so no window opens); without it Chromium draws with
SwiftShader on the CPU, which says the stage runs without a GPU and nothing about a phone. `--unpaced` lifts the
display's frame limit so the numbers are the work of drawing, not the refresh rate. `--budget-p95 MS` fails the run
when the live stage's 95th-percentile frame is longer (only meaningful with `--gpu --unpaced`). Fails on any console
error and on a frame that links more than 12 GL programs after the first seconds (a hitch, not a draw).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError
from smoke import (
    FRAME_TIMES_JS,
    LINKS_PER_FRAME_JS,
    LOAD_TIMEOUT_S,
    SOFTWARE_GL,
    UNPACED,
    gl_info,
    press,
    serve,
    stats,
    wait_for,
)

CASES = [
    # name, query, screen the probe must report, viewport
    ("menu_today_720p", "", "main_menu", {"width": 1280, "height": 720}),
    ("stage_live_720p", "?stage", "menu_stage_screen", {"width": 1280, "height": 720}),
    ("stage_live_1080p", "?stage", "menu_stage_screen", {"width": 1920, "height": 1080}),
    ("stage_live_phone_landscape", "?stage", "menu_stage_screen", {"width": 844, "height": 390}),
    ("stage_still_1080p", "?stage=still", "menu_stage_screen", {"width": 1920, "height": 1080}),
]
SETTLE_MS = 3000
MOVE_EVERY_MS = 2500
MOVES = 5
# A hitch is a frame that links this many programs once the first seconds are over.
MAX_PROGRAMS_AFTER_SETTLE = 12


def measure(page: Page, url: str, screen: str, out: Path, name: str, moves: bool) -> dict:
    page.goto(url, wait_until="commit")
    wait_for(page, f"the {screen} screen", lambda s: s.get("screen") == screen, LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)
    page.wait_for_timeout(SETTLE_MS)
    settled_at = page.evaluate("() => performance.now()")
    page.evaluate("() => { window.__frames = []; }")
    deltas: list[float] = []
    for _ in range(MOVES):
        if moves:
            press(page, "ArrowRight")
        deltas += page.evaluate(FRAME_TIMES_JS, MOVE_EVERY_MS / 1000.0)
    page.screenshot(path=out / f"{name}.png")
    links = page.evaluate("(since) => window.__linkFrames.filter((f) => f[0] > since)", settled_at)
    return {
        **stats(deltas),
        "frames_that_linked_programs": [f for f in links if f[1] > 0],
        "most_programs_in_a_frame": max([f[1] for f in links] + [0]),
        "longest_frame_ms": max(deltas),
    }


def main() -> int:
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"cases": {}}

    def on_console(message: ConsoleMessage) -> None:
        console.append(f"[{message.type}] {message.text}")
        if message.type == "error":
            problems.append(console[-1])

    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    base = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True, args=UNPACED if args.unpaced else [])
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        try:
            for name, query, screen, viewport in CASES:
                page = browser.new_page(viewport=viewport)
                page.add_init_script("(" + LINKS_PER_FRAME_JS.strip() + ")();")
                page.on("console", on_console)
                page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
                page.on("requestfailed", lambda r: problems.append(f"[requestfailed] {r.url} {r.failure}"))
                try:
                    case = measure(page, base + query, screen, args.out, name, moves=bool(query))
                    result["cases"][name] = case
                    if case["most_programs_in_a_frame"] > MAX_PROGRAMS_AFTER_SETTLE:
                        problems.append(f"[{name}] a frame linked {case['most_programs_in_a_frame']} GL programs")
                except (TimeoutError, PlaywrightError) as error:
                    problems.append(f"[{name}] {error}")
                result["gl"] = gl_info(page)
                page.close()
        finally:
            browser.close()
            if server:
                server.shutdown()

    live = result["cases"].get("stage_live_1080p")
    if args.budget_p95 and live and live["p95_ms"] > args.budget_p95:
        problems.append(f"[budget] the live stage's p95 frame is {live['p95_ms']} ms, over {args.budget_p95} ms")
    (args.out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\nmenu stage run FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\nmenu stage run passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the web export folder, or the game's URL")
    parser.add_argument("out", type=Path, help="where the screenshots and result.json go")
    parser.add_argument("--gpu", action="store_true", help="use the installed Chrome and the machine's GPU")
    parser.add_argument("--unpaced", action="store_true", help="with --gpu: lift the display's frame limit")
    parser.add_argument("--budget-p95", type=float, default=0.0, help="fail when the live stage's p95 is over this")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(main())
