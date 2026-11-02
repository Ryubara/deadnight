"""Measure the guns as the player hears them, from a recording of `game/tools/bench/audio_gun_bench.tscn`.

    uv run --with numpy --with scipy python tools/audio/gun_levels.py mix.wav bench.log --ffmpeg <pinned ffmpeg>
        [--json out.json] [--clips folder] [--label before]

For each firearm the bench fires one shot and then a two second burst through the game's own `WeaponSounds`, the
audio service and the buses, and then runs the night's ambient beds alone. This prints, per gun: the sample peak
and, with ffmpeg's `ebur128`, the integrated and loudest momentary loudness (LUFS) of the single shot and of the
burst; the same for the beds; how the energy sits across the bands (the low end), the spectral centroid, the share of
the shot's energy that arrives in its first 50 ms (a close shot is front-loaded, a far or roomy one is not), the
pitch and level the audio service gave every report of the burst, the spread of the loudness and of the low-end pitch
between the burst's shots as recorded, the left-right balance, and whether the shooter's own shots were flat or 3D.
`--clips` also cuts each gun's single shot and burst to its own WAV for the pull request.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import wave
from pathlib import Path

import numpy as np

BANDS = [
    (20, 60),
    (60, 120),
    (120, 250),
    (250, 500),
    (500, 1000),
    (1000, 2000),
    (2000, 4000),
    (4000, 8000),
    (8000, 20000),
]
LOW_END_HZ = 250.0
FRONT_SECONDS = 0.05
SINGLE_SECONDS = 1.6
BURST_TAIL_SECONDS = 1.2
PITCH_BAND_HZ = (40.0, 400.0)
BED_SETTLE_SECONDS = 4.0


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as f:
        channels, width, rate, frames = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
        raw = f.readframes(frames)
    dtype = {2: "<i2", 4: "<i4"}[width]
    data = np.frombuffer(raw, dtype).astype(np.float64) / float(1 << (8 * width - 1))
    return data.reshape(-1, channels).T, rate


def db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-9))


def write_wav(path: Path, data: np.ndarray, rate: int) -> None:
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2").T.copy()
    with wave.open(str(path), "wb") as f:
        f.setnchannels(data.shape[0])
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(pcm.tobytes())


def cut(data: np.ndarray, rate: int, start: float, length: float) -> np.ndarray:
    a = max(int(start * rate), 0)
    return data[:, a : a + int(length * rate)]


def loudness(ffmpeg: str, data: np.ndarray, rate: int, scratch: Path) -> dict[str, float]:
    """Integrated loudness, loudest momentary and true peak of a piece, by the pinned ffmpeg's ebur128."""
    scratch.parent.mkdir(parents=True, exist_ok=True)
    write_wav(scratch, data, rate)
    cmd = [
        ffmpeg,
        "-nostats",
        "-hide_banner",
        "-v",
        "verbose",
        "-i",
        str(scratch),
        "-af",
        "ebur128=peak=true:framelog=verbose",
    ]
    text = subprocess.run([*cmd, "-f", "null", "-"], capture_output=True, text=True, check=False).stderr
    momentary = [float(m) for m in re.findall(r"M:\s*(-?\d+\.?\d*)", text)]
    integrated = re.findall(r"I:\s+(-?\d+\.?\d*) LUFS", text)
    peak = re.findall(r"Peak:\s+(-?\d+\.?\d*) dBFS", text)
    return {
        "lufs": float(integrated[-1]) if integrated else -120.0,
        "momentary_max": max(momentary) if momentary else -120.0,
        "true_peak": float(peak[-1]) if peak else -120.0,
    }


def band_levels(mono: np.ndarray, rate: int) -> tuple[list[float], float, float]:
    """Energy per band in dB below the loudest band, the spectral centroid, and the share of energy under 250 Hz."""
    spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1 / rate)
    energy = [spectrum[(freqs >= a) & (freqs < b)].sum() for a, b in BANDS]
    top = max(energy) + 1e-30
    amp = np.sqrt(spectrum)
    centroid = float((amp * freqs).sum() / (amp.sum() + 1e-30))
    low = float(spectrum[(freqs >= 20) & (freqs < LOW_END_HZ)].sum() / (spectrum[(freqs >= 20)].sum() + 1e-30))
    return [10 * np.log10(e / top + 1e-12) for e in energy], centroid, low


def onset(mono: np.ndarray, rate: int, start: float) -> int:
    """Sample where the sound after `start` first rises within 30 dB of its peak."""
    a = int(start * rate)
    seg = np.abs(mono[a : a + int(0.5 * rate)])
    return a + int(np.argmax(seg > seg.max() * 10 ** (-30 / 20)))


def front_share(mono: np.ndarray, rate: int, start: int) -> float:
    """Share of the shot's energy in its first 50 ms of the 1.5 s after it."""
    energy = mono[start : start + int(1.5 * rate)] ** 2
    front = energy[: int(FRONT_SECONDS * rate)].sum()
    return float(front / (energy.sum() + 1e-30))


