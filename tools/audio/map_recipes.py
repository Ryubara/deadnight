"""The second map's sounds as recipes (issue #657): the depot's room tone, the wind through its broken roof, the
cold yard seen through the windows (wind in bare trees, two fires, the power lines, a fence rattling), a pile of
rubble and furniture dragged off a stair, and feet on wood.

Same rules as `recipes.py`: a recipe takes a seeded numpy Generator and returns float samples, nothing is sampled or
taken from anywhere. The loops are built circularly like the night's beds (`night_recipes.py`): every event that runs
past the end wraps to the start, every filter is applied in the frequency domain and every tone has a whole number of
cycles in the loop, so the last sample is followed by the first without a click. `generate.py` renders `REGISTRY`.
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from limiter import limit_crest
from night_recipes import _crack, _creak, _ring_lowpass, _ring_noise, _slow, _wrap_add
from recipes import Entry, _jv, _metal_click, _thud

ROOM_SECONDS = 20.0
ROOF_SECONDS = 20.0
WIND_SECONDS = 24.0
FIRE_SECONDS = 12.0
WIRE_SECONDS = 12.0


def _cycles(freq: float, seconds: float) -> float:
    """`freq` moved to the nearest whole number of cycles in a loop of `seconds`, so a tone loops without a click."""
    return max(1, round(freq * seconds)) / seconds


def _tone(freq: float, seconds: float) -> np.ndarray:
    n = dsp.samples(seconds)
    return np.sin(2 * np.pi * _cycles(freq, seconds) * np.arange(n) / SAMPLE_RATE)


# ---- the depot's room tone --------------------------------------------------------------------------------------


def room_tone(rng: np.random.Generator) -> np.ndarray:
    """A shut building at night: the air in a big stone room (a low, slow pressure), a faint mains hum from a
    transformer in the next wall, a dull band of draught, and now and then a pipe ticking as it cools, a drip and
    old timber settling. Nothing in it is ever above a murmur: it is felt when it stops."""
    n = dsp.samples(ROOM_SECONDS)
    pressure = _ring_lowpass(_ring_noise(rng, ROOM_SECONDS, 25, 220, -4.0), 160) * (
        0.7 + 0.3 * _slow(rng, ROOM_SECONDS, 0.1)
    )
    hum = sum(g * _tone(60.0 * k, ROOM_SECONDS) for k, g in ((1, 0.05), (2, 0.09), (3, 0.03), (4, 0.015)))
    hum = hum * (0.8 + 0.2 * _slow(rng, ROOM_SECONDS, 0.07))
    draught = _ring_lowpass(_ring_noise(rng, ROOM_SECONDS, 250, 1800, -7.0), 900) * (
        0.25 + 0.75 * _slow(rng, ROOM_SECONDS, 0.18)
    )
    mix = pressure * 0.55 + hum + draught * 0.16
    for _ in range(4):  # a pipe ticking as it cools: a dull metal tick, a little ring
        tick = _metal_click(rng, rng.uniform(380, 640), ring=0.03)
        tick = dsp.filt(tick, "low", 2200) * 0.5
        _wrap_add(mix, tick, rng.uniform(0, ROOM_SECONDS), rng.uniform(0.05, 0.1))
    for _ in range(2):  # a drip into standing water somewhere
        m = dsp.samples(0.25)
        f = rng.uniform(700, 1100)
        plink = dsp.sine(np.linspace(f * 0.8, f * 1.5, m)) * dsp.decay(m, 0.06)
        _wrap_add(mix, plink, rng.uniform(0, ROOM_SECONDS), 0.035)
    _wrap_add(mix, _creak(rng, 0.9, 70, 120), rng.uniform(2, ROOM_SECONDS - 3), 0.04)  # timber settling
    return mix[:n]


def roof_wind(rng: np.random.Generator) -> np.ndarray:
    """Wind coming through the broken roof: gusts that swell a low moan and a dull rush, with a thin whistle where
    it pours through the hole that rises with the gust."""
    n = dsp.samples(ROOF_SECONDS)
    gust = _slow(rng, ROOF_SECONDS, 0.16)
    gust = np.clip((gust - 0.15) * 1.3, 0.0, 1.0)
    moan = _ring_lowpass(_ring_noise(rng, ROOF_SECONDS, 60, 420, -3.0), 300)
    rush = _ring_lowpass(_ring_noise(rng, ROOF_SECONDS, 350, 2600, -6.0), 1500)
    whistle = sum(g * _tone(hz, ROOF_SECONDS) for hz, g in ((612.0, 0.5), (684.0, 0.8), (760.0, 0.4)))
    # The whistle comes and goes faster than the gusts, sharpened so it speaks only at their peaks.
    voice = gust**3 * (0.6 + 0.4 * _slow(rng, ROOF_SECONDS, 0.5))
    out = moan * (0.25 + 0.75 * gust) * 0.55 + rush * gust * 0.28 + whistle * voice * 0.05
    return out[:n]


# ---- the yard, seen through the windows -------------------------------------------------------------------------


def backdrop_wind(rng: np.random.Generator) -> np.ndarray:
    """Wind in bare trees on a cold night: a low swell, a long hiss of twigs that rises and falls with the gusts, and
    a branch creaking now and then. Open air: no whistle, nothing in a room's range."""
    gust = np.clip((_slow(rng, WIND_SECONDS, 0.11) - 0.1) * 1.2, 0.0, 1.0)
    swell = _ring_lowpass(_ring_noise(rng, WIND_SECONDS, 30, 260, -4.0), 200)
    twigs = _ring_lowpass(_ring_noise(rng, WIND_SECONDS, 700, 5200, -5.0), 3200)
    mix = swell * (0.35 + 0.65 * gust) * 0.55 + twigs * (gust**1.6) * 0.3
    for _ in range(3):
        _wrap_add(
            mix,
            _creak(rng, rng.uniform(0.7, 1.2), rng.uniform(210, 320), rng.uniform(380, 520)),
            rng.uniform(0, WIND_SECONDS),
            0.05,
        )
    return mix


