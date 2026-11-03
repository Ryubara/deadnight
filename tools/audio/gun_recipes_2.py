"""The sounds of the second batch of firearms (Deadnight #790): the PPSh, the M249 SAW, the M4A1, the .50 calibre
rifle, the dual pistols, the MP5 and the 870 pump.

Built the way the first guns are, from `weapon_recipes.py`'s own pieces (`report` and `tail`, the shared click, thud
and rasp) and not edited into that file: each gun has a report (`shot_<gun>`, five seeded variants that differ in
their noise and not their note), a tail (`tail_<gun>`), an equip (`equip_<gun>`), a dry click (`dry_<gun>`) and
the steps of its own reload (`reload_<gun>_<step>`). Synthesised, nothing sampled; the rules every firearm follows
(pitch, level, loudness against the night, headroom) are `docs/research/gun-audio.md`.

The gun ids are the catalogue's (#793): `ppsh`, `m249`, `m4a1`, `fifty_cal`, `mp5`, `pump_870`, `dual_pistols`.
"""

from __future__ import annotations

import dsp
import numpy as np
from recipes import Entry, _jv, _metal_click, _rasp, _thud
from weapon_recipes import Report, Tail, report, tail

# ---- reports and tails -----------------------------------------------------------------------------------------

# Each gun sounds like its kind. The numbers are the `Report` of `weapon_recipes.py`: a click, a crack, a roar that
# darkens, a bark, a falling thump and a low note, driven together.
REPORTS = {
    # A fast light SMG: a pistol round at high pressure, so a bright sharp crack over a short thump, with the
    # receiver's ring; it fires faster than any other gun, so every part of it is short.
    "ppsh": Report(
        2200,
        0.007,
        (4600, 700),
        0.07,
        (230, 115),
        0.06,
        115,
        0.06,
        0.18,
        mid_hz=620,
        mid_len=0.045,
        ring=1500,
        gain_crack=0.6,
        gain_boom=2.4,
        gain_body=0.45,
        gain_sub=0.25,
    ),
    # The LMG: the rifle round of the M4A1 through a longer barrel, heavier, a thump that stays and a receiver that
    # rings under it, so a long burst of it chatters.
    "m249": Report(
        1250,
        0.012,
        (3400, 320),
        0.17,
        (135, 58),
        0.14,
        58,
        0.18,
        0.5,
        mid_hz=360,
        mid_len=0.09,
        ring=950,
        gain_crack=0.65,
        gain_boom=2.5,
        gain_body=0.45,
        gain_sub=0.35,
    ),
    # The carbine: a rifle round that cracks, shorter and higher than the SAW, a clean mid bark, no ring.
    "m4a1": Report(
        1750,
        0.011,
        (3700, 420),
        0.12,
        (150, 72),
        0.1,
        72,
        0.12,
        0.36,
        mid_hz=430,
        mid_len=0.075,
        gain_crack=1.0,
        gain_boom=2.5,
        gain_body=0.4,
        gain_sub=0.3,
    ),
    # A huge rifle crack and boom: a long roar, a thump an octave under the rifle's, a note that hangs.
    "fifty_cal": Report(
        850,
        0.022,
        (3000, 170),
        0.5,
        (88, 33),
        0.36,
        35,
        0.5,
        1.2,
        mid_hz=250,
        mid_len=0.2,
        gain_crack=0.6,
        gain_boom=3.2,
        gain_body=0.65,
        gain_sub=0.5,
    ),
    # The MP5: nine millimetres from a closed bolt, tight and dry, darker and meatier than the PPSh and without
    # its ring.
    "mp5": Report(
        1450,
        0.008,
        (3200, 420),
        0.09,
        (175, 88),
        0.08,
        88,
        0.08,
        0.22,
        mid_hz=470,
        mid_len=0.06,
        gain_crack=0.45,
        gain_boom=2.5,
        gain_body=0.55,
        gain_sub=0.3,
    ),
    # One barrel of twelve gauge: the double-barrel's boom with its roar cut shorter and its crack sharper.
    "pump_870": Report(
        1000,
        0.018,
        (3000, 240),
        0.3,
        (118, 46),
        0.24,
        50,
        0.3,
        0.78,
        mid_hz=320,
        mid_len=0.14,
        gain_crack=0.6,
        gain_boom=3.0,
        gain_body=0.5,
        gain_sub=0.4,
    ),
    # Two self-loading pistols: a quick pop, snappier and shorter than the revolver (no cylinder gap to roar in).
    "dual_pistols": Report(
        1700,
        0.01,
        (3600, 450),
        0.11,
        (205, 90),
        0.09,
        82,
        0.1,
        0.34,
        mid_hz=480,
        mid_len=0.06,
        gain_crack=0.65,
        gain_boom=2.5,
        gain_body=0.4,
        gain_sub=0.25,
    ),
}

