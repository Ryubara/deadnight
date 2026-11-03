"""The .50 calibre rifle (`fifty_cal`, #796): a semi-automatic anti-materiel rifle of the M82 type
(docs/research/weapon-models.md#50-calibre-rifle-fifty_cal-796).

Drawn at 1.40 m (muzzle -1.05, butt +0.35; the real gun is 1.45 m) with the cross-sections about 1.5-2 times real; the origin is the
pistol grip, behind the trigger (the Tommy gun's grip, guard, trigger and sockets). Its read: the longest gun, the
scope on top, the big double-chamber brake whose two windows each side show through in the outline. The stock is
shorter than the real one's so the butt stays at the shoulder. Studied from public-domain photos
(refs/weapons/fifty_cal/); a generic type, no maker's marks.

The reload's parts are their own nodes: `Magazine` (out down along its own axis) and `Bolt` (the big charging handle
on the right, back +X 0.12).
"""

import math

G, D, K, GL = "Grey", "DarkGrey", "Black", "Glow"
BORE = 0.05
MAG_LEAN = 0.12  # radians: the magazine's foot sits a little forward


def pistol_grip(b, colour=K, guard=D):
    """The Tommy gun's pistol grip, guard (deep enough for the Soldier's finger, #460) and trigger."""
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, colour, bevel=0.008)  # fmt: skip
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, guard)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, K)


def brake(b):
    """The double-chamber muzzle brake: a block built as top, bottom and three walls, so its two windows each side
    are open and show in the outline."""
    x0, x1 = -1.05, -0.92
    top, bottom, w = BORE + 0.05, BORE - 0.05, 0.08
    b.box(((x0 + x1) / 2, 0, top - 0.0125), (x1 - x0, w, 0.025), K, bevel=0.006)
    b.box(((x0 + x1) / 2, 0, bottom + 0.0125), (x1 - x0, w, 0.025), K, bevel=0.006)
    for x, t in ((-1.04, 0.02), (-0.985, 0.024), (-0.93, 0.02)):
        b.box((x, 0, BORE), (t, w, top - bottom), K, bevel=0)
    b.cyl((-1.05, 0, BORE), (-1.054, 0, BORE), 0.014, D, segs=8, bevel=0, detail=True)  # bore


