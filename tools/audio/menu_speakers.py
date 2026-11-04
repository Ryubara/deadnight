"""Check the menu's hints against its ambience bed on a laptop speaker and a phone speaker, without ears (#926).

    uv run --with numpy --with scipy --with matplotlib python tools/audio/menu_speakers.py \
        levels.wav levels.log bed.wav [--plot speakers.png] [--json out.json] [--pin game/tests/core/menu_bed_levels.json]

`levels.wav` and `levels.log` are the recording of `game/tests/captures/audio_menu_levels.tscn` (every sound of the
menu's table alone, through the real service and buses at the default settings; read by `menu_levels.py levels`) and
`bed.wav` the recording of `game/tests/captures/audio_menu_bed.tscn` (the menu's ambience bed alone, at the default
settings). Both are Movie Maker's 32-bit PCM at 48 kHz (`ffmpeg -i m.avi -vn -c:a pcm_s32le m.wav`).

The mix is linear, so a hint over the bed is the hint alone plus the bed alone, and each can be put through a
**speaker model** before they are compared. The models are assumed curves, not measurements of a device (the true cutoff
of a speaker varies by device; the kit's page says the loss is large near 300 Hz and under on a phone):

- `flat`: the recording as it is (headphones, a good desk speaker).
- `laptop`: two small drivers: a 4th-order high-pass at 280 Hz, a 3 dB presence bump at 2.5 kHz, a 2nd-order low-pass at
  13 kHz.
- `phone`: one tiny driver (the two channels summed): a 4th-order high-pass at 500 Hz, a 4 dB bump at 2 kHz, a
  2nd-order low-pass at 9 kHz.

For every hint (hover, focus, tick, and the quieter ones of a "Coming" row) and every model it prints two margins:

- **over the bed's momentary loudness**: the hint's peak (dBFS, after the model) minus the loudest 400 ms of the bed
  (LUFS-M, K-weighted, after the model). The kit's rule is 10 dB: a hint that far over the bed is plain. This is the
  gate.
- **in its own band**: the hint's loudest 50 ms rms in the band the hints live in (1.5 to 8 kHz) minus the loud
  moments of the bed in that band over 50 ms (its 95th percentile). A cricket chirp and a hint are both short and
  both in that band, while a low motor is not in it and masks nothing there; this one says whether the bed's chirps
  bury the hint. It must stay 6 dB or more.

It exits 1 when a gate fails.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
from analyze import read_wav
from menu_levels import db, first_over, k_weighted, momentary_max, parse

BEDS_PATH = Path(__file__).resolve().parents[2] / "game" / "core" / "audio" / "banks" / "beds.tres"
TARGETS_PATH = Path(__file__).resolve().parents[2] / "game" / "tests" / "core" / "menu_sound_levels.json"
HINTS = ("ui_hover|0.0", "ui_focus|0.0", "ui_tick|0.0", "ui_hover|-4.0", "ui_focus|-4.0")
OVER_BED_MIN_DB = 10.0
IN_BAND_MIN_DB = 6.0
# The band the hints live in (the hover's ring is at 2.5 kHz, its click 3.5 to 6.5 kHz).
BAND_HZ = (1500.0, 8000.0)
WINDOW_S = 0.05
# The bed is read after its fade-in (the recording starts with the bed's start).
BED_SKIP_S = 4.0


def peaking(f0: float, gain_db: float, q: float, rate: int) -> np.ndarray:
    """An RBJ peaking filter as a second-order section."""
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / rate
    alpha = np.sin(w) / (2 * q)
    b = np.array([1 + alpha * a, -2 * np.cos(w), 1 - alpha * a])
    den = np.array([1 + alpha / a, -2 * np.cos(w), 1 - alpha / a])
    return np.concatenate([b / den[0], den / den[0]])[None, :]


def model_sos(name: str, rate: int) -> np.ndarray | None:
    if name == "flat":
        return None
    if name == "laptop":
        parts = [
            signal.butter(4, 280, "highpass", fs=rate, output="sos"),
            peaking(2500, 3.0, 0.9, rate),
            signal.butter(2, 13000, "lowpass", fs=rate, output="sos"),
        ]
    else:
        parts = [
            signal.butter(4, 500, "highpass", fs=rate, output="sos"),
            peaking(2000, 4.0, 1.0, rate),
            signal.butter(2, 9000, "lowpass", fs=rate, output="sos"),
        ]
    return np.vstack(parts)


MODELS = ("flat", "laptop", "phone")


def through(name: str, mix: np.ndarray, rate: int) -> np.ndarray:
    """The recording as the model's speaker plays it: (channels, samples); the phone is one channel."""
    sos = model_sos(name, rate)
    out = mix if sos is None else signal.sosfilt(sos, mix, axis=-1)
    if name == "phone":
        out = out.mean(axis=0, keepdims=True)
    return out


