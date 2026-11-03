"""Measure the crickets: their chirps a second and their level against the other beds (#781).

    uv run --with numpy --with scipy python tools/audio/cricket_levels.py check
    uv run --with numpy --with scipy python tools/audio/cricket_levels.py measure --ffmpeg <pinned ffmpeg>
        --crickets <crickets.ogg> --crickets-db -26.0 [--highway <highway.ogg>] [--scale 1.0] [--label after]

    uv run --with numpy --with scipy python tools/audio/cricket_levels.py capture --ffmpeg <pinned ffmpeg> night.wav
        [--from 4] [--to 30]

`check` renders the recipe and fails unless every cricket's chirp rate is inside `CRICKET_RATE_HZ` and every cricket
chirps a whole number of times in the 24 s loop (what makes it loop cleanly); it is the pin of the rate range.

`capture` reads the mix a Movie Maker run of `game/tests/captures/audio_quiet_night.tscn` wrote (the beds alone, the
rules paused in the intro) and prints the loudness, the crickets' band and the chirps a second the listener can tell
apart over the window, so a night before and after can be put side by side.

`measure` prints, for a rendered file with the catalog's `volume_db` laid over it: the chirps a second the recipe
scheduled and sang (`--scale 1.0` re-runs the recipe before the cut, to put the old file's numbers beside the new
ones), the chirps a second a listener can still tell apart in the file (a lower bound: chirps of different crickets
overlap), the loudness (ffmpeg `ebur128`) and the loudest chirp, the level in the crickets' own band (3.4 to 5.7 kHz,
where the highway has next to nothing, so it cannot mask them) and, with `--highway`, the crickets against the
highway bed in loudness and in that band.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import wave
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))

import night_recipes

RATE = 44100
BAND_HZ = (3400.0, 5700.0)
HIGHWAY_DB = -18.0
SMOOTH_SECONDS = 0.012
TILE_SECONDS = 96.0  # the least common multiple of the crickets' 24 s and the highway's 32 s loops


def seed() -> int:
    return zlib.crc32(b"deadnight:crickets:1")


def plan_of(scale: float) -> list[tuple[float, int, int]]:
    """Render the recipe keeping `scale` of the chirps; return each cricket's (pitch, chirps scheduled, chirps sung)."""
    old = night_recipes.CRICKET_RATE_SCALE
    night_recipes.CRICKET_RATE_SCALE = scale
    plan: list[tuple[float, int, int]] = []
    try:
        night_recipes.night_crickets(np.random.default_rng(seed()), plan)
    finally:
        night_recipes.CRICKET_RATE_SCALE = old
    return plan


def decode(ffmpeg: str, path: Path) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        subprocess.run(
            [ffmpeg, "-y", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le", str(wav)],
            check=True,
        )
        with wave.open(str(wav), "rb") as f:
            raw = f.readframes(f.getnframes())
    return np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0


def tile(x: np.ndarray) -> np.ndarray:
    return np.tile(x, round(TILE_SECONDS * RATE / len(x)))


def db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-9))


def band_envelope(x: np.ndarray) -> np.ndarray:
    sos = signal.butter(4, BAND_HZ, "band", fs=RATE, output="sos")
    env = np.abs(signal.hilbert(signal.sosfiltfilt(sos, x)))
    width = round(SMOOTH_SECONDS * RATE)
    return np.convolve(env, np.ones(width) / width, "same")


def band_rms_db(x: np.ndarray) -> float:
    sos = signal.butter(4, BAND_HZ, "band", fs=RATE, output="sos")
    return db(float(np.sqrt(np.mean(signal.sosfilt(sos, x) ** 2))))


def separable_chirps_per_second(x: np.ndarray) -> float:
    """Chirps the band envelope shows as separate blobs (one chirp is three pulses in about 64 ms)."""
    env = band_envelope(x)
    peaks, _ = signal.find_peaks(
        env,
        height=0.12 * np.percentile(env, 99.5),
        distance=round(0.05 * RATE),
        prominence=0.06 * np.percentile(env, 99.5),
    )
    return len(peaks) / (len(x) / RATE)


