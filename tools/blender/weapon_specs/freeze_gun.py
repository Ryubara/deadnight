"""The freeze gun (#797; the plan: docs/research/weapon-models.md, "Freeze gun"): our own design, a cold-store rifle.

1950s refrigeration made a weapon: a pressure tank of coolant lying on top (the signature mass, 0.09 m across), a
condenser of six square Frost fins along the barrel, a flared nozzle with a Glow disc inside it, a round Glow gauge
on the receiver's left and a Glow sight strip along each side of the tank. Not the genre's freeze or lightning guns: no glass
bulb, no copper coils. Everything that burns is the palette's Glow cell, which the game lights (`ModelGlow`). Drawn at
0.90 m and held as a rifle at 1.3 like the Tommy gun, whose pistol grip, guard, trigger and vertical foregrip (moved
7.5 cm back, behind the fins) it takes; the origin is the grip.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only freeze_gun
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _revolve import revolve_x
from weaponlib import BEVEL

BORE = 0.05  # the barrel's axis height
TANK_Z = 0.14  # the tank's axis height
FG = 0.075  # how far behind the Tommy gun's the foregrip sits (clear of the fins)
F, G, D, K, L = "Frost", "Grey", "DarkGrey", "Black", "Glow"


def body(b):
    """Nozzle, finned barrel, receiver, clamps, foregrip, grip and stock: everything but the tank."""
    # The nozzle: a Grey flare, open at the front, a Glow disc deep inside it.
    revolve_x(b, [(-0.53, 0.026), (-0.6, 0.042), (-0.6, 0.032), (-0.565, 0.017), (-0.53, 0.017)], G, segs=12, z=BORE,
              closed=True)  # fmt: skip
    b.cyl((-0.574, 0, BORE), (-0.584, 0, BORE), 0.022, L, segs=12, bevel=0)
    # The barrel and its condenser: six square Frost fins (kept in the far level: they are the gun's outline).
    b.cyl((-0.535, 0, BORE), (-0.22, 0, BORE), 0.02, D, segs=12, bevel=0)
    for i in range(6):
        b.box((-0.51 + 0.036 * i, 0, BORE), (0.008, 0.08, 0.08), F, bevel=0)
    b.cyl((-0.25, 0, BORE), (-0.215, 0, BORE), 0.03, D, segs=12, bevel=0, detail=True)  # the collar at the receiver
    # Receiver: the Grey block, its screws, the round Glow gauge on the left side.
    b.box((-0.09, 0, 0.035), (0.26, 0.075, 0.11), G, bevel=0.012)
    for y in (-0.039, 0.039):
        b.box((-0.2, y, 0.06), (0.014, 0.006, 0.014), K, bevel=0, detail=True)
    b.cyl((-0.12, -0.036, 0.04), (-0.12, -0.047, 0.04), 0.026, G, segs=12, bevel=0, detail=True)  # gauge rim
    b.cyl((-0.12, -0.047, 0.04), (-0.12, -0.049, 0.04), 0.02, L, segs=12, bevel=0)  # gauge face
    b.box((-0.114, -0.0495, 0.046), (0.016, 0.002, 0.003), K, bevel=0, rot=(0, 0.8, 0), detail=True)  # needle
    # The tank's two clamps: saddles on the receiver's top and straps round the tank (they stay when it lifts off).
    for x in (-0.2, 0.0):
        b.box((x, 0, 0.096), (0.03, 0.06, 0.02), D, bevel=0, detail=True)
        revolve_x(b, [(x - 0.008, 0.044), (x + 0.008, 0.044), (x + 0.008, 0.051), (x - 0.008, 0.051)], D, segs=10,
                  z=TANK_Z, closed=True, detail=True)  # fmt: skip
    # Vertical foregrip on its block under the barrel's root (the Tommy gun's, moved back behind the fins).
    b.box((-0.365 + FG, 0, 0.03), (0.07, 0.04, 0.03), D, bevel=0, detail=True)
    b.prism([(x + FG, z) for x, z in ((-0.335, 0.03), (-0.395, 0.03), (-0.402, -0.01), (-0.405, -0.09),
             (-0.39, -0.11), (-0.35, -0.106), (-0.338, -0.084), (-0.343, -0.05), (-0.33, -0.01))],
            -0.026, 0.026, K, bevel=0.008)  # fmt: skip
    # Pistol grip, trigger guard (deep enough for the Soldier's finger, #460), trigger: the Tommy gun's.
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, K, bevel=0.008)  # fmt: skip
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, G)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, K)
    # Stock: the Tommy gun's shallow stock a little shorter, DarkGrey, a Black pad.
    b.prism([(0.04, 0.075), (0.12, 0.06), (0.28, 0.064), (0.298, -0.05), (0.26, -0.056), (0.12, -0.012),
             (0.04, -0.012)], -0.03, 0.03, D, bevel=BEVEL * 0.7)  # fmt: skip
    b.box((0.292, 0, 0.007), (0.016, 0.064, 0.122), K, bevel=0.004, rot=(0, -0.15, 0))


def tank(b):
    """The coolant tank: a Frost cylinder with rounded ends, a Glow sight strip along each side, a Grey valve
    wheel at its rear and the DarkGrey pipe that runs down into the receiver. The reload's part: unclipped, it lifts
    up and off about its rear clamp."""
    revolve_x(b, [(-0.305, 0.016), (-0.3, 0.032), (-0.287, 0.045), (0.012, 0.045), (0.025, 0.032), (0.03, 0.016)],
              F, segs=14, z=TANK_Z, far=[(-0.305, 0.02), (-0.29, 0.045), (0.015, 0.045), (0.03, 0.02)])  # fmt: skip
    for y in (-0.045, 0.045):
        b.box((-0.14, y, TANK_Z), (0.2, 0.006, 0.02), L, bevel=0)  # sight strips: the glow shows from either side
    b.cyl((0.03, 0, TANK_Z), (0.045, 0, TANK_Z), 0.007, D, segs=6, bevel=0, detail=True)  # valve stem
    b.cyl((0.045, 0, TANK_Z), (0.053, 0, TANK_Z), 0.026, G, segs=10, bevel=0)  # valve wheel
    # The feed pipe, under the tank's front, down to the barrel's collar.
    b.tube([(-0.28, 0.11), (-0.282, 0.088), (-0.262, 0.078), (-0.236, 0.078)], 0.008, D, segs=6, detail=True)


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {"Tank": (tank, (0.0, 0.0, TANK_Z))},  # the rear clamp: it lifts up and off about it
    "muzzle": (-0.6, 0.0, BORE),  # the nozzle's front face, on the bore
    # The Tommy gun's pistol grip and trigger; the support on the vertical foregrip, 7.5 cm behind the Tommy's.
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),
    "trigger": (-0.018, 0.0, -0.038),
    "support": ((-0.37 + FG, 0.0, -0.045), (0.08, 0.0, 1.0), (-1.0, 0.0, 0.0)),
    "ammo": (tank, (-0.14, 0.0, TANK_Z)),
}
