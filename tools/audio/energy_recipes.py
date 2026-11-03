"""The energy weapons' sounds, the re-cut layer and the re-cut bench (Deadnight #791). Synthesised like the rest
(`recipes.py`): noise, oscillators and filters, nothing sampled.

Three families, in a module of their own so the firearms' recipes (`weapon_recipes.py`) are not touched:

- The ray gun (a blue bolt that bursts with a splash): a charged, rising zap for the shot, a hum for the bolt's flight,
  a burst with its crackling splash, and the reload's cell going out and in.
- The freeze gun (a cold hiss that freezes a zombie for three seconds, after which one blow shatters it): the shot, the
  freeze taking hold, the creak of the ice while it holds, the thaw and the shatter.
- The re-cut layer: one short futuristic sound (a sweep, a ring and a sub pulse) that plays over the shot of any
  re-cut weapon, in variants, so every weapon of the roster sounds upgraded without a recipe each; and the re-cut bench's
  own sequence (`buy_recut`), which ends on the same ring so the two read as one thing.

The shots keep the firearms' rules (`docs/research/gun-audio.md`): the variants of a shot differ in their noise, not in
their note (`FREQUENCY_SPREAD`), the file is dense up to its peak (the loudness rule against the beds is read on a short
burst) and nothing leans on a bus effect, which the web build ignores. `tools/audio/energy_levels.py` measures them.
"""

from __future__ import annotations

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from limiter import limit_crest
from recipes import Entry, _jv, _metal_click, _rasp, _thud
from weapon_recipes import FREQUENCY_SPREAD

# ---- small parts ------------------------------------------------------------------------------------------------


def _sweep(f0: float, f1: float, seconds: float, shape: str = "geo") -> np.ndarray:
    """A sine gliding from f0 to f1 (geometric by default, which is how a pitch is heard to glide)."""
    n = dsp.samples(seconds)
    hz = np.geomspace(f0, f1, n) if shape == "geo" else np.linspace(f0, f1, n)
    return dsp.sine(hz)


def _fm_sweep(f0: float, f1: float, seconds: float, ratio: float, index: float) -> np.ndarray:
    """A frequency-modulated glide: a carrier from f0 to f1 bent by a sine at `ratio` of itself. The sound of a
    synthetic zap: the sidebands make it ring metallic and bright at the top."""
    n = dsp.samples(seconds)
    hz = np.geomspace(f0, f1, n)
    carrier_phase = dsp.phase_of(hz)
    mod = np.sin(2 * np.pi * dsp.phase_of(hz * ratio)) * index
    return np.sin(2 * np.pi * carrier_phase + mod)


def _crackle(
    rng: np.random.Generator, seconds: float, per_second: float, high: float, grain: float = 0.006
) -> np.ndarray:
    """Electric or icy crackle: short bright grains at random times, the rate falling off over the sound."""
    n = dsp.samples(seconds)
    out = np.zeros(n)
    count = int(per_second * seconds)
    times = np.sort(rng.exponential(seconds * 0.4, count))
    for at in times:
        if at > seconds - grain * 2:
            continue
        g = dsp.filt(dsp.white(rng, grain * 2), "high", rng.uniform(high, high * 1.8))
        g = g * dsp.decay(len(g), grain * rng.uniform(0.5, 1.2)) * rng.uniform(0.25, 1.0)
        out = dsp.place(out, g, at)[:n]
    return out


def _tame(x: np.ndarray, hz: float = 8000.0) -> np.ndarray:
    """Roll off what an FM sweep or a noise grain throws above `hz` (aliased sidebands are harsh, not bright)."""
    return dsp.filt(dsp.filt(x, "low", hz), "low", hz)


def _dense(x: np.ndarray, crest_db: float, passes: int = 3) -> np.ndarray:
    """`limit_crest` again until the crest holds: limiting also lowers the loudest 400 ms it was measured on, so one pass
    leaves the crest a few dB over what was asked."""
    for _ in range(passes):
        x = limit_crest(x, crest_db)
    return x


def _partials(base: float, ratios: list[float], gains: list[float], ring: float, n: int) -> np.ndarray:
    """A struck, glassy tone: damped sines at the given ratios (higher ones die sooner)."""
    out = np.zeros(n)
    for k, (ratio, gain) in enumerate(zip(ratios, gains, strict=True)):
        out += gain * dsp.sine(base * ratio, n) * dsp.decay(n, ring / (1.0 + 0.6 * k))
    return out