def loudness(ffmpeg: str, x: np.ndarray) -> tuple[float, float]:
    """Integrated loudness and the loudest short-term (3 s) loudness, LUFS, of a mono signal."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        with wave.open(str(wav), "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
        out = subprocess.run(
            [ffmpeg, "-nostats", "-i", str(wav), "-af", "ebur128=peak=true", "-f", "null", "-"],
            capture_output=True,
            text=True,
            check=True,
        ).stderr
    integrated = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", out)[-1])
    short = [float(v) for v in re.findall(r"S:\s+(-?[\d.]+)", out)]
    return integrated, max(short) if short else float("nan")


def gain(db_value: float) -> float:
    return 10 ** (db_value / 20.0)


def measure(args: argparse.Namespace) -> None:
    lo, hi = (v * args.scale for v in night_recipes.CRICKET_DRAW_HZ)
    plan = plan_of(args.scale)
    scheduled = sum(p[1] for p in plan) / night_recipes.CRICKET_SECONDS
    sung = sum(p[2] for p in plan) / night_recipes.CRICKET_SECONDS
    rates = [p[1] / night_recipes.CRICKET_SECONDS for p in plan]
    print(f"== {args.label} (volume_db {args.crickets_db}, recipe range {lo}-{hi} chirps/s per cricket)")
    print(
        f"recipe: {scheduled:.2f} chirps/s scheduled over 8 crickets ({min(rates):.2f} to {max(rates):.2f} each), {sung:.2f} sung"
    )
    crickets = decode(args.ffmpeg, args.crickets)
    print(
        f"file:   {separable_chirps_per_second(crickets):.2f} chirps/s tell apart in the file (a lower bound), {len(crickets) / RATE:.1f} s loop"
    )
    laid = tile(crickets) * gain(args.crickets_db)
    integrated, short = loudness(args.ffmpeg, laid)
    env = band_envelope(laid)
    print(
        f"level:  {integrated:.1f} LUFS integrated, {short:.1f} LUFS loudest 3 s, loudest chirp {db(np.percentile(env, 99.9)):.1f} dB (band envelope, 99.9th pct)"
    )
    print(
        f"        {band_rms_db(laid):.1f} dBFS rms in {BAND_HZ[0] / 1000:.1f}-{BAND_HZ[1] / 1000:.1f} kHz, file peak {db(np.abs(crickets).max()):.1f} dBFS"
    )
    if args.highway:
        highway = tile(decode(args.ffmpeg, args.highway)) * gain(HIGHWAY_DB)
        h_int, h_short = loudness(args.ffmpeg, highway)
        print(f"highway: {h_int:.1f} LUFS ({HIGHWAY_DB} dB), {band_rms_db(highway):.1f} dBFS rms in the crickets' band")
        print(
            f"crickets minus highway: {integrated - h_int:+.1f} LU integrated, {short - h_short:+.1f} LU loudest 3 s,"
            f" {band_rms_db(laid) - band_rms_db(highway):+.1f} dB in the crickets' band"
        )
        both, _ = loudness(args.ffmpeg, laid + highway)
        print(f"crickets + highway: {both:.1f} LUFS ({both - h_int:+.1f} LU over the highway alone)")


def capture(args: argparse.Namespace) -> None:
    global RATE
    with wave.open(str(args.wav), "rb") as f:
        RATE, channels, width = f.getframerate(), f.getnchannels(), f.getsampwidth()
        raw = f.readframes(f.getnframes())
    x = np.frombuffer(raw, {2: "<i2", 4: "<i4"}[width]).astype(np.float64) / float(1 << (8 * width - 1))
    x = x.reshape(-1, channels).mean(axis=1)[round(args.start * RATE) : round(args.end * RATE)]
    integrated, short = loudness(args.ffmpeg, x)
    env = band_envelope(x)
    print(f"== {args.label}: {args.start:g} to {args.end:g} s of {args.wav.name}")
    print(
        f"mix:    {integrated:.1f} LUFS integrated, {short:.1f} LUFS loudest 3 s, peak {db(np.abs(x).max()):.1f} dBFS"
    )
    print(
        f"        {band_rms_db(x):.1f} dBFS rms in {BAND_HZ[0] / 1000:.1f}-{BAND_HZ[1] / 1000:.1f} kHz, loudest chirp"
        f" {db(np.percentile(env, 99.9)):.1f} dB, {separable_chirps_per_second(x):.2f} chirps/s tell apart"
    )


def check() -> int:
    plan: list[tuple[float, int, int]] = []
    night_recipes.night_crickets(np.random.default_rng(seed()), plan)
    lo, hi = night_recipes.CRICKET_RATE_HZ
    bad = []
    for i, (freq, chirps, _) in enumerate(plan):
        rate = chirps / night_recipes.CRICKET_SECONDS
        if not lo - 0.5 / night_recipes.CRICKET_SECONDS <= rate <= hi + 0.5 / night_recipes.CRICKET_SECONDS:
            bad.append(f"cricket {i} ({freq:.0f} Hz): {rate:.3f} chirps/s outside {lo}-{hi}")
    if len(plan) != 8:
        bad.append(f"{len(plan)} crickets, not 8")
    if (round(lo, 3), round(hi, 3)) != (1.0, 2.1):
        bad.append(f"the range is {lo}-{hi}, the maintainer's is 1.0-2.1 (#781)")
    for line in bad:
        print("FAIL", line)
    if not bad:
        total = sum(p[1] for p in plan) / night_recipes.CRICKET_SECONDS
        print(f"ok: 8 crickets, {total:.2f} chirps/s, each a whole number of chirps in the loop and in {lo}-{hi}")
    return 1 if bad else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    m = sub.add_parser("measure")
    m.add_argument("--ffmpeg", required=True)
    m.add_argument("--crickets", type=Path, required=True)
    m.add_argument("--crickets-db", type=float, required=True)
    m.add_argument("--highway", type=Path)
    m.add_argument("--scale", type=float, default=night_recipes.CRICKET_RATE_SCALE)
    m.add_argument("--label", default="crickets")
    c = sub.add_parser("capture")
    c.add_argument("--ffmpeg", required=True)
    c.add_argument("wav", type=Path)
    c.add_argument("--from", dest="start", type=float, default=4.0)
    c.add_argument("--to", dest="end", type=float, default=30.0)
    c.add_argument("--label", default="capture")
    args = parser.parse_args()
    if args.cmd == "capture":
        capture(args)
        return
    if args.cmd == "check":
        sys.exit(check())
    measure(args)


if __name__ == "__main__":
    main()
