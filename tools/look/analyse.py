"""Reads csv files written by game/tests/captures/look_lag_probe.gd and prints what the frames showed.

The probe posts a recorded mouse path after every frame; the engine handles it at once, so frame k
shows the path posted up to the end of frame k-1. For every frame this compares what the hand did
(`want`, the turn the path asks for) with the view that was drawn (the camera's own yaw) and with
the rig's yaw (what the player node holds). Columns:

- total: the drawn view's turn at the end minus the hand's turn (degrees; 0 is one to one)
- over: the biggest distance, in degrees, between the drawn view and the hand in one frame
- back: frames where the drawn view moved against the hand (the hand moved on, the view went back)
- phantom: frames where the view moved while the hand did not
- rmse: root mean square of (drawn step - hand step) per frame, in degrees

    python tools/look/analyse.py <csv> [<csv> ...] [--plot out.png]
"""

import math
import statistics
import sys

DEG = 180.0 / math.pi
SKIP_SECONDS = 0.5


def load(path):
    rows = []
    meta = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("frame") or not line:
                continue
            if line.startswith("#"):
                for part in line[1:].split():
                    key, value = part.split("=")
                    meta[key] = float(value)
                continue
            f = line.split(",")
            rows.append(
                {
                    "frame": int(f[0]),
                    "t": int(f[1]) / 1e6,
                    "dt": int(f[2]) / 1e6,
                    "yaw": float(f[3]),
                    "cam_yaw": float(f[5]),
                    "aim_yaw": float(f[6]),
                    "ticks": int(f[11]),
                    "px": float(f[12]),
                }
            )
    return meta, [r for r in rows if r["t"] >= SKIP_SECONDS]


def wrap(angle):
    return (angle + math.pi) % (2 * math.pi) - math.pi


def analyse(path):
    meta, rows = load(path)
    rpp = meta["rpp"]
    yaw0 = meta["yaw0"]
    rmse, back, phantom, drawn_err, rig_err = [], 0, 0, [], []
    hand_steps, drawn_steps = [], []
    for i in range(1, len(rows)):
        cur, prev = rows[i], rows[i - 1]
        want = wrap(yaw0 - rpp * cur["px"])
        drawn_err.append(abs(wrap(cur["cam_yaw"] - want)))
        rig_err.append(abs(wrap(cur["yaw"] - want)))
        hand = wrap(-rpp * (cur["px"] - prev["px"]))
        drawn = wrap(cur["cam_yaw"] - prev["cam_yaw"])
        hand_steps.append(hand * DEG)
        drawn_steps.append(drawn * DEG)
        rmse.append((drawn - hand) ** 2)
        if abs(hand) > 0.05 / DEG and drawn * hand < 0:
            back += 1
        if abs(hand) < 1e-9 and abs(drawn) > 0.05 / DEG:
            phantom += 1
    dts = [r["dt"] for r in rows]
    last = rows[-1]
    return {
        "file": path.replace("\\", "/").split("/")[-1].removesuffix(".csv"),
        "fps": 1.0 / statistics.mean(dts),
        "dtmax": max(dts) * 1000,
        "frames": len(rows),
        "total": wrap(last["cam_yaw"] - (yaw0 - rpp * last["px"])) * DEG,
        "rig_total": wrap(last["yaw"] - (yaw0 - rpp * last["px"])) * DEG,
        "over": max(drawn_err) * DEG,
        "rig_over": max(rig_err) * DEG,
        "back": back,
        "phantom": phantom,
        "rmse": math.sqrt(sum(rmse) / len(rmse)) * DEG,
        "hand_steps": hand_steps,
        "drawn_steps": drawn_steps,
        "t": [r["t"] for r in rows[1:]],
    }


def plot(results, out):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(results), 1, figsize=(10, 2.4 * len(results)), sharex=False)
    if len(results) == 1:
        axes = [axes]
    for ax, r in zip(axes, results):
        ax.plot(r["t"], r["hand_steps"], ".-", lw=0.8, ms=3, label="hand (path posted last frame)")
        ax.plot(r["t"], r["drawn_steps"], ".-", lw=0.8, ms=3, label="drawn view")
        ax.set_title(
            f"{r['file']}: {r['fps']:.0f} fps, over {r['over']:.2f} deg, back {r['back']}, phantom {r['phantom']}",
            fontsize=9,
        )
        ax.set_ylabel("turn per frame (deg)")
        ax.set_xlim(2.0, 4.0)
        ax.legend(fontsize=7, loc="upper right")
    axes[-1].set_xlabel("seconds")
    fig.tight_layout()
    fig.savefig(out, dpi=110)


if __name__ == "__main__":
    args = sys.argv[1:]
    out = None
    if "--plot" in args:
        at = args.index("--plot")
        out = args[at + 1]
        args = args[:at] + args[at + 2 :]
    results = [analyse(p) for p in args]
    print(
        f"{'run':26s} {'fps':>6s} {'dtmax':>6s} {'total':>7s} {'rig':>6s} {'over':>7s} "
        f"{'rigover':>7s} {'back':>5s} {'phantom':>7s} {'rmse':>6s}"
    )
    for r in results:
        print(
            f"{r['file']:26s} {r['fps']:6.1f} {r['dtmax']:6.1f} {r['total']:7.3f} "
            f"{r['rig_total']:6.3f} {r['over']:7.3f} {r['rig_over']:7.3f} {r['back']:5d} "
            f"{r['phantom']:7d} {r['rmse']:6.3f}"
        )
    if out:
        plot(results, out)
