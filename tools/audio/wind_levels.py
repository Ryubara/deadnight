"""Measure the drive-in's wind (issue #782): the files against the other beds, and a night's gusts in a capture.

    uv run --with numpy --with scipy --with matplotlib python tools/audio/wind_levels.py files --ffmpeg <ffmpeg>
    uv run --with numpy --with scipy --with matplotlib python tools/audio/wind_levels.py night --ffmpeg <ffmpeg>
        --solo <folder with stem_ambience.wav of a run with the wind alone> --log <its capture log>
        [--beds <folder with stem_ambience.wav of the same night with the other beds>] [--out wind.png]

`files` reads `game/assets/audio/ambience/` and the banks' trims (`beds.tres`, `wind.tres`, `smallmap.tres`) and prints, for the base
layer, each gust and each detail, and for the crickets, the highway and the projector: the file's integrated loudness,
the loudest momentary loudness (400 ms, LUFS), the crest, the spectral centroid and the share of energy under 250 Hz,
and the loudness *as played* (the file plus the catalog's trim, which is what the Ambience bus carries before the
sliders). The distance of a 3D sound is not in it: a gust is played 9 to 15 m off with `unit_size` 8 (1 to 5.5 dB down).

`night` reads the Ambience stem of `game/tests/captures/audio_wind_night.tscn` (`--solo` is the run with the wind
alone, `--beds` the same night, the same seeds, with the crickets, the highway and the projector too) and the `WIND`
lines the capture printed, and prints the base layer's loudness between gusts, each gust's loudest momentary loudness,
how far it stands over the base and over the other beds in the same moment, and the gaps; with `--out` it plots the
momentary loudness of both with the gusts shaded.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from analyze import read_wav
from gun_levels import band_levels, loudness

ROOT = Path(__file__).resolve().parents[2]
AMBIENCE = ROOT / "game" / "assets" / "audio" / "ambience"
BANKS = [ROOT / "game" / "core" / "audio" / "banks" / name for name in ("beds.tres", "wind.tres", "smallmap.tres")]
BEDS = ["crickets_1", "highway_1", "projector_1", "roof_wind_1", "yard_wind_1", "room_tone_1"]
SOUNDS = ["wind_base_1", *[f"wind_gust_{i}" for i in range(1, 9)]]
SOUNDS += [f"wind_creak_{i}" for i in range(1, 4)] + [f"wind_rattle_{i}" for i in range(1, 4)]
SOUNDS += [f"wind_flap_{i}" for i in range(1, 3)]
MOMENTARY = 0.4


def trims() -> dict[str, float]:
    """The trim (volume_db) of every sound in the banks, by its file stem (`crickets` -> `crickets_1`)."""
    out: dict[str, float] = {}
    for bank in BANKS:
        text = bank.read_text(encoding="utf-8")
        for block in text.split("[sub_resource")[1:]:
            path = re.search(r'path_format = "[^"]*/([a-z_]+?)_%d\.ogg"', block)
            volume = re.search(r"volume_db = (-?[\d.]+)", block)
            if path and volume:
                out[path.group(1)] = float(volume.group(1))
    return out


def decode(ffmpeg: str, ogg: Path, wav: Path) -> tuple[np.ndarray, int]:
    subprocess.run([ffmpeg, "-y", "-v", "error", "-i", str(ogg), "-c:a", "pcm_s16le", str(wav)], check=True)
    return read_wav(wav)


def files(ffmpeg: str, folder: Path) -> None:
    trim = trims()
    print(
        f"{'file':14s} {'sec':>5s} {'I':>7s} {'Mmax':>7s} {'crest':>6s} {'centroid':>8s} {'<250Hz':>6s} {'trim':>6s}"
        f" {'as played I':>11s} {'as played Mmax':>14s}"
    )
    with tempfile.TemporaryDirectory() as tmp:
        for name in [*BEDS, *SOUNDS]:
            ogg = folder / "ambience" / f"{name}.ogg" if (folder / "ambience").exists() else folder / f"{name}.ogg"
            if not ogg.exists():
                continue
            data, rate = decode(ffmpeg, ogg, Path(tmp) / f"{name}.wav")
            mono = data.mean(axis=0)
            result = loudness(ffmpeg, data, rate, Path(tmp) / "m.wav")
            _, centroid, low = band_levels(mono, rate)
            rms = float(np.sqrt((mono**2).mean()))
            crest = 20 * np.log10(np.abs(mono).max() / max(rms, 1e-9))
            t = trim.get(name.rsplit("_", 1)[0], 0.0)
            print(
                f"{name:14s} {len(mono) / rate:5.1f} {result['lufs']:7.1f} {result['momentary_max']:7.1f} {crest:6.1f}"
                f" {centroid:8.0f} {low * 100:5.0f}% {t:6.1f} {result['lufs'] + t:11.1f}"
                f" {result['momentary_max'] + t:14.1f}"
            )


def momentary_series(ffmpeg: str, data: np.ndarray, rate: int, scratch: Path, step: float = 0.1) -> np.ndarray:
    """The momentary loudness (LUFS, 400 ms) every `step` seconds of a stereo piece, from ffmpeg's ebur128 log."""
    from gun_levels import write_wav

    write_wav(scratch, data, rate)
    cmd = [ffmpeg, "-nostats", "-hide_banner", "-v", "verbose", "-i", str(scratch), "-af", "ebur128=framelog=verbose"]
    text = subprocess.run([*cmd, "-f", "null", "-"], capture_output=True, text=True, check=False).stderr
    return np.array([float(m) for m in re.findall(r"M:\s*(-?\d+\.?\d*)", text)])