def _periodic_noise(rng: np.random.Generator, seconds: float, low: float, high: float) -> np.ndarray:
    """Band-limited noise that is exactly periodic over `seconds` (its spectrum is on whole hertz): a loop with no seam."""
    n = dsp.samples(seconds)
    spectrum = np.zeros(n // 2 + 1, dtype=complex)
    freqs = np.fft.rfftfreq(n, 1 / SAMPLE_RATE)
    keep = (freqs >= low) & (freqs <= high)
    spectrum[keep] = np.exp(2j * np.pi * rng.random(keep.sum()))
    out = np.fft.irfft(spectrum, n)
    return out / (np.abs(out).max() + 1e-9)


# ---- the ray gun ------------------------------------------------------------------------------------------------

RAY_CREST_DB = 7.0
# The quiet sounds of the freeze (its hold, its thaw, its creak) are made of ticks and drips: a crest of 25 dB, so at the
# peak a sound beside the listener may have its body is under the night's beds. Dense, they are heard.
SOFT_CREST_DB = 10.0
FREEZE_CREST_DB = 7.0


def shot_ray(rng: np.random.Generator) -> np.ndarray:
    """The ray gun's shot: the cell charges (a sweep climbing from 350 Hz to 2.2 kHz in 90 ms), the bolt is let go
    with a crack, a falling FM zap over a barking roar and a thump, and a few electric snaps, with the ring of the
    discharge after it. Limited in the file so a short burst of it is loud at a peak the other sounds can land on."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    total = 0.7
    n = dsp.samples(total)
    charge_s = 0.09
    cn = dsp.samples(charge_s)
    charge = _fm_sweep(jv(350), jv(2200), charge_s, 1.5, 1.2) * np.linspace(0.15, 1.0, cn) ** 1.5
    charge += 0.5 * dsp.filt(dsp.white(rng, charge_s), "band", np.linspace(600, 3500, cn), 1800) * np.linspace(0, 1, cn)
    mix = dsp.place(None, charge, 0.0, 0.9)
    at = charge_s
    crack = dsp.filt(dsp.white(rng, 0.08), "high", jv(1500)) * dsp.decay(dsp.samples(0.08), 0.01)
    zap = _fm_sweep(jv(2400), jv(240), 0.34, 1.41, 1.8) * dsp.attack_decay(dsp.samples(0.34), 0.001, 0.15)
    zap2 = _sweep(jv(1500), jv(120), 0.3) * dsp.attack_decay(dsp.samples(0.3), 0.001, 0.12)
    bark = dsp.filt(dsp.white(rng, 0.16), "band", jv(700), 1200) * dsp.decay(dsp.samples(0.16), 0.06)
    roar = dsp.filt(dsp.white(rng, 0.3), "low", np.linspace(jv(3000), 300, dsp.samples(0.3))) * dsp.decay(
        dsp.samples(0.3), 0.09
    )
    thump = _sweep(jv(210), jv(52), 0.22) * dsp.decay(dsp.samples(0.22), 0.1)
    sub = dsp.sine(jv(58), dsp.samples(0.2)) * dsp.decay(dsp.samples(0.2), 0.09)
    mix = dsp.place(mix, crack * 0.8, at)
    mix = dsp.place(mix, zap * 1.2, at)
    mix = dsp.place(mix, zap2 * 0.8, at)
    mix = dsp.place(mix, bark * 3.0, at)
    mix = dsp.place(mix, roar * 2.2, at)
    mix = dsp.place(mix, thump * 1.4, at)
    mix = dsp.place(mix, sub * 0.6, at)
    mix = dsp.place(mix, _crackle(rng, 0.45, 70, 2200) * 0.4, at + 0.02)
    mix = _tame(dsp.drive(mix[:n], 2.0), 7000)
    ring_n = dsp.samples(0.4)
    ring = _partials(jv(1900), [1.0, 1.51, 2.33], [0.5, 0.3, 0.2], 0.25, ring_n) * 0.3
    mix = dsp.place(mix, ring, at + 0.02)
    return _dense(dsp.fade(mix, 0.0005, 0.12), RAY_CREST_DB)


def bolt_ray(rng: np.random.Generator) -> np.ndarray:
    """The bolt in flight, a loop one second long: a hum of two close notes beating at 7 Hz, a shimmer that sweeps
    through the bright band eight times and an electric fizz. Every frequency is a whole number of hertz, so the loop
    has no seam."""
    seconds = 1.0
    t = dsp.t_axis(seconds)
    hum = np.sin(2 * np.pi * 196 * t) + 0.9 * np.sin(2 * np.pi * 203 * t) + 0.4 * np.sin(2 * np.pi * 392 * t)
    saw = sum(np.sin(2 * np.pi * 98 * k * t) / k for k in range(1, 12))
    wobble = 0.55 + 0.45 * np.sin(2 * np.pi * 8 * t)
    shimmer = np.sin(2 * np.pi * (1500 * t + 220 / (2 * np.pi * 8) * (1 - np.cos(2 * np.pi * 8 * t))))
    fizz = _periodic_noise(rng, seconds, 2500, 9000) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    mix = 0.5 * hum + 0.25 * saw + 0.3 * shimmer * wobble + 0.35 * fizz
    return mix


def burst_ray(rng: np.random.Generator) -> np.ndarray:
    """The bolt bursting where it lands, with its splash: a boom and a falling zap, then a shower of electric
    crackle that spreads and thins over half a second and rings off. Limited, like the shot."""
    total = 1.1
    n = dsp.samples(total)
    boom = dsp.filt(dsp.white(rng, total), "low", np.linspace(3200, 300, n)) * dsp.decay(n, 0.14)
    thump = _sweep(160, 38, 0.4) * dsp.decay(dsp.samples(0.4), 0.18)
    flash = dsp.filt(dsp.white(rng, 0.06), "high", 2200) * dsp.decay(dsp.samples(0.06), 0.01)
    zap = _fm_sweep(2400, 180, 0.4, 1.41, 1.8) * dsp.attack_decay(dsp.samples(0.4), 0.001, 0.15)
    splash = _crackle(rng, 0.8, 140, 2400, 0.008)
    spark_fall = dsp.filt(dsp.white(rng, 0.9), "band", np.linspace(4200, 1500, dsp.samples(0.9)), 2500)
    spark_fall = spark_fall * dsp.attack_decay(dsp.samples(0.9), 0.01, 0.4)
    mix = dsp.place(None, boom * 2.4, 0.0)
    mix = dsp.place(mix, thump * 1.1, 0.0)
    mix = dsp.place(mix, flash * 1.2, 0.0)
    mix = dsp.place(mix, zap * 1.1, 0.005)
    mix = dsp.place(mix, splash * 0.9, 0.03)
    mix = dsp.place(mix, spark_fall * 0.45, 0.04)
    mix = _tame(dsp.drive(mix[:n], 1.8), 7000)
    ring = (
        _partials(_jv(rng, 1450, 0.03), [1.0, 1.51, 2.33, 3.1], [0.5, 0.35, 0.25, 0.15], 0.5, dsp.samples(0.7)) * 0.25
    )
    mix = dsp.place(mix, ring, 0.04)
    mix = dsp.room_tail(rng, mix, 0.5, wet=0.3, dark=5000)
    return _dense(dsp.fade(mix, 0.0005, 0.2), 8.0)


def reload_ray_cell_out(rng: np.random.Generator) -> np.ndarray:
    """The energy cell released: a latch click, the cell sliding out on a falling whine (the charge draining), and a
    soft clunk as it drops into a palm."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1000, 0.05), ring=0.03), 0.0, 0.8)
    whine_s = 0.32
    n = dsp.samples(whine_s)
    whine = _sweep(_jv(rng, 2200, 0.03), 380, whine_s) * dsp.attack_decay(n, 0.01, 0.2)
    whine += 0.4 * _sweep(_jv(rng, 4400, 0.03), 760, whine_s) * dsp.attack_decay(n, 0.01, 0.12)
    mix = dsp.place(mix, whine, 0.03, 0.35)
    mix = dsp.place(mix, _rasp(rng, 0.1, 1200, 2600) * 0.6, 0.02)
    mix = dsp.place(mix, _thud(rng, 160, 0.1), 0.17, 0.7)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 700, 0.05), ring=0.04), 0.17, 0.5)
    return dsp.fade(mix, 0.001, 0.05)


