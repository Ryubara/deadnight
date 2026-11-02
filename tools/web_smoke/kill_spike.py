"""What a kill costs in the web build: the bot plays a quick night and every frame is logged.

The game, started with `?bench` in its address, plays a night with the autopilot (`KillBench`), logs every frame
(`PerfLog`: the time since the frame before, and what `PerfProbe` timed and counted in it) and publishes the log as
`window.deadnightPerf` after `bench_seconds`. This script serves the exported build, runs it in a fresh Chrome profile,
and reports how long the frames with a kill, a zombie appearing or a zombie leaving take next to the others.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 --with matplotlib python tools/web_smoke/kill_spike.py build/web build/kill_spike

Options: `--seconds S` (the night's length, default 70), `--label before|after` names the chart and the report,
`--unpaced` lets the page run faster than the display (frame times then show the work, not the 60 Hz tick).
`--throttle N` slows the page's processor N times (a weaker machine). `--from-json FILE` reports a log already taken (a desktop run: `godot --path game -- --bench --out=FILE`).
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
import first_use
import smoke

NIGHT_SECONDS = 70.0
# Frames longer than these are a visible hitch at 60 Hz (two frames, three, six).
THRESHOLDS_MS = (33.4, 50.0, 100.0)
CHROME_FLAGS = ["--enable-precise-memory-info"]
# Frames before and after a kill that the chart lines up.
SHOPPING_EVENTS = ("ev.door_opened", "ev.purchase_made", "ev.circuit_changed")
SHOP_BEFORE_MS = 500.0
SHOP_AFTER_MS = 1500.0
WINDOW_BEFORE = 5
WINDOW_AFTER = 150
# A frame counts as a spike when it takes this much longer than the median frame.
SPIKE_OVER_MEDIAN_MS = 4.0


def run_once(build: str, seconds: float, unpaced: bool, out: Path, throttle: float = 1.0) -> dict:
    """Plays the bench in the browser and returns the game's report."""
    deployed = build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(build))
    base = build if deployed else f"http://127.0.0.1:{port}/index.html"
    url = f"{base}{'&' if '?' in base else '?'}bench&bench_seconds={seconds:g}"
    try:
        with sync_playwright() as p:
            args = [*CHROME_FLAGS, *(smoke.UNPACED if unpaced else [])]
            browser = p.chromium.launch(channel="chrome", headless=True, args=args)
            page = browser.new_page(viewport=smoke.VIEWPORT)
            errors: list[str] = []
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: errors.append(str(e)))
            if throttle > 1.0:
                # A slower processor: the page's work takes this many times longer (Chrome DevTools).
                session = page.context.new_cdp_session(page)
                session.send("Emulation.setCPUThrottlingRate", {"rate": throttle})
            page.add_init_script("(" + first_use.GL_HOOK_JS.strip() + ")();")
            page.goto(url, wait_until="commit")
            deadline = time.monotonic() + smoke.LOAD_TIMEOUT_S + seconds + 120
            report = None
            while time.monotonic() < deadline:
                text = page.evaluate("window.deadnightPerf || null")
                if text:
                    report = json.loads(text)
                    break
                time.sleep(0.5)
            if report is None:
                raise TimeoutError("the bench never published its log")
            report["links"] = page.evaluate("window.__links")
            report["gl"] = smoke.gl_info(page)
            report["errors"] = errors[:5]
            page.screenshot(path=out / "bench_end.png")
            browser.close()
    finally:
        if server:
            server.shutdown()
    return report


def percentile(values: list[float], share: float) -> float:
    ordered = sorted(values)
    return ordered[min(int(len(ordered) * share), len(ordered) - 1)]


def fight_start(report: dict) -> float:
    """When the first round began, in milliseconds on the log's clock: before it the bot walks to its post."""
    start = report["started_at"] * 1000
    return next((r["t"] for r in report["rows"] if r["t"] >= start and r["counts"].get("ev.round_started")), start)


def play_frames(report: dict) -> list[int]:
    """The rows of the fight: from the first round on, without the frames around shopping."""
    rows = report["rows"]
    begun = fight_start(report)
    # Shopping (a door opens and the lot's navigation is baked again, a breaker is thrown and the lamps change) is not
    # shooting or killing: the frames around it are left out and counted. A fighting-only bench has none.
    shopping = [r["t"] for r in rows if any(r["counts"].get(k) for k in SHOPPING_EVENTS)]
    return [
        i
        for i, r in enumerate(rows)
        if r["t"] >= begun and not any(-SHOP_BEFORE_MS <= r["t"] - t <= SHOP_AFTER_MS for t in shopping)
    ]


