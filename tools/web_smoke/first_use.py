"""Frame times through the first seconds of a night in the web build, to find first-use hitches.

The first time something is drawn in the browser, Godot compiles and links a WebGL program for it (and loads and
decodes the resource), on the main thread. This script plays a night the way a player does (Play, then walk a square
firing) in a fresh Chrome profile, records every requestAnimationFrame delta from the page's first frame, and reports
the worst frames and where in the night they fall. Chrome keeps a GPU program cache in its profile, so a run always
starts from an empty one: `launch` makes a new temporary profile each time.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 --with matplotlib python tools/web_smoke/first_use.py build/web build/first_use

Options: `--runs N` repeats from a new profile each time (the report keeps every run), `--seconds S` is how long the
night is played (default 20), `--label before|after` names the chart. The chart (`frame_times.png`) shows the first
run, or the worst run with `--chart worst`.
"""

from __future__ import annotations

import argparse
import bisect
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import smoke

NIGHT_SECONDS = 20.0
# Frames longer than these are a visible hitch at 60 Hz (two frames, three, six).
THRESHOLDS_MS = (33.4, 50.0, 100.0)
CHROME_FLAGS = ["--enable-precise-memory-info"]

# Records every frame from the first one: [time since the page began, delta, zombies alive, night running].
RECORDER_JS = """
() => {
  window.__frames = [];
  let last = performance.now();
  function frame(now) {
    const d = window.deadnight || {};
    window.__frames.push([Math.round(now * 10) / 10, Math.round((now - last) * 10) / 10,
                          d.alive || 0, d.running ? 1 : 0]);
    last = now;
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}
"""


# Counts every WebGL program Godot links, and the time the page spends waiting for it: the cost of a first use.
# Godot calls getProgramParameter(LINK_STATUS) right after linkProgram, which is where the browser blocks.
GL_HOOK_JS = """
() => {
  window.__links = [];
  const proto = WebGL2RenderingContext.prototype;
  const shaderSource = proto.shaderSource;
  proto.shaderSource = function (shader, source) {
    shader.__defs = (source.match(/^#define [A-Z0-9_]+/gm) || []).map((d) => d.slice(8)).join(' ');
    return shaderSource.call(this, shader, source);
  };
  const attach = proto.attachShader;
  proto.attachShader = function (program, shader) {
    (program.__defs = program.__defs || []).push(shader.__defs || '');
    return attach.call(this, program, shader);
  };
  const link = proto.linkProgram;
  proto.linkProgram = function (program) {
    program.__t = performance.now();
    return link.call(this, program);
  };
  const param = proto.getProgramParameter;
  proto.getProgramParameter = function (program, pname) {
    const before = performance.now();
    const result = param.call(this, program, pname);
    if (pname === this.LINK_STATUS && program.__t !== undefined) {
      const done = performance.now();
      window.__links.push([Math.round(program.__t * 10) / 10, Math.round((done - program.__t) * 10) / 10,
                           (program.__defs || []).join(' | ').slice(0, 3000)]);
      program.__t = undefined;
    }
    return result;
  };
}
"""


def wait_for_night(page: Page, out: Path, index: int) -> None:
    """Waits for a running night, taking a screenshot of the loading screen every few seconds."""
    deadline = time.monotonic() + 120
    next_shot = time.monotonic() + 1.0
    shots = 0
    while time.monotonic() < deadline:
        seen = smoke.probe(page)
        if seen.get("night") and seen.get("running"):
            return
        if time.monotonic() >= next_shot:
            page.screenshot(path=out / f"loading_{index}_{shots:02d}.png")
            shots += 1
            next_shot = time.monotonic() + 2.5
        time.sleep(0.1)
    raise TimeoutError("the night never started running")