def backdrop_fire(rng: np.random.Generator) -> np.ndarray:
    """A burning wreck or a barrel, a long way off: a low draw of flame, a soft hiss and the pops and crackle of
    wood and fuel, more of them when it flares."""
    flare = _slow(rng, FIRE_SECONDS, 0.35)
    draw = _ring_lowpass(_ring_noise(rng, FIRE_SECONDS, 40, 380, -3.0), 260) * (0.5 + 0.5 * flare)
    hiss = _ring_lowpass(_ring_noise(rng, FIRE_SECONDS, 2500, 9000, 0.0), 8000) * (0.3 + 0.7 * flare) * 0.1
    mix = draw * 0.5 + hiss
    for _ in range(round(FIRE_SECONDS * 22)):
        at = rng.uniform(0, FIRE_SECONDS)
        weight = 0.35 + 0.65 * flare[int(at * SAMPLE_RATE) % len(flare)]
        if rng.uniform() > weight:
            continue
        m = dsp.samples(rng.uniform(0.004, 0.02))
        pop = dsp.filt(dsp.white(rng, m / SAMPLE_RATE), "band", rng.uniform(1200, 5200), 3000) * dsp.decay(
            m, m / SAMPLE_RATE * 0.5
        )
        _wrap_add(mix, pop, at, rng.uniform(0.05, 0.6) ** 1.4)
    for _ in range(4):  # a bigger knock of settling wood
        _wrap_add(mix, _thud(rng, rng.uniform(110, 190), 0.07), rng.uniform(0, FIRE_SECONDS), 0.3)
    return mix


