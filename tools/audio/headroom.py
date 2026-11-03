"""Headroom over the player's own gunfire, measured from a recording (Deadnight #718).

    uv run --with numpy --with scipy --with matplotlib python tools/audio/headroom.py \
        --run before=<folder> --run after=<folder> \
        --ffmpeg <pinned ffmpeg> --out folder [--ceiling -1]

Each `--run label=<folder>` holds one or more runs of `game/tests/captures/audio_headroom.tscn`, each in its own
subfolder with the Movie Maker mix (`mix.wav`) and the capture's log (`run.log`, `CELL <own gun> <cell> <start> <end>`
lines), one own gun a run. The buses have no effects, so the mix is the plain sum of what the client plays. Writes
into `--out`:
- `headroom.md`: one table row for each pair of own gun and what lands on it (peak, the samples over the ceiling, the
  most the sum went over the gun alone), then the gun alone (RMS, crest factor, the loudest 400 ms and the whole
  burst in LUFS, from the pinned ffmpeg's `ebur128`) and what each other sound peaks at by itself (`none` rows);
- `headroom.json`: the same numbers;
- `headroom.png`: the peak level (dBFS) in 10 ms windows for every cell, the runs on top of each other, with the
  ceiling and full scale drawn.
Exits 1 when a run of the last label has a sample over `--ceiling` (default -1 dBFS).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from analyze import db, read_wav
from gun_levels import write_wav

LEAD = 0.5  # seconds before the first event in a cell (the capture's LEAD)
TAIL = 0.7  # seconds after the last (the capture's TAIL)
SOUND_WINDOW = 0.3  # seconds after a sound starts that its own peak is looked for
PEAK_WINDOW = 0.01  # seconds per peak-envelope window of the plot
CELLS = ["alone", "reload", "mate", "zombie", "world"]
GUNS = [
    "pistol",
    "smg",
    "rifle",
    "shotgun",
    "flare_gun",
    "ppsh",
    "m249",
    "m4a1",
    "fifty_cal",
    "mp5",
    "pump_870",
    "dual_pistols",
]


def read_cells(log: Path) -> list[dict]:
    cells = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"CELL (\S+) (\S+) ([\d.]+) ([\d.]+)", line)
        if m:
            cells.append({"own": m.group(1), "cell": m.group(2), "start": float(m.group(3)), "end": float(m.group(4))})
    return cells


def loudness(segment: np.ndarray, rate: int, ffmpeg: str) -> dict:
    """Integrated and loudest momentary loudness (LUFS) of a stereo segment with ffmpeg's ebur128."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "segment.wav"
        write_wav(path, segment, rate)
        out = subprocess.run(
            [ffmpeg, "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
            capture_output=True,
            text=True,
            check=False,
        ).stderr
    integrated = re.findall(r"I:\s+(-?[\d.]+) LUFS", out)
    momentary = [float(x) for x in re.findall(r"M:\s*(-?[\d.]+)", out)]
    return {
        "integrated": float(integrated[-1]) if integrated else float("nan"),
        "momentary_max": max(momentary) if momentary else float("nan"),
    }


def runs_in(folder: Path) -> list[tuple[Path, Path]]:
    found = [(wav, wav.with_name("run.log")) for wav in sorted(folder.glob("*/mix.wav"))]
    if not found:
        raise SystemExit(f"{folder}: no <run>/mix.wav")
    return found


def measure(runs: list[tuple[Path, Path]], ffmpeg: str | None, ceiling_db: float) -> dict:
    ceiling = 10 ** (ceiling_db / 20)
    out: dict = {"cells": {}, "ceiling_db": ceiling_db}
    for wav, log in runs:
        measure_run(wav, log, ffmpeg, ceiling, out)
    return out


def sound_peaks(data: np.ndarray, rate: int, log: Path, out: dict) -> None:
    """The peak (dBFS) in the `SOUND_WINDOW` after each `PLAY` line of a run without an own gun, by sound."""
    peaks = out.setdefault("sounds", {})
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"PLAY ([\d.]+) none (\S+) (\S+)", line)
        if m and m.group(2) != "alone":
            at = int(float(m.group(1)) * rate)
            level = db(np.abs(data[:, at : at + int(SOUND_WINDOW * rate)]).max())
            peaks[m.group(3)] = max(peaks.get(m.group(3), -120.0), level)


