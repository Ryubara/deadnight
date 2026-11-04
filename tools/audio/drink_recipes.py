"""The perk drink's sounds (Deadnight #912), synthesised like the rest: the cap popped off, the drink, the empty
bottle thrown away. Played by the drink clip's events on the drinker's body (`PerkBottle`), from the `perks` bank
(deferred: made after the loading bar, #864). Seeded from each sound's name by `generate.py`.
"""

from __future__ import annotations

import dsp
import numpy as np
from recipes import Entry


def _ring(rng: np.random.Generator, partials: list[float], seconds: float, spread: float = 0.03) -> np.ndarray:
    """Glass struck: inharmonic sines, each a little off its nominal pitch, the high ones dying first."""
    n = dsp.samples(seconds)
    out = np.zeros(n)
    for i, hz in enumerate(partials):
        f = hz * (1.0 + rng.uniform(-spread, spread))
        out += dsp.sine(f, n) * dsp.attack_decay(n, 0.0005, seconds / (1.0 + 0.6 * i)) / (1.0 + 0.4 * i)
    return out


def _click(rng: np.random.Generator, hz: float, seconds: float = 0.02) -> np.ndarray:
    """A short bright tick: a burst of noise through a band at `hz`."""
    n = dsp.samples(seconds)
    return dsp.filt(dsp.white(rng, seconds), "band", hz, hz * 0.5) * dsp.attack_decay(n, 0.0003, seconds)


def drink_open(rng: np.random.Generator) -> np.ndarray:
    """The crown cap levered off: a metal snap, the cap's small ring, and the gas rushing out into a fizz that
    settles into bubbles."""
    seconds = 0.9
    n = dsp.samples(seconds)
    hiss = dsp.filt(dsp.white(rng, seconds), "high", 3500) * dsp.curve([(0, 0), (0.02, 1.0), (0.15, 0.45), (1, 0)], n)
    mix = dsp.place(None, _click(rng, 2600, 0.03), 0.0, 1.0)
    mix = dsp.place(mix, _ring(rng, [3100.0, 5200.0, 7900.0], 0.12), 0.004, 0.25)
    mix = dsp.place(mix, hiss, 0.01, 0.55)[:n]
    # Bubbles: tiny rising chirps, thinning out.
    for at in np.sort(rng.uniform(0.08, 0.85, 26)):
        m = dsp.samples(0.025)
        hz = rng.uniform(1800, 3600)
        chirp = dsp.sine(np.linspace(hz, hz * 1.4, m), m) * dsp.attack_decay(m, 0.001, 0.025)
        mix = dsp.place(mix, chirp, float(at), 0.12 * (1.0 - at))[:n]
    return dsp.fade(mix, 0.0005, 0.05)


def _gulp(rng: np.random.Generator) -> np.ndarray:
    """One swallow: a wet, low gulp (a falling resonance over a soft knock) and the drink's glug back in the neck."""
    seconds = 0.22
    n = dsp.samples(seconds)
    hz = np.linspace(rng.uniform(380, 440), rng.uniform(170, 210), n)
    tone = dsp.sine(hz, n) * dsp.attack_decay(n, 0.008, 0.16)
    wet = dsp.filt(dsp.white(rng, seconds), "band", np.linspace(900, 450, n), 260) * dsp.attack_decay(n, 0.004, 0.1)
    knock = dsp.filt(dsp.white(rng, 0.03), "low", 300) * dsp.attack_decay(dsp.samples(0.03), 0.001, 0.03)
    mix = dsp.place(None, tone, 0.0, 0.8)
    mix = dsp.place(mix, wet, 0.0, 0.6)
    mix = dsp.place(mix, knock, 0.0, 0.7)
    glug = dsp.sine(np.linspace(260, 520, dsp.samples(0.06))) * dsp.attack_decay(dsp.samples(0.06), 0.002, 0.06)
    return dsp.place(mix, glug, 0.12, 0.35)[:n]


def drink_gulp(rng: np.random.Generator) -> np.ndarray:
    """The drink: three swallows over the clip's 0.85 s at the mouth, the last with a breath out after it."""
    mix = None
    for at in (0.0, 0.27 + rng.uniform(-0.02, 0.02), 0.55 + rng.uniform(-0.02, 0.02)):
        mix = dsp.place(mix, _gulp(rng), at, rng.uniform(0.85, 1.0))
    breath = dsp.filt(dsp.white(rng, 0.3), "band", 1400, 1600) * dsp.curve([(0, 0), (0.2, 1), (1, 0)], dsp.samples(0.3))
    mix = dsp.place(mix, breath, 0.8, 0.25)
    return dsp.fade(mix, 0.002, 0.06)


def drink_discard(rng: np.random.Generator) -> np.ndarray:
    """The empty bottle thrown away: a short swish off the hand, then 0.45 s later it lands on the asphalt, glass on
    stone (a hard tick and a bright ring), bounces once and rolls to a stop."""
    seconds = 0.18
    n = dsp.samples(seconds)
    swish = dsp.filt(dsp.white(rng, seconds), "band", np.linspace(1400, 2600, n), 900)
    mix = dsp.place(None, swish * dsp.curve([(0, 0), (0.4, 1), (1, 0)], n), 0.0, 0.3)
    land = 0.45
    mix = dsp.place(mix, _click(rng, 4200, 0.015), land, 1.0)
    mix = dsp.place(mix, _ring(rng, [2350.0, 3880.0, 5710.0, 7420.0], 0.35), land, 0.55)
    mix = dsp.place(mix, _click(rng, 3600, 0.012), land + 0.16, 0.5)
    mix = dsp.place(mix, _ring(rng, [2350.0, 3880.0, 5710.0], 0.2), land + 0.16, 0.25)
    roll_s = 0.5
    m = dsp.samples(roll_s)
    roll = dsp.filt(dsp.white(rng, roll_s), "band", 2800, 2200) * (0.5 + 0.5 * dsp.sine(17.0, m) ** 2)
    roll *= dsp.curve([(0, 0.35), (1, 0)], m)
    mix = dsp.place(mix, roll, land + 0.24, 0.3)
    return dsp.fade(mix, 0.002, 0.08)


REGISTRY: list[Entry] = [
    Entry("perks", "drink_open", 2, drink_open, -4.0),
    Entry("perks", "drink_gulp", 3, drink_gulp, -5.0),
    Entry("perks", "drink_discard", 2, drink_discard, -4.0),
]
