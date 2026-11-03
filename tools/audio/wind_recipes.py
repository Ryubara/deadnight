"""The drive-in's wind as recipes (issue #782): a quiet steady base, gusts that each have their own length, rise and
fall and colour, and a few incidental details (a loose sign, a rattling sheet, a flapping tarp).

Same rules as `recipes.py`: a recipe takes a seeded numpy Generator and returns float samples, nothing is sampled or
taken from anywhere. The base is a loop built circularly like the night's other beds (`night_recipes.py`); the gusts
and the details are one-shots, which the game plays at random times and levels (`WindSounds`), so the wind is a
base plus events, never one long loop. `generate.py` renders `REGISTRY`; how the shape was chosen and what it
sounds like against the other beds is `docs/research/wind.md`.
"""

from __future__ import annotations

from dataclasses import dataclass

import dsp
import numpy as np
from limiter import limit_crest
from night_recipes import _creak, _ring_lowpass, _ring_noise, _slow
from recipes import Entry, _jv, _metal_click

BASE_SECONDS = 30.0
# How far the loudest 400 ms of a gust may stand over its body: the gusts are noise, and a loud variant must not
# be a peaky one, so every file of a kind has the same crest and the catalog's one trim fits them all.
GUST_CREST_DB = 9.0


@dataclass(frozen=True)
class GustShape:
    """One gust file: its length, where in it the peak falls, how bright the peak gets, and the extras."""

    seconds: float
    rise: float  # the share of the length before the peak (0.3 is a quick push and a slow fade)
    peak_hz: float  # the low-pass cutoff at the peak; it sits at `FLOOR_HZ` in the lulls on either side
    whistle: bool = False
    double: bool = False  # a second, weaker push after the first


GUST_FLOOR_HZ = 130.0

GUSTS: list[GustShape] = [
    GustShape(3.6, 0.45, 520),  # a short puff
    GustShape(5.2, 0.30, 900),  # a quick push and a slow fade
    GustShape(7.5, 0.55, 650),  # a slow swell
    GustShape(9.8, 0.50, 420),  # long and dark: a moan
    GustShape(6.4, 0.38, 1100),  # brighter, more air in it
    GustShape(11.5, 0.62, 560, double=True),  # long, pushes twice
    GustShape(4.4, 0.70, 780),  # builds and drops off suddenly
    GustShape(8.6, 0.35, 1400, whistle=True),  # the rare one that sings a little through the wires
]


def _lowpass2(x: np.ndarray, cutoff: np.ndarray) -> np.ndarray:
    """A 24 dB per octave low-pass whose cutoff moves (two second-order sections one after the other)."""
    return dsp.filt(dsp.filt(x, "low", cutoff), "low", cutoff)


def _bump(n: int, rise: float) -> np.ndarray:
    """0 to 1 to 0 over `n` samples with the peak at `rise` of the way: a raised-cosine each side, so it begins and
    ends at silence without a corner."""
    u = np.linspace(0.0, 1.0, n)
    up = np.sin(np.clip(u / rise, 0.0, 1.0) * np.pi / 2) ** 2
    down = np.sin(np.clip((1.0 - u) / (1.0 - rise), 0.0, 1.0) * np.pi / 2) ** 2
    return np.where(u < rise, up, down)


def wind_gust(rng: np.random.Generator, shape: GustShape) -> np.ndarray:
    """A gust crossing the lot: a swell of air whose colour opens with the strength (the low-pass rises from
    `GUST_FLOOR_HZ` to `peak_hz` and back), a heavy body under it, a slow turbulence on the level, and sometimes a
    second push or a thin whistle that speaks only near the top."""
    n = dsp.samples(shape.seconds)
    env = _bump(n, shape.rise)
    if shape.double:
        second = 0.55 * _bump(n, 0.5)
        shifted = np.roll(second, int(n * 0.28))
        shifted[: int(n * 0.28)] = 0.0
        env = np.maximum(env, shifted)
    turbulence = dsp.filt(rng.normal(0, 1, n), "low", 1.6)
    turbulence = turbulence / (np.abs(turbulence).max() + 1e-9)
    env = env * (1.0 + 0.22 * turbulence)
    env = np.clip(env, 0.0, None)

    air = rng.normal(0, 1, n)
    cutoff = GUST_FLOOR_HZ + (shape.peak_hz - GUST_FLOOR_HZ) * np.clip(env, 0.0, 1.0) ** 0.9
    airy = _lowpass2(air, cutoff)
    body = dsp.filt(rng.normal(0, 1, n), "low", 110)
    # The body is the weight of the wind, so it follows the level more gently than the air does.
    mix = airy * env * 0.9 + body * env**0.6 * 1.6
    if shape.whistle:
        centre = 940.0 + 140.0 * dsp.filt(rng.normal(0, 1, n), "low", 0.7) / 0.35
        centre = np.clip(centre, 700.0, 1300.0)
        thin = dsp.filt(rng.normal(0, 1, n), "band", centre, 70.0)
        mix = mix + thin * env**4 * 5.0
    mix = dsp.filt(mix, "high", 28)  # nothing below what a laptop speaker can carry
    return dsp.fade(limit_crest(mix, GUST_CREST_DB), 0.05, 0.1)


