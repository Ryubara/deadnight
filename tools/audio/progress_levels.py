"""Measure the progression sounds as the player hears them, without ears (#1062).

    uv run --with numpy --with scipy --with matplotlib python tools/audio/progress_levels.py levels mix.wav run.log
        [--plot levels.png] [--sheet sheet.png] [--json out.json] [--pin game/tests/core/progress_sound_levels.json]

`mix.wav` and `run.log` are the recording of `game/tests/captures/audio_progress_levels.tscn`: each cue alone (every
variant file), eight unlocks in two seconds and at 0.15 s, moments close together, the night's sounds a cue must not
hide (a pistol shot, a groan, a shriek, a grenade's beep, two of the soldier's urgent lines, a footstep, the till), the
bursts of three automatic weapons and the night's beds, all through the real service and buses at the default
settings (Movie Maker's 32-bit PCM at 48 kHz: `ffmpeg -i m.avi -vn -c:a pcm_s32le m.wav`). No bus has an effect, so the
sum of two recordings is the recording of both played together: what a cue does to a shot is the cue's recording plus the
shot's, with the shot started anywhere over the cue.

What it prints and gates (exit 1 when one fails):

1. **Level**: each cue's peak (dBFS, Master) against its target in `menu_sound_levels.json`, its length against its row in
   `UiSoundTable`, no sample over `CLIP_DB`, the share of its energy in the first 50 ms (a sound whose attack is a
   moment is plain at once), the loudest 400 ms (LUFS-M, K-weighted) and the spectrum's centroid.
2. **Against the night and the menu**: the loudest 400 ms of each cue against a pistol shot's, a burst's and the night's
   beds' (all LUFS-M), and the menu's bed (pinned in `menu_bed_levels.json`).
3. **Stacks**: eight unlocks in two seconds, and at the popups' 0.15 s, peak under the level up's peak.
4. **Moments**: a scratch and a level up asked for together, a level up and a tier up in both orders, a tier up and a
   scratch: the mix's peak stays under `MOMENTS_CEILING_DB`; a level up asked for while a tier up sounds is not played.
5. **Does not hide**: for each cue and each sound it must not mask, the reference's loudest 50 ms in its own band (the
   band that holds 80 percent of its energy) minus the cue's loudest 50 ms in that band: the worst case, the cue's loudest
   moment under the reference's, must stay `MASK_GATE_DB` or more.
6. **Over a burst**: a cue started anywhere over a burst of an automatic weapon (every 50 ms of it): the sum's peak, the
   samples over `CLIP_DB`, and the bands where the cue stands out of the burst (`AUDIBLE_BANDS` of them over `AUDIBLE_OVER_DB`).

The margins of 5 and 6 are read at the night's level, the table's menu level plus `FIGHT_DB`.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
from menu_levels import TARGETS, db, first_over, momentary_max, parse, read_stereo

ROOT = Path(__file__).resolve().parents[2]
CLIP_DB = -1.0
# The loudest any combination of progression sounds may reach, under the pistol's -8.6 at the muzzle.
MOMENTS_CEILING_DB = -9.0
MASK_GATE_DB = 6.0
# The window the reference's loudest moment is read over: a shot is a click and is read over 10 ms, every other
# sound over 50 ms.
SHORT_WINDOW_S = 0.01
# In a night the cues are this much quieter than the table's menu levels (`UiSounds.FIGHT_DB`): the margins and the
# audibility below are read at that level, and the menu's levels are the table's. Passed with `--fight-db`.
FIGHT_DB = -10.0
# A cue is audible over a burst when at least this many third-octave bands (200 Hz to 6.3 kHz) of its loudest 400 ms
# stand `AUDIBLE_OVER_DB` over the burst's average in the same band: a brass note is a few narrow peaks, a burst is a
# broad wash, and a tone is heard in noise when it stands out in its own band.
AUDIBLE_BANDS = 2
AUDIBLE_OVER_DB = 0.0
# The cue must be at least this far under a pistol shot in loudness (LUFS-M): never the loudest thing in a fight.
UNDER_PISTOL_LU = 0.0
FIRST_MS = 50
WINDOW_S = 0.05
LENGTH_TOLERANCE = 0.15
PEAK_TOLERANCE_DB = 1.0
MENU_BED_PATH = ROOT / "game" / "tests" / "core" / "menu_bed_levels.json"
SOUNDS = {
    "challenge_done": "ui_challenge_done",
    "level_up": "ui_level_up",
    "tier_up": "ui_tier_up",
    "unlock": "ui_unlock",
    "card_earned": "ui_card_earned",
}
SECONDS = {"challenge_done": 0.6, "level_up": 1.1, "tier_up": 2.0, "unlock": 0.35, "card_earned": 0.5}
# What the cues must not hide, and what each one is for the table (a shot, a groan, a warning).
MUST_STAY = {
    "shot_pistol": "shot",
    "zombie_groan": "groan",
    "zombie_shriek": "warning",
    "grenade_beep": "warning",
    "vox_boss_arrive_1": "warning",
    "vox_low_ammo_1": "warning",
}


# ---- reading the recording ---------------------------------------------------------------------------------------


def cut(mix: np.ndarray, rate: int, start: float, end: float) -> np.ndarray:
    """The part of the mix from `start` to `end` seconds, trimmed to where the sound begins."""
    a = max(int((start - 0.02) * rate), 0)
    b = min(int((end - 0.02) * rate), mix.shape[-1])
    begin = first_over(mix[:, a:b], 0) + a
    return mix[:, max(begin - int(0.005 * rate), 0) : b]


def events(log: Path) -> list[tuple[float, str, list[str]]]:
    rows = []
    for kind in ("PLAY", "REF", "BURST", "SECTION", "BEDS"):
        for row in parse(log, kind):
            rows.append((float(row[0]), kind, list(row[1:])))
    return sorted(rows, key=lambda e: (e[0], e[1] != "SECTION"))


def length_s(seg: np.ndarray, rate: int, floor_db: float = -45.0) -> float:
    """From the first sample to the last 10 ms window that is within `floor_db` of the segment's peak."""
    mono = np.sqrt(np.mean(seg**2, axis=0))
    win = int(0.01 * rate)
    rms = np.sqrt(np.convolve(mono**2, np.ones(win) / win, mode="same"))
    loud = np.nonzero(rms > mono.max() * 10 ** (floor_db / 20))[0]
    return (loud[-1] + 1) / rate if len(loud) else 0.0


