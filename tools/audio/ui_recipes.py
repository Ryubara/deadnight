"""The menu's sounds, as recipes (#894; same rules as `recipes.py`: seeded, synthesised, nothing sampled).

The menu is a drive-in's box office and projection booth, and every sound is an object of that room: a marquee bulb
(hover, focus), a relay (a slider step, a select), a ticket punch (a press), a ticket torn along its perforation (a
commit), a slide projector's advance (a tab), a rocker switch (a toggle), a shutter that will not open (a refusal),
and the neon sign lighting a letter at a time. The design and the levels are `docs/research/menu-sfx.md`.

Every file is normalised to -6 dBFS and the levels are the trims in `core/audio/banks/ui.tres`, so the files of one
sound differ only in shape. The variants of a sound differ by a few percent in every pitch and time; the rest is the
engine's random pitch.
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from recipes import Entry

# The neon sign's ignition (`NeonSign`): the first letter lights at `IGNITE_START`, a new one every `IGNITE_GAP`, each
# catching for `IGNITE_STUTTER`; nine letters.
SIGN_START = 0.25
SIGN_GAP = 0.16
SIGN_STUTTER = 0.5
SIGN_LETTERS = 9


def _j(rng: np.random.Generator, centre: float, spread: float = 0.06) -> float:
    return centre * (1.0 + rng.uniform(-spread, spread))


def _partials(freq: float, ratios: list[float], gains: list[float], n: int, ring: float) -> np.ndarray:
    """A few damped sines at (inharmonic) ratios of `freq`: small struck metal."""
    out = np.zeros(n)
    for ratio, gain in zip(ratios, gains, strict=True):
        out += gain * dsp.sine(freq * ratio, n) * dsp.decay(n, ring / (0.6 + 0.4 * ratio))
    return out


def _snap(rng: np.random.Generator, seconds: float, lo: float, hi: float, ring: float) -> np.ndarray:
    """A band of noise that stops at once: paper, or the edge of a ticket in the punch."""
    n = dsp.samples(seconds)
    return dsp.filt(dsp.white(rng, seconds), "band", (lo + hi) / 2, hi - lo) * dsp.decay(n, ring)


def _thump(freq_from: float, freq_to: float, seconds: float, ring: float) -> np.ndarray:
    n = dsp.samples(seconds)
    return dsp.sine(np.linspace(freq_from, freq_to, n)) * dsp.decay(n, ring)


# ---- hints: a bulb --------------------------------------------------------------------------------------------


def ui_hover(rng: np.random.Generator) -> np.ndarray:
    """A marquee bulb's tick: a glassy ring a few milliseconds long over a click of air. The quietest sound."""
    n = dsp.samples(0.05)
    f = _j(rng, 2500, 0.08)
    ring = _partials(f, [1.0, 2.76], [1.0, 0.35], n, 0.05)
    click = _snap(rng, 0.05, 3500, 6500, 0.008)
    return dsp.fade(ring * 0.8 + click * 0.9, 0.0008, 0.012)


def ui_focus(rng: np.random.Generator) -> np.ndarray:
    """The same bulb a little warmer and longer: a key or a pad moved on purpose."""
    n = dsp.samples(0.07)
    f = _j(rng, 1750, 0.08)
    ring = _partials(f, [1.0, 2.41], [1.0, 0.3], n, 0.07)
    body = _thump(_j(rng, 420, 0.1), 300, 0.07, 0.05)
    return dsp.fade(ring * 0.75 + body * 0.35 + _snap(rng, 0.07, 2800, 5500, 0.004) * 0.6, 0.001, 0.015)


def ui_tick(rng: np.random.Generator) -> np.ndarray:
    """A projector sprocket's tooth: the slider's step. Shorter than a hover, a little duller."""
    n = dsp.samples(0.03)
    f = _j(rng, 2100, 0.08)
    ring = _partials(f, [1.0, 1.9], [1.0, 0.4], n, 0.03)
    return dsp.fade(ring * 0.9 + _snap(rng, 0.03, 1800, 4200, 0.003) * 0.8, 0.0006, 0.008)


# ---- presses: a ticket punch ----------------------------------------------------------------------------------


def _punch(rng: np.random.Generator, body: float, ring: float, seconds: float, bright: float) -> np.ndarray:
    n = dsp.samples(seconds)
    thump = _thump(_j(rng, body * 1.5, 0.04), body, seconds, seconds * 0.9)
    metal = _partials(_j(rng, ring, 0.05), [1.0, 1.58, 2.31], [1.0, 0.6, 0.35], n, 0.08)
    paper = _snap(rng, seconds, 3200, 7200, 0.015)
    return thump * 0.9 + metal * 0.5 * bright + paper * 0.7 * bright


