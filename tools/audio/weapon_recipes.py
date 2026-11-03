"""The weapons' and the lot's machines' sounds: layered gunshots, reload steps, impacts, the generator's moods, the
shop, and a tense bed for the rounds. Same rules as `recipes.py`: synthesised from noise, oscillators and filters.

A gunshot is built from layers that the game plays on separate voices, so no two shots are the same file twice:
`shot_<gun>` is the transient and the body (the report you feel), `tail_<gun>` is the roll across the lot and the slap
off the screen tower. Both come in several variants whose every parameter is jittered by the variant's seed.
"""

from __future__ import annotations

from dataclasses import dataclass

import dsp
import numpy as np
from dsp import SAMPLE_RATE
from recipes import Entry, _jv, _metal_click, _rasp, _thud

# ---- gunshots: report (transient + body) and tail ---------------------------------------------------------------


@dataclass(frozen=True)
class Report:
    """What a close gunshot is made of. The report is the whole shot as the shooter hears it, a few feet from the
    muzzle: a click, a crack, a roar that darkens, a falling thump and a low note under it, all in its first
    quarter second. The room comes later, in the tail, which is a voice of its own."""

    crack_hp: float  # high-pass of the supersonic crack
    crack_len: float
    boom_hz: tuple[float, float]  # the muzzle roar's low-pass, from where it starts to where it ends
    boom_len: float
    body_hz: tuple[float, float]  # the chest thump's sweep
    body_len: float
    sub_hz: float  # a steady low note under the thump
    sub_len: float
    length: float  # the file's length before trimming
    mid_hz: float = 500.0  # the bark: band noise between the thump and the crack, where a gun is loudest
    mid_len: float = 0.06
    ring: float = 0.0  # a metallic ring after the shot (an SMG's receiver)
    gain_crack: float = 1.0
    gain_boom: float = 1.0
    gain_mid: float = 2.0
    gain_body: float = 1.0
    gain_sub: float = 0.0
    drive: float = 12.0  # a gunshot is loud because it is dense: driven hard, the roar fills the file up to its peak
    bounce: float = 0.007  # the ground's reflection, seconds after the shot: size without a room


# Every variant keeps these numbers within a few percent (`FREQUENCY_SPREAD`): the shots of a burst differ in their
# noise, not in their pitch, which the ear takes for the gun itself.
FREQUENCY_SPREAD = 0.02
LEVEL_SPREAD = 0.1

REPORTS = {
    "pistol": Report(
        1500,
        0.012,
        (3500, 400),
        0.15,
        (190, 75),
        0.12,
        70,
        0.16,
        0.5,
        mid_hz=450,
        mid_len=0.08,
        gain_crack=0.6,
        gain_boom=2.5,
        gain_body=0.35,
        gain_sub=0.2,
    ),
    "smg": Report(
        1800,
        0.008,
        (4000, 600),
        0.08,
        (200, 100),
        0.07,
        100,
        0.07,
        0.2,
        mid_hz=500,
        mid_len=0.05,
        ring=1250,
        gain_crack=0.5,
        gain_boom=2.5,
        gain_body=0.55,
        gain_sub=0.3,
    ),
    "rifle": Report(
        1300,
        0.014,
        (3200, 300),
        0.22,
        (150, 60),
        0.16,
        62,
        0.22,
        0.7,
        mid_hz=380,
        mid_len=0.11,
        gain_crack=0.6,
        gain_boom=2.5,
        gain_body=0.4,
        gain_sub=0.3,
    ),
    "shotgun": Report(
        900,
        0.02,
        (2800, 220),
        0.36,
        (110, 42),
        0.28,
        48,
        0.35,
        0.9,
        mid_hz=300,
        mid_len=0.16,
        gain_crack=0.5,
        gain_boom=3.0,
        gain_body=0.5,
        gain_sub=0.4,
    ),
}


def report(rng: np.random.Generator, gun: Report) -> np.ndarray:
    """A click, a crack, a roar that darkens, a falling thump and a low note under it, driven together so they glue."""
    n = dsp.samples(gun.length)
    seconds = gun.length
    snap = dsp.filt(dsp.white(rng, 0.004), "high", 3000) * dsp.decay(dsp.samples(0.004), 0.0015)
    crack = dsp.filt(dsp.white(rng, seconds), "high", _jv(rng, gun.crack_hp, FREQUENCY_SPREAD))
    crack *= dsp.decay(n, gun.crack_len)
    boom_hz = np.geomspace(_jv(rng, gun.boom_hz[0], FREQUENCY_SPREAD), gun.boom_hz[1], n)
    boom = dsp.filt(dsp.white(rng, seconds), "low", boom_hz)
    boom *= 0.65 * dsp.decay(n, gun.boom_len * 0.3) + 0.35 * dsp.decay(n, gun.boom_len)
    f0, f1 = (_jv(rng, f, FREQUENCY_SPREAD) for f in gun.body_hz)
    body = dsp.sine(np.geomspace(f0, f1, n)) * dsp.decay(n, gun.body_len)
    mid_hz = _jv(rng, gun.mid_hz, FREQUENCY_SPREAD)
    mid = dsp.filt(dsp.white(rng, seconds), "band", mid_hz, mid_hz * 1.2) * dsp.decay(n, gun.mid_len)
    sub = dsp.sine(_jv(rng, gun.sub_hz, FREQUENCY_SPREAD), n) * dsp.attack_decay(n, 0.004, gun.sub_len)
    shot = gun.gain_crack * crack + gun.gain_boom * boom * _jv(rng, 1.0, LEVEL_SPREAD)
    shot += gun.gain_mid * mid + gun.gain_body * body + gun.gain_sub * sub
    shot[: len(snap)] += 1.5 * snap
    if gun.ring:
        shot += dsp.sine(_jv(rng, gun.ring, FREQUENCY_SPREAD), n) * dsp.decay(n, 0.05) * 0.12
    shot = dsp.echo(dsp.drive(shot, gun.drive), gun.bounce, 0.3, dark=3500)
    return dsp.fade(shot, 0.0002, 0.03)


@dataclass(frozen=True)
class Tail:
    length: float  # how long the lot rolls
    echo: float  # the screen tower's slap delay
    dark: float  # the roll's low-pass start
    gain_echo: float = 0.5


TAILS = {
    "pistol": Tail(0.55, 0.21, 3600, gain_echo=0.35),
    "smg": Tail(0.32, 0.19, 3800, gain_echo=0.3),
    "rifle": Tail(0.8, 0.27, 3200, gain_echo=0.4),
    "shotgun": Tail(0.9, 0.24, 2800, gain_echo=0.45),
}


