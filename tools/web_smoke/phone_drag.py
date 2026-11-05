"""A drag that starts on a button scrolls a phone's card, and a tap still presses it (issue #1257).

Loads the exported build in Chromium as a phone (844 x 390 CSS pixels, pixel ratio 3, so the page reports 2 and the
canvas is 1688 x 780), makes a night of your own (the stand-in backend of `phone_layout.py` answers) and works on the
host's lobby, whose card scrolls and is mostly buttons. Every finger is a real touch event sent through the DevTools
protocol (`Input.dispatchTouchEvent`), which the engine's web runtime reads as `touchstart` / `touchmove` and turns into
touch events and the emulated mouse, as on a phone.

It measures, in CSS pixels:

- the card's scroll range (the lobby's Start button, read before and after a long drag from the margin);
- a drag of `DRAG_PX` from the card's margin (nothing under the finger: the control), then from each button (Start,
  Copy the link, Copy the code, Leave): how far the card moved, and whether any button was pressed;
- a tap on Start: it presses once and the card stays;
- the resting look: after a drag that scrolled the card from a button and lifted, the button is drawn as it is after a
  touch elsewhere, not hovered (the finger lifts over it, the content having moved with it);
- the resting look after a tap (issue #1268): the same measure after a tap on a button that stays on screen, for the
  buttons inside the card (Copy the link, Copy the code, Start) and for one outside any scroll area (the Play together
  screen's "Join with the code", reached by Leave); a lifted finger sends no mouse exit, so the engine kept the button
  lit until the next touch. With `--desktop` the same click keeps the hover (a mouse pointer stays over its button);
- a slip sweep: a finger that lands on Start and moves `slip` CSS pixels, then lifts on it. The press must survive a
  small slip and a slip past the threshold must scroll the card and give the press up.

`--desktop` runs the mouse and the wheel instead of a finger (no touch, a desktop agent): a press on a button still
presses it, a mouse drag across a button moves nothing, the wheel over a button scrolls the card.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 --with pillow python tools/web_smoke/phone_drag.py <web folder> <out folder> \\
        [--label after] [--desktop] [--no-fail]

Exits 1 when a drag from a button scrolls less than `MIN_SHARE` of what the same drag from the margin does, when a
button was pressed by a drag, when a tap or a slip under `PRESS_SLIP_PX` does not press, or when a slip over
`SCROLL_SLIP_PX` does not scroll. What it cannot show: a real phone's thumb, a real iOS Safari, Discord's webview.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import time
from pathlib import Path

from PIL import Image
from playwright.sync_api import CDPSession, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import phone_layout as layout
import smoke

SIZE = {"width": 844, "height": 390}
DPR = 3.0
# The drag every case makes, in CSS pixels, and how it is sent: a finger that moves at a steady, slow pace and holds
# still before it lifts, so the card has no speed left to coast on (`FLICK_*` is the fast one).
DRAG_PX = 40.0
DRAG_STEPS = 12
STEP_MS = 40
HOLD_MS = 300
FLICK_STEPS = 5
FLICK_STEP_MS = 16
# The margin at the card's left, where nothing is pressed (CSS pixels): the buttons begin at about x = 123.
MARGIN_X = 112.0
MARGIN_Y = 200.0
# A drag from a button must move the card by at least this share of what a drag from the margin moved it.
MIN_SHARE = 0.6
# The slip sweep (CSS pixels): under the first the press must survive, over the second the card must scroll.
SLIPS = [0.0, 3.0, 6.0, 8.0, 9.0, 12.0, 16.0, 24.0]
PRESS_SLIP_PX = 9.0
SCROLL_SLIP_PX = 12.0
SETTLE_MS = 1200
# The resting look: the colour of the button's fill is read left of its words (CSS pixels from its centre), and a
# button that is lit differs from its resting colour by more than this sum over the three channels (the grain of the
# fill and its gradient move it up to 23; a lit button is 68 or more away: measured 95, 68 and 81).
LOOK_OFFSET_PX = 110.0
LIT_DISTANCE = 40
# Where nothing is: a touch here puts every button back to what it is at rest (CSS pixels), outside any card.
EMPTY_SPOT = (20.0, 20.0)


class Phone:
    """The page, the touch it is sent through and the numbers it reads back."""

    def __init__(self, page: Page, game: layout.Frame, backend: layout.StubBackend, cdp: CDPSession | None) -> None:
        self.page = page
        self.game = game
        self.backend = backend
        self.cdp = cdp
        self.size = game.frame.evaluate("() => [window.innerWidth, window.innerHeight]")

    def spots(self) -> dict[str, tuple[float, float]]:
        """The named buttons of the screen, centres in CSS pixels."""
        found = {}
        for part in str(self.game.state().get("spots", "")).split("|"):
            if ":" in part:
                name, at = part.rsplit(":", 1)
                x, y = (float(n) for n in at.split(","))
                found[name] = (x * self.size[0], y * self.size[1])
        return found

    def at(self, name: str) -> tuple[float, float]:
        return self.spots()[name]

    def presses(self) -> int:
        """Presses of Start so far: the stand-in backend is told each time."""
        return sum(1 for call in self.backend.lobby_calls if call.startswith("POST /start"))

    def note(self) -> str:
        return str(self.game.state().get("lobby_note", ""))

    def touch(self, kind: str, x: float | None = None, y: float | None = None) -> None:
        points = [] if x is None else [{"x": x, "y": y, "id": 1}]
        self.cdp.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": points})

    def drag(self, start: tuple[float, float], dy: float, steps=DRAG_STEPS, step_ms=STEP_MS, hold_ms=HOLD_MS) -> None:
        """A finger down at `start`, `dy` CSS pixels down the page in `steps` equal steps, held, lifted."""
        x, y = start
        self.touch("touchStart", x, y)
        for step in range(1, steps + 1):
            self.page.wait_for_timeout(step_ms)
            self.touch("touchMove", x, y + dy * step / steps)
        self.page.wait_for_timeout(hold_ms)
        self.touch("touchEnd")
        self.page.wait_for_timeout(SETTLE_MS)

    def tap(self, at: tuple[float, float]) -> None:
        self.touch("touchStart", *at)
        self.page.wait_for_timeout(80)
        self.touch("touchEnd")
        self.page.wait_for_timeout(SETTLE_MS)

    def fill(self, name: str) -> tuple[int, int, int]:
        """The colour of `name`'s fill, read in a screenshot at a point left of its words."""
        x, y = self.at(name)
        image = Image.open(io.BytesIO(self.page.screenshot())).convert("RGB")
        scale = image.width / self.size[0]
        return image.getpixel((int((x - LOOK_OFFSET_PX) * scale), int(y * scale)))

    def look_after_tap(self, name: str, elsewhere: tuple[float, float], shot: Path | None = None) -> tuple:
        """The colour of `name`'s fill after a tap on it has finished, and at rest (after a touch at `elsewhere`)."""
        self.tap(self.at(name))
        lit = self.fill(name)
        if shot is not None:
            self.page.screenshot(path=shot)
        self.tap(elsewhere)
        return lit, self.fill(name)

    def card_y(self) -> float:
        """Where the Start button is: the card's scroll, read as a position."""
        return self.at("Start the night")[1]

    def to_the_foot(self) -> None:
        """The card scrolled to its end, as a drag up from the margin leaves it."""
        self.drag((MARGIN_X, MARGIN_Y), -300.0, steps=20, step_ms=30)

    def restore(self, target_y: float) -> None:
        """Puts the card back where Start was `target_y`, by a drag from the margin (nothing under the finger)."""
        gap = target_y - self.card_y()
        if abs(gap) > 1.0:
            self.drag((MARGIN_X, MARGIN_Y), gap, steps=12, step_ms=30)


