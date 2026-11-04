"""Big crowds in a browser: the autopilot plays a night and the frame times of each round are reported (issue #171).

The game, started with `?autopilot` in its address, lets the bot play from its shoulder camera under the shipped rules
with a player who cannot die (`AutopilotRun`, `game/tools/bench/autopilot_run.gd`), and publishes
`window.deadnightRounds` when it has played the round asked for. This script serves the exported build (or takes a
URL), runs it in a fresh browser profile, takes a screenshot whenever the crowd passes 10, 20, 40, 80 zombies on the
lot, and prints and saves for each round the frames' mean, median, 95th and 99th percentile and worst, the worst
second and the zombies on the lot. Recorded, never gated.

    uv run --with playwright==1.64.1 --with matplotlib python tools/web_smoke/autopilot_night.py build/web build/autopilot \\
        --gpu --unpaced --rounds 6 --count 3 --alive 40

Options: `--gpu` the installed Chrome with this machine's GPU (without it the headless shell's software renderer, which
is what CI runs), `--unpaced` lets the page run faster than the display (frame times then show the work, not the
display's refresh), `--throttle N` slows the page's processor N times, `--rounds`, `--hold`, `--count`, `--alive`,
`--tough`, `--break`, `--seconds` as `AutopilotRun` reads them, `--label NAME` names the files, `--timeout S` how long to wait.
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
# Screenshot the first time the zombies on the lot reach one of these.
SHOT_AT = (10, 20, 40, 80)
DEFAULT_TIMEOUT_S = 900


def run_once(args: argparse.Namespace, out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    deployed = args.build.startswith(("http://", "https://"))
    server, port = (None, 0) if deployed else smoke.serve(Path(args.build))
    base = smoke.probing(args.build) if deployed else f"http://127.0.0.1:{port}/index.html"
    query = f"autopilot&rounds={args.rounds}&hold={args.hold:g}&count={args.count:g}&alive={args.alive}"
    query += f"&tough={args.tough:g}"
    if args.crowd:
        query += f"&crowd={args.crowd}"
    query += f"&break={args.break_seconds:g}&seconds={args.seconds:g}"
    url = f"{base}{'&' if '?' in base else '?'}{query}"
    report: dict = {}
    errors: list[str] = []
    try:
        with sync_playwright() as p:
            if args.gpu:
                flags = [*CHROME_FLAGS, *(smoke.UNPACED if args.unpaced else [])]
                browser = p.chromium.launch(channel="chrome", headless=True, args=flags)
            else:
                flags = [*smoke.SOFTWARE_GL, *CHROME_FLAGS, *(smoke.UNPACED if args.unpaced else [])]
                browser = p.chromium.launch(headless=True, args=flags)
            page = browser.new_page(viewport=smoke.VIEWPORT)
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: errors.append(str(e)))
            if args.throttle > 1.0:
                session = page.context.new_cdp_session(page)
                session.send("Emulation.setCPUThrottlingRate", {"rate": args.throttle})
            page.goto(url, wait_until="commit")
            shots = list(SHOT_AT)
            deadline = time.monotonic() + args.timeout
            started = time.monotonic()
            while time.monotonic() < deadline:
                text = page.evaluate("window.deadnightRounds || null")
                if text:
                    report = json.loads(text)
                    break
                state = smoke.probe(page)
                if shots and state.get("alive", 0) >= shots[0]:
                    page.screenshot(path=out / f"crowd_{shots[0]}.png")
                    shots.pop(0)
                time.sleep(0.5)
            else:
                report = {"error": "the autopilot run never reported", "last": smoke.probe(page)}
            report["wall_s"] = round(time.monotonic() - started, 1)
            report["gl"] = smoke.gl_info(page)
            report["browser"] = "chrome (gpu)" if args.gpu else "headless shell (software)"
            report["unpaced"] = args.unpaced
            report["throttle"] = args.throttle
            page.screenshot(path=out / "end.png")
            browser.close()
    finally:
        if server:
            server.shutdown()
    report["console_errors"] = errors[:5]
    return report


def by_alive_table(report: dict) -> str:
    lines = ["alive from  frames  seconds  mean  p50   p95   p99    max  worst-second  over 33ms  alive peak / mean"]
    for r in report.get("by_alive", []):
        lines.append(
            f"{r['alive_from']:>10} {r['frames']:>7} {r['seconds']:>8} {r['mean_ms']:>5} {r['p50_ms']:>4} "
            f"{r['p95_ms']:>5} {r['p99_ms']:>5} {r['max_ms']:>6} {r['worst_second_ms']:>13} "
            f"{r['frames_over_33ms']:>10}  {r['alive_peak']:>5} / {r['alive_mean']}"
        )
    return "\n".join(lines)


def table(report: dict) -> str:
    lines = [
        "round  frames  seconds  mean  p50   p95   p99    max  worst-second  over 33ms  alive peak / mean",
    ]
    for r in report.get("rounds", []):
        lines.append(
            f"{r['round']:>5} {r['frames']:>7} {r['seconds']:>8} {r['mean_ms']:>5} {r['p50_ms']:>4} {r['p95_ms']:>5} "
            f"{r['p99_ms']:>5} {r['max_ms']:>6} {r['worst_second_ms']:>13} {r['frames_over_33ms']:>10}  "
            f"{r['alive_peak']:>5} / {r['alive_mean']}"
        )
    return "\n".join(lines)


def chart(report: dict, path: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rounds = report.get("rounds", [])
    if not rounds:
        return
    x = [r["round"] for r in rounds]
    fig, (top, bottom) = plt.subplots(2, 1, figsize=(9, 6), dpi=110, sharex=True)
    top.plot(x, [r["p95_ms"] for r in rounds], "o-", color="#2f6fb0", label="frame p95")
    top.plot(x, [r["worst_second_ms"] for r in rounds], "s--", color="#b3402a", label="worst second (mean)")
    top.plot(x, [r["p50_ms"] for r in rounds], "^:", color="#2a9d4a", label="frame median")
    top.axhline(16.7, color="#888", linewidth=0.8, linestyle=":")
    top.set_ylabel("ms per frame")
    top.legend(fontsize=8)
    top.set_title(title, fontsize=9)
    bottom.bar(x, [r["alive_peak"] for r in rounds], color="#7a7a7a", label="alive peak")
    bottom.plot(x, [r["alive_mean"] for r in rounds], "o-", color="#d98c1f", label="alive mean")
    bottom.set_ylabel("zombies on the lot")
    bottom.set_xlabel("round")
    bottom.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="folder with the exported index.html, or a URL")
    parser.add_argument("out", type=Path)
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--unpaced", action="store_true")
    parser.add_argument("--throttle", type=float, default=1.0)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--hold", type=float, default=20.0)
    parser.add_argument("--count", type=float, default=1.0)
    parser.add_argument("--alive", type=int, default=0)
    parser.add_argument("--crowd", type=int, default=0, help="zombies the first round brings (0: the tuned 6)")
    parser.add_argument("--tough", type=float, default=1.0, help="health of the dead, times (the crowd grows)")
    parser.add_argument("--break", dest="break_seconds", type=float, default=0.0)
    parser.add_argument("--seconds", type=float, default=600.0)
    parser.add_argument("--label", default="run")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_S)
    args = parser.parse_args()

    report = run_once(args, args.out)
    print(table(report))
    print(by_alive_table(report))
    print(json.dumps({k: v for k, v in report.items() if k != "rounds"}))
    (args.out / f"autopilot_{args.label}.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    chart(report, args.out / f"autopilot_{args.label}.png", f"{args.label}: {report.get('browser', '')}")
    return 1 if report.get("error") else 0


if __name__ == "__main__":
    sys.exit(main())
