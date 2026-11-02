"""Browser check of the resolution scale setting: the night drawn at 100 % and at a lower scale.

Serves the exported build, and for each scale in a fresh browser context (so each starts with no saved settings):
opens Settings with the keyboard, lowers "Resolution scale" to that scale, goes back, presses Play, waits for a
running night and takes a screenshot. Then compares the shots: a lower scale draws the 3D world smaller and stretches
it, so the picture differs and has less detail from pixel to pixel; the run fails when it does not. It is the web half
of issue #36 (`tests/captures/resolution_scale.tscn` is the desktop half). Headless only, never a captured mouse.

    uv run --with playwright==1.64.1 --with pillow python tools/web_smoke/resolution_scale.py build/web <out>
        [--scales 100 50] [--gpu] [--size 1280x720]

`--gpu` uses the installed Chrome (this machine's GPU); without it the headless shell draws in software, which is far
slower to load a night. Frame time is not measured here.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

from PIL import Image
from playwright.sync_api import Browser, ConsoleMessage, sync_playwright
from playwright.sync_api import Error as PlaywrightError
from smoke import SOFTWARE_GL, menu_item, press, serve, wait_for

LOAD_TIMEOUT_S = 150
SCREEN_TIMEOUT_S = 40
NIGHT_LOAD_TIMEOUT_S = 240
STEP = 5  # percent per press of Left on the slider
# The part of the picture compared: the middle of the lower half, which is lot and sky, not the HUD's corners.
REGION = (0.30, 0.45, 0.70, 0.85)
# A lower scale must change this share of the region (mean absolute difference, 0 to 1) and lose this share of detail.
MIN_DIFFERENCE = 0.003
MIN_DETAIL_LOSS = 0.02


def region(png: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(png)).convert("L")
    width, height = image.size
    left, top, right, bottom = REGION
    return image.crop((int(width * left), int(height * top), int(width * right), int(height * bottom)))


def detail(image: Image.Image) -> float:
    """The mean change in brightness from one pixel to the next along a row, 0 to 1."""
    width, height = image.size
    pixels = image.load()
    total = 0
    for y in range(height):
        for x in range(1, width):
            total += abs(pixels[x, y] - pixels[x - 1, y])
    return total / (255.0 * height * (width - 1))


def difference(a: Image.Image, b: Image.Image) -> float:
    pa, pb = a.load(), b.load()
    width, height = a.size
    total = sum(abs(pa[x, y] - pb[x, y]) for y in range(height) for x in range(width))
    return total / (255.0 * width * height)


def shot_at(browser: Browser, url: str, scale: int, out: Path, size: dict, console: list, problems: list) -> bytes:
    page = browser.new_page(viewport=size)
    page.on("console", lambda m: on_console(m, console, problems))
    page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
    try:
        page.goto(url, wait_until="commit")
        wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
        page.mouse.click(5, 5)  # gives the canvas the keyboard
        page.wait_for_timeout(2500)
        # Settings is the first item of the More tab; the first tab is Video, whose first row on the web is the
        # resolution scale.
        menu_item(page, "More")
        press(page, "Enter")
        wait_for(page, "settings", lambda s: s.get("screen") == "settings_screen", SCREEN_TIMEOUT_S)
        page.wait_for_timeout(1500)
        press(page, "ArrowDown")  # from the tab strip to the first row
        for _ in range((100 - scale) // STEP):
            press(page, "ArrowLeft")
        page.wait_for_timeout(800)
        page.screenshot(path=out / f"settings_{scale}.png")
        press(page, "Escape")
        wait_for(page, "the menu", lambda s: s.get("screen") == "main_menu", SCREEN_TIMEOUT_S)
        page.wait_for_timeout(1500)
        menu_item(page, "Play", 2)
        press(page, "Enter")  # Solo
        wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
        page.wait_for_timeout(4000)
        png = page.screenshot()
        (out / f"night_{scale}.png").write_bytes(png)
        return png
    finally:
        page.close()


def on_console(message: ConsoleMessage, console: list, problems: list) -> None:
    console.append(f"[{message.type}] {message.text}")
    if message.type == "error":
        problems.append(console[-1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--scales", type=int, nargs="+", default=[100, 50])
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--size", default="1280x720")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    width, height = (int(part) for part in args.size.split("x"))
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"scales": args.scales, "viewport": [width, height], "regions": {}}
    shots: dict[int, bytes] = {}
    server, port = serve(args.build)
    with sync_playwright() as p:
        if args.gpu:
            browser = p.chromium.launch(channel="chrome", headless=True)
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        try:
            for scale in args.scales:
                shots[scale] = shot_at(
                    browser,
                    f"http://127.0.0.1:{port}/index.html",
                    scale,
                    args.out,
                    {"width": width, "height": height},
                    console,
                    problems,
                )
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
        finally:
            browser.close()
            server.shutdown()

    if len(shots) == len(args.scales):
        full = region(shots[args.scales[0]])
        full_detail = detail(full)
        result["regions"][str(args.scales[0])] = {"detail": round(full_detail, 4)}
        for scale in args.scales[1:]:
            lower = region(shots[scale])
            seen = {
                "detail": round(detail(lower), 4),
                "difference_from_full": round(difference(full, lower), 4),
            }
            result["regions"][str(scale)] = seen
            if seen["difference_from_full"] < MIN_DIFFERENCE:
                problems.append(f"[scale] {scale} % changed the picture by only {seen['difference_from_full']}")
            if seen["detail"] > full_detail * (1.0 - MIN_DETAIL_LOSS):
                problems.append(f"[scale] {scale} % kept its detail ({seen['detail']} against {round(full_detail, 4)})")
    (args.out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\nresolution scale check FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\nresolution scale check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