def ui_press(rng: np.random.Generator) -> np.ndarray:
    """A ticket punch: a short thump, the metal of the punch and a snap of paper."""
    return dsp.fade(_punch(rng, 165, 1900, 0.16, 1.0), 0.001, 0.02)


def ui_back(rng: np.random.Generator) -> np.ndarray:
    """The punch's pair: lower and softer on top, so a step back sounds like a step back."""
    return dsp.fade(_punch(rng, 118, 1350, 0.17, 0.6), 0.001, 0.03)


def ui_confirm(rng: np.random.Generator) -> np.ndarray:
    """A ticket torn along its perforation (a rip of fourteen teeth), then the punch, then a soft marquee chord."""
    mix = None
    n_rip = dsp.samples(0.12)
    centre = np.linspace(1300, 4200, n_rip)
    rip = dsp.filt(dsp.white(rng, 0.12), "band", centre, centre * 0.9)
    teeth = 0.55 + 0.45 * np.sin(np.linspace(0, 14 * 2 * np.pi, n_rip)) ** 2
    rip = rip * teeth * np.sin(np.linspace(0.15, np.pi * 0.85, n_rip)) ** 0.7
    mix = dsp.place(mix, dsp.fade(rip, 0.002, 0.006), 0.0, 2.2)
    mix = dsp.place(mix, dsp.fade(_punch(rng, 150, 1750, 0.17, 1.0), 0.001, 0.02), 0.115, 1.0)
    # The chord: a major third, struck fast and left to fade, under the punch.
    n = dsp.samples(0.5)
    root = _j(rng, 392.0, 0.01)
    chord = dsp.sine(root, n) + 0.8 * dsp.sine(root * 1.26, n) + 0.3 * dsp.sine(root * 2.0, n)
    chord = chord * dsp.attack_decay(n, 0.006, 0.3)
    mix = dsp.place(mix, dsp.fade(chord, 0.004, 0.05), 0.125, 0.22)
    return mix


# ---- moves: a slide, a select, a rocker -------------------------------------------------------------------------


def ui_tab(rng: np.random.Generator) -> np.ndarray:
    """A slide projector advancing: the latch, then the carriage dropping home (ka-chunk)."""
    mix = None
    n = dsp.samples(0.05)
    latch = _partials(_j(rng, 1150, 0.05), [1.0, 1.58, 2.31], [1.0, 0.6, 0.3], n, 0.045)
    latch = latch + _snap(rng, 0.05, 2500, 6500, 0.004) * 0.9
    mix = dsp.place(mix, dsp.fade(latch, 0.0006, 0.01), 0.0, 0.8)
    chunk = _thump(_j(rng, 190, 0.05), 85, 0.14, 0.1) + _snap(rng, 0.14, 400, 1400, 0.04) * 0.5
    mix = dsp.place(mix, dsp.fade(chunk, 0.001, 0.025), _j(rng, 0.07, 0.08), 1.0)
    return mix


def ui_select(rng: np.random.Generator) -> np.ndarray:
    """One soft clack of a relay: a chip, a choice, one step of a selector."""
    n = dsp.samples(0.1)
    clack = _partials(_j(rng, 1250, 0.06), [1.0, 1.9], [1.0, 0.45], n, 0.05)
    clack = clack + _thump(_j(rng, 240, 0.08), 160, 0.1, 0.07) * 0.7 + _snap(rng, 0.1, 2200, 5200, 0.005) * 0.6
    return dsp.fade(clack, 0.001, 0.02)


def _rocker(rng: np.random.Generator, up: bool) -> np.ndarray:
    n = dsp.samples(0.12)
    body, ring = (190, 2300) if up else (125, 1500)
    thump = _thump(_j(rng, body * 1.3, 0.05), body, 0.12, 0.08)
    click = _partials(_j(rng, ring, 0.05), [1.0, 1.58], [1.0, 0.5], n, 0.04) + _snap(rng, 0.12, 3000, 6000, 0.004) * 0.6
    sweep_n = dsp.samples(0.018)
    sweep = dsp.sine(np.linspace(1700, 2700, sweep_n) if up else np.linspace(2200, 1300, sweep_n)) * dsp.decay(
        sweep_n, 0.012
    )
    return dsp.fade(thump * 0.8 + click * 0.8 + np.pad(sweep, (0, n - sweep_n)) * 0.3, 0.001, 0.02)


