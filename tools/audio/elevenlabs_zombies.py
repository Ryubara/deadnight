"""Extra takes of the dead's voices from ElevenLabs Sound Effects (free tier), cleaned and encoded for the game.

    ELEVENLABS_API_KEY=... uv run --with numpy --with scipy --with requests python tools/audio/elevenlabs_zombies.py
        --ffmpeg <pinned ffmpeg> [--only name,...] [--dry-run]

The key is read from the environment and never printed or written. Each take is one call (40 credits a second of
requested length); the result is trimmed of leading and trailing silence, normalised to the peak the synthesised
variants use, faded, and written as `game/assets/audio/zombie/<name>_<n>.ogg` after the synthesised variants (the
catalog's variant counts include them). A take that already exists is not requested again, so a rerun costs nothing.
Licence and prompts: `game/assets/audio/zombie/eleven/LICENSE.md` (a file per take is listed there).
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

import dsp

API = "https://api.elevenlabs.io/v1/sound-generation"
OUT = Path("game/assets/audio/zombie")
PEAK_DB = -3.0

# name, first variant number (after the synthesised ones), takes, seconds each, prompt
TAKES = [
    ("groan", 5, 3, 2.0, "A single slow low zombie groan from a dead man's rasping throat, wet and breathy, no music"),
    ("groan_brute", 4, 2, 2.0, "A huge hulking zombie groaning very low and deep, heavy chest, rumbling, no music"),
    ("groan_crawler", 4, 2, 1.5, "A weak pained zombie moan, thin reedy voice, short of breath, no music"),
    ("alert", 4, 3, 1.0, "A zombie noticing prey: a short rising rasping snarl, hungry and angry, no music"),
    ("attack", 4, 3, 1.0, "A zombie lunging to attack: a guttural growling snarl and bite, aggressive, no music"),
    ("hurt", 4, 3, 0.8, "A zombie hit by a bullet: a short pained grunt and gasp, raspy, no music"),
    ("death", 3, 3, 1.5, "A zombie dying: a rattling last groan that falls away into a wet breath, no music"),
    ("shriek", 3, 3, 1.2, "A fast zombie screaming a shrill raspy shriek as it charges, high and terrifying, no music"),
    (
        "roar",
        3,
        2,
        3.0,
        "A gigantic monstrous zombie boss roaring, deep distorted growl rising to a roar, cinematic, no music",
    ),
]


def clean(mp3: Path, ffmpeg: str, wav: Path) -> np.ndarray:
    subprocess.run(
        [ffmpeg, "-y", "-v", "error", "-i", str(mp3), "-ac", "1", "-ar", str(dsp.SAMPLE_RATE), str(wav)], check=True
    )
    with wave.open(str(wav)) as f:
        x = np.frombuffer(f.readframes(f.getnframes()), "<i2").astype(float) / 32768
    loud = np.nonzero(np.abs(x) > np.abs(x).max() * 10 ** (-40 / 20))[0]
    x = x[max(loud[0] - dsp.samples(0.005), 0) : loud[-1] + 1] if len(loud) else x
    x = dsp.trim_tail(x, -50.0)
    return dsp.normalize(dsp.fade(x, 0.003, 0.05), PEAK_DB)


def write_ogg(x: np.ndarray, ffmpeg: str, wav: Path, ogg: Path) -> None:
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(wav), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(dsp.SAMPLE_RATE)
        f.writeframes(pcm.tobytes())
    cmd = [ffmpeg, "-y", "-v", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4"]
    subprocess.run([*cmd, "-fflags", "+bitexact", "-flags:a", "+bitexact", str(ogg)], check=True)


def main() -> None:
    import requests

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--only")
    parser.add_argument("--dry-run", action="store_true", help="print the plan and its credit cost, call nothing")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    plan = [
        (n, v0 + i, secs, text) for n, v0, takes, secs, text in TAKES for i in range(takes) if not only or n in only
    ]
    plan = [p for p in plan if not (OUT / f"{p[0]}_{p[1]}.ogg").exists()]
    print(f"{len(plan)} takes, {sum(p[2] for p in plan):.1f} s, {sum(p[2] for p in plan) * 40:.0f} credits")
    if args.dry_run or not plan:
        return
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set")
    with tempfile.TemporaryDirectory() as tmp:
        for name, variant, seconds, text in plan:
            body = {"text": text, "duration_seconds": seconds, "prompt_influence": 0.6}
            r = requests.post(
                API,
                params={"output_format": "mp3_44100_128"},
                headers={"xi-api-key": key},
                json=body,
                timeout=120,
            )
            if r.status_code != 200:
                sys.exit(f"{name}_{variant}: HTTP {r.status_code} {r.text[:200]}")
            mp3 = Path(tmp) / "take.mp3"
            mp3.write_bytes(r.content)
            x = clean(mp3, args.ffmpeg, Path(tmp) / "take.wav")
            write_ogg(x, args.ffmpeg, Path(tmp) / "out.wav", OUT / f"{name}_{variant}.ogg")
            print(f"{name}_{variant}.ogg {len(x) / dsp.SAMPLE_RATE:.2f} s")


if __name__ == "__main__":
    main()
