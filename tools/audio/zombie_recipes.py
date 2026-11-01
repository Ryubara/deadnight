"""The dead's voices and footsteps, per type, as recipes: the alert snarl, the swing grunt, the runner's shriek, the
brute's heavy breath and low groan, the crawler's moan and drag, the headliner's roar and its growl before a blow, and
the shuffle, run and stomp of their feet.

Same rules as `recipes.py` (a seeded numpy Generator in, float samples out; everything synthesised: formant-filtered
sawtooth with jitter for the throat, shaped noise for breath, scrape and cloth). `generate.py` renders `REGISTRY`
together with the first file's. Timing notes the game relies on are in each docstring: the swing grunt and the growl peak
at a known time into the file, so the game can start them early enough to land on the blow.
"""

from __future__ import annotations

import dsp
import numpy as np
from recipes import Entry, _jv, _voice


def _breath(rng: np.random.Generator, seconds: float, lo: float, hi: float) -> np.ndarray:
    return dsp.filt(dsp.white(rng, seconds), "band", (lo + hi) / 2, hi - lo)


# ---- voices -----------------------------------------------------------------------------------------------------


def zombie_alert(rng: np.random.Generator) -> np.ndarray:
    """It has seen you: a short snarl that rises, with a hiss in front. Readable at a glance."""
    seconds = _jv(rng, 0.62, 0.12)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, _jv(rng, 135, 0.1)), (0.35, _jv(rng, 235, 0.1)), (1, 150)], n)
    voice = _voice(rng, seconds, pitch, ("uh", "aa"), rasp=0.6, breath=0.5, growl_hz=30, growl_depth=0.3)
    env = dsp.curve([(0, 0), (0.05, 0.5), (0.2, 1), (0.7, 0.8), (1, 0)], n)
    hiss = _breath(rng, seconds, 2500, 6500) * dsp.curve([(0, 0.0), (0.04, 0.35), (0.25, 0.0), (1, 0.0)], n)
    mix = dsp.room_tail(rng, voice * env + hiss * 0.5, 0.4, wet=0.2, dark=3500)
    return dsp.fade(mix, 0.004, 0.06)


GRUNT_PEAK_SECONDS = 0.07  # into the file, where the effort lands (the game starts it this early before the blow)


def zombie_grunt(rng: np.random.Generator) -> np.ndarray:
    """The effort of a swing: a short, low, chesty 'hhuh' that peaks at GRUNT_PEAK_SECONDS."""
    seconds = _jv(rng, 0.26, 0.15)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, _jv(rng, 150, 0.1)), (0.3, _jv(rng, 125, 0.1)), (1, 85)], n)
    voice = _voice(rng, seconds, pitch, ("uh", "oh"), rasp=0.55, breath=0.4)
    env = dsp.curve([(0, 0), (0.07, 0.4), (0.27, 1), (0.5, 0.5), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.25, wet=0.15, dark=3500), 0.003, 0.04)


def zombie_shriek(rng: np.random.Generator) -> np.ndarray:
    """The runner: a thin, high shriek that cracks upward, nothing like the walkers' low voices."""
    seconds = _jv(rng, 0.8, 0.12)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, _jv(rng, 380, 0.08)), (0.2, _jv(rng, 720, 0.08)), (0.6, _jv(rng, 940, 0.08)), (1, 600)], n)
    wobble = 1.0 + 0.035 * dsp.sine(rng.uniform(6.5, 8.5), n)
    voice = _voice(rng, seconds, pitch * wobble, ("aa", "aa"), rasp=0.35, breath=0.45)
    edge = dsp.filt(dsp.white(rng, seconds), "band", 3200, 2200) * 0.35
    env = dsp.curve([(0, 0), (0.05, 1), (0.7, 0.85), (1, 0)], n)
    mix = dsp.drive((voice + edge) * env, 2.0)
    return dsp.fade(dsp.room_tail(rng, mix, 0.5, wet=0.22, dark=5000), 0.004, 0.07)


def zombie_breath_brute(rng: np.random.Generator) -> np.ndarray:
    """The brute: a big chest working, breath in then out with a wet rumble under it. Quiet but carries low."""
    seconds = _jv(rng, 1.5, 0.12)
    n = dsp.samples(seconds)
    inhale = dsp.curve([(0, 0), (0.3, 1), (0.42, 0.3), (0.5, 0), (1, 0)], n)
    exhale = dsp.curve([(0, 0), (0.46, 0), (0.58, 0.8), (0.75, 1), (1, 0)], n)
    air = _breath(rng, seconds, 250, 1500) * (0.6 * inhale + exhale)
    rumble = dsp.filt(dsp.saw(np.full(n, _jv(rng, 58, 0.1))), "low", 300)
    rumble = dsp.formants(rumble, [(300, 90, 1.0), (620, 120, 0.5)]) * exhale
    wet = 1.0 - 0.45 * np.abs(dsp.filt(rng.normal(0, 1, n), "low", 24)) * 3
    mix = (air * 0.9 + rumble * 0.7) * np.clip(wet, 0, 1)
    return dsp.fade(dsp.room_tail(rng, mix, 0.5, wet=0.2, dark=2500), 0.02, 0.1)


