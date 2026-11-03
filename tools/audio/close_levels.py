"""How loud each close sound gets right beside the listener, from a recording (Deadnight #753).

    uv run --with numpy --with scipy python tools/audio/close_levels.py --run <folder> --ffmpeg <pinned ffmpeg> \
        --out <folder> [--table game/tests/core/close_sound_levels.json]

`--run` is a run of `game/tests/captures/audio_headroom.tscn --own=none --cells=zombie,world --all-variants --close`
(its folder holds `mix.wav` and `run.log`; the sounds play one at a time, a file's length apart, 1.2 m from the
listener, where the player's `max_db` holds every sound, not the distance). Writes into `--out`:
- `close_levels.md`: each sound, loudest first, with the ceiling it was held to (`max_db`, dB over its file), the
  highest sample of any of its variants (dBFS) and the loudness of its loudest 400 ms (LUFS);
- `close_levels.json`: the same numbers.
`--table` also writes the pinned table the test `tests/core/test_close_sound_levels.gd` reads: `max_db`,
`close_peak_dbfs` and (with `--ffmpeg`) `close_lufs`, the loudest 400 ms, per sound, to be written again whenever a
sound's cap or trim, or a file, changes.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from analyze import db, read_wav
from headroom import loudness


def write(path: Path, text: str) -> None:
    """Write `text` with LF line endings, whatever the platform (the repository keeps LF)."""
    with path.open("w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def parse(log: Path) -> tuple[list[tuple[float, str, str]], dict[str, float]]:
    """The `PLAY` lines of the close cells (time, cell, sound) and each sound's `MAXDB`."""
    plays: list[tuple[float, str, str]] = []
    ceilings: dict[str, float] = {}
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"PLAY ([\d.]+) none (zombie|world) (\S+)", line)
        if m:
            plays.append((float(m.group(1)), m.group(2), m.group(3)))
        m = re.match(r"MAXDB (\S+) (-?[\d.]+)", line)
        if m:
            ceilings[m.group(1)] = max(ceilings.get(m.group(1), -99.0), float(m.group(2)))
    return plays, ceilings


def measure(folder: Path, ffmpeg: str | None) -> dict[str, dict]:
    data, rate = read_wav(folder / "mix.wav")
    plays, ceilings = parse(folder / "run.log")
    sounds: dict[str, dict] = {}
    for k, (start, cell, sound) in enumerate(plays):
        nxt = plays[k + 1][0] if k + 1 < len(plays) and plays[k + 1][1] == cell else start + 3.0
        segment = data[:, int(start * rate) : int(nxt * rate)]
        peak = db(float(np.abs(segment).max()))
        row = sounds.setdefault(sound, {"max_db": ceilings.get(sound), "close_peak_dbfs": -120.0, "variants": 0})
        row["close_peak_dbfs"] = max(row["close_peak_dbfs"], peak)
        row["variants"] += 1
        if ffmpeg:
            moment = loudness(segment, rate, ffmpeg)["momentary_max"]
            row["loudest_400ms_lufs"] = max(row.get("loudest_400ms_lufs", -120.0), moment)
    return sounds


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--ffmpeg")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--table", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    sounds = measure(args.run, args.ffmpeg)
    write(args.out / "close_levels.json", json.dumps(sounds, indent=1))
    lines = [
        "| Sound | Held to (dB over its file) | Highest sample of any variant (dBFS) | Loudest 400 ms (LUFS) |",
        "| --- | --- | --- | --- |",
    ]
    for name, r in sorted(sounds.items(), key=lambda kv: -kv[1]["close_peak_dbfs"]):
        lufs = f"{r['loudest_400ms_lufs']:.1f}" if "loudest_400ms_lufs" in r else "-"
        lines.append(f"| {name} | {r['max_db']} | {r['close_peak_dbfs']:.1f} | {lufs} |")
    text = "\n".join(lines) + "\n"
    write(args.out / "close_levels.md", text)
    print(text)
    if args.table:
        table = {
            name: {"max_db": round(r["max_db"], 1), "close_peak_dbfs": round(r["close_peak_dbfs"], 1)}
            | ({"close_lufs": round(r["loudest_400ms_lufs"], 1)} if "loudest_400ms_lufs" in r else {})
            for name, r in sorted(sounds.items())
        }
        write(args.table, json.dumps({"sounds": table}, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