def tail(rng: np.random.Generator, spec: Tail) -> np.ndarray:
    """What is left of the shot after the lot has taken it: a darkening roll of noise and one slap off the screen
    tower. Starts almost silent (the report is the front), so the game plays it a few hundredths late and well
    under the report."""
    length = _jv(rng, spec.length, 0.08)
    n = dsp.samples(length)
    roll = dsp.filt(dsp.white(rng, length), "low", np.linspace(_jv(rng, spec.dark, 0.05), 500, n))
    roll *= dsp.attack_decay(n, 0.03, length * 0.4)
    low = dsp.sine(np.geomspace(_jv(rng, 80, 0.03), 38, n)) * dsp.attack_decay(n, 0.025, length * 0.3) * 0.25
    out = dsp.echo(roll + low, _jv(rng, spec.echo, 0.08), spec.gain_echo, dark=2200)
    out = dsp.room_tail(rng, out, length * 0.5, wet=0.4, dark=3500)
    return dsp.fade(out, 0.004, 0.1)


def flare_shot(rng: np.random.Generator) -> np.ndarray:
    """A flare pistol's report: a crack, a hollow thump and a puff of the short barrel, then the rocket's ignition, a
    hiss that climbs as the flare takes off."""
    n = dsp.samples(0.9)
    crack = dsp.filt(dsp.white(rng, 0.9), "high", _jv(rng, 1400, FREQUENCY_SPREAD)) * dsp.decay(n, 0.014)
    puff = dsp.filt(dsp.white(rng, 0.9), "low", np.linspace(_jv(rng, 3200, FREQUENCY_SPREAD), 500, n)) * dsp.decay(
        n, 0.09
    )
    bark = dsp.filt(dsp.white(rng, 0.9), "band", _jv(rng, 420, FREQUENCY_SPREAD), 500) * dsp.decay(n, 0.07)
    thump = dsp.sine(np.geomspace(_jv(rng, 190, FREQUENCY_SPREAD), 65, n)) * dsp.decay(n, 0.12)
    click = _metal_click(rng, _jv(rng, 1400, FREQUENCY_SPREAD), ring=0.02)
    centre = np.linspace(1800, 5200, n)
    hiss = dsp.filt(dsp.white(rng, 0.9), "band", centre, centre * 0.9) * dsp.attack_decay(n, 0.04, 0.4) * 0.5
    body = 0.6 * crack + 2.4 * puff + 2.2 * bark + 0.7 * thump
    mix = dsp.place(None, dsp.drive(body, 2.5) + hiss, 0.0)
    mix = dsp.place(mix, click, 0.0, 0.4)
    return dsp.fade(mix, 0.0003, 0.12)


def flare_burst(rng: np.random.Generator) -> np.ndarray:
    """A flare lighting where it lands: a magnesium flash crackle and a fizzling hiss."""
    n = dsp.samples(1.4)
    pop = dsp.filt(dsp.white(rng, 1.4), "band", 2200, 3000) * dsp.decay(n, 0.05) * 1.2
    sizzle = dsp.filt(dsp.white(rng, 1.4), "high", 3500) * dsp.decay(n, 0.7)
    crackle = np.zeros(n)
    for _ in range(int(rng.integers(26, 40))):
        at = rng.exponential(0.25)
        if at > 1.2:
            continue
        grain = dsp.filt(dsp.white(rng, 0.01), "high", 3000) * dsp.decay(dsp.samples(0.01), 0.003)
        crackle = dsp.place(crackle, grain, at, rng.uniform(0.2, 0.9))[:n]
    return dsp.fade(pop + sizzle * 0.35 + crackle * 0.6, 0.0005, 0.2)


# ---- swap, empty, impacts ---------------------------------------------------------------------------------------


def weapon_swap(rng: np.random.Generator) -> np.ndarray:
    """A sling's rustle and a metal-on-leather clap as the other gun comes up."""
    mix = dsp.place(None, _rasp(rng, _jv(rng, 0.09), 600, 1400) * 0.5, 0.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 170, 0.1), 0.08), 0.07, 0.8)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 780, 0.1), ring=0.03), 0.075, 0.8)
    return dsp.fade(mix, 0.002, 0.03)


def impact_flesh(rng: np.random.Generator) -> np.ndarray:
    """A wet thump: a falling sine, a mid squelch of band noise, a flick of cloth."""
    n = dsp.samples(0.22)
    thump = dsp.sine(np.geomspace(_jv(rng, 150, 0.15), 55, n)) * dsp.decay(n, 0.08)
    squelch_c = np.linspace(_jv(rng, 1400, 0.2), 380, n)
    squelch = dsp.filt(dsp.white(rng, 0.22), "band", squelch_c, squelch_c) * dsp.decay(n, 0.06)
    cloth = dsp.filt(dsp.white(rng, 0.22), "high", 3000) * dsp.decay(n, 0.012) * 0.4
    return dsp.fade(thump * 1.0 + squelch * 0.9 + cloth, 0.0008, 0.04)


def impact_head(rng: np.random.Generator) -> np.ndarray:
    """A headshot: the flesh thump with a bright crack and a short hollow knock, so it reads over the rest."""
    base = impact_flesh(rng)
    n = len(base)
    crack = dsp.filt(dsp.white(rng, n / SAMPLE_RATE), "high", 2200) * dsp.decay(n, 0.02)
    knock = dsp.sine(_jv(rng, 420, 0.1), n) * dsp.decay(n, 0.05) * 0.6
    return dsp.fade(base * 0.8 + crack * 0.9 + knock, 0.0005, 0.04)


def impact_world(rng: np.random.Generator) -> np.ndarray:
    """A round on asphalt or sheet metal: a dry hit, a puff of grit, and a ricochet's falling whine."""
    n = dsp.samples(0.5)
    hit = _metal_click(rng, _jv(rng, 2100, 0.15), ring=0.012)
    grit = dsp.filt(dsp.white(rng, 0.5), "band", _jv(rng, 2600, 0.2), 3500) * dsp.decay(n, 0.03)
    whine_n = dsp.samples(0.35)
    whine = dsp.sine(np.geomspace(_jv(rng, 5200, 0.15), 1700, whine_n)) * dsp.attack_decay(whine_n, 0.003, 0.09)
    mix = dsp.place(None, hit, 0.0, 0.9)
    mix = dsp.place(mix, grit, 0.0, 0.7)
    mix = dsp.place(mix, whine, 0.004, 0.22 * rng.uniform(0.4, 1.0))
    return dsp.fade(mix, 0.0004, 0.05)


