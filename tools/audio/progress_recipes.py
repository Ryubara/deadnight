"""The progression sounds, as recipes (#1062; same rules as `recipes.py`: seeded, synthesised, nothing sampled).

A challenge done is a record scratch, a level up a snare roll into a short brass call, a tier up the same made bigger,
an unlock the menu's ticket punch with one soft bell, and a card, emblem or frame earned an unlock with a paper rustle.
All five are made here from noise, sines and sawtooth stacks; no recording and no sound of any game is used, and the
scratch is a style reference only. The design is `docs/design/progression.md#popups-motion-and-sound`, the levels and
the checks are `docs/research/menu-sfx.md#the-progression-sounds-1062`.

Every file is normalised to -6 dBFS and the levels are the trims in `core/audio/banks/ui_progress.tres`.
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from recipes import Entry
from ui_recipes import _j, _partials, _punch, _snap

# The brass's root: G3. The call is the bugle's own steps of the harmonic series (2:3:4 above it), the chords are
# whole-number ratios of the same root, so every partial of every voice sits on the root's harmonic series.
ROOT = 196.0

# The lengths of the rows of the issue (#1062), in seconds.
SCRATCH_S = 0.6
LEVEL_UP_S = 1.1
TIER_UP_S = 2.0
UNLOCK_S = 0.35
CARD_S = 0.5


def _to_length(x: np.ndarray, seconds: float, fade_s: float = 0.06) -> np.ndarray:
    """The sound as long as its row says: cut (with a fade) or padded with silence."""
    n = dsp.samples(seconds)
    x = x[:n] if len(x) >= n else np.pad(x, (0, n - len(x)))
    return dsp.fade(x, 0.001, fade_s)


# ---- the snare roll -------------------------------------------------------------------------------------------


def _snare(rng: np.random.Generator, level: float, seconds: float = 0.14) -> np.ndarray:
    """One stroke of a snare: a drum head's short body, the wires' hiss, a click of the stick."""
    n = dsp.samples(seconds)
    head = dsp.sine(np.linspace(_j(rng, 215, 0.04), 165, n)) * dsp.decay(n, 0.07)
    wires = dsp.filt(dsp.white(rng, seconds), "band", 4200, 5200) * dsp.decay(n, 0.1)
    stick = dsp.filt(dsp.white(rng, seconds), "band", 2200, 1800) * dsp.decay(n, 0.012)
    return (head * 0.55 + wires * 0.8 + stick * 0.5) * level


def _roll(rng: np.random.Generator, seconds: float, first_gap: float, last_gap: float, start: float, end: float):
    """Strokes that come faster and louder: a crescendo roll of `seconds`, the gap between strokes falling from
    `first_gap` to `last_gap`, the level from `start` to `end`."""
    mix = None
    t = 0.0
    while t < seconds:
        k = t / seconds
        level = start + (end - start) * k**1.3
        stroke = _snare(rng, level * rng.uniform(0.85, 1.0))
        mix = dsp.place(mix, stroke, t, 1.0)
        t += (first_gap + (last_gap - first_gap) * k) * rng.uniform(0.93, 1.07)
    return mix


# ---- brass ------------------------------------------------------------------------------------------------------


def _brass(
    rng: np.random.Generator, freq: float, seconds: float, attack: float = 0.07, tail: float = 0.25
) -> np.ndarray:
    """One brass voice: a stack of three slightly detuned sawtooths and a pulse, a slow attack, a low-pass that
    opens as the note blooms, a little vibrato once it is held, a breath of noise at the lip."""
    n = dsp.samples(seconds + tail)
    t = np.arange(n) / SAMPLE_RATE
    vibrato = 1.0 + 0.0035 * np.sin(2 * np.pi * _j(rng, 5.4, 0.08) * t) * np.clip((t - 0.15) / 0.3, 0.0, 1.0)
    stack = sum(dsp.saw(freq * vibrato * (1.0 + cents / 1200.0), n) for cents in (-7.0, 0.0, 7.0)) / 3.0
    stack = stack + 0.35 * dsp.pulse(freq * vibrato, 0.3, n)
    cutoff = freq * (2.2 + 7.0 * np.clip(t / (attack * 2.2 + 0.05), 0.0, 1.0) ** 0.7)
    voice = dsp.filt(stack, "low", cutoff)
    env = np.ones(n)
    a = max(1, int(attack * SAMPLE_RATE))
    env[:a] = np.linspace(0.0, 1.0, a) ** 1.6
    hold = int(seconds * SAMPLE_RATE)
    env[hold:] = np.exp(-6.9 * (t[hold:] - seconds) / tail)
    # The note swells a little into its middle, as a player's breath does.
    env *= 1.0 + 0.12 * np.sin(np.pi * np.clip(t / max(seconds, 1e-3), 0.0, 1.0))
    lip_n = dsp.samples(0.05)
    lip = dsp.filt(dsp.white(rng, 0.05), "band", freq * 3.0, freq * 2.0) * dsp.decay(lip_n, 0.03)
    return np.pad(lip, (0, n - lip_n)) * 0.18 + voice * env


def _far_wall(x: np.ndarray, wet: float = 0.22) -> np.ndarray:
    """The slap-back of a far wall, as the night's other sounds have it."""
    return dsp.echo(x, 0.16, wet, dark=3200.0)