def parse_log(path: Path) -> list[dict]:
    gusts = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"WIND ([\d.]+) gust (\S+) db=(-?[\d.]+) length=([\d.]+) lull=([\d.]+) detail=(\S*)", line)
        if m:
            gusts.append(
                {
                    "at": float(m.group(1)),
                    "file": m.group(2),
                    "db": float(m.group(3)),
                    "length": float(m.group(4)),
                    "lull": float(m.group(5)),
                    "detail": m.group(6),
                }
            )
    return gusts


def integrated(ffmpeg: str, folder: Path, name: str, scratch: Path, start: float = 6.0, end: float = 120.0) -> dict:
    """Integrated loudness, loudest momentary loudness and sample peak of a stem between `start` and `end` seconds."""
    from gun_levels import cut

    data, rate = read_wav(folder / name)
    piece = cut(data, rate, start, end - start)
    result = loudness(ffmpeg, piece, rate, scratch)
    result["sample_peak_dbfs"] = float(20 * np.log10(max(np.abs(piece).max(), 1e-9)))
    return result


def night(ffmpeg: str, solo: Path, beds: Path | None, log: Path, out: Path | None, nowind: Path | None = None) -> None:
    gusts = parse_log(log)
    with tempfile.TemporaryDirectory() as tmp:
        data, rate = read_wav(solo / "stem_ambience.wav")
        wind = momentary_series(ffmpeg, data, rate, Path(tmp) / "a.wav")
        mix = None
        if beds is not None:
            data2, rate2 = read_wav(beds / "stem_ambience.wav")
            mix = momentary_series(ffmpeg, data2, rate2, Path(tmp) / "b.wav")
    if nowind is not None and beds is not None:
        with tempfile.TemporaryDirectory() as tmp:
            rows = {
                "the beds alone (no wind)": integrated(ffmpeg, nowind, "stem_ambience_nowind.wav", Path(tmp) / "c.wav"),
                "the wind alone": integrated(ffmpeg, solo, "stem_ambience.wav", Path(tmp) / "c.wav"),
                "the beds with the wind": integrated(ffmpeg, beds, "stem_ambience.wav", Path(tmp) / "c.wav"),
            }
        print("The Ambience stem from 6 s to 120 s (the beds are in from 3 s):")
        for label, r in rows.items():
            print(
                f"  {label:26s} integrated {r['lufs']:6.1f} LUFS, loudest 400 ms {r['momentary_max']:6.1f}, peak {r['sample_peak_dbfs']:6.1f} dBFS"
            )
        gap = rows["the beds with the wind"]["lufs"] - rows["the beds alone (no wind)"]["lufs"]
        print(f"  the wind adds {gap:+.2f} LU to the night's integrated loudness")
    times = np.arange(len(wind)) * 0.1
    blowing = np.zeros(len(wind), dtype=bool)
    for g in gusts:
        blowing |= (times >= g["at"]) & (times < g["at"] + g["length"])
    settled = times > 8.0  # the beds fade in over 3 s
    between = wind[settled & ~blowing & np.isfinite(wind) & (wind > -70)]
    print(f"{len(gusts)} gusts in {times[-1]:.0f} s; the wind alone, momentary loudness (LUFS, 400 ms):")
    if len(between):
        print(
            f"  base layer between gusts: median {np.median(between):.1f}, range {between.min():.1f} to {between.max():.1f}"
        )
    print(
        f"  {'at':>6s} {'sec':>5s} {'lull':>5s} {'draw dB':>7s} {'peak M':>7s} {'over base':>9s}"
        + (f" {'beds M':>7s} {'with wind':>9s} {'raise':>6s}" if mix is not None else "")
        + "  file / detail"
    )
    base = float(np.median(between)) if len(between) else -70.0
    peaks = []
    for g in gusts:
        sl = (times >= g["at"]) & (times < g["at"] + g["length"])
        if not sl.any():
            continue
        peak = float(wind[sl].max())
        peaks.append(peak)
        row = f"  {g['at']:6.1f} {g['length']:5.1f} {g['lull']:5.1f} {g['db']:7.1f} {peak:7.1f} {peak - base:9.1f}"
        if mix is not None:
            around = (
                float(np.median(mix[(times >= g["at"] - 12) & (times < g["at"] - 1) & ~blowing]))
                if g["at"] > 13
                else float("nan")
            )
            during = float(mix[sl].max())
            row += f" {around:7.1f} {during:9.1f} {during - around:6.1f}"
        print(row + f"  {Path(g['file']).stem} {g['detail']}")
    if peaks:
        print(
            f"  gust peaks: min {min(peaks):.1f}, median {np.median(peaks):.1f}, max {max(peaks):.1f} LUFS-M;"
            f" lulls {min(g['lull'] for g in gusts):.1f} to {max(g['lull'] for g in gusts):.1f} s,"
            f" lengths {min(g['length'] for g in gusts):.1f} to {max(g['length'] for g in gusts):.1f} s"
        )
    if out is not None:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, ax = plt.subplots(figsize=(13, 4.2))
        for g in gusts:
            ax.axvspan(g["at"], g["at"] + g["length"], color="#9bb7d4", alpha=0.35, lw=0)
            if g["detail"]:
                ax.text(
                    g["at"] + g["length"] * 0.4, -52.5, g["detail"].replace("wind_", ""), fontsize=7, color="#7b341e"
                )
        ax.plot(times, wind, color="#1a365d", lw=1.2, label="the wind alone")
        if mix is not None:
            ax.plot(
                np.arange(len(mix)) * 0.1, mix, color="#718096", lw=0.9, label="the Ambience bus with the other beds"
            )
        ax.set_xlabel("seconds")
        ax.set_ylabel("momentary loudness, LUFS")
        ax.set_ylim(-58, -28)
        ax.set_xlim(0, 122)
        ax.set_title(
            "A quiet night's wind: the base layer, and the gusts (shaded) that differ in length, strength and colour"
        )
        ax.legend(loc="lower right", fontsize=8)
        fig.tight_layout()
        fig.savefig(out, dpi=110)
        print(f"plot: {out}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("files")
    f.add_argument("--ffmpeg", required=True)
    f.add_argument("--folder", type=Path, default=AMBIENCE)
    n = sub.add_parser("night")
    n.add_argument("--ffmpeg", required=True)
    n.add_argument("--solo", type=Path, required=True)
    n.add_argument("--beds", type=Path)
    n.add_argument("--nowind", type=Path, help="folder of stem_ambience_nowind.wav: the same night without the wind")
    n.add_argument("--log", type=Path, required=True)
    n.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.cmd == "files":
        files(args.ffmpeg, args.folder)
    else:
        night(args.ffmpeg, args.solo, args.beds, args.log, args.out, args.nowind)


if __name__ == "__main__":
    main()
