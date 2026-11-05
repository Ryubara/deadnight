"""A phone taps a text field in the web build (issue #1183): does the keyboard come up, and does the field stay in view.

A phone is a touch screen with a pixel ratio of 3 and a user agent of its own. This script loads the exported build in
Chromium as a mobile device (844 x 390 CSS pixels, touch), walks to the Play together screen and taps the room code
field with a finger (a DevTools touch, never the person's mouse). Around the tap it records, from inside the page, every
`focus()` of an input or textarea with the event it ran in (`window.event`), and then checks:

1. an editable input has the browser's focus after the tap (an emulated browser draws no keyboard: this is the signal
   that makes a phone raise one), and the focus was made inside a tap's own events (`touchstart`, `touchend`,
   `pointerup`, `click`: iOS opens a keyboard only for those);
2. what is typed reaches the game's field (`insert_text`, the way a keyboard's input does);
3. with a keyboard up the field is drawn in the part of the page it leaves free (`--keyboard N` makes the keyboard N CSS
   pixels tall; `--mode visual` shrinks only the visual viewport, as Chrome and iOS do, `--mode resize` the layout
   viewport too, as a webview that resizes for the keyboard does) and a button pressed meanwhile still works;
4. after the keyboard closes the scene is back where it was, the page is not scrolled or zoomed and the canvas has the
   focus again;
5. the menu's More tab name field (and, with `--query dev`, the Join screen's address) does the same four things.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/phone_keyboard.py <web folder> <out folder> \\
        [--keyboard 220] [--mode visual|resize] [--size 844x390] [--embed plain|sandbox] [--engine chromium|webkit]

It prints one line per check and exits 1 when one fails. What it cannot show: a keyboard on a real phone, a real iOS
Safari (the WebKit Playwright ships is a desktop one), Discord's webview.
"""

from __future__ import annotations

import argparse
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import rooms
import smoke

PHONE_AGENT = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/156.0.0.0 Mobile Safari/537.36"
)
IPHONE_AGENT = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
    "Version/18.0 Mobile/15E148 Safari/604.1"
)
TAP_EVENTS = {"touchstart", "touchend", "pointerup", "pointerdown", "click", "mouseup"}
CODE = "abcd2345"
# The share of the page's height the Together card's rows end at (the card keeps a margin below its last row).
VISIBLE_SHARE = 0.9
# A spot no screen draws anything on, to tap when a tap must hit nothing: left of the card on the Together and Join
# screens, over the street scene of the menu. (40, 40) is the menu's Play tab since the phone layout (#1225).
EMPTY_SPOT = (40.0, 195.0)
# Where a drag can start and be on the scrolling area's own margin, not on a button or outside it: this share of the
# page's width from the left (the card's edge is at 18% of an 844 px page, its rows start at 23%, the area at 21%).
GRIP_SHARE = 0.217
# Wraps every input focus, so the run knows which event it came from. In `visual` mode the page reports a keyboard
# `window.__kbN` tall (`visualViewport` shrunk) while an input has the focus: Chromium's emulation draws none.
SPY = """
(() => {
  window.__kb = {focus: [], events: []};
  for (const name of ['touchstart', 'touchend', 'pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click']) {
    addEventListener(name, () => window.__kb.events.push([name, Math.round(performance.now())]), true);
  }
  const real = HTMLElement.prototype.focus;
  const editable = (el) => el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement;
  HTMLElement.prototype.focus = function (...args) {
    const out = real.apply(this, args);
    if (editable(this)) {
      window.__kb.focus.push({
        tag: this.tagName.toLowerCase(), t: Math.round(performance.now()),
        event: window.event ? window.event.type : '', active: document.activeElement === this,
        activation: navigator.userActivation ? navigator.userActivation.isActive : null,
      });
    }
    return out;
  };
  const visual = window.visualViewport;
  if (visual && window.__kbMode === 'visual') {
    window.__kbh = 0;
    Object.defineProperty(window, 'visualViewport', {value: new Proxy(visual, {
      get(target, key) {
        if (key === 'height') { return target.height - (window.__kbh || 0); }
        const value = target[key];
        return typeof value === 'function' ? value.bind(target) : value;
      },
    })});
    addEventListener('focusin', (e) => { if (editable(e.target)) { window.__kbh = window.__kbN; } }, true);
    addEventListener('focusout', (e) => {
      if (editable(e.target)) {
        setTimeout(() => { if (!editable(document.activeElement)) { window.__kbh = 0; } }, 50);
      }
    }, true);
  }
})();
"""
STATE = """
() => {
  const a = document.activeElement;
  const c = document.getElementById('canvas');
  const k = window.deadnightKeyboard;
  return {
    active: a ? a.tagName.toLowerCase() : '',
    editable: !!a && (a instanceof HTMLInputElement || a instanceof HTMLTextAreaElement) && !a.disabled && !a.readOnly,
    fontSize: a && a.tagName === 'INPUT' ? parseFloat(getComputedStyle(a).fontSize) : null,
    scale: window.visualViewport ? window.visualViewport.scale : 1,
    scroll: [window.scrollX, window.scrollY],
    canvasFocused: document.activeElement === c,
    layer: k ? {deferred: k.deferred, opened: k.opened, closed: k.closed} : null,
    focus: window.__kb.focus.slice(),
  };
}
"""