def reload_ray_cell_in(rng: np.random.Generator) -> np.ndarray:
    """A fresh cell seated and charged: the slide, a clack, then a whine that climbs to a ready ping."""
    mix = dsp.place(None, _rasp(rng, 0.08, 1400, 3000) * 0.6, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 800, 0.05), ring=0.045), 0.07, 1.0)
    mix = dsp.place(mix, _thud(rng, 210, 0.09), 0.07, 0.8)
    charge_s = 0.4
    n = dsp.samples(charge_s)
    charge = _fm_sweep(_jv(rng, 500, 0.03), _jv(rng, 3000, 0.03), charge_s, 1.5, 1.5)
    charge *= np.linspace(0.1, 1.0, n) ** 1.5 * dsp.curve([(0, 1), (0.9, 1), (1, 0)], n)
    mix = dsp.place(mix, charge, 0.12, 0.35)
    ping = _partials(_jv(rng, 3000, 0.02), [1.0, 2.0], [0.6, 0.2], 0.12, dsp.samples(0.25))
    mix = dsp.place(mix, ping, 0.52, 0.4)
    return dsp.fade(mix, 0.001, 0.06)


def equip_ray(rng: np.random.Generator) -> np.ndarray:
    """The ray gun raised: its cell wakes (a hum that rises 120 to 420 Hz and settles, with a thin shimmer) and a
    latch clicks."""
    seconds = 0.6
    n = dsp.samples(seconds)
    hz = dsp.curve([(0, 120), (0.5, 400), (1, 420)], n)
    hum = dsp.filt(dsp.saw(hz, n), "low", 1400) * 0.5 + dsp.sine(hz * 2, n) * 0.25
    hum *= dsp.curve([(0, 0), (0.15, 0.8), (0.7, 0.7), (1, 0)], n)
    shimmer = _fm_sweep(1200, 3800, seconds, 1.5, 1.5) * dsp.curve([(0, 0), (0.4, 0.2), (0.7, 0.15), (1, 0)], n)
    mix = dsp.place(None, hum, 0.0, 0.6)
    mix = dsp.place(mix, shimmer, 0.0, 0.4)
    mix = dsp.place(mix, _metal_click(rng, 900, ring=0.03), 0.02, 0.6)
    return dsp.fade(mix, 0.002, 0.1)


# ---- the freeze gun ---------------------------------------------------------------------------------------------