def zombie_groan_brute(rng: np.random.Generator) -> np.ndarray:
    """A low, long groan, an octave under the walkers'."""
    seconds = _jv(rng, 1.7, 0.15)
    n = dsp.samples(seconds)
    top = _jv(rng, 70, 0.12)
    pitch = dsp.curve([(0, top * 0.9), (0.3, top), (1, top * 0.6)], n)
    voice = _voice(rng, seconds, pitch, ("uh", "oh"), rasp=0.55, breath=0.22, growl_hz=22, growl_depth=0.3)
    env = dsp.curve([(0, 0), (0.15, 1), (0.65, 0.85), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.6, wet=0.25, dark=2800), 0.012, 0.12)


def zombie_groan_crawler(rng: np.random.Generator) -> np.ndarray:
    """The crawler: a thin, reedy moan, pained and short of breath."""
    seconds = _jv(rng, 0.95, 0.15)
    n = dsp.samples(seconds)
    top = _jv(rng, 178, 0.12)
    pitch = dsp.curve([(0, top * 0.9), (0.3, top), (0.65, top * 0.85), (1, top * 0.6)], n)
    voice = _voice(rng, seconds, pitch, ("oh", "uh"), rasp=0.7, breath=0.6)
    env = dsp.curve([(0, 0), (0.1, 0.8), (0.45, 1), (0.7, 0.6), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.35, wet=0.2, dark=3500), 0.01, 0.1)


def zombie_drag(rng: np.random.Generator) -> np.ndarray:
    """One pull of the crawler: a body hauled over asphalt. Rough band noise whose pitch climbs with the pull, a
    flutter of cloth, a soft thump when the hand lands. About half a second."""
    seconds = _jv(rng, 0.62, 0.12)
    n = dsp.samples(seconds)
    centre = dsp.curve([(0, _jv(rng, 180, 0.15)), (0.6, _jv(rng, 520, 0.15)), (1, 330)], n)
    scrape = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.9)
    scrape = dsp.filt(scrape, "low", 1400) * 2.5
    grain = np.abs(0.5 + 0.5 * dsp.filt(rng.normal(0, 1, n), "low", 120) * 4)
    env = dsp.curve([(0, 0), (0.08, 0.7), (0.55, 1), (0.85, 0.35), (1, 0)], n)
    cloth = dsp.filt(dsp.white(rng, seconds), "high", 2800) * 0.05 * env * (0.5 + 0.5 * dsp.sine(17.0, n))
    mix = scrape * np.clip(grain, 0, 1.5) * env + cloth
    thump = dsp.sine(np.linspace(110, 60, dsp.samples(0.1))) * dsp.decay(dsp.samples(0.1), 0.045)
    mix = dsp.place(mix, thump, 0.0, 0.4)
    return dsp.fade(mix, 0.004, 0.08)


def zombie_roar(rng: np.random.Generator) -> np.ndarray:
    """The headliner's entrance: a huge, rising roar with a throat growl and a cracked top, the room ringing behind
    it. Its loudest moment is about 0.9 s in (the Boss_Roar clip's roar frame), then it falls away."""
    seconds = _jv(rng, 2.6, 0.06)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, 62), (0.25, _jv(rng, 118, 0.06)), (0.5, _jv(rng, 96, 0.06)), (1, 52)], n)
    voice = _voice(rng, seconds, pitch, ("aa", "oh"), rasp=0.45, breath=0.35, growl_hz=26, growl_depth=0.45)
    sub = dsp.sine(pitch * 0.5, n) * 0.5
    crack = _breath(rng, seconds, 600, 3800) * dsp.curve([(0, 0), (0.2, 0.5), (0.4, 0.3), (1, 0)], n) * 0.5
    env = dsp.curve([(0, 0), (0.12, 0.55), (0.35, 1), (0.6, 0.85), (1, 0)], n)
    mix = dsp.drive((voice * 1.2 + sub + crack) * env, 3.0)
    mix = dsp.echo(mix, 0.19, 0.25)
    return dsp.fade(dsp.room_tail(rng, mix, 1.3, wet=0.4, dark=3200), 0.01, 0.2)