def measure_run(wav: Path, log: Path, ffmpeg: str | None, ceiling: float, out: dict) -> None:
    data, rate = read_wav(wav)
    out["rate"] = rate
    if log.parent.name == "none":
        sound_peaks(data, rate, log, out)
    for cell in read_cells(log):
        a, b = int(cell["start"] * rate), int(cell["end"] * rate)
        seg = data[:, a:b]
        mono = np.abs(seg).max(axis=0)
        active = seg[:, int(LEAD * rate) : int(seg.shape[1] - TAIL * rate)]
        row = {
            "start": cell["start"],
            "end": cell["end"],
            "peak_db": db(mono.max()),
            "over_ceiling": int((mono > ceiling).sum()),
            "full_scale": int((mono >= 0.999).sum()),
            "rms_db": db(float(np.sqrt((active**2).mean()))) if active.size else float("nan"),
        }
        row["crest_db"] = row["peak_db"] - row["rms_db"]
        if ffmpeg and cell["cell"] == "alone" and cell["own"] != "none":
            whole = loudness(active, rate, ffmpeg)
            row["burst_lufs"] = whole["integrated"]
            row["loudest_400ms_lufs"] = whole["momentary_max"]
        out["cells"][f"{cell['own']}/{cell['cell']}"] = row


def envelope(wav_data: np.ndarray, rate: int, start: float, end: float) -> tuple[np.ndarray, np.ndarray]:
    seg = np.abs(wav_data[:, int(start * rate) : int(end * rate)]).max(axis=0)
    step = int(PEAK_WINDOW * rate)
    n = len(seg) // step
    peaks = seg[: n * step].reshape(n, step).max(axis=1)
    return np.arange(n) * PEAK_WINDOW, 20 * np.log10(np.maximum(peaks, 1e-6))


def table(runs: dict[str, dict]) -> str:
    labels = list(runs)
    lines = ["Peak of the mix (dBFS) and samples over the ceiling, own gun firing without a break:", ""]
    head = (
        "| Own gun | Lands on it | "
        + " | ".join(f"{label}: peak (dBFS) | {label}: samples over" for label in labels)
        + " |"
    )
    lines += [head, "|" + " --- |" * (2 + 2 * len(labels))]
    for gun in GUNS:
        for cell in CELLS:
            key = f"{gun}/{cell}"
            parts = []
            for label in labels:
                r = runs[label]["cells"].get(key)
                parts += [f"{r['peak_db']:.1f}", str(r["over_ceiling"])] if r else ["-", "-"]
            lines.append(f"| {gun} | {cell} | " + " | ".join(parts) + " |")
    lines += ["", "The gun by itself (what its punch is made of):", ""]
    head = (
        "| Own gun | "
        + " | ".join(f"{l}: peak | {l}: RMS | {l}: crest | {l}: loudest 400 ms LUFS | {l}: burst LUFS" for l in labels)
        + " |"
    )
    lines += [head, "|" + " --- |" * (1 + 5 * len(labels))]
    for gun in GUNS:
        parts = []
        for label in labels:
            r = runs[label]["cells"].get(f"{gun}/alone")
            parts += (
                [
                    f"{r['peak_db']:.1f}",
                    f"{r['rms_db']:.1f}",
                    f"{r['crest_db']:.1f}",
                    f"{r.get('loudest_400ms_lufs', float('nan')):.1f}",
                    f"{r.get('burst_lufs', float('nan')):.1f}",
                ]
                if r
                else ["-"] * 5
            )
        lines.append(f"| {gun} | " + " | ".join(parts) + " |")
    lines += ["", "What lands on the gun, each cell by itself with no own gun (peak, dBFS):", ""]
    lines += ["| What | " + " | ".join(labels) + " |", "|" + " --- |" * (1 + len(labels))]
    for cell in CELLS[1:]:
        key = f"none/{cell}"
        cols = []
        for label in labels:
            r = runs[label]["cells"].get(key)
            cols.append(f"{r['peak_db']:.1f}" if r else "-")
        lines.append(f"| {cell} | " + " | ".join(cols) + " |")
    sounds = {label: runs[label].get("sounds", {}) for label in labels}
    if any(sounds.values()):
        names = sorted(
            {n for per in sounds.values() for n in per}, key=lambda n: -max(per.get(n, -120) for per in sounds.values())
        )
        lines += [
            "",
            "Each sound by itself with no own gun, its peak in the 0.3 s after it starts (dBFS), loudest first:",
            "",
        ]
        lines += ["| Sound | " + " | ".join(labels) + " |", "|" + " --- |" * (1 + len(labels))]
        for name in names:
            cols = [f"{sounds[l][name]:.1f}" if name in sounds[l] else "-" for l in labels]
            lines.append(f"| {name} | " + " | ".join(cols) + " |")
    return "\n".join(lines) + "\n"