def shot_freeze(rng: np.random.Generator) -> np.ndarray:
    """The freeze gun's shot: a gas valve opening (a sharp cold hiss), a bark of pressure, a bright icy crackle
    and a glassy ring, over a low thump. Limited in the file."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    total = 0.75
    n = dsp.samples(total)
    valve = _metal_click(rng, jv(1300), ring=0.02)
    burst = dsp.filt(dsp.white(rng, total), "high", np.linspace(jv(2200), 4500, n)) * dsp.attack_decay(n, 0.004, 0.22)
    bark = dsp.filt(dsp.white(rng, total), "band", jv(900), 1100) * dsp.decay(n, 0.06)
    body = dsp.filt(dsp.white(rng, total), "low", np.linspace(3000, 400, n)) * dsp.decay(n, 0.08)
    thump = _sweep(jv(170), jv(60), 0.2) * dsp.decay(dsp.samples(0.2), 0.09)
    crackle = _crackle(rng, 0.5, 120, 3200, 0.005)
    frost = _fm_sweep(jv(3200), jv(1300), 0.35, 1.73, 1.2) * dsp.attack_decay(dsp.samples(0.35), 0.002, 0.14)
    mix = dsp.place(None, dsp.drive(burst * 0.4 + bark * 5.0 + body * 4.0, 3.0), 0.0)
    mix = dsp.place(mix, valve, 0.0, 0.5)
    mix = dsp.place(mix, thump * 2.0, 0.0)
    mix = dsp.place(mix, crackle * 0.5, 0.02)
    mix = dsp.place(mix, frost * 0.35, 0.0)
    ring = _partials(jv(2300), [1.0, 1.62, 2.41, 3.5], [0.5, 0.35, 0.25, 0.15], 0.35, dsp.samples(0.5)) * 0.15
    mix = dsp.place(_tame(dsp.drive(mix[:n], 2.2), 8500), ring, 0.03)[:n]
    return _dense(dsp.fade(mix, 0.0005, 0.15), FREEZE_CREST_DB)


def freeze_hit(rng: np.random.Generator) -> np.ndarray:
    """The freeze taking hold of a zombie: a crackle that thickens as the frost spreads, glass notes rising over it,
    and a last hard crack as it locks."""
    seconds = 0.8
    n = dsp.samples(seconds)
    rate = dsp.curve([(0, 20), (0.7, 160), (1, 40)], n)
    # Grains placed by a rising density: the quantile of a rising ramp.
    grains = np.zeros(n)
    t = 0.0
    while t < seconds - 0.05:
        g = dsp.filt(dsp.white(rng, 0.012), "high", rng.uniform(3000, 6000))
        g = g * dsp.decay(len(g), 0.004) * rng.uniform(0.3, 1.0)
        grains = dsp.place(grains, g, t)[:n]
        t += 1.0 / rate[min(int(t * SAMPLE_RATE), n - 1)] * rng.uniform(0.5, 1.5)
    mix = dsp.place(None, grains, 0.0, 0.8)
    for k, hz in enumerate((1760.0, 2217.5, 2637.0, 3322.4, 3951.1)):
        m = dsp.samples(0.3)
        note = _partials(_jv(rng, hz, 0.01), [1.0, 2.76], [0.5, 0.15], 0.18, m)
        mix = dsp.place(mix, note, 0.1 + k * 0.1, 0.22)
    lock = dsp.place(
        _metal_click(rng, _jv(rng, 2600, 0.03), ring=0.03),
        dsp.filt(dsp.white(rng, 0.05), "high", 2500) * dsp.decay(dsp.samples(0.05), 0.01),
        0.0,
    )
    mix = dsp.place(mix, lock, 0.62, 0.8)
    mix = dsp.place(mix, _thud(rng, 120, 0.12), 0.62, 0.6)
    return _dense(dsp.fade(mix[:n], 0.002, 0.08), SOFT_CREST_DB)


def freeze_creak(rng: np.random.Generator) -> np.ndarray:
    """Ice under load: a stick-slip groan (a band of noise and a sawtooth whose pitch falls and wobbles, gated by
    irregular slips) with a tick or two of cracking."""
    seconds = float(rng.uniform(0.55, 0.8))
    n = dsp.samples(seconds)
    base = _jv(rng, 420, 0.15)
    hz = np.geomspace(base * 1.5, base * 0.7, n) * (1 + 0.04 * np.sin(2 * np.pi * 11 * dsp.t_axis(seconds)))
    saw = dsp.filt(dsp.saw(hz, n), "band", hz * 2.0, hz * 1.5)
    slips = np.abs(dsp.filt(dsp.white(rng, seconds), "low", 38)) * 6.0
    slips = np.clip(slips, 0, 1) ** 1.5
    groan = saw * slips * np.sin(np.linspace(0, np.pi, n)) ** 0.7
    mix = dsp.place(None, groan, 0.0, 0.8)
    for _ in range(int(rng.integers(2, 4))):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2300, 0.2), ring=0.01), rng.uniform(0.05, seconds - 0.1), 0.35)
    return _dense(dsp.fade(mix[:n], 0.01, 0.1), SOFT_CREST_DB)


def freeze_thaw(rng: np.random.Generator) -> np.ndarray:
    """The ice letting go: a soft crack, a trickle of drips (short sines that bend up) and a settling clink."""
    seconds = 1.0
    n = dsp.samples(seconds)
    mix = dsp.place(
        None, dsp.filt(dsp.white(rng, 0.08), "band", 1800, 2400) * dsp.decay(dsp.samples(0.08), 0.02), 0.0, 0.6
    )
    mix = dsp.place(mix, _thud(rng, 110, 0.1), 0.0, 0.5)
    at = 0.12
    while at < seconds - 0.2:
        d = dsp.samples(0.07)
        hz = np.geomspace(_jv(rng, 700, 0.3), _jv(rng, 1500, 0.3), d)
        drip = dsp.sine(hz) * dsp.attack_decay(d, 0.001, 0.03)
        mix = dsp.place(mix, drip, at, rng.uniform(0.15, 0.4))
        at += rng.uniform(0.06, 0.16)
    wet = dsp.filt(dsp.white(rng, 0.7), "band", 900, 1500) * np.sin(np.linspace(0, np.pi, dsp.samples(0.7))) * 0.12
    mix = dsp.place(mix, wet, 0.1)
    mix = dsp.place(mix, _partials(2400, [1.0, 2.7], [0.5, 0.15], 0.1, dsp.samples(0.2)), 0.8, 0.25)
    return _dense(dsp.fade(mix[:n], 0.001, 0.1), SOFT_CREST_DB)


def freeze_shatter(rng: np.random.Generator) -> np.ndarray:
    """A frozen body breaking into pieces: a hard crack and a low thump, then twenty-odd shards of glass tinkling
    down over half a second (damped inharmonic tones, high ones first), and the rubble of the bigger pieces."""
    total = 1.2
    n = dsp.samples(total)
    crack = dsp.filt(dsp.white(rng, 0.12), "high", 1500) * dsp.decay(dsp.samples(0.12), 0.02)
    snap = dsp.filt(dsp.white(rng, 0.15), "band", 800, 1200) * dsp.decay(dsp.samples(0.15), 0.04)
    thump = _sweep(190, 55, 0.25) * dsp.decay(dsp.samples(0.25), 0.1)
    mix = dsp.place(None, crack * 1.5, 0.0)
    mix = dsp.place(mix, snap * 2.0, 0.0)
    mix = dsp.place(mix, thump * 1.0, 0.0)
    shards = int(rng.integers(22, 32))
    for k in range(shards):
        at = 0.02 + abs(rng.normal(0.0, 0.22))
        if at > 0.8:
            continue
        hz = rng.uniform(2200, 7800) * (1.0 - 0.3 * at)
        shard = _partials(hz, [1.0, 2.32, 4.1], [0.6, 0.3, 0.15], rng.uniform(0.05, 0.16), dsp.samples(0.25))
        mix = dsp.place(mix, shard, at, rng.uniform(0.12, 0.45))
    for _ in range(int(rng.integers(6, 10))):
        at = 0.08 + rng.uniform(0.0, 0.5)
        chunk = _thud(rng, rng.uniform(140, 320), 0.06) + _metal_click(rng, rng.uniform(1200, 2600), ring=0.012) * 0.4
        mix = dsp.place(mix, chunk, at, rng.uniform(0.2, 0.5))
    mix = dsp.room_tail(rng, mix[:n], 0.4, wet=0.2, dark=6000)
    return _dense(dsp.fade(mix, 0.0005, 0.2), 8.0)


def reload_freeze_out(rng: np.random.Generator) -> np.ndarray:
    """The coolant canister twisted off: a clamp's click, a hiss of gas leaving and a hollow knock as it comes free."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 800, 0.05), ring=0.04), 0.0, 0.8)
    hiss = dsp.filt(dsp.white(rng, 0.3), "high", 4000) * dsp.attack_decay(dsp.samples(0.3), 0.01, 0.15)
    mix = dsp.place(mix, hiss, 0.03, 0.35)
    mix = dsp.place(mix, _rasp(rng, 0.12, 900, 2200) * 0.5, 0.05)
    mix = dsp.place(mix, _thud(rng, 150, 0.1), 0.2, 0.8)
    mix = dsp.place(mix, _partials(520, [1.0, 2.1], [0.4, 0.2], 0.05, dsp.samples(0.12)), 0.2, 0.3)
    return dsp.fade(mix, 0.001, 0.05)


