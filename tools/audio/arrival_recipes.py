"""The helicopter drop's sounds (Deadnight #1057), synthesised like the rest: a 1958 piston helicopter's rotor beat
and engine as one seamless loop (the cutscene moves it from far to over the player's head, so distance does the rest),
the rope run through gloved hands, and the boots landing. Seeded from each sound's name by `generate.py`.

The loop is built circularly (every flap wraps round the end, every tone is a whole number of cycles in the loop,
every filter runs in the frequency domain), so its last sample is followed by its first without a click.
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from night_recipes import _ring_lowpass, _ring_noise, _slow, _wrap_add
from recipes import Entry, _metal_click, _thud

HELI_SECONDS = 4.0
# A two-bladed rotor at 5 turns a second: ten beats a second, forty in the loop. The weight is kept above 55 Hz
# and the body in the 100 to 1500 Hz band, so a phone speaker still carries the beat.
FLAP_HZ = 10.0
ENGINE_HZ = 60.0  # 240 cycles in the loop
TAIL_HZ = 400.0  # 1600 cycles


def _flap(rng: np.random.Generator) -> np.ndarray:
    """One blade passing: a low thump (the pressure wave) with a short slap of mid noise and a trace of crack."""
    n = dsp.samples(0.11)
    thump = dsp.sine(np.linspace(rng.uniform(100, 112), 58, n), n) * dsp.attack_decay(n, 0.003, 0.07)
    m = dsp.samples(0.04)
    slap = dsp.filt(dsp.white(rng, 0.04), "band", rng.uniform(900, 1500), 1400) * dsp.attack_decay(m, 0.001, 0.016)
    crack = dsp.filt(dsp.white(rng, 0.012), "high", 3200) * dsp.decay(dsp.samples(0.012), 0.004)
    out = thump * 1.0
    out[:m] += slap * 1.1
    out[: len(crack)] += crack * 0.25
    return out


def heli_loop(rng: np.random.Generator) -> np.ndarray:
    n = dsp.samples(HELI_SECONDS)
    t = np.arange(n) / SAMPLE_RATE
    beats = round(HELI_SECONDS * FLAP_HZ)
    flaps = np.zeros(n)
    for k in range(beats):
        # The beat wanders a little (a rotor is never even) and swells and thins slowly.
        at = (k + rng.uniform(-0.05, 0.05)) / FLAP_HZ
        swell = 0.82 + 0.18 * np.cos(2 * np.pi * k / 20.0)
        _wrap_add(flaps, _flap(rng), at, swell * rng.uniform(0.9, 1.0))
    # The wash of the blades through the air, pulsing at the beat.
    wash = _ring_noise(rng, HELI_SECONDS, 220.0, 3200.0, -6.0)
    wash *= 0.5 + 0.5 * np.cos(2 * np.pi * FLAP_HZ * t - 0.4) ** 2
    # The engine: a low saw in whole cycles, a rumble under it, and the tail rotor's thin whine.
    saw = 2.0 * ((ENGINE_HZ * t) % 1.0) - 1.0
    engine = _ring_lowpass(saw, 700.0, 3) * (0.8 + 0.2 * _slow(rng, HELI_SECONDS, 0.5))
    rumble = _ring_noise(rng, HELI_SECONDS, 35.0, 170.0, 0.0)
    whine = np.sin(2 * np.pi * TAIL_HZ * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 30.0 * t)) * 0.05
    mix = flaps * 1.0 + wash * 0.55 + engine * 0.5 + rumble * 0.08 + whine
    return mix


def rope_slide(rng: np.random.Generator) -> np.ndarray:
    """A rope run through gloved hands: a long dry hiss that rises as the slide gathers speed and falls as the
    hands brake, with the hemp's small creaks in it."""
    seconds = 2.1
    n = dsp.samples(seconds)
    centre = np.linspace(1500.0, 2900.0, n)
    hiss = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.9)
    bumps = np.abs(0.65 + 0.35 * dsp.filt(dsp.white(rng, seconds), "low", 38))
    body = dsp.curve([(0, 0.0), (0.12, 0.6), (0.5, 1.0), (0.85, 0.7), (1, 0.0)], n)
    mix = hiss * bumps * body
    for at in np.sort(rng.uniform(0.1, 1.9, 7)):
        m = dsp.samples(0.07)
        hz = rng.uniform(380, 760)
        creak = dsp.sine(np.linspace(hz, hz * rng.uniform(0.8, 1.25), m), m) * dsp.attack_decay(m, 0.004, 0.06)
        mix = dsp.place(mix, creak, float(at), 0.08)[:n]
    return dsp.fade(mix, 0.02, 0.15)


def drop_land(rng: np.random.Generator) -> np.ndarray:
    """Boots on the lot after the drop: the heavy landing, the knees taking it, the pack's buckles, a puff of dust."""
    mix = dsp.place(None, _thud(rng, 78.0, 0.16), 0.0, 1.0)
    mix = dsp.place(
        mix, dsp.filt(dsp.white(rng, 0.09), "band", 1100, 1500) * dsp.decay(dsp.samples(0.09), 0.02), 0.0, 0.5
    )
    mix = dsp.place(mix, _thud(rng, 90.0, 0.1), 0.17, 0.55)
    for at, base in ((0.03, 2300.0), (0.09, 3100.0), (0.2, 2700.0)):
        mix = dsp.place(mix, _metal_click(rng, base, 0.03), at, 0.16)
    dust = dsp.filt(dsp.white(rng, 0.4), "band", 1800, 2600) * dsp.curve([(0, 0), (0.1, 1), (1, 0)], dsp.samples(0.4))
    mix = dsp.place(mix, dust, 0.02, 0.18)
    return dsp.fade(mix, 0.001, 0.08)


REGISTRY: list[Entry] = [
    Entry("arrival", "heli_loop", 1, heli_loop, -3.0, loop=True),
    Entry("arrival", "rope_slide", 1, rope_slide, -5.0),
    Entry("arrival", "drop_land", 1, drop_land, -4.0),
]