def moving_mean(x: np.ndarray, n: int) -> np.ndarray:
    """The mean of every `n` samples (the windows that fit), by a running sum."""
    total = np.concatenate([[0.0], np.cumsum(x)])
    return (total[n:] - total[:-n]) / n


def power(seg: np.ndarray) -> np.ndarray:
    """Instantaneous power summed over the channels."""
    return np.sum(seg**2, axis=0)


def centroid(seg: np.ndarray, rate: int) -> float:
    mono = seg.sum(axis=0)
    spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    return float((spectrum * np.fft.rfftfreq(len(mono), 1 / rate)).sum() / (spectrum.sum() + 1e-12))


def band_of(seg: np.ndarray, rate: int, share: float = 0.8) -> tuple[float, float]:
    """The band that holds `share` of the energy of the loudest 300 ms of a sound (the cumulative energy from
    (1-share)/2 to (1+share)/2), from 60 Hz up."""
    n = int(0.3 * rate)
    p = power(seg)
    win = moving_mean(p, n) if len(p) > n else np.array([p.mean()])
    start = int(np.argmax(win))
    part = seg[:, start : start + n].sum(axis=0)
    spectrum = np.abs(np.fft.rfft(part * np.hanning(len(part)))) ** 2
    freqs = np.fft.rfftfreq(len(part), 1 / rate)
    keep = freqs >= 60.0
    cumulative = np.cumsum(spectrum[keep])
    cumulative /= max(cumulative[-1], 1e-30)
    lo = freqs[keep][int(np.searchsorted(cumulative, (1 - share) / 2))]
    hi = freqs[keep][int(np.searchsorted(cumulative, (1 + share) / 2))]
    return float(lo), float(max(hi, lo * 1.5))


def band_filter(seg: np.ndarray, rate: int, lo: float, hi: float) -> np.ndarray:
    sos = signal.butter(4, [lo / (rate / 2), min(hi, rate / 2 * 0.95) / (rate / 2)], btype="band", output="sos")
    return signal.sosfilt(sos, seg, axis=-1)


