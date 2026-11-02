"""Browser tour of the skin shaders: the menu, the three transitions and the credits, in a real browser.

Serves the exported build, opens it, and walks the main menu the way a player does with the keyboard: Settings (the
slide), back, Credits (the burn), back, Play (the iris). It fails on any console error or page error, takes a run of
screenshots during every transition, checks each for a frame that is all black or all white (a shader that went wrong
usually does one of those), and records the page's frame times on the menu and through each transition at the
viewport's size (1080p by default). It is the browser half of issue #82; `smoke.py` is the CI gate.

    uv run --with playwright==1.64.1 --with pillow python tools/web_smoke/skin_tour.py build/web build/skin-tour
        [--browser chromium|chrome|firefox] [--size 1920x1080]

`chromium` is the headless shell (software GL), `chrome` the installed Chrome (this machine's GPU), `firefox` needs
`playwright install firefox`. Frame times depend on the machine: they are reported, never gated.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import time
from pathlib import Path

from PIL import Image
from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError
from smoke import SOFTWARE_GL, UNPACED, press, serve, stats, wait_for

LOAD_TIMEOUT_S = 150
SCREEN_TIMEOUT_S = 40
# Screenshots taken one after the other while a transition runs (each takes a while itself, so these are spread over
# the transition, not frame-exact).
SHOTS_PER_TRANSITION = 8
# A shot is "bad" when this share of its pixels is exactly black or exactly white. The burn has one char frame (all
# near black) by design; the menu and the credits never come near it.
BAD_SHARE = 0.98
MEASURE_MS = 1500

# Records the page's frame deltas from the start, with the page clock, so the run can ask for a slice afterwards.
RECORDER_JS = """
() => {
  window.__frames = [];
  let last = performance.now();
  function frame(now) { window.__frames.push([now, now - last]); last = now; requestAnimationFrame(frame); }
  requestAnimationFrame(frame);
}
"""
SLICE_JS = "([from, to]) => window.__frames.filter(f => f[0] >= from && f[0] <= to).map(f => f[1])"


def judge(png: bytes) -> dict:
    """Mean brightness and the share of pixels that are exactly black or exactly white."""
    image = Image.open(io.BytesIO(png)).convert("RGB")
    pixels = list(image.getdata())
    black = sum(1 for p in pixels if p == (0, 0, 0))
    white = sum(1 for p in pixels if p == (255, 255, 255))
    mean = sum(sum(p) for p in pixels) / (3 * len(pixels))
    return {
        "mean_brightness": round(mean, 1),
        "black_share": round(black / len(pixels), 3),
        "white_share": round(white / len(pixels), 3),
    }


def shot(page: Page, out: Path, name: str, report: list[dict], problems: list[str]) -> None:
    png = page.screenshot()
    (out / f"{name}.png").write_bytes(png)
    verdict = {"shot": name, **judge(png)}
    report.append(verdict)
    if verdict["black_share"] > BAD_SHARE or verdict["white_share"] > BAD_SHARE:
        problems.append(f"[pixels] {name} is all black or all white: {verdict}")


def clock(page: Page) -> float:
    return page.evaluate("performance.now()")


def transition(
    page: Page, out: Path, name: str, key: str, report: list[dict], problems: list[str], result: dict
) -> None:
    """Presses `key`, takes a run of shots while the transition plays, and records the frames of that time.

    Taking a shot stalls the page, so those frame times are not the transition's: `measure` does a pass of its own.
    """
    press(page, key)
    for index in range(SHOTS_PER_TRANSITION):
        shot(page, out, f"{name}_{index}", report, problems)


def measure(page: Page, name: str, key: str, result: dict) -> None:
    """Presses `key` and records the page's frames for the next 1.5 s, with nothing else asking the page for anything."""
    start = clock(page)
    press(page, key)
    page.wait_for_timeout(MEASURE_MS)
    result["frames"][name] = stats(page.evaluate(SLICE_JS, [start, clock(page)]))