TAILS = {
    "ppsh": Tail(0.28, 0.18, 4000, gain_echo=0.28),
    "m249": Tail(0.65, 0.26, 3000, gain_echo=0.4),
    "m4a1": Tail(0.55, 0.24, 3300, gain_echo=0.36),
    "fifty_cal": Tail(1.4, 0.34, 2500, gain_echo=0.5),
    "mp5": Tail(0.3, 0.18, 3700, gain_echo=0.28),
    "pump_870": Tail(0.85, 0.25, 2800, gain_echo=0.45),
    "dual_pistols": Tail(0.45, 0.2, 3600, gain_echo=0.33),
}


def _report(name: str):
    return lambda rng: report(rng, REPORTS[name])


def _tail(name: str):
    return lambda rng: tail(rng, TAILS[name])


# ---- the dry click -----------------------------------------------------------------------------------------------


def _dry(rng: np.random.Generator, hz: float, ring: float, weight: float = 0.0, hollow: float = 0.0) -> np.ndarray:
    """The trigger pulled on nothing: a striker or a sear falling, a tick of the frame, and for the heavy guns a
    thud of the bolt or the hammer. The pitch and the ring say what it is."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, hz, 0.04), ring=ring), 0.0, 0.8)
    if weight:
        mix = dsp.place(mix, _thud(rng, _jv(rng, 170, 0.06), 0.06), 0.0, weight)
    if hollow:
        n = dsp.samples(0.08)
        tone = dsp.filt(dsp.white(rng, 0.08), "band", _jv(rng, 700, 0.06), 160) * 5.0 * dsp.decay(n, 0.03)
        mix = dsp.place(mix, tone, 0.002, hollow)
    return dsp.fade(mix, 0.0004, 0.012) * 0.7


def dry_ppsh(rng: np.random.Generator) -> np.ndarray:
    return _dry(rng, 1100, 0.03, weight=0.4)


def dry_m249(rng: np.random.Generator) -> np.ndarray:
    return _dry(rng, 780, 0.05, weight=0.7)


def dry_m4a1(rng: np.random.Generator) -> np.ndarray:
    return _dry(rng, 1300, 0.035, weight=0.25)


def dry_fifty_cal(rng: np.random.Generator) -> np.ndarray:
    return _dry(rng, 620, 0.08, weight=1.0)


def dry_mp5(rng: np.random.Generator) -> np.ndarray:
    return _dry(rng, 1500, 0.025, weight=0.2)


def dry_pump_870(rng: np.random.Generator) -> np.ndarray:
    return _dry(rng, 900, 0.04, weight=0.3, hollow=0.5)


def dry_dual_pistols(rng: np.random.Generator) -> np.ndarray:
    """Two hammers: one click and a second a few hundredths later, a little apart in pitch."""
    mix = dsp.place(None, _dry(rng, 1700, 0.02), 0.0, 1.0)
    return dsp.place(mix, _dry(rng, 1950, 0.02), _jv(rng, 0.05, 0.2), 0.8)


# ---- the equip -----------------------------------------------------------------------------------------------------


def _equip(
    rng: np.random.Generator, thud_hz: float, thud_gain: float, click_hz: float, rustle: float, ring: float
) -> np.ndarray:
    """The gun coming up: a sling's rustle and the weight of it on the shoulder, then the one metal detail a hand
    checks (a charging handle, a safety, a magazine seated). Heavy guns thud lower and rustle longer."""
    mix = dsp.place(None, _rasp(rng, _jv(rng, rustle, 0.1), 500, 1500) * 0.5, 0.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, thud_hz, 0.08), 0.09 + 0.05 * thud_gain), rustle * 0.7, thud_gain)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, click_hz, 0.06), ring=ring), rustle * 0.75, 0.8)
    return dsp.fade(mix, 0.002, 0.03)


def equip_ppsh(rng: np.random.Generator) -> np.ndarray:
    return _equip(rng, 190, 0.7, 900, 0.08, 0.035)


def equip_m249(rng: np.random.Generator) -> np.ndarray:
    mix = _equip(rng, 120, 1.0, 600, 0.14, 0.06)
    # The belt shifting in its box under the receiver.
    for at in (0.12, 0.17, 0.205):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2600, 0.15), ring=0.01), at, 0.25)
    return dsp.fade(mix, 0.002, 0.03)


def equip_m4a1(rng: np.random.Generator) -> np.ndarray:
    return _equip(rng, 170, 0.6, 1100, 0.07, 0.04)


def equip_fifty_cal(rng: np.random.Generator) -> np.ndarray:
    return _equip(rng, 95, 1.0, 520, 0.16, 0.07)


def equip_mp5(rng: np.random.Generator) -> np.ndarray:
    return _equip(rng, 210, 0.5, 1250, 0.06, 0.03)


def equip_pump_870(rng: np.random.Generator) -> np.ndarray:
    """The slide worked once as it comes up: forward-and-back, the ready click of a pump."""
    mix = _equip(rng, 135, 0.8, 800, 0.1, 0.045)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 640, 0.05), ring=0.05), 0.21, 0.9)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 130, 0.08), 0.08), 0.21, 0.7), 0.002, 0.03)


def equip_dual_pistols(rng: np.random.Generator) -> np.ndarray:
    """Two pistols drawn, one a moment after the other."""
    mix = dsp.place(None, _equip(rng, 220, 0.5, 1500, 0.05, 0.025), 0.0, 1.0)
    return dsp.place(mix, _equip(rng, 235, 0.5, 1650, 0.05, 0.025), _jv(rng, 0.07, 0.2), 0.85)


# ---- the reloads -------------------------------------------------------------------------------------------------------


def _mag(rng: np.random.Generator, out: bool, pitch: float, weight: float, ring: float) -> np.ndarray:
    """A magazine leaving (a release click, a slide, a drop into the palm) or arriving (a slide and the seat's clack),
    heavier and longer for a big one. Its own helper, so the first guns' steps are as they were."""
    if out:
        mix = dsp.place(None, _metal_click(rng, _jv(rng, 1200 * pitch, 0.04), ring=ring), 0.0, 0.7)
        mix = dsp.place(mix, _rasp(rng, 0.05 + 0.03 * weight, 1500, 3000) * 0.7, 0.015)
        return dsp.place(
            mix, _thud(rng, _jv(rng, 150 * pitch, 0.06), 0.08 + 0.04 * weight), 0.08 + 0.02 * weight, 0.7 * weight
        )
    mix = dsp.place(None, _rasp(rng, 0.05 + 0.03 * weight, 1400, 2800) * 0.6, 0.0)
    at = 0.05 + 0.03 * weight
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 800 * pitch, 0.04), ring=ring + 0.01), at, 1.0)
    return dsp.place(mix, _thud(rng, _jv(rng, 210 * pitch, 0.06), 0.08 + 0.03 * weight), at, 0.9 * weight)