def plot(runs: dict[str, list[tuple[Path, Path]]], out: Path, ceiling_db: float) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    colours = ["#8a8f98", "#d1495b", "#2e86ab"]
    loaded: dict[str, list[tuple[np.ndarray, int, dict]]] = {}
    for label, pairs in runs.items():
        loaded[label] = []
        for wav, log in pairs:
            data, rate = read_wav(wav)
            loaded[label] += [(data, rate, c) for c in read_cells(log)]
    widths = []
    for cell in CELLS:
        lengths = [
            c["end"] - c["start"]
            for cells in loaded.values()
            for _, _, c in cells
            if c["cell"] == cell and c["own"] != "none"
        ]
        widths.append(max(lengths, default=1.0))
    fig, axes = plt.subplots(
        len(GUNS),
        len(CELLS),
        figsize=(18, 11),
        gridspec_kw={"width_ratios": widths},
        sharey=True,
        constrained_layout=True,
    )
    for i, gun in enumerate(GUNS):
        for j, cell in enumerate(CELLS):
            ax = axes[i][j]
            for k, (label, cells) in enumerate(loaded.items()):
                for data, rate, c in cells:
                    if c["own"] == gun and c["cell"] == cell:
                        t, e = envelope(data, rate, c["start"], c["end"])
                        ax.plot(t, e, lw=0.8, color=colours[k % len(colours)], label=label)
            ax.axhline(0, color="black", lw=1.0)
            ax.axhline(ceiling_db, color="#c1121f", lw=0.8, ls="--")
            ax.set_ylim(-30, 3)
            ax.set_xlim(0, widths[j])
            if i == 0:
                ax.set_title(cell)
            if j == 0:
                ax.set_ylabel(f"{gun}\npeak dBFS")
            if i == len(GUNS) - 1:
                ax.set_xlabel("seconds")
            if i == 0 and j == 0:
                ax.legend(loc="lower right", fontsize=8)
    fig.suptitle(
        f"Own gun firing without a break, with other sounds landing on it (dashed: {ceiling_db:g} dBFS, solid: full scale)"
    )
    fig.savefig(out, dpi=100)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run", action="append", required=True, help="label=<folder of runs>")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--ceiling", type=float, default=-1.0)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    paths: dict[str, list[tuple[Path, Path]]] = {}
    for spec in args.run:
        label, folder = spec.split("=", 1)
        paths[label] = runs_in(Path(folder))
    runs = {label: measure(pairs, args.ffmpeg, args.ceiling) for label, pairs in paths.items()}
    (args.out / "headroom.json").write_text(json.dumps(runs, indent=1))
    text = table(runs)
    (args.out / "headroom.md").write_text(text)
    print(text)
    plot(paths, args.out / "headroom.png", args.ceiling)
    last = list(runs)[-1]
    bad = {
        k: v["over_ceiling"] for k, v in runs[last]["cells"].items() if v["over_ceiling"] and not k.startswith("none/")
    }
    if bad:
        print(f"{last}: samples over {args.ceiling} dBFS in {bad}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
