"""Measure the gusts driving the second map's roof and yard wind (issue #809), on a capture of the map's night.

    uv run --with numpy --with scipy --with matplotlib python tools/audio/gust_levels.py night --ffmpeg <ffmpeg>
        --runs <folder holding roof_on, roof_off, hall_on, hall_off, open_on, open_off> [--out gusts.png]

Each run folder is one run of `game/tests/captures/audio_smallmap_gusts.tscn` (`--stand=roof|hall|open`, `--swell=on|off`,
the same seed): the second map with its yard, the night's wind and the map's own sound (its room tone, roof wind and yard,
started in place of the lot's crickets and highway),
the listener standing in one place, the Ambience bus recorded as `stem_<stand>_<on|off>.wav`, and the log with the `WIND`
lines (each gust) and the `TRACE` lines (ten a second: the gust's swell, the level the roof wind and the yard wind loop
through the first window are at). `on` is the gusts driving the loops, `off` is the same night without it (the loops as they rested before this
change), so the two differ only by what the gust adds.

For each stand it prints the loop's own level (from the trace: where it rests, what it reaches in each gust), the bus's
momentary loudness (LUFS, 400 ms, the pinned ffmpeg's `ebur128`) between gusts and at each gust's peak with and without the
swell, how far the swell raises the bus (the greatest `on - off` in the gust), and the night's integrated loudness and
loudest 400 ms with and without it; `--out` plots the three stands.
"""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from analyze import read_wav
from wind_levels import integrated, momentary_series, parse_log

STANDS = {
    "roof": "upstairs, under the hole in the roof",
    "hall": "the hall, in line with a boarded window",
    "open": "the same window with its boards off",
}
SETTLED = 8.0  # seconds: the beds fade in over 3 s
STEP = 0.1


def parse_trace(path: Path) -> dict[str, np.ndarray]:
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"TRACE ([\d.]+) swell=(-?[\d.]+) roof=(-?[\d.inf]+) yard=(-?[\d.inf]+) blowing=(\d)", line)
        if m:
            rows.append([float(g.replace("inf", "1e9")) for g in m.groups()])
    a = np.array(rows)
    return {"t": a[:, 0], "swell": a[:, 1], "roof": a[:, 2], "yard": a[:, 3], "blowing": a[:, 4]}


def load(ffmpeg: str, folder: Path, stand: str, mode: str, scratch: Path) -> dict:
    run = folder / f"{stand}_{mode}"
    stem = f"stem_{stand}_{mode}.wav"
    data, rate = read_wav(run / stem)
    return {
        "series": momentary_series(ffmpeg, data, rate, scratch),
        "gusts": parse_log(run / "log.txt"),
        "trace": parse_trace(run / "log.txt"),
        "stat": integrated(ffmpeg, run, stem, scratch.with_name("i.wav")),
        "dir": run,
    }


