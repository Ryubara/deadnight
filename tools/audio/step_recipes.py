"""The player's own footsteps: a soft sole on asphalt and on gravel.

Same rules as `recipes.py` (a seeded numpy Generator in, float samples out). These are for the local player's own
feet, which the game plays flat and very quietly (`SoundCatalog` `step_own_*`): a step you hear 2 to 3 times a second
for the whole night must not have anything in it that wears: no bright scuff, no hiss, no grit. So they are made of
a dull heel-and-toe thump and a low band of noise, nothing above 3.2 kHz, and every take differs in pitch, in the gap
between heel and toe and in its grains, so eight takes do not read as a loop. The other players' feet are the brighter
`step_asphalt` and `step_gravel` of `recipes.py`.
"""

from __future__ import annotations

import dsp
import numpy as np
from recipes import Entry, _jv

LOW_PASS_HZ = 3200  # nothing above this: the hiss is what makes a repeated step obnoxious


def _heel_toe(rng: np.random.Generator, f: float, toe_gain: float) -> np.ndarray:
    """A heel thump, then a smaller toe thump 35 to 60 ms later."""
    n = dsp.samples(0.12)
    heel = dsp.sine(np.linspace(f * 1.5, f, n)) * dsp.attack_decay(n, 0.003, 0.05)
    toe = dsp.sine(np.linspace(f * 1.8, f * 1.2, n)) * dsp.attack_decay(n, 0.003, 0.03)
    return dsp.place(heel, toe, rng.uniform(0.035, 0.06), toe_gain)[:n]


def step_own_asphalt(rng: np.random.Generator) -> np.ndarray:
    """A sole on tarmac: heel and toe thumps over a short, dull band of rubbing."""
    n = dsp.samples(0.16)
    thump = np.pad(_heel_toe(rng, _jv(rng, 135, 0.18), rng.uniform(0.35, 0.6)), (0, n - dsp.samples(0.12)))
    rub = dsp.filt(dsp.white(rng, 0.16), "band", _jv(rng, 850, 0.25), 900) * dsp.attack_decay(n, 0.006, 0.05)
    mix = thump + rng.uniform(0.7, 1.0) * rub
    return dsp.fade(dsp.filt(mix, "low", LOW_PASS_HZ), 0.002, 0.04)


def step_own_gravel(rng: np.random.Generator) -> np.ndarray:
    """A sole on gravel: a soft thump and a short, loose spray of dull grains (fewer and lower than the others')."""
    length = 0.24
    n = dsp.samples(length)
    mix = np.zeros(n)
    for _ in range(int(rng.integers(16, 28))):
        at = abs(rng.normal(0.0, 0.06))
        if at > length - 0.03:
            continue
        grain = dsp.filt(dsp.white(rng, 0.012), "band", rng.uniform(1000, 3000), 1500)
        grain = grain * dsp.decay(len(grain), rng.uniform(0.003, 0.008)) * rng.uniform(0.2, 1.0)
        mix = dsp.place(mix, grain, at)
    mix = mix[:n]
    thump = np.pad(_heel_toe(rng, _jv(rng, 150, 0.18), rng.uniform(0.3, 0.5)), (0, n - dsp.samples(0.12)))
    return dsp.fade(dsp.filt(1.0 * mix + 1.2 * thump, "low", LOW_PASS_HZ), 0.002, 0.05)


REGISTRY: list[Entry] = [
    Entry("steps", "own_asphalt", 8, step_own_asphalt, -6.0),
    Entry("steps", "own_gravel", 8, step_own_gravel, -6.0),
]