def reload_freeze_in(rng: np.random.Generator) -> np.ndarray:
    """A fresh canister locked in: a slide, a clunk, the pressure building in a rising hiss and a click as it seals."""
    mix = dsp.place(None, _rasp(rng, 0.07, 1300, 2800) * 0.6, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 700, 0.05), ring=0.05), 0.06, 1.0)
    mix = dsp.place(mix, _thud(rng, 190, 0.1), 0.06, 0.9)
    n = dsp.samples(0.35)
    centre = np.linspace(1500, 6000, n)
    hiss = dsp.filt(dsp.white(rng, 0.35), "band", centre, centre) * np.linspace(0.1, 1.0, n) ** 1.5
    mix = dsp.place(mix, hiss * dsp.curve([(0, 1), (0.9, 1), (1, 0)], n), 0.12, 0.3)
    mix = dsp.place(mix, _metal_click(rng, 1500, ring=0.02), 0.5, 0.6)
    return dsp.fade(mix, 0.001, 0.05)


def equip_freeze(rng: np.random.Generator) -> np.ndarray:
    """The freeze gun raised: a cold chime (glass partials) and a short breath of gas, with a click."""
    mix = dsp.place(None, _partials(1760, [1.0, 2.41, 3.6], [0.5, 0.3, 0.15], 0.3, dsp.samples(0.5)), 0.0, 0.35)
    hiss = dsp.filt(dsp.white(rng, 0.25), "high", 4500) * dsp.attack_decay(dsp.samples(0.25), 0.02, 0.1)
    mix = dsp.place(mix, hiss, 0.0, 0.3)
    mix = dsp.place(mix, _metal_click(rng, 950, ring=0.03), 0.02, 0.6)
    return dsp.fade(mix, 0.002, 0.1)


