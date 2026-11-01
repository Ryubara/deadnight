"""Extra takes of the dead's voices from ElevenLabs Sound Effects (free tier), picked by analysis and encoded.

    ELEVENLABS_API_KEY=... uv run --with numpy --with scipy --with requests python tools/audio/elevenlabs_zombies.py
        --ffmpeg <pinned ffmpeg> --cache <folder for the raw takes> [--only name,...] [--dry-run] [--no-generate]

The key is read from the environment and never printed or written. Two steps:

1. **Generate.** For each sound, `CANDIDATES` fresh takes (`MODEL`, falling back to `FALLBACK_MODEL` when the API does
   not know it) are requested and the raw mp3s kept in `--cache`; a take already cached is not requested again, so a
   rerun costs nothing (40 credits a second of requested length).
2. **Pick.** Every candidate and the takes already in the game are cleaned (leading and trailing silence trimmed,
   a gentle low-pass at `LOWPASS_HZ` on the voices, fades, normalised to the synthesised variants' peak) and scored:
   hiss above 5 kHz, silence inside the take, a slow onset for the short sounds, and clipping (rejected). The best
   ones fill the sound's slots in `game/assets/audio/zombie/` and `eleven.json` (file, model, prompt, seconds) is
   rewritten; `LICENSE.md` lists it.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))

import dsp

API = "https://api.elevenlabs.io/v1/sound-generation"
MODEL = "eleven_text_to_sound_v3"
FALLBACK_MODEL = "eleven_text_to_sound_v2"
OUT = Path("game/assets/audio/zombie")
MANIFEST = OUT / "eleven.json"
PEAK_DB = -3.0
LOWPASS_HZ = 8000.0
INFLUENCE = 0.45
CANDIDATES = 3

# name, first slot (after the synthesised variants), slots, seconds, short (an onset matters), low-pass, prompt
SOUNDS = [
    (
        "groan",
        5,
        3,
        2.0,
        False,
        True,
        "One-shot, a dead man's low guttural groan, wet throat rattle, slow and breathy, close-mic, dry, no reverb, no music",
    ),
    (
        "groan_brute",
        4,
        2,
        2.0,
        False,
        True,
        "One-shot, a huge hulking zombie's deep rumbling groan from a heavy chest, very low, close-mic, dry, no reverb",
    ),
    (
        "groan_crawler",
        4,
        2,
        1.5,
        False,
        True,
        "One-shot, a weak pained zombie moan, thin reedy voice, short of breath, close-mic, dry, no reverb, no music",
    ),
    (
        "alert",
        4,
        3,
        1.0,
        True,
        True,
        "One-shot, an undead man's short rising rasping snarl as he spots prey, guttural, close-mic, dry, no reverb",
    ),
    (
        "attack",
        4,
        3,
        1.0,
        True,
        True,
        "One-shot, a zombie lunging to bite: a short guttural growl and snarl, aggressive, close-mic, dry, no reverb",
    ),
    (
        "hurt",
        4,
        3,
        0.8,
        True,
        True,
        "One-shot, a zombie shot by a bullet, a short pained raspy grunt and gasp, close-mic, dry, no reverb",
    ),
    (
        "death",
        3,
        3,
        1.5,
        True,
        True,
        "One-shot, a zombie dying, a rattling last groan falling away into a wet breath, close-mic, dry, no reverb",
    ),
    (
        "shriek",
        3,
        3,
        1.2,
        True,
        False,
        "One-shot, a fast undead runner screaming a shrill raspy shriek as it charges, high, close-mic, dry, no reverb",
    ),
    (
        "roar",
        3,
        2,
        3.0,
        False,
        True,
        "One-shot, a gigantic monstrous zombie boss roaring, deep distorted growl rising to a roar, dry, no reverb, no music",
    ),
]

# The prompts of the first run (v2, 0.6), whose takes are in the game before this script picked among candidates.
FIRST_RUN_PROMPTS = {
    "groan": "A single slow low zombie groan from a dead man's rasping throat, wet and breathy, no music",
    "groan_brute": "A huge hulking zombie groaning very low and deep, heavy chest, rumbling, no music",
    "groan_crawler": "A weak pained zombie moan, thin reedy voice, short of breath, no music",
    "alert": "A zombie noticing prey: a short rising rasping snarl, hungry and angry, no music",
    "attack": "A zombie lunging to attack: a guttural growling snarl and bite, aggressive, no music",
    "hurt": "A zombie hit by a bullet: a short pained grunt and gasp, raspy, no music",
    "death": "A zombie dying: a rattling last groan that falls away into a wet breath, no music",
    "shriek": "A fast zombie screaming a shrill raspy shriek as it charges, high and terrifying, no music",
    "roar": "A gigantic monstrous zombie boss roaring, deep distorted growl rising to a roar, cinematic, no music",
}


def run_ffmpeg(ffmpeg: str, *args: str) -> None:
    subprocess.run([ffmpeg, "-y", "-v", "error", *args], check=True)


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path)) as f:
        return np.frombuffer(f.readframes(f.getnframes()), "<i2").astype(float) / 32768


def decode(src: Path, ffmpeg: str, tmp: Path) -> np.ndarray:
    wav = tmp / "decode.wav"
    run_ffmpeg(ffmpeg, "-i", str(src), "-ac", "1", "-ar", str(dsp.SAMPLE_RATE), str(wav))
    return read_wav(wav)


def clean(x: np.ndarray, lowpass: bool) -> np.ndarray:
    """Trim the lead-in to where it first rises within 24 dB of the peak and the tail, soften the hiss, fade."""
    loud = np.nonzero(np.abs(x) > np.abs(x).max() * 10 ** (-24 / 20))[0]
    if len(loud):
        x = x[max(loud[0] - dsp.samples(0.005), 0) :]
    x = dsp.trim_tail(x, -50.0)
    if lowpass:
        x = signal.sosfilt(signal.butter(2, LOWPASS_HZ / (dsp.SAMPLE_RATE / 2), output="sos"), x)
    return dsp.normalize(dsp.fade(x, 0.003, 0.05), PEAK_DB)


def score(x: np.ndarray, short: bool) -> float:
    """Lower is better: hiss above 5 kHz, silence inside the take and (for the short sounds) a slow onset."""
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / dsp.SAMPLE_RATE)
    hiss = spectrum[freqs > 5000].sum() / (spectrum.sum() + 1e-12)
    win = dsp.samples(0.02)
    rms = np.sqrt(np.convolve(x**2, np.ones(win) / win, mode="same"))
    quiet = float((rms < rms.max() * 10 ** (-35 / 20)).mean())
    onset = float(np.argmax(rms > rms.max() * 10 ** (-12 / 20))) / dsp.SAMPLE_RATE
    slow = max(onset - 0.12, 0.0) * 2.0 if short else max(onset - 0.15, 0.0) * 2.0
    return hiss + 0.5 * quiet + slow


def write_ogg(x: np.ndarray, ffmpeg: str, tmp: Path, ogg: Path) -> None:
    wav = tmp / "out.wav"
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(wav), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(dsp.SAMPLE_RATE)
        f.writeframes(pcm.tobytes())
    run_ffmpeg(
        ffmpeg,
        "-i",
        str(wav),
        "-c:a",
        "libvorbis",
        "-q:a",
        "4",
        "-fflags",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        str(ogg),
    )


def generate(sounds: list, cache: Path, key: str, dry: bool) -> None:
    import requests

    plan = [(s, k) for s in sounds for k in range(CANDIDATES) if not (cache / f"{s[0]}_{k}.mp3").exists()]
    seconds = sum(s[3] for s, _ in plan)
    print(f"{len(plan)} new takes, {seconds:.1f} s, {seconds * 40:.0f} credits")
    if dry or not plan:
        return
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set")
    model = MODEL
    for (name, _slot, _n, secs, _short, _lp, prompt), k in plan:
        for attempt in (0, 1):
            body = {"text": prompt, "duration_seconds": secs, "prompt_influence": INFLUENCE, "model_id": model}
            r = requests.post(
                API, params={"output_format": "mp3_44100_128"}, headers={"xi-api-key": key}, json=body, timeout=120
            )
            if r.status_code != 200 and attempt == 0 and model == MODEL and "model" in r.text.lower():
                model = FALLBACK_MODEL
                print(f"{MODEL} refused, using {model}")
                continue
            break
        if r.status_code != 200:
            sys.exit(f"{name}_{k}: HTTP {r.status_code} {r.text[:200]}")
        (cache / f"{name}_{k}.mp3").write_bytes(r.content)
        (cache / f"{name}_{k}.model").write_text(model)
        print(f"{name}_{k}.mp3 ({model})")


def pick(sounds: list, cache: Path, ffmpeg: str, tmp: Path) -> None:
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    for name, slot0, slots, secs, short, lowpass, prompt in sounds:
        pool = []  # (score, label, samples, model, prompt, seconds)
        for i in range(slots):
            ogg = OUT / f"{name}_{slot0 + i}.ogg"
            if ogg.exists():
                old = manifest.get(
                    ogg.name,
                    {"model": FALLBACK_MODEL, "prompt": FIRST_RUN_PROMPTS[name], "seconds": secs, "influence": 0.6},
                )
                x = decode(ogg, ffmpeg, tmp)
                pool.append(
                    (
                        score(x, short),
                        ogg.name,
                        ogg.read_bytes(),
                        old["model"],
                        old["prompt"],
                        old["seconds"],
                        old.get("influence", 0.6),
                    )
                )
        for k in range(CANDIDATES):
            mp3 = cache / f"{name}_{k}.mp3"
            if not mp3.exists():
                continue
            x = clean(decode(mp3, ffmpeg, tmp), lowpass)
            if (np.abs(x) > 0.999).any():
                continue
            model = (cache / f"{name}_{k}.model").read_text() if (cache / f"{name}_{k}.model").exists() else MODEL
            pool.append((score(x, short), f"candidate {k}", x, model, prompt, secs, INFLUENCE))
        pool.sort(key=lambda p: p[0])
        print(name, [(p[1], round(p[0], 3), p[3][-2:]) for p in pool])
        for i, (_s, _label, x, model, text, seconds, influence) in enumerate(pool[:slots]):
            file = f"{name}_{slot0 + i}.ogg"
            if isinstance(x, bytes):  # a take already in the game keeps its exact file
                (OUT / file).write_bytes(x)
            else:
                write_ogg(x, ffmpeg, tmp, OUT / file)
            manifest[file] = {"model": model, "prompt": text, "seconds": seconds, "influence": influence}
    MANIFEST.write_text(json.dumps(dict(sorted(manifest.items())), indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--only")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-generate", action="store_true")
    args = parser.parse_args()
    only = set(args.only.split(",")) if args.only else None
    sounds = [s for s in SOUNDS if not only or s[0] in only]
    args.cache.mkdir(parents=True, exist_ok=True)
    if not args.no_generate:
        generate(sounds, args.cache, os.environ.get("ELEVENLABS_API_KEY", ""), args.dry_run)
    if args.dry_run:
        return
    tmp = args.cache / "tmp"
    tmp.mkdir(exist_ok=True)
    pick(sounds, args.cache, args.ffmpeg, tmp)


if __name__ == "__main__":
    main()