def loudest_window(seg: np.ndarray, rate: int, seconds: float = WINDOW_S) -> float:
    """The loudest `seconds` of rms, dB, summed over the channels (a flat sound in both channels reads as it is)."""
    n = int(seconds * rate)
    p = power(seg)
    if len(p) < n:
        p = np.pad(p, (0, n - len(p)))
    win = moving_mean(p, n)
    return 10.0 * np.log10(max(float(win.max()), 1e-18))


def p95_50ms(seg: np.ndarray, rate: int) -> float:
    n = int(WINDOW_S * rate)
    win = moving_mean(power(seg), n)
    return 10.0 * np.log10(max(float(np.percentile(win, 95)), 1e-18))


# ---- the measures ------------------------------------------------------------------------------------------------


def measure_cues(mix: np.ndarray, rate: int, rows: list) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = defaultdict(list)
    for i, (t, kind, row) in enumerate(rows):
        if kind != "PLAY" or row[0] != "cue":
            continue
        end = rows[i + 1][0] if i + 1 < len(rows) else t + 3.0
        seg = cut(mix, rate, t, end)
        first = seg[:, : int(FIRST_MS / 1000 * rate)]
        out[row[1]].append(
            {
                "variant": int(row[3]),
                "peak": db(np.abs(seg).max()),
                "lufs_m": momentary_max(seg, rate),
                "seconds": length_s(seg, rate),
                "first50": float(np.sum(first**2) / max(np.sum(seg**2), 1e-18)),
                "centroid": centroid(seg, rate),
                "clipped": int(np.sum(np.abs(seg) > 10 ** (CLIP_DB / 20))),
                "seg": seg,
            }
        )
    return out


def measure_refs(mix: np.ndarray, rate: int, rows: list) -> dict[str, dict]:
    refs: dict[str, dict] = {}
    for i, (t, kind, row) in enumerate(rows):
        if kind not in ("REF", "BURST"):
            continue
        end = rows[i + 1][0] if i + 1 < len(rows) else t + 3.0
        if kind == "BURST":
            seg = cut(mix, rate, t, t + float(row[1]) + 1.2)
            name = row[0]
        else:
            seg = cut(mix, rate, t, end)
            name = row[0]
            if name == "zombie_groan":
                # The capture plays the groan 6 m off, then 2 m off.
                name = "zombie_groan_2m" if "zombie_groan_6m" in refs else "zombie_groan_6m"
        lo, hi = band_of(seg, rate)
        refs[name] = {
            "name": name,
            "seg": seg,
            "kind": kind,
            "peak": db(np.abs(seg).max()),
            "lufs_m": momentary_max(seg, rate),
            "band": (lo, hi),
        }
    return refs


def measure_stacks(mix: np.ndarray, rate: int, rows: list) -> dict[str, dict]:
    out = {}
    for i, (t, kind, row) in enumerate(rows):
        if kind != "PLAY" or not row[0].startswith("stack_"):
            continue
        name = row[0]
        entry = out.setdefault(name, {"start": t, "last": t, "count": 0})
        entry["last"] = t
        entry["count"] += 1
    for name, e in out.items():
        seg = cut(mix, rate, e["start"], e["last"] + 1.0)
        e["peak"] = db(np.abs(seg).max())
        e["lufs_m"] = momentary_max(seg, rate)
    return out


def measure_moments(mix: np.ndarray, rate: int, rows: list) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for i, (t, kind, row) in enumerate(rows):
        if kind != "PLAY" or not row[0].startswith("moment_"):
            continue
        case = row[0].removeprefix("moment_")
        entry = out.setdefault(case, {"start": t, "last": t, "played": []})
        entry["last"] = t
        entry["played"].append((row[1], int(row[2])))
    for e in out.values():
        seg = cut(mix, rate, e["start"], e["last"] + 3.0)
        e["peak"] = db(np.abs(seg).max())
    return out


