"""Every Deadnight sound as a short recipe. A recipe takes a seeded numpy Generator and returns float samples
(mono, or a (2, n) array for stereo); `REGISTRY` lists them with their variant counts.

The sounds are synthesised from noise, oscillators and filters: nothing is sampled or taken from anywhere, so the
output is original and can be committed. Run `generate.py` to render them.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

import dsp
import numpy as np
from dsp import SAMPLE_RATE

Recipe = Callable[[np.random.Generator], np.ndarray]


def _jv(rng: np.random.Generator, centre: float, spread: float = 0.08) -> float:
    """A value within +-spread (a fraction) of centre: what makes variant 2 differ from variant 1."""
    return centre * (1.0 + rng.uniform(-spread, spread))


# ---- UI: a projector booth's clicks and a film-leader whoosh ----------------------------------------------------


def _blip(freq: float, seconds: float, partial: float = 0.0) -> np.ndarray:
    n = dsp.samples(seconds)
    tone = dsp.sine(freq, n) + partial * dsp.sine(freq * 2.01, n)
    return tone * dsp.attack_decay(n, 0.002, seconds * 0.5)


def ui_hover(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_blip(1900, 0.05, 0.3)) * 0.5


def ui_focus(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_blip(1250, 0.07, 0.5)) * 0.6


def ui_tick(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_blip(2600, 0.025, 0.2)) * 0.5


def _clack(rng: np.random.Generator, body: float, length: float = 0.09) -> np.ndarray:
    """A relay or projector-gate clack: a damped thump under a bright, brief click."""
    n = dsp.samples(length)
    thump = dsp.sine(np.linspace(body * 1.6, body, n)) * dsp.decay(n, length * 0.5)
    click = dsp.filt(dsp.white(rng, length), "band", 2800, 2400) * dsp.decay(n, 0.012)
    return thump * 0.9 + click * 0.8


def ui_press(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_clack(rng, 150))


def ui_back(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_clack(rng, 105, 0.11)) * 0.9


def _whoosh(rng: np.random.Generator, rising: bool, seconds: float) -> np.ndarray:
    n = dsp.samples(seconds)
    lo, hi = (500, 4200) if rising else (4200, 500)
    centre = np.linspace(lo, hi, n)
    noise = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.8)
    swell = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    sweep = dsp.sine(np.linspace(lo / 8, hi / 8, n)) * 0.15
    return (noise * 1.8 + sweep) * swell


def ui_push(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_whoosh(rng, True, 0.32), 0.01, 0.05)


def ui_pop(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_whoosh(rng, False, 0.26), 0.01, 0.05) * 0.9


# ---- guns -------------------------------------------------------------------------------------------------------


def dry_fire(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_metal_click(rng, 1400, 0.05), 0.0005, 0.01) * 0.7


# ---- reloads ----------------------------------------------------------------------------------------------------

_MODES = np.array([1.0, 1.58, 2.31, 3.37, 4.9])  # inharmonic, a little like struck steel
_MODE_GAINS = [1.0, 0.7, 0.5, 0.3, 0.2]


def _metal_click(rng: np.random.Generator, base: float, ring: float = 0.04) -> np.ndarray:
    n = dsp.samples(max(ring * 4, 0.06))
    out = np.zeros(n)
    for ratio, gain in zip(_MODES, _MODE_GAINS, strict=True):
        out += gain * dsp.sine(base * ratio * rng.uniform(0.97, 1.03), n) * dsp.decay(n, ring * rng.uniform(0.6, 1.2))
    transient = dsp.filt(dsp.white(rng, n / SAMPLE_RATE), "high", 3000) * dsp.decay(n, 0.003)
    return out * 0.45 + transient * 1.2


def _thud(rng: np.random.Generator, freq: float, length: float = 0.1) -> np.ndarray:
    n = dsp.samples(length)
    body = dsp.sine(np.linspace(freq * 1.4, freq, n)) + 0.3 * dsp.filt(dsp.white(rng, length), "low", 900)
    return body * dsp.decay(n, length * 0.5)


def _rasp(rng: np.random.Generator, seconds: float, lo: float, hi: float) -> np.ndarray:
    """Metal sliding on metal: band noise with a bumpy envelope."""
    n = dsp.samples(seconds)
    centre = np.linspace(lo, hi, n)
    noise = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.6)
    bumps = np.abs(0.6 + 0.4 * dsp.filt(dsp.white(rng, seconds), "low", 90))
    return dsp.fade(noise * bumps * np.sin(np.linspace(0, np.pi, n)) ** 0.7, 0.01, 0.02) * 1.6


# ---- footsteps --------------------------------------------------------------------------------------------------


def step_asphalt(rng: np.random.Generator) -> np.ndarray:
    n = dsp.samples(0.16)
    f = _jv(rng, 95, 0.15)
    thud = dsp.sine(np.linspace(f * 1.5, f, n)) * dsp.decay(n, 0.07)
    scuff = dsp.filt(dsp.white(rng, 0.16), "band", _jv(rng, 1100, 0.2), 1400) * dsp.attack_decay(n, 0.004, 0.05)
    grit = dsp.filt(dsp.white(rng, 0.16), "high", 4500) * dsp.decay(n, 0.02) * rng.uniform(0.1, 0.25)
    return dsp.fade(thud * 1.0 + scuff * 0.55 + grit, 0.001, 0.03)


def step_gravel(rng: np.random.Generator) -> np.ndarray:
    length = 0.3
    n = dsp.samples(length)
    mix = np.zeros(n)
    for _ in range(int(rng.integers(34, 52))):
        at = abs(rng.normal(0.0, 0.07))
        if at > length - 0.03:
            continue
        grain = dsp.filt(dsp.white(rng, 0.012), "band", rng.uniform(1800, 6500), 2500)
        grain = grain * dsp.decay(len(grain), rng.uniform(0.002, 0.006)) * rng.uniform(0.2, 1.0)
        mix = dsp.place(mix, grain, at)
    mix = mix[:n]
    f = _jv(rng, 105, 0.15)
    mix[: n // 2] += 0.5 * dsp.sine(np.linspace(f * 1.4, f, n // 2)) * dsp.decay(n // 2, 0.05)
    return dsp.fade(mix * 2.2, 0.001, 0.05)


# ---- the dead ---------------------------------------------------------------------------------------------------

_VOWELS = {
    "oh": [(420, 90, 1.0), (800, 120, 0.7), (2500, 300, 0.2)],
    "aa": [(760, 110, 1.0), (1150, 140, 0.8), (2600, 320, 0.25)],
    "uh": [(520, 100, 1.0), (1000, 130, 0.7), (2400, 300, 0.2)],
}


def _voice(
    rng: np.random.Generator,
    seconds: float,
    pitch: np.ndarray,
    vowels: tuple[str, str],
    rasp: float,
    breath: float,
    growl_hz: float = 0.0,
    growl_depth: float = 0.0,
) -> np.ndarray:
    """A throat: jittery sawtooth through two blended vowel formants, with breath and optional growl AM."""
    n = len(pitch)
    jitter = dsp.filt(rng.normal(0, 1, n), "low", 12) * 25
    source = dsp.saw(np.maximum(pitch + jitter, 30.0))
    source = dsp.filt(source, "low", 2600) + breath * dsp.filt(dsp.white(rng, seconds), "band", 1500, 2500)
    a = dsp.formants(source, _VOWELS[vowels[0]])
    b = dsp.formants(source, _VOWELS[vowels[1]])
    blend = np.linspace(0.0, 1.0, n)
    voiced = (1 - blend) * a + blend * b
    am = 1.0 - rasp * np.abs(dsp.filt(rng.normal(0, 1, n), "low", 60)) * 3
    if growl_hz:
        am *= 1.0 - growl_depth * (0.5 + 0.5 * dsp.sine(growl_hz * rng.uniform(0.9, 1.1), n))
    return dsp.drive(voiced * np.clip(am, 0, 1), 2.5)


def zombie_groan(rng: np.random.Generator) -> np.ndarray:
    seconds = _jv(rng, 1.25, 0.2)
    n = dsp.samples(seconds)
    top = _jv(rng, 118, 0.15)
    pitch = dsp.curve([(0, top * 0.85), (0.25, top), (1, top * 0.62)], n)
    vowels = ("oh", "aa") if rng.random() < 0.5 else ("uh", "oh")
    voice = _voice(rng, seconds, pitch, vowels, rasp=0.5, breath=0.18)
    env = dsp.curve([(0, 0), (0.12, 1), (0.6, 0.85), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.5, wet=0.25, dark=3500), 0.01, 0.1)


def zombie_attack(rng: np.random.Generator) -> np.ndarray:
    seconds = _jv(rng, 0.55, 0.2)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, _jv(rng, 150, 0.1)), (0.3, _jv(rng, 210, 0.1)), (1, 120)], n)
    voice = _voice(rng, seconds, pitch, ("aa", "uh"), rasp=0.7, breath=0.45, growl_hz=38, growl_depth=0.55)
    env = dsp.curve([(0, 0), (0.04, 1), (0.5, 0.9), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.35, wet=0.2, dark=3500), 0.004, 0.06)


def zombie_hurt(rng: np.random.Generator) -> np.ndarray:
    seconds = _jv(rng, 0.38, 0.15)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, _jv(rng, 190, 0.1)), (1, 105)], n)
    voice = _voice(rng, seconds, pitch, ("aa", "oh"), rasp=0.4, breath=0.25)
    env = dsp.curve([(0, 0), (0.06, 1), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.3, wet=0.2, dark=3500), 0.003, 0.05)


def zombie_death(rng: np.random.Generator) -> np.ndarray:
    seconds = _jv(rng, 1.7, 0.15)
    n = dsp.samples(seconds)
    pitch = dsp.curve([(0, _jv(rng, 130, 0.1)), (0.4, 95), (1, 48)], n)
    voice = _voice(rng, seconds, pitch, ("oh", "uh"), rasp=0.6, breath=0.3)
    env = dsp.curve([(0, 0), (0.06, 1), (0.5, 0.7), (1, 0)], n)
    return dsp.fade(dsp.room_tail(rng, voice * env, 0.6, wet=0.3, dark=3000), 0.004, 0.1)


# ---- the generator ----------------------------------------------------------------------------------------------

HUM_SECONDS = 2.0  # every component is a whole number of cycles in this, so the clip loops without a seam


def _periodic_lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SAMPLE_RATE)
    return np.fft.irfft(spectrum / (1 + (freqs / cutoff) ** 4), len(x))


def generator_hum(rng: np.random.Generator) -> np.ndarray:
    t = dsp.t_axis(HUM_SECONDS)
    n = len(t)
    mains = sum(
        gain * np.sin(2 * np.pi * (60 * k) * t + rng.uniform(0, 6.28))
        for k, gain in zip((1, 2, 3, 5), (0.5, 0.35, 0.18, 0.08), strict=True)
    )
    firing = (t * 24) % 1.0  # 24 power strokes a second
    stroke = np.exp(-firing * 9) * np.minimum(firing / 0.05, 1.0) * (1 + 0.25 * np.sin(2 * np.pi * 1.0 * t))
    rumble = _periodic_lowpass(rng.normal(0, 1, n), 700)
    rumble /= np.abs(rumble).max()
    throb = 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t)
    out = mains * 0.45 + rumble * stroke * 0.9 + 0.12 * _periodic_lowpass(rng.normal(0, 1, n), 3000)
    return out * throb


def generator_start(rng: np.random.Generator) -> np.ndarray:
    """A pull-cord rasp, a false start, then the engine catching and settling toward its hum."""
    seconds = 3.2
    n = dsp.samples(seconds)
    rate = dsp.curve([(0, 3), (0.12, 5), (0.3, 5), (0.34, 9), (0.55, 15), (0.8, 22), (1, 24)], n)
    firing = (np.cumsum(rate) / SAMPLE_RATE) % 1.0
    gate = dsp.curve([(0, 0), (0.1, 1), (0.3, 0.5), (0.32, 0.2), (0.4, 0.9), (1, 1)], n)
    stroke = np.exp(-firing * 8) * gate
    noise = dsp.filt(rng.normal(0, 1, n), "low", np.linspace(500, 900, n))
    noise /= np.abs(noise).max()
    hz = dsp.curve([(0, 30), (0.4, 40), (0.8, 55), (1, 60)], n)
    level = dsp.curve([(0, 0), (0.45, 0.1), (0.8, 0.5), (1, 0.5)], n)
    hum = np.sin(2 * np.pi * np.cumsum(hz) / SAMPLE_RATE) * level
    cord = dsp.place(np.zeros(n), _rasp(rng, 0.35, 600, 1800), 0.0, 0.4)[:n]
    return dsp.fade(noise * stroke + hum + cord, 0.01, 0.1)


# ---- stings -----------------------------------------------------------------------------------------------------


def _stereo(rng: np.random.Generator, dry: np.ndarray, seconds: float, wet: float) -> np.ndarray:
    """Two different room tails make a mono source wide."""
    left = dsp.room_tail(rng, dry, seconds, wet=wet)
    right = dsp.room_tail(rng, dry, seconds, wet=wet)
    return np.stack([left, right])


def round_start(rng: np.random.Generator) -> np.ndarray:
    """Timpani, a minor-cluster brass stab, a theremin wail and a cymbal swell: a B-movie title card."""
    seconds = 2.8
    n = dsp.samples(seconds)
    drum_n = dsp.samples(1.2)
    drum = dsp.sine(np.geomspace(110, 52, drum_n)) * dsp.decay(drum_n, 0.8)
    drum += 0.5 * dsp.filt(dsp.white(rng, 1.2), "low", 600) * dsp.decay(drum_n, 0.08)
    brass = np.zeros(n)
    cutoff = dsp.curve([(0, 300), (0.08, 2800), (0.35, 900), (1, 400)], n)
    for hz in (73.4, 110.0, 146.8, 207.7):
        for detune in (0.994, 1.0, 1.006):
            brass += dsp.filt(dsp.saw(hz * detune, n), "low", cutoff) * 0.12
    brass *= dsp.attack_decay(n, 0.03, 1.5)
    vibrato = 1 + 0.012 * np.sin(2 * np.pi * 5.6 * dsp.t_axis(seconds))
    glide = dsp.curve([(0, 440), (0.25, 440), (0.6, 880), (1, 830)], n) * vibrato
    swell_level = dsp.curve([(0, 0), (0.22, 0), (0.4, 0.5), (0.75, 0.4), (1, 0)], n)
    theremin = (dsp.sine(glide) + 0.12 * dsp.sine(glide * 2)) * swell_level
    swell_n = dsp.samples(2.4)
    swell = dsp.filt(dsp.white(rng, 2.4), "high", 5000) * np.minimum(np.linspace(0, 1, swell_n) * 6, 1) ** 2
    swell *= dsp.decay(swell_n, 1.8)
    dry = dsp.place(None, drum, 0.0, 1.0)
    dry = dsp.place(dry, brass, 0.0, 0.8)
    dry = dsp.place(dry, theremin, 0.0, 0.35)
    dry = dsp.place(dry, swell, 0.0, 0.18)
    return dsp.fade(_stereo(rng, dry, 1.4, 0.5), 0.002, 0.2)


def special_round(rng: np.random.Generator) -> np.ndarray:
    """A marquee switching on: bulbs ticking on faster and faster, a reel whirring up, two low organ stabs, a gong."""
    seconds = 3.2
    n = dsp.samples(seconds)
    dry = np.zeros(n)
    at, gap = 0.0, 0.24
    for i in range(11):
        tick_n = dsp.samples(0.05)
        click = dsp.filt(dsp.white(rng, 0.05), "band", 3400 + 90 * i, 1800) * dsp.decay(tick_n, 0.008)
        blip = dsp.sine(1500 + 110 * i, tick_n) * dsp.decay(tick_n, 0.012)
        dry = dsp.place(dry, click + 0.5 * blip, at, 3.0)
        at += gap
        gap *= 0.84
    whirr_n = dsp.samples(1.5)
    whirr = dsp.filt(dsp.white(rng, 1.5), "band", np.geomspace(350, 3200, whirr_n), 600)
    whirr *= dsp.curve([(0, 0), (0.7, 0.8), (0.9, 1), (1, 0)], whirr_n)
    flutter = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * np.geomspace(6, 24, whirr_n).cumsum() / SAMPLE_RATE))
    dry = dsp.place(dry, whirr * flutter, 0.9, 0.9)
    for when, base in ((1.95, 1.0), (2.35, 0.84)):
        stab_n = dsp.samples(1.6)
        stab = np.zeros(stab_n)
        cutoff = dsp.curve([(0, 400), (0.06, 2400), (0.3, 700), (1, 300)], stab_n)
        for hz in (55.0, 82.4, 110.0, 164.8):
            for detune in (0.995, 1.0, 1.005):
                stab += dsp.filt(dsp.saw(hz * base * detune, stab_n), "low", cutoff) * 0.12
        dry = dsp.place(dry, stab * dsp.attack_decay(stab_n, 0.02, 1.0), when, 0.6)
    gong_n = dsp.samples(2.4)
    gong = np.zeros(gong_n)
    for ratio, level in ((1.0, 1.0), (1.51, 0.6), (2.37, 0.4), (3.1, 0.25)):
        mod = dsp.sine(147.0 * ratio * 2.01, gong_n) * dsp.decay(gong_n, 0.6) * 1.4
        gong += level * np.sin(2 * np.pi * dsp.phase_of(np.full(gong_n, 147.0 * ratio)) + mod)
    dry = dsp.place(dry, gong * dsp.attack_decay(gong_n, 0.004, 1.8), 1.95, 0.16)
    return dsp.fade(_stereo(rng, dry, 1.5, 0.5), 0.002, 0.25)


def round_end(rng: np.random.Generator) -> np.ndarray:
    """A relieved, bell-like resolve: three FM tones climbing over a soft low tom."""
    n = dsp.samples(2.2)
    dry = np.zeros(n)
    for at, hz in ((0.0, 293.7), (0.14, 370.0), (0.28, 440.0)):
        m = dsp.samples(1.8)
        mod = dsp.sine(hz * 2.0, m) * dsp.decay(m, 0.4) * 2.2
        bell = np.sin(2 * np.pi * dsp.phase_of(np.full(m, hz)) + mod) * dsp.attack_decay(m, 0.004, 1.2)
        dry = dsp.place(dry, bell, at, 0.4)
    tom_n = dsp.samples(0.5)
    dry = dsp.place(dry, dsp.sine(np.geomspace(140, 80, tom_n)) * dsp.decay(tom_n, 0.3), 0.0, 0.7)
    return dsp.fade(_stereo(rng, dry, 1.2, 0.45), 0.002, 0.2)


# ---- registry ---------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Entry:
    group: str
    name: str
    variants: int
    recipe: Recipe
    peak_db: float = -3.0  # the file's peak; the game balances loudness with the catalog's volume_db
    loop: bool = False  # a loop keeps its length (it is a whole cycle) and is never trimmed


# ---- grenades: the fuse's beep, a throw's whoosh, a bounce on asphalt, the blast --------------------------------

BEEP_HZ = 1100.0
BEEP_SECONDS = 0.06


def grenade_beep(rng: np.random.Generator) -> np.ndarray:
    """The fuse's beep, a time bomb's: a clean electronic tone (1.1 kHz and two harmonics for the edge), held 60 ms
    with a hard start, the same pitch every time (nothing random, so a run of them is a metronome and the gap is the
    signal). It sits low on purpose: behind a car the audio service low-passes a sound at 1.1 kHz and takes 9 dB off,
    which erased a 2.6 kHz beep entirely and leaves this one a dull, still audible knock."""
    del rng  # a beep is not a natural sound: nothing in it is random
    n = dsp.samples(BEEP_SECONDS)
    tone = dsp.sine(BEEP_HZ, n) + 0.45 * dsp.sine(BEEP_HZ * 2.0, n) + 0.2 * dsp.sine(BEEP_HZ * 3.0, n)
    return dsp.fade(tone, 0.002, 0.012)


def grenade_throw(rng: np.random.Generator) -> np.ndarray:
    """The pin and the spoon flying off, then a short arm whoosh."""
    pin = _metal_click(rng, _jv(rng, 1700), ring=0.03)
    spoon = _metal_click(rng, _jv(rng, 1100), ring=0.05)
    mix = dsp.place(None, pin, 0.0, 0.7)
    mix = dsp.place(mix, spoon, 0.045, 0.5)
    mix = dsp.place(mix, _whoosh(rng, False, 0.28) * 0.5, 0.06)
    return dsp.fade(mix, 0.001, 0.05)


def grenade_bounce(rng: np.random.Generator) -> np.ndarray:
    """A heavy iron shell knocking on asphalt: a low knock over a short, bright rattle."""
    n = dsp.samples(0.3)
    knock = dsp.sine(np.geomspace(_jv(rng, 260), 110, n)) * dsp.decay(n, 0.09)
    rattle = _metal_click(rng, _jv(rng, 700), ring=0.08)
    mix = dsp.place(None, knock, 0.0, 0.9)
    mix = dsp.place(mix, rattle, 0.0, 0.6)
    return dsp.fade(mix, 0.0005, 0.04)


def grenade_blast(rng: np.random.Generator) -> np.ndarray:
    """A crack, a roar that darkens, a deep falling boom and one slap off the screen tower, in open air."""
    tail = 2.4
    n = dsp.samples(tail)
    crack = dsp.filt(dsp.white(rng, tail), "high", 1200) * dsp.decay(n, 0.03)
    sweep = np.linspace(_jv(rng, 5000), 180, n)
    roar = dsp.filt(dsp.white(rng, tail), "low", sweep) * dsp.decay(n, 0.45)
    boom_n = dsp.samples(1.2)
    boom = dsp.sine(np.geomspace(_jv(rng, 90), 28, boom_n)) * dsp.decay(boom_n, 0.55)
    boom = np.pad(boom, (0, n - boom_n))
    blast = 0.9 * crack + 1.1 * roar + 1.6 * boom
    blast = dsp.drive(blast, 2.5)
    blast = dsp.echo(blast, _jv(rng, 0.23, 0.1), 0.25)
    blast = dsp.room_tail(rng, blast, 1.6, wet=0.55, dark=4000)
    return dsp.fade(blast, 0.0005, 0.12)


REGISTRY: list[Entry] = [
    Entry("ui", "hover", 1, ui_hover, -12.0),
    Entry("ui", "focus", 1, ui_focus, -10.0),
    Entry("ui", "press", 1, ui_press, -4.0),
    Entry("ui", "back", 1, ui_back, -5.0),
    Entry("ui", "push", 1, ui_push, -6.0),
    Entry("ui", "pop", 1, ui_pop, -6.0),
    Entry("ui", "tick", 1, ui_tick, -12.0),
    Entry("guns", "dry_fire", 1, dry_fire, -6.0),
    Entry("steps", "asphalt", 8, step_asphalt, -6.0),
    Entry("steps", "gravel", 8, step_gravel, -6.0),
    Entry("zombie", "groan", 4, zombie_groan, -3.0),
    Entry("zombie", "attack", 3, zombie_attack, -3.0),
    Entry("zombie", "hurt", 3, zombie_hurt, -3.0),
    Entry("zombie", "death", 2, zombie_death, -3.0),
    Entry("world", "generator_hum", 1, generator_hum, -6.0, loop=True),
    Entry("world", "generator_start", 1, generator_start, -4.0),
    Entry("stings", "round_start", 1, round_start, -2.0),
    Entry("stings", "round_end", 1, round_end, -3.0),
    Entry("stings", "special_round", 1, special_round, -2.0),
    Entry("grenade", "beep", 1, grenade_beep, -6.0),
    Entry("grenade", "throw", 2, grenade_throw, -5.0),
    Entry("grenade", "bounce", 3, grenade_bounce, -6.0),
    Entry("grenade", "blast", 2, grenade_blast, -1.0),
]