def parse_spots(text: str) -> dict[str, list[float]]:
    """`name:n,n,...|name:n,...` from the game's probe."""
    out = {}
    for part in filter(None, text.split("|")):
        name, numbers = part.rsplit(":", 1)
        out[name] = [float(n) for n in numbers.split(",")]
    return out


def css_box(page: Page, key: str, name: str) -> tuple[float, float, float, float]:
    """The box (left, top, width, height in CSS pixels) the game reports for `name` in its `key` list (a point for a
    button: its width and height are 0)."""
    spots = parse_spots(str(rooms.read_probe(page).get(key, "")))
    if name not in spots:
        raise TimeoutError(f"the game shows no {name!r} in {key}; it shows {sorted(spots)}")
    values = spots[name]
    if len(values) == 2:
        values = [*values, 0.0, 0.0]
    x, y, w, h = values
    width, height = page.evaluate("() => [window.innerWidth, window.innerHeight]")
    return (x - w / 2) * width, (y - h / 2) * height, w * width, h * height


def tap(page: Page, cdp, x: float, y: float) -> None:
    """A finger down and up on (x, y), through the DevTools protocol."""
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x, "y": y}]})
    page.wait_for_timeout(80)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})


def tap_box(page: Page, cdp, box: tuple[float, float, float, float]) -> None:
    tap(page, cdp, box[0] + box[2] / 2, box[1] + box[3] / 2)


def swipe_up(page: Page, cdp, x: float, y: float, distance: float, steps: int = 10) -> None:
    """A finger down at (x, y) that drags up by `distance` CSS pixels and lifts: what scrolls a card on a phone."""
    cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x, "y": y}]})
    for step in range(1, steps + 1):
        point = {"x": x, "y": y - distance * step / steps}
        cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [point]})
        page.wait_for_timeout(16)
    cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
    page.wait_for_timeout(600)


def scroll_into_view(page: Page, cdp, key: str, name: str) -> tuple[float, float, float, float]:
    """The box of `name` once it is on the screen. On a phone held sideways (390 CSS pixels) the Together card is taller
    than the page and its rows scroll (#980), so the code field can rest below the fold (since the server browser's
    note and button came above it, #1232): a player drags the card up until the field shows, and so does this, from
    the card's left margin (a button takes a drag that starts on it) and at most five times."""
    width, height = page.evaluate("() => [window.innerWidth, window.innerHeight]")
    for _ in range(5):
        box = css_box(page, key, name)
        if box[1] >= 0 and box[1] + box[3] <= height * VISIBLE_SHARE:
            return box
        swipe_up(page, cdp, width * GRIP_SHARE, height * 0.85, height * 0.5)
    box = css_box(page, key, name)
    if not (box[1] >= 0 and box[1] + box[3] <= height * VISIBLE_SHARE):
        raise TimeoutError(
            f"{name!r} is still off the screen after five swipes: {box[1]:.0f}..{box[1] + box[3]:.0f} px"
        )
    return box


class View:
    """The page a phone shows: the page itself, or its frame (the Activity is a cross-origin iframe), which is where
    `evaluate` runs; the mouse, the keyboard, the viewport and the screenshots are the page's."""

    def __init__(self, page: Page, frame=None) -> None:
        self._page = page
        self._frame = frame if frame is not None else page

    def evaluate(self, *args, **kwargs):
        return self._frame.evaluate(*args, **kwargs)

    def __getattr__(self, name: str):
        return getattr(self._page, name)


