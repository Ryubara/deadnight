"""The view is the person's own soldier in a solo night with 3 bots, in the web build, in headless Chromium (#702).

Presses Solo on the menu's Play tab, sets the Bots row to 3 on the Play screen with the keyboard, starts the night and
waits for it to run. Then, for a few seconds, it reads the game's probe: `bots` must be 3 and `view_is_players` (the
viewport's current camera is the person's own body's camera) must be true every time it is read. A build where a bot's
body took the camera reports false. Takes a screenshot of the start of the night.

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/camera_owner.py build/web build/camera-owner [--label after] [--expect-wrong]

The first argument is a folder with the export (served locally) or the URL of a deployed build. `--expect-wrong` is the
"before" run: it accepts a view through a bot and only records it. Writes `<label>-night.png` and `<label>-result.json`;
exits 1 when a check fails.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

# The browser refuses a pointer lock that is not asked for inside a click or key press; the game goes on.
IGNORED = ("A user gesture is required to request Pointer Lock",)
READS = 12
READ_EVERY_MS = 500


def full(page: Page) -> dict:
    """Everything the game publishes (`smoke.probe` keeps the few fields the other probes read)."""
    return page.evaluate("() => ({ ...window.deadnight })") or {}


def start_with_three_bots(page: Page) -> None:
    smoke.menu_item(page, "Play", 2)
    smoke.press(page, "Enter")
    smoke.wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", 60)
    page.wait_for_timeout(1500)
    smoke.press(page, "ArrowUp")  # Start has the focus: Up reaches the Bots row
    for _ in range(3):
        smoke.press(page, "ArrowRight")  # 0 -> 3 bots
    page.wait_for_timeout(600)
    smoke.press(page, "ArrowDown")  # back to Start
    smoke.press(page, "Enter")
    smoke.wait_for_night(page)


def run(url: str, out: Path, label: str, problems: list[str]) -> dict:
    result: dict = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=smoke.SOFTWARE_GL)
        page = browser.new_context(viewport=smoke.VIEWPORT).new_page()
        page.on("pageerror", lambda e: None if any(t in str(e) for t in IGNORED) else problems.append(str(e)))
        page.on(
            "console",
            lambda m: problems.append(m.text) if m.type == "error" and not any(t in m.text for t in IGNORED) else None,
        )
        page.goto(url, wait_until="commit")
        smoke.reach_menu(page)
        try:
            start_with_three_bots(page)
            page.wait_for_timeout(2500)
            reads = []
            for _ in range(READS):
                state = full(page)
                reads.append({"bots": state.get("bots"), "view_is_players": state.get("view_is_players")})
                page.wait_for_timeout(READ_EVERY_MS)
            result["reads"] = reads
            page.screenshot(path=out / f"{label}-night.png")
        except (TimeoutError, PlaywrightError, RuntimeError) as error:
            problems.append(str(error))
            page.screenshot(path=out / f"{label}-failure.png")
        browser.close()
    return result


def verdict(result: dict, expect_wrong: bool) -> list[str]:
    reads = result.get("reads", [])
    if not reads:
        return ["the night never ran, nothing was read"]
    wrong = []
    if any(read["bots"] != 3 for read in reads):
        wrong.append(f"the night did not seat 3 bots: {sorted({str(r['bots']) for r in reads})}")
    if any(read["view_is_players"] is None for read in reads):
        wrong.append("the probe does not publish view_is_players")
    elif not expect_wrong and not all(read["view_is_players"] for read in reads):
        wrong.append(
            f"the view was not the person's in {sum(not r['view_is_players'] for r in reads)} of {len(reads)} reads"
        )
    elif expect_wrong and all(read["view_is_players"] for read in reads):
        wrong.append("a view through a bot was expected (the 'before' build), the person had the view")
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("build", help="folder with the web export, or the URL of a deployed build")
    parser.add_argument("out", type=Path)
    parser.add_argument("--label", default="after")
    parser.add_argument(
        "--expect-wrong", action="store_true", help="the 'before' run: a view through a bot is expected"
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    problems: list[str] = []
    started = time.monotonic()
    result = run(url, args.out, args.label, problems)
    if server:
        server.shutdown()
    problems += verdict(result, args.expect_wrong)
    report = json.dumps(
        {"result": result, "problems": problems, "seconds": round(time.monotonic() - started)}, indent=2
    )
    (args.out / f"{args.label}-result.json").write_text(report)
    print(report)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
