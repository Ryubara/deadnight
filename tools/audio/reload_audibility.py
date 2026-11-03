"""Is each reload step heard under fire? Measured, not listened to (Deadnight #683).

    uv run --with numpy --with scipy --with matplotlib python tools/audio/reload_audibility.py \
        --fire fire.wav --reload reload.wav --log reload.log [--out plot.png] [--label own_rifle_smg]

`fire.wav` and `reload.wav` are two Movie Maker mixes of the same timeline from
`game/tests/captures/reload_under_fire.tscn` (`--part=fire` and `--part=reload`): the buses have no effects, so the
game's mix of both is their sum and each part can be measured on its own. The log holds the capture's
`STEP <seconds> <sound>` lines (the sound starts a few hundredths later, and its loudest part may come later still,
as the lever's second clack), so each step is found in the reload track within `SPAN` of its line and before the
next step's.

Two numbers per step, both the step's level over the gunfire's in octave bands (signal-to-masker ratio, dB):
- `peak`: over the `WINDOW` around the step's loudest moment, the best band. Strict: at the tommy gun's 0.075 s the
  window always holds a whole shot. A step counts as heard when this is at least `HEARD_DB`.
- `glimpse`: over `FRAME`-long frames through the step, the best frame and band (shown up to `GLIMPSE_CAP`): how far it
  stands out in the gaps between shots, where hearing picks a click out. Generous by nature, so it is only reported.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from analyze import db, read_wav

WINDOW = 0.08  # seconds around a step's loudest moment
SPAN = 0.45  # seconds after its STEP line a step is looked for
FRAME = 0.02  # seconds per glimpse frame, hop half of it
BANDS = (250, 500, 1000, 2000, 4000, 8000)  # octave centres, Hz
HEARD_DB = 0.0
GLIMPSE_CAP = 40.0


def band_levels(mono: np.ndarray, rate: int) -> np.ndarray:
    """Energy in each octave band, dB (relative)."""
    spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1 / rate)
    out = []
    for centre in BANDS:
        lo, hi = centre / np.sqrt(2), centre * np.sqrt(2)
        out.append(10 * np.log10(max(float(spectrum[(freqs >= lo) & (freqs < hi)].sum()), 1e-12)))
    return np.array(out)


def steps(log: Path) -> list[tuple[float, str]]:
    found = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"STEP ([\d.]+) (\S+)", line)
        if m:
            found.append((float(m.group(1)), m.group(2)))
    return found


def measure(fire: Path, reload: Path, log: Path) -> list[dict]:
    f, rate = read_wav(fire)
    r, rate_r = read_wav(reload)
    assert rate == rate_r, "the two mixes must share a rate"
    n = min(f.shape[1], r.shape[1])
    fm, rm = f[:, :n].mean(axis=0), r[:, :n].mean(axis=0)
    rows = []
    found = steps(log)
    for i, (at, name) in enumerate(found):
        a = int(at * rate)
        # Up to `SPAN`, and never into the next step's own sound (it starts as late as this one does).
        until = found[i + 1][0] if i + 1 < len(found) else at + SPAN
        b = min(a + int(min(SPAN, until - at + 0.03) * rate), n)
        part = rm[a:b]
        if len(part) < 256:
            continue
        # The step's loudest moment, and the stretch where it is within 30 dB of it.
        env = np.convolve(np.abs(part), np.ones(int(0.005 * rate)) / int(0.005 * rate), mode="same")
        top = int(np.argmax(env))
        lit = np.nonzero(env >= env[top] * 10 ** (-30 / 20))[0]
        w0 = max(a + top - int(WINDOW * rate / 2), 0)
        w1 = min(w0 + int(WINDOW * rate), n)
        peak = band_levels(rm[w0:w1], rate) - band_levels(fm[w0:w1], rate)
        frame, hop = int(FRAME * rate), int(FRAME * rate / 2)
        glimpse, glimpse_band, glimpse_t = -999.0, BANDS[0], at
        first = min(a + int(lit[0]), a + top - frame // 2)
        last = max(a + int(lit[-1]) - frame, a + top - frame // 2)
        for start in range(max(first, 0), min(last, n - frame) + 1, hop):
            smr = band_levels(rm[start : start + frame], rate) - band_levels(fm[start : start + frame], rate)
            k = int(np.argmax(smr))
            if smr[k] > glimpse:
                glimpse, glimpse_band, glimpse_t = float(smr[k]), BANDS[k], start / rate
        best = int(np.argmax(peak))
        rows.append(
            {
                "t": at,
                "step": name,
                "step_peak_db": db(np.abs(part).max()),
                "fire_peak_db": db(np.abs(fm[w0:w1]).max()),
                "best_band_hz": BANDS[best],
                "best_smr_db": float(peak[best]),
                "glimpse_db": min(glimpse, GLIMPSE_CAP),
                "glimpse_band_hz": glimpse_band,
                "glimpse_t": glimpse_t,
                "heard": bool(peak[best] >= HEARD_DB),
            }
        )
    both = fm + rm
    rows.append({"mix_peak_db": db(np.abs(both).max()), "clipped": int((np.abs(both) >= 0.999).sum())})
    return rows


def plot(fire: Path, reload: Path, log: Path, out: Path, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    f, rate = read_wav(fire)
    r, _ = read_wav(reload)
    n = min(f.shape[1], r.shape[1])
    t = np.arange(n) / rate
    fig, ax = plt.subplots(figsize=(12, 3.2))
    ax.plot(t, f[:, :n].mean(axis=0), color="#9aa0a6", lw=0.5, label="gunfire")
    ax.plot(t, r[:, :n].mean(axis=0), color="#d1453b", lw=0.6, label="reload")
    for at, name in steps(log):
        ax.axvline(at, color="#d1453b", lw=0.4, ls=":")
        ax.text(
            at, 0.95, name.replace("reload_", ""), rotation=90, fontsize=6, va="top", transform=ax.get_xaxis_transform()
        )
    ax.set_xlabel("seconds")
    ax.set_title(title, fontsize=9)
    ax.legend(loc="lower right", fontsize=7)
    fig.tight_layout()
    fig.savefig(out, dpi=110)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fire", type=Path, required=True)
    ap.add_argument("--reload", type=Path, required=True)
    ap.add_argument("--log", type=Path, required=True)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--label", default="")
    args = ap.parse_args()
    rows = measure(args.fire, args.reload, args.log)
    for row in rows[:-1]:
        print(
            f"{args.label}\t{row['t']:.3f}\t{row['step']}\tstep {row['step_peak_db']:.1f} dBFS\t"
            f"fire {row['fire_peak_db']:.1f} dBFS\tpeak {row['best_band_hz']} Hz {row['best_smr_db']:+.1f} dB\t"
            f"glimpse {row['glimpse_band_hz']} Hz {row['glimpse_db']:+.1f} dB\t{'heard' if row['heard'] else 'MASKED'}"
        )
    print(f"{args.label}\tmix peak {rows[-1]['mix_peak_db']:.1f} dBFS, {rows[-1]['clipped']} clipped samples")
    if args.out:
        plot(args.fire, args.reload, args.log, args.out, args.label)


if __name__ == "__main__":
    main()