def serve_parent(game_url: str, sandbox: bool) -> tuple[ThreadingHTTPServer, str]:
    """A page of another origin (127.0.0.1 against the game's localhost) that shows the game full-screen in an iframe,
    as Discord's client shows an Activity; `sandbox` gives the frame the attribute set a webview may add."""
    attribute = ' sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-modals"' if sandbox else ""
    html = (
        '<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">'
        '<body style="margin:0;background:#000">'
        f'<iframe src="{game_url}" style="position:fixed;inset:0;width:100%;height:100%;border:0"{attribute}></iframe>'
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


class Checks:
    def __init__(self) -> None:
        self.failed: list[str] = []

    def __call__(self, ok: bool, what: str, detail: str = "") -> None:
        print(f"{'ok  ' if ok else 'FAIL'} {what}{(' (' + detail + ')') if detail else ''}")
        if not ok:
            self.failed.append(what)


def inside(box: tuple[float, float, float, float], top: float, bottom: float) -> bool:
    return box[1] >= top and box[1] + box[3] <= bottom


def key_point(page: Page, name: str) -> tuple[float, float]:
    box = css_box(page, "spots", name)
    return box[0], box[1]


def code_flow(page: Page, cdp, args, check: Checks, resting: tuple[float, float, float, float]) -> None:
    """The room code on a phone: a tap on the field opens the game's keypad (no system keyboard), the field is lifted
    above it, the keys type the code, Delete deletes and Join submits."""
    tap_box(page, cdp, resting)
    page.wait_for_timeout(1500)
    opened = page.evaluate(STATE)
    spots = parse_spots(str(rooms.read_probe(page).get("spots", "")))
    page.screenshot(path=args.out / "2_code_keypad.png")
    check(
        "1" in spots and "Delete" in spots, "a tap on the code field opens the keypad", f"keys on screen: {len(spots)}"
    )
    check(not opened["editable"], "no system keyboard is raised for the code", f"active={opened['active']}")
    now = css_box(page, "fields", "Code")
    one = key_point(page, "1")
    check(
        now[1] >= 0 and now[1] + now[3] <= one[1],
        "the field is drawn above the keypad",
        f"field {now[1]:.0f}..{now[1] + now[3]:.0f} px, the keypad's first row at {one[1]:.0f} px, resting {resting[1]:.0f}",
    )
    for letter in "ABCD2345":
        x, y = key_point(page, letter)
        tap(page, cdp, x, y)
        page.wait_for_timeout(150)
    page.wait_for_timeout(500)
    typed = rooms.read_probe(page).get("code_text")
    check(typed == CODE.upper(), "the keys type the code into the field", f"field holds {typed!r}")
    page.screenshot(path=args.out / "3_code_typed.png")
    x, y = key_point(page, "Delete")
    tap(page, cdp, x, y)
    page.wait_for_timeout(400)
    check(rooms.read_probe(page).get("code_text") == CODE.upper()[:-1], "Delete takes the last letter off")
    x, y = key_point(page, "5")
    tap(page, cdp, x, y)
    page.wait_for_timeout(400)
    still = rooms.read_probe(page)
    check(still.get("code_text") == CODE.upper(), "the field still has the focus after the keys (they take none)")
    x, y = key_point(page, "Join")
    tap(page, cdp, x, y)
    page.wait_for_timeout(1500)
    said = str(rooms.read_probe(page).get("room_status"))
    check(said != "", "the Join key submits the code", f"the screen says {said!r}")


def name_flow(page: Page, cdp, args, check: Checks, resized: dict, full: dict) -> None:
    """The player's name, which is a word and not a code, on the system keyboard: the prompt that Join opens has its
    field focused by the game; a tap on it must raise the keyboard from the finger's own event."""
    smoke.wait_for(page, "the name prompt", lambda _s: bool(rooms.read_probe(page).get("naming")), 30)
    page.wait_for_timeout(1200)
    # The game focuses the field itself (no tap): put that away, to start from the field at rest.
    tap(page, cdp, *EMPTY_SPOT)
    page.wait_for_timeout(1200)
    reset = page.evaluate("() => { window.__kb.focus = []; return 1; }")
    assert reset == 1
    rest = css_box(page, "fields", "PlayerName")
    tap_box(page, cdp, rest)
    if args.mode == "resize":
        page.set_viewport_size(resized)
    page.wait_for_timeout(1500)
    opened = page.evaluate(STATE)
    page.screenshot(path=args.out / "4_name_tapped.png")
    check(
        opened["editable"],
        "a tap on the name field gives an editable input the browser's focus",
        f"active={opened['active']}, focus() calls: {len(opened['focus'])}",
    )
    events = {f["event"] for f in opened["focus"]}
    check(
        bool(events & TAP_EVENTS),
        "a focus is made inside one of the tap's own events",
        f"events={sorted(events)} layer={opened['layer']}",
    )
    last = opened["focus"][-1] if opened["focus"] else {}
    check(last.get("active", False), "the last focus() of the tap holds")
    check(
        opened["fontSize"] is None or opened["fontSize"] >= 16,
        "the input's type is 16 px or more (iOS zooms the page for less)",
        f"font-size {opened['fontSize']}",
    )
    free_bottom = page.evaluate("() => window.innerHeight") - (args.keyboard if args.mode == "visual" else 0)
    now = css_box(page, "fields", "PlayerName")
    check(
        inside(now, 0, free_bottom),
        "the name field is drawn above the keyboard",
        f"field {now[1]:.0f}..{now[1] + now[3]:.0f} px, free to {free_bottom:.0f} px, resting {rest[1]:.0f}",
    )
    page.keyboard.insert_text("Alex")
    page.wait_for_timeout(800)
    page.screenshot(path=args.out / "5_name_typed.png")
    now = css_box(page, "fields", "PlayerName")
    check(inside(now, 0, free_bottom), "the field is still above the keyboard once typed in")
    if args.mode == "resize":
        page.set_viewport_size(full)
    tap(page, cdp, *EMPTY_SPOT)
    page.wait_for_timeout(1500)
    closed = page.evaluate(STATE)
    after = css_box(page, "fields", "PlayerName")
    check(not closed["editable"], "an empty tap closes the keyboard", f"active={closed['active']}")
    check(abs(after[1] - rest[1]) < 1.0, "the scene is back where it was", f"{after[1]:.1f} px, was {rest[1]:.1f}")
    check(
        closed["scroll"] == [0, 0] and abs(closed["scale"] - 1) < 0.01,
        "no scroll and no zoom left behind",
        f"scroll={closed['scroll']} scale={closed['scale']}",
    )
    check(closed["canvasFocused"], "the canvas has the focus again")
    page.screenshot(path=args.out / "6_closed.png")
    tap_box(page, cdp, rest)
    if args.mode == "resize":
        page.set_viewport_size(resized)
    page.wait_for_timeout(1500)
    again = page.evaluate(STATE)
    check(again["editable"], "a second tap raises the keyboard again", f"focus() calls: {len(again['focus'])}")
    page.keyboard.press("Enter")
    page.wait_for_timeout(1500)
    check(not rooms.read_probe(page).get("naming"), "Enter on the name field goes on")
    if args.mode == "resize":
        page.set_viewport_size(full)


def other_field(
    page: Page, cdp, args, check: Checks, name: str, label: str, typed: str, resized: dict, full: dict
) -> None:
    """A text field that is not the code or the name of a join: a tap raises the keyboard's input inside the tap's own
    event, the field is kept above the keyboard, typed text lands in the input, and an empty tap puts it all back."""
    # A screen may have focused its field itself (the Join screen does): start from the field at rest.
    tap(page, cdp, *EMPTY_SPOT)
    page.wait_for_timeout(1200)
    page.evaluate("() => { window.__kb.focus = []; return 1; }")
    rest = css_box(page, "fields", name)
    tap_box(page, cdp, rest)
    if args.mode == "resize":
        page.set_viewport_size(resized)
    page.wait_for_timeout(1500)
    opened = page.evaluate(STATE)
    page.screenshot(path=args.out / f"7_{label.split(':')[0].lower()}.png")
    events = {f["event"] for f in opened["focus"]}
    check(
        opened["editable"] and bool(events & TAP_EVENTS),
        f"{label}: a tap gives an editable input the browser's focus inside the tap's event",
        f"active={opened['active']}, events={sorted(events)}",
    )
    free_bottom = page.evaluate("() => window.innerHeight") - (args.keyboard if args.mode == "visual" else 0)
    now = css_box(page, "fields", name)
    check(
        inside(now, 0, free_bottom),
        f"{label}: the field is drawn above the keyboard",
        f"field {now[1]:.0f}..{now[1] + now[3]:.0f} px, free to {free_bottom:.0f} px, resting {rest[1]:.0f}",
    )
    page.keyboard.insert_text(typed)
    page.wait_for_timeout(500)
    value = page.evaluate("() => document.activeElement && document.activeElement.value")
    check(typed in str(value), f"{label}: typed text reaches the input", f"input holds {value!r}")
    if args.mode == "resize":
        page.set_viewport_size(full)
    tap(page, cdp, *EMPTY_SPOT)
    page.wait_for_timeout(1500)
    closed = page.evaluate(STATE)
    after = css_box(page, "fields", name)
    check(
        not closed["editable"] and abs(after[1] - rest[1]) < 1.0 and closed["scroll"] == [0, 0],
        f"{label}: an empty tap puts the keyboard and the scene back",
        f"active={closed['active']}, field {after[1]:.1f} px, was {rest[1]:.1f}",
    )


def more_flow(page: Page, cdp, args, check: Checks, resized: dict, full: dict) -> None:
    """The player's name in the menu's More tab."""
    smoke.back_to_menu(page)
    smoke.menu_item(page, "More")
    page.wait_for_timeout(1200)
    other_field(page, cdp, args, check, "PlayerName", "More: the name", "Bo", resized, full)


def join_flow(page: Page, cdp, args, check: Checks, resized: dict, full: dict) -> None:
    """The server address on the developers' Join screen (`--query dev`)."""
    smoke.back_to_menu(page)
    smoke.open_together(page)
    tap_box(page, cdp, scroll_into_view(page, cdp, "spots", "Server address (developers)"))
    smoke.wait_for(page, "the Join screen", lambda s: s.get("screen") == "join_screen", 30)
    page.wait_for_timeout(1500)
    other_field(page, cdp, args, check, "Address", "Join: the address", "x", resized, full)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path, help="the exported web folder")
    parser.add_argument("out", type=Path, help="where the captures go")
    parser.add_argument("--keyboard", type=int, default=220, help="CSS pixels a keyboard takes from the bottom")
    parser.add_argument("--mode", choices=["visual", "resize", "none"], default="visual")
    parser.add_argument("--engine", choices=["chromium", "webkit"], default="chromium")
    parser.add_argument("--dpr", type=float, default=3.0)
    parser.add_argument("--query", default="", help="more of the page's address, e.g. touch=1")
    parser.add_argument(
        "--embed",
        choices=["none", "plain", "sandbox"],
        default="none",
        help="show the game in an iframe of another origin, as Discord shows an Activity (sandbox: with a sandbox attribute)",
    )
    parser.add_argument(
        "--size", default="844x390", help="the page in CSS pixels, e.g. 390x844 for a phone held upright"
    )
    args = parser.parse_args()
    size = tuple(int(n) for n in args.size.split("x"))
    args.out.mkdir(parents=True, exist_ok=True)
    check = Checks()
    server, port = smoke.serve(args.web)
    problems: list[str] = []
    height = size[1] - args.keyboard
    resized = {"width": size[0], "height": height}
    full = {"width": size[0], "height": size[1]}
    try:
        with sync_playwright() as p:
            if args.engine == "chromium":
                browser = p.chromium.launch(args=smoke.SOFTWARE_GL + smoke.mute_args())
            else:
                browser = p.webkit.launch()
            context = browser.new_context(
                viewport={"width": size[0], "height": size[1]},
                device_scale_factor=args.dpr,
                has_touch=True,
                is_mobile=True,
                user_agent=PHONE_AGENT if args.engine == "chromium" else IPHONE_AGENT,
            )
            context.add_init_script(f"window.__kbMode = '{args.mode}'; window.__kbN = {args.keyboard};")
            context.add_init_script(SPY)
            page = context.new_page()
            page.on("pageerror", lambda e: problems.append(f"pageerror {e}"))
            page.on(
                "console", lambda m: problems.append(f"console {m.text}") if m.type in ("error", "warning") else None
            )
            extra = f"&{args.query}" if args.query else ""
            if args.embed == "none":
                page.goto(f"http://127.0.0.1:{port}/?probe{extra}", wait_until="commit")
                view = View(page)
            else:
                _parent, parent_url = serve_parent(f"http://localhost:{port}/?probe{extra}", args.embed == "sandbox")
                page.goto(parent_url, wait_until="commit")
                waited = time.monotonic()
                while len(page.frames) < 2:
                    if time.monotonic() - waited > 30:
                        raise SystemExit("the page around the game never showed its frame")
                    page.wait_for_timeout(200)
                view = View(page, page.frames[1])
            cdp = context.new_cdp_session(page)
            smoke.reach_menu(view)
            smoke.open_together(view)
            view.screenshot(path=args.out / "1_together.png")
            resting = scroll_into_view(view, cdp, "fields", "Code")
            code_flow(view, cdp, args, check, resting)
            name_flow(view, cdp, args, check, resized, full)
            more_flow(view, cdp, args, check, resized, full)
            if "dev" in args.query.split("&"):
                join_flow(view, cdp, args, check, resized, full)
            browser.close()
    finally:
        server.shutdown()
    if problems:
        print("page problems:", *problems[:8], sep="\n  ")
    print("all held" if not check.failed else "FAILED: " + "; ".join(check.failed))
    return 1 if check.failed else 0


if __name__ == "__main__":
    started = time.monotonic()
    code = main()
    print(f"({time.monotonic() - started:.0f} s)")
    sys.exit(code)
