"""The main menu's music and wind (#979), as recipes: three loops of different lengths that play together.

Same rules as `recipes.py`: a recipe takes a seeded numpy Generator and returns float samples, nothing is sampled or
taken from anywhere, so the output is original and can be committed (no licence entry).

Why three loops and not one long piece (`docs/research/menu-music.md`): a person who leaves the menu open hears it for
minutes. One loop, however long, is a tune that returns; loops of unequal lengths that never agree (Eno's *Music for
Airports* is made of tape loops of differing lengths) return as a new combination each time. The three lengths here
share no factor, so the whole repeats only after about 4.7 days; each loop is a whole cycle and every sound in it is
periodic in its own length, so the seam is exact.

- `menu_pad` (76 s): a steady D and A held under a slow walk through four chords of D dorian, each fading into the next.
- `menu_bells` (113 s): single soft notes of D dorian a long way apart, with a delay and a long tail; silence is most of it.
- `menu_wind` (47 s): air over an empty lot in the mids (a small speaker keeps it), swelling and falling.

Every note is in D dorian over the pedal D and A, so any note the bells play fits whichever chord the pad is on, at
whatever offset the loops meet. Nothing is in the 1.5 to 8 kHz band the menu's hints live in, apart from the faint
upper partials of a bell: the loops are dark on purpose (`tools/audio/menu_speakers.py` checks it).
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from night_recipes import _ring_lowpass, _ring_noise, _slow, _wrap_add
from recipes import Entry

PAD_SECONDS = 76.0
BELLS_SECONDS = 113.0
WIND_SECONDS = 47.0

# D dorian over a D of 146.83 Hz, every note a just ratio of it: each note and each of its harmonics then sits on the
# root's own harmonic series, so no two voices beat except the pairs detuned on purpose (twelve-tone tuning put a third
# harmonic 0.5 Hz off a neighbour and the pad's level pulsed every two seconds).
ROOT = 146.83
D3, A3, D4 = ROOT, ROOT * 3 / 2, ROOT * 2
# The four chords' own voices over the held D and A; each is a set of scale tones, no two a semitone apart.
CHORDS: list[tuple[float, ...]] = [
    (ROOT * 16 / 9, ROOT * 12 / 5, ROOT * 3),  # C4 F4 A4: D minor seventh
    (ROOT * 4 / 3, ROOT * 5 / 3, ROOT * 9 / 4),  # G3 B3 E4: G sixth over the D
    (ROOT * 16 / 9, ROOT * 9 / 4, ROOT * 3),  # C4 E4 A4: A minor seventh
    (ROOT * 6 / 5, ROOT * 16 / 9, ROOT * 8 / 3),  # F3 C4 G4: F with its ninth
]
# The notes the bells choose from, low to high: D E F G A C, over two octaves, no B so the colour stays open.
BELL_NOTES = tuple(ROOT * r for r in (2, 9 / 4, 12 / 5, 8 / 3, 3, 32 / 9, 4, 9 / 2, 24 / 5, 16 / 3))


def _exact(hz: float, seconds: float) -> float:
    """The frequency nearest `hz` that completes a whole number of cycles in `seconds`: a sine of it ends where it began,
    so a loop of that length has no seam (the change is under a tenth of a cent)."""
    return round(hz * seconds) / seconds


def _periodic_lfo(seconds: float, cycles: int, phase: float, n: int) -> np.ndarray:
    return np.sin(2 * np.pi * cycles * np.arange(n) / n + phase)


# ---- the pad ----------------------------------------------------------------------------------------------------


def _voice(hz: float, seconds: float, n: int, side: int, rng: np.random.Generator) -> np.ndarray:
    """One held note: two sines a few cents apart (they beat slowly) with a soft second and third harmonic whose level
    drifts, so the note opens and darkens by itself. All of it is periodic in `seconds`."""
    t = np.arange(n) / SAMPLE_RATE
    out = np.zeros(n)
    detune = 1.0 + (0.0006 if side else -0.0006)
    for spread in (1.0, detune * (1.0 + 0.0004)):
        f = _exact(hz * spread, seconds)
        phase = rng.uniform(0, 2 * np.pi)
        wobble = 0.0025 * _periodic_lfo(seconds, int(rng.integers(3, 9)), rng.uniform(0, 2 * np.pi), n)
        carrier = 2 * np.pi * f * t + phase + wobble
        open_up = 0.5 + 0.5 * _periodic_lfo(seconds, int(rng.integers(2, 6)), rng.uniform(0, 2 * np.pi), n)
        out += (
            np.sin(carrier) + (0.35 + 0.3 * open_up) * np.sin(2 * carrier) + 0.15 * open_up * np.sin(3 * carrier)
        ) * 0.5
    return out


def menu_pad(rng: np.random.Generator) -> np.ndarray:
    """A held D and A under four chords that fade into each other, stereo. 76 s, 19 s a chord: the changes are slow
    enough to be felt and never heard as a change."""
    n = dsp.samples(PAD_SECONDS)
    phase = np.arange(n) / n
    channels = []
    for side in (0, 1):
        mix = np.zeros(n)
        # The pedal: the D and A, and the D an octave up, level all the way round.
        for hz, gain in ((D3, 0.6), (A3, 0.5), (D4, 0.45)):
            mix += gain * _voice(hz, PAD_SECONDS, n, side, rng)
        # Each chord swells and falls on a raised cosine as wide as the loop, centred on its quarter: the four always sum
        # to the same, so the walk is a drift and not a cut.
        for i, notes in enumerate(CHORDS):
            window = np.cos(np.pi * (((phase - i / len(CHORDS)) + 0.5) % 1.0 - 0.5)) ** 2
            for hz in notes:
                mix += 0.55 * window * _voice(hz, PAD_SECONDS, n, side, rng)
                mix += 0.2 * window * _voice(hz * 2, PAD_SECONDS, n, side, rng)  # the same note an octave up, thin
        channels.append(_ring_lowpass(mix, 1500, 2))
    left, right = channels
    # A circular shift keeps the loop whole; 11 ms widens the pair a little.
    right = np.roll(right, dsp.samples(0.011))
    return np.stack([left, right])


# ---- the bells --------------------------------------------------------------------------------------------------


def _bell(rng: np.random.Generator, hz: float) -> np.ndarray:
    """A soft struck tone: a sine with a quiet octave and a quieter 3.01x partial (a little out of tune, so it is glass
    and not an organ), 40 ms to rise and several seconds to fall."""
    seconds = float(rng.uniform(4.5, 7.0))
    n = dsp.samples(seconds)
    t = np.arange(n) / SAMPLE_RATE
    ring = np.exp(-t / (seconds * 0.22))
    body = np.sin(2 * np.pi * hz * t) + 0.28 * np.sin(2 * np.pi * 2.0 * hz * t) * ring
    body += 0.05 * np.sin(2 * np.pi * 3.01 * hz * t) * ring**2
    rise = np.minimum(t / 0.04, 1.0)
    return body * rise * np.exp(-t / (seconds * 0.35))


def _plan_bells(rng: np.random.Generator) -> list[tuple[float, float, float, float]]:
    """(second, hz, level, pan) for each note: gaps of 5 to 14 s (silence is most of the loop), a walk of one to three
    steps along the scale, and now and then a second note a fifth or an octave under it a moment later."""
    notes: list[tuple[float, float, float, float]] = []
    at = float(rng.uniform(3.0, 6.0))
    index = int(rng.integers(2, 6))
    while at < BELLS_SECONDS - 4.0:
        step = int(rng.choice([-3, -2, -1, 1, 2, 3]))
        index = int(np.clip(index + step, 0, len(BELL_NOTES) - 1))
        level = float(rng.uniform(0.45, 1.0))
        pan = float(rng.uniform(-0.6, 0.6))
        notes.append((at, BELL_NOTES[index], level, pan))
        if rng.random() < 0.3 and index >= 3:
            notes.append((at + float(rng.uniform(0.9, 1.6)), BELL_NOTES[index - 3], 0.6 * level, -pan))
        at += float(rng.uniform(5.0, 14.0))
    return notes


def _ring_tail(rng: np.random.Generator, x: np.ndarray, seconds: float, wet: float) -> np.ndarray:
    """A reverb that wraps: circular convolution with a decaying, darkening noise (the FFT does it in the loop)."""
    n = len(x)
    m = dsp.samples(seconds)
    ir = np.zeros(n)
    t = np.arange(m) / SAMPLE_RATE
    ir[:m] = rng.normal(0, 1, m) * np.exp(-t / (seconds * 0.3))
    ir = _ring_lowpass(ir, 1800, 2)
    ir /= np.sqrt((ir**2).sum()) + 1e-12
    wet_part = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir), n)
    return x + wet * wet_part


def menu_bells(rng: np.random.Generator) -> np.ndarray:
    """Sparse soft notes with a dark delay and a long tail, stereo. 113 s with a note every 5 to 14 s."""
    n = dsp.samples(BELLS_SECONDS)
    left, right = np.zeros(n), np.zeros(n)
    for at, hz, level, pan in _plan_bells(rng):
        tone = _bell(rng, hz)
        _wrap_add(left, tone, at, level * (1.0 - pan) / 2)
        _wrap_add(right, tone, at, level * (1.0 + pan) / 2)
    out = []
    for side, x in enumerate((left, right)):
        echoed = x + 0.38 * np.roll(_ring_lowpass(x, 900, 2), dsp.samples(0.62 + 0.07 * side))
        echoed += 0.2 * np.roll(_ring_lowpass(x, 700, 2), dsp.samples(1.31 - 0.09 * side))
        out.append(_ring_lowpass(_ring_tail(rng, echoed, 6.0, 1.6), 2600, 2))
    return np.stack(out)


# ---- the wind ---------------------------------------------------------------------------------------------------


def menu_wind(rng: np.random.Generator) -> np.ndarray:
    """Air over an empty lot, in the mids a small speaker keeps: a dull breath that swells and falls over about ten
    seconds, with a thin ring of air in the structure near 500 Hz. 47 s, mono, and no gust: a gust is an event, and the
    menu holds still."""
    breath = _ring_lowpass(_ring_noise(rng, WIND_SECONDS, 160, 1500, -5.0), 1100, 2)
    ring = _ring_noise(rng, WIND_SECONDS, 380, 660, 0.0)
    swell = 0.25 + 0.75 * _slow(rng, WIND_SECONDS, 0.07) ** 1.5
    ring_swell = 0.2 + 0.8 * _slow(rng, WIND_SECONDS, 0.05)
    return breath * swell + 0.35 * ring * ring_swell * swell


REGISTRY: list[Entry] = [
    Entry("music", "menu_pad", 1, menu_pad, -3.0, loop=True),
    Entry("music", "menu_bells", 1, menu_bells, -3.0, loop=True),
    Entry("ambience", "menu_wind", 1, menu_wind, -3.0, loop=True),
]
