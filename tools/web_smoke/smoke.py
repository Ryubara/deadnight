"""Browser smoke run of the Deadnight web export.

Serves the exported build, opens it in headless Chromium (Playwright), waits for the main menu, opens the
wardrobe and comes back, starts a night with the keyboard, plays it for a while, and fails on any console error,
page error or failed request. It also writes what it saw: screenshots, the load time, frame times, and the zombie
crowd the game reports through `window.deadnight` (game/core/web_probe.gd).

    uv run --with playwright==1.64.1 python tools/web_smoke/smoke.py build/web build/smoke

The first argument can also be a URL (https://...): the run then opens the deployed game instead of serving a folder,
and `load_to_menu_s` is the time over that connection.

Frame times depend on the machine: on a CI runner Chromium draws with a software renderer, so they are recorded,
never gated. Pass --gpu to leave Chromium's own GPU choice alone (a desktop with a graphics card).
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import statistics
import sys
import threading
import time
from pathlib import Path
from typing import ClassVar

from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

VIEWPORT = {"width": 1280, "height": 720}
LOAD_TIMEOUT_S = 150
SCREEN_TIMEOUT_S = 40
# Play builds the lot and warms up everything the night draws before it runs (docs/research/first-use-hitches.md):
# about 31 s in Chrome with a GPU, far more with a software renderer.
NIGHT_LOAD_TIMEOUT_S = 150
NIGHT_SECONDS = 45
WALK_LEG_S = 4.0
WALK_KEYS = ("w", "d", "s", "a")  # a square, so the player does not stand facing one wall
SAMPLE_SECONDS = 1.0
MENU_FRAME_SECONDS = 3.0
KEY_HOLD_MS = 150
# With --gpu --unpaced the page is not held to the display's refresh rate, so frame times show the GPU's work.
UNPACED = ["--disable-gpu-vsync", "--disable-frame-rate-limit"]
SOFTWARE_GL = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]

# Between pressing Play and a running night the game draws its lot and everything else once, behind a loading screen
# (docs/research/first-use-hitches.md). The browser builds a GL program the first time a kind of thing is drawn, on the
# main thread, so a frame that links many programs is a frame in which nothing moves: before the lot was drawn in
# pieces (#347) one frame linked 79 of them and took 9 s. The count is the same on every GPU and in a software
# renderer, which is why this is gated and a frame time is not. The pieces link at most 12 (a shader's two big
# programs and the few that go with them); the limit has room for a new kind of material, not for a new burst.
MAX_PROGRAMS_IN_A_LOADING_FRAME = 12

# Console errors that are about the browser, not the game, and are fine. Keep this list short and say why.
IGNORED: tuple[str, ...] = ()

# One mouse motion of `dx` pixels, sent to the canvas as the browser would while the pointer is locked (Godot's web
# runtime listens for `pointermove` on the window).
SYNTHETIC_MOUSE_MOVE_JS = """
(dx) => {
  const canvas = document.querySelector('canvas');
  const init = { movementX: dx, movementY: 0, bubbles: true, cancelable: true };
  canvas.dispatchEvent(new PointerEvent('pointermove', init));
}
"""

# Measures frame times in the page: requestAnimationFrame deltas for a number of seconds.
FRAME_TIMES_JS = """
(seconds) => new Promise((resolve) => {
  const deltas = [];
  let last = performance.now();
  const end = last + seconds * 1000;
  function frame(now) {
    deltas.push(now - last);
    last = now;
    if (now < end) requestAnimationFrame(frame); else resolve(deltas);
  }
  requestAnimationFrame(frame);
})
"""

# Counts the WebGL programs linked in each page frame (Godot links them inside its own frame callback, and this one
# runs once a frame), and keeps the frames that linked any or took over 100 ms: [time, programs, frame ms].
LINKS_PER_FRAME_JS = """
() => {
  window.__linkFrames = [];
  let count = 0;
  let last = performance.now();
  const link = WebGL2RenderingContext.prototype.linkProgram;
  WebGL2RenderingContext.prototype.linkProgram = function (program) {
    count += 1;
    return link.call(this, program);
  };
  function frame(now) {
    if (count > 0 || now - last > 100) window.__linkFrames.push([Math.round(now * 10) / 10, count, Math.round((now - last) * 10) / 10]);
    count = 0;
    last = now;
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
"""

PROBE_JS = """
() => {
  const d = window.deadnight;
  return d ? {screen: d.screen, night: d.night, running: d.running, over: d.over,
              round: d.round, remaining: d.remaining, alive: d.alive, yaw: d.yaw} : null;
}
"""

GL_JS = """
() => {
  const gl = document.createElement('canvas').getContext('webgl2');
  if (!gl) return 'no webgl2';
  const e = gl.getExtension('WEBGL_debug_renderer_info');
  return gl.getParameter(gl.VERSION) + ' | ' + (e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : 'n/a');
}
"""


class Quiet(http.server.SimpleHTTPRequestHandler):
    extensions_map: ClassVar[dict[str, str]] = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
    }

    def log_message(self, *_args) -> None:  # the run's own report is the log
        pass


def serve(folder: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    handler = functools.partial(Quiet, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def stats(deltas: list[float]) -> dict:
    ordered = sorted(deltas)
    return {
        "frames": len(ordered),
        "mean_ms": round(statistics.fmean(ordered), 1),
        "p50_ms": round(ordered[len(ordered) // 2], 1),
        "p95_ms": round(ordered[int(len(ordered) * 0.95)], 1),
        "max_ms": round(ordered[-1], 1),
    }


def probe(page: Page) -> dict:
    return page.evaluate(PROBE_JS) or {}


def press(page: Page, key: str) -> None:
    """A key held for a few frames: Godot reads input once per frame, and a tap shorter than that can be lost."""
    page.keyboard.down(key)
    page.wait_for_timeout(KEY_HOLD_MS)
    page.keyboard.up(key)


def wait_for(page: Page, what: str, test, seconds: float) -> dict:
    """Polls the game's probe until `test(probe)` is true; fails with the last thing it saw."""
    deadline = time.monotonic() + seconds
    seen: dict = {}
    while time.monotonic() < deadline:
        seen = probe(page)
        if test(seen):
            return seen
        time.sleep(0.1)
    raise TimeoutError(f"timed out waiting for {what}; the game last reported {seen}")


def main() -> int:
    args = parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"viewport": VIEWPORT, "night_samples": []}

    def on_console(message: ConsoleMessage) -> None:
        console.append(f"[{message.type}] {message.text}")
        if message.type == "error" and not any(text in message.text for text in IGNORED):
            problems.append(console[-1])

    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    with sync_playwright() as p:
        if args.gpu:  # the installed Chrome, which has the machine's GPU; the headless shell is always software
            flags = UNPACED if args.unpaced else []
            browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
        else:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
        page = browser.new_page(viewport=VIEWPORT)
        page.add_init_script("(" + LINKS_PER_FRAME_JS.strip() + ")();")
        page.on("console", on_console)
        page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
        page.on("requestfailed", lambda r: problems.append(f"[requestfailed] {r.url} {r.failure}"))
        page.on("response", lambda r: problems.append(f"[http {r.status}] {r.url}") if r.status >= 400 else None)
        try:
            run(page, url, out, result, args.night_seconds)
        except (TimeoutError, PlaywrightError) as error:
            problems.append(f"[run] {error}")
            try:
                page.screenshot(path=out / "failure.png")
            except PlaywrightError:
                pass
        finally:
            result["gl"] = gl_info(page)
            browser.close()
            if server:
                server.shutdown()

    burst = result.get("loading", {}).get("most_programs_in_a_frame", 0)
    if burst > MAX_PROGRAMS_IN_A_LOADING_FRAME:
        problems.append(
            f"[loading] a frame of the loading screen linked {burst} GL programs (at most "
            f"{MAX_PROGRAMS_IN_A_LOADING_FRAME}): the lot is drawn in too few pieces, so the page stops for seconds "
            "(docs/research/first-use-hitches.md)"
        )

    (out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["console_lines"] = len(console)
    result["problems"] = problems
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if problems:
        print(f"\nweb smoke FAILED with {len(problems)} problem(s):", file=sys.stderr)
        for line in problems:
            print("  " + line, file=sys.stderr)
        return 1
    print("\nweb smoke passed")
    return 0


def run(page: Page, url: str, out: Path, result: dict, night_seconds: float) -> None:
    started = time.monotonic()
    page.goto(url, wait_until="commit")
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    result["load_to_menu_s"] = round(time.monotonic() - started, 2)
    # The menu's items rise a moment after the screen arrives; a click gives the canvas the keyboard.
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)
    page.screenshot(path=out / "menu.png")
    result["menu_frames"] = stats(page.evaluate(FRAME_TIMES_JS, MENU_FRAME_SECONDS))

    # The wardrobe reads parts.json, which only reaches the build through the export filter. It is the
    # third item, after Play and Join.
    press(page, "ArrowDown")
    press(page, "ArrowDown")
    press(page, "Enter")
    wait_for(page, "the wardrobe", lambda s: s.get("screen") == "customize_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(2500)
    page.screenshot(path=out / "wardrobe.png")
    press(page, "Escape")
    wait_for(page, "the menu again", lambda s: s.get("screen") == "main_menu", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "menu_back.png")

    # Back on the menu nothing has focus until a key asks for it (that key is spent doing so); then Up walks
    # to the first item, Play (focus stops at the ends, so an Up too many is harmless).
    press(page, "ArrowDown")
    for _ in range(4):
        press(page, "ArrowUp")
    page.screenshot(path=out / "menu_focus.png")
    pressed = page.evaluate("performance.now()")
    press(page, "Enter")
    wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
    running = page.evaluate("performance.now()")
    result["loading"] = loading_report(page.evaluate("window.__linkFrames"), pressed, running)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "night.png")

    # The mouse turns the view: a full-screen control that catches the mouse once ate every motion
    # (desktop and web alike), and only a real browser run sees that.
    page.mouse.move(640, 360)
    page.wait_for_timeout(500)
    yaw_before = probe(page).get("yaw", 0.0)
    for step in range(1, 21):
        page.mouse.move(640 + step * 15, 360)
        page.wait_for_timeout(20)
    page.wait_for_timeout(600)
    yaw_after = probe(page).get("yaw", 0.0)
    result["mouse_look_via"] = "playwright mouse"
    if abs(yaw_after - yaw_before) < 0.1:
        # Chromium on Linux (the CI runner) answers every synthetic move under pointer lock with a motion and then
        # the opposite motion (+15 px, -15 px), which cancel; Windows does not. Send the motion as the page's own
        # mouse events instead: Godot reads them the same way, and a control eating the mouse still fails.
        yaw_before = probe(page).get("yaw", 0.0)
        for _ in range(20):
            page.evaluate(SYNTHETIC_MOUSE_MOVE_JS, 15)
            page.wait_for_timeout(20)
        page.wait_for_timeout(600)
        yaw_after = probe(page).get("yaw", 0.0)
        result["mouse_look_via"] = "page mouse events"
    result["mouse_look_turn_rad"] = round(abs(yaw_after - yaw_before), 3)
    if result["mouse_look_turn_rad"] < 0.1:
        lock = page.evaluate("() => document.pointerLockElement ? document.pointerLockElement.tagName : null")
        raise RuntimeError(
            f"moving the mouse did not turn the view (yaw {yaw_before} -> {yaw_after}, pointer lock {lock})"
        )

    # Walk a square and fire for the rest of the time, so the night is played, not only started.
    page.mouse.move(640, 360)
    page.mouse.down()
    began = time.monotonic()
    shots = 0
    crowd_sizes = (1, 5, 15)
    walking = ""
    while time.monotonic() - began < night_seconds:
        key = WALK_KEYS[int((time.monotonic() - began) / WALK_LEG_S) % len(WALK_KEYS)]
        if key != walking:
            if walking:
                page.keyboard.up(walking)
            page.keyboard.down(key)
            walking = key
        sample = {"t": round(time.monotonic() - began, 1), **probe(page)}
        sample["frames"] = stats(page.evaluate(FRAME_TIMES_JS, SAMPLE_SECONDS))
        result["night_samples"].append(sample)
        if shots < len(crowd_sizes) and sample.get("alive", 0) >= crowd_sizes[shots]:
            page.screenshot(path=out / f"night_crowd_{crowd_sizes[shots]}.png")
            shots += 1
        if sample.get("over"):
            break
    page.mouse.up()
    if walking:
        page.keyboard.up(walking)
    page.screenshot(path=out / "night_end.png")
    samples = result["night_samples"]
    result["night_peak_alive"] = max((s.get("alive", 0) for s in samples), default=0)
    result["night_worst_p95_ms"] = max((s["frames"]["p95_ms"] for s in samples), default=0)
    result["night_worst_frame_ms"] = max((s["frames"]["max_ms"] for s in samples), default=0)


def loading_report(frames: list[list[float]], pressed: float, running: float) -> dict:
    """What the loading screen cost between Play and a running night: its length, and the worst frames.

    `frames` is [time, programs linked, frame ms] for each page frame that linked a program or took over 100 ms."""
    during = [f for f in frames if pressed <= f[0] <= running]
    burst = max(during, key=lambda f: f[1], default=[0, 0, 0])
    longest = max(during, key=lambda f: f[2], default=[0, 0, 0])
    return {
        "seconds": round((running - pressed) / 1000, 2),
        "programs_linked": int(sum(f[1] for f in during)),
        "most_programs_in_a_frame": int(burst[1]),
        "longest_frame_ms": round(longest[2], 1),
        "frames_over_1s": sum(1 for f in during if f[2] > 1000),
    }


def gl_info(page: Page) -> str:
    try:
        return page.evaluate(GL_JS)
    except PlaywrightError:
        return "unknown"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or the URL of a deployed build")
    parser.add_argument("out", type=Path, help="folder for screenshots, console.txt and result.json")
    parser.add_argument("--night-seconds", type=float, default=NIGHT_SECONDS, help="how long to play the night")
    parser.add_argument("--gpu", action="store_true", help="use the machine's GPU instead of a software renderer")
    parser.add_argument("--unpaced", action="store_true", help="with --gpu: do not wait for the display's refresh")
    return parser.parse_args()


if __name__ == "__main__":
    sys.exit(main())
