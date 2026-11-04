"""A clip with the sound in it for a voice pull request: title cards and a waveform over the game's recording.

    uv run --with pillow python tools/audio/voice_clip.py <listen|beside|fight> --ffmpeg <pinned ffmpeg>
        --wav <master mix> --log <capture log> --out <clip.mp4> [--frames <folder of fight frames>]

`game/tests/captures/audio_progression_voice.tscn` plays the progression cheers through the real audio service under
Movie Maker and prints when each one starts; Movie Maker's `.wav` is the master mix. This turns that recording into an
`.mp4` (`gh --attach` takes no `.ogg` or `.wav`; `docs/capture.md#sound-a-clip-you-can-listen-to` in the kit):

- `listen`: one card for each take (`TAKE <seconds> <voice> <moment> <n>`), the line written on it, the waveform below.
- `beside`: the reference shot and groan, then each moment alone and with the shot just before it (`BESIDE ...`).
- `fight`: the night's own frames (`--frames`) with a caption on each moment told to the soldier (`TOLD ...`).

The sound is the recording as it is: no normalising, no limiter, so the listener hears the levels of the game. The
loudest sample of the clip is printed next to the recording's, which match to about 0.1 dB.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
VOICES = {"male": "soldier", "female": "soldier_female"}
SIZE = (960, 540)
WAVE_Y = 300
WAVE_H = 240
FPS = 10
BG = (18, 16, 24)
FONT_PATH = "C:/Windows/Fonts/segoeui.ttf"
FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"


def lines_of() -> dict[str, dict[str, str]]:
    """voice -> `<moment>_<n>` -> the line, from the manifests."""
    out: dict[str, dict[str, str]] = {}
    for voice, folder in VOICES.items():
        manifest = json.loads((ROOT / f"game/assets/audio/voice/{folder}/manifest.json").read_text(encoding="utf-8"))
        out[voice] = {name.removesuffix(".ogg"): entry["text"] for name, entry in manifest.items()}
    return out


def spoken(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", " ", text)).strip()


def card(path: Path, title: str, line: str, note: str) -> None:
    image = Image.new("RGB", SIZE, BG)
    draw = ImageDraw.Draw(image)
    draw.text((40, 36), title, font=ImageFont.truetype(FONT_BOLD, 42), fill=(255, 226, 150))
    y = 110
    for row in wrap(draw, line, ImageFont.truetype(FONT_PATH, 34), SIZE[0] - 80):
        draw.text((40, y), row, font=ImageFont.truetype(FONT_PATH, 34), fill=(235, 235, 240))
        y += 48
    draw.text((40, SIZE[1] - 50), note, font=ImageFont.truetype(FONT_PATH, 22), fill=(150, 150, 165))
    image.save(path)


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int) -> list[str]:
    rows, row = [], ""
    for word in text.split():
        trial = f"{row} {word}".strip()
        if draw.textlength(trial, font=font) > width and row:
            rows.append(row)
            row = word
        else:
            row = trial
    return rows + [row]


def sections(mode: str, log: Path, texts: dict) -> list[tuple[float, str, str, str]]:
    """(start, title, line, note) for every card of `listen` or `beside`."""
    found: list[tuple[float, str, str, str]] = []
    for row in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if mode == "listen" and (m := re.match(r"TAKE ([\d.]+) (\w+) (\w+) (\d+)$", row)):
            at, voice, moment, n = float(m[1]), m[2], m[3], m[4]
            title = f"{moment.replace('_', ' ')}  -  {voice}, take {n} of 3"
            found.append(
                (at, title, spoken(texts[voice][f"{moment}_{n}"]), "the voice bus, the player's own flat voice")
            )
        if mode == "beside" and (m := re.match(r"BESIDE ([\d.]+) (.+)$", row)):
            at, what = float(m[1]), m[2].split()
            if what[0] == "-":
                found.append((at, "reference: " + " ".join(what[2:]), "", "alone, as the player hears it"))
            else:
                voice, moment, how = what
                text = spoken(texts[voice][f"{moment}_1"])
                title = f"{moment.replace('_', ' ')}  -  {voice}, " + (
                    "alone" if how == "alone" else "just after a pistol shot"
                )
                found.append(
                    (
                        at,
                        title,
                        text,
                        "pistol shot at the muzzle, then the line 0.3 s later" if how == "shot" else "alone",
                    )
                )
    return found


def run(exe: str, *args: str) -> str:
    done = subprocess.run([exe, "-y", "-nostats", "-v", "info", *args], capture_output=True, text=True, check=True)
    return done.stderr


def peak(exe: str, media: Path) -> str:
    log = run(exe, "-i", str(media), "-vn", "-af", "volumedetect", "-f", "null", "-")
    found = re.search(r"max_volume: (-?[\d.]+) dB", log)
    return found[1] if found else "?"


def cards_clip(mode: str, args: argparse.Namespace, work: Path) -> None:
    texts = lines_of()
    cards = sections(mode, args.log, texts)
    duration = float(
        run(args.ffmpeg, "-i", str(args.wav), "-f", "null", "-").rsplit("time=", 1)[1].split()[0].split(":")[2]
    )
    head = "Progression voice lines" if mode == "listen" else "Beside a shot and a groan"
    card(
        work / "card_00.png",
        head,
        "",
        "recorded through the real audio service at the default settings, not normalised",
    )
    concat = [("card_00.png", cards[0][0])]
    for i, (start, title, line, note) in enumerate(cards, 1):
        card(work / f"card_{i:02d}.png", title, line, note)
        end = cards[i][0] if i < len(cards) else duration
        concat.append((f"card_{i:02d}.png", end - start))
    text = "".join(f"file '{name}'\nduration {seconds:.3f}\n" for name, seconds in concat) + f"file '{concat[-1][0]}'\n"
    (work / "cards.txt").write_text(text, encoding="utf-8")
    graph = (
        f"[0:a]showwaves=s={SIZE[0]}x{WAVE_H}:mode=cline:rate={FPS}:scale=sqrt:colors=white[w];"
        f"[1:v]fps={FPS},format=yuv420p[b];[b][w]overlay=0:{WAVE_Y}:shortest=1,format=yuv420p[v]"
    )
    run(
        args.ffmpeg, "-i", str(args.wav), "-f", "concat", "-safe", "0", "-i", str(work / "cards.txt"),
        "-filter_complex", graph, "-map", "[v]", "-map", "0:a", "-c:v", "libx264", "-crf", "35", "-preset", "slow",
        "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(args.out),
    )  # fmt: skip


def fight_clip(args: argparse.Namespace) -> None:
    told = []
    for row in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
        if m := re.match(r"CHEER ([\d.]+) (\w+)", row):
            told.append(
                (float(m[1]), re.sub(r"^voxf?_|_\d+$", "", m[2]), "female" if m[2].startswith("voxf_") else "male")
            )
    font = FONT_BOLD.replace(":", "\\:")
    captions = ",".join(
        f"drawtext=fontfile='{font}':text='{moment.replace('_', ' ')}  ({voice})':x=(w-text_w)/2:y=h*0.62:fontsize=34"
        f":fontcolor=#ffe296"
        f":box=1:boxcolor=0x000000AA:boxborderw=14:enable='between(t,{at:.2f},{at + 3.2:.2f})'"
        for at, moment, voice in told
    )
    frames = args.frames.as_posix() + "/" + args.pattern
    run(
        args.ffmpeg, "-framerate", "15", "-i", frames, "-i", str(args.wav),
        "-vf", f"scale=960:-2,{captions},format=yuv420p" if captions else "scale=960:-2,format=yuv420p",
        "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-crf", "30", "-c:a", "aac", "-b:a", "128k",
        "-shortest", "-movflags", "+faststart", str(args.out),
    )  # fmt: skip


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["listen", "beside", "fight"])
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--frames", type=Path, help="fight: the folder of Movie Maker frames")
    parser.add_argument("--pattern", default="fight%08d.png", help="fight: the frames' file name pattern")
    args = parser.parse_args()
    if args.mode == "fight":
        if not args.frames:
            sys.exit("--frames is required for fight")
        fight_clip(args)
    else:
        work = args.out.parent / f"{args.out.stem}-cards"
        work.mkdir(exist_ok=True)
        cards_clip(args.mode, args, work)
    print(
        f"recording peak {peak(args.ffmpeg, args.wav)} dB, clip peak {peak(args.ffmpeg, args.out)} dB, {args.out.stat().st_size / 1e6:.1f} MB"
    )


if __name__ == "__main__":
    main()
