"""Measure the menu's music and wind (#979) without ears: the files, and the mix as the game plays it.

    uv run --with numpy --with scipy python tools/audio/menu_music_levels.py files --ffmpeg <ffmpeg> [--plot out.png]
    uv run --with numpy --with scipy python tools/audio/menu_music_levels.py mix bed.wav [--plot out.png]

`files` decodes the three Ogg files the game ships (`music/menu_pad_1`, `music/menu_bells_1`, `ambience/menu_wind_1`)
and checks what makes a loop fit a long stay (`docs/research/menu-music.md`):

- **no clipping**: the peak is at most -1 dBFS;
- **the seam**: the step from the last sample to the first is no bigger than the biggest step inside the file, and the
  400 ms either side of the seam differ by at most 1.5 dB in level (a loop that returns with a bump is heard every time);
- **a low dynamic range**: the loudest 400 ms is at most 8 LU over the median of the pad and of the wind (a swell,
  never a jump); the bells are sparse notes with silence between, so only the mix is held to it;
- **dark**: at most -26 dB of the energy is over 1.5 kHz, where the menu's hints live (and 2 dB less for the pad);
- **nothing repeats soon**: the three lengths share no factor, so the whole returns after their product.

`mix` reads Movie Maker's recording of `game/tests/captures/audio_menu_bed.tscn` (the beds together through the real
service and buses) and prints its integrated loudness, loudest 400 ms, loudness range, peak.
It exits 1 when a gate fails.
"""

from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
from analyze import centroid, db, read_wav
from menu_levels import k_weighted

ROOT = Path(__file__).resolve().parents[2] / "game" / "assets" / "audio"
LOOPS = {
    "menu_pad": ROOT / "music" / "menu_pad_1.ogg",
    "menu_bells": ROOT / "music" / "menu_bells_1.ogg",
    "menu_wind": ROOT / "ambience" / "menu_wind_1.ogg",
}
PEAK_MAX_DBFS = -1.0
SEAM_RMS_MAX_DB = 1.5
RANGE_MAX_LU = 8.0
HIGH_HZ = 1500.0
HIGH_MAX_DB = {"menu_pad": -28.0, "menu_bells": -26.0, "menu_wind": -26.0}


def momentary(channels: np.ndarray, rate: int, window_s: float = 0.4, hop_s: float = 0.1) -> np.ndarray:
    """LUFS-M of each 400 ms window (hop 100 ms), K-weighted."""
    weighted = k_weighted(channels)
    n, hop = int(window_s * rate), int(hop_s * rate)
    power = (weighted**2).sum(axis=0)
    cumulative = np.concatenate([[0.0], np.cumsum(power)])
    starts = np.arange(0, weighted.shape[-1] - n + 1, hop)
    return -0.691 + 10 * np.log10(np.maximum((cumulative[starts + n] - cumulative[starts]) / n, 1e-18))


def integrated(channels: np.ndarray, rate: int) -> float:
    """BS.1770 integrated loudness with the absolute (-70) and relative (-10 LU) gates."""
    values = momentary(channels, rate)
    values = values[values > -70.0]
    if not len(values):
        return -70.0
    mean = 10 * np.log10(np.mean(10 ** (values / 10)))
    kept = values[values > mean - 10.0]
    return float(10 * np.log10(np.mean(10 ** (kept / 10)))) if len(kept) else float(mean)


def decode(ffmpeg: str, ogg: Path, wav: Path) -> None:
    subprocess.run([ffmpeg, "-y", "-v", "error", "-i", str(ogg), "-c:a", "pcm_s32le", str(wav)], check=True)


def seam_report(x: np.ndarray, rate: int) -> dict:
    """The jump from the last sample to the first against the biggest step inside, and the level 400 ms either side."""
    mono = x.mean(axis=0)
    inside = float(np.abs(np.diff(mono)).max())
    jump = float(abs(mono[0] - mono[-1]))
    n = int(0.4 * rate)
    before = 10 * np.log10(max(float(np.mean(mono[-n:] ** 2)), 1e-18))
    after = 10 * np.log10(max(float(np.mean(mono[:n] ** 2)), 1e-18))
    return {"jump": jump, "max_step": inside, "rms_diff_db": abs(before - after)}


def high_share_db(x: np.ndarray, rate: int) -> float:
    """The energy over 1.5 kHz against all of it, dB."""
    power = np.abs(np.fft.rfft(x.mean(axis=0))) ** 2
    freqs = np.fft.rfftfreq(x.shape[-1], 1 / rate)
    return float(10 * np.log10(max(power[freqs >= HIGH_HZ].sum(), 1e-18) / (power.sum() + 1e-18)))


def centroid_range(x: np.ndarray, rate: int, window_s: float = 5.0) -> tuple[float, float]:
    mono = x.mean(axis=0)
    n = int(window_s * rate)
    values = [centroid(mono[i : i + n], rate) for i in range(0, len(mono) - n + 1, n)]
    return min(values), max(values)