def analyse(report: dict) -> dict:
    """Frame statistics for the night, by what happened in the frame."""
    rows = report["rows"]
    start = report["started_at"] * 1000
    begun = fight_start(report)
    play = play_frames(report)
    left_out = sum(1 for r in rows if r["t"] >= begun) - len(play)
    first, last = play[0], play[-1]
    dts = [rows[i]["dt"] for i in play]
    median = statistics.median(dts)

    def group(pick) -> dict:
        values = [rows[i]["dt"] for i in play if pick(rows[i]["counts"])]
        if not values:
            return {"frames": 0}
        return {
            "frames": len(values),
            "mean_ms": round(statistics.fmean(values), 2),
            "median_ms": round(statistics.median(values), 2),
            "p95_ms": round(percentile(values, 0.95), 2),
            "max_ms": round(max(values), 2),
            "over_median_by_ms": round(statistics.fmean(values) - median, 2),
        }

    kill_frames = [i for i in play if rows[i]["counts"].get("kill")]
    # Frames in the 40 after a kill (the death, the fall, the leaving), whatever else they hold.
    after = sorted({j for i in kill_frames for j in range(i, min(i + 40, last))})
    spikes = [i for i in play if rows[i]["dt"] > median + SPIKE_OVER_MEDIAN_MS]
    worst = sorted(play, key=lambda i: -rows[i]["dt"])[:12]

    def describe(i: int) -> dict:
        r = rows[i]
        top = sorted(r["usec"].items(), key=lambda kv: -kv[1])[:6]
        return {
            "at_s": round((r["t"] - start) / 1000, 2),
            "ms": r["dt"],
            "counts": r["counts"],
            "objects": r["objects"],
            "resources": r["resources"],
            "nodes": r["nodes"],
            "probes_ms": {k: round(v / 1000, 2) for k, v in top if v > 200},
        }

    # Programs the page linked while the night ran: the page's clock, lined up with the log's by its origin.
    origin = report.get("page_origin_ms", 0.0)
    play_origin = origin + begun
    links = [li for li in report.get("links", []) if li[0] >= play_origin]
    # What a kill leaves behind: objects, resources and nodes one frame before and 90 frames after.
    leaks = []
    for i in kill_frames:
        if i - 1 >= first and i + 90 < len(rows):
            b, a = rows[i - 1], rows[i + 90]
            leaks.append((a["resources"] - b["resources"], a["objects"] - b["objects"]))
    return {
        "kills": report["kills"],
        "round": report["round"],
        "frames": len(play),
        "frames_left_out_for_shopping": left_out,
        "median_ms": round(median, 2),
        "p99_ms": round(percentile(dts, 0.99), 2),
        "max_ms": round(max(dts), 2),
        "over": {f">{t:g}ms": sum(1 for d in dts if d > t) for t in THRESHOLDS_MS},
        "by_frame_kind": {
            "ordinary": group(lambda c: not c),
            "shot": group(lambda c: c.get("ev.shot_fired", 0) > 0 and not c.get("kill")),
            "kill": group(lambda c: c.get("kill", 0) > 0),
            "zombie_appears": group(lambda c: c.get("view_added", 0) > 0),
            "zombie_leaves": group(lambda c: c.get("view_removed", 0) > 0),
        },
        "frames_after_a_kill": {
            "frames": len(after),
            "mean_ms": round(statistics.fmean(rows[j]["dt"] for j in after), 2) if after else 0,
            "max_ms": round(max((rows[j]["dt"] for j in after), default=0), 2),
            "over_33ms": sum(1 for j in after if rows[j]["dt"] > 33.4),
        },
        "spike_frames": len(spikes),
        "spikes_with_a_kill": sum(1 for i in spikes if rows[i]["counts"].get("kill")),
        "spikes_with_a_zombie_added": sum(1 for i in spikes if rows[i]["counts"].get("view_added")),
        "spikes_with_a_zombie_removed": sum(1 for i in spikes if rows[i]["counts"].get("view_removed")),
        "resources_change_per_kill_median": statistics.median([r for r, _ in leaks]) if leaks else None,
        "worst": [describe(i) for i in worst],
        "programs_linked_in_play": len(links),
        "link_ms_in_play": round(sum(li[1] for li in links), 1),
        "links_in_play": [
            {"at_s": round((li[0] - play_origin) / 1000, 2), "ms": li[1], "defs": li[2][:200]} for li in links
        ],
        "gl": report.get("gl", ""),
        "console_errors": report.get("errors", []),
    }