def run_once(url: str, out: Path, seconds: float, gpu: bool, index: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        if gpu:
            browser = p.chromium.launch(channel="chrome", headless=True, args=CHROME_FLAGS)
        else:
            browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *CHROME_FLAGS])
        page = browser.new_page(viewport=smoke.VIEWPORT)
        errors: list[str] = []
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.add_init_script("(" + RECORDER_JS.strip() + ")();")
        page.add_init_script("(" + GL_HOOK_JS.strip() + ")();")
        marks: dict[str, float] = {}
        t0 = time.monotonic()
        page.goto(url, wait_until="commit")
        smoke.reach_menu(page)
        marks["menu_s"] = round(time.monotonic() - t0, 2)
        marks["play_pressed"] = page.evaluate("performance.now()")
        smoke.start_solo(page)
        wait_for_night(page, out, index)
        marks["night_running"] = page.evaluate("performance.now()")
        # Walk a square and fire from the first second, as the smoke run does.
        page.mouse.move(640, 360)
        marks["fire_pressed"] = page.evaluate("performance.now()")
        page.mouse.down()
        began = time.monotonic()
        walking = ""
        while time.monotonic() - began < seconds:
            key = smoke.WALK_KEYS[int((time.monotonic() - began) / smoke.WALK_LEG_S) % len(smoke.WALK_KEYS)]
            if key != walking:
                if walking:
                    page.keyboard.up(walking)
                page.keyboard.down(key)
                walking = key
            page.wait_for_timeout(200)
        page.mouse.up()
        if walking:
            page.keyboard.up(walking)
        page.screenshot(path=out / f"night_end_{index}.png")
        frames = page.evaluate("window.__frames")
        links = page.evaluate("window.__links")
        steps = page.evaluate("window.deadnight_marks || []")
        gl = smoke.gl_info(page)
        browser.close()
    return {"marks": marks, "frames": frames, "links": links, "steps": steps, "gl": gl, "errors": errors}


