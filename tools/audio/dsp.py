"""Small DSP toolbox for the Deadnight sounds: noise, envelopes, oscillators, filters, a room tail.

Everything is numpy/scipy on float64 arrays at SAMPLE_RATE, mono unless a function says otherwise, so a sound
is a few readable lines in `recipes.py`. No randomness lives here: callers pass a seeded Generator.
"""

from __future__ import annotations

import numpy as np
from scipy import signal

SAMPLE_RATE = 44100
BLOCK = 128  # samples per coefficient update when a filter cutoff sweeps


def samples(seconds: float) -> int:
    """Length in samples; rounded, so 0.7 s is always the same count whichever way it is computed."""
    return round(seconds * SAMPLE_RATE)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(samples(seconds)) / SAMPLE_RATE


def silence(seconds: float) -> np.ndarray:
    return np.zeros(samples(seconds))


def white(rng: np.random.Generator, seconds: float) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, samples(seconds))


# ---- envelopes -------------------------------------------------------------------------------------------------


def decay(n: int, seconds: float, shape: float = 1.0) -> np.ndarray:
    """Exponential decay that falls by 60 dB over `seconds` (shape > 1 sharpens the front)."""
    t = np.arange(n) / SAMPLE_RATE
    return np.exp(-6.9 * (t / max(seconds, 1e-4)) ** shape)


def attack_decay(n: int, attack: float, seconds: float) -> np.ndarray:
    env = decay(n, seconds)
    a = max(1, int(attack * SAMPLE_RATE))
    env[:a] *= np.linspace(0.0, 1.0, a) ** 2
    return env


def fade(x: np.ndarray, in_s: float = 0.002, out_s: float = 0.01) -> np.ndarray:
    """Short fades so a sound never clicks at its edges (a stereo array is faded per channel)."""
    if x.ndim == 2:
        return np.stack([fade(ch, in_s, out_s) for ch in x])
    x = x.copy()
    a, b = int(in_s * SAMPLE_RATE), int(out_s * SAMPLE_RATE)
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    return x


def curve(points: list[tuple[float, float]], n: int) -> np.ndarray:
    """Piecewise-linear control curve over n samples from (position 0..1, value) points."""
    xs, ys = zip(*points, strict=True)
    return np.interp(np.linspace(0.0, 1.0, n), xs, ys)


# ---- oscillators -----------------------------------------------------------------------------------------------


def phase_of(freq: np.ndarray) -> np.ndarray:
    return np.cumsum(freq) / SAMPLE_RATE


def sine(freq: float | np.ndarray, n: int | None = None) -> np.ndarray:
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)
    return np.sin(2 * np.pi * phase_of(f))


def saw(freq: float | np.ndarray, n: int | None = None) -> np.ndarray:
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)
    return 2.0 * (phase_of(f) % 1.0) - 1.0


def pulse(freq: float | np.ndarray, width: float, n: int | None = None) -> np.ndarray:
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)
    return np.where(phase_of(f) % 1.0 < width, 1.0, -1.0)


# ---- filters ---------------------------------------------------------------------------------------------------


def _design(kind: str, freq: float, width: float | None) -> np.ndarray:
    nyq = SAMPLE_RATE / 2
    freq = float(np.clip(freq, 20.0, nyq * 0.95))
    if kind in ("low", "high"):
        return signal.butter(2, freq / nyq, btype=kind, output="sos")
    bw = width if width is not None else freq * 0.5
    lo = float(np.clip(freq - bw / 2, 20.0, nyq * 0.9))
    hi = float(np.clip(freq + bw / 2, lo * 1.05, nyq * 0.97))
    return signal.butter(2, [lo / nyq, hi / nyq], btype="band", output="sos")


def filt(x: np.ndarray, kind: str, freq: float | np.ndarray, width: float | np.ndarray | None = None) -> np.ndarray:
    """Low/high/band-pass; `freq` (and `width` for band) may be arrays to sweep the cutoff over time."""
    if np.isscalar(freq) and (width is None or np.isscalar(width)):
        return signal.sosfilt(_design(kind, float(freq), width), x)
    freqs = np.broadcast_to(freq, x.shape)
    widths = None if width is None else np.broadcast_to(width, x.shape)
    out = np.empty_like(x)
    zi = None
    for start in range(0, len(x), BLOCK):
        sl = slice(start, min(start + BLOCK, len(x)))
        sos = _design(kind, freqs[sl.start], None if widths is None else widths[sl.start])
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[sl], zi = signal.sosfilt(sos, x[sl], zi=zi)
    return out


def formants(x: np.ndarray, centres: list[tuple[float, float, float]]) -> np.ndarray:
    """Parallel resonators: (frequency, bandwidth, gain) each; the sound of a mouth shape."""
    return sum(g * filt(x, "band", f, bw) for f, bw, g in centres)


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    """Soft clip; amount 1 is gentle, 8 is gritty."""
    return np.tanh(x * amount) / np.tanh(amount)


# ---- space -----------------------------------------------------------------------------------------------------


def room_tail(
    rng: np.random.Generator, x: np.ndarray, seconds: float, wet: float, dark: float = 6000.0, pre: float = 0.0
) -> np.ndarray:
    """Convolve with decaying, darkening noise: a cheap open-air reverb. Returns a longer array."""
    n = samples(seconds)
    ir = rng.normal(0, 1, n) * decay(n, seconds * 0.55)
    ir = filt(ir, "low", np.linspace(dark, dark * 0.25, n))
    ir[: int(pre * SAMPLE_RATE)] = 0
    ir /= np.abs(ir).max() + 1e-9
    tail = signal.fftconvolve(x, ir * 0.12)
    dry = np.pad(x, (0, len(tail) - len(x)))
    return dry + wet * tail


def echo(x: np.ndarray, delay: float, gain: float, dark: float = 2500.0) -> np.ndarray:
    """One slap-back from a far wall (the drive-in screen tower)."""
    d = int(delay * SAMPLE_RATE)
    out = np.pad(x, (0, d))
    out[d:] += gain * filt(x, "low", dark)
    return out


# ---- layout ----------------------------------------------------------------------------------------------------


def place(mix: np.ndarray | None, part: np.ndarray, at: float, gain: float = 1.0) -> np.ndarray:
    """Add `part` into `mix` starting `at` seconds, growing the mix as needed."""
    start = int(at * SAMPLE_RATE)
    size = start + len(part)
    mix = np.zeros(size) if mix is None else mix
    if len(mix) < size:
        mix = np.pad(mix, (0, size - len(mix)))
    mix[start : start + len(part)] += gain * part
    return mix


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.abs(x).max()
    return x if peak == 0 else x * (10 ** (peak_db / 20) / peak)


def trim_tail(x: np.ndarray, floor_db: float = -60.0) -> np.ndarray:
    """Drop the near-silent end so files are as short as the sound."""
    limit = np.abs(x).max() * 10 ** (floor_db / 20)
    loud = np.nonzero(np.abs(x) > limit)[0]
    return x if len(loud) == 0 else x[: loud[-1] + 1]
