"""Draws the loading screen of two runs of `first_use.py` one above the other: the frame times from pressing Play to a
running night, on one scale, so a long frame (a page that does not move) shows as a tall bar.

    uv run --with matplotlib python tools/web_smoke/compare_loading.py before/frames_before.json after/frames_after.json \
        loading_before_after.png

Each file is the `frames_<label>.json` of `first_use.py`; the first run in it is drawn, or `--run N` another one. The
steps the game marked (`WebProbe.mark`: the loading screen's own text) are drawn as faint lines when the file has them.
"""

from __future__ import annotations

import argparse
import bisect
import json
from pathlib import Path


def load(path: Path, run: int) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))[run]
    pressed = data["marks"]["play_pressed"]
    running = data["marks"]["night_running"]
    frames = [(f[0] - pressed, f[1]) for f in data["frames"] if pressed <= f[0] <= running]
    ends = [f[0] for f in data["frames"]]
    per_frame: dict[int, int] = {}
    for link in data["links"]:
        index = bisect.bisect_left(ends, link[0])
        if index < len(ends) and pressed <= ends[index] <= running:
            per_frame[index] = per_frame.get(index, 0) + 1
    return {
        "frames": frames,
        "seconds": (running - pressed) / 1000,
        "longest": max((f[1] for f in frames), default=0),
        "over_1s": sum(1 for f in frames if f[1] > 1000),
        "over_250": sum(1 for f in frames if f[1] > 250),
        "programs_in_a_frame": max(per_frame.values(), default=0),
        "steps": [(t - pressed, label) for label, t in data.get("steps", []) if pressed <= t <= running],
    }


def main() -> int:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--run", type=int, default=0)
    parser.add_argument("--titles", nargs=2, default=("Before", "After"))
    args = parser.parse_args()

    runs = [load(args.before, args.run), load(args.after, args.run)]
    top = max(run["longest"] for run in runs) * 1.15 / 1000
    longest_seconds = max(run["seconds"] for run in runs)
    fig, axes = plt.subplots(2, 1, figsize=(11, 6.4), dpi=110, sharex=True, sharey=True)
    for axis, run, title, colour in zip(axes, runs, args.titles, ("#b3402a", "#2f6fb0"), strict=True):
        for at, _label in run["steps"]:
            axis.axvline(at / 1000, color="#999999", linewidth=0.3, alpha=0.6)
        axis.bar([f[0] / 1000 for f in run["frames"]], [f[1] / 1000 for f in run["frames"]], width=0.06, color=colour)
        axis.axhline(1.0, color="#777777", linewidth=0.8, linestyle=":")
        axis.set_ylim(0, top)
        axis.set_xlim(0, longest_seconds * 1.02)
        axis.set_ylabel("frame time (s)")
        axis.set_title(
            f"{title}: {run['seconds']:.1f} s from Play to a running night; longest frame {run['longest'] / 1000:.1f} s; "
            f"{run['over_1s']} frames over 1 s; most programs linked in one frame {run['programs_in_a_frame']}",
            fontsize=9,
            loc="left",
        )
    axes[1].set_xlabel("seconds since Play was pressed (the loading screen is up the whole time)")
    fig.tight_layout()
    fig.savefig(args.out)
    print(
        json.dumps(
            {t: {k: v for k, v in r.items() if k not in ("frames", "steps")} for t, r in zip(args.titles, runs)},
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
