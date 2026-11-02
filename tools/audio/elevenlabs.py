"""Fetch the few sounds that are generated with ElevenLabs Sound Effects (free tier) instead of synthesised.

    ELEVENLABS_API_KEY=... python tools/audio/elevenlabs.py --ffmpeg <ffmpeg> [--only name,...] [--dry-run]

The key is read from the environment only and is never printed or written. A file that already exists is not fetched
again (the files are committed, so a run costs credits only for a new or deleted entry). Each result is levelled, trimmed and encoded to Ogg
Vorbis in `game/assets/audio/eleven/`; `game/assets/audio/eleven/LICENSE.md` records every file with its prompt.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

ENDPOINT = "https://api.elevenlabs.io/v1/sound-generation"
OUT = Path("game/assets/audio/eleven")
RATE = 44100
PEAK_DB = -1.0
LEAD_DB = -34.0  # the sound starts where it first rises within this many dB of its peak
FADE_OUT = 0.03


@dataclass(frozen=True)
class Clip:
    name: str  # the file is `<name>_<variant>.ogg`
    variants: int
    prompt: str
    seconds: float
    influence: float = 0.6
    loop: bool = False


CLIPS: list[Clip] = [
    Clip(
        "generator_hum",
        1,
        "portable gasoline generator running steadily at constant load, low engine drone, seamless loop, no voices",
        4.0,
        0.5,
        True,
    ),
    Clip("generator_down", 1, "gasoline generator running out of fuel, sputtering and winding down to silence", 3.0),
    Clip(
        "generator_up",
        1,
        "gasoline generator being refuelled and roaring back to life, then settling to a steady run",
        3.0,
    ),
    Clip(
        "door_buy", 2, "heavy steel padlock and chain unlocked, then a creaking metal door swung open on a hinge", 2.2
    ),
]


def fetch(clip: Clip, key: str) -> bytes:
    body = {
        "text": clip.prompt,
        "duration_seconds": clip.seconds,
        "prompt_influence": clip.influence,
        "model_id": "eleven_text_to_sound_v2",
    }
    if clip.loop:
        body["loop"] = True
    request = urllib.request.Request(
        ENDPOINT + "?output_format=mp3_44100_128",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def process(ffmpeg: str, src: Path, ogg: Path, loop: bool) -> None:
    """Decode, cut the lead-in before the sound starts, level to a -1 dB peak, trim the dead tail, encode to Ogg.

    The generator's levels and lead-ins vary from file to file (a shot can start 0.3 s in, a peak can sit above full
    scale once decoded), so every file is normalised here and the game balances them with the catalog's `volume_db`.
    A loop keeps its length and its ends. Running it on its own output changes nothing."""
    raw = subprocess.run(
        [ffmpeg, "-v", "error", "-i", str(src), "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
        capture_output=True,
        check=True,
    ).stdout
    x = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    peak = np.abs(x).max()
    if not loop:
        loud = np.nonzero(np.abs(x) > peak * 10 ** (LEAD_DB / 20))[0]
        x = x[max(loud[0] - int(0.004 * RATE), 0) : loud[-1] + 1]
        n = int(FADE_OUT * RATE)
        x[-n:] *= np.linspace(1.0, 0.0, min(n, len(x)))[-n:]
    x = x * (10 ** (PEAK_DB / 20) / np.abs(x).max())
    ogg.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "clip.wav"
        pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
        with wave.open(str(wav), "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(pcm.tobytes())
        cmd = [ffmpeg, "-y", "-v", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "4", str(ogg)]
        subprocess.run(cmd, check=True)


def licence_text() -> str:
    lines = [
        "# Sounds generated with ElevenLabs Sound Effects",
        "",
        "- Generator: ElevenLabs Sound Effects (<https://elevenlabs.io/sound-effects>), free tier, model",
        "  `eleven_text_to_sound_v2`, fetched by `tools/audio/elevenlabs.py`.",
        "- Licence: generated with ElevenLabs Sound Effects (free tier); attribution required; not licensed for",
        "  commercial use. **Replace or relicense before any commercial release** (tracking issue #252).",
        "- Credit: ElevenLabs (the Credits screen names it).",
        "",
        "| Files | Prompt | Seconds |",
        "| --- | --- | --- |",
    ]
    for clip in CLIPS:
        files = f"`{clip.name}_1..{clip.variants}.ogg`" if clip.variants > 1 else f"`{clip.name}_1.ogg`"
        lines.append(f"| {files} | {clip.prompt} | {clip.seconds} |")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--only", help="comma-separated clip names")
    parser.add_argument("--dry-run", action="store_true", help="list what would be fetched")
    parser.add_argument("--reprocess", action="store_true", help="re-level and re-trim the files already there")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not key and not args.dry_run:
        sys.exit("ELEVENLABS_API_KEY is not set")
    (OUT).mkdir(parents=True, exist_ok=True)
    (OUT / "LICENSE.md").write_text(licence_text(), encoding="utf-8")
    for clip in CLIPS:
        if only and clip.name not in only:
            continue
        for variant in range(1, clip.variants + 1):
            ogg = OUT / f"{clip.name}_{variant}.ogg"
            if ogg.exists():
                if args.reprocess:
                    with tempfile.TemporaryDirectory() as tmp:
                        copy = Path(tmp) / "in.ogg"
                        copy.write_bytes(ogg.read_bytes())
                        process(args.ffmpeg, copy, ogg, clip.loop)
                continue
            print(f"{'would fetch' if args.dry_run else 'fetching'} {ogg.as_posix()} ({clip.seconds}s)")
            if args.dry_run:
                continue
            with tempfile.TemporaryDirectory() as tmp:
                mp3 = Path(tmp) / "clip.mp3"
                mp3.write_bytes(fetch(clip, key))
                process(args.ffmpeg, mp3, ogg, clip.loop)


if __name__ == "__main__":
    main()
