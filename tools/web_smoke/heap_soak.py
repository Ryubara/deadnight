"""What the web page's JS heap holds over a night (issue #834).

Loads the exported build in Chrome as a phone (or as a desktop with `--dpr 1 --size 1280x720`), lets the autopilot
play a night from the page's address, and every `--gc-every` seconds forces a collection (`HeapProfiler.collectGarbage`)
and reads what stays: the V8 heap (`Runtime.getHeapUsage`), the DOM nodes and event listeners (`Performance.getMetrics`)
and the engine's own count of its nodes. A heap that rises after a forced collection is held, not waiting to be freed.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/heap_soak.py build/web <out folder> \\
        [--minutes 6] [--label NAME] [--query "probe_off=webprobe"] [--no-recorder] [--sampling] [--plain]

`--plain` opens the page the way a player does, without `?probe`: no probe reads the page, so the night is waited for a
fixed `--settle` seconds instead of asked of `window.deadnight`, and the rows carry no zombie count (#935). Without it
the page carries `?probe`, the browser test's arm.

`--no-recorder` leaves out the frame-time recorder of `phone_frames.py` (a page that is only played); `--sampling`
runs V8's sampling heap profiler for the whole run and writes the stacks that allocated what is still alive at the
end (`<label>_sampling.txt`), the shortest way to the code that holds the memory.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

CHROME_FLAGS = ["--enable-precise-memory-info"]
PHONE_AGENT = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/156.0.0.0 Mobile Safari/537.36"
)
NIGHT_WAIT_S = 420.0
# The sampling profiler takes one sample about every this many bytes allocated.
SAMPLING_INTERVAL = 16384
TOP_STACKS = 40

# The same recorder `phone_frames.py` installs: every frame's time into a page array that is drained every few seconds.
RECORDER_JS = """
() => {
  window.__d = [];
  let last = performance.now();
  function frame(now) {
    window.__d.push(now, Math.round((now - last) * 100) / 100);
    last = now;
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
"""
# Counts every WebGL object the page creates (emscripten numbers them with one shared counter and pads every table
# to it, so each creation costs eight bytes in each of the tables until the page closes: the heap growth of #834).
GL_COUNT_JS = """
() => {
  window.__gl = {};
  const names = ['createBuffer', 'createTexture', 'createProgram', 'createShader', 'createFramebuffer',
    'createRenderbuffer', 'createVertexArray', 'fenceSync', 'createQuery', 'createSampler', 'createTransformFeedback'];
  for (const proto of [WebGL2RenderingContext.prototype, WebGLRenderingContext.prototype]) {
    for (const name of names) {
      const original = proto[name];
      if (!original) continue;
      proto[name] = function () {
        window.__gl[name] = (window.__gl[name] || 0) + 1;
        return original.apply(this, arguments);
      };
    }
  }
}
"""
DRAIN_JS = "() => { const d = window.__d || []; window.__d = []; return d.length; }"


def metrics(session) -> dict[str, float]:
    """The page's counters after a forced collection: V8 heap, DOM nodes, listeners."""
    session.send("HeapProfiler.collectGarbage")
    usage = session.send("Runtime.getHeapUsage")
    got = {m["name"]: m["value"] for m in session.send("Performance.getMetrics")["metrics"]}
    return {
        "heap_mb": round(usage["usedSize"] / 1048576.0, 1),
        "heap_total_mb": round(usage["totalSize"] / 1048576.0, 1),
        "dom_nodes": got.get("Nodes", 0),
        "listeners": got.get("JSEventListeners", 0),
        "documents": got.get("Documents", 0),
    }


def stacks(profile: dict) -> list[tuple[int, str]]:
    """The sampling profile's nodes as (bytes still alive, `function url:line` chain), biggest first."""
    rows: list[tuple[int, str]] = []

    def walk(node: dict, chain: list[str]) -> None:
        frame = node["callFrame"]
        name = frame["functionName"] or "(anonymous)"
        here = [*chain, f"{name} {frame['url'].rsplit('/', 1)[-1]}:{frame['lineNumber']}"]
        if node.get("selfSize", 0):
            rows.append((int(node["selfSize"]), " < ".join(reversed(here[-7:]))))
        for child in node.get("children", []):
            walk(child, here)

    walk(profile["head"], [])
    rows.sort(reverse=True)
    return rows


def run(args: argparse.Namespace) -> dict:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    server, port = smoke.serve(Path(args.build))
    query = f"autopilot&rounds=99&hold=0&seconds={int(args.minutes * 60 + 240)}&{args.query}"
    if not args.plain:
        query += "&probe"
    url = f"http://127.0.0.1:{port}/index.html?{query}"
    flags = [*CHROME_FLAGS, *(smoke.UNPACED if args.unpaced else []), *smoke.mute_args()]
    width, height = (int(v) for v in args.size.split("x"))
    series: list[dict] = []
    errors: list[str] = []
    sampling_text = ""
    try:
        with sync_playwright() as p:
            if args.software:
                browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *flags])
            else:
                browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
            context = browser.new_context(
                viewport={"width": width, "height": height},
                device_scale_factor=args.dpr,
                is_mobile=args.dpr > 1.0,
                has_touch=args.dpr > 1.0,
                user_agent=PHONE_AGENT if args.dpr > 1.0 else None,
            )
            page = context.new_page()
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: errors.append(str(e)))
            session = context.new_cdp_session(page)
            session.send("Performance.enable")
            if not args.no_recorder:
                page.add_init_script("(" + RECORDER_JS.strip() + ")();")
            if args.count_gl:
                page.add_init_script("(" + GL_COUNT_JS.strip() + ")();")
            if args.sampling:
                session.send("HeapProfiler.startSampling", {"samplingInterval": SAMPLING_INTERVAL})
            page.goto(url, wait_until="commit")
            began = time.monotonic()
            if args.plain:
                time.sleep(args.settle)
            else:
                while not smoke.probe(page).get("running"):
                    if time.monotonic() - began > NIGHT_WAIT_S:
                        raise TimeoutError("the night never ran")
                    time.sleep(1.0)
            run_began = time.monotonic()
            if not args.no_recorder:
                page.evaluate(DRAIN_JS)
            while time.monotonic() - run_began < args.minutes * 60:
                time.sleep(args.gc_every)
                row = metrics(session)
                row["t"] = round(time.monotonic() - run_began, 1)
                if not args.no_recorder:
                    page.evaluate(DRAIN_JS)
                row["alive"] = page.evaluate("() => (window.deadnight ? window.deadnight.alive : -1)")
                row["round"] = page.evaluate("() => (window.deadnight ? window.deadnight.round : -1)")
                if args.count_gl:
                    row["gl_created"] = page.evaluate("() => window.__gl")
                series.append(row)
                print(json.dumps(row), flush=True)
            page.screenshot(path=out / f"{args.label}_end.png")
            if args.sampling:
                session.send("HeapProfiler.collectGarbage")
                profile = session.send("HeapProfiler.stopSampling")["profile"]
                rows = stacks(profile)
                total = sum(size for size, _ in rows)
                lines = [f"alive at the end: {total / 1048576.0:.1f} MB in {len(rows)} stacks"]
                lines += [f"{size / 1048576.0:8.2f} MB  {chain}" for size, chain in rows[:TOP_STACKS]]
                sampling_text = "\n".join(lines)
                (out / f"{args.label}_sampling.txt").write_text(sampling_text, encoding="utf-8")
            browser.close()
    finally:
        server.shutdown()
    return {"label": args.label, "query": args.query, "series": series, "console_errors": errors[:5]}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported build folder")
    parser.add_argument("out", help="where the report goes")
    parser.add_argument("--minutes", type=float, default=6.0)
    parser.add_argument("--gc-every", type=float, default=30.0, help="seconds between forced collections")
    parser.add_argument("--dpr", type=float, default=3.0)
    parser.add_argument("--size", default="844x390")
    parser.add_argument("--unpaced", action="store_true", help="lift the display's 60 Hz limit")
    parser.add_argument("--software", action="store_true")
    parser.add_argument("--no-recorder", action="store_true", help="no frame-time recorder in the page")
    parser.add_argument("--sampling", action="store_true", help="V8 sampling heap profile of what is alive at the end")
    parser.add_argument("--count-gl", action="store_true", help="count the WebGL objects the page creates")
    parser.add_argument("--plain", action="store_true", help="no ?probe: the page a player opens")
    parser.add_argument("--settle", type=float, default=90.0, help="with --plain: seconds to wait for the night")
    parser.add_argument("--label", default="run")
    parser.add_argument(
        "--query",
        default="count=1&hints=0",
        help="more address arguments for the autopilot (hints=0: the touch hints are marked used)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = run(args)
    (Path(args.out) / f"{args.label}.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    first, last = report["series"][0], report["series"][-1]
    print(
        f"{args.label}: heap after a forced collection {first['heap_mb']} MB at {first['t']} s -> {last['heap_mb']} MB at {last['t']} s"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
