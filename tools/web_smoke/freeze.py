"""A browser tab that freezes, and comes back where the server has the player (issue #502, from #483).

Starts a game server of its own (a headless Godot process, `--server`), opens the web build in Chrome, joins the
server the way a player does, walks, and then stops the page's main thread with a busy loop in the page (not a pointer
lock, not a debugger pause: the loop is what the engine's own hitch looks like to the browser, and the WebSocket keeps
receiving into the browser's buffer meanwhile). After each stall the player lets go of the keys and the script reads
the game's probe (`window.deadnight`, game/core/web_probe.gd): the body this client moves, the player where the server
has it, and how many freezes the client noticed. The run fails when

- the body is further than `--settled` metres from the server's position some seconds after the player stopped;
- the body went further than `--most-off` metres from it while the player walked on after the stall;
- the console shows an `ERROR` about a full buffer (`Buffer payload full`) or any other error;
- the client noticed no freeze (the guard is blind in the browser).

    uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python \\
        tools/web_smoke/freeze.py build/web build/freeze --godot <path to the pinned Godot> --gpu --stalls 0.5,2,5

`--stalls` lists the seconds to stall for, in order; add a long one (`60`) to check the buffers. Writes `result.json`,
`console.txt` and screenshots into the output folder.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import ConsoleMessage, Page, sync_playwright
from playwright.sync_api import Error as PlaywrightError

sys.path.insert(0, str(Path(__file__).parent))
import online
import smoke

WALK_S = 1.5
SETTLE_S = 3.0
SAMPLE_S = 0.1
# The game's own limits, as test_client_freeze.gd holds them: settled within a hand, and at most the lead of a sprint
# plus the half second the server goes on with the last command of a client that went quiet.
SETTLED_M = 0.3
MOST_OFF_M = 8.0
SERVER_START_S = 90

BUSY_JS = """
(ms) => {
  const end = performance.now() + ms;
  while (performance.now() < end) {}
  return performance.now();
}
"""


class DelayProxy:
    """A TCP relay that holds every chunk back by `delay_s` each way, in order: a connection with a round trip of
    twice that between the page and the server. The browser's own network throttling does not touch WebSockets, and
    the freeze desync of #483 needs a round trip of a few frames, so a probe over loopback proves nothing without it."""

    def __init__(self, target_port: int, delay_s: float) -> None:
        self.target_port = target_port
        self.delay_s = delay_s
        self.port = 0
        self._loop = asyncio.new_event_loop()
        self._ready = threading.Event()
        threading.Thread(target=self._run, daemon=True).start()
        self._ready.wait(10)

    def _run(self) -> None:
        asyncio.set_event_loop(self._loop)
        server = self._loop.run_until_complete(asyncio.start_server(self._handle, "127.0.0.1", 0))
        self.port = server.sockets[0].getsockname()[1]
        self._ready.set()
        self._loop.run_forever()

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        up_reader, up_writer = await asyncio.open_connection("127.0.0.1", self.target_port)
        await asyncio.gather(self._pipe(reader, up_writer), self._pipe(up_reader, writer))

    async def _pipe(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        queue: asyncio.Queue = asyncio.Queue()

        async def deliver() -> None:
            while True:
                due, data = await queue.get()
                if data is None:
                    break
                wait = due - self._loop.time()
                if wait > 0:
                    await asyncio.sleep(wait)
                try:
                    writer.write(data)
                    await writer.drain()
                except ConnectionError:
                    break
            writer.close()

        task = asyncio.ensure_future(deliver())
        try:
            while data := await reader.read(65536):
                queue.put_nowait((self._loop.time() + self.delay_s, data))
        except ConnectionError:
            pass
        queue.put_nowait((0.0, None))
        await task

    def stop(self) -> None:
        self._loop.call_soon_threadsafe(self._loop.stop)


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def start_server(godot: str, game: Path, port: int, log: Path) -> subprocess.Popen:
    """A headless game server (one night, `NightHost`) on `port`; returns once it says it listens."""
    log.unlink(missing_ok=True)
    process = subprocess.Popen(
        [
            godot,
            "--headless",
            "--log-file",
            str(log),
            "--path",
            str(game),
            "--quit-after",
            "200000",
            "--",
            "--server",
            "--port",
            str(port),
            "--seed",
            "7",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.monotonic() + SERVER_START_S
    while time.monotonic() < deadline:
        if log.exists() and '"listening"' in log.read_text(encoding="utf-8", errors="replace"):
            return process
        time.sleep(0.25)
    stop(process)
    raise TimeoutError("the game server never said it listens")


def stop(process: subprocess.Popen) -> None:
    """Stops the server and what it started (the console wrapper of Godot starts the real program on Windows)."""
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], capture_output=True, check=False)
    else:
        process.kill()
    process.wait()


def gap(seen: dict) -> float:
    return math.hypot(
        seen.get("body_x", 0.0) - seen.get("server_x", 0.0), seen.get("body_z", 0.0) - seen.get("server_z", 0.0)
    )


def walk(page: Page, key: str, seconds: float, samples: list[float] | None = None) -> None:
    page.keyboard.down(key)
    page.keyboard.down("Shift")
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        seen = online.read_probe(page)
        if samples is not None:
            samples.append(gap(seen))
        page.wait_for_timeout(int(SAMPLE_S * 1000))


def release(page: Page, *keys: str) -> None:
    for key in keys:
        page.keyboard.up(key)


def one_stall(page: Page, seconds: float, out: Path, index: int) -> dict:
    """Walks, stalls the page for `seconds` with the keys held, walks on, stops, and reports where the body ended up."""
    before = online.read_probe(page)
    walk(page, "a" if index % 2 else "d", WALK_S)
    # The keys stay down through the freeze, as a player's would.
    page.evaluate(BUSY_JS, seconds * 1000)
    after_stall = online.read_probe(page)
    during: list[float] = []
    walk(page, "d" if index % 2 else "a", WALK_S, during)
    release(page, "w", "a", "s", "d", "Shift")
    page.wait_for_timeout(int(SETTLE_S * 1000))
    settled = online.read_probe(page)
    page.screenshot(path=out / f"stall_{index}_{seconds:g}s.png")
    return {
        "stall_s": seconds,
        "rtt_ms": round(settled.get("rtt_ms", -1.0), 1),
        "stalls_before": before.get("stalls", 0),
        "stalls_after": settled.get("stalls", 0),
        "longest_stall_ms": settled.get("stall_longest_ms", 0.0),
        "gap_right_after_stall_m": round(gap(after_stall), 2),
        "gap_most_while_walking_m": round(max(during, default=0.0), 2),
        "gap_settled_m": round(gap(settled), 3),
        "body": [round(settled.get("body_x", 0.0), 2), round(settled.get("body_z", 0.0), 2)],
        "server": [round(settled.get("server_x", 0.0), 2), round(settled.get("server_z", 0.0), 2)],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("web", help="folder with the exported index.html (served here), or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--godot", required=True, help="the pinned Godot (gds tool path godot)")
    parser.add_argument("--game", type=Path, default=Path(__file__).resolve().parents[2] / "game")
    parser.add_argument("--stalls", default="0.5,2,5", help="seconds to stall the page for, in order")
    parser.add_argument("--delay-ms", type=float, default=100.0, help="held back each way (a round trip of twice that)")
    parser.add_argument("--settled", type=float, default=SETTLED_M)
    parser.add_argument("--most-off", type=float, default=MOST_OFF_M)
    parser.add_argument("--gpu", action="store_true", help="the machine's Chrome and GPU, not a software renderer")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    stalls = [float(s) for s in args.stalls.split(",") if s]
    problems: list[str] = []
    console: list[str] = []
    result: dict = {"stalls": []}

    def on_console(message: ConsoleMessage) -> None:
        console.append(f"[{message.type}] {message.text}")
        if message.type == "error":
            problems.append(console[-1])

    port = free_port()
    server = start_server(args.godot, args.game, port, args.out / "server.log")
    proxy = DelayProxy(port, args.delay_ms / 1000.0) if args.delay_ms > 0 else None
    address_port = proxy.port if proxy else port
    local = None
    url = args.web
    if not url.startswith(("http://", "https://")):
        local, web_port = smoke.serve(Path(url))
        url = f"http://127.0.0.1:{web_port}/index.html"
    url += ("&" if "?" in url else "?") + "dev&probe"
    try:
        with sync_playwright() as p:
            if args.gpu:
                browser = p.chromium.launch(channel="chrome", headless=True, args=smoke.mute_args())
            else:
                browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
            page = browser.new_page(viewport=smoke.VIEWPORT)
            page.on("console", on_console)
            page.on("pageerror", lambda error: problems.append(f"[pageerror] {error}"))
            try:
                page.goto(url, wait_until="commit")
                online.join(page, f"ws://127.0.0.1:{address_port}", args.out)
                online.probe_after(
                    page,
                    online.JOIN_TIMEOUT_S,
                    "a running online night",
                    lambda s: bool(s.get("night") and s.get("running")),
                )
                page.mouse.move(640, 360)
                page.wait_for_timeout(1500)
                page.screenshot(path=args.out / "night.png")
                for index, seconds in enumerate(stalls):
                    row = one_stall(page, seconds, args.out, index)
                    result["stalls"].append(row)
                    print(json.dumps(row))
                    if row["stalls_after"] <= row["stalls_before"]:
                        problems.append(f"the client noticed no freeze after the {seconds:g} s stall")
                    if row["gap_settled_m"] > args.settled:
                        problems.append(
                            f"{seconds:g} s stall: the body is {row['gap_settled_m']} m from the server after stopping"
                        )
                    if row["gap_most_while_walking_m"] > args.most_off:
                        problems.append(
                            f"{seconds:g} s stall: the body went {row['gap_most_while_walking_m']} m from the server"
                        )
            except (TimeoutError, PlaywrightError) as error:
                problems.append(f"[run] {error}")
                try:
                    page.screenshot(path=args.out / "failure.png")
                except PlaywrightError:
                    pass
            finally:
                browser.close()
    finally:
        stop(server)
        if proxy:
            proxy.stop()
        if local:
            local.shutdown()
    full = [line for line in console if "payload full" in line.lower()]
    result["buffer_full_lines"] = len(full)
    if full:
        problems.append(f"the console shows {len(full)} 'Buffer payload full' lines")
    (args.out / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    result["problems"] = problems
    (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"problems": problems}, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