def band_rms_db(channels: np.ndarray, rate: int) -> np.ndarray:
    """The rms of each 50 ms window (hop 10 ms) of the hints' band, dB; shorter than a window is padded to it."""
    sos = signal.butter(4, BAND_HZ, "bandpass", fs=rate, output="sos")
    band = signal.sosfilt(sos, channels, axis=-1)
    return _window_db(band, rate)


def _window_db(channels: np.ndarray, rate: int) -> np.ndarray:
    n = int(WINDOW_S * rate)
    if channels.shape[-1] < n:
        channels = np.pad(channels, ((0, 0), (0, n - channels.shape[-1])))
    power = (channels**2).sum(axis=0)
    cumulative = np.concatenate([[0.0], np.cumsum(power)])
    starts = np.arange(0, channels.shape[-1] - n + 1, int(0.01 * rate))
    return 10 * np.log10(np.maximum((cumulative[starts + n] - cumulative[starts]) / n, 1e-18))


def bed_stats(bed: np.ndarray, rate: int, model: str) -> dict:
    heard = through(model, bed[:, int(BED_SKIP_S * rate) :], rate)
    window = band_rms_db(heard, rate)
    return {
        "lufs_m_max": momentary_max(heard, rate),
        "lufs_m_median": momentary_median(heard, rate),
        "band_p95": float(np.percentile(window, 95)),
        "peak": db(np.abs(heard).max()),
    }


def momentary_median(channels: np.ndarray, rate: int) -> float:
    weighted = k_weighted(channels)
    n = int(0.4 * rate)
    values = []
    for start in range(0, weighted.shape[-1] - n + 1, int(0.1 * rate)):
        power = np.mean(weighted[:, start : start + n] ** 2, axis=-1).sum()
        values.append(-0.691 + 10 * np.log10(max(power, 1e-18)))
    return float(np.median(values))


def hint_segments(mix: np.ndarray, rate: int, plays: list[tuple]) -> dict[str, list[tuple[int, int]]]:
    """Where each hint play begins and ends in the recording (sample indexes), by `sound|trim`."""
    times = sorted(float(p[0]) for p in plays)
    out: dict[str, list[tuple[int, int]]] = {}
    for p in plays:
        key = f"{p[1]}|{float(p[3])}"
        if key not in HINTS:
            continue
        t = float(p[0])
        later = [u for u in times if u > t + 1e-6]
        end = later[0] if later else t + 1.0
        a = max(int((t - 0.02) * rate), 0)
        b = min(int(end * rate) - int(0.02 * rate), mix.shape[-1])
        start = first_over(mix[:, a:b], 0) + a
        out.setdefault(key, []).append((max(start - int(0.005 * rate), 0), b))
    return out


def hint_report(mix: np.ndarray, rate: int, plays: list[tuple], bed: np.ndarray) -> dict:
    segments = hint_segments(mix, rate, plays)
    report: dict[str, dict] = {}
    for model in MODELS:
        heard = through(model, mix, rate)
        bed_info = bed_stats(bed, rate, model)
        rows = {}
        for key, spans in segments.items():
            peaks, windows = [], []
            for a, b in spans:
                seg = heard[:, a:b]
                peaks.append(db(np.abs(seg).max()))
                windows.append(float(band_rms_db(seg, rate).max()))
            peak = float(np.mean(peaks))
            window = float(np.mean(windows))
            rows[key] = {
                "peak": round(peak, 1),
                "over_bed": round(peak - bed_info["lufs_m_max"], 1),
                "in_band": round(window - bed_info["band_p95"], 1),
            }
        report[model] = {"bed": {k: round(v, 1) for k, v in bed_info.items()}, "hints": rows}
    return report


def bed_trims() -> dict[str, float]:
    """The trims (volume_db) of the menu's two bed sounds as `beds.tres` has them now."""
    text = BEDS_PATH.read_text(encoding="utf-8")
    out = {}
    for sound in ("bed_menu_crickets", "bed_menu_projector"):
        match = re.search(rf'id = &"{sound}".*?volume_db = (-?[\d.]+)', text, re.DOTALL)
        assert match, f"{sound} is not in {BEDS_PATH}"
        out[sound] = float(match.group(1))
    return out


def pin(report: dict) -> dict:
    """What `tests/core/test_menu_bed_levels.gd` pins: the trims and hint targets this check ran at, and the worst
    margins it found. A change to a trim or a hint's level makes the test ask for this check to be run again."""
    targets = json.loads(TARGETS_PATH.read_text(encoding="utf-8"))
    return {
        "_what": "written by tools/audio/menu_speakers.py --pin; see docs/research/menu-sfx.md, 'The bed'",
        "trims": bed_trims(),
        "hint_targets_dbfs": {key: targets[key]["target_dbfs"] for key in HINTS},
        "gates": {"over_bed_db": OVER_BED_MIN_DB, "in_band_db": IN_BAND_MIN_DB},
        "worst": {
            model: {
                "over_bed_db": min(row["over_bed"] for row in info["hints"].values()),
                "in_band_db": min(row["in_band"] for row in info["hints"].values()),
                "bed_lufs_m": info["bed"]["lufs_m_max"],
            }
            for model, info in report.items()
        },
    }