# ---- the re-cut layer -------------------------------------------------------------------------------------------

# The layer rides over a gun's report. The report is dense up to its peak and the peaks of two sounds add, so the layer
# starts `LAYER_DELAY` after the shot (the report's crack is over, as a tail's start is) and is made dense in its own
# right (a crest of `LAYER_CREST_DB`): it is not loud at any moment but it keeps ringing in the bright band after the
# report, where nothing else in the shot is tonal. `energy_levels.py` measures the sum against the gun alone.
LAYER_DELAY = 0.03
LAYER_CREST_DB = 7.0


def _pulsing(x: np.ndarray, hz: float, depth: float) -> np.ndarray:
    """`x` swelling and ebbing `hz` times a second: the pulse that tells a ring from a held tone."""
    t = np.arange(len(x)) / SAMPLE_RATE
    return x * (1.0 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * hz * t)))


def _layer_sub(rng: np.random.Generator, hz: float, seconds: float) -> np.ndarray:
    n = dsp.samples(seconds)
    return dsp.sine(hz, n) * dsp.attack_decay(n, 0.006, seconds * 0.5)


def recut_layer(rng: np.random.Generator) -> np.ndarray:
    """What an upgraded weapon adds to its shot: a synthetic sweep that climbs and then dives (a laser's pew, bent),
    a ring of three cold partials that pulses and outlasts the shot, a shimmer, and a short sub pulse underneath. It
    starts `LAYER_DELAY` after the shot. The frequencies of the variants stay within `FREQUENCY_SPREAD`: it is one
    sound in several takes."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    d = LAYER_DELAY
    up = _fm_sweep(jv(1100), jv(4600), 0.05, 1.5, 1.2) * np.linspace(0.3, 1.0, dsp.samples(0.05))
    down = _fm_sweep(jv(4600), jv(900), 0.22, 1.5, 1.2) * dsp.attack_decay(dsp.samples(0.22), 0.002, 0.12)
    mix = dsp.place(None, up, d, 0.7)
    mix = dsp.place(mix, down, d + 0.05, 1.0)
    ring = _partials(jv(2350), [1.0, 1.51, 2.33], [0.5, 0.35, 0.25], 0.5, dsp.samples(0.6))
    mix = dsp.place(mix, _pulsing(ring, 14.0, 0.4), d + 0.01, 1.0)
    shimmer = _fm_sweep(jv(3200), jv(2800), 0.55, 2.0, 1.0) * dsp.attack_decay(dsp.samples(0.55), 0.02, 0.35)
    mix = dsp.place(mix, shimmer, d + 0.05, 0.35)
    mix = dsp.place(mix, _layer_sub(rng, jv(62), 0.14), d, 0.5)
    return _dense(dsp.fade(mix, 0.0005, 0.15), LAYER_CREST_DB)


def recut_deep(rng: np.random.Generator) -> np.ndarray:
    """The re-cut layer of the wonder weapons, whose own shots are already full of sweeps and glass in the bright band
    (where the shared layer would be lost): the same idea an octave and a half down, a falling sweep, a ring of three
    low partials that pulses, and a longer sub pulse. 30 ms behind the shot, like the shared layer."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    d = LAYER_DELAY
    dive = _fm_sweep(jv(1700), jv(240), 0.3, 1.5, 1.0) * dsp.attack_decay(dsp.samples(0.3), 0.004, 0.16)
    ring = _partials(jv(330), [1.0, 1.51, 2.33], [0.6, 0.4, 0.3], 0.55, dsp.samples(0.6))
    mix = dsp.place(None, dive, d, 0.9)
    mix = dsp.place(mix, _pulsing(ring, 12.0, 0.4), d + 0.01, 1.0)
    mix = dsp.place(mix, _layer_sub(rng, jv(52), 0.22), d, 0.7)
    return _dense(dsp.fade(mix, 0.0005, 0.15), LAYER_CREST_DB)


# The elements' layers play over the shared layer, not instead of it (a weapon that burns is also a re-cut weapon), so
# each is only what the element adds: no ring of its own, a different colour of noise and a different pulse.


