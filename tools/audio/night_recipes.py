"""The night's remaining sounds as recipes: the ambient bed (crickets, a distant highway, the projector), the score,
the boards at the fence, doors, melee and the till (the soldiers' voices are `elevenlabs_voice.py`).

Same rules as `recipes.py`: a recipe takes a seeded numpy Generator and returns float samples, nothing is sampled
or taken from anywhere. The loops (the bed and the score) are built circularly: every event that runs past the end
wraps to the start and every filter is applied in the frequency domain, so the last sample is followed by the first
without a click. `generate.py` renders `REGISTRY` together with the first file's.
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from limiter import limit_crest
from recipes import Entry, _jv, _metal_click, _rasp, _thud

# ---- helpers for loops ------------------------------------------------------------------------------------------


def _wrap_add(mix: np.ndarray, part: np.ndarray, at: float, gain: float = 1.0) -> None:
    """Add `part` into the loop `mix` from `at` seconds, wrapping past the end back to the start."""
    start = int(at * SAMPLE_RATE) % len(mix)
    first = min(len(part), len(mix) - start)
    mix[start : start + first] += gain * part[:first]
    rest = len(part) - first
    while rest > 0:  # a part longer than the loop folds more than once
        take = min(rest, len(mix))
        mix[:take] += gain * part[len(part) - rest : len(part) - rest + take]
        rest -= take


def _ring_noise(rng: np.random.Generator, seconds: float, lo: float, hi: float, slope: float = 0.0) -> np.ndarray:
    """Noise that repeats exactly every `seconds`: random phases only between `lo` and `hi` Hz, tilted by `slope`
    (dB per octave, negative darkens). Normalised to a peak of 1."""
    n = dsp.samples(seconds)
    freqs = np.fft.rfftfreq(n, 1 / SAMPLE_RATE)
    band = (freqs >= lo) & (freqs <= hi)
    spectrum = np.zeros(len(freqs), dtype=complex)
    tilt = 10 ** (slope * np.log2(np.maximum(freqs, 1.0) / max(lo, 1.0)) / 20)
    spectrum[band] = tilt[band] * np.exp(1j * rng.uniform(0, 2 * np.pi, band.sum()))
    out = np.fft.irfft(spectrum, n)
    return out / (np.abs(out).max() + 1e-12)


def _ring_lowpass(x: np.ndarray, cutoff: float, order: int = 4) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SAMPLE_RATE)
    return np.fft.irfft(spectrum / (1 + (freqs / cutoff) ** order), len(x))


def _slow(rng: np.random.Generator, seconds: float, hz: float) -> np.ndarray:
    """A slowly wandering control curve in 0..1 that repeats every `seconds`."""
    n = dsp.samples(seconds)
    wander = _ring_lowpass(rng.normal(0, 1, n), hz, 2)
    wander -= wander.min()
    return wander / (wander.max() + 1e-12)


# ---- the ambient bed --------------------------------------------------------------------------------------------

CRICKET_SECONDS = 24.0
# The chirps a second each cricket is drawn at, and the share of them it keeps: the maintainer halved the rate (#781), so
# the eight are the same insects (pitch, bursts, place) with every other chirp gone, and each now sings 1.0 to 2.1 a second.
CRICKET_DRAW_HZ = (2.0, 4.2)
CRICKET_RATE_SCALE = 0.5
CRICKET_RATE_HZ = (CRICKET_DRAW_HZ[0] * CRICKET_RATE_SCALE, CRICKET_DRAW_HZ[1] * CRICKET_RATE_SCALE)
CRICKET_PEAK_DB = -5.0
HIGHWAY_SECONDS = 32.0
PROJECTOR_SECONDS = 12.0  # 288 frames at 24 a second
PROJECTOR_FPS = 24
SCORE_SECONDS = 32.0


def night_crickets(rng: np.random.Generator, plan: list[tuple[float, int, int]] | None = None) -> np.ndarray:
    """Eight crickets in a field: each chirps three pulses at its own pitch and rate, and sings in bursts.

    `plan`, when given, collects each cricket's (pitch in Hz, chirps in the loop, chirps sung) for `cricket_levels.py`."""
    n = dsp.samples(CRICKET_SECONDS)
    mix = np.zeros(n)
    pulse_n = dsp.samples(0.016)
    window = np.hanning(pulse_n)
    for _ in range(8):
        freq = rng.uniform(3700, 5300)
        drawn = round(rng.uniform(*CRICKET_DRAW_HZ) * CRICKET_SECONDS)  # chirps before the cut, a whole number a loop
        chirps = round(drawn * CRICKET_RATE_SCALE)
        rate = chirps / CRICKET_SECONDS
        singing = np.clip((_slow(rng, CRICKET_SECONDS, 0.35) - 0.4) * 2.6, 0.0, 1.0)
        pan_gain = rng.uniform(0.35, 1.0)
        pulse = np.sin(2 * np.pi * freq * np.arange(pulse_n) / SAMPLE_RATE) * window
        pulse += 0.25 * np.sin(2 * np.pi * freq * 2 * np.arange(pulse_n) / SAMPLE_RATE) * window
        phase = rng.uniform(0, CRICKET_SECONDS / drawn)
        loudness = rng.uniform(0.7, 1.0, drawn)  # one draw per chirp there was, so the later crickets stay the same
        sung = 0
        for k in range(chirps):
            at = phase + k / rate
            level = (
                singing[int(at * SAMPLE_RATE) % n] * pan_gain * loudness[min(round(k / CRICKET_RATE_SCALE), drawn - 1)]
            )
            if level < 0.02:
                continue
            sung += 1
            for p in range(3):
                _wrap_add(mix, pulse, at + p * 0.024, level * (1.0 - 0.18 * p))
        if plan is not None:
            plan.append((float(freq), chirps, sung))
    air = _ring_noise(rng, CRICKET_SECONDS, 300, 2500, -6.0) * 0.012
    return mix * 0.5 + air


