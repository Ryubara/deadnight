"""Measure the menu's sounds as the player hears them (#894).

    uv run --with numpy --with scipy --with matplotlib python tools/audio/menu_levels.py levels mix.wav bench.log
        [--plot levels.png] [--json out.json]
    uv run --with numpy --with scipy --with matplotlib python tools/audio/menu_levels.py tour mix.wav tour.log
        [--before before.wav before.log] [--plot tour.png]

`levels` reads the recording of `game/tests/captures/audio_menu_levels.tscn` (every sound of the menu's table alone,
through the real service and buses at the default settings) and its log, and prints for each sound the peak (dBFS) and
the loudest 400 ms (LUFS-M, K-weighted, BS.1770) of every variant file and the sound's mean against its target; then
the night's sounds played for scale. It exits 1 when a sound is more than `TOLERANCE_DB` from its target, when a rung of
the weight ladder is not louder than the one below, or when anything clips.

`tour` reads the recording of `game/tests/captures/menu_sfx_tour.tscn` (a walk through the real menus) and its log: how
many sounds each kind made, the most hints in any second, the least gap between hints and between ticks, the peak of the
mix, and, with `--before`, the same for the recording of the menus without the sounds, and a plot of both.

The recording is Movie Maker's: 32-bit integer PCM at 48 kHz (`ffmpeg -i m.avi -vn -c:a pcm_s32le m.wav` from an avi).
"""

from __future__ import annotations

import argparse
import itertools
import json
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
from analyze import read_wav

# Peak dBFS of the Master mix at the default settings (the UI bus at 80 percent): where each sound should sit, and the
# weight (rung of the ladder) it is on. The numbers are `game/tests/core/menu_sound_levels.json`, the file the game's
# test reads too, so the recording and the test hold the same table; `docs/research/menu-sfx.md` says where they come
# from. A row is "<sound>|<the table's trim in dB>": hover on a "Coming" row is 4 dB under.
TARGETS_PATH = Path(__file__).resolve().parents[2] / "game" / "tests" / "core" / "menu_sound_levels.json"
TARGETS: dict[str, tuple[float, int]] = {
    key: (row["target_dbfs"], row["rung"]) for key, row in json.loads(TARGETS_PATH.read_text(encoding="utf-8")).items()
}
TOLERANCE_DB = 2.5
# A weight's loudest-sounding mean peak must stay this far under the next weight's quietest one, at least.
LADDER_MIN_STEP_DB = 3.0
CLIP_DB = -1.0
FLOOR_DB = -45.0
MOMENTARY_S = 0.4
HOP_S = 0.1
# BS.1770 K-weighting at 48 kHz: the pre-filter (a high shelf) and the RLB high-pass.
K_PRE = (
    np.array([1.53512485958697, -2.69169618940638, 1.19839281085285]),
    np.array([1.0, -1.69065929318241, 0.73248077421585]),
)
K_RLB = (np.array([1.0, -2.0, 1.0]), np.array([1.0, -1.99004745483398, 0.99007225036621]))


def db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-9))


def k_weighted(channels: np.ndarray) -> np.ndarray:
    """Each channel through the K filters; (channels, samples)."""
    out = signal.lfilter(*K_PRE, channels, axis=-1)
    return signal.lfilter(*K_RLB, out, axis=-1)


def momentary_max(channels: np.ndarray, rate: int) -> float:
    """The loudest 400 ms of the stretch, in LUFS (the window slides by 100 ms; a stretch shorter than the window is
    read as zero-padded to it, as a meter would see the sound alone)."""
    weighted = k_weighted(channels)
    n = int(MOMENTARY_S * rate)
    if weighted.shape[-1] < n:
        weighted = np.pad(weighted, ((0, 0), (0, n - weighted.shape[-1])))
    best = -200.0
    for start in range(0, weighted.shape[-1] - n + 1, int(HOP_S * rate)):
        power = np.mean(weighted[:, start : start + n] ** 2, axis=-1).sum()
        best = max(best, -0.691 + 10.0 * np.log10(max(power, 1e-18)))
    return best


