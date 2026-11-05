"""What a phone's page really shows of the menu screens, in CSS pixels (issue #1197).

A phone is a touch screen with a pixel ratio of 3 that the page reports as at most 2, so an 844 x 390 CSS pixel page is
a canvas of 1688 x 780. This script loads the exported build in Chromium as a mobile device, walks the menu screens
(the five tabs, Play together, the solo Play screen, Settings and its tabs, Credits) and, on each, saves a screenshot and
the numbers the game publishes (`window.deadnight`, `WebProbe`): the page, the canvas, the content scale factor, the
canvas in units, the CSS pixels in one unit, and the smallest text and tap target in CSS pixels (`UiAudit`, asked for
by `window.deadnight_audit`). It fails on a screen with text under 14 CSS pixels or a target under 44.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/phone_layout.py <web folder> <out folder> \\
        [--label after] [--size 844x390] [--dpr 3] [--iframe] [--section tour,turn,night] [--no-fail]

`--iframe` shows the game in an iframe of another origin that fills the page, as Discord's client shows an Activity.
Sections: `tour` (the screens), `turn` (the page turned upright and back, and resized across the phone limit), `night`
(a solo night entered and left: does the menu's factor come back). What it cannot show: a real phone, a real iOS
Safari, Discord's own webview.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

PHONE_AGENT = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/156.0.0.0 Mobile Safari/537.36"
)
MIN_TEXT_PX = 14.0
MIN_TAP_PX = 44.0
# The game publishes its state every 0.25 s; a screen is read this long after it is shown.
SETTLE_MS = 1800
# Console errors so far, so a result says on which screen the first one came.
ERRORS: list[str] = []
TAB_NAMES = ["Play", "Loadout", "Shop", "Challenges", "More"]


def parse_size(text: str) -> dict:
    width, height = text.lower().split("x")
    return {"width": int(width), "height": int(height)}


def serve_parent(game_url: str) -> tuple[ThreadingHTTPServer, str]:
    """A page of another origin that shows the game full-screen in an iframe, as Discord's client shows an Activity."""
    html = (
        '<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">'
        '<body style="margin:0;background:#000">'
        f'<iframe src="{game_url}" allow="autoplay; gamepad" '
        'style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>'
    ).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, *_args) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}/"


class Frame:
    """The page or, with `--iframe`, the game's frame inside it: the probe lives in the frame."""

    def __init__(self, page: Page, frame) -> None:
        self.page = page
        self.frame = frame

    def state(self) -> dict:
        return self.frame.evaluate("() => window.deadnight ? Object.assign({}, window.deadnight) : {}") or {}


def parse_layout(text: str) -> dict:
    """`page_w,page_h|canvas_w,canvas_h|factor|units_w,units_h|css_per_unit` from the game."""
    if not text:
        return {}
    page, canvas, factor, units, per_unit = text.split("|")
    px, py = (float(n) for n in page.split(","))
    cw, ch = (int(n) for n in canvas.split(","))
    ux, uy = (float(n) for n in units.split(","))
    return {
        "page_css": [px, py],
        "canvas": [cw, ch],
        "factor": float(factor),
        "units": [ux, uy],
        "css_per_unit": float(per_unit),
    }


AUDIT = re.compile(r"^text (\S+) px \[(\d+)\] \((.*)\) tap (\S+) px \[(\d+)\] \((.*)\)$")


def parse_audit(text: str) -> dict:
    """`text 15.8 px [1] (a:13.2) tap 44.6 px [0] ()` from `UiAudit.summary`: the smallest, how many are under, names."""
    out: dict = {"raw": text}
    found = AUDIT.match(text)
    if not found:
        return out
    low_text, count_text, small_text, low_tap, count_tap, small_tap = found.groups()
    out["text_min"] = None if low_text == "-" else float(low_text)
    out["text_count"] = int(count_text)
    out["text_small"] = [s for s in small_text.split(",") if s]
    out["tap_min"] = None if low_tap == "-" else float(low_tap)
    out["tap_count"] = int(count_tap)
    out["tap_small"] = [s for s in small_tap.split(",") if s]
    return out


def snap(frame: Frame, out: Path, label: str, results: list[dict], what: str) -> dict:
    """Waits for the screen to settle, reads the game's numbers and saves a screenshot."""
    frame.page.wait_for_timeout(SETTLE_MS)
    state = frame.state()
    layout = parse_layout(str(state.get("layout", "")))
    audit = parse_audit(str(state.get("ui_audit", "")))
    inner = frame.frame.evaluate("() => [window.innerWidth, window.innerHeight, window.devicePixelRatio]")
    entry = {
        "what": what,
        "screen": state.get("screen"),
        "tab": state.get("tab"),
        "phone": state.get("phone"),
        "console_errors": len(ERRORS),
        "inner": inner,
        **layout,
        **{f"audit_{k}": v for k, v in audit.items()},
    }
    results.append(entry)
    frame.page.screenshot(path=out / f"{label}_{len(results):02d}_{what.replace(' ', '_').replace('/', '_')}.png")
    per = layout.get("css_per_unit", 0.0)
    print(
        f"{what:28s} screen={state.get('screen')} phone={state.get('phone')} page={layout.get('page_css')} "
        f"canvas={layout.get('canvas')} factor={layout.get('factor')} units={layout.get('units')} "
        f"css/unit={per:.3f}\n{'':28s} {audit.get('raw')}"
    )
    return entry


