"""Does a limiter on the Master bus act in the web build? Measured in a browser (Deadnight #718).

    uv run --project <kit>/python gds quiet -- \
        uv run --with playwright==1.64.1 python tools/web_smoke/limiter_web.py build/limiter --godot <pinned godot>

Runs `res://tools/bench/audio_limiter_probe.tscn` (the tommy gun fired without a break through the audio service in
four phases: nothing on the buses, a hard limiter on Master, the limiter taken off, Master turned down) as the page's
program, in headless Chromium, with the same tap on the page's audio output as `gun_levels_web.py`. The browser plays
sounds as samples, which ignore bus effects, so the limiter's phase should peak like the plain ones and only the
volume control should move it. Prints the peak and RMS (dBFS) of each phase and writes `limiter_web.json`. The same
scene run natively with Movie Maker (`--write-movie`) shows the limiter holding its ceiling there.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import gun_levels_web as tap
from smoke import SOFTWARE_GL, serve

SCENE = "res://tools/bench/audio_limiter_probe.tscn"
BURST_S = 2.0
RUN_TIMEOUT_S = 150


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=Path)
    parser.add_argument("--godot", required=True, help="the pinned Godot (gds tool path godot), with its templates")
    args = parser.parse_args()
    tap.SCENE = SCENE
    build = args.out / "web"
    tap.export(args.godot, build)
    server, port = serve(build)
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
            page = browser.new_page(viewport={"width": 320, "height": 180})
            page.add_init_script(tap.INIT_JS)
            page.goto(f"http://127.0.0.1:{port}/index.html", timeout=tap.LOAD_TIMEOUT_S * 1000)
            page.wait_for_selector("canvas", timeout=tap.LOAD_TIMEOUT_S * 1000)
            page.mouse.click(160, 90)  # the browser lets a page play sound after a click
            deadline = time.monotonic() + RUN_TIMEOUT_S
            while time.monotonic() < deadline:
                if page.evaluate("window.__log.some(l => l[1].startsWith('END'))"):
                    break
                time.sleep(0.5)
            else:
                sys.exit("the probe did not finish")
            time.sleep(1.0)
            log = page.evaluate("window.__log")
            series = page.evaluate("window.__series")
            browser.close()
    finally:
        server.shutdown()
    starts = {text.split()[1]: stamp for stamp, text in log if text.startswith("PHASE")}
    result = {name: tap.window(series, stamp, BURST_S) for name, stamp in starts.items()}
    (args.out / "limiter_web.json").write_text(json.dumps(result, indent=1))
    print(f"{'phase':<14}{'peak dBFS':>10}{'rms dBFS':>10}")
    for name, row in result.items():
        print(f"{name:<14}{row['peak_dbfs']:>10}{row['rms_dbfs']:>10}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