# ---- reload steps -----------------------------------------------------------------------------------------------


def _mag_out(rng: np.random.Generator, pitch: float) -> np.ndarray:
    """The release button's click, then the magazine sliding out and dropping into a palm."""
    mix = dsp.place(None, _metal_click(rng, 1200 * pitch, ring=0.03), 0.0, 0.7)
    mix = dsp.place(mix, _rasp(rng, 0.07, 1500, 3000) * 0.7, 0.015)
    return dsp.place(mix, _thud(rng, 150 * pitch, 0.1), 0.09, 0.7)


def _mag_in(rng: np.random.Generator, pitch: float) -> np.ndarray:
    """A magazine sliding home and seating with a hard clack."""
    mix = dsp.place(None, _rasp(rng, 0.06, 1400, 2800) * 0.6, 0.0)
    mix = dsp.place(mix, _metal_click(rng, 800 * pitch, ring=0.045), 0.055, 1.0)
    return dsp.place(mix, _thud(rng, 210 * pitch, 0.09), 0.055, 0.9)


def reload_smg_mag_out(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag_out(rng, _jv(rng, 0.9, 0.05)), 0.001, 0.02)


def reload_smg_mag_in(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag_in(rng, _jv(rng, 0.9, 0.05)), 0.001, 0.02)


def reload_rifle_round(rng: np.random.Generator) -> np.ndarray:
    """One round pushed through the loading gate: a brass tick and a spring's thud."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1900, 0.06), ring=0.018), 0.0, 0.7)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 260, 0.1), 0.06), 0.012, 0.6), 0.001, 0.02)


def reload_rifle_lever(rng: np.random.Generator) -> np.ndarray:
    """The lever thrown down and snapped back: a slide of steel and two heavy clacks."""
    mix = dsp.place(None, _metal_click(rng, 640, ring=0.05), 0.0, 0.9)
    mix = dsp.place(mix, _rasp(rng, _jv(rng, 0.13, 0.1), 700, 2400), 0.03, 0.7)
    mix = dsp.place(mix, _thud(rng, 130, 0.09), 0.0, 0.7)
    mix = dsp.place(mix, _metal_click(rng, 520, ring=0.06), 0.2, 1.0)
    return dsp.fade(dsp.place(mix, _thud(rng, 110, 0.1), 0.2, 0.8), 0.001, 0.03)


def reload_shotgun_open(rng: np.random.Generator) -> np.ndarray:
    """The break-action's lever and hinge: a latch click, a short metal creak, the barrels dropping."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 900, 0.06), ring=0.03), 0.0, 0.8)
    n = dsp.samples(0.09)
    creak = dsp.saw(np.linspace(380, 520, n)) * dsp.attack_decay(n, 0.01, 0.05)
    creak = dsp.filt(creak, "band", 900, 700)
    mix = dsp.place(mix, creak, 0.02, 0.5)
    return dsp.fade(dsp.place(mix, _thud(rng, 140, 0.1), 0.07, 0.7), 0.001, 0.03)


def reload_shotgun_shells(rng: np.random.Generator) -> np.ndarray:
    """Two shells dropped into the chambers: brass thuds with a plastic tick each."""
    mix = None
    for at in (0.0, _jv(rng, 0.11, 0.2)):
        size = dsp.samples(0.1)
        shell = np.zeros(size)
        shell[: dsp.samples(0.07)] += _thud(rng, _jv(rng, 250, 0.1), 0.07) * 0.9
        click = _metal_click(rng, _jv(rng, 1800, 0.06), ring=0.02)[:size]
        shell[: len(click)] += click * 0.5
        mix = dsp.place(mix, shell, at, 0.9)
    return dsp.fade(mix, 0.001, 0.03)


def reload_shotgun_shut(rng: np.random.Generator) -> np.ndarray:
    """The barrels snapped shut: one heavy clack and a thump, the loudest step of the reload."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 520, 0.05), ring=0.07), 0.0, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 120, 0.1), 0.12), 0.0, 0.9)
    return dsp.fade(dsp.place(mix, _rasp(rng, 0.05, 900, 1800) * 0.4, 0.0), 0.001, 0.04)


def _shells_falling(rng: np.random.Generator, count: int, base: float, spread: float, length: float) -> np.ndarray:
    """Empty cases hitting the ground and each other: short high clicks scattered over `spread` seconds, each with
    a bounce or two, fading as they settle."""
    mix = np.zeros(dsp.samples(length))
    for _ in range(count):
        at = rng.uniform(0.0, spread)
        gain = rng.uniform(0.5, 1.0)
        for bounce in range(int(rng.integers(1, 3)) + 1):
            tick = _metal_click(rng, base * rng.uniform(0.85, 1.25), ring=0.012)
            mix = dsp.place(mix, tick, at, gain)
            at += rng.uniform(0.05, 0.09)
            gain *= 0.45
            if at > length - 0.07 or bounce > 2:
                break
    return mix[: dsp.samples(length)]


def reload_pouch(rng: np.random.Generator) -> np.ndarray:
    """The hand at the belt pouch: a leather flap, a snap, and the cloth of the sleeve. The one step every gun shares,
    in the middle of the reload, where the hands are busy and nothing metal sounds (Deadnight #683)."""
    n = dsp.samples(0.26)
    cloth = dsp.filt(dsp.white(rng, 0.26), "band", np.linspace(_jv(rng, 1800, 0.1), 3200, n), 1800)
    cloth = cloth * dsp.attack_decay(n, 0.04, 0.12) * np.abs(0.5 + 0.5 * dsp.filt(dsp.white(rng, 0.26), "low", 40))
    mix = dsp.place(None, cloth, 0.0, 0.8)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 210, 0.1), 0.06), 0.09, 0.6)  # the flap
    snap = dsp.filt(dsp.white(rng, 0.02), "band", _jv(rng, 2600, 0.08), 1500) * dsp.decay(dsp.samples(0.02), 0.004)
    mix = dsp.place(mix, snap, 0.1, 1.0)
    return dsp.fade(mix, 0.002, 0.04)