def _charge(rng: np.random.Generator, pitch: float, weight: float, slap: bool = False) -> np.ndarray:
    """A charging handle drawn and let go: a steel slide, and the bolt slamming home. `slap` is the MP5's: a short
    sharp pull and a flat, bright clap of the handle on its tube."""
    pull = 0.05 if slap else 0.09
    mix = dsp.place(None, _rasp(rng, _jv(rng, pull, 0.1), 900 * pitch, 2600 * pitch) * 0.8, 0.0)
    at = pull + 0.01
    if slap:
        clap = dsp.filt(dsp.white(rng, 0.03), "band", _jv(rng, 2100, 0.05), 1800) * dsp.decay(dsp.samples(0.03), 0.008)
        mix = dsp.place(mix, clap * 2.0, at, 0.9)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 700 * pitch, 0.05), ring=0.04 + 0.02 * weight), at, 1.0)
    return dsp.fade(
        dsp.place(mix, _thud(rng, _jv(rng, 150 * pitch, 0.08), 0.08 + 0.04 * weight), at, 0.8 * weight), 0.001, 0.03
    )


def _rattle(rng: np.random.Generator, count: int, span: float, base: float, gain: float) -> np.ndarray:
    """Loose rounds shifting in a drum or a belt: small high clicks in a bunch, quieter as they settle."""
    mix = np.zeros(dsp.samples(span + 0.07))
    for i in range(count):
        at = rng.uniform(0.0, span)
        mix = dsp.place(
            mix,
            _metal_click(rng, _jv(rng, base, 0.2), ring=0.01),
            at,
            gain * rng.uniform(0.4, 1.0) * (1 - 0.5 * i / count),
        )
    return mix


