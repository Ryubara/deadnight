"""Browser smoke run of the Deadnight web export.

Serves the exported build, opens it in headless Chromium (Playwright), waits for the main menu, opens the
wardrobe and comes back, starts a night with the keyboard, plays it for a while, and fails on any console error,
page error or failed request. It also writes what it saw: screenshots, the load time, frame times, and the zombie
crowd the game reports through `window.deadnight` (game/core/web_probe.gd).

    uv run --project <kit>/python gds quiet -- \\
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
import os
import statistics
import sys
import threading
import time
from pathlib import Path
from typing import ClassVar

from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

# The scripts beside this one are on the path whether smoke.py runs as a script or another script imports it.
sys.path.insert(0, str(Path(__file__).parent))
from night_load import night_load_problems

VIEWPORT = {"width": 1280, "height": 720}
LOAD_TIMEOUT_S = 150
SCREEN_TIMEOUT_S = 40
# Play builds the lot and warms up everything the night draws before it runs (docs/research/first-use-hitches.md):
# about 31 s in Chrome with a GPU, far more with a software renderer: on the CI runners it took 82 s to 107 s, and one
# slower runner (the menu itself took 16 s, not 9 s to 13 s) was still at 83 % of the loading bar at 150 s.
NIGHT_LOAD_TIMEOUT_S = 300
NIGHT_SECONDS = 45
WALK_LEG_S = 4.0
WALK_KEYS = ("w", "d", "s", "a")  # a square, so the player does not stand facing one wall
SAMPLE_SECONDS = 1.0
MENU_FRAME_SECONDS = 3.0
# The idle menu is followed for this many seconds more, counting what the engine asks of WebGL in each frame (#989).
MENU_TRACE_SECONDS = 9.0
KEY_HOLD_MS = 150
# The game publishes its state every 0.25 s: a key pressed shows in `window.deadnight` within that.
FOCUS_PUBLISH_MS = 400
# Presses `focus_control` makes at most; a screen has fewer controls than this in a column.
FOCUS_TRIES = 14
# With --gpu --unpaced the page is not held to the display's refresh rate, so frame times show the GPU's work.
UNPACED = ["--disable-gpu-vsync", "--disable-frame-rate-limit"]
SOFTWARE_GL = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
# A probe never listens (the page reports numbers through `window.deadnight`). Playwright's headless Chromium is
# already muted; a headed one, and Firefox, are not. `gds quiet` sets GDS_QUIET=1 for everything it runs, and then every
# launch adds these (docs/godot/no-focus.md in the kit, "Sound").
MUTE_CHROMIUM = ["--mute-audio"]
MUTE_FIREFOX = {"media.volume_scale": "0.0"}


def quiet() -> bool:
    """True under `gds quiet` (GDS_QUIET=1): the probe must not use the person's keyboard, mouse or speakers."""
    return os.environ.get("GDS_QUIET") == "1"


def mute_args() -> list[str]:
    """Chromium arguments that silence a launch under `gds quiet`; add them to every `chromium.launch(args=...)`."""
    return MUTE_CHROMIUM if quiet() else []


def mute_firefox_prefs() -> dict[str, str]:
    """Firefox preferences that silence a launch under `gds quiet`, for `firefox.launch(firefox_user_prefs=...)`."""
    return MUTE_FIREFOX if quiet() else {}


# Between pressing Play and a running night the game draws its lot and everything else once, behind a loading screen
# (docs/research/first-use-hitches.md). The browser builds a GL program the first time a kind of thing is drawn, on the
# main thread, so a frame that links many programs is a frame in which nothing moves: before the lot was drawn in
# pieces (#347) one frame linked 79 of them and took 9 s. The count is the same on every GPU and in a software
# renderer, which is why this is gated and a frame time is not. The pieces link at most 12 (a shader's two big
# programs and the few that go with them); the limit has room for a new kind of material, not for a new burst.
MAX_PROGRAMS_IN_A_LOADING_FRAME = 12
# Tabs in the menu's bar: Q and E walk them, wrapping round.
MENU_TABS = 5

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