def analyse(run: dict, seconds: float) -> dict:
    """Frame statistics for the play window: from the night's start (the first running frame) on."""
    marks = run["marks"]
    start = marks["night_running"]
    window = [f for f in run["frames"] if start <= f[0] <= start + seconds * 1000]
    deltas = [f[1] for f in window]
    ordered = sorted(deltas)
    worst = sorted(window, key=lambda f: -f[1])[:10]
    loading = [f for f in run["frames"] if marks["play_pressed"] <= f[0] < start]
    loading_worst = sorted(loading, key=lambda f: -f[1])[:5]
    links = run["links"]
    night_links = [li for li in links if start <= li[0] <= start + seconds * 1000]
    # Programs linked in each page frame of the loading screen: a link belongs to the first frame that ends after it.
    ends = [f[0] for f in run["frames"]]
    per_frame: dict[int, int] = {}
    for link in links:
        index = bisect.bisect_left(ends, link[0])
        if index < len(ends) and marks["play_pressed"] <= ends[index] < start:
            per_frame[index] = per_frame.get(index, 0) + 1
    first_zombie = next((f[0] for f in window if f[2] > 0), None)
    return {
        "frames": len(window),
        "p50_ms": ordered[len(ordered) // 2],
        "p99_ms": ordered[int(len(ordered) * 0.99)],
        "max_ms": ordered[-1],
        "over": {f">{t:g}ms": sum(1 for d in deltas if d > t) for t in THRESHOLDS_MS},
        "worst": [{"at_s": round((f[0] - start) / 1000, 2), "ms": f[1], "alive": f[2]} for f in worst],
        "loading_worst": [{"at_s": round((f[0] - start) / 1000, 2), "ms": f[1]} for f in loading_worst],
        "loading": {
            "seconds": round((start - marks["play_pressed"]) / 1000, 2),
            "longest_frame_ms": loading_worst[0][1] if loading_worst else 0,
            "frames_over_250ms": sum(1 for f in loading if f[1] > 250),
            "frames_over_1s": sum(1 for f in loading if f[1] > 1000),
            "most_programs_in_a_frame": max(per_frame.values(), default=0),
        },
        "programs_linked_total": len(links),
        "programs_linked_in_play": len(night_links),
        "link_ms_in_play": round(sum(li[1] for li in night_links), 1),
        "links_in_play": [
            {"at_s": round((li[0] - start) / 1000, 2), "ms": li[1], "defs": li[2][:300]}
            for li in sorted(night_links, key=lambda li: li[0])
        ],
        "first_zombie_at_s": None if first_zombie is None else round((first_zombie - start) / 1000, 2),
        "load_press_to_running_s": round((start - marks["play_pressed"]) / 1000, 2),
        "menu_s": marks["menu_s"],
    }


def chart(run: dict, summary: dict, path: Path, title: str, seconds: float) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    start = run["marks"]["night_running"]
    play_pressed = run["marks"]["play_pressed"]
    fig, (loading, night) = plt.subplots(1, 2, figsize=(12, 4.2), dpi=110, gridspec_kw={"width_ratios": [1, 3]})
    before = [f for f in run["frames"] if play_pressed <= f[0] < start]
    during = [f for f in run["frames"] if start <= f[0] <= start + seconds * 1000]
    loading.bar(
        [(f[0] - play_pressed) / 1000 for f in before], [f[1] for f in before], width=0.1, color="#7a7a7a", linewidth=0
    )
    loading.set_title(
        f"Play pressed to night running\n({summary['load_press_to_running_s']:.1f} s; the loading screen)",
        fontsize=9,
    )
    loading.set_xlabel("seconds since Play")
    loading.set_ylabel("frame time (ms)")
    night.bar([(f[0] - start) / 1000 for f in during], [f[1] for f in during], width=0.03, color="#3b6fd4", linewidth=0)
    night.axhline(16.7, color="#2a9d4a", linewidth=0.8, linestyle=":")
    night.axhline(33.4, color="#d98c1f", linewidth=0.8, linestyle="--")
    night.set_ylim(0, max(120, summary["max_ms"] * 1.2))
    for w in summary["worst"][:3]:
        night.annotate(f"{w['ms']:.0f} ms", (w["at_s"], w["ms"]), fontsize=8, ha="left", va="bottom", color="#b00020")
    night.set_xlabel("seconds since the night started running")
    night.set_title(
        f"{title}: worst {summary['max_ms']:.0f} ms, p99 {summary['p99_ms']:.0f} ms, "
        f"{summary['over']['>33.4ms']} frames over 33 ms",
        fontsize=9,
    )
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--seconds", type=float, default=NIGHT_SECONDS)
    parser.add_argument("--label", default="run")
    parser.add_argument("--software", action="store_true", help="Chromium's software renderer instead of the GPU")
    args = parser.parse_args()

    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    url = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    summaries = []
    runs = []
    try:
        for i in range(args.runs):
            run = run_once(url, args.out, args.seconds, not args.software, i)
            summary = analyse(run, args.seconds)
            summary["gl"] = run["gl"]
            summary["console_errors"] = run["errors"][:5]
            runs.append(run)
            summaries.append(summary)
            print(json.dumps(summary, indent=2))
    finally:
        if server:
            server.shutdown()
    worst_index = max(range(len(runs)), key=lambda i: summaries[i]["max_ms"])
    chart(
        runs[worst_index],
        summaries[worst_index],
        args.out / f"frame_times_{args.label}.png",
        f"{args.label} (run {worst_index + 1} of {args.runs}, fresh Chrome profile)",
        args.seconds,
    )
    (args.out / f"first_use_{args.label}.json").write_text(json.dumps(summaries, indent=2) + "\n", encoding="utf-8")
    raw = [{"marks": r["marks"], "frames": r["frames"], "links": r["links"], "steps": r["steps"]} for r in runs]
    (args.out / f"frames_{args.label}.json").write_text(json.dumps(raw), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