def boot(play, browser, args, backend: layout.StubBackend, port: int) -> tuple[Phone, object]:
    desktop = args.desktop
    if desktop:
        context = browser.new_context(viewport=SIZE, device_scale_factor=1.0)
    else:
        context = browser.new_context(
            viewport=SIZE, device_scale_factor=DPR, is_mobile=True, has_touch=True, user_agent=layout.PHONE_AGENT
        )
    backend.attach(context)
    page = context.new_page()
    page.on("console", lambda m: layout.ERRORS.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: layout.ERRORS.append(str(e)))
    page.add_init_script("window.deadnight_probe = true; window.deadnight_audit = false;")
    page.goto(f"http://127.0.0.1:{port}/index.html?probe&backend={layout.STUB_BACKEND}", wait_until="commit")
    game = layout.Frame(page, page.main_frame)
    smoke.wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", smoke.LOAD_TIMEOUT_S)
    if desktop:
        page.mouse.click(5, 5)
    else:
        page.touchscreen.tap(5, 5)
    page.wait_for_timeout(2500)
    layout.to_tab(game, "Play")
    layout.open_create(game)
    layout.wait_for(game, "the name prompt or the lobby", lambda s: s.get("naming") or s.get("room_code"), 20)
    layout.together_name(game)
    layout.wait_for(game, "the lobby", lambda s: s.get("screen") == "lobby_screen" and s.get("room_code"), 60)
    page.wait_for_timeout(2500)
    cdp = None if desktop else context.new_cdp_session(page)
    return Phone(page, game, backend, cdp), context


