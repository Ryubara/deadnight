"""The soldiers' voice lines: ElevenLabs text to speech, one request per line, encoded for the game.

    ELEVENLABS_API_KEY=... uv run --with requests python tools/audio/elevenlabs_voice.py
        --ffmpeg <pinned ffmpeg> --cache <folder for the raw takes> [--voice male|female]
        <command> [--only event,...] [--budget N]

Two voices, the same events and number of takes each: `male` (default; `soldier_voice.json` into
`game/assets/audio/voice/soldier/`) and `female` (`soldier_voice_female.json` into
`game/assets/audio/voice/soldier_female/`). Each voice has its own cache folder.

Commands:

- `plan`      the table of every take (file, event, characters, text) and the characters still to be requested;
              nothing is sent. Refuses when the characters to request are over `--budget`.
- `generate`  requests every take that is not in `--cache` yet (a take is never requested twice: the raw mp3 and the
              request that made it are kept); run `encode` after it.
- `encode`    trims, levels (to `target_lufs` in the voice's json, peak limited to -1 dBFS) and writes Ogg Vorbis
              into the voice's folder, plus `manifest.json` (file -> event, text, characters, model, voice,
              settings, seed, seconds, loudness).
              `--plan free --generated 2026-11-04` records the plan and the day in each manifest entry it writes
              (the licence's regeneration list, #252, reads them); `--only` keeps the other entries as they are.
- `check`     transcribes each take (`POST /v1/speech-to-text`, model `scribe_v1`; it costs credits, about 8 a
              take, so a transcript is kept in `--cache` and never fetched twice) and flags the takes where an audio
              tag was spoken aloud (its words in the transcript outside Scribe's own `[laughs]` marks) or words are
              missing, so only those are regenerated (delete the take from `--cache` and run `generate` again).
- `credits`   prints the free tier's characters used and left.

The key is read from the environment and never printed or written. The lines, voice, model and settings are data in
`tools/audio/soldier_voice.json` (the maintainer approved them on 2026-11-01); the two `samples` are takes the
maintainer listened to, copied into the cache and encoded like the rest, not requested again. The female voice's
settings are the male voice's (same model and settings, a premade female voice) and it has no samples.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).parent
VOICES = {
    "male": (HERE / "soldier_voice.json", Path("game/assets/audio/voice/soldier")),
    "female": (HERE / "soldier_voice_female.json", Path("game/assets/audio/voice/soldier_female")),
}
API = "https://api.elevenlabs.io/v1"
TAG = re.compile(r"\[[^\]]*\]")
SEED_BASE = 1958
PEAK_LIMIT = 0.891  # -1 dBFS
FADE_IN = 0.004
FADE_OUT = 0.06


def load(voice: str = "male") -> dict:
    return json.loads(VOICES[voice][0].read_text(encoding="utf-8"))


def takes(data: dict) -> list[dict]:
    """Every take in order: its file name, event, text, and the sample it is (if it is one)."""
    samples = data.get("samples", {})
    out = []
    seed_index = 0
    for event, lines in data["events"].items():
        reserved = {name for name in samples if name.rsplit("_", 1)[0] == event}
        queue = list(lines)
        total = len(lines) + len(reserved)
        for n in range(1, total + 1):
            name = f"{event}_{n}"
            seed_index += 1
            if name in samples:
                out.append(
                    {"name": name, "event": event, "text": samples[name]["text"], "sample": samples[name]["file"]}
                )
            else:
                out.append(
                    {"name": name, "event": event, "text": queue.pop(0), "sample": "", "seed": SEED_BASE + seed_index}
                )
    return out


def spoken(text: str) -> str:
    """The words a listener should hear: the line without its audio tags."""
    return re.sub(r"\s+", " ", TAG.sub(" ", text)).strip()


def key() -> str:
    value = os.environ.get("ELEVENLABS_API_KEY", "")
    if not value:
        sys.exit("ELEVENLABS_API_KEY is not set")
    return value


def credits() -> tuple[int, int]:
    import requests

    r = requests.get(f"{API}/user/subscription", headers={"xi-api-key": key()}, timeout=60)
    r.raise_for_status()
    d = r.json()
    return int(d["character_count"]), int(d["character_limit"])


def pending(all_takes: list[dict], cache: Path) -> list[dict]:
    return [t for t in all_takes if not t["sample"] and not (cache / f"{t['name']}.mp3").exists()]


def plan(all_takes: list[dict], cache: Path, budget: int) -> int:
    todo = {t["name"] for t in pending(all_takes, cache)}
    print(f"{'file':20s}{'chars':>6s}  {'state':8s} text")
    for t in all_takes:
        state = "sample" if t["sample"] else ("request" if t["name"] in todo else "cached")
        print(f"{t['name']:20s}{len(t['text']):6d}  {state:8s} {t['text']}")
    chars = sum(len(t["text"]) for t in all_takes if t["name"] in todo)
    total = sum(len(t["text"]) for t in all_takes)
    print(f"\n{len(all_takes)} takes, {total} characters in all, {chars} still to request (budget {budget})")
    if chars > budget:
        sys.exit(f"over budget by {chars - budget} characters")
    return chars


def generate(all_takes: list[dict], data: dict, cache: Path) -> None:
    import requests

    k = key()
    for t in pending(all_takes, cache):
        body = {
            "text": t["text"],
            "model_id": data["model_id"],
            "voice_settings": data["voice_settings"],
            "seed": t["seed"],
        }
        r = requests.post(
            f"{API}/text-to-speech/{data['voice_id']}",
            params={"output_format": data["output_format"]},
            headers={"xi-api-key": k},
            json=body,
            timeout=180,
        )
        if r.status_code != 200:
            sys.exit(f"{t['name']}: HTTP {r.status_code} {r.text[:200]}")
        (cache / f"{t['name']}.mp3").write_bytes(r.content)
        (cache / f"{t['name']}.json").write_text(json.dumps(body, indent=2), encoding="utf-8")
        print(f"{t['name']}.mp3 ({len(t['text'])} characters)")


def ffmpeg(exe: str, *args: str) -> str:
    done = subprocess.run([exe, "-y", "-nostats", "-v", "info", *args], capture_output=True, text=True, check=True)
    return done.stderr


def loudness(exe: str, wav: Path) -> float:
    log = ffmpeg(exe, "-i", str(wav), "-af", "ebur128=peak=true", "-f", "null", "-")
    found = re.findall(r"\bI:\s+(-?[\d.]+) LUFS", log)
    return float(found[-1]) if found else -70.0


def seconds_of(wav: Path) -> float:
    with wave.open(str(wav)) as f:
        return f.getnframes() / f.getframerate()


def encode(
    all_takes: list[dict], data: dict, cache: Path, exe: str, samples_dir: Path, out: Path, stamp: dict | None = None
) -> None:
    out.mkdir(parents=True, exist_ok=True)
    # Takes encoded earlier stay in the manifest when only some events are encoded (`--only`).
    saved = out / "manifest.json"
    manifest = json.loads(saved.read_text(encoding="utf-8")) if saved.exists() else {}
    trim = (
        "silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.02,"
        "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.12,areverse"
    )
    with tempfile.TemporaryDirectory() as tmp_name:
        tmp = Path(tmp_name)
        for t in all_takes:
            src = samples_dir / t["sample"] if t["sample"] else cache / f"{t['name']}.mp3"
            if not src.exists():
                print(f"missing {src.name}, skipped")
                continue
            trimmed = tmp / "trimmed.wav"
            ffmpeg(exe, "-i", str(src), "-ac", "1", "-ar", "44100", "-af", trim, str(trimmed))
            lufs = loudness(exe, trimmed)
            gain = data["target_lufs"] - lufs
            length = seconds_of(trimmed)
            ogg = out / f"{t['name']}.ogg"
            chain = (
                f"volume={gain:.2f}dB,alimiter=limit={PEAK_LIMIT}:level=disabled,"
                f"afade=t=in:d={FADE_IN},afade=t=out:st={max(length - FADE_OUT, 0):.3f}:d={FADE_OUT}"
            )
            ffmpeg(
                exe, "-i", str(trimmed), "-af", chain, "-c:a", "libvorbis", "-q:a", "3",
                "-fflags", "+bitexact", "-flags:a", "+bitexact", str(ogg),
            )  # fmt: skip
            request = cache / f"{t['name']}.json"
            seed = json.loads(request.read_text(encoding="utf-8")).get("seed") if request.exists() else None
            manifest[ogg.name] = {
                "event": t["event"],
                "text": t["text"],
                "characters": len(t["text"]),
                "model_id": data["model_id"],
                "voice": data["voice"],
                "voice_id": data["voice_id"],
                "voice_settings": data["voice_settings"],
                "output_format": data["output_format"],
                "seed": seed,
                "source": "maintainer-approved sample" if t["sample"] else "text-to-speech",
                "seconds": round(length, 2),
                "lufs_before": round(lufs, 1),
                **(stamp or {}),
            }
            print(f"{ogg.name}: {length:.2f} s, {lufs:.1f} LUFS -> {data['target_lufs']}")
    names = [f"{t['name']}.ogg" for t in takes(data)]
    manifest = {name: manifest[name] for name in names if name in manifest}
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    (out / "manifest.json").write_text(text, encoding="utf-8", newline="\n")


def words(text: str) -> list[str]:
    return re.findall(r"[a-z']+", text.lower())


def check(all_takes: list[dict], cache: Path) -> int:
    """Transcribe every take; flag a tag spoken aloud (its words in the transcript but not the line) or lost words."""
    import requests

    flagged = 0
    for t in all_takes:
        src = cache / (t["sample"] or f"{t['name']}.mp3")
        saved = cache / f"{t['name']}.stt.json"
        if not saved.exists():
            k = key()
            with src.open("rb") as f:
                r = requests.post(
                    f"{API}/speech-to-text",
                    headers={"xi-api-key": k},
                    data={"model_id": "scribe_v1"},
                    files={"file": (src.name, f, "audio/mpeg")},
                    timeout=180,
                )
            if r.status_code != 200:
                sys.exit(f"{t['name']}: HTTP {r.status_code} {r.text[:200]}")
            saved.write_text(json.dumps(r.json(), indent=2), encoding="utf-8")
        heard = json.loads(saved.read_text(encoding="utf-8")).get("text", "")
        # Scribe writes the sounds it hears in brackets ("[laughs]"): those were performed, not spoken.
        heard_words = words(re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", heard))
        line_words = set(words(spoken(t["text"])))
        tag_words = set(words(" ".join(TAG.findall(t["text"])))) - line_words
        spoken_tags = sorted(tag_words & set(heard_words))
        missing = [w for w in words(spoken(t["text"])) if w not in heard_words]
        problem = bool(spoken_tags) or len(missing) > max(2, len(line_words) // 4)
        flagged += problem
        mark = "FLAG" if problem else "ok  "
        print(f"{mark} {t['name']:18s} heard: {heard}" + (f"   [spoke tag: {spoken_tags}]" if spoken_tags else ""))
        if problem and missing:
            print(f"     missing: {missing}")
    print(f"{flagged} of {len(all_takes)} flagged")
    return flagged


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["plan", "generate", "encode", "check", "credits"])
    parser.add_argument("--voice", choices=sorted(VOICES), default="male")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--samples", type=Path, help="folder of the approved sample mp3s (default: the cache)")
    parser.add_argument("--only", help="comma-separated events")
    parser.add_argument("--budget", type=int, default=6500)
    parser.add_argument("--plan", help="`encode`: the ElevenLabs plan that made the takes (free, creator ...)")
    parser.add_argument("--generated", help="`encode`: the date the takes were requested (YYYY-MM-DD)")
    args = parser.parse_args()
    data = load(args.voice)
    if args.command == "credits":
        used, limit = credits()
        print(f"{used} of {limit} characters used, {limit - used} left")
        return
    if args.cache is None:
        sys.exit("--cache is required")
    args.cache.mkdir(parents=True, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None
    all_takes = [t for t in takes(data) if not only or t["event"] in only]
    samples_dir = args.samples or args.cache
    if args.command == "plan":
        plan(all_takes, args.cache, args.budget)
    elif args.command == "generate":
        plan(all_takes, args.cache, args.budget)
        generate(all_takes, data, args.cache)
    elif args.command == "encode":
        if not args.ffmpeg:
            sys.exit("--ffmpeg is required")
        stamp = {}
        if args.plan:
            stamp["plan"] = args.plan
        if args.generated:
            stamp["generated"] = args.generated
        encode(all_takes, data, args.cache, args.ffmpeg, samples_dir, VOICES[args.voice][1], stamp)
    elif args.command == "check":
        check(all_takes, args.cache)


if __name__ == "__main__":
    main()
