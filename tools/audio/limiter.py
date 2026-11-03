"""A look-ahead peak limiter for the recipes (Deadnight #762).

A sharp sound (a board snapping, a door's bolt, rubble) has a crest factor of 20 to 25 dB: the file is normalised
to its crack, so the body under it is quiet. The web build ignores bus effects (`docs/godot/audio.md`), so the
limiting is done here, in the file, and the file is rendered once.

`limit_crest(x, crest_db)` holds the highest sample to `crest_db` over the loudest 400 ms of the sound. The gain
curve is smooth: the sample-by-sample gain a sample needs is cut to its minimum over a window and then averaged
over the same window, so the curve never rises into a peak and never steps, which is what keeps the Vorbis encoder
from overshooting the way it does on a flat top. `recipes.Entry` still normalises the result, so a recipe that
calls this returns a sound whose peak sits closer to its body.
"""

from __future__ import annotations

import numpy as np
from dsp import SAMPLE_RATE
from scipy.ndimage import minimum_filter1d, uniform_filter1d

LOOK_AHEAD = 0.002  # seconds the gain starts to fall before a peak, and the length it takes to come back
LOUD_WINDOW = 0.4  # the window the loudness is read over (EBU R128's momentary loudness)


def loudest_rms(x: np.ndarray, window: float = LOUD_WINDOW) -> float:
    """The root mean square of the loudest `window` seconds of `x` (mono or channels x samples)."""
    mono_power = (x**2).mean(axis=0) if x.ndim == 2 else x**2
    n = max(1, int(window * SAMPLE_RATE))
    if len(mono_power) <= n:
        return float(np.sqrt(mono_power.mean()))
    sums = np.convolve(mono_power, np.ones(n) / n, mode="valid")
    return float(np.sqrt(sums.max()))


def smooth_gain(need: np.ndarray, look_ahead: float = LOOK_AHEAD) -> np.ndarray:
    """The smooth gain (at most 1) that stays under `need` everywhere: its minimum over a window, then its average
    over the same window."""
    half = max(1, int(look_ahead * SAMPLE_RATE))
    low = minimum_filter1d(need, size=2 * half + 1, mode="nearest")
    return uniform_filter1d(low, size=2 * half + 1, mode="nearest")


def limit(x: np.ndarray, ceiling: float, look_ahead: float = LOOK_AHEAD) -> np.ndarray:
    """`x` with no sample over `ceiling` (linear), by a smooth gain; a stereo sound gets one gain for both channels."""
    peak = np.abs(x).max(axis=0) if x.ndim == 2 else np.abs(x)
    need = np.minimum(1.0, ceiling / np.maximum(peak, 1e-12))
    return x * smooth_gain(need, look_ahead)


def limit_crest(x: np.ndarray, crest_db: float, look_ahead: float = LOOK_AHEAD) -> np.ndarray:
    """`x` with its highest sample held `crest_db` over the loudest 400 ms (a crest factor of at most `crest_db`)."""
    ceiling = loudest_rms(x) * 10 ** (crest_db / 20)
    return limit(x, ceiling, look_ahead)
