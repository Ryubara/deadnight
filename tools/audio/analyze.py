"""Measure sounds without ears: levels, clipping, timing, loop seams, and pictures of them.

    uv run --with numpy --with scipy --with matplotlib python tools/audio/analyze.py report a.wav b.wav ...
    uv run --with numpy --with scipy --with matplotlib python tools/audio/analyze.py sheet --out sheet.png a.wav ...
    uv run --with numpy --with scipy --with matplotlib python tools/audio/analyze.py capture mix.wav --out mix.png
        [--window 0.5] [--expect 12.4:board_tear ...] [--tolerance 0.25]

`report` prints, for every file: length, peak and RMS in dBFS, clipped samples, spectral centroid and, for the
files that loop, the step across the seam against the largest step inside the file. `sheet` draws a waveform and a
log-frequency spectrogram per file. `capture` reads a Movie Maker mix (`--write-movie` writes 32-bit integer PCM, not
16-bit), prints its level in windows and its onsets, checks that the expected sounds start where they were played
(`--expect seconds:name`, within `--tolerance`), and draws the mix.
"""

from __future__ import annotations

import argparse
import sys
import wave
from pathlib import Path

import numpy as np
from scipy import signal

CLIP_LEVEL = 0.999


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    """Samples as float in -1..1, shape (channels, n), whatever the PCM width (16, 24 or 32 bit integer)."""
    with wave.open(str(path), "rb") as f:
        channels, width, rate, frames = f.getnchannels(), f.getsampwidth(), f.getframerate(), f.getnframes()
        raw = f.readframes(frames)
    if width == 2:
        data = np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0
    elif width == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3).astype(np.int32)
        value = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        data = np.where(value >= 1 << 23, value - (1 << 24), value) / float(1 << 23)
    elif width == 4:
        data = np.frombuffer(raw, "<i4").astype(np.float64) / 2147483648.0
    else:
        raise SystemExit(f"{path}: unsupported sample width {width}")
    return data.reshape(-1, channels).T, rate


def db(x: float) -> float:
    return 20 * np.log10(max(float(x), 1e-9))


def centroid(mono: np.ndarray, rate: int) -> float:
    spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    freqs = np.fft.rfftfreq(len(mono), 1 / rate)
    return float((spectrum * freqs).sum() / (spectrum.sum() + 1e-12))


def seam_step(mono: np.ndarray) -> tuple[float, float]:
    """The step from the last sample to the first, and the largest step between neighbours inside the file."""
    return float(abs(mono[0] - mono[-1])), float(np.abs(np.diff(mono)).max())


def report(paths: list[Path], loops: set[str]) -> list[dict]:
    rows = []
    for path in paths:
        data, rate = read_wav(path)
        mono = data.mean(axis=0)
        row = {
            "name": path.stem,
            "seconds": data.shape[1] / rate,
            "peak_db": db(np.abs(data).max()),
            "rms_db": db(np.sqrt((data**2).mean())),
            "clipped": int((np.abs(data) >= CLIP_LEVEL).sum()),
            "centroid_hz": centroid(mono, rate),
        }
        if any(path.stem.startswith(name) for name in loops):
            jump, widest = seam_step(mono)
            row["seam_step"], row["max_inner_step"] = jump, widest
        rows.append(row)
    return rows


def print_report(rows: list[dict]) -> None:
    print(f"{'name':24} {'sec':>6} {'peak':>7} {'rms':>7} {'clip':>5} {'centroid':>9}  loop seam")
    for r in rows:
        seam = ""
        if "seam_step" in r:
            seam = f"{r['seam_step']:.4f} (inner max {r['max_inner_step']:.4f})"
        print(
            f"{r['name']:24} {r['seconds']:6.2f} {r['peak_db']:7.1f} {r['rms_db']:7.1f} {r['clipped']:5d}"
            f" {r['centroid_hz']:8.0f}Hz  {seam}"
        )