def read_stereo(path: Path) -> tuple[np.ndarray, int]:
    data, rate = read_wav(path)
    if data.ndim == 1:
        data = data[None, :]
    return data, rate


def parse(log: Path, kind: str) -> list[tuple]:
    rows = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if parts and parts[0] == kind:
            rows.append(tuple(parts[1:]))
    return rows


def first_over(x: np.ndarray, start: int, floor: float = 1e-4) -> int:
    """The first sample at or after `start` where any channel passes `floor`: where the sound begins in the mix."""
    loud = np.nonzero(np.abs(x[:, start:]).max(axis=0) > floor)[0]
    return start + int(loud[0]) if len(loud) else start


def measure_levels(mix: np.ndarray, rate: int, plays: list[tuple], refs: list[tuple]) -> tuple[dict, dict]:
    events = [(float(p[0]), "play", p) for p in plays] + [(float(r[0]), "ref", r) for r in refs]
    events.sort(key=lambda e: e[0])
    by_key: dict[str, list[dict]] = defaultdict(list)
    by_ref: dict[str, list[dict]] = defaultdict(list)
    for i, (t, kind, row) in enumerate(events):
        end = events[i + 1][0] if i + 1 < len(events) else t + 3.0
        a = max(int((t - 0.02) * rate), 0)
        b = min(int(end * rate) - int(0.02 * rate), mix.shape[-1])
        start = first_over(mix[:, a:b], 0) + a
        seg = mix[:, max(start - int(0.005 * rate), 0) : b]
        entry = {"peak": db(np.abs(seg).max()), "lufs_m": momentary_max(seg, rate)}
        if kind == "play":
            by_key[f"{row[1]}|{float(row[3])}"].append({**entry, "variant": int(row[2])})
        else:
            by_ref[row[1]].append(entry)
    return by_key, by_ref


def report_levels(by_key: dict, by_ref: dict) -> tuple[int, dict]:
    failed = 0
    table = {}
    print(f"{'sound|trim':26} {'peak min':>8} {'mean':>7} {'max':>7} {'target':>7} {'LUFS-M':>7}  rung  verdict")
    rung_peaks: dict[int, list[float]] = defaultdict(list)
    rung_lufs: dict[int, list[float]] = defaultdict(list)
    for key in sorted(by_key, key=lambda k: (TARGETS.get(k, (0, 9))[1], k)):
        rows = by_key[key]
        peaks = [r["peak"] for r in rows]
        mean_peak = float(np.mean(peaks))
        lufs = float(np.mean([r["lufs_m"] for r in rows]))
        target, rung = TARGETS.get(key, (float("nan"), 0))
        verdict = "ok"
        if np.isnan(target):
            verdict = "no target"
            failed += 1
        elif abs(mean_peak - target) > TOLERANCE_DB:
            verdict = "OFF TARGET"
            failed += 1
        if max(peaks) > CLIP_DB:
            verdict += " CLIPS"
            failed += 1
        rung_peaks[rung].append(mean_peak)
        rung_lufs[rung].append(lufs)
        print(
            f"{key:26} {min(peaks):8.1f} {mean_peak:7.1f} {max(peaks):7.1f} {target:7.1f} {lufs:7.1f}  {rung:>4}  {verdict}"
        )
        table[key] = {"peak_mean": round(mean_peak, 1), "peak_max": round(max(peaks), 1), "lufs_m": round(lufs, 1)}
    # The ladder is read on each rung's median, for the peak and for the loudness: the rungs 1 to 4 are what is heard
    # often; the fifth (a moment, the sign) is rare and long and stands outside it.
    rungs = [r for r in sorted(rung_peaks) if 0 < r <= 4]
    for name, source in (("peak", rung_peaks), ("LUFS-M", rung_lufs)):
        for low, high in itertools.pairwise(rungs):
            step = float(np.median(source[high]) - np.median(source[low]))
            verdict = "ok" if step >= LADDER_MIN_STEP_DB else "LADDER TOO FLAT"
            failed += verdict != "ok"
            print(
                f"ladder ({name}): the median of rung {high} is {step:+.1f} dB over the median of rung {low}  {verdict}"
            )
    print("\nthe night, for scale (peak dBFS, LUFS-M):")
    for name, rows in by_ref.items():
        print(f"  {name:20} {np.mean([r['peak'] for r in rows]):7.1f} {np.mean([r['lufs_m'] for r in rows]):7.1f}")
    loudest_ui = max(v["peak_mean"] for v in table.values())
    quietest_gun = np.mean([r["peak"] for r in by_ref.get("shot_pistol", [{"peak": 0.0}])])
    print(f"loudest menu sound {loudest_ui:.1f} dBFS, the pistol {quietest_gun:.1f}")
    return failed, table