def backdrop_wire(rng: np.random.Generator) -> np.ndarray:
    """Power lines on a cold night: a mains hum with its harmonics, the wind singing across the wire (a thin warble
    that comes and goes) and a few ticks of corona."""
    sway = 0.75 + 0.25 * _slow(rng, WIRE_SECONDS, 0.2)
    hum = (
        sum(
            g * _tone(60.0 * k, WIRE_SECONDS)
            for k, g in ((1, 0.25), (2, 1.0), (3, 0.35), (4, 0.4), (5, 0.12), (7, 0.07))
        )
        * sway
    )
    gust = np.clip((_slow(rng, WIRE_SECONDS, 0.25) - 0.3) * 1.6, 0.0, 1.0)
    n = dsp.samples(WIRE_SECONDS)
    t = np.arange(n) / SAMPLE_RATE
    # The wire sings at a pitch that wobbles a little; a whole number of wobbles in the loop keeps it seamless.
    f0 = _cycles(430.0, WIRE_SECONDS)
    # Integral of f0 * (1 + 0.012 sin(2 pi 3 t / T)): after one loop the phase is a whole number of cycles.
    depth = 0.012 * WIRE_SECONDS / (2 * np.pi * 3)
    phase = 2 * np.pi * f0 * (t - depth * (np.cos(2 * np.pi * 3 * t / WIRE_SECONDS) - 1.0))
    sing = np.sin(phase) * gust**2 * 0.35
    mix = hum * 0.3 + sing
    for _ in range(round(WIRE_SECONDS * 2.5)):
        m = dsp.samples(0.006)
        spit = dsp.filt(dsp.white(rng, 0.006), "band", rng.uniform(2500, 6000), 3000) * dsp.decay(m, 0.002)
        _wrap_add(mix, spit, rng.uniform(0, WIRE_SECONDS), rng.uniform(0.1, 0.35))
    return mix


def yard_rattle(rng: np.random.Generator) -> np.ndarray:
    """A wire fence shaking in a gust: a cluster of tiny metal rings, many at first and thinning out, over a low
    rattle of loose posts."""
    length = _jv(rng, 1.7, 0.2)
    n = dsp.samples(length)
    mix = np.zeros(n)
    rate = rng.uniform(26, 40)
    t = 0.0
    while t < length - 0.15:
        ring = _metal_click(rng, rng.uniform(900, 2600), ring=0.02)
        ring = dsp.filt(ring, "high", 700)
        fall = np.exp(-t / (length * 0.38))
        mix = dsp.place(mix, ring, t, fall * rng.uniform(0.2, 1.0))[:n]
        t += rng.exponential(1.0 / (rate * (0.35 + 0.65 * fall)))
    knock = _ring_lowpass(dsp.white(rng, length), 500, 2) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.25
    return dsp.fade(mix + knock, 0.01, 0.2)


# ---- pieces -----------------------------------------------------------------------------------------------------

# The blocker's highest sample over its loudest 400 ms, in dB (`limiter.limit_crest`, #762).
DEBRIS_CLEAR_CREST_DB = 11.0


def _drag(rng: np.random.Generator, seconds: float) -> np.ndarray:
    """Furniture dragged over a stone floor: band noise whose pitch wanders and which grabs and lets go."""
    n = dsp.samples(seconds)
    centre = np.linspace(rng.uniform(240, 340), rng.uniform(420, 620), n)
    noise = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 1.1)
    grab = np.clip(0.55 + 0.9 * dsp.filt(dsp.white(rng, seconds), "low", 14) / 0.12, 0.0, 1.0)
    body = dsp.filt(dsp.white(rng, seconds), "low", 160) * 0.8
    return dsp.fade((noise * 1.3 + body) * grab * np.sin(np.linspace(0, np.pi, n)) ** 0.6, 0.03, 0.12)


