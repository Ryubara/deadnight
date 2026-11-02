"""Loudness report of a night capture with the soldier's voice: the voice against the guns and the beds.

    uv run --with numpy --with scipy --with matplotlib --with pyloudnorm python tools/audio/voice_report.py
        --stems <folder with stem_voice.wav, stem_effects.wav, stem_ambience.wav> --log <capture log>
        [--mix night.wav] [--out report.png]

`game/tests/captures/audio_soldier_night.tscn` records the Voice, Effects and Ambience buses as stems and prints
`VOICE <seconds> <id>` for every line and `GUN <seconds> <id>` for every shot. This reads them and prints, in LUFS
(ITU-R BS.1770, K-weighted, gated):

- the integrated loudness of each stem over the whole run;
- the voice lines' loudness while they speak (momentary, 400 ms windows over each line), by moment;
- the guns' loudness in the 400 ms after a shot, and the loudest second of the Effects stem;
- the beds' loudness (Ambience stem) and the voice against the rest of the night in the same windows.

The mix file, when given, is checked for clipping and its peak.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from analyze import read_wav

WINDOW = 0.4


def lufs(samples: np.ndarray, rate: int) -> float:
    import pyloudnorm

    if samples.shape[0] < int(WINDOW * rate):
        return -70.0
    value = pyloudnorm.Meter(rate).integrated_loudness(samples)
    return float(value) if np.isfinite(value) else -70.0


def stem(path: Path) -> tuple[np.ndarray, int]:
    data, rate = read_wav(path)
    return data, rate  # (channels, n)


def window(data: np.ndarray, rate: int, start: float, seconds: float) -> np.ndarray:
    a = max(int(start * rate), 0)
    return data[:, a : a + int(seconds * rate)].T  # pyloudnorm wants (n, channels)


def parse(log: Path) -> tuple[list[tuple[float, str]], list[tuple[float, str]]]:
    voice, guns = [], []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"(VOICE|GUN) ([\d.]+) (\S+)", line)
        if m:
            (voice if m.group(1) == "VOICE" else guns).append((float(m.group(2)), m.group(3)))
    return voice, guns


def level(data: np.ndarray, rate: int, start: float, seconds: float) -> float:
    return lufs(window(data, rate, start, seconds), rate)


def loudest(data: np.ndarray, rate: int, step: float = 0.5) -> tuple[float, float]:
    best, at = -70.0, 0.0
    for t in np.arange(0.0, data.shape[1] / rate - 1.0, step):
        value = level(data, rate, float(t), 1.0)
        if value > best:
            best, at = value, float(t)
    return best, at


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--stems", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--mix", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    voice_data, vr = stem(args.stems / "stem_voice.wav")
    fx_data, fr = stem(args.stems / "stem_effects.wav")
    amb_data, ar = stem(args.stems / "stem_ambience.wav")
    voice_log, gun_log = parse(args.log)
    seconds = voice_data.shape[1] / vr
    print(f"run: {seconds:.1f} s, {len(voice_log)} voice lines, {len(gun_log)} shots logged")
    print("\nIntegrated loudness of each stem over the run (LUFS):")
    for name, data, rate in (("Voice", voice_data, vr), ("Effects", fx_data, fr), ("Ambience", amb_data, ar)):
        print(
            f"  {name:9s}{lufs(data.T, rate):7.1f} LUFS   peak {20 * np.log10(max(np.abs(data).max(), 1e-9)):6.1f} dBFS"
        )

    per_event: dict[str, list[float]] = {}
    against: list[float] = []
    for t, take in voice_log:
        event = take.removeprefix("vox_").rsplit("_", 1)[0]
        v = level(voice_data, vr, t, 1.2)
        per_event.setdefault(event, []).append(v)
        fx, amb = window(fx_data, fr, t, 1.2), window(amb_data, ar, t, 1.2)
        n = min(len(fx), len(amb))
        against.append(v - lufs(fx[:n] + amb[:n], fr))
    print("\nThe voice while it speaks, first 1.2 s of each line (LUFS), by moment:")
    for event, values in sorted(per_event.items()):
        print(f"  {event:14s}{len(values):3d} lines   mean {np.mean(values):6.1f}   max {max(values):6.1f}")
    allv = [v for values in per_event.values() for v in values]
    print(f"  {'all':14s}{len(allv):3d} lines   mean {np.mean(allv):6.1f}   max {max(allv):6.1f}")

    shots = [level(fx_data, fr, t, WINDOW) for t, _ in gun_log]
    best, at = loudest(fx_data, fr)
    print(f"\nThe guns (Effects stem), {WINDOW} s from each shot: mean {np.mean(shots):.1f} LUFS, max {max(shots):.1f}")
    print(f"  loudest second of the Effects stem: {best:.1f} LUFS at {at:.1f} s")
    quiet_t = [t for t in np.arange(0.0, seconds - 1.2, 1.0) if not any(abs(t - g) < 2.0 for g, _ in gun_log)]
    bed_levels = [level(amb_data, ar, float(t), 1.0) for t in quiet_t]
    print(f"\nThe beds (Ambience stem) away from gunfire: mean {np.mean(bed_levels):.1f} LUFS over {len(bed_levels)} s")
    print(
        f"\nVoice against guns: mean voice line {np.mean(allv) - np.mean(shots):+.1f} LU, against the beds {np.mean(allv) - np.mean(bed_levels):+.1f} LU"
    )
    print(f"Voice against everything else playing in the same 1.2 s: mean {np.mean(against):+.1f} LU")

    if args.mix:
        mix, mr = read_wav(args.mix)
        peak = float(np.abs(mix).max())
        print(
            f"\nMix {args.mix.name}: {mix.shape[1] / mr:.1f} s, peak {20 * np.log10(max(peak, 1e-9)):.1f} dBFS, "
            f"clipped samples {int((np.abs(mix) >= 0.999).sum())}, integrated {lufs(mix.T, mr):.1f} LUFS"
        )

    if args.out:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, ax = plt.subplots(figsize=(13, 4.5))
        for name, data, rate, color in (
            ("Effects (guns, the dead)", fx_data, fr, "#c05621"),
            ("Ambience (beds)", amb_data, ar, "#2f855a"),
            ("Voice (the soldier)", voice_data, vr, "#2b6cb0"),
        ):
            ts = np.arange(0.0, data.shape[1] / rate - 0.5, 0.5)
            ax.plot(ts, [level(data, rate, float(t), 0.5) for t in ts], label=name, color=color, lw=1.2)
        for t, take in voice_log:
            ax.axvline(t, color="#2b6cb0", alpha=0.25, lw=0.8)
        ax.set_ylim(-70, 0)
        ax.set_xlabel("seconds")
        ax.set_ylabel("loudness, 0.5 s windows (LUFS)")
        ax.set_title("A night with the soldier's voice: the stems' loudness (blue lines: a voice line starts)")
        ax.legend(loc="lower right")
        fig.tight_layout()
        fig.savefig(args.out, dpi=110)
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