def plot_levels(by_key: dict, by_ref: dict, out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    keys = sorted(by_key, key=lambda k: (TARGETS.get(k, (0, 9))[1], TARGETS.get(k, (0, 9))[0]))
    fig, ax = plt.subplots(figsize=(10, 5.5))
    colours = {1: "#8aa4c8", 2: "#5b8def", 3: "#e8a838", 4: "#d9534f", 5: "#9b59b6", 0: "#888888"}
    for i, key in enumerate(keys):
        peaks = [r["peak"] for r in by_key[key]]
        rung = TARGETS.get(key, (0, 0))[1]
        ax.bar(i, np.mean(peaks) - FLOOR_DB, bottom=FLOOR_DB, color=colours[rung], width=0.7)
        ax.plot([i, i], [min(peaks), max(peaks)], color="black", lw=1)
        if key in TARGETS:
            ax.plot([i - 0.4, i + 0.4], [TARGETS[key][0]] * 2, color="black", ls=":", lw=1.5)
    ax.set_xticks(range(len(keys)))
    ax.set_xticklabels(
        [k.replace("ui_", "").replace("|0.0", "").replace("|", " ") for k in keys], rotation=60, ha="right"
    )
    for name, rows in by_ref.items():
        ax.axhline(np.mean([r["peak"] for r in rows]), color="#999", lw=0.8, ls="--")
        ax.text(len(keys) - 0.4, np.mean([r["peak"] for r in rows]) + 0.4, name, fontsize=7, ha="right", color="#555")
    ax.axhline(0.0, color="#d9534f", lw=1)
    ax.set_ylim(FLOOR_DB, 2)
    ax.set_ylabel("peak, dBFS in the mix (default settings)")
    ax.set_title(
        "Menu sounds by weight: hint, move, press, commit, moment. Black line: spread of variants; dotted: target; dashed: the night",
        fontsize=9,
    )
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print("plot", out)


def tour_stats(mix: np.ndarray, rate: int, log: Path) -> dict:
    sounds = [(float(t), name) for t, name in parse(log, "SFX")]
    marks = [(float(t), " ".join(rest)) for t, *rest in parse(log, "MARK")]
    hints = [t for t, n in sounds if n in ("ui_hover", "ui_focus")]
    ticks = [t for t, n in sounds if n == "ui_tick"]
    best = 0
    for t in hints:
        best = max(best, sum(1 for u in hints if t <= u < t + 1.0))
    seconds = mix.shape[-1] / rate
    return {
        "sounds": len(sounds),
        "by_sound": {n: sum(1 for _, m in sounds if m == n) for n in sorted({n for _, n in sounds})},
        "most_hints_in_a_second": best,
        "least_hint_gap_s": round(min(np.diff(hints)), 3) if len(hints) > 1 else None,
        "least_tick_gap_s": round(min(np.diff(ticks)), 3) if len(ticks) > 1 else None,
        "mix_peak_db": round(db(np.abs(mix).max()), 1),
        "clipped_samples": int((np.abs(mix) > 10 ** (-0.1 / 20)).sum()),
        "seconds": round(seconds, 1),
        "marks": marks,
        "silent_seconds_over_3": _silent_stretches(mix, rate),
    }


def _silent_stretches(mix: np.ndarray, rate: int, floor_db: float = -60.0, minimum: float = 3.0) -> int:
    """How many stretches of `minimum` seconds or more are silent: how often the menu says nothing for a while."""
    block = int(0.1 * rate)
    n = mix.shape[-1] // block
    loud = np.abs(mix[:, : n * block]).reshape(mix.shape[0], n, block).max(axis=(0, 2)) > 10 ** (floor_db / 20)
    count, run = 0, 0
    for flag in loud:
        run = 0 if flag else run + 1
        if run == int(minimum / 0.1):
            count += 1
    return count


def plot_tour(runs: list[tuple[str, np.ndarray, int, Path]], out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(runs), 1, figsize=(11, 2.6 * len(runs)), sharex=True)
    axes = np.atleast_1d(axes)
    for ax, (label, mix, rate, log) in zip(axes, runs, strict=True):
        block = int(0.05 * rate)
        n = mix.shape[-1] // block
        peaks = np.abs(mix[:, : n * block]).reshape(mix.shape[0], n, block).max(axis=(0, 2))
        ax.fill_between(np.arange(n) * 0.05, 20 * np.log10(np.maximum(peaks, 1e-5)), -100, color="#5b8def", step="pre")
        for t, text in [(float(t), " ".join(r)) for t, *r in parse(log, "MARK")]:
            ax.axvline(t, color="#999", lw=0.6)
            ax.text(t + 0.1, -4, text.split(":")[0][:22], rotation=90, fontsize=6, va="top", color="#444")
        ax.set_ylim(-70, 0)
        ax.set_ylabel("peak, dBFS")
        ax.set_title(label, fontsize=9, loc="left")
    axes[-1].set_xlabel("seconds into the walk")
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print("plot", out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("levels")
    a.add_argument("wav", type=Path)
    a.add_argument("log", type=Path)
    a.add_argument("--plot", type=Path)
    a.add_argument("--json", type=Path)
    b = sub.add_parser("tour")
    b.add_argument("wav", type=Path)
    b.add_argument("log", type=Path)
    b.add_argument("--before", nargs=2, type=Path, metavar=("WAV", "LOG"))
    b.add_argument("--plot", type=Path)
    args = parser.parse_args()
    if args.cmd == "levels":
        mix, rate = read_stereo(args.wav)
        plays = parse(args.log, "PLAY")
        refs = parse(args.log, "REF")
        by_key, by_ref = measure_levels(mix, rate, plays, refs)
        failed, table = report_levels(by_key, by_ref)
        clipped = int((np.abs(mix) >= 1.0).sum())
        print(f"clipped samples in the recording: {clipped}")
        if args.plot:
            plot_levels(by_key, by_ref, args.plot)
        if args.json:
            args.json.write_text(json.dumps(table, indent=1, sort_keys=True), encoding="utf-8")
        sys.exit(1 if failed or clipped else 0)
    mix, rate = read_stereo(args.wav)
    runs = [("After: the menus with their sounds", mix, rate, args.log)]
    stats = {"after": tour_stats(mix, rate, args.log)}
    if args.before:
        bmix, brate = read_stereo(args.before[0])
        runs.insert(0, ("Before: the same walk, on main", bmix, brate, args.before[1]))
        stats["before"] = tour_stats(bmix, brate, args.before[1])
    for name, s in stats.items():
        marks = s.pop("marks")
        print(name, json.dumps(s, indent=1))
        s["marks"] = marks
    if args.plot:
        plot_tour(runs, args.plot)
    after = stats["after"]
    bad = after["most_hints_in_a_second"] > 5 or (after["least_hint_gap_s"] or 1.0) < 0.079
    bad = bad or (after["least_tick_gap_s"] or 1.0) < 0.069 or after["clipped_samples"] > 0
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