def report(ffmpeg: str, folder: Path, stand: str, tmp: Path) -> dict:
    on = load(ffmpeg, folder, stand, "on", tmp / "a.wav")
    off = load(ffmpeg, folder, stand, "off", tmp / "b.wav")
    gusts = on["gusts"]
    times = np.arange(min(len(on["series"]), len(off["series"]))) * STEP
    blowing = np.zeros(len(times), dtype=bool)
    for g in gusts:
        blowing |= (times >= g["at"]) & (times < g["at"] + g["length"] + 0.5)
    settled = (times > SETTLED) & np.isfinite(off["series"][: len(times)]) & (off["series"][: len(times)] > -70)
    rest_bus = float(np.median(off["series"][: len(times)][settled & ~blowing]))
    tr = on["trace"]
    quiet = (tr["blowing"] == 0) & (tr["t"] > SETTLED)
    loop_key = "roof" if stand == "roof" else "yard"
    rest_loop = float(np.median(tr[loop_key][quiet]))
    print(f"\n== {stand}: {STANDS[stand]}")
    print(
        f"  the {'roof' if stand == 'roof' else 'yard wind (through the first window)'} loop rests at {rest_loop:.1f} dB (its trim and fade);"
        f" the bus between gusts, without the swell: {rest_bus:.1f} LUFS-M (median)"
    )
    print(
        f"  {'at':>6s} {'sec':>5s} {'draw dB':>7s} {'swell':>5s} {'loop peak':>9s} {'loop over rest':>14s}"
        f" {'bus off':>7s} {'bus on':>7s} {'raise':>6s}  file"
    )
    rows = []
    for g in gusts:
        sl = (times >= g["at"]) & (times < g["at"] + g["length"])
        if not sl.any():
            continue
        ts = (tr["t"] >= g["at"]) & (tr["t"] < g["at"] + g["length"])
        loop_peak = float(tr[loop_key][ts].max())
        swell = float(tr["swell"][ts].max())
        peak_off = float(off["series"][: len(times)][sl].max())
        peak_on = float(on["series"][: len(times)][sl].max())
        raise_db = float((on["series"][: len(times)][sl] - off["series"][: len(times)][sl]).max())
        rows.append((swell, loop_peak - rest_loop, peak_off, peak_on, raise_db))
        print(
            f"  {g['at']:6.1f} {g['length']:5.1f} {g['db']:7.1f} {swell:5.2f} {loop_peak:9.1f} {loop_peak - rest_loop:14.1f}"
            f" {peak_off:7.1f} {peak_on:7.1f} {raise_db:6.1f}  {Path(g['file']).stem}"
        )
    if rows:
        a = np.array(rows)
        print(
            f"  {len(rows)} gusts: the loop {a[:, 1].min():.1f} to {a[:, 1].max():.1f} dB over its rest at the gust's peak;"
            f" the bus's peak raised by {a[:, 4].min():.1f} to {a[:, 4].max():.1f} LU (median {np.median(a[:, 4]):.1f}),"
            f" a gust's peak {np.median(a[:, 3]) - rest_bus:.1f} LU over the bus between gusts"
            f" (without the swell {np.median(a[:, 2]) - rest_bus:.1f})"
        )
    for label, key in (("integrated loudness", "lufs"), ("loudest 400 ms", "momentary_max")):
        print(
            f"  {label:20s} without the swell {off['stat'][key]:6.1f}, with it {on['stat'][key]:6.1f}"
            f" ({on['stat'][key] - off['stat'][key]:+.2f} LU)"
        )
    return {"times": times, "on": on, "off": off, "gusts": gusts, "stand": stand}


def plot(results: list[dict], out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(results), 1, figsize=(13, 3.6 * len(results)), sharex=True)
    for ax, r in zip(np.atleast_1d(axes), results, strict=True):
        for g in r["gusts"]:
            ax.axvspan(g["at"], g["at"] + g["length"], color="#9bb7d4", alpha=0.35, lw=0)
        n = len(r["times"])
        ax.plot(
            r["times"],
            r["off"]["series"][:n],
            color="#718096",
            lw=1.0,
            label="before: the loops do not follow the gust",
        )
        ax.plot(r["times"], r["on"]["series"][:n], color="#1a365d", lw=1.2, label="after: the gust raises the loops")
        ax.set_ylabel("LUFS, 400 ms")
        ax.set_title(f"{r['stand']}: {STANDS[r['stand']]}", fontsize=10, loc="left")
        ax.set_xlim(0, 122)
        ax.set_ylim(-42, -26)
        ax.legend(loc="lower right", fontsize=8)
    np.atleast_1d(axes)[-1].set_xlabel("seconds (the gusts shaded)")
    fig.suptitle(
        "The second map's night: the Ambience bus (wind, room tone, roof and yard), with and without the swell"
    )
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print(f"plot: {out}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("night")
    n.add_argument("--ffmpeg", required=True)
    n.add_argument("--runs", type=Path, required=True)
    n.add_argument("--stands", default="roof,hall,open")
    n.add_argument("--out", type=Path)
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        for stand in args.stands.split(","):
            results.append(report(args.ffmpeg, args.runs, stand, Path(tmp)))
    if args.out:
        plot(results, args.out)


if __name__ == "__main__":
    main()
