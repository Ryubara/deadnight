"""Measures the footsteps against the rest of a night's mix, from the capture `audio_footsteps`.

    uv run --with numpy python tools/audio/step_levels.py --ffmpeg <pinned ffmpeg> --wav out.wav --log out.log [--png sheet.png]

The scene prints `STAGE <seconds> <name>` for each part (the bed alone, a walk, a sprint, a crouch, standing, gravel,
gunfire, a teammate), `STEP <seconds> <id> <positional>` for every step the service started and `SHOT <seconds> <id>` for
every shot. For each stage this prints the loudness the pinned ffmpeg's `ebur128` hears (integrated, and the loudest
momentary 400 ms), and for every kind of event how far its own 100 ms stands above the bed around it (the median
100 ms level of the "bed" stage, which is crickets, highway and the score over each other). Read the Movie Maker mix
as 32-bit integer PCM (`--write-movie` writes that, not 16-bit).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import wave
from pathlib import Path

import numpy as np

WINDOW = 0.1  # seconds an event's level is read over, from its start


def read_mix(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as f:
        channels, width, rate, frames = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
        raw = f.readframes(frames)
    dtype = {2: "<i2", 4: "<i4"}[width]
    scale = float(2 ** (8 * width - 1))
    return (np.frombuffer(raw, dtype).astype(np.float64) / scale).reshape(-1, channels).mean(axis=1), rate


def parse_log(path: Path) -> tuple[list[tuple[float, str]], list[tuple[float, str, str]], list[tuple[float, str]]]:
    stages, steps, shots = [], [], []
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split()
        if line.startswith("STAGE") and len(parts) >= 3:
            stages.append((float(parts[1]), parts[2]))
        elif line.startswith("STEP") and len(parts) >= 4:
            steps.append((float(parts[1]), parts[2], parts[3]))
        elif line.startswith("SHOT") and len(parts) >= 3:
            shots.append((float(parts[1]), parts[2]))
    return stages, steps, shots


def loudness(ffmpeg: str, wav: Path, start: float, length: float) -> tuple[float, float]:
    """Integrated LUFS and the loudest momentary (400 ms) LUFS of a part of the file."""
    cmd = [ffmpeg, "-hide_banner", "-nostats", "-ss", f"{start:.2f}", "-t", f"{length:.2f}", "-i", str(wav)]
    cmd += ["-af", "ebur128=peak=true", "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stderr
    momentary = [float(m) for m in re.findall(r"M:\s*(-?\d+\.\d+)", out)]
    integrated = re.findall(r"I:\s+(-?\d+\.\d+) LUFS", out)
    return float(integrated[-1]), max(momentary) if momentary else float("nan")


def db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-9))


def window_db(mono: np.ndarray, rate: int, at: float) -> float:
    part = mono[int(at * rate) : int((at + WINDOW) * rate)]
    return db(float(np.sqrt(np.mean(part**2)))) if len(part) else -120.0


def peak_db(mono: np.ndarray, rate: int, at: float) -> float:
    part = mono[int(at * rate) : int((at + WINDOW) * rate)]
    return db(float(np.abs(part).max())) if len(part) else -120.0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    mono, rate = read_mix(args.wav)
    stages, steps, shots = parse_log(args.log)
    ends = [s[0] for s in stages[1:]] + [len(mono) / rate]
    # The bed: the first stage after the beds have faded in (3 s), from the middle of the stage.
    bed_start, bed_end = stages[0][0] + 3.0, ends[0] - 0.2
    bed_levels = [window_db(mono, rate, t) for t in np.arange(bed_start, bed_end - WINDOW, WINDOW)]
    bed = float(np.median(bed_levels))
    bed_peak = float(np.median([peak_db(mono, rate, t) for t in np.arange(bed_start, bed_end - WINDOW, WINDOW)]))
    clipped = int((np.abs(mono) >= 0.999).sum())
    print(f"mix peak {db(float(np.abs(mono).max())):.1f} dBFS, {clipped} clipped samples")
    print(f"bed alone: median 100 ms RMS {bed:.1f} dBFS, median 100 ms peak {bed_peak:.1f} dBFS\n")
    print(f"{'stage':<16}{'seconds':>8}{'LUFS':>8}{'M max':>8}")
    for (start, name), end in zip(stages, ends):
        first = start + (3.0 if name == stages[0][1] else 0.0)
        lufs, momentary = loudness(args.ffmpeg, args.wav, first, max(0.5, end - first))
        print(f"{name:<16}{end - start:8.1f}{lufs:8.1f}{momentary:8.1f}")
    print()
    print(
        f"{'event':<28}{'n':>4}{'RMS dBFS':>10}{'over bed':>10}{'peak dBFS':>11}{'over bed peak':>15}{'loudest over bed':>18}"
    )
    kinds: dict[str, list[float]] = {}
    for at, sound, positional in steps:
        stage = [n for s, n in stages if s <= at][-1]
        kinds.setdefault(f"{sound} {'(world)' if positional == 'true' else '(flat)'} {stage}", []).append(at)
    for at, sound in shots:
        kinds.setdefault(f"{sound} (burst)", []).append(at)
    for kind, times in kinds.items():
        rms = float(np.median([window_db(mono, rate, t) for t in times]))
        peak = float(np.median([peak_db(mono, rate, t) for t in times]))
        loudest = max(window_db(mono, rate, t) for t in times) - bed
        print(
            f"{kind:<28}{len(times):4d}{rms:10.1f}{rms - bed:10.1f}{peak:11.1f}{peak - bed_peak:15.1f}{loudest:18.1f}"
        )


if __name__ == "__main__":
    main()