# The WebGL calls counted in each page frame by TRACE_JS: the name of the counter and the methods it adds up.
COUNTED_GL_CALLS = {
    "draws": ["drawArrays", "drawElements", "drawArraysInstanced", "drawElementsInstanced", "drawRangeElements"],
    "clears": ["clear", "clearBufferfv", "clearBufferiv", "clearBufferuiv", "clearBufferfi"],
    "blits": ["blitFramebuffer"],
    "fbo_binds": ["bindFramebuffer"],
    "programs": ["useProgram"],
    "uploads": ["texImage2D", "texSubImage2D", "bufferData", "bufferSubData", "texStorage2D"],
}

# Follows `seconds` of page frames and counts, in each, the WebGL calls of COUNTED_GL_CALLS. The calls are wrapped for
# this time only and put back after it (a wrapper on every draw of the night would slow the night the gate times):
# [{names, rows: [[ms since the start, ms since the frame before, ...a count for each name]]}.
TRACE_JS = """
([seconds, counted]) => new Promise((resolve) => {
  const proto = WebGL2RenderingContext.prototype;
  const names = Object.keys(counted);
  const now = {};
  const originals = [];
  for (const name of names) {
    now[name] = 0;
    for (const method of counted[name]) {
      const original = proto[method];
      if (!original) continue;
      originals.push([method, original]);
      proto[method] = function (...args) {
        now[name] += 1;
        return original.apply(this, args);
      };
    }
  }
  const rows = [];
  const origin = performance.now();
  let last = origin;
  function frame(at) {
    rows.push([at - origin, at - last, ...names.map((name) => now[name])]);
    for (const name of names) now[name] = 0;
    last = at;
    if (at - origin < seconds * 1000) {
      requestAnimationFrame(frame);
    } else {
      for (const [method, original] of originals) proto[method] = original;
      resolve({names, rows});
    }
  }
  requestAnimationFrame(frame);
})
"""