def press(frame: Frame, key: str) -> None:
    frame.page.keyboard.down(key)
    frame.page.wait_for_timeout(smoke.KEY_HOLD_MS)
    frame.page.keyboard.up(key)


def wait_for(frame: Frame, what: str, test, seconds: float) -> dict:
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = frame.state()
        if test(seen):
            return seen
        time.sleep(0.15)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def to_tab(frame: Frame, tab: str) -> None:
    for _ in range(len(TAB_NAMES)):
        if frame.state().get("tab") == tab:
            return
        before = frame.state().get("tab")
        press(frame, "e")
        frame.page.wait_for_timeout(500)
        wait_for(frame, "a tab change", lambda s, b=before: s.get("tab") != b, 20)
    raise TimeoutError(f"the menu never reached {tab}")


def go(frame: Frame, tab: str, steps: int, screen: str) -> None:
    """From the menu: the tab, `steps` of Down to the item, Enter, and wait for `screen`."""
    to_tab(frame, tab)
    frame.page.wait_for_timeout(500)
    for _ in range(steps):
        press(frame, "ArrowDown")
    press(frame, "Enter")
    wait_for(frame, screen, lambda s: s.get("screen") == screen, 40)


def back(frame: Frame) -> None:
    deadline = time.monotonic() + 40
    while frame.state().get("screen") != "main_menu" and time.monotonic() < deadline:
        press(frame, "Escape")
        frame.page.wait_for_timeout(1000)
    frame.page.wait_for_timeout(1200)


def tour(frame: Frame, out: Path, label: str, results: list[dict]) -> None:
    for tab in TAB_NAMES:
        to_tab(frame, tab)
        snap(frame, out, label, results, f"menu {tab}")
    to_tab(frame, "Play")
    go(frame, "Play", 0, "together_screen")
    if frame.state().get("naming"):
        snap(frame, out, label, results, "together name prompt")
        frame.page.keyboard.type("Alex", delay=40)
        press(frame, "Enter")
        frame.page.wait_for_timeout(1500)
    snap(frame, out, label, results, "together")
    back(frame)
    go(frame, "Play", 2, "play_screen")
    snap(frame, out, label, results, "play solo")
    back(frame)
    go(frame, "More", 0, "settings_screen")
    snap(frame, out, label, results, "settings tab 1")
    for index in range(2, 6):
        press(frame, "PageDown")
        snap(frame, out, label, results, f"settings tab {index}")
    back(frame)
    go(frame, "More", 1, "credits_screen")
    snap(frame, out, label, results, "credits")
    back(frame)


def turn(frame: Frame, out: Path, label: str, results: list[dict], size: dict) -> None:
    """The page turned upright and back, then resized across the limit and back: the factor must follow."""
    page = frame.page
    page.set_viewport_size({"width": size["height"], "height": size["width"]})
    snap(frame, out, label, results, "turned upright")
    page.set_viewport_size(size)
    snap(frame, out, label, results, "turned back")
    # A tablet's page: over the phone limit, so the layout is the desktop's.
    page.set_viewport_size({"width": 1024, "height": 768})
    snap(frame, out, label, results, "tablet 1024x768")
    page.set_viewport_size({"width": 932, "height": 430})
    snap(frame, out, label, results, "phone 932x430")
    page.set_viewport_size(size)
    snap(frame, out, label, results, "phone again")
    # With a screen over the menu: the resize happens while the menu is hidden.
    go(frame, "More", 0, "settings_screen")
    page.set_viewport_size({"width": 1024, "height": 768})
    snap(frame, out, label, results, "settings on a tablet page")
    page.set_viewport_size(size)
    snap(frame, out, label, results, "settings on a phone page again")
    back(frame)
    snap(frame, out, label, results, "menu after")


