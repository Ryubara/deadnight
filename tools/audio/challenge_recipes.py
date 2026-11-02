"""The challenge prompt's two cues, as recipes (same rules as `recipes.py`: seeded, synthesised, nothing sampled).

A ticket punch for a quarter mark: a dry, short clack with a paper click on top, quiet enough to sit under gunfire.
A finish adds a soft two-note chime after the punch, a fifth apart, rising. Neither uses a generated voice.
"""

from __future__ import annotations

import dsp
import numpy as np
from recipes import Entry, _clack, _jv


def _punch(rng: np.random.Generator) -> np.ndarray:
    """The ticket punch: a short damped thump and a dry click, nothing that rings."""
    return dsp.fade(_clack(rng, _jv(rng, 230, 0.03), 0.09), 0.001, 0.02)


def _bell(freq: float, seconds: float) -> np.ndarray:
    """A soft chime: a sine and a quiet octave-and-a-bit partial, struck fast and left to fade."""
    n = dsp.samples(seconds)
    tone = dsp.sine(freq, n) + 0.25 * dsp.sine(freq * 2.76, n) + 0.08 * dsp.sine(freq * 5.4, n)
    return tone * dsp.attack_decay(n, 0.004, seconds * 0.35)


def challenge_tick(rng: np.random.Generator) -> np.ndarray:
    return _punch(rng) * 0.9


def challenge_done(rng: np.random.Generator) -> np.ndarray:
    mix = dsp.place(None, _punch(rng), 0.0, 0.9)
    mix = dsp.place(mix, _bell(659.3, 0.55), 0.07, 0.38)
    mix = dsp.place(mix, _bell(987.8, 0.7), 0.2, 0.34)
    return dsp.fade(mix, 0.001, 0.08)


REGISTRY: list[Entry] = [
    Entry("ui", "challenge_tick", 1, challenge_tick, -12.0),
    Entry("ui", "challenge_done", 1, challenge_done, -10.0),
]