def recut_fire(rng: np.random.Generator) -> np.ndarray:
    """The fire element's accent (the pump 870 and the flare gun): an ember hiss that swells into a rising whoosh of flame,
    with sparks spitting out of it. Warm, where the shared layer is cold."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    d = LAYER_DELAY
    total = 0.6
    n = dsp.samples(total)
    centre = np.linspace(jv(500), jv(2400), n)
    whoosh = dsp.filt(dsp.white(rng, total), "band", centre, centre) * dsp.attack_decay(n, 0.05, 0.25)
    sparks = _crackle(rng, 0.5, 90, 3000, 0.006)
    flicker = _pulsing(dsp.filt(dsp.white(rng, total), "band", 1200, 1500), 9.0, 0.5) * dsp.attack_decay(n, 0.02, 0.3)
    mix = dsp.place(None, whoosh * 1.4, d)
    mix = dsp.place(mix, sparks * 0.9, d + 0.03)
    mix = dsp.place(mix, flicker * 0.6, d)
    return _dense(dsp.fade(mix, 0.0005, 0.15), LAYER_CREST_DB)


def recut_shock(rng: np.random.Generator) -> np.ndarray:
    """The shock element's accent (the dual pistols' arc): a buzz of 100 Hz pulses through the high band, gated at
    random, with a few snaps and a quick rising zip."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    d = LAYER_DELAY
    total = 0.5
    n = dsp.samples(total)
    buzz = dsp.filt(dsp.pulse(jv(100), 0.2, n), "band", 2600, 3000) * dsp.attack_decay(n, 0.004, 0.22)
    gate = np.repeat((rng.random(n // 300 + 2) > 0.35).astype(float), 300)[:n]
    snaps = _crackle(rng, 0.45, 100, 2800, 0.004)
    zip_ = _fm_sweep(jv(1400), jv(5200), 0.07, 1.41, 1.5) * dsp.attack_decay(dsp.samples(0.07), 0.002, 0.05)
    mix = dsp.place(None, buzz * gate, d)
    mix = dsp.place(mix, snaps * 0.8, d + 0.02)
    mix = dsp.place(mix, zip_, d, 0.9)
    return _dense(dsp.fade(mix, 0.0005, 0.15), LAYER_CREST_DB)


def recut_blast(rng: np.random.Generator) -> np.ndarray:
    """The explosive element's accent (the revolver's rounds): a dull crump under the shot (a falling sine and a puff of
    low noise) and a scatter of small debris ticks that falls away."""
    jv = lambda c: _jv(rng, c, FREQUENCY_SPREAD)
    d = LAYER_DELAY
    total = 0.5
    n = dsp.samples(total)
    crump = _sweep(jv(130), jv(42), 0.22) * dsp.attack_decay(dsp.samples(0.22), 0.006, 0.12)
    puff = dsp.filt(dsp.white(rng, total), "low", 900) * dsp.attack_decay(n, 0.006, 0.12)
    ticks = _crackle(rng, 0.4, 45, 1800, 0.01)
    mix = dsp.place(None, crump * 1.4, d)
    mix = dsp.place(mix, puff * 1.5, d)
    mix = dsp.place(mix, ticks * 0.6, d + 0.05)
    return _dense(dsp.fade(mix, 0.0005, 0.12), LAYER_CREST_DB)


# ---- the re-cut bench -------------------------------------------------------------------------------------------

# The bench's sequence in seconds (`RecutMachine`, as #787 made it): the weapon is laid down by 0.4, the press strikes at
# 0.8 (a flash, a ring of light and sparks, all cold blue), the weapon's skin sweeps on from butt to muzzle until 1.35,
# the press rises from 1.0, the weapon is shown lifted to 2.4. The sound follows it: the reels' power whine climbs to
# the strike, the strike is a discharge, a rush climbs with the skin's front, and the ring of the re-cut layer closes it.
BENCH_STRIKE = 0.8
BENCH_DONE = 1.55
BENCH_SWEEP = 0.55  # the skin sweeps on from the butt to the muzzle, from the strike (`RecutMachine.SWEEP`)
BENCH_RING = 0.6  # the ring of light that leaves the blow (`RecutMachine.RING_SECONDS`)


def buy_recut(rng: np.random.Generator) -> np.ndarray:
    """The re-cut bench in its new, cold look: the reels' motor winds up under a charging whine that climbs to the
    press, the strike discharges (a hard crack, a thump and an arc of crackle) with a sweep that rushes up through the
    bright band, the weapon's change shimmers as the press lifts (glass notes climbing, a ratchet of clicks slowing),
    and the ring of the re-cut layer says it is done at 1.55 s. The motor and the press are the booth's; the charge,
    the arc and the ring are what the re-cut is made of now."""
    seconds = 2.5
    n = dsp.samples(seconds)
    hz = dsp.curve([(0, 70), (0.3, 210), (0.7, 190), (1, 120)], n)
    motor = dsp.filt(dsp.saw(hz, n), "low", 700) * 0.4 + dsp.sine(hz * 0.5, n) * 0.35
    motor *= dsp.curve([(0, 0), (0.04, 0.7), (0.65, 0.8), (0.9, 0.25), (1, 0)], n)
    mix = dsp.place(None, motor, 0.0, 0.45)[:n]
    cn = dsp.samples(BENCH_STRIKE)
    charge = _fm_sweep(180, 2600, BENCH_STRIKE, 1.5, 1.5) * np.linspace(0.05, 1.0, cn) ** 2.0
    charge += 0.4 * _fm_sweep(360, 5200, BENCH_STRIKE, 1.0, 1.0) * np.linspace(0.0, 1.0, cn) ** 2.5
    mix = dsp.place(mix, charge, 0.0, 0.4)[:n]
    # The strike.
    mix = dsp.place(mix, _thud(rng, 70, 0.3), BENCH_STRIKE, 1.0)[:n]
    crack = dsp.filt(dsp.white(rng, 0.1), "high", 1800) * dsp.decay(dsp.samples(0.1), 0.02)
    mix = dsp.place(mix, crack, BENCH_STRIKE, 0.9)[:n]
    arc = _crackle(rng, 0.6, 110, 2800, 0.007)
    mix = dsp.place(mix, arc, BENCH_STRIKE + 0.01, 0.7)[:n]
    # The skin sweeps on from the butt to the muzzle in `BENCH_SWEEP` seconds: a rush that climbs with its front.
    sn = dsp.samples(BENCH_SWEEP)
    rush = _fm_sweep(400, 7000, BENCH_SWEEP, 1.41, 1.5) * np.sin(np.linspace(0.0, np.pi * 0.85, sn)) ** 1.5
    mix = dsp.place(mix, rush, BENCH_STRIKE, 0.45)[:n]
    # The ring of light that leaves the blow opens out and fades: a breath of noise that falls as it widens.
    wn = dsp.samples(BENCH_RING)
    centre = np.linspace(4200, 1200, wn)
    breath = dsp.filt(dsp.white(rng, BENCH_RING), "band", centre, centre) * dsp.attack_decay(wn, 0.02, 0.45)
    mix = dsp.place(mix, breath, BENCH_STRIKE, 0.5)[:n]
    # The weapon changes as the front passes: glass notes climb with it, and a ratchet slows with the lamps.
    for k, note_hz in enumerate((1318.5, 1568.0, 1975.5, 2349.3)):
        m = dsp.samples(0.32)
        note = _partials(note_hz, [1.0, 2.76], [0.5, 0.15], 0.2, m)
        mix = dsp.place(mix, note, BENCH_STRIKE + 0.05 + k * 0.12, 0.18)[:n]
    at, gap = 1.1, 0.03
    while at < 1.5:
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2200, 0.1), ring=0.01), at, 0.25)[:n]
        at += gap
        gap *= 1.18
    # The ring that closes it, the same partials as the re-cut layer's (2350 Hz, 1.51, 2.33).
    ring = _partials(2350.0, [1.0, 1.51, 2.33], [0.5, 0.35, 0.25], 0.5, dsp.samples(0.9))
    mix = dsp.place(mix, ring, BENCH_DONE, 0.55)[:n]
    mix = dsp.place(
        mix, dsp.sine(62, dsp.samples(0.2)) * dsp.attack_decay(dsp.samples(0.2), 0.004, 0.1), BENCH_DONE, 0.5
    )[:n]
    return dsp.fade(dsp.room_tail(rng, mix, 0.5, wet=0.15, dark=6000), 0.003, 0.15)