def debris_clear(rng: np.random.Generator) -> np.ndarray:
    """A blocker pulled off a stair: a table dragged back over the floor, planks knocked and snapped off the pile,
    and a slide of rubble that tumbles, clatters and settles."""
    mix = dsp.place(None, _drag(rng, _jv(rng, 0.75, 0.15)), 0.0, 0.6)
    for k in range(int(rng.integers(3, 5))):  # planks knocked loose
        at = 0.25 + k * rng.uniform(0.16, 0.26)
        mix = dsp.place(mix, _thud(rng, rng.uniform(150, 260), 0.1), at, 0.75)
        mix = dsp.place(
            mix, _crack(rng, rng.uniform(380, 640), 0.7)[: dsp.samples(0.2)], at + 0.01, rng.uniform(0.4, 0.8)
        )
    slide_at = 0.85
    length = 1.2
    m = dsp.samples(length)
    slide = dsp.filt(dsp.white(rng, length), "band", np.linspace(2200, 900, m), 2600) * np.exp(
        -np.arange(m) / (0.45 * SAMPLE_RATE)
    )
    mix = dsp.place(mix, dsp.fade(slide, 0.05, 0.1), slide_at, 0.35)
    for _ in range(int(rng.integers(22, 34))):  # stones and brick tumbling
        at = slide_at + abs(rng.normal(0.0, 0.32))
        f = rng.uniform(600, 3800)
        stone = dsp.filt(dsp.white(rng, 0.03), "band", f, f * 0.7) * dsp.decay(
            dsp.samples(0.03), rng.uniform(0.004, 0.012)
        )
        mix = dsp.place(mix, stone, at, rng.uniform(0.15, 0.9) ** 1.3)
    for k in range(int(rng.integers(2, 4))):  # a heavy piece hitting the stair
        mix = dsp.place(
            mix, _thud(rng, rng.uniform(65, 110), 0.22), slide_at + 0.05 + 0.18 * k + rng.uniform(0, 0.1), 0.9
        )
    return dsp.fade(limit_crest(mix, DEBRIS_CLEAR_CREST_DB), 0.004, 0.25)


def _wood_step(rng: np.random.Generator, bright: bool) -> np.ndarray:
    """A foot on a plank over a hollow: a heel knock, the plank's body ringing, a tiny creak now and then. The
    local player's feet (not `bright`) have no hiss and nothing above 3.2 kHz, like the other own steps."""
    n = dsp.samples(0.26)
    f = _jv(rng, 125, 0.16)
    knock = dsp.sine(np.linspace(f * 1.6, f, n)) * dsp.decay(n, 0.045)
    body_hz = _jv(rng, 310, 0.14)
    body = dsp.sine(np.linspace(body_hz * 1.05, body_hz, n)) * dsp.decay(n, 0.11) * 0.42
    body += dsp.sine(body_hz * 1.9, n) * dsp.decay(n, 0.06) * 0.15  # the hollow under the plank
    toe = dsp.place(np.zeros(n), knock[: dsp.samples(0.1)], rng.uniform(0.04, 0.07), rng.uniform(0.3, 0.5))[:n]
    mix = knock + body + toe
    if bright:
        mix = (
            mix
            + dsp.filt(dsp.white(rng, 0.26), "band", _jv(rng, 1500, 0.2), 1500) * dsp.attack_decay(n, 0.002, 0.03) * 0.3
        )
        mix = mix + dsp.filt(dsp.white(rng, 0.26), "high", 3500) * dsp.decay(n, 0.008) * 0.1
    if rng.uniform() < 0.35:
        creak = _creak(rng, 0.14, rng.uniform(260, 340), rng.uniform(380, 520))
        mix = dsp.place(mix, creak, 0.05, 0.05 if bright else 0.03)[:n]
    if not bright:
        mix = dsp.filt(mix, "low", 3200)
    return dsp.fade(mix, 0.002, 0.06)


def step_wood(rng: np.random.Generator) -> np.ndarray:
    return _wood_step(rng, True)


def step_own_wood(rng: np.random.Generator) -> np.ndarray:
    return _wood_step(rng, False)


# ---- registry ---------------------------------------------------------------------------------------------------

REGISTRY: list[Entry] = [
    Entry("ambience", "room_tone", 1, room_tone, -3.0, loop=True),
    Entry("ambience", "roof_wind", 1, roof_wind, -3.0, loop=True),
    Entry("ambience", "yard_wind", 1, backdrop_wind, -3.0, loop=True),
    Entry("ambience", "yard_fire", 1, backdrop_fire, -3.0, loop=True),
    Entry("ambience", "yard_wire", 1, backdrop_wire, -3.0, loop=True),
    Entry("ambience", "yard_rattle", 3, yard_rattle, -6.0),
    Entry("world", "debris_clear", 3, debris_clear, -6.0),
    Entry("steps", "wood", 8, step_wood, -6.0),
    Entry("steps", "own_wood", 8, step_own_wood, -6.0),
]