def _thump(freq_from: float, freq_to: float, seconds: float, ring: float) -> np.ndarray:
    n = dsp.samples(seconds)
    return dsp.sine(np.linspace(freq_from, freq_to, n)) * dsp.decay(n, ring)


def _drum(rng: np.random.Generator, freq: float, level: float) -> np.ndarray:
    """A low drum hit (a floor tom or timpani): the head's pitch falls as it rings, a soft beater click."""
    n = dsp.samples(0.7)
    body = _thump(_j(rng, freq * 1.5, 0.03), freq, 0.7, 0.55)
    skin = _thump(_j(rng, freq * 2.3, 0.03), freq * 1.6, 0.4, 0.2) * 0.35
    beater = dsp.filt(dsp.white(rng, 0.03), "band", 900, 900) * dsp.decay(dsp.samples(0.03), 0.012)
    skin = np.pad(skin, (0, n - len(skin)))
    return (body + skin + np.pad(beater, (0, n - len(beater))) * 0.4) * level


# ---- the five sounds ------------------------------------------------------------------------------------------


def _fanfare(rng: np.random.Generator, big: bool) -> np.ndarray:
    """A snare roll into a short brass call. The big one (a tier) rolls longer, with a low drum hit under the call,
    and ends on a fuller chord that rises a fourth and holds."""
    if big:
        call_at = 0.78
        mix = _roll(rng, 0.76, 0.08, 0.03, 0.18, 0.85)
        mix = dsp.place(mix, _drum(rng, 62, 0.8), 0.0, 0.3)
        mix = dsp.place(mix, _drum(rng, 58, 1.0), call_at - 0.02, 0.6)
        # A stab of the triad, then the chord a fourth up (4/3) held to the end.
        for k, ratio in enumerate([1.0, 1.5, 2.0, 2.5, 3.0]):
            gain = 0.5 if k < 3 else 0.32
            mix = dsp.place(mix, _brass(rng, ROOT * ratio, 0.28, 0.05, 0.1), call_at, gain)
        for k, ratio in enumerate([4 / 3, 2.0, 8 / 3, 10 / 3, 4.0]):
            gain = 0.5 if k < 3 else 0.32
            mix = dsp.place(mix, _brass(rng, ROOT * ratio, 0.55, 0.09, 0.4), call_at + 0.3, gain)
        return _to_length(_far_wall(dsp.fade(mix, 0.002, 0.04), 0.2), TIER_UP_S, 0.2)
    call_at = 0.4
    mix = _roll(rng, 0.42, 0.07, 0.032, 0.25, 0.85)
    # The call: the bugle's second, third and fourth of the series (2:3:4), two short and one held, over a fifth.
    for ratio, at, seconds in [(2.0, 0.0, 0.1), (3.0, 0.12, 0.1), (4.0, 0.24, 0.32)]:
        mix = dsp.place(mix, _brass(rng, ROOT * ratio, seconds, 0.045, 0.2), call_at + at, 0.6)
    mix = dsp.place(mix, _brass(rng, ROOT * 2.0, 0.32, 0.08, 0.25), call_at + 0.24, 0.3)
    mix = dsp.place(mix, _brass(rng, ROOT * 3.0, 0.32, 0.08, 0.25), call_at + 0.24, 0.26)
    mix = dsp.place(mix, _drum(rng, 70, 0.7), call_at - 0.01, 0.3)
    return _to_length(_far_wall(dsp.fade(mix, 0.002, 0.04), 0.16), LEVEL_UP_S, 0.12)


def level_up(rng: np.random.Generator) -> np.ndarray:
    return _fanfare(rng, big=False)


def tier_up(rng: np.random.Generator) -> np.ndarray:
    return _fanfare(rng, big=True)