def reload_ppsh_drum_out(rng: np.random.Generator) -> np.ndarray:
    """The drum's catch, and the round drum pulled down off the receiver with its rounds rattling inside."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 950, 0.04), ring=0.04), 0.0, 0.8)
    mix = dsp.place(mix, _rasp(rng, 0.09, 1200, 2400) * 0.7, 0.02)
    mix = dsp.place(mix, _rattle(rng, 8, 0.12, 2800, 0.35), 0.06)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 130, 0.06), 0.12), 0.12, 0.8), 0.001, 0.03)


def reload_ppsh_drum_in(rng: np.random.Generator) -> np.ndarray:
    """The drum pushed up into the well: a slide, a spring's few ticks, and a hollow seat with a ring."""
    mix = dsp.place(None, _rasp(rng, 0.09, 1300, 2700) * 0.6, 0.0)
    mix = dsp.place(mix, _rattle(rng, 6, 0.08, 3000, 0.3), 0.03)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 700, 0.04), ring=0.07), 0.1, 1.0)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 170, 0.06), 0.1), 0.1, 0.9), 0.001, 0.03)


def reload_ppsh_bolt(rng: np.random.Generator) -> np.ndarray:
    return _charge(rng, 1.1, 0.7)


def reload_m249_cover_open(rng: np.random.Generator) -> np.ndarray:
    """The feed tray's latch and its cover flipped up: a click, then a flat plate of steel ringing as it swings."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1100, 0.04), ring=0.03), 0.0, 0.7)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 430, 0.05), ring=0.12), 0.05, 1.0)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 120, 0.06), 0.12), 0.05, 0.8), 0.001, 0.05)


def reload_m249_belt(rng: np.random.Generator) -> np.ndarray:
    """The belt laid in the tray: its links chinking over each other as the length of it is drawn across, and the
    first round dropped into the feed."""
    mix = np.zeros(dsp.samples(0.5))
    at = 0.0
    for _ in range(int(rng.integers(11, 15))):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, 2500, 0.2), ring=0.012), at, rng.uniform(0.5, 1.0))
        at += rng.uniform(0.012, 0.03)
    mix = dsp.place(mix, _rasp(rng, 0.2, 1800, 3400) * 0.6, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 1000, 0.05), ring=0.03), at + 0.02, 0.9)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 190, 0.08), 0.07), at + 0.02, 0.7), 0.001, 0.04)


def reload_m249_cover_shut(rng: np.random.Generator) -> np.ndarray:
    """The cover slammed down on the belt: the heaviest step, a flat clang and a thump, the latch catching a
    moment after."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 470, 0.05), ring=0.1), 0.0, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 105, 0.06), 0.14), 0.0, 1.0)
    mix = dsp.place(mix, _rasp(rng, 0.05, 900, 1800) * 0.4, 0.0)
    return dsp.fade(dsp.place(mix, _metal_click(rng, _jv(rng, 1250, 0.05), ring=0.03), 0.045, 0.7), 0.001, 0.05)


def reload_m249_charge(rng: np.random.Generator) -> np.ndarray:
    return _charge(rng, 0.85, 1.0)


def reload_m4a1_mag_out(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag(rng, True, 1.0, 0.9, 0.03), 0.001, 0.02)


def reload_m4a1_mag_in(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag(rng, False, 1.0, 0.9, 0.04), 0.001, 0.02)