def reload_smg_bolt(rng: np.random.Generator) -> np.ndarray:
    """The tommy gun's cocking knob pulled back: a steel slide, a catch, and the heavy clack of the bolt held open."""
    mix = dsp.place(None, _rasp(rng, _jv(rng, 0.09, 0.1), 900, 2600) * 0.8, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 700, 0.05), ring=0.05), 0.09, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 150, 0.08), 0.1), 0.09, 0.8)
    return dsp.fade(mix, 0.001, 0.03)


def reload_shotgun_eject(rng: np.random.Generator) -> np.ndarray:
    """The extractor kicks both empties out: a sprung ping, then two paper-and-brass cases on the asphalt."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1500, 0.06), ring=0.03), 0.0, 0.9)
    for at in (0.3, _jv(rng, 0.36, 0.05)):
        case = _thud(rng, _jv(rng, 320, 0.1), 0.05) * 0.7
        case[: dsp.samples(0.03)] += _metal_click(rng, _jv(rng, 2400, 0.08), ring=0.01)[: dsp.samples(0.03)] * 0.6
        mix = dsp.place(mix, case, at, 0.8)
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2600, 0.1), ring=0.008), at + rng.uniform(0.06, 0.1), 0.3)
    return dsp.fade(mix, 0.001, 0.03)


def reload_revolver_open(rng: np.random.Generator) -> np.ndarray:
    """The cylinder latch pushed and the crane swung out: a small click, a turning ratchet, a stop."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1700, 0.05), ring=0.02), 0.0, 0.8)
    for i in range(3):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2300, 0.08), ring=0.008), 0.03 + 0.022 * i, 0.35)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 950, 0.05), ring=0.04), 0.1, 0.9)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 260, 0.1), 0.05), 0.1, 0.5), 0.001, 0.03)


def reload_revolver_eject(rng: np.random.Generator) -> np.ndarray:
    """The ejector rod slapped: six brass cases out at once, ringing on the ground."""
    mix = dsp.place(None, _rasp(rng, 0.05, 1800, 3400) * 0.6, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 1300, 0.05), ring=0.03), 0.04, 0.9)
    return dsp.fade(dsp.place(mix, _shells_falling(rng, 6, 3200, 0.16, 0.55), 0.1, 0.9), 0.001, 0.05)


def reload_revolver_rounds(rng: np.random.Generator) -> np.ndarray:
    """A speedloader of six rounds into the chambers: a brass rattle, then the knob turned and the release click."""
    n = dsp.samples(0.07)
    rattle = dsp.filt(dsp.white(rng, 0.07), "band", 3600, 2600) * dsp.attack_decay(n, 0.01, 0.03)
    mix = dsp.place(None, rattle, 0.0, 0.7)
    for i in range(3):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2700, 0.1), ring=0.01), 0.01 + 0.015 * i, 0.4)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 300, 0.1), 0.05), 0.04, 0.6)
    return dsp.fade(dsp.place(mix, _metal_click(rng, _jv(rng, 1400, 0.05), ring=0.025), 0.12, 0.9), 0.001, 0.03)


def reload_revolver_close(rng: np.random.Generator) -> np.ndarray:
    """The cylinder swung home with a flick: one firm snap and the frame's ring."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 820, 0.05), ring=0.06), 0.0, 1.0)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 190, 0.08), 0.08), 0.0, 0.8), 0.001, 0.04)


def _hollow(rng: np.random.Generator, freq: float, length: float) -> np.ndarray:
    """A knock on a light hollow body (the flare gun's alloy barrel, a plastic cartridge): a short resonant tone."""
    n = dsp.samples(length)
    tone = dsp.filt(dsp.white(rng, length), "band", freq, freq * 0.15) * 6.0 + dsp.sine(freq * 0.5, n) * 0.4
    return tone * dsp.decay(n, length * 0.35)


def reload_flare_open(rng: np.random.Generator) -> np.ndarray:
    """The flare gun's latch and its light barrel dropping open: a click and a hollow clunk."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1300, 0.05), ring=0.02), 0.0, 0.8)
    return dsp.fade(dsp.place(mix, _hollow(rng, _jv(rng, 520, 0.08), 0.12), 0.05, 0.9), 0.001, 0.03)


def reload_flare_eject(rng: np.random.Generator) -> np.ndarray:
    """The spent cartridge shaken out: a hollow tok off the barrel and a plastic bounce on the ground."""
    mix = dsp.place(None, _hollow(rng, _jv(rng, 900, 0.08), 0.08), 0.0, 0.8)
    for i, at in enumerate((0.26, 0.36)):
        mix = dsp.place(mix, _hollow(rng, _jv(rng, 1300, 0.1), 0.06), at, 0.7 * (0.5**i))
    return dsp.fade(mix, 0.001, 0.04)


def reload_flare_in(rng: np.random.Generator) -> np.ndarray:
    """A fat cartridge slid into the bore and seated: a soft slide and a hollow thump."""
    mix = dsp.place(None, _rasp(rng, 0.07, 700, 1600) * 0.6, 0.0)
    return dsp.fade(dsp.place(mix, _hollow(rng, _jv(rng, 420, 0.08), 0.12), 0.06, 1.0), 0.001, 0.03)


def reload_flare_shut(rng: np.random.Generator) -> np.ndarray:
    """The barrel flicked shut: a latch snap, the frame's knock and the alloy's hollow ring, lighter than the
    shotgun's but long enough to be heard through gunfire (the first version, 0.04 s, was lost: #683)."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1000, 0.05), ring=0.1), 0.0, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 190, 0.08), 0.16), 0.0, 0.9)
    mix = dsp.place(mix, _hollow(rng, _jv(rng, 700, 0.08), 0.5), 0.0, 1.0)
    # The latch catching a moment after the barrel meets the frame.
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 1500, 0.05), ring=0.05), 0.035, 0.8)
    return dsp.fade(mix, 0.001, 0.05)


# ---- the generator ----------------------------------------------------------------------------------------------