def over_burst(cue: np.ndarray, burst: np.ndarray, rate: int) -> dict:
    """The cue added to the burst, started at each 50 ms of the burst: the worst peak, the samples over the clip
    level, and the cue's loudest 400 ms against the burst's own."""
    worst = -200.0
    clipped = 0
    step = int(0.05 * rate)
    for start in range(0, max(burst.shape[-1] - step, 1), step):
        size = max(burst.shape[-1], start + cue.shape[-1])
        total = np.zeros((2, size))
        total[:, : burst.shape[-1]] += burst
        total[:, start : start + cue.shape[-1]] += cue
        worst = max(worst, db(np.abs(total).max()))
        clipped = max(clipped, int(np.sum(np.abs(total) > 10 ** (CLIP_DB / 20))))
    return {
        "peak": worst,
        "clipped": clipped,
        "cue_lufs_m": momentary_max(cue, rate),
        "burst_lufs_m": momentary_max(burst, rate),
    }


THIRD_OCTAVES = [200.0 * 2 ** (k / 3) for k in range(16)]


def band_levels(seg: np.ndarray, rate: int) -> np.ndarray:
    """The power in each third octave from 200 Hz up to 6.3 kHz, dB, of the average spectrum of the segment."""
    mono = seg.sum(axis=0)
    freqs, density = signal.welch(mono, rate, nperseg=4096)
    levels = []
    for centre in THIRD_OCTAVES:
        lo, hi = centre / 2 ** (1 / 6), centre * 2 ** (1 / 6)
        keep = (freqs >= lo) & (freqs < hi)
        levels.append(10.0 * np.log10(max(float(density[keep].sum()), 1e-24)))
    return np.array(levels)


def loudest_400ms(seg: np.ndarray, rate: int) -> np.ndarray:
    n = int(0.4 * rate)
    if seg.shape[-1] <= n:
        return seg
    start = int(np.argmax(moving_mean(power(seg), n)))
    return seg[:, start : start + n]


def audible_bands(cue: np.ndarray, burst: np.ndarray, rate: int) -> tuple[int, float]:
    """How many third-octave bands of the cue's loudest 400 ms stand over the burst's average, and the most by which."""
    over = band_levels(loudest_400ms(cue, rate), rate) - band_levels(burst, rate)
    return int(np.sum(over >= AUDIBLE_OVER_DB)), float(over.max())


def masking(cue: np.ndarray, ref: dict, rate: int) -> dict:
    """The reference's loudest 50 ms in its own band minus the cue's loudest 50 ms in that band (the cue at its
    loudest over the reference at its loudest is the worst alignment there is)."""
    lo, hi = ref["band"]
    window = SHORT_WINDOW_S if ref["name"].startswith("shot_pistol") else WINDOW_S
    ref_level = loudest_window(band_filter(ref["seg"], rate, lo, hi), rate, window)
    cue_level = loudest_window(band_filter(cue, rate, lo, hi), rate, window)
    return {"margin": ref_level - cue_level, "ref_db": ref_level, "cue_db": cue_level, "band": (lo, hi)}


# ---- report ------------------------------------------------------------------------------------------------------