def night_highway(rng: np.random.Generator) -> np.ndarray:
    """A road a long way off: a low rumble that swells and thins, and a car or truck now and then passing."""
    rumble = _ring_lowpass(_ring_noise(rng, HIGHWAY_SECONDS, 25, 400, -3.0), 220)
    swell = 0.55 + 0.45 * _slow(rng, HIGHWAY_SECONDS, 0.12)
    hiss = _ring_lowpass(_ring_noise(rng, HIGHWAY_SECONDS, 400, 2200, -6.0), 1400)
    mix = rumble * swell * 0.5 + hiss * _slow(rng, HIGHWAY_SECONDS, 0.2) * 0.12
    for _ in range(6):
        seconds = rng.uniform(3.5, 6.5)
        m = dsp.samples(seconds)
        pas = np.sin(np.linspace(0, np.pi, m)) ** 2
        centre = np.linspace(rng.uniform(750, 950), rng.uniform(380, 520), m)  # the pitch falls as it passes
        tyres = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.9) * pas
        engine = dsp.filt(dsp.saw(np.linspace(rng.uniform(95, 130), rng.uniform(70, 90), m)), "low", 420)
        car = (tyres * 0.6 + engine * 0.25 * pas) * rng.uniform(0.35, 0.8)
        _wrap_add(mix, dsp.filt(car, "low", 1500), rng.uniform(0, HIGHWAY_SECONDS))
    return mix


def night_projector(rng: np.random.Generator) -> np.ndarray:
    """A 35 mm projector up in the booth: the gate's 24-a-second clatter over a motor and a fan."""
    n = dsp.samples(PROJECTOR_SECONDS)
    t = np.arange(n) / SAMPLE_RATE
    mix = np.zeros(n)
    tick_len = dsp.samples(0.03)
    for frame in range(round(PROJECTOR_SECONDS * PROJECTOR_FPS)):
        at = frame / PROJECTOR_FPS
        click = dsp.filt(dsp.white(rng, 0.03), "band", rng.uniform(1100, 1900), 1800) * dsp.decay(tick_len, 0.008)
        knock = dsp.sine(np.linspace(220, 140, tick_len)) * dsp.decay(tick_len, 0.012)
        _wrap_add(mix, click * 0.5 + knock * 0.5, at, rng.uniform(0.75, 1.0) * (1.0 if frame % 2 else 0.85))
    motor = sum(
        g * np.sin(2 * np.pi * (hz * PROJECTOR_SECONDS) / PROJECTOR_SECONDS * t)
        for hz, g in ((48, 0.08), (96, 0.04), (144, 0.015))
    )
    fan = _ring_lowpass(_ring_noise(rng, PROJECTOR_SECONDS, 300, 3000, -3.0), 2200) * 0.07
    flutter = 1.0 + 0.1 * np.sin(2 * np.pi * (1 / PROJECTOR_SECONDS) * 6 * t)  # six slow swells in the loop
    return _ring_lowpass(mix * 0.9 + motor + fan, 4000) * flutter


# ---- the score --------------------------------------------------------------------------------------------------