def low_pitch(mono: np.ndarray, rate: int) -> float:
    """Frequency of the strongest bin between 40 and 400 Hz of a 60 ms piece (the thump's pitch)."""
    seg = mono[: int(0.06 * rate)]
    n = 1 << 14
    spectrum = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n))
    freqs = np.fft.rfftfreq(n, 1 / rate)
    mask = (freqs >= PITCH_BAND_HZ[0]) & (freqs <= PITCH_BAND_HZ[1])
    return float(freqs[mask][np.argmax(spectrum[mask])])


def parse_log(path: Path) -> tuple[dict[str, dict], list[dict], tuple[float, float] | None]:
    slots: dict[str, dict] = {}
    shots: list[dict] = []
    bed = None
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "SLOT":
            slots[parts[1]] = {"single": float(parts[2]), "burst": float(parts[3]), "burst_end": float(parts[4])}
        elif parts[0] == "SHOT" and parts[-1] == "dropped":
            shots.append({"t": float(parts[1]), "weapon": parts[2], "sound": parts[3], "dropped": True})
        elif parts[0] == "SHOT" and len(parts) >= 8:
            shots.append(
                {
                    "t": float(parts[1]),
                    "weapon": parts[2],
                    "sound": parts[3],
                    "pitch": float(parts[4]),
                    "db": float(parts[5]),
                    "kind": parts[6],
                    "distance": float(parts[7]),
                }
            )
        elif parts[0] == "BED":
            bed = (float(parts[1]), float(parts[2]))
    return slots, shots, bed


def semitones(pitch: float) -> float:
    return 12.0 * float(np.log2(pitch))


def per_shot_stats(data: np.ndarray, rate: int, times: list[float]) -> list[dict]:
    stats = []
    for i, t in enumerate(times):
        end = times[i + 1] if i + 1 < len(times) else t + 0.2
        piece = cut(data, rate, t - 0.005, min(max(end - t, 0.04), 0.2)).mean(axis=0)
        if len(piece) < int(0.03 * rate):
            continue
        stats.append(
            {
                "peak": db(np.abs(piece).max()),
                "pitch_hz": low_pitch(piece[int(0.005 * rate) :], rate),
                "centroid": band_levels(piece, rate)[1],
            }
        )
    return stats


def analyse_gun(
    weapon: str, slot: dict, mine: list[dict], data: np.ndarray, rate: int, ffmpeg: str, scratch: Path
) -> dict:
    live = [s for s in mine if not s.get("dropped")]
    reports = [s for s in live if s["sound"].startswith("shot_")]
    burst_reports = [s for s in reports if slot["burst"] - 0.01 <= s["t"] <= slot["burst_end"] + 0.1]
    single = cut(data, rate, slot["single"] - 0.05, SINGLE_SECONDS)
    burst = cut(data, rate, slot["burst"] - 0.05, slot["burst_end"] - slot["burst"] + BURST_TAIL_SECONDS)
    s_mono = single.mean(axis=0)
    start = onset(s_mono, rate, 0.0)
    bands, centroid, low = band_levels(s_mono[start : start + int(0.3 * rate)], rate)
    shots = per_shot_stats(data, rate, sorted(s["t"] for s in burst_reports))
    pitches = [semitones(s["pitch"]) for s in burst_reports]
    levels = [s["db"] for s in burst_reports]
    hz = np.array([p["pitch_hz"] for p in shots]) if shots else np.array([1.0])
    centroids = [p["centroid"] for p in shots]
    first = live[0] if live else None
    return {
        "single": {
            **loudness(ffmpeg, single, rate, scratch / "single.wav"),
            "peak": db(np.abs(single).max()),
            "front_share": front_share(s_mono, rate, start),
        },
        "burst": {
            **loudness(ffmpeg, burst, rate, scratch / "burst.wav"),
            "peak": db(np.abs(burst).max()),
            "shots": len(burst_reports),
        },
        "bands_db": dict(zip([f"{a}-{b}" for a, b in BANDS], [round(x, 1) for x in bands], strict=True)),
        "centroid_hz": centroid,
        "low_end_share": low,
        "report_pitch_spread_semitones": [min(pitches), max(pitches)] if pitches else [0.0, 0.0],
        "report_level_spread_db": [min(levels), max(levels)] if levels else [0.0, 0.0],
        "recorded_shot_peak_spread_db": float(max(p["peak"] for p in shots) - min(p["peak"] for p in shots))
        if shots
        else 0.0,
        "recorded_low_pitch_spread_semitones": float(12 * np.log2(hz.max() / hz.min())),
        "recorded_centroid_cv": float(np.std(centroids) / (np.mean(centroids) + 1e-9)) if centroids else 0.0,
        "voices_per_shot": len({s["sound"] for s in live}),
        "own_shot": {
            "flat": bool(live) and all(s["kind"] == "flat" for s in live),
            "distance_m": 0.0 if first is None else first["distance"],
        },
        "lr_balance_db": db(np.sqrt((data[0] ** 2).mean())) - db(np.sqrt((data[1] ** 2).mean())),
    }