def report(mix: np.ndarray, rate: int, log: Path, fight_db: float) -> tuple[int, dict]:
    rows = events(log)
    cues = measure_cues(mix, rate, rows)
    refs = measure_refs(mix, rate, rows)
    stacks = measure_stacks(mix, rate, rows)
    moments = measure_moments(mix, rate, rows)
    failed = 0
    gain = 10 ** (fight_db / 20)
    table: dict = {
        "fight_db": fight_db,
        "cues": {},
        "refs": {},
        "stacks": {},
        "moments": {},
        "masking": {},
        "burst": {},
    }

    print("1. level, length, attack, spectrum (every variant file, the mean of the variants in the second line)")
    print(f"{'cue':16} {'var':>3} {'peak':>6} {'LUFS-M':>7} {'sec':>5} {'first50':>8} {'centroid':>9} {'clipped':>8}")
    peaks_of: dict[str, float] = {}
    for cue, sound in SOUNDS.items():
        for v in cues[cue]:
            print(
                f"{cue:16} {v['variant']:>3} {v['peak']:6.1f} {v['lufs_m']:7.1f} {v['seconds']:5.2f}"
                f" {v['first50'] * 100:7.1f}% {v['centroid']:8.0f}Hz {v['clipped']:>8}"
            )
        mean_peak = float(np.mean([v["peak"] for v in cues[cue]]))
        peaks_of[cue] = mean_peak
        target = TARGETS[f"{sound}|0.0"][0]
        seconds = float(np.mean([v["seconds"] for v in cues[cue]]))
        verdicts = []
        if abs(mean_peak - target) > PEAK_TOLERANCE_DB:
            verdicts.append(f"PEAK {mean_peak:.1f} OFF TARGET {target:.1f}")
        if abs(seconds - SECONDS[cue]) > SECONDS[cue] * LENGTH_TOLERANCE:
            verdicts.append(f"LENGTH {seconds:.2f} s, row says {SECONDS[cue]}")
        if any(v["clipped"] for v in cues[cue]):
            verdicts.append("CLIPS")
        failed += len(verdicts)
        print(
            f"{cue:16} mean {mean_peak:6.1f} {float(np.mean([v['lufs_m'] for v in cues[cue]])):7.1f} {seconds:5.2f}"
            f"   target {target:.1f}  {'ok' if not verdicts else '; '.join(verdicts)}"
        )
        table["cues"][cue] = {
            "peak": round(mean_peak, 1),
            "lufs_m": round(float(np.mean([v["lufs_m"] for v in cues[cue]])), 1),
            "seconds": round(seconds, 2),
            "first50_percent": round(100 * float(np.mean([v["first50"] for v in cues[cue]])), 1),
            "centroid_hz": round(float(np.mean([v["centroid"] for v in cues[cue]]))),
        }

    print("\n2. against the night and the menu (LUFS-M, the loudest 400 ms)")
    pistol = refs["shot_pistol"]
    menu_bed = json.loads(MENU_BED_PATH.read_text(encoding="utf-8"))["worst"]["flat"]["bed_lufs_m"]
    print(
        f"   pistol shot {pistol['lufs_m']:.1f} (peak {pistol['peak']:.1f}), menu bed (loudest 400 ms) {menu_bed:.1f}"
    )
    for t, kind, row in rows:
        if kind == "BEDS":
            # The night's beds alone (crickets, highway, score, wind), after their three-second fade in.
            bed = cut(mix, rate, t + 4.0, t + 11.5)
            table["night_beds_lufs_m"] = round(momentary_max(bed, rate), 1)
            print(
                f"   the night's beds alone: peak {db(np.abs(bed).max()):6.1f}   LUFS-M {table['night_beds_lufs_m']:6.1f}"
            )
    for name, ref in refs.items():
        print(f"   {name:22} peak {ref['peak']:6.1f}   LUFS-M {ref['lufs_m']:6.1f}")
        table["refs"][name] = {"peak": round(ref["peak"], 1), "lufs_m": round(ref["lufs_m"], 1)}
    for cue in SOUNDS:
        lufs = table["cues"][cue]["lufs_m"]
        fight = lufs + fight_db
        under = pistol["lufs_m"] - fight
        verdict = "ok"
        if under < UNDER_PISTOL_LU:
            verdict = f"LOUDER THAN THE PISTOL by {-under:.1f} LU"
            failed += 1
        print(
            f"   {cue:16} menu {lufs:6.1f} ({lufs - menu_bed:+5.1f} LU over the menu bed), in a night {fight:6.1f}:"
            f" {under:+5.1f} LU under the pistol  {verdict}"
        )
        table["cues"][cue]["fight_lufs_m"] = round(fight, 1)
        table["cues"][cue]["fight_under_pistol_lu"] = round(under, 1)

    print("\n3. stacks (peak against the level up's)")
    for name, e in stacks.items():
        verdict = "ok" if e["peak"] < peaks_of["level_up"] else "OVER THE LEVEL UP"
        failed += verdict != "ok"
        print(
            f"   {name} {e['count']} sounds: peak {e['peak']:.1f} (level up {peaks_of['level_up']:.1f}), LUFS-M {e['lufs_m']:.1f}  {verdict}"
        )
        table["stacks"][name] = {"peak": round(e["peak"], 1), "count": e["count"]}

    print("\n4. moments close together")
    for case, e in moments.items():
        played = ", ".join(f"{c}:{n}" for c, n in e["played"])
        verdict = "ok" if e["peak"] <= MOMENTS_CEILING_DB else "TOO LOUD"
        failed += verdict != "ok"
        print(f"   {case:14} peak {e['peak']:6.1f} (ceiling {MOMENTS_CEILING_DB})  started {played}  {verdict}")
        table["moments"][case] = {"peak": round(e["peak"], 1)}

    print(
        f"\n5. does it hide a shot, a groan or a warning, in a night ({fight_db:+.0f} dB)? (the reference's loudest"
        f" moment in its band, 10 ms for a shot and 50 ms for the rest, minus the cue's; gate {MASK_GATE_DB} dB)"
    )
    gate_rows = [name for name in refs if name in MUST_STAY or name.startswith("zombie_groan")]
    print(f"   {'':16} " + " ".join(f"{n[:14]:>14}" for n in gate_rows))
    for cue in SOUNDS:
        loudest = max(cues[cue], key=lambda v: v["peak"])
        cells = []
        for name in gate_rows:
            m = masking(loudest["seg"] * gain, refs[name], rate)
            ok = m["margin"] >= MASK_GATE_DB
            failed += not ok
            cells.append(f"{m['margin']:+6.1f}{'' if ok else ' FAIL'}".rjust(14))
            table["masking"][f"{cue}|{name}"] = round(m["margin"], 1)
        print(f"   {cue:16} " + " ".join(cells))
    print("   bands (Hz): " + ", ".join(f"{n}: {refs[n]['band'][0]:.0f}-{refs[n]['band'][1]:.0f}" for n in gate_rows))

    print(f"\n6. a cue started anywhere over a burst of an automatic weapon, in a night ({fight_db:+.0f} dB)")
    for burst in ("shot_m4a1", "shot_m249", "shot_smg"):
        if burst not in refs:
            continue
        for cue in ("challenge_done", "level_up", "tier_up"):
            loudest = max(cues[cue], key=lambda v: v["peak"])
            scaled = loudest["seg"] * gain
            r = over_burst(scaled, refs[burst]["seg"], rate)
            bands, best = audible_bands(scaled, refs[burst]["seg"], rate)
            verdicts = []
            if r["clipped"]:
                verdicts.append(f"CLIPS {r['clipped']} samples")
            if r["peak"] > CLIP_DB:
                verdicts.append("OVER -1 dBFS")
            if bands < AUDIBLE_BANDS:
                verdicts.append("NOT AUDIBLE")
            failed += len(verdicts)
            print(
                f"   {burst:10} + {cue:14} sum peak {r['peak']:6.1f}, {bands:2} bands stand out of the burst"
                f" (the most by {best:+5.1f} dB)  {'ok' if not verdicts else '; '.join(verdicts)}"
            )
            table["burst"][f"{burst}|{cue}"] = {"peak": round(r["peak"], 1), "bands": bands, "best_db": round(best, 1)}
    print(f"\n{'ALL GATES PASS' if failed == 0 else f'{failed} GATES FAILED'}")
    return failed, table