def ui_toggle_on(rng: np.random.Generator) -> np.ndarray:
    """A rocker switch thrown up: higher and brighter."""
    return _rocker(rng, True)


def ui_toggle_off(rng: np.random.Generator) -> np.ndarray:
    """The same switch thrown down: lower and duller."""
    return _rocker(rng, False)


# ---- a refusal: a shutter that will not open --------------------------------------------------------------------


def ui_deny(rng: np.random.Generator) -> np.ndarray:
    """A dull thud and a short low buzz, a shutter on a booth: a press on something that is not there yet."""
    n = dsp.samples(0.16)
    thud = _thump(_j(rng, 120, 0.05), 62, 0.16, 0.13)
    buzz = dsp.filt(dsp.saw(_j(rng, 68, 0.04), n), "low", 520) * (
        0.55 + 0.45 * np.sin(2 * np.pi * 52 * np.arange(n) / SAMPLE_RATE)
    )
    buzz = buzz * dsp.decay(n, 0.15)
    return dsp.fade(thud + buzz * 0.45 + _snap(rng, 0.16, 500, 1600, 0.01) * 0.3, 0.001, 0.03)


# ---- a moment: the sign lights -------------------------------------------------------------------------------


def ui_sign_on(rng: np.random.Generator) -> np.ndarray:
    """The neon sign lighting, to the sign's own timing: a relay clunk, then a buzz that swells with a tick for every
    letter that catches, and falls away to nothing as the last tube holds."""
    seconds = SIGN_START + SIGN_GAP * SIGN_LETTERS + SIGN_STUTTER + 0.55
    n = dsp.samples(seconds)
    t = np.arange(n) / SAMPLE_RATE
    mix = np.zeros(n)
    clunk = _thump(95, 55, 0.2, 0.08) + _partials(1100, [1.0, 1.58, 2.31], [1.0, 0.5, 0.3], dsp.samples(0.2), 0.03)
    mix = dsp.place(mix, dsp.fade(clunk, 0.001, 0.04), SIGN_START - 0.06, 0.5)
    # The buzz: mains harmonics, louder with every letter, a little ragged where a tube is catching.
    level = np.zeros(n)
    for i in range(SIGN_LETTERS):
        start = SIGN_START + SIGN_GAP * i
        level += (t >= start) * (0.5 / SIGN_LETTERS) * np.minimum((t - start) / 0.05, 1.0)
    fall_from = SIGN_START + SIGN_GAP * (SIGN_LETTERS - 1) + SIGN_STUTTER
    level = level * np.where(t > fall_from, np.exp(-6.9 * (t - fall_from) / 0.55), 1.0)
    hum = sum(dsp.sine(120.0 * k, n) / k for k in (1, 2, 3, 5)) * 0.4
    grit = dsp.filt(dsp.white(rng, seconds), "band", 2400, 1800)
    catching = (rng.random(n // 441 + 1)[np.arange(n) // 441] < 0.7).astype(float)
    mix += (hum * 0.6 + grit * 0.35 * catching) * level * 1.3
    for i in range(SIGN_LETTERS):
        tick = _partials(_j(rng, 2400, 0.08), [1.0, 2.76], [1.0, 0.4], dsp.samples(0.03), 0.01)
        tick = tick + _snap(rng, 0.03, 3000, 6500, 0.004) * 0.8
        mix = dsp.place(mix, dsp.fade(tick, 0.0006, 0.008), SIGN_START + SIGN_GAP * i, 0.55)
    return dsp.fade(mix[:n], 0.001, 0.15)


# Every file is normalised to -6 dBFS; the trims are in the bank.
FILE_PEAK = -6.0

REGISTRY: list[Entry] = [
    Entry("ui", "hover", 4, ui_hover, FILE_PEAK),
    Entry("ui", "focus", 4, ui_focus, FILE_PEAK),
    Entry("ui", "tick", 3, ui_tick, FILE_PEAK),
    Entry("ui", "press", 3, ui_press, FILE_PEAK),
    Entry("ui", "back", 3, ui_back, FILE_PEAK),
    Entry("ui", "confirm", 2, ui_confirm, FILE_PEAK),
    Entry("ui", "tab", 3, ui_tab, FILE_PEAK),
    Entry("ui", "select", 3, ui_select, FILE_PEAK),
    Entry("ui", "toggle_on", 2, ui_toggle_on, FILE_PEAK),
    Entry("ui", "toggle_off", 2, ui_toggle_off, FILE_PEAK),
    Entry("ui", "refuse", 2, ui_deny, FILE_PEAK),
    Entry("ui", "sign_on", 1, ui_sign_on, FILE_PEAK),
]
