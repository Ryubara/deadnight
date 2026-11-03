"""Measure the grenade's fuse beep as the player hears it, from a recording of a throw (issue #680).

    uv run --with numpy --with scipy python tools/audio/beep_report.py mix.wav --frames A B --fps 60 [--json out.json]

`mix.wav` is a Movie Maker recording of `game/tests/captures/grenade_pack.tscn` (or any night where one grenade is
cooked, thrown and goes off): the audio the game's own service and buses made. `--frames A B` is the movie frames the
fuse ran between (the capture prints them as `FUSE_FRAMES`; `--window` takes seconds instead). The beep is a 1.1 kHz
tone with two harmonics, so a beep is a moment where a 60 ms window is mostly that tone (a pure sine reads 0.577,
noise far less), and the tone's amplitude there is the beep's level in the mix whatever else sounds at the same time.
This prints how many beeps and when, the gap between each pair, whether the gaps shrink (their thirds' means fall),
the first and last gap, each beep's tone peak in the mix (dBFS), and the blast's peak and 100 ms level, so the beep's
level against the mix can be read off: it swells toward the blast and stays under the blast's own level.
"""

from __future__ import annotations

import argparse
import itertools
import json
import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
from analyze import read_wav

BEEP_HZ = 1100.0
# The window a beep is looked for in (the beep lasts 60 ms), and how pure a tone it must be there: the share of the
# window's energy that is at `BEEP_HZ`, scaled so that a pure sine reads 0.577 (a hann window) and noise reads far less.
WINDOW_S = 0.06
MIN_TONE = 0.15
MIN_BEEP_GAP_S = 0.045
# A beep found in a noisy mix can be placed a frame early or late, so "the gaps shrink" is read on the means of the
# first, middle and last third of them.
THIRDS = 3
LEVEL_WINDOW_S = 0.1


def db(value: float) -> float:
    return 20.0 * np.log10(max(float(value), 1e-9))


def tone_track(x: np.ndarray, rate: int) -> tuple[np.ndarray, np.ndarray]:
    """For every sample: how tonal the window centred on it is at `BEEP_HZ` (0 to 0.577), and the amplitude of that
    tone (the peak of a sine of the same strength), through a hann window. The two are what tell a beep from noise."""
    n = int(WINDOW_S * rate)
    window = signal.windows.hann(n)
    carrier = np.exp(-2j * np.pi * BEEP_HZ * np.arange(n) / rate)
    kernel = (window * carrier)[::-1]
    projection = np.abs(signal.fftconvolve(x, kernel, mode="same"))
    energy = signal.fftconvolve(x**2, (window**2)[::-1], mode="same")
    tone = projection / np.sqrt(np.maximum(energy, 1e-18) * n)
    amplitude = 2.0 * projection / np.sum(window)
    return tone, amplitude


def blast_time(x: np.ndarray, rate: int) -> float:
    """The loudest 10 ms of the broadband signal above 100 Hz: the blast."""
    sos = signal.butter(2, 100.0, btype="highpass", fs=rate, output="sos")
    loud = signal.sosfilt(sos, x) ** 2
    width = int(0.01 * rate)
    power = np.convolve(loud, np.ones(width) / width, mode="same")
    return float(np.argmax(power) / rate)


def window_db(x: np.ndarray, rate: int, at: float) -> float:
    """RMS of the 100 ms that start at `at`, in dBFS."""
    start = int(at * rate)
    chunk = x[start : start + int(LEVEL_WINDOW_S * rate)]
    return db(np.sqrt(np.mean(chunk**2))) if len(chunk) else -120.0


def peak_db(x: np.ndarray, rate: int, at: float, span: float = 0.03) -> float:
    start = max(int((at - span / 2) * rate), 0)
    chunk = x[start : start + int(span * rate)]
    return db(np.max(np.abs(chunk))) if len(chunk) else -120.0


def beeps_between(x: np.ndarray, rate: int, start: float, end: float) -> tuple[list[float], list[float]]:
    """The times of the beeps in [start, end) and the peak (dBFS) of the tone each one has in the mix."""
    tone, amplitude = tone_track(x, rate)
    first, last = int(start * rate), int(max(end - 0.03, 0.0) * rate)
    window = tone[first:last]
    if window.size == 0:
        return [], []
    peaks, _ = signal.find_peaks(window, height=MIN_TONE, distance=int(MIN_BEEP_GAP_S * rate))
    times = [float((first + p) / rate) for p in peaks]
    levels = [db(amplitude[first + p]) for p in peaks]
    return times, levels


def shrinks(gaps: list[float]) -> bool:
    if len(gaps) < THIRDS * 2:
        return False
    size = len(gaps) // THIRDS
    parts = [gaps[i * size : (i + 1) * size] for i in range(THIRDS - 1)] + [gaps[(THIRDS - 1) * size :]]
    means = [float(np.mean(part)) for part in parts]
    return all(later < earlier for earlier, later in itertools.pairwise(means))


def report(path: Path, label: str, window: tuple[float, float] | None) -> dict:
    channels, rate = read_wav(path)
    x = channels.mean(axis=0) if channels.ndim == 2 else channels
    blast = window[1] if window else blast_time(x, rate)
    start = window[0] if window else 0.0
    times, peaks = beeps_between(x, rate, start, blast)
    gaps = [b - a for a, b in itertools.pairwise(times)]
    shrinking = shrinks(gaps)
    result = {
        "label": label,
        "file": path.name,
        "beeps": len(times),
        "times_s": [round(t, 3) for t in times],
        "gaps_s": [round(g, 3) for g in gaps],
        "gaps_shrink": shrinking,
        "first_gap_s": round(gaps[0], 3) if gaps else None,
        "last_gap_s": round(gaps[-1], 3) if gaps else None,
        "beep_tone_peak_dbfs": [round(float(p), 1) for p in peaks],
        "blast_time_s": round(blast, 3),
        "blast_peak_dbfs": round(float(peak_db(x, rate, blast + 0.01, 0.08)), 1),
        "blast_100ms_rms_dbfs": round(float(window_db(x, rate, blast)), 1),
        "mix_peak_dbfs": round(float(db(np.max(np.abs(x)))), 1),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("wav", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--label", default="")
    parser.add_argument("--window", nargs=2, type=float, metavar=("START_S", "BLAST_S"))
    parser.add_argument("--frames", nargs=2, type=int, metavar=("PIN", "BLAST"))
    parser.add_argument("--fps", type=float, default=60.0)
    args = parser.parse_args()
    window = tuple(args.window) if args.window else None
    if args.frames:
        window = (args.frames[0] / args.fps, args.frames[1] / args.fps)
    result = report(args.wav, args.label or args.wav.stem, window)
    print(f"{result['file']}: {result['beeps']} beeps before the blast at {result['blast_time_s']} s")
    print(f"  at (s):   {result['times_s']}")
    print(f"  gaps (s): {result['gaps_s']}")
    print(f"  gaps shrink: {result['gaps_shrink']}; first {result['first_gap_s']} s, last {result['last_gap_s']} s")
    print(f"  beep tone peaks in the mix (dBFS): {result['beep_tone_peak_dbfs']}")
    print(
        f"  blast: peak {result['blast_peak_dbfs']} dBFS, 100 ms RMS {result['blast_100ms_rms_dbfs']} dBFS;"
        f" whole mix peak {result['mix_peak_dbfs']} dBFS"
    )
    if args.json:
        args.json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    ok = result["beeps"] >= 8 and result["gaps_shrink"]
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