# One chord every eight seconds: a slow B-movie vamp (D minor, B flat, G minor, A) in note frequencies.
_CHORDS = [
    (73.4, (146.8, 174.6, 220.0)),
    (58.3, (116.5, 146.8, 174.6)),
    (49.0, (98.0, 146.8, 233.1)),
    (55.0, (110.0, 138.6, 164.8)),
]
# Theremin phrases: (start seconds, note Hz, seconds) over the chords; sparse, so the bed breathes.
_PHRASES = [(1.0, 440.0, 4.2), (9.5, 466.2, 3.4), (17.0, 392.0, 4.6), (25.5, 554.4, 4.8)]


def score(rng: np.random.Generator) -> np.ndarray:
    """The break's music: a low organ pad moving through four chords, a sub bass, a sparse wailing theremin. Stereo."""
    n = dsp.samples(SCORE_SECONDS)
    left = np.zeros(n)
    right = np.zeros(n)
    chord_seconds = SCORE_SECONDS / len(_CHORDS)
    for i, (bass, notes) in enumerate(_CHORDS):
        at = i * chord_seconds
        m = dsp.samples(chord_seconds + 3.0)
        swell = (
            np.minimum(np.arange(m) / (2.2 * SAMPLE_RATE), 1.0) ** 2
            * np.minimum((m - np.arange(m)) / (2.8 * SAMPLE_RATE), 1.0) ** 2
        )
        for side, bus in enumerate((left, right)):
            pad = np.zeros(m)
            for hz in notes:
                for detune in (0.9965, 1.0, 1.0035):
                    pad += dsp.saw(hz * detune * (1.0 + 0.0005 * side), m) * 0.1
            pad = dsp.filt(pad, "low", 700)
            sub = dsp.sine(bass, m) * 0.5 + dsp.sine(bass * 2, m) * 0.12
            _wrap_add(bus, (pad + sub) * swell, at)
    for start, hz, seconds in _PHRASES:
        m = dsp.samples(seconds)
        glide = dsp.curve([(0, hz * 0.97), (0.3, hz), (1, hz * 1.01)], m)
        vibrato = 1 + 0.011 * np.sin(2 * np.pi * 5.3 * np.arange(m) / SAMPLE_RATE) * np.minimum(
            np.arange(m) / (0.9 * SAMPLE_RATE), 1.0
        )
        tone = (dsp.sine(glide * vibrato) + 0.1 * dsp.sine(glide * vibrato * 2)) * np.sin(
            np.linspace(0, np.pi, m)
        ) ** 1.4
        _wrap_add(left, tone, start, 0.2)
        _wrap_add(right, tone, start + 0.02, 0.2)
    shift = dsp.samples(0.017)
    right = np.roll(right, shift)  # a circular shift keeps the loop seamless
    return np.stack([_ring_lowpass(left, 2500), _ring_lowpass(right, 2500)])


# ---- boards at the fence ----------------------------------------------------------------------------------------

# The highest sample of each sharp sound, over its loudest 400 ms, in dB (`limiter.limit_crest`): without it the crack
# was 20 dB over the body and the body, at the level the crack is allowed close up (#753), was too quiet (#762).
BOARD_TEAR_CREST_DB = 13.0
BOARD_LAST_CREST_DB = 10.0
BOARD_REPAIR_CREST_DB = 8.0
DOOR_OPEN_CREST_DB = 12.0


def _creak(rng: np.random.Generator, seconds: float, lo: float, hi: float) -> np.ndarray:
    """Wood and nails giving way: a stick-slip pitch (a stuttering pulse train) through a wooden resonance."""
    n = dsp.samples(seconds)
    wobble = dsp.filt(rng.normal(0, 1, n), "low", 20)
    pitch = dsp.curve([(0, lo), (0.5, (lo + hi) / 2), (1, hi)], n) * (
        1.0 + 0.08 * wobble / (np.abs(wobble).max() + 1e-9)
    )
    stick = np.clip(1.0 + 0.9 * np.sin(2 * np.pi * np.cumsum(rng.uniform(14, 22) * np.ones(n)) / SAMPLE_RATE), 0.0, 1.0)
    source = dsp.pulse(pitch, 0.22) * stick
    wood = dsp.filt(source, "band", _jv(rng, 780, 0.15), 500) + 0.5 * dsp.filt(source, "band", _jv(rng, 1650, 0.1), 700)
    rise = np.sin(np.linspace(0, np.pi, n)) ** 0.8
    return wood * rise