def generator_sputter(rng: np.random.Generator) -> np.ndarray:
    """A starving engine: uneven strokes with dropouts, a rough pitch that sags, and a backfire at the end."""
    seconds = 1.6
    n = dsp.samples(seconds)
    mix = np.zeros(n)
    at = 0.0
    gap = 0.07
    while at < seconds - 0.4:
        if rng.random() < 0.7:
            m = dsp.samples(0.09)
            thump = dsp.sine(np.geomspace(_jv(rng, 95, 0.1), 45, m)) * dsp.decay(m, 0.04)
            puff = dsp.filt(dsp.white(rng, 0.09), "low", 900) * dsp.decay(m, 0.03)
            mix = dsp.place(mix, thump + 0.8 * puff, at, rng.uniform(0.4, 1.0))[:n]
        at += gap
        gap = min(gap * rng.uniform(1.05, 1.5), 0.28)
    pop_m = dsp.samples(0.22)
    pop = dsp.filt(dsp.white(rng, 0.22), "band", 700, 1400) * dsp.decay(pop_m, 0.05)
    pop += dsp.sine(np.geomspace(140, 50, pop_m)) * dsp.decay(pop_m, 0.08)
    mix = dsp.place(mix, dsp.drive(pop, 2.0), seconds - 0.38, 1.1)[:n]
    return dsp.fade(mix, 0.003, 0.08)


def generator_down(rng: np.random.Generator) -> np.ndarray:
    """The tank runs dry: strokes slow to single thumps, the 60 Hz hum winds down to nothing, a relay drops out, and the
    lamps' buzz ends on a last dull clunk."""
    seconds = 3.4
    n = dsp.samples(seconds)
    rate = dsp.curve([(0, 24), (0.2, 15), (0.5, 7), (0.8, 2.5), (1, 1)], n)
    firing = (np.cumsum(rate) / SAMPLE_RATE) % 1.0
    stroke = np.exp(-firing * 7) * dsp.curve([(0, 1), (0.8, 0.7), (1, 0)], n)
    noise = dsp.filt(rng.normal(0, 1, n), "low", np.linspace(800, 120, n))
    noise /= np.abs(noise).max()
    hz = dsp.curve([(0, 60), (0.3, 54), (0.7, 30), (1, 6)], n)
    level = dsp.curve([(0, 0.55), (0.6, 0.35), (1, 0)], n)
    hum = (
        np.sin(2 * np.pi * np.cumsum(hz) / SAMPLE_RATE) + 0.5 * np.sin(4 * np.pi * np.cumsum(hz) / SAMPLE_RATE)
    ) * level
    buzz = dsp.sine(np.geomspace(120, 40, n)) * dsp.curve([(0, 0.15), (0.5, 0.1), (1, 0)], n)
    mix = noise * stroke * 0.8 + hum * 0.8 + buzz
    mix = dsp.place(mix, _metal_click(rng, 600, ring=0.05), 0.55, 0.5)[:n]
    mix = dsp.place(mix, _thud(rng, 90, 0.2), seconds - 0.7, 0.7)[:n]
    return dsp.fade(mix, 0.005, 0.15)


def _breaker(rng: np.random.Generator, closing: bool) -> np.ndarray:
    """A knife switch thrown: the handle's clunk and the contacts. Closing arcs with a zap; opening just drops."""
    mix = dsp.place(None, _thud(rng, _jv(rng, 85 if closing else 110, 0.08), 0.18), 0.0, 1.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 480 if closing else 640, 0.05), ring=0.08), 0.0, 1.0)
    if closing:
        n = dsp.samples(0.16)
        zap = dsp.filt(dsp.white(rng, 0.16), "high", 2500) * dsp.decay(n, 0.05)
        zap *= 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 120 * dsp.t_axis(0.16)))
        mix = dsp.place(mix, zap, 0.025, 0.5)
    else:
        mix = dsp.place(mix, _rasp(rng, 0.06, 900, 600) * 0.5, 0.05)
    return dsp.fade(mix, 0.0005, 0.05)


def breaker_on(rng: np.random.Generator) -> np.ndarray:
    return _breaker(rng, True)


def breaker_off(rng: np.random.Generator) -> np.ndarray:
    return _breaker(rng, False)


# ---- the shop ---------------------------------------------------------------------------------------------------


def door_unlock(rng: np.random.Generator) -> np.ndarray:
    """A padlock and chain: a rattle of links, the shackle springing, the bolt's clunk."""
    mix = None
    at = 0.0
    for _ in range(int(rng.integers(4, 7))):
        link = _metal_click(rng, _jv(rng, 2200, 0.2), ring=0.015)
        mix = dsp.place(mix, link, at, rng.uniform(0.3, 0.7))
        at += rng.uniform(0.025, 0.06)
    mix = dsp.place(mix, _metal_click(rng, 1000, ring=0.04), at + 0.05, 0.9)
    mix = dsp.place(mix, _metal_click(rng, 460, ring=0.07), at + 0.2, 1.0)
    mix = dsp.place(mix, _thud(rng, 100, 0.12), at + 0.2, 0.8)
    return dsp.fade(mix, 0.001, 0.05)


def buy_weapon(rng: np.random.Generator) -> np.ndarray:
    """A gun lifted off its rack: a wooden clack of the peg, a slide of metal and a ready click."""
    mix = dsp.place(None, _thud(rng, _jv(rng, 190, 0.1), 0.07), 0.0, 0.8)
    mix = dsp.place(mix, _rasp(rng, 0.14, 900, 2600) * 0.7, 0.02)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 760, 0.05), ring=0.05), 0.2, 1.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 1300, 0.05), ring=0.03), 0.29, 0.8)
    return dsp.fade(mix, 0.001, 0.05)


def buy_ammo(rng: np.random.Generator) -> np.ndarray:
    """A steel locker: latch, door swing and a handful of brass rattling in a tray."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 700, 0.06), ring=0.05), 0.0, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 100, 0.1), 0.16), 0.01, 0.9)
    at = 0.12
    for _ in range(int(rng.integers(7, 11))):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2900, 0.25), ring=0.012), at, rng.uniform(0.15, 0.5))
        at += rng.uniform(0.012, 0.045)
    return dsp.fade(mix, 0.001, 0.06)


def buy_fuel(rng: np.random.Generator) -> np.ndarray:
    """Fuel poured from a can: glugs that thin out, over a tin's hollow thunk."""
    seconds = 1.5
    n = dsp.samples(seconds)
    glug_rate = dsp.curve([(0, 7), (0.7, 9), (1, 14)], n)
    glug = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(glug_rate) / SAMPLE_RATE)
    centre = dsp.curve([(0, 520), (1, 900)], n)
    body = dsp.filt(dsp.white(rng, seconds), "band", centre, centre) * glug**2
    body *= dsp.curve([(0, 0), (0.05, 1), (0.8, 0.8), (1, 0)], n)
    mix = dsp.place(body * 1.4, _thud(rng, 150, 0.1), 0.0, 0.6)[:n]
    mix = dsp.place(mix, _metal_click(rng, 1100, ring=0.04), seconds - 0.1, 0.5)[:n]
    return dsp.fade(mix, 0.005, 0.1)


