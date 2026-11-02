"""Plays a loud night's worth of voices in the web build, in a browser, and listens to what comes out.

    uv run --with playwright==1.64.1 python tools/web_smoke/audio_load.py build/web build/audio-load \
        [--playback sample|stream] [--gpu]

Runs `res://tools/web_audio_load/web_audio_load.tscn` (a copy of the export's page with that scene as the program's
argument) in headless Chromium. The scene starts looping voices in steps: silence, one bright voice open, the same one
with the player's distance filter at 800 Hz, the same one under a -12 dB bus effect (the duck), then 8, 16, 32 and
32 positional with 12 flat voices (the service's whole pool). The page taps the browser's audio output: every connection
the game makes to the speakers is routed through one gain node and an `AudioWorklet` that counts, for each phase, the
output's level, the 128-sample blocks that are silent (an underrun) and the jumps between neighbouring samples over 0.2
of full scale (a click). The scene's own frame times come with them. The result is `audio_load.json` and a table.

Playback is how the engine plays an `AudioStreamPlayer`: `sample` is the browser's own nodes (the web default of Godot
4.3 and later), `stream` is the engine's mixer in an audio worklet. `docs/research/web-export.md` has what it found.
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

SCENE = "res://tools/web_audio_load/web_audio_load.tscn"
GAME = Path(__file__).resolve().parents[2] / "game"
MAIN_SCENE = 'run/main_scene="res://main.tscn"'
LOAD_TIMEOUT_S = 150
RUN_TIMEOUT_S = 120

TAP_JS = r"""
(() => {
  window.__tap = {};
  const marks = [];
  marks.push = function (entry) {
    entry.push(Object.assign({}, window.__tap));
    return Array.prototype.push.call(this, entry);
  };
  window.deadnight_marks = marks;
  const worklet = `
    class Tap extends AudioWorkletProcessor {
      constructor() { super(); this.q = 0; this.silent = 0; this.jumps = 0; this.peak = 0; this.sumsq = 0; this.n = 0;
                      this.last = [0, 0]; this.t = 0; }
      process(inputs) {
        const input = inputs[0];
        if (input && input.length) {
          let quiet = true;
          for (let c = 0; c < input.length; c++) {
            const x = input[c];
            for (let i = 0; i < x.length; i++) {
              const v = x[i], a = Math.abs(v);
              if (a > 1e-6) quiet = false;
              if (a > this.peak) this.peak = a;
              this.sumsq += v * v;
              if (Math.abs(v - this.last[c]) > 0.2) this.jumps++;
              this.last[c] = v;
            }
          }
          this.n += input.length * input[0].length;
          this.q++;
          if (quiet) this.silent++;
        }
        if (++this.t % 16 === 0) {
          this.port.postMessage({ q: this.q, silent: this.silent, jumps: this.jumps, peak: this.peak,
                                  sumsq: this.sumsq, n: this.n });
        }
        return true;
      }
    }
    registerProcessor('deadnight-tap', Tap);`;
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
          const node = new AudioWorkletNode(ctx, 'deadnight-tap', { numberOfOutputs: 0 });
          node.port.onmessage = (event) => { window.__tap = event.data; };
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


def phases_from(marks: list, result: dict) -> list[dict]:
    """Cuts the tap's counters at the marks: each phase from the end of its settling second to its end."""
    at = {entry[0]: entry[2] for entry in marks}
    out = []
    for row in result["phases"]:
        name = row["phase"]
        start, end = at.get(f"audio:{name}:measure"), at.get(f"audio:{name}:end")
        if not start or not end or "n" not in start or "n" not in end:
            out.append({**row, "level_dbfs": None})
            continue
        samples = end["n"] - start["n"]
        energy = end["sumsq"] - start["sumsq"]
        out.append(
            {
                **row,
                "level_dbfs": round(db(math.sqrt(energy / samples)), 1) if samples else None,
                "peak_dbfs": round(db(end["peak"]), 1),
                "silent_blocks": end["silent"] - start["silent"],
                "blocks": end["q"] - start["q"],
                "jumps": end["jumps"] - start["jumps"],
            }
        )
    return out


def export_with_scene(godot: str, folder: Path, settings: str = "") -> None:
    """Exports the web build into `folder` with the load scene as the main scene, and restores project.godot."""
    project = GAME / "project.godot"
    original = project.read_bytes()
    text = original.decode("utf-8")
    if MAIN_SCENE not in text:
        sys.exit("project.godot has no run/main_scene to replace")
    folder.mkdir(parents=True, exist_ok=True)
    try:
        edited = text.replace(MAIN_SCENE, f'run/main_scene="{SCENE}"')
        if settings:
            edited = edited.replace("[autoload]", f"[audio]\n\n{settings}\n\n[autoload]", 1)
        project.write_bytes(edited.encode("utf-8"))
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=Path)
    parser.add_argument(
        "--godot", required=True, help="the pinned Godot (gds tool path godot), with its export templates"
    )
    parser.add_argument(
        "--latency", type=int, help="the web audio driver's output latency in ms (the engine's default is 50)"
    )
    parser.add_argument("--playback", choices=["sample", "stream", "default"], default="default")
    parser.add_argument("--gpu", action="store_true", help="the installed Chrome (the machine's GPU), not the shell")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    build = args.out / "web"
    settings = f"audio/driver/output_latency.web={args.latency}" if args.latency else ""
    export_with_scene(args.godot, build, settings)
    page_name = "index.html"
    server, port = serve(build)
    console: list[str] = []
    try:
        with sync_playwright() as p:
            if args.gpu:
                browser = p.chromium.launch(channel="chrome", headless=True, args=UNPACED)
            else:
                browser = p.chromium.launch(headless=True, args=SOFTWARE_GL)
            page = browser.new_page(viewport={"width": 640, "height": 360})
            page.on("console", lambda m: console.append(f"[{m.type}] {m.text}"))
            page.add_init_script(TAP_JS)
            query = "" if args.playback == "default" else f"?playback={args.playback}"
            page.goto(f"http://127.0.0.1:{port}/{page_name}{query}", timeout=LOAD_TIMEOUT_S * 1000)
            page.wait_for_selector("canvas", timeout=LOAD_TIMEOUT_S * 1000)
            page.mouse.click(320, 180)  # the browser lets a page play sound after a click
            deadline = time.monotonic() + RUN_TIMEOUT_S
            result = None
            while time.monotonic() < deadline:
                result = page.evaluate("window.deadnight_audio_load || null")
                if result:
                    break
                time.sleep(0.25)
            if not result:
                sys.exit("the scene did not finish: " + "\n".join(console[-10:]))
            marks = page.evaluate("window.deadnight_marks")
            browser.close()
    finally:
        server.shutdown()
    rows = phases_from(marks, result)
    (args.out / "audio_load.json").write_text(
        json.dumps({"playback": args.playback, "gpu": args.gpu, "phases": rows, "console": console}, indent=1)
    )
    print(
        f"playback {args.playback}, {'GPU Chrome' if args.gpu else 'headless shell'}, mix {result['mix_rate']:.0f} Hz"
    )
    print(
        f"{'phase':<12}{'voices':>7}{'level':>8}{'peak':>8}{'silent':>8}{'jumps':>7}{'mean ms':>9}{'p95 ms':>8}{'max ms':>8}"
    )
    for row in rows:
        print(
            f"{row['phase']:<12}{row['voices']:>7}{row.get('level_dbfs')!s:>8}{row.get('peak_dbfs')!s:>8}"
            f"{row.get('silent_blocks')!s:>8}{row.get('jumps')!s:>7}{row['mean_ms']:>9}{row['p95_ms']:>8}{row['max_ms']:>8}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
