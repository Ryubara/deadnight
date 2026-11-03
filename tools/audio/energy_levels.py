"""Measure the energy weapons, the re-cut layer and the close sounds of the freeze and the burst (Deadnight #791), from
a recording of `game/tools/bench/audio_energy_bench.tscn`.

    uv run --with numpy --with scipy python tools/audio/energy_levels.py mix.wav bench.log --ffmpeg <pinned ffmpeg>
        [--json out.json] [--table game/tests/night/energy_levels.json] [--label energy]

The bench fires, for each slot, one shot and then a two second burst through the game's own `WeaponSounds`,
`EnergySounds` and `RecutLayer`, the audio service and the buses, then runs the night's beds alone, then plays every
variant of the close sounds one at a time 1.2 m ahead. A slot called `<weapon>_recut` is the same weapon with the frame
saying it was re-cut. This prints, as `gun_levels.py` does for the firearms (it is used for the slots): the peak,
the integrated and loudest-400 ms loudness of the shot and of the burst, the centroid and the low-end share, and then
what the re-cut layer changes, weapon by weapon: how much higher the peak of a shot and of a burst is with the layer
than without it (the headroom it takes), how much louder the tail is (the 0.08 to 0.5 s after the report, where the
layer rings) and how much more energy the 2 to 8 kHz band has there, the share of the report's low end it leaves. And
the highest sample and loudest 400 ms of each close sound. `--table` writes what `test_energy_audio_rules.gd` pins; a run of the close sounds alone (`slots=none beds=0`) only
replaces the close section of the table that is already there.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import gun_levels as gl

ENERGY_FILES = Path(__file__).resolve().parents[2] / "game" / "assets" / "audio" / "energy"
RECUT = "_recut"
TAIL_FROM = 0.08
TAIL_TO = 0.5
BRIGHT_BAND = (2000, 8000)
CLOSE_GAP = 0.25
DEEP_BAND = "250-500"  # where the wonder weapons' layer rings (the bands are dB under each shot's strongest)


def parse_close(log: Path) -> list[dict]:
    rows = []
    for line in log.read_text(errors="replace").splitlines():
        m = re.match(r"CLOSE ([\d.]+) (\S+) (\d+) (-?[\d.]+)", line)
        if m:
            rows.append(
                {"t": float(m.group(1)), "sound": m.group(2), "variant": int(m.group(3)), "max_db": float(m.group(4))}
            )
    return rows


def close_levels(data: np.ndarray, rate: int, rows: list[dict], ffmpeg: str, scratch: Path) -> dict:
    sounds: dict[str, dict] = {}
    for k, row in enumerate(rows):
        end = rows[k + 1]["t"] if k + 1 < len(rows) else row["t"] + 3.0
        piece = gl.cut(data, rate, row["t"], end - row["t"])
        peak = gl.db(float(np.abs(piece).max()))
        moment = gl.loudness(ffmpeg, piece, rate, scratch / "close.wav")["momentary_max"]
        entry = sounds.setdefault(
            row["sound"], {"max_db": row["max_db"], "close_peak_dbfs": -120.0, "close_lufs": -120.0}
        )
        entry["close_peak_dbfs"] = max(entry["close_peak_dbfs"], peak)
        entry["close_lufs"] = max(entry["close_lufs"], moment)
    return sounds


def tail_stats(data: np.ndarray, rate: int, slot: dict, mono_start: int) -> dict:
    """The tail of the single shot: the 0.08 to 0.5 s after its onset, its loudness and its 2 to 8 kHz energy."""
    single = gl.cut(data, rate, slot["single"] - 0.05, gl.SINGLE_SECONDS).mean(axis=0)
    a = mono_start + int(TAIL_FROM * rate)
    seg = single[a : a + int((TAIL_TO - TAIL_FROM) * rate)]
    spectrum = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
    freqs = np.fft.rfftfreq(len(seg), 1 / rate)
    bright = spectrum[(freqs >= BRIGHT_BAND[0]) & (freqs < BRIGHT_BAND[1])].sum()
    return {"tail_rms_db": gl.db(float(np.sqrt((seg**2).mean()))), "bright_db": float(10 * np.log10(bright + 1e-30))}


def analyse(mix: Path, log: Path, ffmpeg: str, scratch: Path) -> dict:
    result = gl.analyse(mix, log, ffmpeg, scratch, None)
    data, rate = gl.read_wav(mix)
    slots, _shots, _bed = gl.parse_log(log)
    result["close"] = close_levels(data, rate, parse_close(log), ffmpeg, scratch) if parse_close(log) else {}
    result["recut"] = {}
    if not slots:
        return result
    for slot_name, slot in slots.items():
        if not slot_name.endswith(RECUT):
            continue
        weapon = slot_name[: -len(RECUT)]
        if weapon not in slots:
            continue
        plain = slots[weapon]
        a_mono = gl.cut(data, rate, plain["single"] - 0.05, gl.SINGLE_SECONDS).mean(axis=0)
        b_mono = gl.cut(data, rate, slot["single"] - 0.05, gl.SINGLE_SECONDS).mean(axis=0)
        a, b = gl.onset(a_mono, rate, 0.0), gl.onset(b_mono, rate, 0.0)
        tail_a, tail_b = tail_stats(data, rate, plain, a), tail_stats(data, rate, slot, b)
        pa, pb = result["guns"][weapon], result["guns"][slot_name]
        bands_a, bands_b = pa["bands_db"], pb["bands_db"]
        result["recut"][weapon] = {
            "single_peak_added_db": pb["single"]["peak"] - pa["single"]["peak"],
            "burst_peak_added_db": pb["burst"]["peak"] - pa["burst"]["peak"],
            "single_lufs_added_db": pb["single"]["momentary_max"] - pa["single"]["momentary_max"],
            "burst_lufs_added_db": pb["burst"]["lufs"] - pa["burst"]["lufs"],
            "tail_added_db": tail_b["tail_rms_db"] - tail_a["tail_rms_db"],
            "bright_added_db": tail_b["bright_db"] - tail_a["bright_db"],
            "deep_added_db": bands_b[DEEP_BAND] - bands_a[DEEP_BAND],
            "centroid_hz": [round(pa["centroid_hz"]), round(pb["centroid_hz"])],
            "low_end_share": [round(pa["low_end_share"], 3), round(pb["low_end_share"], 3)],
            "bands_db_plain": bands_a,
            "bands_db_recut": bands_b,
        }
    return result


def level_table(result: dict, log: Path, merge_into: Path | None = None) -> dict:
    """The pinned table. A run of the close sounds alone (`slots=none beds=0`) has no guns: with `--merge` its close
    rows replace the close section of the table already written, and nothing else changes."""
    if "beds" not in result and merge_into is not None:
        table = json.loads(merge_into.read_text(encoding="utf-8"))
        table["close"] = close_table(result)
        return table
    trims: dict[str, dict[str, float]] = {}
    for line in log.read_text(errors="replace").splitlines():
        parts = line.split()
        if parts and parts[0] == "TRIM":
            trims.setdefault(parts[1], {})[parts[2]] = float(parts[3])
    slots = {}
    for slot_name, g in result["guns"].items():
        weapon = slot_name.removesuffix(RECUT)
        if weapon not in ("ray_gun", "freeze_gun") and not slot_name.endswith(RECUT):
            continue
        energy_sounds = [s for s in trims.get(slot_name, {}) if list(ENERGY_FILES.glob(f"{s}_[0-9]*.ogg"))]
        slots[slot_name] = {
            "trims_db": trims.get(slot_name, {}),
            "files_sha256": gl.file_hashes(energy_sounds, ENERGY_FILES),
            "single_momentary_lufs": round(g["single"]["momentary_max"], 1),
            "burst_lufs": round(g["burst"]["lufs"], 1),
            "peak_dbfs": round(max(g["single"]["peak"], g["burst"]["peak"]), 1),
            "centroid_hz": round(g["centroid_hz"]),
            "low_end_share": round(g["low_end_share"], 2),
        }
    recut = {
        weapon: {
            "single_peak_added_db": round(r["single_peak_added_db"], 1),
            "burst_peak_added_db": round(r["burst_peak_added_db"], 1),
            "tail_added_db": round(r["tail_added_db"], 1),
            "bright_added_db": round(r["bright_added_db"], 1),
            "deep_added_db": round(r["deep_added_db"], 1),
        }
        for weapon, r in result["recut"].items()
    }
    return {"bed_lufs": round(result["beds"]["lufs"], 1), "slots": slots, "recut": recut, "close": close_table(result)}


def close_table(result: dict) -> dict:
    return {
        name: {
            "max_db": round(r["max_db"], 1),
            "close_peak_dbfs": round(r["close_peak_dbfs"], 1),
            "close_lufs": round(r["close_lufs"], 1),
        }
        for name, r in sorted(result["close"].items())
    }


def report(result: dict, label: str) -> None:
    if result["guns"]:
        gl.report(result, label)
    print("\nwhat the re-cut layer changes (re-cut minus plain)")
    print(
        "weapon      peak 1-shot / burst  | loudest 400 ms / burst LU | tail dB, 2-8 kHz dB | 250-500 Hz dB | centroid Hz | low<250"
    )
    for weapon, r in result["recut"].items():
        print(
            f"{weapon:<11} {r['single_peak_added_db']:+5.1f} / {r['burst_peak_added_db']:+5.1f}      | "
            f"{r['single_lufs_added_db']:+5.1f} / {r['burst_lufs_added_db']:+5.1f}         | "
            f"{r['tail_added_db']:+5.1f}, {r['bright_added_db']:+5.1f}      | {r['deep_added_db']:+5.1f} | {r['centroid_hz'][0]} -> {r['centroid_hz'][1]} | "
            f"{r['low_end_share'][0]:.2f} -> {r['low_end_share'][1]:.2f}"
        )
    if result["close"]:
        print("\nclose sounds, 1.2 m ahead")
        print("sound            held to (dB over file) | highest sample dBFS | loudest 400 ms LUFS")
        for name, r in sorted(result["close"].items()):
            print(f"{name:<16} {r['max_db']:6.1f} | {r['close_peak_dbfs']:6.1f} | {r['close_lufs']:6.1f}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mix", type=Path)
    parser.add_argument("log", type=Path)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--table", type=Path)
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    result = analyse(args.mix, args.log, args.ffmpeg, args.mix.parent / "_scratch")
    report(result, args.label or args.mix.name)
    if args.json:
        args.json.write_text(json.dumps(result, indent=2))
    if args.table:
        args.table.write_text(
            json.dumps(level_table(result, args.log, args.table), indent=2) + chr(10), encoding="utf-8", newline=""
        )


if __name__ == "__main__":
    main()