def _crack(rng: np.random.Generator, body_hz: float, size: float = 1.0) -> np.ndarray:
    """A board snapping: a sharp broadband snap, a woody ring, then a few splinters rattling."""
    length = 0.35
    n = dsp.samples(length)
    snap = dsp.filt(dsp.white(rng, length), "high", 1500) * dsp.decay(n, 0.012)
    ring = dsp.sine(np.linspace(body_hz * 1.25, body_hz, n)) * dsp.decay(n, 0.07 * size)
    ring += 0.5 * dsp.sine(np.linspace(body_hz * 2.7, body_hz * 2.4, n)) * dsp.decay(n, 0.04)
    splinters = np.zeros(n)
    for _ in range(int(rng.integers(3, 7))):
        at = rng.uniform(0.02, 0.2)
        tick = dsp.filt(dsp.white(rng, 0.02), "band", rng.uniform(2200, 5200), 2500)
        tick = tick * dsp.decay(len(tick), 0.004) * rng.uniform(0.15, 0.5)
        splinters = dsp.place(splinters, tick, at)[:n]
    return snap * 1.0 + ring * 0.8 * size + splinters


def board_tear(rng: np.random.Generator) -> np.ndarray:
    """A board pulled off its nails: a creak, the crack, the board dropping to the ground."""
    creak_s = _jv(rng, 0.34, 0.15)
    mix = dsp.place(None, _creak(rng, creak_s, _jv(rng, 170, 0.15), _jv(rng, 330, 0.15)), 0.0, 0.55)
    at = creak_s * 0.92
    mix = dsp.place(mix, _crack(rng, _jv(rng, 420, 0.1)), at, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 130, 0.1), 0.12), at + 0.17, 0.55)
    return dsp.fade(limit_crest(mix, BOARD_TEAR_CREST_DB), 0.004, 0.06)


def board_last(rng: np.random.Generator) -> np.ndarray:
    """The last board going: a short heavy creak, a bigger crack with a low thump, the board clattering down."""
    creak_s = _jv(rng, 0.22, 0.15)
    mix = dsp.place(None, _creak(rng, creak_s, _jv(rng, 120, 0.1), _jv(rng, 260, 0.1)), 0.0, 0.5)
    at = creak_s * 0.9
    mix = dsp.place(mix, _crack(rng, _jv(rng, 320, 0.1), 1.5), at, 1.0)
    boom_n = dsp.samples(0.35)
    mix = dsp.place(mix, dsp.sine(np.geomspace(_jv(rng, 95, 0.1), 45, boom_n)) * dsp.decay(boom_n, 0.14), at, 0.9)
    for k, delay in enumerate((0.2, 0.34, 0.44)):
        mix = dsp.place(mix, _thud(rng, _jv(rng, 150 + 25 * k, 0.1), 0.08), at + delay, 0.6 - 0.15 * k)
        mix = dsp.place(mix, _crack(rng, _jv(rng, 600, 0.1), 0.4)[: dsp.samples(0.1)], at + delay, 0.3)
    return dsp.fade(limit_crest(mix, BOARD_LAST_CREST_DB), 0.004, 0.08)


def board_repair(rng: np.random.Generator) -> np.ndarray:
    """A board hammered back: three knocks, each a wood thud over a nail's ring, the last one the hardest."""
    mix = None
    at = 0.0
    for i in range(3):
        n = dsp.samples(0.16)
        f = _jv(rng, 190 + 28 * i, 0.06)
        wood = dsp.sine(np.linspace(f * 1.5, f * 0.8, n)) * dsp.decay(n, 0.05)
        slap = dsp.filt(dsp.white(rng, 0.16), "band", _jv(rng, 1300, 0.15), 1200) * dsp.decay(n, 0.012)
        nail = _metal_click(rng, _jv(rng, 2400 + 150 * i, 0.04), ring=0.012)[:n]
        mix = dsp.place(mix, wood * 1.0 + slap * 0.6, at, 0.75 + 0.15 * i)
        mix = dsp.place(mix, nail, at, 0.3 + 0.1 * i)
        at += rng.uniform(0.17, 0.23)
    return dsp.fade(limit_crest(mix, BOARD_REPAIR_CREST_DB), 0.0008, 0.05)


# ---- doors -----------------------------------------------------------------------------------------------------


