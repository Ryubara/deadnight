"""Render every Deadnight sound to Ogg Vorbis.

    uv run --with numpy --with scipy python tools/audio/generate.py --ffmpeg <ffmpeg> [--out game/assets/audio]
        [--wav-dir <folder to keep the 16-bit WAVs>] [--only name,...]

Seeds come from the sound's name and variant number, so the same command always renders the same WAVs. Files are
`<group>/<name>_<n>.ogg`; a one-variant sound has `_1` too, so the game's catalog treats every sound alike.
"""

from __future__ import annotations

import argparse
import inspect
import subprocess
import sys
import tempfile
import wave
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

import challenge_recipes
import dsp
import gun_recipes_2
import map_recipes
import night_recipes
import recipes
import step_recipes
import weapon_recipes
import wind_recipes
import zombie_recipes
from recipes import Entry

REGISTRY: list[Entry] = [
    *recipes.REGISTRY,
    *night_recipes.REGISTRY,
    *weapon_recipes.REGISTRY,
    *gun_recipes_2.REGISTRY,
    *zombie_recipes.REGISTRY,
    *step_recipes.REGISTRY,
    *map_recipes.REGISTRY,
    *wind_recipes.REGISTRY,
    *challenge_recipes.REGISTRY,
]


def seed_of(name: str, variant: int) -> int:
    return zlib.crc32(f"deadnight:{name}:{variant}".encode())


def render(entry: Entry, variant: int) -> np.ndarray:
    rng = np.random.default_rng(seed_of(entry.name, variant))
    # A recipe with a `variant` parameter is one table of shapes, one per file (the wind's gusts).
    takes_variant = "variant" in inspect.signature(entry.recipe).parameters
    samples = np.nan_to_num(entry.recipe(rng, variant) if takes_variant else entry.recipe(rng))
    if not entry.loop:
        if samples.ndim == 2:
            length = max(len(dsp.trim_tail(ch)) for ch in samples)
            samples = samples[:, :length]
        else:
            samples = dsp.trim_tail(samples)
    return dsp.normalize(samples, entry.peak_db)


def write_wav(path: Path, samples: np.ndarray) -> None:
    channels = samples.shape[0] if samples.ndim == 2 else 1
    interleaved = samples.T if samples.ndim == 2 else samples
    pcm = (np.clip(interleaved, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(channels)
        f.setsampwidth(2)
        f.setframerate(dsp.SAMPLE_RATE)
        f.writeframes(pcm.tobytes())


def encode(ffmpeg: str, wav: Path, ogg: Path) -> None:
    ogg.parent.mkdir(parents=True, exist_ok=True)
    cmd = [ffmpeg, "-y", "-v", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4"]
    cmd += ["-fflags", "+bitexact", "-flags:a", "+bitexact", str(ogg)]
    subprocess.run(cmd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ffmpeg", required=True, help="path to the pinned ffmpeg")
    parser.add_argument("--out", type=Path, default=Path("game/assets/audio"))
    parser.add_argument("--wav-dir", type=Path, help="also keep the WAVs here")
    parser.add_argument("--only", help="comma-separated sound names")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    total = 0
    with tempfile.TemporaryDirectory() as tmp:
        wav_root = args.wav_dir or Path(tmp)
        for entry in REGISTRY:
            if only and entry.name not in only:
                continue
            for variant in range(1, entry.variants + 1):
                stem = f"{entry.name}_{variant}"
                wav = wav_root / entry.group / f"{stem}.wav"
                wav.parent.mkdir(parents=True, exist_ok=True)
                samples = render(entry, variant)
                write_wav(wav, samples)
                ogg = args.out / entry.group / f"{stem}.ogg"
                encode(args.ffmpeg, wav, ogg)
                seconds = samples.shape[-1] / dsp.SAMPLE_RATE
                print(f"{ogg.as_posix()}  {seconds:5.2f}s  {ogg.stat().st_size / 1024:6.1f} KiB")
                total += ogg.stat().st_size
    print(f"total {total / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