def reload_m4a1_bolt(rng: np.random.Generator) -> np.ndarray:
    """The bolt catch slapped: the carrier flying forward with a sharp clack and a ring of the upper receiver."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 1900, 0.05), ring=0.012), 0.0, 0.5)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 860, 0.05), ring=0.05), 0.012, 1.0)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 160, 0.08), 0.08), 0.012, 0.7), 0.001, 0.03)


def reload_fifty_mag_out(rng: np.random.Generator) -> np.ndarray:
    """A big box magazine freed: a heavy catch, a long slide and a deep thump as it is dropped."""
    return dsp.fade(_mag(rng, True, 0.62, 1.4, 0.06), 0.001, 0.04)


def reload_fifty_mag_in(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag(rng, False, 0.6, 1.5, 0.07), 0.001, 0.04)


def reload_fifty_bolt(rng: np.random.Generator) -> np.ndarray:
    """The bolt handle of a huge rifle: lifted with a click, dragged back, slammed forward, turned down with a last
    heavy clack. Four events over about half a second."""
    mix = dsp.place(None, _metal_click(rng, _jv(rng, 700, 0.04), ring=0.05), 0.0, 0.8)
    mix = dsp.place(mix, _rasp(rng, _jv(rng, 0.14, 0.1), 600, 1800), 0.05, 0.8)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 480, 0.04), ring=0.08), 0.25, 1.0)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 95, 0.06), 0.14), 0.25, 1.0)
    return dsp.fade(dsp.place(mix, _metal_click(rng, _jv(rng, 620, 0.04), ring=0.06), 0.38, 0.9), 0.001, 0.05)


def reload_mp5_mag_out(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag(rng, True, 1.1, 0.6, 0.025), 0.001, 0.02)


def reload_mp5_mag_in(rng: np.random.Generator) -> np.ndarray:
    return dsp.fade(_mag(rng, False, 1.1, 0.6, 0.035), 0.001, 0.02)


def reload_mp5_bolt(rng: np.random.Generator) -> np.ndarray:
    return _charge(rng, 1.15, 0.5, slap=True)


def reload_pump_shell(rng: np.random.Generator) -> np.ndarray:
    """One shell pushed into the tube's loading gate: the plastic of the hull on the carrier, a brass tick and the
    spring's small clack. It sounds once for each shell of the reload."""
    mix = dsp.place(None, _rasp(rng, 0.03, 1500, 2600) * 0.4, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 1850, 0.06), ring=0.02), 0.025, 0.8)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 270, 0.1), 0.06), 0.025, 0.7)
    return dsp.fade(dsp.place(mix, _metal_click(rng, _jv(rng, 2500, 0.06), ring=0.01), 0.065, 0.4), 0.001, 0.02)


def reload_pump_stroke(rng: np.random.Generator) -> np.ndarray:
    """The forend racked: back with a slide of steel and a clack, a beat for the shell to rise, then forward and
    shut with the heavier clack."""
    mix = dsp.place(None, _rasp(rng, _jv(rng, 0.09, 0.1), 700, 2200) * 0.7, 0.0)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 720, 0.05), ring=0.05), 0.09, 0.9)
    mix = dsp.place(mix, _thud(rng, _jv(rng, 140, 0.08), 0.08), 0.09, 0.6)
    mix = dsp.place(mix, _rasp(rng, _jv(rng, 0.08, 0.1), 2200, 900) * 0.6, 0.23)
    mix = dsp.place(mix, _metal_click(rng, _jv(rng, 540, 0.05), ring=0.07), 0.31, 1.0)
    return dsp.fade(dsp.place(mix, _thud(rng, _jv(rng, 118, 0.08), 0.12), 0.31, 0.9), 0.001, 0.04)


def reload_dual_mag_out(rng: np.random.Generator) -> np.ndarray:
    """Both magazines dropped: two small releases and two light thumps, the second hand a hair behind."""
    mix = dsp.place(None, _mag(rng, True, 1.15, 0.5, 0.025), 0.0, 1.0)
    return dsp.fade(dsp.place(mix, _mag(rng, True, 1.25, 0.5, 0.025), _jv(rng, 0.045, 0.2), 0.85), 0.001, 0.02)


