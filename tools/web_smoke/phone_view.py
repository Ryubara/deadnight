r"""Whether a phone page shows the game at the scale it should, and whether a zoom can get stuck (issue #1310).

The maintainer played on a real phone and found the game "super zoomed in". Every earlier phone measure (`phone_layout.py`)
reads the game's own numbers in headless Chrome at one fixed viewport. This one reads the page's: the layout viewport
(`innerWidth`), the visual viewport (`visualViewport.scale`, size, offset), the pixel ratio the page reports and the one the
device has, and the canvas's box and pixels, then holds them against what they must be:

- the canvas box is the page, and the page is the visual viewport at scale 1 (nothing is zoomed, nothing is cut off);
- the canvas has `min(device ratio, 2)` pixels to a CSS pixel (`PhoneRender.PIXEL_RATIO_CAP`);
- the game's CSS pixels to a unit is the page's height over 540 in the phone's menu and over 1080 in a night;
- the `?viewcheck` readout says the same numbers (it is what the maintainer reads off a real phone), and is not there
  without the query;
- two fingers pulled apart and a double tap on the page leave the scale at 1;
- a page turned upright and back, and a page whose height changes (an address bar), follow on the next frames.

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/phone_view.py <web folder> <out folder> \
        [--night] [--iframe] [--engine webkit] [--dprcap 3]

`--night` also starts a solo night in the first case. `--iframe` repeats the first case in an iframe of another origin (as
Discord shows an Activity). `--engine webkit` runs Playwright's WebKit with the iPhone device descriptors (iPhone 14, 13
Pro Max, SE, landscape): the nearest engine to iOS Safari here, which is not Safari (no pinch, no real toolbars, a
software GL), and its `navigator.maxTouchPoints` is 0 where an iPhone's is 5, so the page is given 5. `--dprcap 3` loads
`?dprcap=3`, the page as it would run if the ratio cap did not apply. What it cannot show: a real phone, iOS Safari (which
ignores `user-scalable=no`, takes a zoom of its own to a focused field smaller than 16 px and leaves it), Discord's own
webview. Run it under `gds quiet`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import phone_layout
import smoke

PHONE_AGENT = phone_layout.PHONE_AGENT
# (width, height, device pixel ratio) of CSS pixels: a phone, a big phone, the narrowest, a Pixel's ratio, a page with
# the address bar showing, and a ratio of 4 (a Galaxy's 3.75) that the page must hold to the cap of 2.
CASES = [
    (844, 390, 3.0),
    (932, 430, 3.0),
    (667, 375, 2.0),
    (915, 412, 2.625),
    (844, 340, 3.0),
    (740, 360, 4.0),
]
PIXEL_RATIO_CAP = 2.0
# Playwright's WebKit with the iPhone descriptors: the nearest engine to iOS Safari here, which is not Safari. Its
# `navigator.maxTouchPoints` is 0 where an iPhone's is 5 (`TouchMode.detect` asks for more than 0), so the page is
# given 5, as a phone would.
WEBKIT_DEVICES = ["iPhone 14 landscape", "iPhone 13 Pro Max landscape", "iPhone SE landscape"]
WEBKIT_INIT = "Object.defineProperty(navigator, 'maxTouchPoints', {get: () => 5});"
UNITS_MENU = 540.0
UNITS_NIGHT = 1080.0
TOLERANCE = 0.6  # CSS pixels: a box is read to a tenth, a canvas rounds to a pixel
FRAMES_MS = 1500

GEOMETRY_JS = """() => {
  const frame = document.getElementById('canvas');
  const box = frame ? frame.getBoundingClientRect() : {x: 0, y: 0, width: 0, height: 0};
  const view = window.visualViewport;
  const pixels = window.deadnightPixels || {};
  const game = window.deadnight || {};
  const note = document.getElementById('viewcheck');
  return {
    inner: [innerWidth, innerHeight],
    ratio: devicePixelRatio, real_ratio: pixels.real || null,
    visual: view ? [view.width, view.height, view.scale, view.offsetLeft, view.offsetTop] : null,
    box: [box.x, box.y, box.width, box.height],
    canvas: frame ? [frame.width, frame.height] : null,
    layout: game.layout || '', phone: !!game.phone, screen: game.screen || '',
    readout: note ? note.textContent : null,
  };
}"""


def parse_readout(text: str | None) -> dict:
    """The numbers of the `?viewcheck` lines, or {} when there is no readout."""
    if not text:
        return {}
    found = {}
    page = re.search(r"page (\d+) x (\d+) css px", text)
    visual = re.search(r"visual ([\d.]+) x ([\d.]+) scale ([\d.]+) \(seen ([\d.]+) to ([\d.]+)\)", text)
    canvas = re.search(r"canvas box ([\d.]+) x ([\d.]+) px (\d+) x (\d+)", text)
    ratio = re.search(r"ratio real ([\d.]+) used ([\d.]+) cap (\S+) getter (\w+) physical (\d+) px", text)
    heights = re.search(r"vh (\d+) svh (\d+) dvh (\d+) lvh (\d+)", text)
    safe = re.search(r"safe (\S+) (\S+) (\S+) (\S+)", text)
    action = re.search(r"touch-action html (\S+) body (\S+) canvas (\S+)", text)
    gestures = re.search(r"gestures (\d+) last scale ([\d.]+), two-finger touches (\d+)", text)
    units = re.search(r"night ([\d.]+) phone menu ([\d.]+)", text)
    if page:
        found["page"] = [int(page[1]), int(page[2])]
    if visual:
        found["visual"] = [float(visual[1]), float(visual[2])]
        found["scale"] = float(visual[3])
        found["scale_seen"] = [float(visual[4]), float(visual[5])]
    if canvas:
        found["box"] = [float(canvas[1]), float(canvas[2])]
        found["pixels"] = [int(canvas[3]), int(canvas[4])]
    if ratio:
        found["ratio_real"] = float(ratio[1])
        found["ratio_used"] = float(ratio[2])
        found["cap"] = ratio[3]
        found["getter"] = ratio[4]
        found["physical"] = int(ratio[5])
    if heights:
        found["vh"] = [int(heights[i]) for i in range(1, 5)]
    if safe:
        found["safe"] = [safe[i] for i in range(1, 5)]
    if action:
        found["touch_action"] = [action[1], action[2], action[3]]
    if gestures:
        found["gestures"] = [int(gestures[1]), float(gestures[2]), int(gestures[3])]
    if units:
        found["per_unit_night"] = float(units[1])
        found["per_unit_menu"] = float(units[2])
    return found


class Run:
    def __init__(self, out: Path, cap: float = PIXEL_RATIO_CAP) -> None:
        self.out = out
        self.cap = cap
        self.problems: list[str] = []
        self.rows: list[dict] = []

    def expect(self, ok: bool, what: str, case: str, detail: object = "") -> None:
        if not ok:
            self.problems.append(f"{case}: {what} {detail}")

    def read(self, page_or_frame, case: str, tag: str, *, units: float | None, page: Page | None = None) -> dict:
        """One reading of the geometry; checks the invariants that hold in every state."""
        got = page_or_frame.evaluate(GEOMETRY_JS)
        inner, box, canvas = got["inner"], got["box"], got["canvas"]
        visual = got["visual"] or [0, 0, 1, 0, 0]
        label = f"{case} {tag}"
        self.expect(
            abs(box[2] - inner[0]) < TOLERANCE and abs(box[3] - inner[1]) < TOLERANCE,
            "canvas box is not the page",
            label,
            (box, inner),
        )
        self.expect(
            abs(visual[0] - inner[0]) < TOLERANCE and abs(visual[1] - inner[1]) < TOLERANCE,
            "visual viewport is not the page",
            label,
            (visual, inner),
        )
        self.expect(abs(visual[2] - 1.0) < 0.001, "page is zoomed", label, visual[2])
        self.expect(visual[3] == 0 and visual[4] == 0, "page is panned", label, visual[3:])
        want_ratio = min(got["real_ratio"] or got["ratio"], self.cap)
        self.expect(abs(got["ratio"] - want_ratio) < 0.001, "pixel ratio is not capped", label, got["ratio"])
        self.expect(
            canvas is not None
            and abs(canvas[0] - round(inner[0] * got["ratio"])) <= 1
            and abs(canvas[1] - round(inner[1] * got["ratio"])) <= 1,
            "canvas pixels are not the page's times the ratio",
            label,
            (canvas, inner, got["ratio"]),
        )
        layout = phone_layout.parse_layout(got["layout"])
        if units is not None and layout:
            want = inner[1] / units
            self.expect(
                abs(layout["css_per_unit"] - want) < 0.005,
                "a unit is not the page's height over the canvas's units",
                label,
                (layout["css_per_unit"], round(want, 4)),
            )
        readout = parse_readout(got["readout"])
        self.expect(got["readout"] is not None, "no ?viewcheck readout on the page", label)
        if got["readout"] is not None:
            self.expect(readout.get("page") == inner, "readout page differs", label, (readout.get("page"), inner))
            self.expect(
                readout.get("pixels") == canvas and abs(readout.get("scale", 0) - visual[2]) < 0.01,
                "readout canvas or scale differs",
                label,
                readout,
            )
            self.expect(
                readout.get("getter") == "own", "the ratio cap found no own getter", label, readout.get("getter")
            )
            self.expect(
                readout.get("touch_action", ["none", "none"])[:2] == ["none", "none"],
                "touch-action is not none on html and body",
                label,
                readout.get("touch_action"),
            )
        row = {"case": case, "tag": tag, **got, "per_unit": layout.get("css_per_unit"), "readout_numbers": readout}
        self.rows.append(row)
        print(
            f"{label:34s} page={inner} visual={[round(n, 2) for n in visual]} box={[round(n, 1) for n in box[2:]]} "
            f"canvas={canvas} ratio={got['ratio']}(real {got['real_ratio']}) per_unit={layout.get('css_per_unit')}"
        )
        if page is not None:
            page.screenshot(path=self.out / f"{case}_{tag.replace(' ', '_')}.png")
        return row


def pinch(page: Page, centre: tuple[float, float]) -> None:
    """Two fingers pulled apart, as raw touch events (Chrome's synthesized pinch does nothing in headless emulation)."""
    cdp = page.context.new_cdp_session(page)

    def fingers(spread: float) -> list[dict]:
        return [
            {"x": centre[0] - spread, "y": centre[1], "id": 1},
            {"x": centre[0] + spread, "y": centre[1], "id": 2},
        ]

    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": fingers(30)})
    for spread in range(30, 200, 10):
        cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": fingers(spread)})
        page.wait_for_timeout(16)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    cdp.detach()


def open_browser(playwright, engine: str, case: dict):
    """A browser and a phone context for one case: Chrome as a Pixel, or WebKit as an iPhone (`WEBKIT_DEVICES`)."""
    if engine == "webkit":
        browser = playwright.webkit.launch(headless=True)
        context = browser.new_context(**playwright.devices[case["device"]])
        context.add_init_script(WEBKIT_INIT)
        return browser, context
    browser = playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
    context = browser.new_context(
        viewport={"width": case["width"], "height": case["height"]},
        device_scale_factor=case["ratio"],
        is_mobile=True,
        has_touch=True,
        user_agent=PHONE_AGENT,
    )
    return browser, context


def run_case(playwright, web_port: int, run: Run, case: dict, args, *, first: bool) -> None:
    engine = args.engine
    query = "?probe&viewcheck" + (f"&dprcap={args.dprcap:g}" if args.dprcap else "")
    url = f"http://127.0.0.1:{web_port}/index.html{query}"
    parent = None
    if first and args.iframe:
        parent, url = phone_layout.serve_parent(url)
    browser, context = open_browser(playwright, engine, case)
    page = context.new_page()
    width, height = page.viewport_size["width"], page.viewport_size["height"]
    ratio = case.get("ratio") or playwright.devices[case["device"]]["device_scale_factor"]
    label = case.get("device") or f"{width}x{height}"
    label = f"{engine} {label} @{ratio:g}" + (f" cap {args.dprcap:g}" if args.dprcap else "")
    page.add_init_script("window.deadnight_probe = true;")
    page.goto(url, wait_until="commit")
    target = page
    if parent:
        label += " iframe"
        deadline = time.monotonic() + 60
        frame = None
        while time.monotonic() < deadline and frame is None:
            frame = next((f for f in page.frames if f != page.main_frame), None)
            page.wait_for_timeout(200)
        assert frame is not None, "the iframe never loaded"
        target = frame
    smoke.wait_for(
        phone_layout._FramePage(page, target) if parent else page,
        "the main menu",
        lambda s: s.get("screen") == "main_menu",
        smoke.LOAD_TIMEOUT_S,
    )
    page.touchscreen.tap(5, 5)
    page.wait_for_timeout(2500)
    run.read(target, label, "menu", units=UNITS_MENU, page=page)
    if first:
        page.touchscreen.tap(width / 2, height / 2)
        page.wait_for_timeout(120)
        page.touchscreen.tap(width / 2, height / 2)
        page.wait_for_timeout(FRAMES_MS)
        run.read(target, label, "after a double tap", units=None)
        if engine == "chromium":
            pinch(page, (width / 2, height / 2))
            page.wait_for_timeout(FRAMES_MS)
            run.read(target, label, "after a pinch", units=None)
        for turned in ((height, width), (width, height)):
            page.set_viewport_size({"width": turned[0], "height": turned[1]})
            page.wait_for_timeout(2000)
            upright = turned[0] < turned[1]
            run.read(target, label, "upright" if upright else "turned back", units=None, page=page)
        for shorter in (height + 22, height - 50, height):
            page.set_viewport_size({"width": width, "height": shorter})
            page.wait_for_timeout(2000)
            run.read(target, label, f"height {shorter}", units=None)
        if args.night and not parent:
            smoke.start_solo(page)
            smoke.wait_for_night(page)
            page.wait_for_timeout(8000)
            run.read(target, label, "night", units=UNITS_NIGHT, page=page)
    browser.close()
    if parent:
        parent.shutdown()


def check_without_query(playwright, web_port: int, run: Run) -> None:
    """A player's page has no readout."""
    browser = playwright.chromium.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
    context = browser.new_context(
        viewport={"width": 844, "height": 390},
        device_scale_factor=3,
        is_mobile=True,
        has_touch=True,
        user_agent=PHONE_AGENT,
    )
    page = context.new_page()
    page.goto(f"http://127.0.0.1:{web_port}/index.html", wait_until="load")
    page.wait_for_timeout(4000)
    shown = page.evaluate("() => document.getElementById('viewcheck') !== null")
    run.expect(not shown, "the readout is on a page without ?viewcheck", "844x390@3")
    browser.close()


# A visual viewport as iOS leaves it after a zoom: half the page, a scale of 2, shifted down.
FAKE_ZOOM = """(() => { const real = window.visualViewport;
  const fake = {width: real.width / 2, height: real.height / 2 - 20, scale: 2, offsetLeft: 0, offsetTop: 12, pageTop: 12,
    pageLeft: 0, addEventListener: (...a) => real.addEventListener(...a)};
  Object.defineProperty(window, 'visualViewport', {get: () => fake}); })()"""


def check_verdict(playwright, web_port: int, run: Run) -> None:
    """The readout's first line names a zoomed page: it must, for the maintainer to read it on a phone that is one."""
    browser, context = open_browser(playwright, "chromium", {"width": 844, "height": 390, "ratio": 3.0})
    page = context.new_page()
    page.add_init_script("window.deadnight_probe = true;")
    page.goto(f"http://127.0.0.1:{web_port}/index.html?probe&viewcheck", wait_until="commit")
    smoke.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    page.wait_for_timeout(1200)
    before = page.evaluate("() => document.getElementById('viewcheck').textContent.split(String.fromCharCode(10))[0]")
    run.expect(
        before == "check: all as designed", "the verdict is not all as designed on a plain page", "fake zoom", before
    )
    page.evaluate(FAKE_ZOOM)
    page.wait_for_timeout(1500)
    after = page.evaluate("() => document.getElementById('viewcheck').textContent.split(String.fromCharCode(10))[0]")
    for word in ("page zoomed", "visual viewport is not the page", "page panned"):
        run.expect(word in after, f"the verdict does not say '{word}' for a zoomed page", "fake zoom", after)
    print(f"{'fake zoom':34s} verdict before: {before!r}; after: {after!r}")
    browser.close()


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--night", action="store_true")
    parser.add_argument("--iframe", action="store_true")
    parser.add_argument("--engine", choices=["chromium", "webkit"], default="chromium")
    parser.add_argument("--dprcap", type=float, default=0.0, help="the page's `?dprcap=` (0: the game's own cap of 2)")
    parser.add_argument("--no-fail", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = smoke.serve(args.web)
    run = Run(args.out, cap=args.dprcap or PIXEL_RATIO_CAP)
    cases = (
        [{"device": name} for name in WEBKIT_DEVICES]
        if args.engine == "webkit"
        else [{"width": w, "height": h, "ratio": r} for w, h, r in CASES]
    )
    try:
        with sync_playwright() as playwright:
            for index, case in enumerate(cases):
                run_case(playwright, port, run, case, args, first=index == 0)
            if args.engine == "chromium":
                check_without_query(playwright, port, run)
                check_verdict(playwright, port, run)
    finally:
        server.shutdown()
    (args.out / "phone_view.json").write_text(json.dumps({"rows": run.rows, "problems": run.problems}, indent=1))
    print(f"\n{len(run.problems)} problems")
    for line in run.problems:
        print("  ", line)
    return 0 if (args.no_fail or not run.problems) else 1


if __name__ == "__main__":
    sys.exit(main())