def scratch(rng: np.random.Generator) -> np.ndarray:
    """A record scratch of our own making: a needle dragged over a groove under a hand. A platter's speed is the
    control: forward fast, back, forward again with a snap, then the platter let go to coast to a stop. A buzzy
    voiced source is read at that speed, so its pitch and loudness follow the hand (a platter that stops is silent),
    with the groove's hiss and a crackle of dust that rise and fall with it, and the thud of the needle landing."""
    seconds = 0.62
    n = dsp.samples(seconds)
    t = np.arange(n) / SAMPLE_RATE
    stretch = _j(rng, 1.0, 0.04)
    # The hand's speed over time (1 is the platter at rest speed; negative is backwards). Strokes, then the coast.
    points = [
        (0.0, 0.0),
        (0.02, 0.2),
        (0.07, 3.1),
        (0.12, 2.6),
        (0.15, -0.3),
        (0.19, -2.7),
        (0.235, -2.0),
        (0.265, 0.5),
        (0.30, 2.9),
        (0.34, 3.4),
        (0.40, 1.8),
        (0.62, 0.0),
    ]
    xs = np.array([p[0] for p in points]) * stretch
    speed = np.interp(t, xs, [p[1] for p in points])
    speed = dsp.filt(speed, "low", 120.0)
    rate = np.abs(speed)
    # The coast is a platter slowing: it falls faster than a line near the end.
    coast = t > 0.40 * stretch
    fall = np.clip((t - 0.40 * stretch) / (0.22 * stretch), 0.0, 1.0)
    rate = np.where(coast, rate * (1.0 - fall**1.6), rate)
    base = _j(rng, 150.0, 0.05)
    source = dsp.saw(base * np.maximum(rate, 0.02), n) + 0.5 * dsp.pulse(base * 1.5 * np.maximum(rate, 0.02), 0.25, n)
    # A voiced vowel: formants that ride with the speed (a sample played faster moves them up).
    shifted = np.maximum(rate, 0.25)
    vowel = (
        dsp.filt(source, "band", 700 * shifted, 450 * shifted)
        + 0.8 * dsp.filt(source, "band", 1450 * shifted, 700 * shifted)
        + 0.35 * dsp.filt(source, "band", 2900 * shifted, 1400 * shifted)
    )
    gate = np.clip(rate / 0.55, 0.0, 1.0) ** 0.9
    vowel = vowel * gate
    hiss = dsp.filt(dsp.white(rng, seconds), "band", 3800, 3400) * np.clip(rate / 2.5, 0.0, 1.0) ** 1.2 * 0.09
    dust = np.zeros(n)
    hits = rng.random(n) < (0.0012 + 0.0045 * np.clip(rate / 3.0, 0.0, 1.0))
    dust[hits] = rng.uniform(-1.0, 1.0, int(hits.sum()))
    dust = dsp.filt(dust, "band", 3500, 3000) * 2.0
    landing = _thump(_j(rng, 140, 0.05), 70, 0.12, 0.05) * 0.8
    landing[: dsp.samples(0.04)] += _snap(rng, 0.04, 800, 2400, 0.012) * 0.5
    vowel = vowel * (0.35 + 0.65 * np.clip(rate / 3.0, 0.0, 1.0))
    mix = dsp.drive(vowel * 0.9 + hiss + dust * 0.25, 1.3)
    mix = dsp.place(mix, landing, 0.0, 0.6)
    return _to_length(dsp.filt(mix, "high", 140.0), SCRATCH_S, 0.05)


def _bell(freq: float, seconds: float) -> np.ndarray:
    """One soft bell: a struck sine with the partials of a small cast bell, left to fade."""
    n = dsp.samples(seconds)
    return _partials(freq, [1.0, 2.0, 2.76, 5.4], [1.0, 0.35, 0.22, 0.07], n, seconds)


def unlock(rng: np.random.Generator) -> np.ndarray:
    """The ticket punch of the menu and one soft bell over it. The stack that climbs a pentatonic scale in the rules
    (`UiSounds`) shifts the whole sound, so the bell is the root of the scale: 880 Hz."""
    mix = dsp.fade(_punch(rng, 160, 1850, 0.14, 0.8), 0.001, 0.02)
    mix = dsp.place(None, mix, 0.0, 0.8)
    return _to_length(dsp.place(mix, _bell(_j(rng, 880.0, 0.003), 0.55), 0.045, 0.55), UNLOCK_S + 0.05, 0.08)


def card_earned(rng: np.random.Generator) -> np.ndarray:
    """An unlock with a rustle of paper: a card slid out of an envelope, then the punch and the bell."""
    n = dsp.samples(0.2)
    envelope = np.concatenate([np.linspace(0.0, 1.0, n // 3) ** 2, np.linspace(1.0, 0.0, n - n // 3) ** 1.5]) * (
        0.6 + 0.4 * np.sin(np.linspace(0, 11 * np.pi, n)) ** 2
    )
    rustle = dsp.filt(dsp.white(rng, 0.2), "band", 4300, 4800) * envelope
    rustle = rustle + _snap(rng, 0.2, 1600, 3200, 0.06) * 0.25 * envelope
    mix = dsp.place(None, dsp.fade(rustle, 0.004, 0.02), 0.0, 0.5)
    mix = dsp.place(mix, dsp.fade(_punch(rng, 160, 1850, 0.14, 0.8), 0.001, 0.02), 0.19, 0.75)
    return _to_length(dsp.place(mix, _bell(_j(rng, 880.0, 0.003), 0.55), 0.235, 0.5), CARD_S + 0.03, 0.08)


# Every file is normalised to -6 dBFS; the trims are in the bank.
FILE_PEAK = -6.0

REGISTRY: list[Entry] = [
    Entry("progress", "scratch", 2, scratch, FILE_PEAK),
    Entry("progress", "level_up", 2, level_up, FILE_PEAK),
    Entry("progress", "tier_up", 1, tier_up, FILE_PEAK),
    Entry("progress", "unlock", 3, unlock, FILE_PEAK),
    Entry("progress", "card_earned", 2, card_earned, FILE_PEAK),
]