GROWL_PEAK_SECONDS = 0.92  # where the growl reaches its height: the game starts it this long before the blow lands


def zombie_growl_boss(rng: np.random.Generator) -> np.ndarray:
    """The headliner winding up: a growl that climbs and swells under the raised arms, then cuts at the top."""
    seconds = GROWL_PEAK_SECONDS + 0.15
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, 58), (0.8, _jv(rng, 125, 0.06)), (1, 130)], n)
    voice = _voice(rng, seconds, pitch, ("uh", "aa"), rasp=0.5, breath=0.4, growl_hz=24, growl_depth=0.5)
    swell = dsp.curve([(0, 0.0), (0.5, 0.3), (0.86, 1.0), (1, 0)], n)
    air = _breath(rng, seconds, 500, 3000) * dsp.curve([(0, 0), (0.8, 0.5), (1, 0)], n) * 0.4
    mix = dsp.drive((voice + air) * swell, 3.0)
    return dsp.fade(dsp.room_tail(rng, mix, 0.7, wet=0.25, dark=3000), 0.01, 0.1)


# ---- feet -------------------------------------------------------------------------------------------------------


def zombie_step_shuffle(rng: np.random.Generator) -> np.ndarray:
    """A dragging step: the sole brushes then lands, with a fold of cloth. Soft, low and sloppy."""
    length = 0.28
    n = dsp.samples(length)
    brush = _breath(rng, length, 250, 1800) * dsp.curve([(0, 0), (0.25, 0.8), (0.5, 0.2), (1, 0)], n)
    f = _jv(rng, 78, 0.12)
    land = dsp.sine(np.linspace(f * 1.5, f, n)) * dsp.decay(n, 0.07)
    land = np.concatenate([np.zeros(dsp.samples(0.07)), land])[:n]
    grit = dsp.filt(dsp.white(rng, length), "high", 3500) * dsp.decay(n, 0.03) * rng.uniform(0.05, 0.12)
    return dsp.fade(brush * 0.55 + land * 0.9 + grit, 0.003, 0.05)


def zombie_step_run(rng: np.random.Generator) -> np.ndarray:
    """A hurried, ragged step: a harder slap and a sharp scuff, shorter than a shuffle."""
    length = 0.16
    n = dsp.samples(length)
    f = _jv(rng, 112, 0.12)
    slap = dsp.sine(np.linspace(f * 1.7, f, n)) * dsp.decay(n, 0.09)
    scuff = dsp.filt(dsp.white(rng, length), "band", _jv(rng, 1700, 0.2), 2200) * dsp.attack_decay(n, 0.002, 0.05)
    grit = dsp.filt(dsp.white(rng, length), "high", 5000) * dsp.decay(n, 0.02) * rng.uniform(0.15, 0.3)
    return dsp.fade(slap * 0.9 + scuff * 0.7 + grit, 0.001, 0.03)


def zombie_step_stomp(rng: np.random.Generator) -> np.ndarray:
    """The brute's step: a heavy weight coming down, a deep thump and a rumble of the ground, little else."""
    length = 0.4
    n = dsp.samples(length)
    f = _jv(rng, 46, 0.1)
    thump = dsp.sine(np.linspace(f * 2.0, f, n)) * dsp.decay(n, 0.22)
    body = dsp.filt(dsp.white(rng, length), "low", 220) * dsp.attack_decay(n, 0.003, 0.16)
    crunch = dsp.filt(dsp.white(rng, length), "band", 900, 1000) * dsp.decay(n, 0.025) * 0.25
    return dsp.fade(thump * 1.0 + body * 0.8 + crunch, 0.002, 0.07)


REGISTRY: list[Entry] = [
    Entry("zombie", "alert", 3, zombie_alert, -3.0),
    Entry("zombie", "grunt", 3, zombie_grunt, -3.0),
    Entry("zombie", "shriek", 2, zombie_shriek, -3.0),
    Entry("zombie", "breath_brute", 3, zombie_breath_brute, -4.0),
    Entry("zombie", "groan_brute", 3, zombie_groan_brute, -3.0),
    Entry("zombie", "groan_crawler", 3, zombie_groan_crawler, -3.0),
    Entry("zombie", "drag", 4, zombie_drag, -4.0),
    Entry("zombie", "roar", 2, zombie_roar, -2.0),
    Entry("zombie", "growl_boss", 2, zombie_growl_boss, -2.0),
    Entry("zombie", "step_shuffle", 4, zombie_step_shuffle, -5.0),
    Entry("zombie", "step_run", 4, zombie_step_run, -5.0),
    Entry("zombie", "step_stomp", 3, zombie_step_stomp, -4.0),
]