def finger_cases(phone: Phone, out: Path, label: str, rows: list[dict]) -> list[str]:
    """The touch cases. Returns what went wrong, in words."""
    wrong: list[str] = []
    phone.page.screenshot(path=out / f"{label}_lobby_start.png")
    top = phone.card_y()
    phone.to_the_foot()
    foot = phone.card_y()
    reach = top - foot
    print(f"the card scrolls {reach:.0f} CSS px (Start at {top:.0f} on opening, {foot:.0f} at the foot)")
    rows.append({"case": "range", "css_px": reach})
    phone.restore(top)
    if reach < DRAG_PX:
        return [f"the card scrolls only {reach:.0f} px, less than a {DRAG_PX:.0f} px drag"]
    base_presses = phone.presses()
    # The control: the margin, then each button, all from the way the card opens, dragging up by DRAG_PX.
    moved: dict[str, float] = {}
    for name in ("margin", "Start the night", "Copy the link", "Copy the code", "Leave"):
        start = (MARGIN_X, MARGIN_Y) if name == "margin" else phone.at(name)
        before = phone.card_y()
        phone.drag(start, -DRAG_PX)
        shift = phone.card_y() - before
        moved[name] = shift
        pressed = phone.presses() - base_presses
        print(f"drag {DRAG_PX:.0f} px down from {name:16s}: the card moved {shift:6.1f} px, Start pressed {pressed}x")
        rows.append({"case": f"drag from {name}", "moved_css_px": shift, "start_presses": pressed})
        if name == "Start the night":
            phone.page.screenshot(path=out / f"{label}_after_drag_from_start.png")
        if name != "margin" and shift > MIN_SHARE * moved["margin"]:
            wrong.append(
                f"a drag from {name} moved the card {shift:.1f} px, the margin's moved it {moved['margin']:.1f}"
            )
        phone.restore(top)
    if phone.presses() != base_presses:
        wrong.append("a drag pressed Start")
    if phone.note():
        wrong.append(f"a drag pressed a copy button ({phone.note()!r})")
    # The resting look: a drag that scrolled the card from a button, lifted, leaves the button as a touch elsewhere does.
    for name in ("Start the night", "Copy the link", "Copy the code"):
        phone.drag(phone.at(name), -DRAG_PX)
        lifted = phone.fill(name)
        if name == "Start the night":
            phone.page.screenshot(path=out / f"{label}_resting_after_drag_from_start.png")
        phone.restore(top)
        phone.tap((MARGIN_X, MARGIN_Y))
        resting = phone.fill(name)
        distance = sum(abs(a - b) for a, b in zip(lifted, resting))
        print(f"look of {name:16s} after the lift {lifted}, at rest {resting}: {distance} apart")
        rows.append({"case": f"look {name}", "lifted": lifted, "resting": resting, "distance": distance})
        if distance > LIT_DISTANCE:
            wrong.append(f"{name} stays lit after a drag that scrolled the card from it (colour {distance} from rest)")
    # The resting look after a tap: the button stays on screen, the finger lifts over it and no mouse exit is sent.
    for name in ("Copy the link", "Copy the code", "Start the night"):
        slug = name.replace(" ", "_")
        shot = out / f"{label}_resting_after_tap_{slug}.png"
        lifted, resting = phone.look_after_tap(name, (MARGIN_X, MARGIN_Y), shot)
        distance = sum(abs(a - b) for a, b in zip(lifted, resting))
        print(f"look of {name:16s} after a tap {lifted}, at rest {resting}: {distance} apart (in the card)")
        rows.append({"case": f"tap look {name}", "lifted": lifted, "resting": resting, "distance": distance})
        if distance > LIT_DISTANCE:
            wrong.append(f"{name} stays lit after a tap (colour {distance} from rest)")
        phone.restore(top)
    # A flick: fast and released at once, so the card coasts.
    for name in ("margin", "Start the night"):
        start = (MARGIN_X, MARGIN_Y) if name == "margin" else phone.at(name)
        before = phone.card_y()
        phone.drag(start, -DRAG_PX, steps=FLICK_STEPS, step_ms=FLICK_STEP_MS, hold_ms=0)
        shift = phone.card_y() - before
        print(f"flick {DRAG_PX:.0f} px up from {name:16s}: the card moved {shift:6.1f} px")
        rows.append({"case": f"flick from {name}", "moved_css_px": shift})
        phone.restore(top)
    # A tap presses once and moves nothing.
    before, count = phone.card_y(), phone.presses()
    phone.tap(phone.at("Start the night"))
    after = phone.card_y()
    tapped = phone.presses() - count
    print(f"tap on Start: pressed {tapped}x, the card moved {after - before:.1f} px")
    rows.append({"case": "tap", "start_presses": tapped, "moved_css_px": after - before})
    if tapped != 1:
        wrong.append(f"a tap on Start pressed it {tapped} times")
    # The slip sweep: down on Start, moved `slip` CSS pixels (3 steps), lifted on it.
    print("a finger that lands on Start and moves `slip` px before it lifts:")
    for slip in SLIPS:
        before, count = phone.card_y(), phone.presses()
        phone.drag(phone.at("Start the night"), -slip, steps=3, step_ms=40, hold_ms=120)
        shift = phone.card_y() - before
        pressed = phone.presses() - count
        scrolled = abs(shift) > 1.0
        print(f"  slip {slip:5.1f} px: pressed {pressed}x, card moved {shift:6.1f} px")
        rows.append({"case": "slip", "slip_css_px": slip, "start_presses": pressed, "moved_css_px": shift})
        if slip <= PRESS_SLIP_PX and (pressed != 1 or scrolled):
            wrong.append(f"a slip of {slip} px: pressed {pressed}x, moved {shift:.1f} px (it must press, not scroll)")
        if slip >= SCROLL_SLIP_PX and (pressed != 0 or not scrolled):
            wrong.append(f"a slip of {slip} px: pressed {pressed}x, moved {shift:.1f} px (it must scroll, not press)")
        phone.restore(top)
    phone.page.screenshot(path=out / f"{label}_lobby_end.png")
    wrong += outside_cases(phone, out, label, rows)
    return wrong