def files(ffmpeg: str, plot: Path | None) -> int:
    failed = 0
    rows = {}
    seconds = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, ogg in LOOPS.items():
            wav = Path(tmp) / f"{name}.wav"
            decode(ffmpeg, ogg, wav)
            x, rate = read_wav(wav)
            level = momentary(x, rate)
            seam = seam_report(x, rate)
            lo, hi = centroid_range(x, rate)
            high = high_share_db(x, rate)
            row = {
                "seconds": x.shape[-1] / rate,
                "peak": db(np.abs(x).max()),
                "lufs": integrated(x, rate),
                "m_max": float(level.max()),
                "m_median": float(np.median(level)),
                "m_min": float(level.min()),
                "high": high,
                "centroid": (lo, hi),
                **seam,
            }
            row["over_median"] = row["m_max"] - row["m_median"]
            rows[name] = (row, x, level, rate)
            seconds.append(round(row["seconds"]))
            verdicts = []
            if row["peak"] > PEAK_MAX_DBFS:
                verdicts.append("CLIPS")
            if row["jump"] > row["max_step"]:
                verdicts.append("SEAM JUMP")
            if name != "menu_bells" and row["rms_diff_db"] > SEAM_RMS_MAX_DB:
                verdicts.append("SEAM LEVEL")
            if name != "menu_bells" and row["over_median"] > RANGE_MAX_LU:
                verdicts.append("TOO WIDE")
            if high > HIGH_MAX_DB[name]:
                verdicts.append("TOO BRIGHT")
            failed += bool(verdicts)
            print(
                f"{name:11} {row['seconds']:6.1f} s  peak {row['peak']:6.1f} dBFS  integrated {row['lufs']:6.1f} LUFS  "
                f"LUFS-M median {row['m_median']:6.1f} max {row['m_max']:6.1f} (+{row['over_median']:.1f}) "
                f"min {row['m_min']:6.1f}  over 1.5 kHz {high:6.1f} dB  centroid {lo:5.0f}-{hi:5.0f} Hz  "
                f"seam jump {row['jump']:.5f} (inside {row['max_step']:.5f}), level {row['rms_diff_db']:.2f} dB  "
                + " ".join(verdicts)
            )
    for a in range(len(seconds)):
        for b in range(a + 1, len(seconds)):
            g = math.gcd(seconds[a], seconds[b])
            if g != 1:
                print(f"lengths {seconds[a]} and {seconds[b]} share a factor of {g}")
                failed += 1
    whole = math.lcm(*seconds)
    print(f"the three loops return together after {whole} s = {whole / 86400:.1f} days")
    if plot:
        _plot_files(rows, plot)
    return 1 if failed else 0


def _plot_files(rows: dict, out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, len(rows), figsize=(15, 6))
    for col, (name, (row, x, level, rate)) in enumerate(rows.items()):
        axes[0, col].plot(np.arange(len(level)) * 0.1, level, lw=0.8, color="#5b8def")
        axes[0, col].set_title(f"{name}: loudness of every 400 ms (LUFS-M)", fontsize=9)
        axes[0, col].set_xlabel("seconds")
        mono = x.mean(axis=0)
        f, t, s = signal.spectrogram(mono, rate, nperseg=8192, noverlap=4096)
        axes[1, col].pcolormesh(t, f, 10 * np.log10(s + 1e-14), vmin=-120, vmax=-50, shading="auto")
        axes[1, col].set_ylim(0, 4000)
        axes[1, col].set_title("spectrogram, 0-4 kHz", fontsize=9)
        axes[1, col].set_xlabel("seconds")
    fig.tight_layout()
    fig.savefig(out, dpi=100)
    print("plot", out)


def mix(path: Path, plot: Path | None, until: float) -> int:
    x, rate = read_wav(path)
    skip = int(4.0 * rate)  # the beds fade in
    heard = x[:, skip : int(until * rate)]  # from the end of the fade in to the stop (the fade out is cut)
    level = momentary(heard, rate)
    power = (heard**2).sum(axis=0)
    cumulative = np.concatenate([[0.0], np.cumsum(power)])
    window = 3 * rate
    starts = np.arange(0, len(power) - window + 1, rate)
    short = 10 * np.log10(np.maximum((cumulative[starts + window] - cumulative[starts]) / window, 1e-18))
    print(
        f"mix {heard.shape[-1] / rate:.0f} s  peak {db(np.abs(heard).max()):.1f} dBFS  "
        f"integrated {integrated(heard, rate):.1f} LUFS  LUFS-M median {np.median(level):.1f} "
        f"max {level.max():.1f} min {level.min():.1f}  range p95-p5 {np.percentile(level, 95) - np.percentile(level, 5):.1f} LU  "
        f"3 s power swings {short.max() - short.min():.1f} dB"
    )
    if plot:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, ax = plt.subplots(figsize=(10, 3))
        ax.plot(np.arange(len(level)) * 0.1 + 4.0, level, lw=0.8)
        ax.set_xlabel("seconds")
        ax.set_ylabel("LUFS-M")
        ax.set_title("The menu's beds together, loudness of every 400 ms")
        fig.tight_layout()
        fig.savefig(plot, dpi=100)
        print("plot", plot)
    return 1 if db(np.abs(heard).max()) > PEAK_MAX_DBFS else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("files")
    f.add_argument("--ffmpeg", required=True)
    f.add_argument("--plot", type=Path)
    m = sub.add_parser("mix")
    m.add_argument("wav", type=Path)
    m.add_argument("--plot", type=Path)
    m.add_argument("--until", type=float, default=119.5, help="seconds, the capture's stop (default 119.5)")
    args = parser.parse_args()
    sys.exit(files(args.ffmpeg, args.plot) if args.cmd == "files" else mix(args.wav, args.plot, args.until))


if __name__ == "__main__":
    main()
