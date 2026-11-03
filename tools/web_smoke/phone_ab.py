"""Two builds of the web export on the same phone stand-in, taken turn about (issue #728).

`phone_frames.py` compares ways of drawing inside one page. Two builds cannot share a page, so this runs them
turn about, `--rounds` times each, `--minutes` a turn, and pools every turn of a build: on a shared machine each
build then sees the same stretches of the day (a run of one build after the other, once, differed by 10 times:
docs/research/phone-frames.md). It prints the median, p95 and p99 of each build over all its turns, the draw
calls and triangles each published, the heap each turn ended with, and the ratio of the two medians.

    uv run --project <kit>/python gds quiet -- \\
        uv run --with playwright==1.64.1 python tools/web_smoke/phone_ab.py \\
        before=build/before after=build/after <out folder> [--rounds 4] [--minutes 2.5] [--throttle 4] [--software]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import phone_frames


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "builds", nargs=2, help="name=folder[@extra&query] of the two exported builds, first the before"
    )
    parser.add_argument("out")
    parser.add_argument("--rounds", type=int, default=4)
    parser.add_argument("--minutes", type=float, default=2.5)
    parser.add_argument("--throttle", type=float, default=4.0)
    parser.add_argument("--dpr", type=float, default=3.0)
    parser.add_argument("--size", default="844x390")
    parser.add_argument("--unpaced", action="store_true")
    parser.add_argument("--software", action="store_true")
    parser.add_argument("--query", default="count=1")
    parser.add_argument("--label", default="ab")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    builds = []
    for text in args.builds:
        name, rest = text.split("=", 1)
        folder, _, extra = rest.partition("@")
        builds.append((name, folder, extra))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    pooled: dict[str, list[float]] = {name: [] for name, _, _ in builds}
    turns: dict[str, list[dict]] = {name: [] for name, _, _ in builds}
    for round_index in range(args.rounds):
        for name, folder, extra in builds:
            one = argparse.Namespace(
                build=folder,
                out=str(out),
                minutes=args.minutes,
                throttle=args.throttle,
                dpr=args.dpr,
                size=args.size,
                unpaced=args.unpaced,
                software=args.software,
                real=False,
                gc=False,
                arms="",
                block=20.0,
                label=f"{args.label}_{name}_{round_index}",
                query=args.query + ("&" + extra if extra else ""),
            )
            report = phone_frames.run(one)
            pooled[name].extend(report["_deltas"])
            render = report["render"]
            turns[name].append(
                {
                    "round": round_index,
                    "p50_ms": report["overall"].get("p50_ms"),
                    "draw_calls": render["draw_calls_mean"],
                    "draw_calls_3d": render["draw_calls_3d_mean"],
                    "primitives": render["primitives_mean"],
                    "process_ms": render["process_ms_mean"],
                    "render_cpu_ms": render["render_cpu_ms_mean"],
                    "objects": render["objects_mean"],
                    "heap_mb_first": render["heap_mb_first"],
                    "heap_mb_last": render["heap_mb_last"],
                    "alive_mean": render["alive_mean"],
                    "errors": report["console_errors"],
                }
            )
            print(name, round_index, turns[name][-1], flush=True)
    summary = {name: {**phone_frames.describe(deltas), "turns": turns[name]} for name, deltas in pooled.items()}
    first, second = (name for name, _, _ in builds)
    summary["median_ratio"] = round(summary[first]["p50_ms"] / max(summary[second]["p50_ms"], 0.01), 3)
    summary["settings"] = {k: v for k, v in vars(args).items() if k != "builds"}
    (out / f"{args.label}.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
