"""Levels and reach of the second map's sounds (issue #657), measured without ears.

    uv run --with numpy --with scipy python tools/audio/smallmap_levels.py table --ffmpeg <ffmpeg>
    uv run --with numpy --with scipy python tools/audio/smallmap_levels.py capture mix.wav tour.log

`table` reads each sound's trim, reach and fall-off from the banks under `game/core/audio/banks/`, the file's own loudness
from the Ogg itself (decoded with the pinned ffmpeg), and the wall, window and slew numbers from
`smallmap_sound_tuning_default.tres`, and prints for each sound: its level at 1 m (file RMS plus trim, dBFS), how far it
carries in open air before it falls to the audible floor (`FLOOR_DBFS`: 12 dB under the room tone, which is itself at the
level of the game's other beds) and what it is behind a boarded window, an open one and a wall at the geometry of the first
window. The fall-off is the engine's inverse distance, `unit_size / (unit_size + distance)`, the same rule
`AudioStreamPlayer3D` and `SmallMapWays` use. `capture` reads a Movie Maker mix (`audio_smallmap_tour.tscn`) and the
`STAGE` and `SOUND` lines it printed, and prints the mix's level in each stage and where every sound started.
"""

from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from analyze import db, read_wav

BANKS = Path("game/core/audio/banks")
TUNING = Path("game/gameplay/night/smallmap_sound_tuning_default.tres")
AUDIO = Path("game/assets/audio")
# The audible floor in dBFS RMS: the room tone (-36) less 12 dB.
FLOOR_DBFS = -48.0
# The geometry of the first window from a listener in line with it: the listener is 4.65 m from the window and the
# source 25.35 m beyond it (`test_smallmap_sounds.gd`).
NEAR, BEYOND = 4.65, 25.35
SOUNDS = [
    "bed_room_tone",
    "bed_roof_wind",
    "yard_wind",
    "yard_fire",
    "yard_wire",
    "yard_road",
    "yard_rattle",
    "debris_clear",
    "step_wood",
    "step_own_wood",
]
# The game's other sounds the new ones are set beside.
COMPARE = [
    "bed_crickets",
    "bed_highway",
    "bed_projector",
    "board_tear",
    "door_open",
    "step_own_asphalt",
    "step_asphalt",
]


def parse_defs() -> dict[str, dict[str, str]]:
    found: dict[str, dict[str, str]] = {}
    for bank in sorted(BANKS.glob("*.tres")):
        for block in re.split(r"\n(?=\[sub_resource)", bank.read_text(encoding="utf-8")):
            name = re.search(r'resource_name = "([^"]+)"', block)
            if name:
                found[name.group(1)] = dict(re.findall(r"^(\w+) = (.+)$", block, re.MULTILINE))
    return found


def parse_tuning() -> dict[str, float]:
    return {
        k: float(v) for k, v in re.findall(r"^(\w+) = (-?[\d.]+)$", TUNING.read_text(encoding="utf-8"), re.MULTILINE)
    }


def file_rms(ffmpeg: str, path: Path) -> tuple[float, float]:
    """RMS and peak in dBFS of an Ogg, mono mix of all its channels, decoded."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        subprocess.run([ffmpeg, "-y", "-v", "error", "-i", str(path), str(wav)], check=True)
        data, _ = read_wav(wav)
    mono = data.mean(axis=0)
    return db(np.sqrt((mono**2).mean())), db(np.abs(mono).max())


def first_file(defs: dict[str, str]) -> Path:
    fmt = defs["path_format"].strip('"').replace("res://assets/audio/", "")
    return AUDIO / (fmt % 1 if "%d" in fmt else fmt)


def fall(unit: float, distance: float) -> float:
    return 20 * math.log10(unit / (unit + distance))


def carry(level_1m: float, unit: float, maximum: float) -> float:
    """Metres at which `level_1m` (RMS dBFS at 1 m, taken as at the source) falls to the audible floor."""
    need = FLOOR_DBFS - level_1m
    if need >= 0:
        return 0.0
    ratio = 10 ** (need / 20)
    return min(unit / ratio - unit, maximum)


def table(ffmpeg: str) -> None:
    defs = parse_defs()
    tuning = parse_tuning()
    print(f"audible floor {FLOOR_DBFS:.0f} dBFS RMS; geometry of window 1: {NEAR} m in, {BEYOND} m out")
    print(
        f"{'sound':16} {'file rms':>8} {'trim':>6} {'at 1 m':>7} {'unit':>5} {'reach':>6} {'carry':>6}"
        f" {'boarded':>8} {'open':>6} {'wall':>6}"
    )
    for name in SOUNDS + COMPARE:
        d = defs[name]
        rms, peak = file_rms(ffmpeg, first_file(d))
        trim = float(d["volume_db"])
        unit, reach = float(d["unit_size"]), float(d["max_distance"])
        level = rms + trim
        row = f"{name:16} {rms:8.1f} {trim:6.1f} {level:7.1f} {unit:5.1f} {reach:6.0f} {carry(level, unit, reach):6.0f}"
        if name.startswith("yard"):
            total = NEAR + BEYOND
            way = fall(unit, total)
            boarded = level + way + tuning["boarded_db"]
            opened = level + way + tuning["open_db"]
            wall = level + fall(unit, total) + tuning["wall_db"]
            row += f" {boarded:8.1f} {opened:6.1f} {wall:6.1f}"
        print(row + ("   (existing)" if name in COMPARE else ""))
        _ = peak


def read_log(path: Path) -> tuple[list[tuple[float, str]], list[tuple[float, str]]]:
    stages, sounds = [], []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"STAGE (\d+\.\d+) (.*)$", line)
        if m and not m.group(2).startswith("event "):
            stages.append((float(m.group(1)), m.group(2)))
        m = re.match(r"SOUND (\d+\.\d+) (\S+)$", line)
        if m:
            sounds.append((float(m.group(1)), m.group(2)))
    return stages, sounds


def capture(wav: Path, log: Path, stage_names: list[tuple[float, str]] | None = None) -> None:
    data, rate = read_wav(wav)
    mono = data.mean(axis=0)
    # Movie Maker writes the mix at twice the clock the frames run on in some builds: the length says which.
    stages, sounds = read_log(log)
    print(f"mix {len(mono) / rate:.1f} s at {rate} Hz, peak {db(np.abs(mono).max()):.1f} dBFS")
    print(f"{'from':>6} {'to':>6} {'rms dBFS':>9} {'peak':>7}  stage")
    names = stage_names or stages
    for i, (start, name) in enumerate(names):
        end = names[i + 1][0] if i + 1 < len(names) else len(mono) / rate
        a, b = int((start + (end - start) * 0.4) * rate), int(end * rate)
        part = mono[a:b]
        if len(part) == 0:
            continue
        print(f"{start:6.1f} {end:6.1f} {db(np.sqrt((part**2).mean())):9.1f} {db(np.abs(part).max()):7.1f}  {name}")
    print("sounds started:")
    for t, name in sounds:
        print(f"  {t:6.2f}  {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    t = sub.add_parser("table")
    t.add_argument("--ffmpeg", required=True)
    c = sub.add_parser("capture")
    c.add_argument("wav", type=Path)
    c.add_argument("log", type=Path)
    args = parser.parse_args()
    if args.command == "table":
        table(args.ffmpeg)
    else:
        capture(args.wav, args.log)


if __name__ == "__main__":
    main()