def analyse(mix: Path, log: Path, ffmpeg: str, scratch: Path, clips: Path | None) -> dict:
    data, rate = read_wav(mix)
    slots, shots, bed = parse_log(log)
    result: dict = {"guns": {}, "rate": rate}
    for weapon, slot in slots.items():
        mine = [s for s in shots if s["weapon"] == weapon]
        result["guns"][weapon] = analyse_gun(weapon, slot, mine, data, rate, ffmpeg, scratch)
        if clips is not None:
            clips.mkdir(parents=True, exist_ok=True)
            write_wav(clips / f"{weapon}_single.wav", cut(data, rate, slot["single"] - 0.05, SINGLE_SECONDS), rate)
            length = slot["burst_end"] - slot["burst"] + BURST_TAIL_SECONDS
            write_wav(clips / f"{weapon}_burst.wav", cut(data, rate, slot["burst"] - 0.05, length), rate)
    if bed is not None:
        beds = cut(data, rate, bed[0] + BED_SETTLE_SECONDS, bed[1] - bed[0] - BED_SETTLE_SECONDS)
        result["beds"] = loudness(ffmpeg, beds, rate, scratch / "beds.wav")
    return result


def level_table(result: dict, log: Path) -> dict:
    """What the game's test pins: the trims the catalog had when this was measured, and the loudness of each gun."""
    trims: dict[str, dict[str, float]] = {}
    for line in log.read_text(errors="replace").splitlines():
        parts = line.split()
        if parts and parts[0] == "TRIM":
            trims.setdefault(parts[1], {})[parts[2]] = float(parts[3])
    guns = {}
    for weapon, g in result["guns"].items():
        guns[weapon] = {
            "trims_db": trims.get(weapon, {}),
            "single_momentary_lufs": round(g["single"]["momentary_max"], 1),
            "burst_lufs": round(g["burst"]["lufs"], 1),
            "peak_dbfs": round(max(g["single"]["peak"], g["burst"]["peak"]), 1),
            "centroid_hz": round(g["centroid_hz"]),
        }
    return {"bed_lufs": round(result["beds"]["lufs"], 1), "guns": guns}


def report(result: dict, label: str) -> None:
    print(f"== {label}")
    if "beds" in result:
        b = result["beds"]
        print(f"night beds alone: {b['lufs']:.1f} LUFS, peak {b['true_peak']:.1f} dBFS")
    print(
        "gun        1-shot LUFS (M max)  peak | burst LUFS  peak | centroid low<250 front50 | "
        "report pitch st / level dB | shot-peak spread, low-pitch spread | own"
    )
    for weapon, g in result["guns"].items():
        s, m = g["single"], g["burst"]
        own = "flat" if g["own_shot"]["flat"] else f"3d {g['own_shot']['distance_m']:.1f} m"
        print(
            f"{weapon:<10} {s['lufs']:6.1f} ({s['momentary_max']:6.1f}) {s['peak']:6.1f} | {m['lufs']:6.1f} {m['peak']:6.1f} | "
            f"{g['centroid_hz']:6.0f} {g['low_end_share']:6.2f} {s['front_share']:6.2f} | "
            f"{g['report_pitch_spread_semitones'][0]:+.2f}..{g['report_pitch_spread_semitones'][1]:+.2f} / "
            f"{g['report_level_spread_db'][0]:+.1f}..{g['report_level_spread_db'][1]:+.1f} | "
            f"{g['recorded_shot_peak_spread_db']:5.1f} dB, {g['recorded_low_pitch_spread_semitones']:5.2f} st | "
            f"{own} LR {g['lr_balance_db']:+.1f}"
        )
    names = next(iter(result["guns"].values()))["bands_db"]
    print("bands Hz, dB below the strongest:", " ".join(names))
    for weapon, g in result["guns"].items():
        print(f"  {weapon:<10}", " ".join(f"{v:7.1f}" for v in g["bands_db"].values()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mix", type=Path)
    parser.add_argument("log", type=Path)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--clips", type=Path)
    parser.add_argument("--table", type=Path, help="write the table `test_gun_audio_rules.gd` reads")
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    result = analyse(args.mix, args.log, args.ffmpeg, args.mix.parent / "_scratch", args.clips)
    report(result, args.label or args.mix.name)
    if args.json:
        args.json.write_text(json.dumps(result, indent=2))
    if args.table:
        args.table.write_text(json.dumps(level_table(result, args.log), indent=2) + chr(10))


if __name__ == "__main__":
    main()