def reload_dual_mag_in(rng: np.random.Generator) -> np.ndarray:
    mix = dsp.place(None, _mag(rng, False, 1.15, 0.5, 0.03), 0.0, 1.0)
    return dsp.fade(dsp.place(mix, _mag(rng, False, 1.25, 0.5, 0.03), _jv(rng, 0.06, 0.2), 0.85), 0.001, 0.02)


def reload_dual_slide(rng: np.random.Generator) -> np.ndarray:
    """Both slides let go: two bright snaps of the frames, one just after the other."""
    mix = None
    for at, hz in ((0.0, 1100), (_jv(rng, 0.07, 0.2), 1260)):
        mix = dsp.place(mix, _metal_click(rng, _jv(rng, hz, 0.04), ring=0.035), at, 1.0)
        mix = dsp.place(mix, _thud(rng, _jv(rng, 190, 0.06), 0.05), at, 0.5)
    return dsp.fade(mix, 0.001, 0.03)


# ---- registry ---------------------------------------------------------------------------------------------------

EQUIP = {
    "ppsh": equip_ppsh,
    "m249": equip_m249,
    "m4a1": equip_m4a1,
    "fifty_cal": equip_fifty_cal,
    "mp5": equip_mp5,
    "pump_870": equip_pump_870,
    "dual_pistols": equip_dual_pistols,
}
DRY = {
    "ppsh": dry_ppsh,
    "m249": dry_m249,
    "m4a1": dry_m4a1,
    "fifty_cal": dry_fifty_cal,
    "mp5": dry_mp5,
    "pump_870": dry_pump_870,
    "dual_pistols": dry_dual_pistols,
}

# (sound name, recipe, file peak dB). The steps are never louder than the first guns' loudest step (the SMG's
# magazine going in, #718): how heavy a step is says in its length and its low end, not in a hotter file.
RELOADS = [
    ("reload_ppsh_drum_out", reload_ppsh_drum_out, -5.0),
    ("reload_ppsh_drum_in", reload_ppsh_drum_in, -4.0),
    ("reload_ppsh_bolt", reload_ppsh_bolt, -4.0),
    ("reload_m249_cover_open", reload_m249_cover_open, -5.0),
    ("reload_m249_belt", reload_m249_belt, -5.0),
    ("reload_m249_cover_shut", reload_m249_cover_shut, -4.0),
    ("reload_m249_charge", reload_m249_charge, -4.0),
    ("reload_m4a1_mag_out", reload_m4a1_mag_out, -5.0),
    ("reload_m4a1_mag_in", reload_m4a1_mag_in, -4.0),
    ("reload_m4a1_bolt", reload_m4a1_bolt, -4.0),
    ("reload_fifty_mag_out", reload_fifty_mag_out, -5.0),
    ("reload_fifty_mag_in", reload_fifty_mag_in, -4.0),
    ("reload_fifty_bolt", reload_fifty_bolt, -4.0),
    ("reload_mp5_mag_out", reload_mp5_mag_out, -5.0),
    ("reload_mp5_mag_in", reload_mp5_mag_in, -4.0),
    ("reload_mp5_bolt", reload_mp5_bolt, -4.0),
    ("reload_pump_shell", reload_pump_shell, -6.0),
    ("reload_pump_stroke", reload_pump_stroke, -4.0),
    ("reload_dual_mag_out", reload_dual_mag_out, -5.0),
    ("reload_dual_mag_in", reload_dual_mag_in, -4.0),
    ("reload_dual_slide", reload_dual_slide, -4.0),
]

REGISTRY: list[Entry] = [
    *(Entry("guns", f"shot_{name}", 5, _report(name), -1.0) for name in REPORTS),
    *(Entry("guns", f"tail_{name}", 3, _tail(name), -4.0) for name in TAILS),
    *(Entry("guns", f"equip_{name}", 2, recipe, -6.0) for name, recipe in EQUIP.items()),
    *(Entry("guns", f"dry_{name}", 2, recipe, -6.0) for name, recipe in DRY.items()),
    *(Entry("guns", name, 2, recipe, peak) for name, recipe, peak in RELOADS),
]