def _plot_one(ax_wave, ax_spec, mono: np.ndarray, rate: int, title: str) -> None:
    t = np.arange(len(mono)) / rate
    ax_wave.plot(t, mono, lw=0.4, color="#2b6cb0")
    ax_wave.set_ylim(-1, 1)
    ax_wave.set_xlim(0, t[-1])
    ax_wave.set_title(title, fontsize=8, loc="left")
    ax_wave.tick_params(labelsize=6)
    nper = 1024 if len(mono) > 8192 else 256
    f, tt, sxx = signal.spectrogram(mono, rate, nperseg=nper, noverlap=nper * 3 // 4)
    ax_spec.pcolormesh(tt, f, 10 * np.log10(sxx + 1e-12), shading="auto", vmin=-110, vmax=-30, cmap="magma")
    ax_spec.set_yscale("symlog", linthresh=500)
    ax_spec.set_ylim(40, rate / 2)
    ax_spec.set_xlim(0, t[-1])
    ax_spec.tick_params(labelsize=6)


def sheet(paths: list[Path], out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    cols = 3
    rows_n = -(-len(paths) // cols)
    fig, axes = plt.subplots(rows_n * 2, cols, figsize=(cols * 4.4, rows_n * 3.2), squeeze=False)
    for i, path in enumerate(paths):
        data, rate = read_wav(path)
        r, c = divmod(i, cols)
        _plot_one(axes[r * 2][c], axes[r * 2 + 1][c], data.mean(axis=0), rate, path.stem)
    for i in range(len(paths), rows_n * cols):
        r, c = divmod(i, cols)
        axes[r * 2][c].axis("off")
        axes[r * 2 + 1][c].axis("off")
    fig.tight_layout()
    fig.savefig(out, dpi=110)


def onsets(mono: np.ndarray, rate: int, rise_db: float = 9.0, gap: float = 0.15) -> list[float]:
    """Times where the short-term level jumps `rise_db` above the background (its median over the last second and the
    next), so a sound is found on top of a bed that never goes quiet."""
    from scipy.ndimage import median_filter

    hop = int(rate * 0.005)
    frames = np.sqrt(np.convolve(mono**2, np.ones(hop * 2) / (hop * 2), "same")[::hop])
    level = 20 * np.log10(frames + 1e-9)
    background = median_filter(level, size=401, mode="nearest")
    above = level - background > rise_db
    times: list[float] = []
    for i in np.nonzero(above & ~np.concatenate(([False], above[:-1])))[0]:
        now = i * hop / rate
        if not times or now - times[-1] >= gap:
            times.append(now)
    return times


def capture(path: Path, out: Path | None, window: float, expects: list[str], tolerance: float) -> int:
    data, rate = read_wav(path)
    mono = data.mean(axis=0)
    peak = float(np.abs(data).max())
    clipped = int((np.abs(data) >= CLIP_LEVEL).sum())
    print(f"{path.name}: {data.shape[1] / rate:.2f} s, {rate} Hz, {data.shape[0]} ch")
    print(f"  mix peak {db(peak):.1f} dBFS, clipped samples {clipped}, rms {db(np.sqrt((mono**2).mean())):.1f} dBFS")
    step = int(window * rate)
    print("  level in windows (seconds: rms dBFS / peak dBFS):")
    for start in range(0, len(mono) - step // 2, step):
        seg = mono[start : start + step]
        print(f"    {start / rate:7.2f}: {db(np.sqrt((seg**2).mean())):7.1f} / {db(np.abs(seg).max()):7.1f}")
    heard = onsets(mono, rate)
    print(f"  onsets ({len(heard)}): " + ", ".join(f"{t:.2f}" for t in heard[:60]))
    failed = 0
    for spec in expects:
        when, name = spec.split(":", 1)
        want = float(when)
        near = min(heard, key=lambda t: abs(t - want), default=None)
        ok = near is not None and abs(near - want) <= tolerance
        failed += 0 if ok else 1
        found = "none" if near is None else f"{near:.2f}"
        lead = mono[max(0, int((want - 0.6) * rate)) : int((want - 0.05) * rate)]
        after = mono[int(want * rate) : int((want + 0.4) * rate)]
        jump = db(np.abs(after).max()) - db(np.sqrt((lead**2).mean())) if len(lead) and len(after) else 0.0
        print(
            f"  expect {name} at {want:.2f}s: onset {found}, peak {jump:+.1f} dB over the rms of the 0.6 s before -> {'ok' if ok else 'MISSED'}"
        )
    if clipped:
        failed += 1
        print("  CLIPPED")
    if out is not None:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, (a, b) = plt.subplots(2, 1, figsize=(13, 5.5), sharex=True)
        _plot_one(a, b, mono, rate, f"{path.stem}: mix, peak {db(peak):.1f} dBFS")
        for t in heard:
            a.axvline(t, color="#c53030", lw=0.5, alpha=0.6)
        for spec in expects:
            when, name = spec.split(":", 1)
            a.text(float(when), 0.8, name, fontsize=6, rotation=90, color="#276749")
        fig.tight_layout()
        fig.savefig(out, dpi=110)
    return failed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("report")
    r.add_argument("wavs", nargs="+", type=Path)
    r.add_argument("--loops", default="crickets,highway,projector,score,generator_hum")
    s = sub.add_parser("sheet")
    s.add_argument("wavs", nargs="+", type=Path)
    s.add_argument("--out", type=Path, required=True)
    c = sub.add_parser("capture")
    c.add_argument("wav", type=Path)
    c.add_argument("--out", type=Path)
    c.add_argument("--window", type=float, default=1.0)
    c.add_argument("--expect", action="append", default=[])
    c.add_argument("--tolerance", type=float, default=0.25)
    args = parser.parse_args()
    if args.cmd == "report":
        print_report(report(args.wavs, set(args.loops.split(","))))
    elif args.cmd == "sheet":
        sheet(args.wavs, args.out)
    else:
        sys.exit(1 if capture(args.wav, args.out, args.window, args.expect, args.tolerance) else 0)


if __name__ == "__main__":
    main()