# ---- registry ---------------------------------------------------------------------------------------------------

REGISTRY: list[Entry] = [
    Entry("energy", "shot_ray", 4, shot_ray, -1.0),
    Entry("energy", "bolt_ray", 1, bolt_ray, -8.0, loop=True),
    Entry("energy", "burst_ray", 3, burst_ray, -3.0),
    Entry("energy", "reload_ray_cell_out", 2, reload_ray_cell_out, -5.0),
    Entry("energy", "reload_ray_cell_in", 2, reload_ray_cell_in, -4.0),
    Entry("energy", "equip_ray", 1, equip_ray, -6.0),
    Entry("energy", "shot_freeze", 4, shot_freeze, -1.0),
    Entry("energy", "freeze_hit", 2, freeze_hit, -5.0),
    Entry("energy", "freeze_creak", 4, freeze_creak, -6.0),
    Entry("energy", "freeze_thaw", 2, freeze_thaw, -6.0),
    Entry("energy", "freeze_shatter", 4, freeze_shatter, -3.0),
    Entry("energy", "reload_freeze_out", 2, reload_freeze_out, -5.0),
    Entry("energy", "reload_freeze_in", 2, reload_freeze_in, -4.0),
    Entry("energy", "equip_freeze", 1, equip_freeze, -6.0),
    Entry("energy", "recut_layer", 5, recut_layer, -3.0),
    Entry("energy", "recut_deep", 3, recut_deep, -3.0),
    Entry("energy", "recut_fire", 3, recut_fire, -3.0),
    Entry("energy", "recut_shock", 3, recut_shock, -3.0),
    Entry("energy", "recut_blast", 3, recut_blast, -3.0),
    Entry("world", "buy_recut", 1, buy_recut, -3.0),
]