def night(frame: Frame, out: Path, label: str, results: list[dict]) -> None:
    """A solo night entered and left: what scale the night runs at and whether the menu's comes back."""
    to_tab(frame, "Play")
    snap(frame, out, label, results, "menu before the night")
    go(frame, "Play", 2, "play_screen")
    press(frame, "Enter")
    wait_for(frame, "a running night", lambda s: bool(s.get("night") and s.get("running")), smoke.NIGHT_LOAD_TIMEOUT_S)
    snap(frame, out, label, results, "in the night")
    press(frame, "Escape")
    frame.page.wait_for_timeout(1500)
    snap(frame, out, label, results, "night menu open")
    spots = {}
    for part in str(frame.state().get("menu_buttons", "")).split("|"):
        if ":" in part:
            name, at = part.rsplit(":", 1)
            spots[name] = [float(n) for n in at.split(",")]
    leave = spots.get("Leave night")
    if leave:
        size = frame.frame.evaluate("() => [window.innerWidth, window.innerHeight]")
        frame.page.mouse.click(leave[0] * size[0], leave[1] * size[1])
        # Leave night returns to the Play screen the night was started from.
        wait_for(frame, "the Play screen again", lambda s: s.get("screen") == "play_screen", 60)
        snap(frame, out, label, results, "play screen after the night")
        back(frame)
        snap(frame, out, label, results, "menu after the night")


def problems(results: list[dict]) -> list[str]:
    found = []
    for entry in results:
        if entry["what"].startswith(("in the night", "night menu", "turned upright", "together name")):
            continue
        low_text = entry.get("audit_text_min")
        low_tap = entry.get("audit_tap_min")
        if low_text is not None and low_text < MIN_TEXT_PX - 0.05:
            found.append(f"{entry['what']}: text {low_text} px {entry.get('audit_text_small')}")
        if low_tap is not None and low_tap < MIN_TAP_PX - 0.05:
            found.append(f"{entry['what']}: tap {low_tap} px {entry.get('audit_tap_small')}")
    return found


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--label", default="run")
    parser.add_argument("--size", default="844x390")
    parser.add_argument("--dpr", type=float, default=3.0)
    parser.add_argument("--iframe", action="store_true")
    parser.add_argument("--section", default="tour")
    parser.add_argument("--no-fail", action="store_true")
    parser.add_argument("--desktop", action="store_true", help="a desktop browser window: no touch, no mobile agent")
    parser.add_argument("--no-audit", action="store_true", help="leave the ruler off (the page does not ask for it)")
    parser.add_argument("--query", default="")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = smoke.serve(args.web)
    url = f"http://127.0.0.1:{port}/index.html?probe{('&' + args.query) if args.query else ''}"
    parent = None
    if args.iframe:
        parent, url = serve_parent(url)
    size = parse_size(args.size)
    results: list[dict] = []
    errors = ERRORS
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
            if args.desktop:
                context = browser.new_context(viewport=size, device_scale_factor=args.dpr)
            else:
                context = browser.new_context(
                    viewport=size, device_scale_factor=args.dpr, is_mobile=True, has_touch=True, user_agent=PHONE_AGENT
                )
            page = context.new_page()
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.add_init_script(
                f"window.deadnight_probe = true; window.deadnight_audit = {str(not args.no_audit).lower()};"
            )
            page.goto(url, wait_until="commit")
            if args.iframe:
                deadline = time.monotonic() + 60
                frame = None
                while time.monotonic() < deadline and frame is None:
                    for candidate in page.frames:
                        if candidate != page.main_frame:
                            frame = candidate
                    page.wait_for_timeout(200)
                assert frame is not None, "the iframe never loaded"
                game = Frame(page, frame)
                frame.evaluate(f"() => {{ window.deadnight_audit = {str(not args.no_audit).lower()}; }}")
            else:
                game = Frame(page, page.main_frame)
            smoke.wait_for(
                page if not args.iframe else _FramePage(page, game.frame),
                "the main menu",
                lambda s: s.get("screen") == "main_menu",
                smoke.LOAD_TIMEOUT_S,
            )
            if args.desktop:
                page.mouse.click(5, 5)
            else:
                page.touchscreen.tap(5, 5)
            page.wait_for_timeout(2500)
            sections = args.section.split(",")
            if "tour" in sections:
                tour(game, args.out, args.label, results)
            if "turn" in sections:
                turn(game, args.out, args.label, results, size)
            if "night" in sections:
                night(game, args.out, args.label, results)
            browser.close()
    finally:
        server.shutdown()
        if parent:
            parent.shutdown()
    (args.out / f"{args.label}.json").write_text(json.dumps({"results": results, "errors": errors}, indent=1))
    found = problems(results)
    print("\nconsole errors:", errors[:5] if errors else "none")
    print(f"{len(found)} floor problems")
    for line in found:
        print("  ", line)
    return 0 if (args.no_fail or not found) else 1


class _FramePage:
    """`smoke.wait_for` reads `page.evaluate`: with an iframe it reads the frame's."""

    def __init__(self, page: Page, frame) -> None:
        self._frame = frame
        self._page = page

    def evaluate(self, *args, **kwargs):
        return self._frame.evaluate(*args, **kwargs)

    def __getattr__(self, name: str):
        return getattr(self._page, name)


if __name__ == "__main__":
    sys.exit(main())