def body(b):
    """Everything that stays put in the reload."""
    brake(b)
    # Barrel with its flutes, the collar where it enters the receiver.
    b.cyl((-0.92, 0, BORE), (-0.40, 0, BORE), 0.028, D, segs=12, bevel=0)
    for a in (0, 90, 180, 270):
        r = math.radians(a)
        b.box((-0.66, 0.026 * math.cos(r), BORE + 0.026 * math.sin(r)), (0.40, 0.012, 0.012), K, bevel=0,
              rot=(r, 0, 0), detail=True)  # fmt: skip
    b.cyl((-0.42, 0, BORE), (-0.45, 0, BORE), 0.036, D, segs=12, bevel=0)
    # Upper receiver: the long slotted box, the longest flat face of the set; a rail on top.
    b.box((-0.17, 0, 0.04), (0.50, 0.076, 0.12), D)
    for y in (-0.039, 0.039):
        for i in range(5):
            b.box((-0.39 + 0.04 * i, y, 0.06), (0.026, 0.004, 0.022), K, bevel=0, detail=True)  # lightening slots
        b.box((-0.05, y, 0.0), (0.024, 0.006, 0.024), K, bevel=0, detail=True)  # takedown pins
    b.box((-0.11, 0, 0.107), (0.36, 0.034, 0.014), K, bevel=0)  # rail
    b.box((-0.05, 0.039, 0.065), (0.07, 0.004, 0.03), K, bevel=0, detail=True)  # ejection port
    # Lower receiver: the magazine well and the trigger housing.
    b.box((-0.135, 0, -0.03), (0.17, 0.07, 0.03), D, bevel=0.006)  # ends ahead of the guard
    pistol_grip(b)
    # Stock: tall, with a cheek line, a black recoil pad and a monopod knob underneath.
    b.prism([(0.07, 0.10), (0.20, 0.09), (0.305, 0.08), (0.315, -0.08), (0.265, -0.088), (0.14, -0.03), (0.07, -0.03)],
            -0.035, 0.035, D, bevel=0.012)  # fmt: skip
    b.box((0.331, 0, 0.0), (0.032, 0.08, 0.18), K, bevel=0.008, rot=(0, -0.06, 0))
    b.box((0.23, 0, -0.078), (0.03, 0.03, 0.02), K, bevel=0, detail=True)
    # Scope on two rings: the objective bell forward, the eyepiece back, a turret on top and on the right.
    sz = 0.175
    for x in (-0.18, -0.02):
        b.box((x, 0, 0.137), (0.024, 0.04, 0.046), G, bevel=0)  # ring bases
        b.cyl((x - 0.012, 0, sz), (x + 0.012, 0, sz), 0.036, G, segs=10, bevel=0, detail=True)  # rings
    b.cyl((-0.21, 0, sz), (0.02, 0, sz), 0.03, K, segs=12, bevel=0)  # tube
    b.cyl((-0.27, 0, sz), (-0.21, 0, sz), 0.046, K, segs=12, bevel=0.006, radius1=0.03)  # objective bell
    b.cyl((-0.27, 0, sz), (-0.274, 0, sz), 0.038, GL, segs=12, bevel=0)  # lens
    b.cyl((0.02, 0, sz), (0.07, 0, sz), 0.03, K, segs=12, bevel=0, radius1=0.038)  # eyepiece
    b.cyl((-0.10, 0, sz + 0.025), (-0.10, 0, sz + 0.05), 0.016, K, segs=8, bevel=0)  # turret
    b.cyl((-0.10, 0.025, sz), (-0.10, 0.045, sz), 0.014, K, segs=8, bevel=0, detail=True)  # windage
    # The bipod folded forward under the barrel: the clamp and two legs ending behind the brake.
    b.box((-0.44, 0, -0.005), (0.04, 0.07, 0.03), K, bevel=0)
    for y in (-0.028, 0.028):
        b.box((-0.59, y, 0.004), (0.30, 0.014, 0.014), D, bevel=0)
        b.box((-0.745, y, 0.004), (0.02, 0.02, 0.03), K, bevel=0, detail=True)  # feet


def magazine(b):
    """The box magazine, Grey so it reads under the dark gun, leaning a little forward."""
    b.box((-0.125, 0, -0.08), (0.12, 0.066, 0.14), G, bevel=0.01, rot=(0, MAG_LEAN, 0))
    b.box(
        (-0.125 - 0.075 * math.sin(MAG_LEAN), 0, -0.152), (0.13, 0.072, 0.014), K, bevel=0, rot=(0, MAG_LEAN, 0)
    )  # floor plate


def bolt(b):
    """The big charging handle on the right of the upper receiver."""
    b.box((-0.06, 0.05, 0.075), (0.03, 0.03, 0.026), K, bevel=0)
    b.cyl((-0.06, 0.06, 0.075), (-0.06, 0.085, 0.075), 0.016, K, segs=8, bevel=0, detail=True)


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Magazine": (magazine, (-0.125, 0.0, -0.02)),  # the top of the well: out down along its own axis
        "Bolt": (bolt, (-0.06, 0.05, 0.075)),  # the handle: slides back +X 0.12
    },
    "muzzle": (-1.05, 0.0, BORE),  # the brake's front face, on the bore
    "eject": (-0.05, 0.039, 0.065),
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),
    "trigger": (-0.018, 0.0, -0.038),
    # Under the upper receiver ahead of the magazine.
    "support": ((-0.28, 0.0, -0.01), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "ammo": (magazine, (-0.125, 0.0, -0.08)),
}
