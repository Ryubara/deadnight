"""Before and after plots of the drawn view against the hand, from two folders of probe csv files.

    uv run --with matplotlib python tools/look/plot_compare.py <before folder> <after folder> <out.png> [run ...]

One row per run (`solo_60`, `solo_30`, `online_15` ...), the left column before, the right after: the turn
the hand asked for (the path posted so far, a line) and the turn the camera was drawn at, per frame (dots), over the
second of the run with the most mouse movement, then the distance between the two per frame.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import analyse

DEG = 180.0 / math.pi


def series(path):
    meta, rows = analyse.load(str(path))
    rpp = meta["rpp"]
    yaw0 = meta["yaw0"]
    hand = [-rpp * r["px"] * DEG for r in rows]
    # The distance between the drawn view and the hand is under half a turn, so it is read modulo a turn.
    drawn = [h + analyse.wrap(r["cam_yaw"] - (yaw0 - rpp * r["px"])) * DEG for h, r in zip(hand, rows)]
    return [r["t"] for r in rows], hand, drawn


def window(times, hand):
    best, best_at = 0.0, 0
    for i in range(len(times)):
        j = i
        while j < len(times) and times[j] - times[i] < 1.0:
            j += 1
        move = abs(hand[j - 1] - hand[i])
        if move > best:
            best, best_at = move, i
    return times[best_at], times[best_at] + 1.0


def main():
    before, after, out = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    runs = sys.argv[4:] or ["solo_60", "solo_30", "online_15"]
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(runs), 2, figsize=(11, 3.1 * len(runs)))
    for row, run in enumerate(runs):
        t0 = None
        for col, folder in enumerate((before, after)):
            t, hand, drawn = series(folder / f"{run}.csv")
            if t0 is None:
                t0, t1 = window(t, hand)
            ax = axes[row][col]
            keep = [i for i, x in enumerate(t) if t0 <= x <= t1]
            xs = [t[i] for i in keep]
            ax.plot(xs, [hand[i] for i in keep], "-", lw=1.2, color="#888", label="hand: path posted so far")
            ax.plot(
                xs,
                [drawn[i] for i in keep],
                "o-",
                ms=3,
                lw=0.8,
                color="#d95f02" if col == 0 else "#1b9e77",
                label="camera as drawn, each frame",
            )
            err = max(abs(drawn[i] - hand[i]) for i in keep)
            ax.set_title(
                f"{'Before' if col == 0 else 'After'}: {run}, most the drawn view is off the hand: {err:.1f} deg",
                fontsize=9,
            )
            ax.set_ylabel("turn (deg)")
            ax.legend(fontsize=7, loc="best")
            if row == len(runs) - 1:
                ax.set_xlabel("seconds")
    fig.tight_layout()
    fig.savefig(out, dpi=110)


if __name__ == "__main__":
    main()