def chart(report: dict, summary: dict, path: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rows = report["rows"]
    start = fight_start(report)
    play = play_frames(report)
    kills = [i for i in play if rows[i]["counts"].get("kill")]
    # A shot that killed is a kill; the others are shots.
    shots = [i for i in play if rows[i]["counts"].get("ev.shot_fired") and not rows[i]["counts"].get("kill")]
    fig, axes = plt.subplots(3, 1, figsize=(12, 10), dpi=110, gridspec_kw={"height_ratios": [1.0, 1, 1]})
    top = axes[0]
    seconds = [(rows[i]["t"] - start) / 1000 for i in play]
    top.bar(seconds, [rows[i]["dt"] for i in play], width=0.03, color="#3b6fd4", linewidth=0)
    for i in kills:
        top.axvline((rows[i]["t"] - start) / 1000, color="#d62728", linewidth=0.6, alpha=0.5)
    top.axhline(16.7, color="#2a9d4a", linewidth=0.8, linestyle=":")
    top.axhline(33.4, color="#d98c1f", linewidth=0.8, linestyle="--")
    top.set_ylim(0, max(50, summary["max_ms"] * 1.15))
    top.set_xlabel("seconds since the first round began (red lines: kills; dotted 16.7 ms, dashed 33.4 ms)")
    top.set_ylabel("frame time (ms)")
    top.set_title(
        f"{title}: {summary['kills']} kills, worst {summary['max_ms']:.0f} ms, p99 {summary['p99_ms']:.0f} ms, "
        f"{summary['over']['>33.4ms']} frames over 33 ms",
        fontsize=10,
    )
    ceiling = 30.0
    for axis, frames, label in ((axes[1], shots, "a shot"), (axes[2], kills, "a kill")):
        offsets = range(-WINDOW_BEFORE, WINDOW_AFTER)
        mean_line, worst_line, median_line = [], [], []
        for k in offsets:
            column = [rows[i + k]["dt"] for i in frames if 0 <= i + k < len(rows)]
            mean_line.append(statistics.fmean(column) if column else 0)
            median_line.append(statistics.median(column) if column else 0)
            worst_line.append(max(column) if column else 0)
        axis.plot(list(offsets), worst_line, color="#d62728", linewidth=1, label="worst")
        axis.plot(list(offsets), mean_line, color="#7a7a7a", linewidth=1, label="mean")
        axis.plot(list(offsets), median_line, color="#3b6fd4", linewidth=1.6, label="median")
        axis.axhline(summary["median_ms"], color="#2a9d4a", linewidth=0.8, linestyle=":", label="an ordinary frame")
        axis.axhline(16.7, color="#d98c1f", linewidth=0.8, linestyle="--", label="60 Hz budget")
        axis.axvline(0, color="#7a7a7a", linewidth=0.6)
        axis.set_xlim(-WINDOW_BEFORE, 40)
        axis.set_ylim(0, ceiling)
        axis.set_xlabel(f"frames since {label} ({len(frames)} of them; 0 is the frame it was fired or killed in)")
        axis.set_ylabel("frame time (ms)")
        axis.legend(fontsize=8, loc="upper right", ncol=5)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", nargs="?", help="folder with the exported index.html, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--seconds", type=float, default=NIGHT_SECONDS)
    parser.add_argument("--label", default="run")
    parser.add_argument("--unpaced", action="store_true")
    parser.add_argument("--throttle", type=float, default=1.0, help="slow the page's processor this many times")
    parser.add_argument("--from-json", type=Path, help="report a log already taken instead of running a browser")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.from_json:
        report = json.loads(args.from_json.read_text(encoding="utf-8"))
    else:
        report = run_once(args.build, args.seconds, args.unpaced, args.out, args.throttle)
        (args.out / f"kill_log_{args.label}.json").write_text(json.dumps(report), encoding="utf-8")
    summary = analyse(report)
    print(json.dumps(summary, indent=2))
    (args.out / f"kill_spike_{args.label}.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    chart(report, summary, args.out / f"kill_frames_{args.label}.png", args.label)
    return 0


if __name__ == "__main__":
    sys.exit(main())