def wind_base(rng: np.random.Generator) -> np.ndarray:
    """The air that is always moving over an empty lot: a low pressure under a dull breath, level to within a couple
    of dB, so it is felt rather than heard. It loops every 30 s; nothing in it is an event."""
    pressure = _ring_lowpass(_ring_noise(rng, BASE_SECONDS, 30, 500, -4.0), 320)
    breath = _ring_lowpass(_ring_noise(rng, BASE_SECONDS, 300, 2600, -8.0), 1200)
    swell = 0.8 + 0.2 * _slow(rng, BASE_SECONDS, 0.05)
    breathing = 0.4 + 0.6 * _slow(rng, BASE_SECONDS, 0.09)
    return (pressure * 0.8 + breath * breathing * 0.25) * swell


# ---- the incidental details ---------------------------------------------------------------------------------------


def wind_creak(rng: np.random.Generator) -> np.ndarray:
    """A sign swinging on a rusted hinge, a long way off: a stick-slip creak that rises and falls with the push,
    dulled by the distance."""
    seconds = float(rng.uniform(1.2, 2.2))
    lo, hi = _jv(rng, 150, 0.2), _jv(rng, 260, 0.2)
    swing = _creak(rng, seconds, lo, hi) * _bump(dsp.samples(seconds), float(rng.uniform(0.35, 0.6)))
    return dsp.fade(dsp.filt(swing, "low", 1900), 0.04, 0.12)


def wind_rattle(rng: np.random.Generator) -> np.ndarray:
    """A loose sheet of tin on the snack bar's roof lifting and dropping in a gust: irregular dull clanks, thickest
    in the middle."""
    seconds = float(rng.uniform(1.6, 2.6))
    n = dsp.samples(seconds)
    mix = np.zeros(n)
    base = _jv(rng, 420, 0.25)
    for _ in range(int(rng.integers(7, 15))):
        at = seconds * float(np.clip(rng.normal(0.5, 0.22), 0.04, 0.9))
        click = dsp.filt(_metal_click(rng, base * rng.uniform(0.8, 1.5), ring=0.05), "low", 2400)
        mix = dsp.place(mix, click, at, float(rng.uniform(0.25, 1.0)))
    return dsp.fade(mix[:n], 0.01, 0.12)


def wind_flap(rng: np.random.Generator) -> np.ndarray:
    """A tarp over a stack of crates, snapping in the gusts: slack whumps of cloth, each a dull noise burst, quick
    at first and slowing as the gust drops."""
    seconds = float(rng.uniform(1.8, 3.0))
    n = dsp.samples(seconds)
    mix = np.zeros(n)
    at = 0.0
    gap = float(rng.uniform(0.09, 0.13))
    while at < seconds - 0.2:
        m = dsp.samples(0.18)
        burst = dsp.filt(dsp.white(rng, 0.18), "low", _jv(rng, 520, 0.2)) * dsp.decay(m, 0.05)
        fall = 1.0 - 0.6 * at / seconds
        mix = dsp.place(mix, burst, at, fall * float(rng.uniform(0.5, 1.0)))
        at += gap * float(rng.uniform(0.8, 1.3))
        gap *= 1.12
    return dsp.fade(mix[:n], 0.01, 0.15)


# ---- registry -----------------------------------------------------------------------------------------------------


def wind_gust_file(rng: np.random.Generator, variant: int) -> np.ndarray:
    """Gust file `variant` (1 to 8): `generate.py` hands a recipe that asks for it the variant number, and the shapes
    are the table `GUSTS`."""
    return wind_gust(rng, GUSTS[variant - 1])


REGISTRY: list[Entry] = [
    Entry("ambience", "wind_base", 1, wind_base, -3.0, loop=True),
    Entry("ambience", "wind_gust", len(GUSTS), wind_gust_file, -3.0),
    Entry("ambience", "wind_creak", 3, wind_creak, -3.0),
    Entry("ambience", "wind_rattle", 3, wind_rattle, -3.0),
    Entry("ambience", "wind_flap", 2, wind_flap, -3.0),
]