def plot(report: dict, mix: np.ndarray, plays: list[tuple], bed: np.ndarray, rate: int, out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.6))
    colours = {"flat": "#8aa4c8", "laptop": "#e8a838", "phone": "#d9534f"}
    ax = axes[0]
    first = {k: v[0] for k, v in hint_segments(mix, rate, plays).items()}["ui_hover|0.0"]
    centres = 1000.0 * 2.0 ** (np.arange(-10, 11) / 3.0)
    for model, style in (("laptop", "-"), ("phone", "--")):
        heard_bed = through(model, bed[:, int(BED_SKIP_S * rate) :], rate)
        heard_mix = through(model, mix, rate)
        hover = heard_mix[:, first[0] : first[1]]
        bed_levels, hint_levels = [], []
        for c in centres:
            lo, hi = c / 2 ** (1 / 6), min(c * 2 ** (1 / 6), rate * 0.45)
            sos = signal.butter(4, [lo, hi], "bandpass", fs=rate, output="sos")
            bed_levels.append(np.percentile(_window_db(signal.sosfilt(sos, heard_bed, axis=-1), rate), 95))
            hint_levels.append(_window_db(signal.sosfilt(sos, hover, axis=-1), rate).max())
        ax.semilogx(centres, bed_levels, style, color="#444", label=f"bed, loud 50 ms, {model}")
        ax.semilogx(centres, hint_levels, style, color="#5b8def", label=f"a hover, loudest 50 ms, {model}")
    ax.set_xlim(100, 12000)
    ax.set_ylim(-100, -30)
    ax.set_xlabel("Hz (third-octave bands)")
    ax.set_ylabel("rms of 50 ms, dB")
    ax.set_title("Where the bed and a hover sit, as each speaker plays them", fontsize=9)
    ax.legend(fontsize=7)
    for ax, field, title, gate in (
        (axes[1], "over_bed", "Hint peak over the bed's momentary loudness (dB; gate 10)", OVER_BED_MIN_DB),
        (axes[2], "in_band", "Hint 50 ms over the bed's loud 50 ms, 1.5-8 kHz (dB; gate 6)", IN_BAND_MIN_DB),
    ):
        keys = [k for k in HINTS if k in report["flat"]["hints"]]
        width = 0.26
        for i, model in enumerate(MODELS):
            vals = [report[model]["hints"][k][field] for k in keys]
            ax.bar(np.arange(len(keys)) + (i - 1) * width, vals, width, color=colours[model], label=model)
        ax.axhline(gate, color="black", lw=1, ls=":")
        ax.set_xticks(range(len(keys)))
        ax.set_xticklabels(
            [k.replace("ui_", "").replace("|0.0", "").replace("|-4.0", " (Coming)") for k in keys], fontsize=8
        )
        ax.set_title(title, fontsize=9)
        ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print("plot", out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("levels_wav", type=Path)
    parser.add_argument("levels_log", type=Path)
    parser.add_argument("bed_wav", type=Path)
    parser.add_argument("--plot", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument(
        "--pin", type=Path, help="write the file the game's test pins (tests/core/menu_bed_levels.json)"
    )
    args = parser.parse_args()
    mix, rate = read_wav(args.levels_wav)
    mix = mix[None, :] if mix.ndim == 1 else mix
    bed, bed_rate = read_wav(args.bed_wav)
    bed = bed[None, :] if bed.ndim == 1 else bed
    assert rate == bed_rate, "the two recordings must have one sample rate"
    plays = parse(args.levels_log, "PLAY")
    report = hint_report(mix, rate, plays, bed)
    failed = 0
    for model in MODELS:
        info = report[model]["bed"]
        print(
            f"\n{model}: bed loudest 400 ms {info['lufs_m_max']:.1f} LUFS-M (median {info['lufs_m_median']:.1f}),"
            f" loud 50 ms in the hints' band {info['band_p95']:.1f} dB, peak {info['peak']:.1f} dBFS"
        )
        print(f"  {'hint':16} {'peak':>6} {'over bed':>9} {'in band':>9}")
        for key, row in report[model]["hints"].items():
            verdict = ""
            if row["over_bed"] < OVER_BED_MIN_DB or row["in_band"] < IN_BAND_MIN_DB:
                verdict = "  TOO CLOSE TO THE BED"
                failed += 1
            print(f"  {key:16} {row['peak']:6.1f} {row['over_bed']:9.1f} {row['in_band']:9.1f}{verdict}")
    if args.plot:
        plot(report, mix, plays, bed, rate, args.plot)
    if args.json:
        args.json.write_text(json.dumps(report, indent=1, sort_keys=True), encoding="utf-8")
    if args.pin and not failed:
        args.pin.write_text(json.dumps(pin(report), indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print("pin", args.pin)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