def outside_cases(phone: Phone, out: Path, label: str, rows: list[dict]) -> list[str]:
    """A tap on a button that sits in no scroll area: Leave goes back to the Play together screen, whose "Join with
    the code" answers a tap without a code by staying where it is."""
    phone.tap(phone.at("Leave"))
    layout.wait_for(phone.game, "the Play together screen", lambda s: s.get("screen") == "together_screen", 20)
    phone.page.wait_for_timeout(1500)
    name = "Join with the code"
    shot = out / f"{label}_resting_after_tap_outside_a_card.png"
    lifted, resting = phone.look_after_tap(name, EMPTY_SPOT, shot)
    distance = sum(abs(a - b) for a, b in zip(lifted, resting))
    print(f"look of {name:18s} after a tap {lifted}, at rest {resting}: {distance} apart (outside a card)")
    rows.append({"case": f"tap look outside {name}", "lifted": lifted, "resting": resting, "distance": distance})
    if distance > LIT_DISTANCE:
        return [f"{name} (outside a card) stays lit after a tap (colour {distance} from rest)"]
    return []


def mouse_cases(phone: Phone, out: Path, label: str, rows: list[dict]) -> list[str]:
    """A desktop's mouse and wheel over the same card."""
    wrong: list[str] = []
    page = phone.page
    base = phone.presses()
    before = phone.card_y()
    x, y = phone.at("Start the night")
    page.mouse.move(x, y)
    page.mouse.down()
    for step in range(1, 7):
        page.mouse.move(x, y - 12.0 * step)
        page.wait_for_timeout(40)
    page.mouse.up()
    page.wait_for_timeout(SETTLE_MS)
    drag_moved = phone.card_y() - before
    drag_pressed = phone.presses() - base
    print(f"mouse drag 72 px up from Start: the card moved {drag_moved:.1f} px, Start pressed {drag_pressed}x")
    rows.append({"case": "mouse drag", "moved_css_px": drag_moved, "start_presses": drag_pressed})
    if abs(drag_moved) > 1.0 or drag_pressed:
        wrong.append(f"a mouse drag from Start moved the card {drag_moved:.1f} px and pressed it {drag_pressed}x")
    x, y = phone.at("Start the night")
    page.mouse.click(x, y)
    page.wait_for_timeout(SETTLE_MS)
    clicked = phone.presses() - base - drag_pressed
    print(f"mouse click on Start: pressed {clicked}x")
    rows.append({"case": "mouse click", "start_presses": clicked})
    if clicked != 1:
        wrong.append(f"a click on Start pressed it {clicked} times")
    before = phone.card_y()
    page.mouse.move(*phone.at("Start the night"))
    page.mouse.wheel(0, 120)
    page.wait_for_timeout(SETTLE_MS)
    wheel_moved = phone.card_y() - before
    print(f"wheel 120 over Start: the card moved {wheel_moved:.1f} px")
    rows.append({"case": "wheel", "moved_css_px": wheel_moved})
    if abs(wheel_moved) < 1.0:
        wrong.append("the wheel over Start did not scroll the card")
    # A click leaves a mouse pointer over its button, which stays hovered (lit): the look is not taken away.
    name = "Copy the link"
    page.mouse.move(*phone.at(name))
    page.mouse.click(*phone.at(name))
    page.wait_for_timeout(SETTLE_MS)
    held = phone.fill(name)
    page.mouse.move(MARGIN_X, MARGIN_Y)
    page.wait_for_timeout(SETTLE_MS)
    resting = phone.fill(name)
    distance = sum(abs(a - b) for a, b in zip(held, resting))
    print(f"look of {name:16s} after a click {held}, at rest {resting}: {distance} apart (the mouse still over it)")
    rows.append({"case": f"click look {name}", "held": held, "resting": resting, "distance": distance})
    if distance <= LIT_DISTANCE:
        wrong.append(f"{name} lost its hover after a mouse click (colour {distance} from rest)")
    page.screenshot(path=out / f"{label}_desktop_end.png")
    return wrong


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--label", default="run")
    parser.add_argument("--desktop", action="store_true", help="a mouse and a wheel, no touch")
    parser.add_argument("--no-fail", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = smoke.serve(args.web)
    backend = layout.StubBackend()
    rows: list[dict] = []
    started = time.monotonic()
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(channel="chrome", headless=True, args=[*smoke.mute_args()])
            phone, _context = boot(p, browser, args, backend, port)
            wrong = (mouse_cases if args.desktop else finger_cases)(phone, args.out, args.label, rows)
            browser.close()
    finally:
        server.shutdown()
    (args.out / f"{args.label}_{'desktop' if args.desktop else 'touch'}.json").write_text(
        json.dumps({"rows": rows, "wrong": wrong, "errors": layout.ERRORS}, indent=1)
    )
    print(
        f"\n{len(wrong)} problems in {time.monotonic() - started:.0f} s; console errors: {layout.ERRORS[:3] or 'none'}"
    )
    for line in wrong:
        print("  ", line)
    return 0 if (args.no_fail or not wrong) else 1


if __name__ == "__main__":
    sys.exit(main())
