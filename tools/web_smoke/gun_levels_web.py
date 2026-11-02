"""Fires every gun in the web build, in a browser, and measures what comes out of the page's audio output.

    uv run --with playwright==1.64.1 python tools/web_smoke/gun_levels_web.py build/gun-levels --godot <pinned godot>

Runs `res://tools/bench/audio_gun_bench.tscn` (the scene that fires one shot and a two second burst of each firearm
through `WeaponSounds` and the audio service, then runs the night's beds alone) as the page's program, in headless
Chromium. The browser plays sounds as samples, which ignore bus effects and the distance filter, so this is the check
that the guns' power is in their files and their trims and not in the bus. The page taps its audio output in an
`AudioWorklet` that reports the peak and the energy of every 16 blocks of 128 samples; the bench's own `SLOT` and
`SHOT` lines (stamped when they reach the browser's console) say when each shot started. Prints, per gun, the peak and
the level (RMS, dBFS) of the single shot and of the burst, and the beds' level for comparison, and writes
`gun_levels_web.json`. RMS is not LUFS (no K-weighting, no gating): compare it with the same figures taken from a native
recording, not with a loudness target.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
from smoke import SOFTWARE_GL, UNPACED, serve

SCENE = "res://tools/bench/audio_gun_bench.tscn"
GAME = Path(__file__).resolve().parents[2] / "game"
MAIN_SCENE = 'run/main_scene="res://main.tscn"'
LOAD_TIMEOUT_S = 150
RUN_TIMEOUT_S = 240
SINGLE_WINDOW_S = 1.2
BURST_WINDOW_S = 3.0
BED_WINDOW_S = 6.0
BED_SETTLE_S = 4.0

INIT_JS = r"""
(() => {
  window.__series = [];
  window.__log = [];
  for (const level of ['log', 'info']) {
    const original = console[level].bind(console);
    console[level] = (...args) => {
      window.__log.push([performance.now(), args.join(' ')]);
      original(...args);
    };
  }
  const worklet = `
    class Tap extends AudioWorkletProcessor {
      constructor() { super(); this.peak = 0; this.sumsq = 0; this.n = 0; this.t = 0; }
      process(inputs) {
        const input = inputs[0];
        if (input && input.length) {
          for (let c = 0; c < input.length; c++) {
            const x = input[c];
            for (let i = 0; i < x.length; i++) {
              const a = Math.abs(x[i]);
              if (a > this.peak) this.peak = a;
              this.sumsq += x[i] * x[i];
            }
            this.n += x.length;
          }
        }
        if (++this.t % 16 === 0) {
          this.port.postMessage({ peak: this.peak, sumsq: this.sumsq, n: this.n });
          this.peak = 0; this.sumsq = 0; this.n = 0;
        }
        return true;
      }
    }
    registerProcessor('deadnight-gun-tap', Tap);`;
  const url = URL.createObjectURL(new Blob([worklet], { type: 'text/javascript' }));
  const connect = AudioNode.prototype.connect;
  const mixers = new WeakMap();
  AudioNode.prototype.connect = function (destination, ...rest) {
    if (destination instanceof AudioDestinationNode && this.context.audioWorklet) {
      const ctx = this.context;
      let mixer = mixers.get(ctx);
      if (!mixer) {
        mixer = ctx.createGain();
        mixers.set(ctx, mixer);
        connect.call(mixer, ctx.destination);
        ctx.audioWorklet.addModule(url).then(() => {
          const node = new AudioWorkletNode(ctx, 'deadnight-gun-tap', { numberOfOutputs: 0 });
          node.port.onmessage = (event) => { window.__series.push([performance.now(), event.data]); };
          connect.call(mixer, node);
        });
      }
      return connect.call(this, mixer, ...rest);
    }
    return connect.call(this, destination, ...rest);
  };
})();
"""


def db(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-9))


def export(godot: str, folder: Path) -> None:
    """Exports the web build with the bench as the main scene, and restores project.godot."""
    project = GAME / "project.godot"
    original = project.read_bytes()
    text = original.decode("utf-8")
    if MAIN_SCENE not in text:
        sys.exit("project.godot has no run/main_scene to replace")
    folder.mkdir(parents=True, exist_ok=True)
    try:
        project.write_bytes(text.replace(MAIN_SCENE, f'run/main_scene="{SCENE}"').encode("utf-8"))
        done = subprocess.run(
            [godot, "--headless", "--path", str(GAME), "--export-release", "Web", str(folder / "index.html")],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        project.write_bytes(original)
    if "ERROR" in done.stdout + done.stderr or not (folder / "index.pck").exists():
        sys.exit("the export failed: " + done.stdout[-1500:] + done.stderr[-1500:])


def window(series: list, start: float, seconds: float) -> dict[str, float]:
    """Peak and RMS (dBFS) of what the tap heard from `start` (browser milliseconds) for `seconds`."""
    peak, energy, count = 0.0, 0.0, 0
    for stamp, row in series:
        if start <= stamp < start + seconds * 1000.0:
            peak = max(peak, row["peak"])
            energy += row["sumsq"]
            count += row["n"]
    return {"peak_dbfs": round(db(peak), 1), "rms_dbfs": round(db(math.sqrt(energy / count)), 1) if count else -120.0}


def analyse(log: list, series: list) -> dict:
    """Cuts the tap's series at the bench's own lines: the first `SHOT` of a weapon is its single shot, the first one
    after more than a second is the burst, and `BED` is where the beds begin."""
    first: dict[str, list[float]] = {}
    bed = None
    for stamp, text in log:
        parts = text.split()
        if parts[:1] == ["SHOT"] and len(parts) > 3 and parts[3].startswith("shot_"):
            stamps = first.setdefault(parts[2], [])
            if not stamps or stamp - stamps[-1] > 1000.0:
                stamps.append(stamp)
        elif parts[:1] == ["BED"]:
            bed = stamp
    guns = {}
    for weapon, stamps in first.items():
        guns[weapon] = {"single": window(series, stamps[0] - 50.0, SINGLE_WINDOW_S)}
        if len(stamps) > 1:
            guns[weapon]["burst"] = window(series, stamps[1] - 50.0, BURST_WINDOW_S)
    beds = window(series, bed + BED_SETTLE_S * 1000.0, BED_WINDOW_S) if bed else None
    return {"guns": guns, "beds": beds}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=Path)
    parser.add_argument("--godot", required=True, help="the pinned Godot (gds tool path godot), with its templates")
    parser.add_argument("--gpu", action="store_true", help="the installed Chrome (the machine's GPU), not the shell")
    args = parser.parse_args()
    build = args.out / "web"
    export(args.godot, build)
    server, port = serve(build)
    try:
        with sync_playwright() as p:
            if args.gpu:
                browser = p.chromium.launch(channel="chrome", headless=True, args=UNPACED)
            else:
                browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
            page = browser.new_page(viewport={"width": 320, "height": 180})
            page.add_init_script(INIT_JS)
            page.goto(f"http://127.0.0.1:{port}/index.html", timeout=LOAD_TIMEOUT_S * 1000)
            page.wait_for_selector("canvas", timeout=LOAD_TIMEOUT_S * 1000)
            page.mouse.click(160, 90)  # the browser lets a page play sound after a click
            deadline = time.monotonic() + RUN_TIMEOUT_S
            bed_seen = None
            while time.monotonic() < deadline:
                lines = page.evaluate("window.__log.map(l => l[1]).filter(t => t.startsWith('BED'))")
                if lines and bed_seen is None:
                    bed_seen = time.monotonic()
                if bed_seen is not None and time.monotonic() - bed_seen > 12.0:
                    break
                time.sleep(0.5)
            else:
                sys.exit("the bench did not reach its beds")
            log = page.evaluate("window.__log")
            series = page.evaluate("window.__series")
            browser.close()
    finally:
        server.shutdown()
    result = analyse(log, series)
    (args.out / "gun_levels_web.json").write_text(json.dumps(result, indent=1))
    print(f"{'gun':<11}{'single peak':>12}{'single rms':>12}{'burst peak':>12}{'burst rms':>11}")
    for weapon, row in result["guns"].items():
        burst = row.get("burst", {})
        print(
            f"{weapon:<11}{row['single']['peak_dbfs']:>12}{row['single']['rms_dbfs']:>12}"
            f"{burst.get('peak_dbfs', '-')!s:>12}{burst.get('rms_dbfs', '-')!s:>11}"
        )
    if result["beds"]:
        print(f"{'beds':<11}{result['beds']['peak_dbfs']:>12}{result['beds']['rms_dbfs']:>12}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