def buy_tonic(rng: np.random.Generator) -> np.ndarray:
    """A bottle opened and a swallow: cork pop, a glass clink, a throat's gulp."""
    pop_n = dsp.samples(0.08)
    pop = dsp.sine(np.geomspace(900, 300, pop_n)) * dsp.decay(pop_n, 0.025)
    pop += dsp.filt(dsp.white(rng, 0.08), "band", 1500, 1500) * dsp.decay(pop_n, 0.015) * 0.6
    mix = dsp.place(None, pop, 0.0, 1.0)
    mix = dsp.place(mix, _metal_click(rng, 3100, ring=0.05) * 0.5, 0.15, 0.6)
    gulp_n = dsp.samples(0.2)
    gulp = dsp.sine(np.geomspace(160, 90, gulp_n)) * dsp.attack_decay(gulp_n, 0.02, 0.1)
    gulp += dsp.filt(dsp.white(rng, 0.2), "band", 400, 400) * dsp.attack_decay(gulp_n, 0.03, 0.08) * 0.7
    mix = dsp.place(mix, gulp, 0.32, 0.7)
    return dsp.fade(mix, 0.001, 0.05)


def buy_recut(rng: np.random.Generator) -> np.ndarray:
    """The re-cut bench: the reels' motor winds up, the press groans down, strikes at 0.8 s with a hot hiss and
    a shower of sparks, the sprockets ratchet round as it lets go, and a bell says it is done at 1.55 s."""
    seconds = 2.5
    n = dsp.samples(seconds)
    # The reels' motor: a sawtooth that climbs 70 to 210 Hz in 0.8 s, hums, and sags at the end.
    hz = dsp.curve([(0, 70), (0.3, 210), (0.7, 190), (1, 120)], n)
    motor = dsp.filt(dsp.saw(hz, n), "low", 700) * 0.5 + dsp.sine(hz * 0.5, n) * 0.4
    motor *= dsp.curve([(0, 0), (0.04, 0.7), (0.65, 0.8), (0.9, 0.25), (1, 0)], n)
    mix = dsp.place(None, motor, 0.0, 0.5)[:n]
    # The press coming down: a low groan, then the blow.
    groan_n = dsp.samples(0.4)
    groan = dsp.sine(np.linspace(150, 60, groan_n)) * dsp.attack_decay(groan_n, 0.05, 0.3)
    groan += _rasp(rng, 0.4, 300, 1400) * 0.5
    mix = dsp.place(mix, groan, 0.4, 0.7)[:n]
    mix = dsp.place(mix, _thud(rng, 70, 0.28), 0.8, 1.0)[:n]
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 520, 0.05), ring=0.09), 0.8, 0.9)[:n]
    # Hot metal: a hiss that dies in half a second, with sparks spitting in it.
    hiss_n = dsp.samples(0.6)
    hiss = dsp.filt(dsp.white(rng, 0.6), "high", 4500) * dsp.decay(hiss_n, 0.22)
    mix = dsp.place(mix, hiss, 0.8, 0.45)[:n]
    for _ in range(int(rng.integers(10, 15))):
        mix = dsp.place(
            mix, _metal_click(rng, _jv(rng, 4200, 0.3), ring=0.006), 0.8 + rng.uniform(0.0, 0.5), rng.uniform(0.1, 0.35)
        )[:n]
    # The sprockets ratcheting as the press lifts: clicks that slow down.
    at, gap = 1.05, 0.03
    while at < 1.5:
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 1800, 0.1), ring=0.012), at, 0.4)[:n]
        at += gap
        gap *= 1.18
    mix = dsp.place(mix, _bell(1567.98, 0.8, ring=0.5), 1.55, 0.45)[:n]
    mix = dsp.place(mix, _bell(2093.0, 0.6, ring=0.35), 1.6, 0.25)[:n]
    return dsp.fade(dsp.room_tail(rng, mix, 0.5, wet=0.15, dark=5000), 0.003, 0.15)


def deny(rng: np.random.Generator) -> np.ndarray:
    """A game-show buzzer, but dull: two low square pulses through a band-pass, and a relay clack before them."""
    mix = dsp.place(None, _metal_click(rng, 900, ring=0.02), 0.0, 0.6)
    for at in (0.03, 0.2):
        n = dsp.samples(0.14)
        buzz = dsp.pulse(np.linspace(130, 110, n), 0.5) + 0.5 * dsp.pulse(np.linspace(196, 165, n), 0.4)
        buzz = dsp.filt(buzz, "band", 520, 700) * dsp.attack_decay(n, 0.003, 0.09)
        mix = dsp.place(mix, buzz, at, 0.9)
    return dsp.fade(mix, 0.001, 0.04)


def _bell(hz: float, seconds: float, bright: float = 1.6, ring: float = 0.25) -> np.ndarray:
    """An FM bell: a sine whose phase is bent by a decaying modulator at a non-integer ratio."""
    n = dsp.samples(seconds)
    mod = dsp.sine(hz * 1.41, n) * dsp.decay(n, ring * 0.5) * bright
    return np.sin(2 * np.pi * dsp.phase_of(np.full(n, hz)) + mod) * dsp.attack_decay(n, 0.001, ring)


def crane_spin(rng: np.random.Generator) -> np.ndarray:
    """The wheel of prizes: a carnival organ jingle that starts frantic and slows to a stop, with the wheel's
    ratchet ticking under each note. The notes walk a major pentatonic scale; the gaps grow by a fixed ratio."""
    scale = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    mix = np.zeros(dsp.samples(5.4))
    at, gap, degree = 0.0, 0.085, 2
    while at < 4.6:
        degree = int(np.clip(degree + rng.choice([-2, -1, 1, 2]), 0, len(scale) - 1))
        hz = scale[degree] * (1.0 - 0.04 * at / 4.6)  # the pitch sags as the wheel tires
        n = dsp.samples(min(gap * 1.6, 0.4))
        organ = dsp.pulse(hz, 0.3, n) * 0.5 + dsp.sine(hz * 2, n) * 0.3
        organ = dsp.filt(organ, "low", 3200) * dsp.attack_decay(n, 0.004, gap * 1.2)
        mix = dsp.place(mix, organ, at, 0.5)[: len(mix)]
        mix = dsp.place(mix, _metal_click(rng, 2400, ring=0.008), at, 0.25)[: len(mix)]
        at += gap
        gap *= 1.085
    mix = dsp.place(mix, _bell(1046.5, 0.5, ring=0.3), at, 0.4)[: len(mix)]
    return dsp.fade(dsp.room_tail(rng, mix, 0.5, wet=0.2, dark=5000), 0.002, 0.15)