def plot(mix: np.ndarray, rate: int, log: Path, sheet: Path | None, chart: Path | None, fight_db: float) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rows = events(log)
    cues = measure_cues(mix, rate, rows)
    refs = measure_refs(mix, rate, rows)
    if sheet is not None:
        fig, axes = plt.subplots(2, 5, figsize=(17, 6.5), gridspec_kw={"height_ratios": [1, 2]})
        for i, cue in enumerate(SOUNDS):
            seg = max(cues[cue], key=lambda v: v["peak"])["seg"].sum(axis=0) / 2
            seg = seg[: int((SECONDS[cue] + 0.1) * rate)]
            t = np.arange(len(seg)) / rate
            axes[0][i].plot(t, seg, lw=0.4, color="#2c6fb0")
            axes[0][i].set_ylim(-0.4, 0.4)
            axes[0][i].set_title(f"{cue}", fontsize=9)
            axes[1][i].specgram(seg, NFFT=1024, Fs=rate, noverlap=900, cmap="magma", vmin=-130, vmax=-40)
            axes[1][i].set_yscale("symlog", linthresh=500)
            axes[1][i].set_ylim(100, 16000)
            axes[1][i].set_xlabel("s")
        axes[0][0].set_ylabel("Master mix")
        axes[1][0].set_ylabel("Hz")
        fig.suptitle("The progression sounds as the mix plays them (default settings), waveform and spectrogram")
        fig.tight_layout()
        fig.savefig(sheet, dpi=110)
        plt.close(fig)
    if chart is not None:
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
        names, peaks, lufs, colours = [], [], [], []
        for cue in SOUNDS:
            names.append(cue)
            peaks.append(float(np.mean([v["peak"] for v in cues[cue]])))
            lufs.append(float(np.mean([v["lufs_m"] for v in cues[cue]])))
            colours.append("#d9534f")
        for cue in SOUNDS:
            names.append(f"{cue} (night)")
            peaks.append(float(np.mean([v["peak"] for v in cues[cue]])) + fight_db)
            lufs.append(float(np.mean([v["lufs_m"] for v in cues[cue]])) + fight_db)
            colours.append("#eba3a1")
        for key in (
            "shot_pistol",
            "zombie_groan_6m",
            "zombie_groan_2m",
            "vox_boss_arrive_1",
            "step_own_asphalt",
            "shot_m4a1",
        ):
            names.append(key)
            peaks.append(refs[key]["peak"])
            lufs.append(refs[key]["lufs_m"])
            colours.append("#8aa4c8")
        x = np.arange(len(names))
        ax1.bar(x, np.array(peaks) + 60, bottom=-60, color=colours)
        ax2.bar(x, np.array(lufs) + 60, bottom=-60, color=colours)
        for ax, title in ((ax1, "peak, dBFS"), (ax2, "loudest 400 ms, LUFS-M (K-weighted)")):
            ax.set_xticks(x)
            ax.set_xticklabels(names, rotation=55, ha="right", fontsize=8)
            ax.set_title(title)
            ax.set_ylim(-45, 0)
            ax.grid(axis="y", alpha=0.3)
        fig.suptitle(
            "Progression cues (red: menu level, pink: in a night) against the night's sounds (blue), in the mix"
        )
        fig.tight_layout()
        fig.savefig(chart, dpi=110)
        plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    levels = sub.add_parser("levels")
    levels.add_argument("mix", type=Path)
    levels.add_argument("log", type=Path)
    levels.add_argument("--plot", type=Path, help="loudness chart (png)")
    levels.add_argument("--sheet", type=Path, help="waveform and spectrogram of each cue (png)")
    levels.add_argument("--json", type=Path)
    levels.add_argument("--fight-db", type=float, default=FIGHT_DB, help="the cues' trim in a night")
    levels.add_argument("--pin", type=Path, help="write the numbers the game's test pins")
    args = parser.parse_args()
    mix, rate = read_stereo(args.mix)
    if mix.shape[0] == 1:
        mix = np.vstack([mix, mix])
    failed, table = report(mix, rate, args.log, args.fight_db)
    if args.json:
        args.json.write_text(json.dumps(table, indent=1, sort_keys=True), encoding="utf-8")
    if args.sheet or args.plot:
        plot(mix, rate, args.log, args.sheet, args.plot, args.fight_db)
    if args.pin:
        pin(args.pin, table)
    sys.exit(1 if failed else 0)


def pin(path: Path, table: dict) -> None:
    """The numbers `test_progress_sounds.gd` holds the sounds to."""
    doc = {
        "_what": "written by tools/audio/progress_levels.py --pin; see docs/research/menu-sfx.md, 'The progression sounds'",
        "gates": {
            "clip_db": CLIP_DB,
            "moments_ceiling_db": MOMENTS_CEILING_DB,
            "mask_gate_db": MASK_GATE_DB,
            "audible_bands": AUDIBLE_BANDS,
            "audible_over_db": AUDIBLE_OVER_DB,
        },
        "fight_db": table["fight_db"],
        "cues": table["cues"],
        "worst_mask_margin_db": round(min(table["masking"].values()), 1),
        "worst_burst_peak_db": round(max(v["peak"] for v in table["burst"].values()), 1),
        "stacks": table["stacks"],
        "moments": table["moments"],
    }
    path.write_text(json.dumps(doc, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