def door_open(rng: np.random.Generator) -> np.ndarray:
    """A bolt thrown, a slow rusty creak, and the door-weight settling against its stop."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 420), ring=0.05), 0.0, 0.9)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 95, 0.1), 0.18), 0.02, 0.8)
    creak = _creak(rng, _jv(rng, 0.8, 0.1), _jv(rng, 90, 0.1), _jv(rng, 190, 0.1))
    mix = dsp.place(mix, creak, 0.2, 0.5)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 70, 0.1), 0.25), 1.05, 0.7)
    mix = dsp.place(mix, _rasp(rng, 0.25, 500, 1200), 0.95, 0.15)
    return dsp.fade(limit_crest(mix, DOOR_OPEN_CREST_DB), 0.002, 0.1)


# ---- melee ------------------------------------------------------------------------------------------------------


def melee_swing(rng: np.random.Generator) -> np.ndarray:
    """A crowbar through the air: a fast band-passed rush that peaks late, and a faint ring from the iron."""
    seconds = _jv(rng, 0.22, 0.12)
    n = dsp.samples(seconds)
    centre = dsp.curve([(0, 500), (0.65, 2100), (1, 700)], n)
    rush = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.9)
    swell = np.sin(np.linspace(0, np.pi, n)) ** 2.2
    swell = np.roll(swell, int(0.1 * n)) * np.linspace(1.0, 0.6, n)
    hum = dsp.sine(np.linspace(_jv(rng, 520, 0.05), 380, n)) * swell * 0.06
    return dsp.fade(rush * swell * 1.6 + hum, 0.004, 0.04)


def melee_hit(rng: np.random.Generator) -> np.ndarray:
    """Iron into the dead: a heavy wet thud, a dull clank of the bar, a bone-dry crunch."""
    n = dsp.samples(0.3)
    thud = dsp.sine(np.geomspace(_jv(rng, 150, 0.08), 55, n)) * dsp.decay(n, 0.1)
    flesh = dsp.filt(dsp.white(rng, 0.3), "low", 700) * dsp.decay(n, 0.05)
    crunch = dsp.filt(dsp.white(rng, 0.3), "band", _jv(rng, 2200, 0.15), 2500) * dsp.decay(n, 0.01)
    mix = thud * 1.0 + flesh * 0.8 + crunch * 0.5
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 540, 0.05), ring=0.04), 0.0, 0.35)
    return dsp.fade(dsp.drive(mix, 1.6), 0.0005, 0.06)


# ---- the shop's till --------------------------------------------------------------------------------------------


def till_ring(rng: np.random.Generator) -> np.ndarray:
    """A 1958 cash register: the key thump, the drawer's ratchet, then the bell."""
    mix = dsp.place(None, _thud(rng, _jv(rng, 110, 0.05), 0.12), 0.0, 0.8)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 800), ring=0.03), 0.01, 0.6)
    ratchet = _rasp(rng, 0.14, 1800, 3600)
    ticks = np.sin(2 * np.pi * 70 * np.arange(len(ratchet)) / SAMPLE_RATE) > 0.3
    mix = dsp.place(mix, ratchet * ticks, 0.08, 0.35)
    bell_hz = _jv(rng, 1760, 0.02)
    m = dsp.samples(1.3)
    bell = np.zeros(m)
    for ratio, gain, ring in ((1.0, 1.0, 0.9), (2.76, 0.5, 0.5), (5.4, 0.22, 0.25)):
        bell += gain * dsp.sine(bell_hz * ratio, m) * dsp.attack_decay(m, 0.001, ring)
    mix = dsp.place(mix, bell, 0.22, 0.6)
    bell2 = dsp.sine(bell_hz * 1.5, m) * dsp.attack_decay(m, 0.001, 0.7)
    mix = dsp.place(mix, bell2, 0.3, 0.25)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 80, 0.1), 0.2), 0.16, 0.5)
    return dsp.fade(mix, 0.001, 0.15)


# ---- registry ---------------------------------------------------------------------------------------------------

REGISTRY: list[Entry] = [
    # -5 dBFS, not -3: with half the chirps overlapping, the file normalises up 2 dB, so this keeps each chirp as loud in the
    # file as it was and the catalog's volume_db is the whole cut of a chirp (#781).
    Entry("ambience", "crickets", 1, night_crickets, CRICKET_PEAK_DB, loop=True),
    Entry("ambience", "highway", 1, night_highway, -3.0, loop=True),
    Entry("ambience", "projector", 1, night_projector, -3.0, loop=True),
    Entry("music", "score", 1, score, -3.0, loop=True),
    Entry("world", "board_tear", 3, board_tear, -10.5),
    Entry("world", "board_last", 2, board_last, -8.2),
    Entry("world", "board_repair", 3, board_repair, -9.5),
    Entry("world", "door_open", 2, door_open, -8.9),
    Entry("melee", "swing", 3, melee_swing, -5.0),
    Entry("melee", "hit", 2, melee_hit, -3.0),
    Entry("shop", "till", 2, till_ring, -3.0),
]