def crane_claw_drop(rng: np.random.Generator) -> np.ndarray:
    """The claw lowered on its cable: a motor whine that falls, a ratchet, a soft clack as it touches the heap."""
    seconds = 1.1
    n = dsp.samples(seconds)
    hz = np.linspace(520, 260, n)
    motor = dsp.filt(dsp.saw(hz, n), "low", 1500) * dsp.curve([(0, 0), (0.05, 0.6), (0.85, 0.5), (1, 0)], n)
    mix = motor * (0.8 + 0.2 * np.sin(2 * np.pi * 14 * dsp.t_axis(seconds)))
    for i in range(14):
        mix = dsp.place(mix, _metal_click(rng, 1700, ring=0.01), 0.04 + i * 0.062, 0.25)[:n]
    mix = dsp.place(mix, _metal_click(rng, 420, ring=0.05), seconds - 0.14, 0.9)[:n]
    mix = dsp.place(mix, _thud(rng, 120, 0.1), seconds - 0.14, 0.7)[:n]
    return dsp.fade(mix, 0.003, 0.06)


def crane_claw_lift(rng: np.random.Generator) -> np.ndarray:
    """The claw closing and hauling up: a grip clack, then a motor whine that climbs and a swaying creak."""
    seconds = 1.2
    n = dsp.samples(seconds)
    mix = dsp.place(None, _metal_click(rng, 560, ring=0.06), 0.0, 1.0)
    mix = dsp.place(mix, _thud(rng, 150, 0.1), 0.0, 0.7)
    lift_n = dsp.samples(seconds - 0.12)
    hz = np.linspace(240, 540, lift_n)
    motor = dsp.filt(dsp.saw(hz, lift_n), "low", 1500) * dsp.curve([(0, 0), (0.1, 0.6), (0.9, 0.5), (1, 0)], lift_n)
    mix = dsp.place(mix, motor * (0.8 + 0.2 * np.sin(2 * np.pi * 12 * dsp.t_axis(seconds - 0.12))), 0.12, 0.8)
    creak = dsp.filt(dsp.white(rng, 0.5), "band", np.linspace(700, 1100, dsp.samples(0.5)), 250)
    mix = dsp.place(mix, creak * np.sin(np.linspace(0, np.pi, len(creak))) * 0.3, 0.3)
    return dsp.fade(mix[:n], 0.002, 0.08)


def crane_prize(rng: np.random.Generator) -> np.ndarray:
    """The prize ding: a till bell struck twice, a fifth apart, over a glitter of tiny high chimes."""
    mix = None
    for at, hz in ((0.0, 1318.5), (0.11, 1975.5)):
        mix = dsp.place(mix, _bell(hz, 1.1, ring=0.7), at, 0.6)
    for _ in range(14):
        hz = float(rng.choice([2637.0, 3135.9, 3951.1, 5274.0]))
        mix = dsp.place(mix, _bell(hz, 0.25, 0.8, 0.12), 0.12 + rng.uniform(0, 0.5), rng.uniform(0.05, 0.18))
    return dsp.fade(dsp.room_tail(rng, mix, 0.6, wet=0.25, dark=6000), 0.0008, 0.2)


def crane_break(rng: np.random.Generator) -> np.ndarray:
    """The machine fails: the motor coughs and sputters, electric zaps crackle, a relay drops and the whine dies."""
    seconds = 2.6
    n = dsp.samples(seconds)
    t = dsp.t_axis(seconds)
    hz = dsp.curve([(0, 300), (0.35, 240), (0.7, 120), (1, 30)], n)
    motor = dsp.filt(dsp.saw(hz, n), "low", 1100) * dsp.curve([(0, 0.6), (0.6, 0.4), (1, 0)], n)
    stutter = (np.sin(2 * np.pi * np.cumsum(dsp.curve([(0, 9), (1, 3)], n)) / SAMPLE_RATE) > -0.2).astype(float)
    mix = motor * (0.4 + 0.6 * dsp.filt(stutter, "low", 40))
    for _ in range(int(rng.integers(9, 14))):
        at = rng.uniform(0.05, 1.9)
        m = dsp.samples(rng.uniform(0.04, 0.12))
        zap = dsp.filt(dsp.white(rng, m / SAMPLE_RATE), "high", 2500) * dsp.decay(m, 0.05)
        zap *= 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 100 * np.arange(m) / SAMPLE_RATE))
        mix = dsp.place(mix, zap, at, rng.uniform(0.3, 0.8))[:n]
    mix = dsp.place(mix, _metal_click(rng, 520, ring=0.06), 1.5, 0.8)[:n]
    mix = dsp.place(mix, _thud(rng, 80, 0.2), seconds - 0.6, 0.7)[:n]
    return dsp.fade(mix + 0.0 * t, 0.003, 0.15)


def crane_move(rng: np.random.Generator) -> np.ndarray:
    """The machine carried off to a new spot: a whoosh that rises and falls past the ear, a rumble of wheels and a
    last clunk as it sets down."""
    seconds = 1.5
    n = dsp.samples(seconds)
    centre = dsp.curve([(0, 500), (0.45, 3200), (1, 450)], n)
    air = dsp.filt(dsp.white(rng, seconds), "band", centre, centre * 0.9)
    air *= np.sin(np.linspace(0, np.pi, n)) ** 1.4 * 1.8
    rumble = dsp.filt(dsp.white(rng, seconds), "low", 180) * np.sin(np.linspace(0, np.pi, n)) ** 0.8 * 1.2
    mix = air + rumble
    mix = dsp.place(mix, _thud(rng, 90, 0.2), seconds - 0.25, 1.0)[:n]
    mix = dsp.place(mix, _metal_click(rng, 600, ring=0.06), seconds - 0.25, 0.6)[:n]
    return dsp.fade(mix, 0.01, 0.1)


def points_tick(rng: np.random.Generator) -> np.ndarray:
    """A coin on a counter: one bright tick."""
    n = dsp.samples(0.07)
    tone = dsp.sine(_jv(rng, 3300, 0.03), n) + 0.5 * dsp.sine(_jv(rng, 5100, 0.03), n)
    return dsp.fade(tone * dsp.attack_decay(n, 0.0008, 0.03), 0.0005, 0.01)