def to_item(page: Page, steps: int) -> None:
    """Walks the menu to the item `steps` below Play. Focus stops at the ends, so Up six times lands on Play whether
    the menu remembered an item or has none (then the first key is spent on taking focus)."""
    for _ in range(6):
        press(page, "ArrowUp")
    for _ in range(steps):
        press(page, "ArrowDown")


def run(page: Page, url: str, out: Path, result: dict, problems: list[str]) -> None:
    report: list[dict] = result["shots"]
    started = time.monotonic()
    page.goto(url, wait_until="commit")
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    result["load_to_menu_s"] = round(time.monotonic() - started, 2)
    page.mouse.click(5, 5)  # gives the canvas the keyboard
    page.wait_for_timeout(2500)
    shot(page, out, "menu", report, problems)
    begin = clock(page)
    page.wait_for_timeout(3000)
    result["frames"]["menu"] = stats(page.evaluate(SLICE_JS, [begin, clock(page)]))

    # Settings is the fourth item (the slide), Credits the fifth (the burn), Play the first (the iris). Each of the
    # first two is entered twice: once to measure the frames, once to take the shots.
    to_item(page, 3)
    measure(page, "settings_slide", "Enter", result)
    press(page, "Escape")
    wait_for(page, "the menu", lambda s: s.get("screen") == "main_menu", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    to_item(page, 3)
    transition(page, out, "settings_slide", "Enter", report, problems, result)
    wait_for(page, "settings", lambda s: s.get("screen") == "settings_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    shot(page, out, "settings", report, problems)
    press(page, "Escape")
    wait_for(page, "the menu", lambda s: s.get("screen") == "main_menu", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)

    to_item(page, 4)
    measure(page, "credits_burn", "Enter", result)
    press(page, "Escape")
    wait_for(page, "the menu", lambda s: s.get("screen") == "main_menu", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    to_item(page, 4)
    transition(page, out, "credits_burn", "Enter", report, problems, result)
    wait_for(page, "the credits", lambda s: s.get("screen") == "credits_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(2000)
    shot(page, out, "credits", report, problems)
    press(page, "Escape")
    wait_for(page, "the menu", lambda s: s.get("screen") == "main_menu", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)

    # Play builds the night behind the iris, so its frames are the loading's, not the iris's: only the shots are kept.
    to_item(page, 0)
    transition(page, out, "play_iris", "Enter", report, problems, result)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--browser", choices=("chromium", "chrome", "firefox"), default="chromium")
    parser.add_argument("--size", default="1920x1080")
    parser.add_argument("--unpaced", action="store_true", help="with chrome: do not hold the page to the refresh rate")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    width, height = (int(part) for part in args.size.split("x"))
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"browser": args.browser, "viewport": [width, height], "frames": {}, "shots": []}

    def on_console(message: ConsoleMessage) -> None:
        console.append(f"[{message.type}] {message.text}")
        if message.type == "error":
            problems.append(console[-1])

    server, port = serve(args.build)
    with sync_playwright() as p:
        if args.browser == "firefox":
            browser = p.firefox.launch(headless=True)
        elif args.browser == "chrome":
            browser = p.chromium.launch(channel="chrome", headless=True, args=UNPACED if args.unpaced else [])
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        page = browser.new_page(viewport={"width": width, "height": height})
        page.add_init_script("(" + RECORDER_JS.strip() + ")();")
        page.on("console", on_console)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        page.on("requestfailed", lambda r: problems.append(f"[requestfailed] {r.url} {r.failure}"))
        try:
            run(page, f"http://127.0.0.1:{port}/index.html", args.out, result, problems)
            result["gl"] = page.evaluate(
                "() => { const gl = document.createElement('canvas').getContext('webgl2'); if (!gl) return 'no webgl2';"
                " const e = gl.getExtension('WEBGL_debug_renderer_info');"
                " return gl.getParameter(gl.VERSION) + ' | ' + (e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : 'n/a'); }"
            )
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=args.out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            browser.close()
            server.shutdown()

    (args.out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["console_lines"] = len(console)
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "shots"}, indent=2))
    if problems:
        print(f"\nskin tour FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\nskin tour passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
