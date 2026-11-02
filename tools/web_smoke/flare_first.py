"""The first flare shot of a night in the browser: frames and GL programs in the seconds after the trigger (issue #502).

The flare is the effect the maintainer saw hitch the page online (#483). This plays a solo night in a fresh Chrome
profile (Chrome keeps a GPU program cache in its profile, so every run starts from an empty one), gives the soldier the
flare gun through the flash probe (`?probe=flash`, game/core/flash_web_probe.gd), waits for it to be in the hand, fires
once with a short press and records every requestAnimationFrame delta and every WebGL program linked (with its
`#define` list) from the press on, then fires a second time for comparison. The numbers are the worst frame, the frames
over 33 and 100 ms and the programs linked in the first second and in the three seconds after each trigger.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/flare_first.py build/web build/flare --runs 3

Exits 1 when a frame after the first shot is over `--max-ms` (default 100) or a program is linked in the second after
it. `--software` uses Chromium's software renderer, where frame times are not comparable (the program count is).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import first_use
import smoke

WATCH_S = 3.0
SETTLE_S = 2.5
SECOND_SHOT_AFTER_S = 3.5
MAX_FRAME_MS = 100.0
CHROME_FLAGS = ["--enable-precise-memory-info"]


def window_stats(run: dict, start: float, seconds: float) -> dict:
    """The frames and programs between `start` and `start + seconds` (page clock, milliseconds)."""
    end = start + seconds * 1000
    frames = [f for f in run["frames"] if start <= f[0] <= end]
    links = [li for li in run["links"] if start <= li[0] <= end]
    deltas = [f[1] for f in frames]
    worst = max(frames, key=lambda f: f[1]) if frames else None
    return {
        "frames": len(frames),
        "worst_ms": worst[1] if worst else 0.0,
        "worst_at_ms": round(worst[0] - start, 1) if worst else 0.0,
        "over_33ms": sum(1 for d in deltas if d > 33.4),
        "over_100ms": sum(1 for d in deltas if d > 100.0),
        "programs": len(links),
        "link_ms": round(sum(li[1] for li in links), 1),
        "defs": [li[2][:200] for li in sorted(links, key=lambda li: li[0])][:12],
    }


def run_once(url: str, out: Path, gpu: bool, index: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        if gpu:
            browser = p.chromium.launch(channel="chrome", headless=True, args=[*CHROME_FLAGS, *smoke.mute_args()])
        else:
            browser = p.chromium.launch(headless=True, args=[*smoke.SOFTWARE_GL, *CHROME_FLAGS, *smoke.mute_args()])
        page = browser.new_page(viewport=smoke.VIEWPORT)
        errors: list[str] = []
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.add_init_script("(" + first_use.RECORDER_JS.strip() + ")();")
        page.add_init_script("(" + first_use.GL_HOOK_JS.strip() + ")();")
        page.goto(url, wait_until="commit")
        smoke.reach_menu(page)
        smoke.start_solo(page)
        smoke.wait_for_night(page)
        page.mouse.move(640, 360)
        page.wait_for_timeout(int(SETTLE_S * 1000))
        page.evaluate("() => { window.deadnight.flashGive = 'flare_gun'; }")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and page.evaluate("() => window.deadnight.flashHave") != "flare_gun":
            page.wait_for_timeout(100)
        page.wait_for_timeout(int(SETTLE_S * 1000))
        shots = []
        for number in (1, 2):
            fired = page.evaluate("performance.now()")
            page.mouse.down()
            page.wait_for_timeout(60)
            page.mouse.up()
            page.wait_for_timeout(int(WATCH_S * 1000))
            page.screenshot(path=out / f"flare_{index}_shot{number}.png")
            shots.append(fired)
            if number == 1:
                page.wait_for_timeout(int((SECOND_SHOT_AFTER_S - WATCH_S) * 1000))
        frames = page.evaluate("window.__frames")
        links = page.evaluate("window.__links")
        gl = smoke.gl_info(page)
        browser.close()
    return {"shots": shots, "frames": frames, "links": links, "gl": gl, "errors": errors}


def chart(runs: list[dict], summaries: list[dict], path: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, len(runs), figsize=(4.2 * len(runs), 3.8), dpi=110, squeeze=False)
    for ax, run, summary in zip(axes[0], runs, summaries, strict=True):
        fired = run["shots"][0]
        frames = [f for f in run["frames"] if fired - 500 <= f[0] <= fired + WATCH_S * 1000]
        ax.bar([(f[0] - fired) / 1000 for f in frames], [f[1] for f in frames], width=0.012, color="#3b6fd4")
        for link in run["links"]:
            if fired - 500 <= link[0] <= fired + WATCH_S * 1000:
                ax.axvline((link[0] - fired) / 1000, color="#d98c1f", linewidth=0.6, alpha=0.7)
        ax.axvline(0, color="#b00020", linewidth=1.0)
        ax.axhline(33.4, color="#d98c1f", linewidth=0.6, linestyle="--")
        ax.set_ylim(0, max(60, summary["first_shot"]["worst_ms"] * 1.2))
        ax.set_title(
            f"worst {summary['first_shot']['worst_ms']:.0f} ms, {summary['first_shot']['programs']} programs (3 s)",
            fontsize=9,
        )
        ax.set_xlabel("seconds since the trigger")
        ax.set_ylabel("frame time (ms)")
    fig.suptitle(title, fontsize=10)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--label", default="run")
    parser.add_argument("--max-ms", type=float, default=MAX_FRAME_MS)
    parser.add_argument("--software", action="store_true")
    args = parser.parse_args()
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    base = args.build if deployed else f"http://127.0.0.1:{port}/index.html"
    url = base + ("&" if "?" in base else "?") + "probe=flash"
    runs: list[dict] = []
    summaries: list[dict] = []
    problems: list[str] = []
    try:
        for i in range(args.runs):
            run = run_once(url, args.out, not args.software, i)
            summary = {
                "first_shot": window_stats(run, run["shots"][0], WATCH_S),
                "first_shot_1s": window_stats(run, run["shots"][0], 1.0),
                "second_shot": window_stats(run, run["shots"][1], WATCH_S),
                "console_errors": run["errors"][:5],
                "gl": run["gl"],
            }
            runs.append(run)
            summaries.append(summary)
            print(json.dumps(summary, indent=2))
            if summary["first_shot"]["worst_ms"] > args.max_ms:
                problems.append(f"run {i + 1}: a frame of {summary['first_shot']['worst_ms']} ms after the first shot")
            if summary["first_shot_1s"]["programs"] > 0:
                problems.append(
                    f"run {i + 1}: {summary['first_shot_1s']['programs']} programs linked in the first second"
                )
            problems += [f"run {i + 1}: console error {e}" for e in run["errors"][:3]]
    finally:
        if server:
            server.shutdown()
    args.out.mkdir(parents=True, exist_ok=True)
    chart(
        runs,
        summaries,
        args.out / f"flare_first_{args.label}.png",
        f"First flare shot, {args.label} (fresh Chrome profile)",
    )
    (args.out / f"flare_first_{args.label}.json").write_text(
        json.dumps({"summaries": summaries, "problems": problems}, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"problems": problems}, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
