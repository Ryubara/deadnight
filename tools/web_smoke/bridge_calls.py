"""How often a page load crosses the JavaScript bridge, with and without the probes (issue #935).

The web build's probes publish what the game does as `window.deadnight` for a browser test. A player's page must not pay
for them: a read or write over `JavaScriptBridge` is a call into the page, and one that allocates lands on the page's
heap. This counts the bridge's traffic of a page that nobody probes, so the claim "a plain page crosses the bridge about
never" has a number, and the web job fails when a probe comes back to the shipped page.

What is counted (an init script puts counters in the page before the engine starts):

- every `JavaScriptBridge.create_object("Object")` is a counting proxy: a property read, a property write and a method
  call on it are one count each (`window.deadnight`, which the probes read and write). `Array` is not wrapped: the
  engine's own glue makes arrays (its WebGL id tables) and they would be counted as the game's;
- every `JavaScriptBridge.eval` is one count (`window.eval` is wrapped);
- `window.deadnight` itself read or written by the engine (the probes fetch it once, in `_ready`).

Two loads, each sampled over `--seconds` after a settle time: the main menu, and a night the autopilot plays from the
address (`?autopilot`, no probe involved). With `--probe` the same loads carry `?probe`, the arm a browser test uses.
The gate is `--max-per-second` for the plain page (default 1 for the menu and for the night: a few `eval`s at start
are before the window).

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/bridge_calls.py build/web out/bridge-calls \\
        [--probe] [--seconds 20] [--settle 25] [--max-per-second 1]
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

# Counters in `window.__bridge`: `get` property reads, `set` property writes, `call` method calls, `eval` evals.
COUNT_JS = """
() => {
  const c = (window.__bridge = { get: 0, set: 0, call: 0, eval: 0 });
  // What was touched: `get:key`, `set:key`, `call:key`, `eval:first 50 characters` -> count.
  const what = (window.__bridgeKeys = {});
  const note = (name) => { what[name] = (what[name] || 0) + 1; };
  const counted = (object) =>
    new Proxy(object, {
      get(target, key) {
        const value = Reflect.get(target, key, target);
        if (typeof value === 'function') {
          c.call += 1;
          note('call:' + String(key));
          return value.bind(target);
        }
        c.get += 1;
        note('get:' + String(key));
        return value;
      },
      set(target, key, value) {
        c.set += 1;
        note('set:' + String(key));
        target[key] = value;
        return true;
      },
    });
  for (const name of ['Object']) {
    const Real = window[name];
    window[name] = new Proxy(Real, {
      construct(target, args) {
        return counted(Reflect.construct(target, args, target));
      },
    });
  }
  const realEval = window.eval;
  window.eval = function (code) {
    c.eval += 1;
    note('eval:' + String(code).slice(0, 50));
    return realEval.call(window, code);
  };
}
"""
READ_JS = "() => Object.assign({}, window.__bridge)"
KEYS_JS = "() => Object.assign({}, window.__bridgeKeys)"
TOP = 8
ARMS = {
    "menu": "",
    "night": "autopilot&rounds=99&hold=0&count=1&seconds=600",
}


def total(counts: dict) -> int:
    return sum(counts.values())


def measure(playwright, base: str, query: str, settle: float, seconds: float) -> dict:
    browser = playwright.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *smoke.mute_args()])
    page = browser.new_page(viewport=smoke.VIEWPORT)
    errors: list[str] = []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.add_init_script("(" + COUNT_JS.strip() + ")();")
    page.goto(f"{base}?{query}" if query else base, wait_until="commit")
    time.sleep(settle)
    first = page.evaluate(READ_JS)
    began = time.monotonic()
    time.sleep(seconds)
    last = page.evaluate(READ_JS)
    keys = page.evaluate(KEYS_JS)
    wall = time.monotonic() - began
    shot = page.screenshot()
    browser.close()
    delta = {key: last[key] - first[key] for key in last}
    return {
        "seconds": round(wall, 1),
        "calls": delta,
        "per_second": round(total(delta) / wall, 2),
        "total_at_start": first,
        "top_touched": dict(sorted(keys.items(), key=lambda item: -item[1])[:TOP]),
        "console_errors": errors[:5],
        "_shot": shot,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="the exported build folder")
    parser.add_argument("out", help="where the report and the screenshots go")
    parser.add_argument("--probe", action="store_true", help="open the pages with ?probe (the browser test's arm)")
    parser.add_argument("--seconds", type=float, default=20.0, help="how long each load is counted")
    parser.add_argument("--settle", type=float, default=25.0, help="seconds after the load before counting starts")
    parser.add_argument("--night-settle", type=float, default=70.0, help="the same for the night (it loads longer)")
    parser.add_argument("--label", default="")
    parser.add_argument(
        "--max-per-second", type=float, default=0.0, help="fail when a plain page crosses more (0: off)"
    )
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    label = args.label or ("probe" if args.probe else "plain")
    server, port = smoke.serve(Path(args.build))
    base = f"http://127.0.0.1:{port}/index.html"
    report: dict = {"label": label, "probe": args.probe}
    problems: list[str] = []
    try:
        with sync_playwright() as p:
            for name, query in ARMS.items():
                if args.probe:
                    query = f"{query}&probe" if query else "probe"
                settle = args.night_settle if name == "night" else args.settle
                result = measure(p, base, query, settle, args.seconds)
                (out / f"{label}_{name}.png").write_bytes(result.pop("_shot"))
                report[name] = result
                print(f"{label} {name}: {result['per_second']} bridge calls a second {result['calls']}", flush=True)
                limit = args.max_per_second
                if not args.probe and limit > 0 and result["per_second"] > limit:
                    problems.append(
                        f"[bridge] the plain {name} page crosses the JavaScript bridge {result['per_second']} times a "
                        f"second, over {limit}: a probe is running in the shipped build (game/core/web_probe.gd)"
                    )
                problems += [f"[console] {line}" for line in result["console_errors"]]
    finally:
        server.shutdown()
    report["problems"] = problems
    (out / f"{label}.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