PROBE_JS = """
() => {
  const d = window.deadnight;
  return d ? {screen: d.screen, night: d.night, running: d.running, over: d.over,
              round: d.round, remaining: d.remaining, alive: d.alive, yaw: d.yaw,
              interpolated: d.interpolated, tab: d.tab, stage: d.stage, quick_join: d.quick_join} : null;
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


# What a served page gets first in its head so the game adds its probes (`WebProbe.asked` reads `window.deadnight_probe`).
PROBES_ON = b"<script>window.deadnight_probe=true</script>"


class Quiet(http.server.SimpleHTTPRequestHandler):
    extensions_map: ClassVar[dict[str, str]] = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
    }
    # A player's page publishes nothing to `window.deadnight` (no snapshot, no probes: #983), so a test that reads it
    # is served the page with the probes asked for. `serve(folder, probing=False)` serves the page a player opens.
    probing: ClassVar[bool] = True

    def log_message(self, *_args) -> None:  # the run's own report is the log
        pass

    def do_GET(self) -> None:
        if self.probing and self.path.split("?")[0] in ("/", "/index.html"):
            html = Path(self.directory, "index.html").read_bytes().replace(b"<head>", b"<head>" + PROBES_ON, 1)
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            return
        super().do_GET()


def serve(folder: Path, probing: bool = True) -> tuple[http.server.ThreadingHTTPServer, int]:
    """Serves the export on a free port. With `probing` (the default) the page is served with the probes asked for;
    pass False to open the page a player opens (`bridge_calls.py`, `heap_soak.py --plain`)."""
    kind = Quiet if probing else type("PlainQuiet", (Quiet,), {"probing": False})
    handler = functools.partial(kind, directory=str(folder))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1]


def machine_info() -> dict:
    """What the runner is, beside the frame times it produced (#989): the cores the run may use, the CPU model and the
    load average. The same software renderer is much slower on a machine with fewer or slower cores, and the model
    tells the runner pools apart, so a run's idle frames can be read against its own machine."""
    info: dict = {"cpus": os.cpu_count()}
    if hasattr(os, "sched_getaffinity"):
        info["usable_cpus"] = len(os.sched_getaffinity(0))
    if hasattr(os, "getloadavg"):
        info["loadavg"] = [round(x, 2) for x in os.getloadavg()]
    try:
        for line in Path("/proc/cpuinfo").read_text(encoding="utf-8").splitlines():
            if line.startswith("model name"):
                info["cpu_model"] = line.split(":", 1)[1].strip()
                break
    except OSError:
        pass
    return info


def stats(deltas: list[float]) -> dict:
    ordered = sorted(deltas)
    return {
        "frames": len(ordered),
        "mean_ms": round(statistics.fmean(ordered), 1),
        "p50_ms": round(ordered[len(ordered) // 2], 1),
        "p95_ms": round(ordered[int(len(ordered) * 0.95)], 1),
        "max_ms": round(ordered[-1], 1),
    }


def trace(page: Page, seconds: float) -> dict:
    """Follows the page for `seconds` and reports the frame time second by second and, per frame, how many WebGL calls
    of each kind the engine made. The counts do not depend on the machine, so a slower run with the same counts is a
    slower runner, and a run with other counts drew something else (docs/research/web-export.md, "The idle menu")."""
    recorded = page.evaluate(TRACE_JS, [seconds, COUNTED_GL_CALLS])
    return summarise_trace(recorded["names"], recorded["rows"], seconds)


def summarise_trace(names: list[str], rows: list[list[float]], seconds: float) -> dict:
    seconds_mean_ms = []
    for start in range(int(seconds)):
        part = [row[1] for row in rows if start * 1000 <= row[0] < (start + 1) * 1000]
        seconds_mean_ms.append(round(statistics.fmean(part), 1) if part else None)
    per_frame = {
        name: {
            "mean": round(statistics.fmean(row[2 + i] for row in rows), 1),
            "min": min(row[2 + i] for row in rows),
            "max": max(row[2 + i] for row in rows),
        }
        for i, name in enumerate(names)
    }
    return {"frames": len(rows), "mean_ms_each_second": seconds_mean_ms, "gl_calls_per_frame": per_frame}


def probing(url: str) -> str:
    """`url` with `probe` in its query: the page then adds the probes that cross the JavaScript bridge in every frame
    (judder, view and pad: `WebProbe.asked`, game/core/web_probe.gd). A player's page has none of them, so a probe that
    reads `viewRows`, `frames`, `pad_count` or `pause_presses` opens its page through this (#935)."""
    return f"{url}{'&' if '?' in url else '?'}probe"


def probe(page: Page) -> dict:
    return page.evaluate(PROBE_JS) or {}


def give_level(page: Page, level: int) -> None:
    """Makes the game think the player is level `level` (`PlayerLevel`, which a page that asks for the probes reads
    from `window.deadnight_player_level`): a fresh page has no profile, so the back rooms (level 10) are locked.
    Call it before the page is opened."""
    page.add_init_script(f"window.deadnight_probe = true; window.deadnight_player_level = {int(level)};")


def give_name(page: Page, name: str, seconds: float = 60.0) -> None:
    """Answers the Play together name prompt, which a player with no saved name gets before signing in."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if page.evaluate("() => window.deadnight ? window.deadnight.naming : false"):
            page.wait_for_timeout(500)  # the field takes the keyboard a frame after it shows
            page.keyboard.type(name, delay=40)
            press(page, "Enter")
            return
        page.wait_for_timeout(250)
    raise TimeoutError("the name prompt never showed")


def press(page: Page, key: str) -> None:
    """A key held for a few frames: Godot reads input once per frame, and a tap shorter than that can be lost."""
    page.keyboard.down(key)
    page.wait_for_timeout(KEY_HOLD_MS)
    page.keyboard.up(key)


def focused_control(page: Page) -> str:
    """The name of the control that has the keyboard, as the game publishes it (`window.deadnight.focus`, the control's
    own name or its nearest named parent's). Waits one publish first, so a key pressed just before has been seen."""
    page.wait_for_timeout(FOCUS_PUBLISH_MS)
    return str(page.evaluate("() => (window.deadnight ? window.deadnight.focus : '')") or "")


def focus_control(page: Page, wanted: str, key: str, tries: int = FOCUS_TRIES) -> None:
    """Presses `key` (an arrow) until the control called `wanted` has the keyboard, never counting presses: a control
    added to the screen only makes the walk one press longer. Fails after `tries` presses naming the wanted control,
    the one reached, and every control passed on the way (#743)."""
    seen = [focused_control(page)]
    for _ in range(tries):
        if seen[-1] == wanted:
            return
        press(page, key)
        seen.append(focused_control(page))
    if seen[-1] != wanted:
        raise TimeoutError(
            f"the keyboard never reached {wanted!r} with {key} in {tries} presses; it reached {seen[-1]!r} "
            f"(passed: {' > '.join(seen)})"
        )


def step_value(page: Page, wanted: str, key: str, times: int) -> None:
    """Presses `key` `times` times on the control called `wanted`, which must have the keyboard before and after (a
    value key that moved the focus to another control would set the wrong setting)."""
    for when in ("before", "after"):
        if when == "after":
            for _ in range(times):
                press(page, key)
        reached = focused_control(page)
        if reached != wanted:
            raise TimeoutError(
                f"{times} presses of {key} were meant for {wanted!r}; the keyboard was on {reached!r} {when}"
            )


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


def menu_item(page: Page, tab: str, steps: int = 0) -> None:
    """Puts the keyboard on an item of the main menu: the tab bar's Q and E walk (and wrap) to `tab`, and the focus lands
    on the tab's first control whatever it was before, so `steps` presses of Down reach the item. It works from
    any focus, which the old menu needed six Up presses for. Play's items are Play together, Quick join and Solo;
    More's are Settings, Credits and Quit."""
    for _ in range(MENU_TABS):
        page.wait_for_timeout(400)  # longer than the probe's period, so `before` is the tab on show
        before = probe(page).get("tab")
        press(page, "e")
        # The game publishes its state a few times a second: wait for the new tab, never read the old one twice.
        now = wait_for(page, "the next tab", lambda s, was=before: s.get("tab") != was, SCREEN_TIMEOUT_S)
        if now.get("tab") == tab:
            break
    else:
        raise TimeoutError(f"the menu never reached the {tab} tab; it reports {probe(page)}")
    for _ in range(steps):
        press(page, "ArrowDown")


def reach_menu(page: Page) -> None:
    """The page is loading: waits for the main menu, clicks the canvas (that gives it the keyboard) and lets the menu
    settle."""
    wait_for(page, "the main menu", lambda s: s.get("screen") == "main_menu", LOAD_TIMEOUT_S)
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)


def back_to_menu(page: Page) -> None:
    """Escape until the menu is the screen again (a screen opened by mistake, a key lost on the way)."""
    deadline = time.monotonic() + SCREEN_TIMEOUT_S
    while probe(page).get("screen") != "main_menu" and time.monotonic() < deadline:
        press(page, "Escape")
        page.wait_for_timeout(1000)
    page.wait_for_timeout(1500)


def open_together(page: Page) -> None:
    """From the main menu to the Play together screen (the first item of the Play tab)."""
    menu_item(page, "Play")
    press(page, "Enter")
    wait_for(page, "the Play together screen", lambda s: s.get("screen") == "together_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)


def open_settings(page: Page) -> None:
    """From the main menu to the settings screen (the first item of the More tab)."""
    menu_item(page, "More")
    press(page, "Enter")
    wait_for(page, "settings", lambda s: s.get("screen") == "settings_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)


def start_solo(page: Page) -> None:
    """Presses Solo on the Play tab, then Start the night on the Play screen it opens (the match settings, left on
    the usual rules; its Start button has the focus): the one way to start a night alone. Every probe that needs a
    night starts it here, so a change to the menu is one edit and `startup_check.py` (the web job) fails on it."""
    menu_item(page, "Play", 2)
    press(page, "Enter")
    wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    press(page, "Enter")


def wait_for_night(page: Page, seconds: float = NIGHT_LOAD_TIMEOUT_S) -> dict:
    return wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), seconds)


def main() -> int:
    args = parse_args()
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"viewport": VIEWPORT, "machine": machine_info(), "night_samples": []}

    def on_console(message: ConsoleMessage) -> None:
        console.append(f"[{message.type}] {message.text}")
        if message.type == "error" and not any(text in message.text for text in IGNORED):
            problems.append(console[-1])

    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else serve(Path(args.build))
    url = probing(args.build) if deployed else f"http://127.0.0.1:{port}/index.html"
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

    if not args.gpu and result.get("stage_level") not in (None, "still"):
        problems.append(
            f"[stage] the menu's stage is {result['stage_level']} on a software renderer: it should start as a still"
        )

    burst = result.get("loading", {}).get("most_programs_in_a_frame", 0)
    if burst > MAX_PROGRAMS_IN_A_LOADING_FRAME:
        problems.append(
            f"[loading] a frame of the loading screen linked {burst} GL programs (at most "
            f"{MAX_PROGRAMS_IN_A_LOADING_FRAME}): the lot is drawn in too few pieces, so the page stops for seconds "
            "(docs/research/first-use-hitches.md)"
        )

    problems.extend(night_load_problems(result, args.gpu, deployed))

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
    # The menu's panel arrives a moment after the screen does; a click gives the canvas the keyboard.
    page.mouse.click(5, 5)
    page.wait_for_timeout(2500)
    # The menu's 3D stage: a still on a renderer that draws on the CPU, live with a GPU.
    result["stage_level"] = probe(page).get("stage")
    page.screenshot(path=out / "menu.png")
    result["menu_frames"] = stats(page.evaluate(FRAME_TIMES_JS, MENU_FRAME_SECONDS))
    # What follows the three seconds the gate reads: a longer trace and what the engine draws in a frame (#989).
    result["menu_trace"] = trace(page, MENU_TRACE_SECONDS)

    # The wardrobe (the Loadout tab) reads parts.json, which only reaches the build through the export filter.
    menu_item(page, "Loadout")
    page.wait_for_timeout(2500)
    page.screenshot(path=out / "wardrobe.png")
    menu_item(page, "Play")
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "menu_back.png")

    # Solo is the third item of the Play tab.
    menu_item(page, "Play", 2)
    page.screenshot(path=out / "menu_focus.png")
    press(page, "Enter")
    # Solo opens the Play screen (the match settings, as a room's host has them); Start the night has the focus.
    wait_for(page, "the Play screen", lambda s: s.get("screen") == "play_screen", SCREEN_TIMEOUT_S)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "play_screen.png")
    pressed = page.evaluate("performance.now()")
    press(page, "Enter")
    wait_for(page, "a running night", lambda s: bool(s.get("night") and s.get("running")), NIGHT_LOAD_TIMEOUT_S)
    running = page.evaluate("performance.now()")
    result["loading"] = loading_report(page.evaluate("window.__linkFrames"), pressed, running)
    result["loading"]["steps"] = loading_steps(page.evaluate("window.deadnight_marks || []"), pressed, running)
    page.wait_for_timeout(1500)
    page.screenshot(path=out / "night.png")

    # The soldier is drawn between physics ticks. A screen (a Control) above the night once switched that off for the
    # whole lot, and nothing in a test room or a frame time showed it (issues #344, #353).
    result["body_interpolated"] = bool(probe(page).get("interpolated"))
    if not result["body_interpolated"]:
        raise RuntimeError("the player's body is not drawn between physics ticks (physics interpolation is off)")

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


def loading_steps(marks: list[list], pressed: float, running: float) -> list[list]:
    """Where the loading time went: the first time the game marked each step (`WebProbe.mark`: the loading screen's own
    text, without its "(3 of 19)" counter), as [seconds after Play, step]. A failed `[loading]` check says how long the
    night took; this says which step took it (the sounds, the lot, the effects), so a slow runner and a slow change tell
    apart in the artifact."""
    steps: list[list] = []
    seen: set[str] = set()
    for label, at in marks:
        name = label.split(" (")[0]
        if name not in seen and pressed <= at <= running:
            seen.add(name)
            steps.append([round((at - pressed) / 1000, 2), name])
    return steps


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
        # The three busiest frames as [seconds after Play, programs, frame ms], to find what they drew.
        "busiest_frames": [
            [round((f[0] - pressed) / 1000, 2), int(f[1]), f[2]] for f in sorted(during, key=lambda f: -f[1])[:3]
        ],
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