def points_kill(rng: np.random.Generator) -> np.ndarray:
    """A till bell for a kill: two quick FM chimes, the second a fifth up."""
    mix = None
    for at, hz in ((0.0, 1480.0), (0.07, 2220.0)):
        m = dsp.samples(0.45)
        mod = dsp.sine(hz * 1.41, m) * dsp.decay(m, 0.1) * 1.6
        bell = np.sin(2 * np.pi * dsp.phase_of(np.full(m, hz)) + mod) * dsp.attack_decay(m, 0.001, 0.25)
        mix = dsp.place(mix, bell, at, 0.6)
    return dsp.fade(mix, 0.0005, 0.08)


# ---- the tense bed ----------------------------------------------------------------------------------------------

BED_SECONDS = 8.0  # every component is a whole number of cycles in this, so the loop has no seam


def _periodic_lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SAMPLE_RATE)
    return np.fft.irfft(spectrum / (1 + (freqs / cutoff) ** 4), len(x))


def bed_tension(rng: np.random.Generator) -> np.ndarray:
    """The round's pulse, kept quiet: a low drone of two close notes beating against each other, a tritone that breathes
    in and out, and a slow double heartbeat. Frequencies are multiples of 1/8 Hz so the loop closes."""
    t = dsp.t_axis(BED_SECONDS)
    n = len(t)
    drone = np.sin(2 * np.pi * 49.0 * t) + 0.8 * np.sin(2 * np.pi * 51.5 * t) + 0.3 * np.sin(2 * np.pi * 98.0 * t)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * t - 1.0)
    tritone = np.sin(2 * np.pi * 233.0 * t) * 0.5 + np.sin(2 * np.pi * 329.625 * t + 0.4) * 0.35
    tritone *= swell**2 * 0.12
    wind = _periodic_lowpass(rng.normal(0, 1, n), 380)
    wind = wind / np.abs(wind).max() * (0.3 + 0.3 * np.sin(2 * np.pi * 0.375 * t))
    phase = (t * 0.5) % 1.0  # a double thump every two seconds
    beat = np.exp(-phase * 30) * np.minimum(phase / 0.01, 1.0) + 0.6 * np.exp(-np.maximum(phase - 0.14, 0) * 30) * (
        phase > 0.14
    )
    thump = np.sin(2 * np.pi * 52.0 * t) * beat * 0.55
    return drone * 0.22 + tritone + wind * 0.25 + thump


# ---- registry ---------------------------------------------------------------------------------------------------


def _report(name: str):
    return lambda rng: report(rng, REPORTS[name])


def _tail(name: str):
    return lambda rng: tail(rng, TAILS[name])


REGISTRY: list[Entry] = [
    *(Entry("guns", f"shot_{name}", 5, _report(name), -1.0) for name in REPORTS),
    *(Entry("guns", f"tail_{name}", 3, _tail(name), -4.0) for name in TAILS),
    Entry("guns", "shot_flare", 3, flare_shot, -2.0),
    Entry("guns", "burst_flare", 2, flare_burst, -4.0),
    Entry("guns", "weapon_swap", 3, weapon_swap, -6.0),
    Entry("guns", "impact_flesh", 4, impact_flesh, -4.0),
    Entry("guns", "impact_head", 4, impact_head, -3.0),
    Entry("guns", "impact_world", 4, impact_world, -5.0),
    Entry("guns", "reload_smg_mag_out", 2, reload_smg_mag_out, -5.0),
    Entry("guns", "reload_smg_mag_in", 2, reload_smg_mag_in, -4.0),
    Entry("guns", "reload_rifle_round", 3, reload_rifle_round, -6.0),
    Entry("guns", "reload_rifle_lever", 2, reload_rifle_lever, -4.0),
    Entry("guns", "reload_shotgun_open", 2, reload_shotgun_open, -5.0),
    Entry("guns", "reload_shotgun_shells", 2, reload_shotgun_shells, -5.0),
    Entry("guns", "reload_shotgun_shut", 2, reload_shotgun_shut, -3.0),
    Entry("guns", "reload_shotgun_eject", 2, reload_shotgun_eject, -4.0),
    Entry("guns", "reload_smg_bolt", 2, reload_smg_bolt, -4.0),
    Entry("guns", "reload_revolver_open", 2, reload_revolver_open, -4.0),
    Entry("guns", "reload_revolver_eject", 2, reload_revolver_eject, -4.0),
    Entry("guns", "reload_revolver_rounds", 2, reload_revolver_rounds, -4.0),
    Entry("guns", "reload_revolver_close", 2, reload_revolver_close, -3.0),
    Entry("guns", "reload_flare_open", 2, reload_flare_open, -4.0),
    Entry("guns", "reload_flare_eject", 2, reload_flare_eject, -5.0),
    Entry("guns", "reload_flare_in", 2, reload_flare_in, -4.0),
    Entry("guns", "reload_flare_shut", 2, reload_flare_shut, -3.0),
    Entry("guns", "reload_pouch", 3, reload_pouch, -5.0),
    Entry("world", "generator_sputter", 3, generator_sputter, -4.0),
    Entry("world", "generator_down", 1, generator_down, -3.0),
    Entry("world", "breaker_on", 2, breaker_on, -3.0),
    Entry("world", "breaker_off", 2, breaker_off, -3.0),
    Entry("world", "door_unlock", 2, door_unlock, -4.0),
    Entry("world", "buy_weapon", 2, buy_weapon, -4.0),
    Entry("world", "buy_ammo", 2, buy_ammo, -4.0),
    Entry("world", "buy_fuel", 1, buy_fuel, -5.0),
    Entry("world", "buy_tonic", 1, buy_tonic, -5.0),
    Entry("world", "buy_recut", 1, buy_recut, -3.0),
    Entry("world", "deny", 1, deny, -6.0),
    Entry("world", "crane_spin", 1, crane_spin, -4.0),
    Entry("world", "crane_claw_drop", 1, crane_claw_drop, -5.0),
    Entry("world", "crane_claw_lift", 1, crane_claw_lift, -5.0),
    Entry("world", "crane_prize", 1, crane_prize, -4.0),
    Entry("world", "crane_break", 1, crane_break, -4.0),
    Entry("world", "crane_move", 1, crane_move, -5.0),
    Entry("ui", "points_tick", 1, points_tick, -12.0),
    Entry("ui", "points_kill", 1, points_kill, -10.0),
    Entry("music", "tension", 1, bed_tension, -8.0, loop=True),
]
