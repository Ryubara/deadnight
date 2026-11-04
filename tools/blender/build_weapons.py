"""Build Deadnight's original weapons in the Toon Shooter kit's style and export them to glTF.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_weapons.py -- [--only lever_rifle] [--out game/assets/weapons]

Writes, for each weapon, `<out>/<name>/<name>.glb` (gameplay: first person and world) and `<name>_far.glb` (the far
level), plus the shared palette `<out>/weapons_palette.png`, and prints one `WEAPON` line per file with its triangle
and part counts. Every number follows the style bible's weapon rules (docs/design/style.md); the part helpers are in
weaponlib.py.

Axes are the kit's: 1 unit = 1 m, up is +Z, a gun's muzzle points along -X and a melee weapon stands up along +Z, thin
across Y. The origin is the grip, where the hand bone holds the weapon with no offset.

Every firearm also carries an empty named `Muzzle` (`MUZZLES`), parented to the weapon at the centre of its barrel's
open end (between the barrels of a double gun), turned so its local +Y points out of the barrel: after the glTF's Y-up
conversion that is the node's -Z in Godot, the engine's forward. The flash and the shot leave from it. The hammer
carries a `Face` the same way, at the centre of its striking face, -Z out of the face.
"""

import argparse
import importlib.util
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import weaponlib as wl

# Palette names, short.
G, D, K, W, R = "Grey", "DarkGrey", "Black", "Wood", "Red"
G2, GN, Y = "Grey2", "Green", "Yellow"


def lever_rifle(b):
    """A lever-action rifle: round barrel over a tube magazine, a box receiver, a big loop lever, wood stock and forend."""
    # Stock, from the wrist (the grip, at the origin) back to a slanted butt.
    b.prism([(-0.02, 0.05), (0.10, 0.04), (0.37, 0.06), (0.41, -0.115), (0.34, -0.12), (0.10, -0.045),
             (-0.02, -0.045)], -0.048, 0.048, W)  # fmt: skip
    b.box((0.40, 0, -0.03), (0.022, 0.1, 0.18), D, bevel=0.006, rot=(0, -0.22, 0))  # butt plate
    b.box((0.05, 0, 0.056), (0.13, 0.03, 0.012), G, bevel=0)  # upper tang
    for x in (0.0, 0.09):
        b.box((x, 0, 0.064), (0.014, 0.014, 0.006), K, bevel=0, detail=True)  # tang screws
    for x, z in ((0.40, 0.03), (0.422, -0.08)):
        b.box((x, 0, z), (0.006, 0.016, 0.016), K, bevel=0, detail=True)  # butt plate screws
    # Receiver: the main block, a bolt on top, a loading gate on the right, screws both sides.
    b.box((-0.15, 0, 0.01), (0.28, 0.086, 0.14), G)
    b.box((-0.12, 0, 0.086), (0.2, 0.04, 0.022), D, bevel=0.006)  # bolt
    b.box((-0.16, 0.045, -0.02), (0.08, 0.01, 0.036), D, bevel=0)  # loading gate
    for y in (-0.044, 0.044):
        for x, z in ((-0.26, 0.045), (-0.04, 0.045), (-0.15, -0.04)):
            b.box((x, y, z), (0.018, 0.008, 0.018), K, bevel=0, detail=True)
    b.bar([(-0.012, 0.07), (0.008, 0.112), (0.034, 0.122)], 0.022, 0.022, D)  # hammer
    # Barrel over the tube magazine, held by a band; a black bore at the muzzle.
    b.cyl((-0.29, 0, 0.045), (-1.22, 0, 0.045), 0.032, D)
    b.cyl((-1.22, 0, 0.045), (-1.224, 0, 0.045), 0.018, K, bevel=0, detail=True)
    b.cyl((-0.29, 0, -0.02), (-1.06, 0, -0.02), 0.024, D, segs=10, bevel=0)
    b.cyl((-1.06, 0, -0.02), (-1.10, 0, -0.02), 0.027, G, segs=10, bevel=0.008)  # magazine cap
    b.box((-1.0, 0, 0.012), (0.04, 0.074, 0.11), G, bevel=0.008)  # barrel band
    b.box((-1.0, -0.038, 0.012), (0.014, 0.006, 0.014), K, bevel=0, detail=True)  # band screw
    # Forend, with a steel cap.
    b.prism([(-0.29, 0.035), (-0.68, 0.035), (-0.70, 0.0), (-0.68, -0.05), (-0.29, -0.062)], -0.044, 0.044, W)
    b.box((-0.70, 0, -0.005), (0.03, 0.092, 0.092), G, bevel=0.008)
    for y in (-0.045, 0.045):
        b.box((-0.48, y, -0.02), (0.016, 0.006, 0.016), K, bevel=0, detail=True)  # forend screws
    # Sights.
    b.box((-1.17, 0, 0.078), (0.05, 0.03, 0.012), D, bevel=0, detail=True)
    b.box((-1.17, 0, 0.094), (0.03, 0.012, 0.03), K, bevel=0)
    b.box((-0.45, 0, 0.08), (0.04, 0.04, 0.02), D, bevel=0)
    b.box((-0.45, 0, 0.098), (0.012, 0.054, 0.022), K, bevel=0, detail=True)
    # The lever (`lever_rifle_lever`, its own node) turns on this pivot pin.
    b.cyl((-0.21, -0.05, -0.045), (-0.21, 0.05, -0.045), 0.012, K, segs=8, bevel=0, detail=True)
    b.bar([(-0.06, -0.058), (-0.056, -0.09), (-0.044, -0.102)], 0.016, 0.014, K)  # trigger


def lever_rifle_lever(b):
    """The lever: a trigger guard that runs back into a finger loop under the wrist. Turns on the pivot pin
    (`NODES`), the loop swinging down and forward to work the action (Deadnight #683)."""
    b.bar([(-0.22, -0.06), (-0.19, -0.11), (-0.08, -0.125), (0.0, -0.115), (0.03, -0.09)], 0.03, 0.022, G)
    b.arc((0.06, -0.13), 0.055, 150, 420, 9, 0.03, 0.022, G)
    b.bar([(0.087, -0.083), (0.06, -0.052)], 0.03, 0.022, G)


def double_shotgun(b):
    """A side-by-side double-barrel shotgun with outside hammers, a splinter forend and a straight stock."""
    b.prism([(-0.02, 0.05), (0.10, 0.04), (0.36, 0.055), (0.40, -0.11), (0.33, -0.115), (0.10, -0.045),
             (-0.02, -0.045)], -0.05, 0.05, W)  # fmt: skip
    b.box((0.395, 0, -0.028), (0.03, 0.104, 0.18), K, bevel=0.008, rot=(0, -0.24, 0))  # butt pad
    b.box((0.05, 0, 0.051), (0.13, 0.03, 0.012), G, bevel=0)  # tang
    for x in (0.0, 0.09):
        b.box((x, 0, 0.059), (0.014, 0.014, 0.006), K, bevel=0, detail=True)
    # Action: the block, side plates, fences around the barrel breeches, hammers, top lever.
    b.box((-0.13, 0, 0.0), (0.26, 0.124, 0.13), G)
    for y in (-0.063, 0.063):
        b.box((-0.09, y, -0.005), (0.16, 0.008, 0.085), D, bevel=0.004)
        for x in (-0.15, -0.03):
            b.box((x, y * 1.06, -0.005), (0.016, 0.006, 0.016), K, bevel=0, detail=True)
    for y in (-0.036, 0.036):
        b.cyl((-0.255, y, 0.035), (-0.285, y, 0.035), 0.042, G, segs=12, bevel=0.008)  # fences
        b.bar([(-0.03, 0.055), (-0.015, 0.09), (0.012, 0.1)], 0.02, 0.024, D, y=y * 1.3)  # hammers
    b.box((0.005, 0, 0.07), (0.07, 0.03, 0.016), D, bevel=0, rot=(0, -0.15, 0))  # top lever
    # The barrels and the forend (`double_shotgun_barrels`, their own node) break open on this hinge pin.
    b.cyl((-0.23, -0.068, -0.03), (-0.23, 0.068, -0.03), 0.015, D, segs=8, bevel=0, detail=True)  # hinge pin
    # Trigger guard and two triggers; the guard hangs deep enough for the Soldier's thick finger (#460).
    b.bar([(-0.12, -0.06), (-0.10, -0.12), (-0.02, -0.132), (0.04, -0.11), (0.07, -0.052)], 0.026, 0.018, G)
    b.bar([(-0.065, -0.058), (-0.06, -0.094)], 0.014, 0.014, K)
    b.bar([(-0.025, -0.058), (-0.02, -0.094)], 0.014, 0.014, K)


def double_shotgun_barrels(b):
    """The barrels side by side (a rib on top and below, black bores, a bead sight) and the splinter forend with its
    iron and latch: one node that breaks open on the hinge pin, the muzzles dropping (Deadnight #683)."""
    for y in (-0.036, 0.036):
        b.cyl((-0.28, y, 0.035), (-1.08, y, 0.035), 0.036, D)
        b.cyl((-1.08, y, 0.035), (-1.084, y, 0.035), 0.022, K, bevel=0, detail=True)
    b.box((-0.68, 0, 0.074), (0.8, 0.024, 0.012), K, bevel=0)  # top rib
    b.box((-0.68, 0, 0.0), (0.8, 0.024, 0.024), D, bevel=0)  # bottom rib
    b.box((-1.065, 0, 0.086), (0.016, 0.016, 0.016), G, bevel=0, detail=True)  # bead
    b.prism([(-0.30, 0.015), (-0.60, 0.015), (-0.62, -0.01), (-0.60, -0.05), (-0.30, -0.055)], -0.058, 0.058, W)
    b.box((-0.29, 0, -0.02), (0.03, 0.12, 0.072), G, bevel=0.008)
    b.box((-0.46, 0, -0.056), (0.05, 0.03, 0.012), G, bevel=0, detail=True)


def baseball_bat(b):
    """A wooden bat with a taped grip and nails driven through the barrel."""
    b.lathe([(0.040, -0.17), (0.053, -0.16), (0.053, -0.142), (0.040, -0.126), (0.030, -0.11), (0.030, 0.25),
             (0.041, 0.40), (0.058, 0.56), (0.066, 0.70), (0.066, 0.90), (0.058, 0.926), (0.040, 0.936)], W, segs=14)  # fmt: skip
    b.lathe([(0.031, -0.112), (0.035, -0.104), (0.035, 0.17), (0.031, 0.178)], K, segs=14)  # grip tape
    for z in (-0.07, 0.03, 0.13):
        b.lathe([(0.036, z), (0.038, z + 0.004), (0.038, z + 0.016), (0.036, z + 0.02)], K, segs=14, detail=True)
    b.box((0.04, 0, 0.175), (0.012, 0.03, 0.05), K, bevel=0, rot=(0, 0.3, 0), detail=True)  # loose tape end
    for i, (deg, z) in enumerate(((10, 0.64), (75, 0.70), (150, 0.76), (215, 0.67), (280, 0.82), (340, 0.86))):
        a = math.radians(deg)
        r = 0.068 + 0.012 * (i % 2)
        b.box((r * math.cos(a), r * math.sin(a), z), (0.07, 0.009, 0.009), G, bevel=0, rot=(0, 0.15, a))
        b.box((0.064 * math.cos(a), 0.064 * math.sin(a), z), (0.006, 0.022, 0.022), G, bevel=0, rot=(0, 0, a),
              detail=True)  # fmt: skip


def fire_axe(b):
    """A fire axe: wood haft with a black grip, a red head with a bare steel edge and a back pick."""
    b.prism([(-0.046, -0.17), (0.046, -0.17), (0.05, -0.12), (0.034, -0.06), (0.03, 1.02), (-0.03, 1.02),
             (-0.034, -0.06), (-0.05, -0.12)], -0.024, 0.024, W, bevel=0.012)  # fmt: skip
    b.box((0, 0, 0.01), (0.074, 0.054, 0.22), K, bevel=0.012)  # grip
    b.box((0, 0, -0.098), (0.078, 0.058, 0.014), K, bevel=0, detail=True)  # grip collars
    b.box((0, 0, 0.118), (0.078, 0.058, 0.014), K, bevel=0, detail=True)
    # Head: the eye block, the blade and its steel edge, the pick and its steel tip.
    b.box((0, 0, 0.93), (0.1, 0.066, 0.14), R)
    b.prism([(-0.045, 0.99), (-0.045, 0.87), (-0.14, 0.855), (-0.205, 0.83), (-0.205, 1.05), (-0.14, 1.01)],
            -0.024, 0.024, R)  # fmt: skip
    b.prism([(-0.20, 0.825), (-0.20, 1.055), (-0.25, 1.075), (-0.25, 0.805)], -0.014, 0.014, G, bevel=0.008)
    b.prism([(0.045, 0.975), (0.045, 0.885), (0.15, 0.915), (0.20, 0.932), (0.15, 0.952)], -0.021, 0.021, R)
    b.prism([(0.18, 0.924), (0.27, 0.94), (0.18, 0.954)], -0.014, 0.014, G, bevel=0.004)
    b.box((0, 0, 1.024), (0.008, 0.034, 0.008), G, bevel=0, detail=True)  # wedge in the haft
    for y in (-0.034, 0.034):
        for z in (0.905, 0.955):
            b.box((-0.02, y, z), (0.016, 0.006, 0.016), G, bevel=0, detail=True)  # rivets


def hammer(b):
    """A claw hammer for nailing boards back (the repair, #297): a wood handle that swells at the grip and flares at
    the butt, a steel head with a round striking face on -X (the axe's blade side) and a split claw curling down on
    +X. Drawn at 0.56 m and enlarged 1.3 times to 0.73 m (2.2 times a real 16 oz hammer), as the kit draws its small
    things large (its knife is 1.4 m) and the Soldier's fist would hide a smaller one; the grip (the origin) is 15 %
    up from the butt."""
    # Handle: one prism, wider in the swing plane than across it, as a real hammer handle is.
    b.prism([(-0.046, -0.085), (0.046, -0.085), (0.05, -0.06), (0.04, 0.0), (0.03, 0.25), (0.027, 0.40),
             (0.027, 0.43), (-0.027, 0.43), (-0.027, 0.40), (-0.03, 0.25), (-0.04, 0.0), (-0.05, -0.06)],
            -0.026, 0.026, W, bevel=0.012)  # fmt: skip
    # Head: the eye block round the handle's top, the neck and the bell out to the face, the claw back.
    b.box((0, 0, 0.415), (0.09, 0.07, 0.105), G)
    b.cyl((-0.04, 0, 0.415), (-0.115, 0, 0.415), 0.034, G, segs=10, bevel=0, radius1=0.04)  # neck
    b.cyl((-0.115, 0, 0.415), (-0.165, 0, 0.415), 0.052, G, segs=12, bevel=0.01)  # face
    b.cyl((-0.165, 0, 0.415), (-0.169, 0, 0.415), 0.04, D, segs=12, bevel=0, detail=True)  # worn striking face
    # The claw: two prongs, each a run of tapering pieces curling down toward the handle, a V between them.
    for y0, y1 in ((-0.035, -0.006), (0.006, 0.035)):
        b.prism([(0.035, 0.37), (0.09, 0.385), (0.09, 0.455), (0.035, 0.467)], y0, y1, G, bevel=0.006)
        b.prism([(0.085, 0.385), (0.135, 0.365), (0.15, 0.43), (0.085, 0.458)], y0, y1, G, bevel=0)
        b.prism([(0.13, 0.367), (0.165, 0.325), (0.19, 0.36), (0.145, 0.433)], y0, y1, G, bevel=0)
        b.prism([(0.16, 0.33), (0.18, 0.29), (0.195, 0.298), (0.188, 0.364)], y0, y1, G, bevel=0, detail=True)
    # A wedge in the handle's top and two steel ones across it, as on the axe.
    b.box((0, 0, 0.471), (0.054, 0.036, 0.01), W, bevel=0, detail=True)
    b.box((0, 0, 0.477), (0.006, 0.04, 0.006), D, bevel=0, detail=True)


def crowbar(b):
    """A wrecking bar (the crowbar, #285): a red-painted hex shaft, a gooseneck bending over toward -X (the striking
    side, as the axe's blade and the hammer's face) into a split claw of bare steel, a slightly bent chisel at the
    butt and a black tape wrap where the hand goes. Drawn at its real 0.74 m with the cross-section about twice a real
    bar's, as the kit draws its handles; the grip (the origin) is 19 % up from the butt."""
    # The hex bar: one sweep from the butt up the shaft and through the gooseneck's half turn toward -X.
    bend = [
        (-0.062 + 0.062 * math.cos(math.radians(a)), 0.52 + 0.062 * math.sin(math.radians(a)))
        for a in range(15, 181, 15)
    ]
    b.tube([(0, -0.095), (0, 0.52), *bend], 0.025, R, segs=6)
    b.cyl((0, 0, -0.055), (0, 0, 0.105), 0.029, K, segs=8, bevel=0.003)  # tape wrap
    b.cyl((0, 0, 0.085), (0, 0, 0.1), 0.031, K, segs=8, bevel=0, detail=True)  # wrap end, a turn proud
    b.box((0.022, 0, 0.11), (0.01, 0.022, 0.03), K, bevel=0, rot=(0, 0.35, 0), detail=True)  # loose tape end
    # Chisel: a flat wedge of bare steel bent a little toward +X.
    b.prism([(-0.024, -0.09), (0.024, -0.09), (0.036, -0.13), (0.03, -0.142), (-0.006, -0.14)], -0.017, 0.017, G,
            bevel=0.003)  # fmt: skip
    # The claw coming back down toward the shaft, split in two.
    for y0, y1 in ((-0.022, -0.004), (0.004, 0.022)):
        b.prism([(-0.146, 0.53), (-0.1, 0.53), (-0.098, 0.48), (-0.106, 0.44), (-0.118, 0.437), (-0.142, 0.48)],
                y0, y1, G, bevel=0.003)  # fmt: skip
    b.box((-0.123, 0, 0.535), (0.05, 0.044, 0.016), G, bevel=0, detail=True)  # the claw's root, where the paint wore


def revolver(b):
    """A six-shot service revolver (the pistol id, #285): a grey frame and barrel with a full-length lug under it, a
    dark cylinder with flutes, wood grips, a hammer spur and a round trigger guard. Drawn at a real 6-inch revolver's
    0.31 m with every cross-section about twice real, the kit's chunk for small guns (its Revolver is 0.99 m long and
    0.53 m high); the origin is the grip, behind the trigger under the hammer."""
    bore = 0.045
    # Barrel: round, a flat rib on top and the ejector lug below, so the side reads as one slab as the kit's does.
    b.cyl((-0.085, 0, bore), (-0.235, 0, bore), 0.017, G, segs=12, bevel=0.004)
    b.box((-0.16, 0, 0.064), (0.15, 0.014, 0.008), G, bevel=0)  # rib
    b.box((-0.155, 0, 0.026), (0.14, 0.024, 0.02), G, bevel=0.004)  # ejector lug
    b.cyl((-0.235, 0, bore), (-0.238, 0, bore), 0.009, K, segs=8, bevel=0, detail=True)  # bore
    b.box((-0.226, 0, 0.078), (0.016, 0.006, 0.016), K, bevel=0)  # front sight
    # Frame round the cylinder: the front block the barrel screws into, the top strap, the bottom, the recoil shield.
    b.box((-0.084, 0, 0.045), (0.02, 0.038, 0.08), G, bevel=0.004)
    b.box((-0.033, 0, 0.084), (0.1, 0.03, 0.012), G, bevel=0.003)
    b.box((-0.038, 0, 0.004), (0.106, 0.036, 0.018), G, bevel=0.004)
    b.box((0.012, 0, 0.042), (0.024, 0.04, 0.094), G, bevel=0.005)
    b.box((0.006, 0, 0.092), (0.012, 0.012, 0.006), K, bevel=0, detail=True)  # rear sight notch
    # The cylinder (`revolver_cylinder`, its own node) swings out to the left on its crane.
    # Grip: wood panels on a steel backstrap, a butt cap, a screw each side.
    b.prism([(-0.004, 0.0), (0.028, 0.002), (0.044, -0.03), (0.068, -0.094), (0.032, -0.1), (0.016, -0.056),
             (-0.002, -0.02)], -0.0195, 0.0195, W, bevel=0.005)  # fmt: skip
    b.bar([(0.03, 0.0), (0.048, -0.04), (0.068, -0.092)], 0.03, 0.008, G)  # backstrap
    b.box((0.05, 0, -0.098), (0.04, 0.034, 0.008), G, bevel=0, rot=(0, -0.15, 0))  # butt cap
    b.cyl((0.03, -0.021, -0.05), (0.03, 0.021, -0.05), 0.005, K, segs=6, bevel=0, detail=True)  # grip screw
    # Hammer spur, trigger guard, trigger.
    b.bar([(0.012, 0.074), (0.03, 0.09), (0.05, 0.092)], 0.014, 0.014, K)
    b.bar([(-0.046, 0.0), (-0.046, -0.028), (-0.028, -0.042), (-0.004, -0.038), (0.006, -0.016)], 0.012, 0.008, G)
    b.bar([(-0.02, -0.002), (-0.023, -0.022), (-0.015, -0.032)], 0.008, 0.008, K)


def revolver_cylinder(b):
    """The cylinder and its flutes: swings out to the gun's left (-Y) on the crane under it (Deadnight #683)."""
    b.cyl((-0.074, 0, 0.043), (-0.004, 0, 0.043), 0.033, D, segs=12, bevel=0.005)
    for i in range(6):
        a = math.radians(30 + 60 * i)
        b.box((-0.039, 0.031 * math.cos(a), 0.043 + 0.031 * math.sin(a)), (0.042, 0.012, 0.006), K, bevel=0,
              rot=(a + math.pi / 2, 0, 0), detail=True)  # fmt: skip


def tommy_gun(b):
    """A drum-fed submachine gun of the 1920s-40s (the SMG, #285): a long grey receiver with a cocking knob on top, a
    dark barrel ringed by cooling fins, a slotted compensator at the muzzle, a vertical wood foregrip, a wood pistol
    grip and stock, and a big dark drum under the receiver. An original take on the period type, not one maker's gun.
    Drawn at a real 0.88 m with the cross-sections about 1.5 times real (the lever rifle's chunk); the origin is the
    pistol grip, behind the trigger."""
    bore = 0.05
    # Receiver, the cocking knob, sights.
    b.box((-0.09, 0, 0.035), (0.3, 0.075, 0.11), G, bevel=0.012)
    b.cyl((-0.12, 0, 0.088), (-0.12, 0, 0.112), 0.013, K, segs=8, bevel=0)  # cocking knob
    b.box((-0.12, 0, 0.0915), (0.12, 0.012, 0.004), K, bevel=0, detail=True)  # its slot
    b.box((0.02, 0, 0.1), (0.036, 0.034, 0.024), D, bevel=0)  # rear sight base
    b.box((0.02, 0, 0.118), (0.008, 0.022, 0.02), K, bevel=0, detail=True)  # rear sight leaf
    for y in (-0.039, 0.039):
        b.box((-0.03, y, 0.0), (0.024, 0.006, 0.014), K, bevel=0, detail=True)  # selector and safety
        b.box((-0.2, y, 0.06), (0.014, 0.006, 0.014), K, bevel=0, detail=True)  # screws
    # Barrel: the collar at the receiver, a finned sleeve, the bare barrel, the compensator and its slots.
    b.cyl((-0.24, 0, bore), (-0.27, 0, bore), 0.032, D, segs=12, bevel=0.006)
    b.cyl((-0.27, 0, bore), (-0.49, 0, bore), 0.02, D, segs=10, bevel=0)
    b.cyl((-0.275, 0, bore), (-0.405, 0, bore), 0.028, D, segs=10, bevel=0)  # finned sleeve
    for x in (-0.285, -0.315, -0.345, -0.375):
        b.cyl((x, 0, bore), (x - 0.014, 0, bore), 0.037, D, segs=10, bevel=0, detail=True)  # fins
    b.box((-0.52, 0, 0.054), (0.06, 0.044, 0.058), G, bevel=0.008)  # compensator
    for x in (-0.508, -0.522, -0.536):
        b.box((x, 0, 0.0835), (0.006, 0.03, 0.004), K, bevel=0, detail=True)  # its slots
    b.box((-0.542, 0, 0.09), (0.012, 0.008, 0.018), K, bevel=0)  # front sight
    b.cyl((-0.55, 0, bore), (-0.554, 0, bore), 0.011, K, segs=8, bevel=0, detail=True)  # bore
    # Vertical foregrip on its block under the barrel.
    b.box((-0.365, 0, 0.03), (0.07, 0.04, 0.03), D, bevel=0)
    b.prism([(-0.335, 0.03), (-0.395, 0.03), (-0.402, -0.01), (-0.405, -0.09), (-0.39, -0.11), (-0.35, -0.106),
             (-0.338, -0.084), (-0.343, -0.05), (-0.33, -0.01)], -0.026, 0.026, W, bevel=0.008)  # fmt: skip
    # The drum (`tommy_gun_drum`, its own node) comes off this seat under the receiver.
    b.box((-0.125, 0, -0.018), (0.06, 0.05, 0.02), D, bevel=0)
    # Pistol grip, trigger guard, trigger.
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, W, bevel=0.008)  # fmt: skip
    # The guard hangs deep enough for the Soldier's thick finger (#460).
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, G)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, K)
    # Stock: shallow, the butt slanted back at the bottom, a black butt plate.
    b.prism([(0.05, 0.075), (0.12, 0.06), (0.3, 0.064), (0.318, -0.05), (0.28, -0.056), (0.12, -0.012),
             (0.05, -0.012)], -0.03, 0.03, W, bevel=0.012)  # fmt: skip
    b.box((0.312, 0, 0.007), (0.016, 0.064, 0.122), K, bevel=0.004, rot=(0, -0.15, 0))


def tommy_gun_drum(b):
    """The drum: a short wide cylinder across Y, a hub, a winding key. Its own node, so the reload takes it off and
    puts a full one on (Deadnight #683)."""
    b.cyl((-0.125, -0.036, -0.09), (-0.125, 0.036, -0.09), 0.09, D, segs=16, bevel=0.01)
    b.cyl((-0.125, -0.041, -0.09), (-0.125, 0.041, -0.09), 0.032, G, segs=10, bevel=0)
    b.box((-0.125, -0.045, -0.09), (0.05, 0.008, 0.014), K, bevel=0, detail=True)  # winding key


def flare_gun(b):
    """A 1950s signal pistol (the flare gun, #285): a short, wide barrel with a big black bore, a muzzle ring, a
    break-open frame hinged under the barrel, all in the palette's red so it reads as a signal and not a sidearm,
    black grip plates and a grey hammer. Drawn at a real 0.25 m with the cross-sections about 1.5 times real; the
    origin is the grip, behind the trigger."""
    # The barrel (`flare_gun_barrel`, its own node) breaks open on the hinge under it.
    # Frame: the breech block, the hinge under the barrel, the latch on top.
    b.box((-0.008, 0, 0.042), (0.06, 0.05, 0.078), R, bevel=0.006)
    b.cyl((-0.04, -0.028, 0.012), (-0.04, 0.028, 0.012), 0.009, G, segs=8, bevel=0)  # hinge pin
    b.box((-0.05, 0, 0.012), (0.03, 0.03, 0.02), R, bevel=0)  # hinge lug
    b.box((-0.008, 0, 0.084), (0.034, 0.022, 0.012), G, bevel=0)  # latch
    # Grip: the red frame, black plates proud on both sides, a grey butt plate.
    b.prism([(-0.01, 0.008), (0.022, 0.008), (0.04, -0.03), (0.062, -0.094), (0.026, -0.1), (0.008, -0.05),
             (-0.008, -0.016)], -0.019, 0.019, R, bevel=0.005)  # fmt: skip
    b.prism([(0.008, -0.012), (0.027, -0.012), (0.048, -0.082), (0.03, -0.087)], -0.022, 0.022, K, bevel=0)
    b.box((0.045, 0, -0.098), (0.04, 0.042, 0.01), G, bevel=0, rot=(0, -0.3, 0))
    # Hammer, trigger guard, trigger.
    b.bar([(0.01, 0.07), (0.028, 0.088), (0.048, 0.09)], 0.016, 0.016, G)
    b.bar([(-0.04, 0.005), (-0.042, -0.024), (-0.025, -0.04), (-0.002, -0.035), (0.006, -0.012)], 0.014, 0.009, R)
    b.bar([(-0.016, 0.004), (-0.02, -0.018), (-0.012, -0.028)], 0.009, 0.009, K)


def flare_gun_barrel(b):
    """The short wide barrel, its muzzle ring, the big black bore and the sight rib: breaks open on the hinge under
    it, the muzzle dropping (Deadnight #683)."""
    bore = 0.045
    b.cyl((-0.03, 0, bore), (-0.178, 0, bore), 0.03, R, segs=12, bevel=0.005)  # barrel
    b.cyl((-0.17, 0, bore), (-0.19, 0, bore), 0.035, R, segs=12, bevel=0.004)  # muzzle ring
    b.cyl((-0.19, 0, bore), (-0.193, 0, bore), 0.022, K, segs=12, bevel=0)  # the bore, wide enough to read far off
    b.box((-0.1, 0, 0.078), (0.12, 0.012, 0.008), R, bevel=0, detail=True)  # sight rib


def grenade(b):
    """A 1950s-flavoured hand grenade: an olive egg ringed by three raised bands, a yellow band under the fuze
    (the period marking for a high-explosive filler) and a squat grey fuze. The spoon and the pin are their own nodes
    (`grenade_spoon`, `grenade_pin`) so the pin pull and the spoon flying off can show. Stands up along +Z; the origin
    (the grip) is the centre of the body, where the fist closes."""
    # Body: one turned egg, fuller at the bottom; the bands are short steps in the radius (the chamfers are in the
    # profile, as on the bat).
    b.lathe([(0.0, -0.215), (0.07, -0.21), (0.118, -0.185), (0.142, -0.15), (0.142, -0.13), (0.156, -0.115),
             (0.156, -0.085), (0.146, -0.07), (0.15, -0.045), (0.164, -0.03), (0.164, 0.0), (0.15, 0.015),
             (0.146, 0.04), (0.156, 0.055), (0.156, 0.085), (0.138, 0.1), (0.118, 0.125), (0.09, 0.145),
             (0.0, 0.15)], GN, segs=14)  # fmt: skip
    b.lathe([(0.112, 0.1), (0.14, 0.094), (0.14, 0.122), (0.1, 0.14), (0.07, 0.149)], Y, segs=14)  # HE band
    b.lathe([(0.03, -0.226), (0.06, -0.218), (0.06, -0.205), (0.03, -0.2)], D, segs=14, detail=True)  # base plug
    # Fuze: a neck, the body with the striker hump, a lug on the right for the spoon hinge.
    b.cyl((0, 0, 0.13), (0, 0, 0.19), 0.062, D, segs=12, bevel=0)
    b.box((0, 0, 0.215), (0.13, 0.11, 0.07), D, bevel=0.014)
    b.box((0.055, 0, 0.245), (0.06, 0.07, 0.03), G2, bevel=0.008)  # striker housing
    b.box((0.075, 0, 0.21), (0.03, 0.08, 0.05), G2, bevel=0, detail=True)  # hinge lug
    for y in (-0.059, 0.059):
        b.cyl((0.0, y, 0.215), (0.0, y * 1.12, 0.215), 0.016, G2, segs=8, bevel=0, detail=True)  # pin bosses


def grenade_spoon(b):
    """The spoon (safety lever): over the fuze and down the body's right side (+X). Pivots at its hinge."""
    b.bar([(-0.035, 0.262), (0.06, 0.268), (0.095, 0.24), (0.15, 0.16), (0.175, 0.07), (0.178, -0.02)],
          0.07, 0.022, G)  # fmt: skip


def grenade_pin(b):
    """The pin through the fuze (across Y) and its pull ring, on the -Y side. Pulls out along -Y."""
    b.cyl((0.0, 0.07, 0.215), (0.0, -0.09, 0.215), 0.01, G2, segs=6, bevel=0)
    b.arc((0.0, 0.215), 0.055, -90, 270, 10, 0.018, 0.018, G2, y=-0.1)


# ---- the reload's ammunition: what the left hand brings from the belt (Deadnight #683) ----------------------------
# Each is drawn along X like its gun (the point or the open end toward -X), in the gun's drawing units, and exported
# at the gun's chunk to `<gun>/<gun>_ammo.glb` (`AMMO`). The game holds it in the left hand at the gun's size.


def shotgun_shells(b):
    """Two red paper shells side by side with brass heads, the size of the barrels' bores (Deadnight #683)."""
    for y in (-0.03, 0.03):
        b.cyl((-0.045, y, 0.0), (0.03, y, 0.0), 0.026, R, segs=10, bevel=0.004)
        b.cyl((0.03, y, 0.0), (0.05, y, 0.0), 0.029, Y, segs=10, bevel=0.003)  # brass head and rim


def rifle_round(b):
    """One rifle cartridge: a brass case with a shoulder and a grey bullet, drawn chunky so it reads in the fist."""
    b.cyl((-0.01, 0, 0.0), (0.05, 0, 0.0), 0.016, Y, segs=8, bevel=0.003)
    b.cyl((-0.03, 0, 0.0), (-0.01, 0, 0.0), 0.012, Y, segs=8, bevel=0, radius1=0.016)  # shoulder
    b.cyl((-0.055, 0, 0.0), (-0.03, 0, 0.0), 0.006, G, segs=8, bevel=0, radius1=0.012)  # bullet


def revolver_speedloader(b):
    """A speedloader: a dark knob holding six brass rounds in the cylinder's circle, the rounds forward (-X)."""
    b.cyl((0.0, 0, 0.0), (0.028, 0, 0.0), 0.034, D, segs=12, bevel=0.004)
    b.cyl((0.028, 0, 0.0), (0.045, 0, 0.0), 0.016, K, segs=8, bevel=0.003)  # the knob
    for i in range(6):
        a = 6.283185 * i / 6
        y, z = 0.022 * math.cos(a), 0.022 * math.sin(a)
        b.cyl((-0.03, y, z), (0.0, y, z), 0.009, Y, segs=6, bevel=0)


def flare_shell(b):
    """A signal cartridge: a fat red case with a brass base, the size of the flare gun's wide bore."""
    b.cyl((-0.06, 0, 0.0), (0.03, 0, 0.0), 0.023, R, segs=10, bevel=0.004)
    b.cyl((0.03, 0, 0.0), (0.045, 0, 0.0), 0.027, Y, segs=10, bevel=0.003)


# gun: (builder, centre): the centre (drawing units) is the piece's origin, where the left hand holds it.
AMMO = {
    "double_shotgun": (shotgun_shells, (0.0, 0.0, 0.0)),
    "lever_rifle": (rifle_round, (0.0, 0.0, 0.0)),
    "revolver": (revolver_speedloader, (0.0, 0.0, 0.0)),
    "tommy_gun": (None, (-0.125, 0.0, -0.09)),  # a full drum: the gun's own `Drum` part (tommy_gun_drum)
    "flare_gun": (flare_shell, (0.0, 0.0, 0.0)),
}


# Weapons made of more than one node: {weapon: {node: (builder, pivot)}}. Each node is joined on its own, its origin
# at the pivot (where it turns or slides from), parented to the weapon's main node so it keeps the weapon's origin.
NODES = {
    "grenade": {"Spoon": (grenade_spoon, (0.075, 0.0, 0.235)), "Pin": (grenade_pin, (0.0, 0.0, 0.215))},
    # The reload's moving parts (Deadnight #683): each turns or slides about its pivot (the game's ReloadMotion).
    "lever_rifle": {"Lever": (lever_rifle_lever, (-0.21, 0.0, -0.045))},  # the lever's pivot pin
    "double_shotgun": {"Barrels": (double_shotgun_barrels, (-0.23, 0.0, -0.03))},  # the hinge pin
    "revolver": {"Cylinder": (revolver_cylinder, (-0.039, -0.024, 0.012))},  # the crane, under and left of it
    "tommy_gun": {"Drum": (tommy_gun_drum, (-0.125, 0.0, -0.09))},  # the drum's centre
    "flare_gun": {"Barrel": (flare_gun_barrel, (-0.04, 0.0, 0.012))},  # the hinge pin
}


# Firearms: the centre of the barrel's open end, in drawing units (before `chunk`, like the NODES pivots). A gun with
# two barrels side by side gets one muzzle centred between them. Melee weapons and the grenade have none.
MUZZLES = {
    "lever_rifle": (-1.22, 0.0, 0.045),  # the barrel's front face (the bore disc stands 4 mm proud on the held level)
    "double_shotgun": (-1.08, 0.0, 0.035),  # between the two barrels' front faces
    "revolver": (-0.235, 0.0, 0.045),  # the barrel's front face (the bore disc stands 3 mm proud on the held level)
    "tommy_gun": (-0.55, 0.0, 0.05),  # the compensator's front face, on the bore
    "flare_gun": (-0.19, 0.0, 0.045),  # the muzzle ring's front face
}
MUZZLE = "Muzzle"
# Tools: the centre of the striking face, facing -X like a muzzle (the far level's face, without the worn disc).
FACES = {
    "hammer": (-0.165, 0.0, 0.415),
}
FACE = "Face"


def add_muzzle(o, name, chunk, table=MUZZLES, node=MUZZLE):
    """The `Muzzle` (or a tool's `Face`) empty under the weapon: at the barrel end or the striking face, local +Y
    out of it (-X), so Godot's -Z."""
    if name not in table:
        return None
    m = bpy.data.objects.new(node, None)
    m.empty_display_type = "ARROWS"
    m.empty_display_size = 0.05
    bpy.context.scene.collection.objects.link(m)
    m.parent = o
    m.location = Vector(table[name]) * Vector(chunk)
    m.rotation_euler = (0.0, 0.0, math.pi / 2)  # +Y -> -X
    return m


# Where the hands meet each weapon (Deadnight #460), in drawing units before `chunk` like MUZZLES. Each is an empty
# under the weapon; the grip solver (game/tools/art/solve_grips.gd) reads them and writes the hand poses.
# - `Grip`: the right hand's handle. At the centre of the handle where the middle finger wraps, its local +Z up the
#   handle toward the index finger (`up`), its local +Y the way the straight fingers point (`front`: along the barrel
#   for a pistol grip, so the palm lies on the grip's right and the fingertips reach round to its left; the striking
#   side of a melee weapon, whose turn about the handle the solver keeps from its old hold). In Godot +Z is the node's
#   +Y and +Y its -Z.
# - `Trigger`: the middle of the trigger's front face, where the index finger's pad presses; local +Y the press
#   (backward, +X). Guns only.
# - `Support`: the left hand's handle (the fore-end, the vertical foregrip, or higher up a melee handle), set out as
#   `Grip` is: up toward the index finger (the muzzle, on a fore-end), front the way the fingers point (to the gun's
#   right, +Y, and a little up on a fore-end held from below; forward on a vertical foregrip). Two-handed weapons only.
# Each entry: (origin, up, front) in drawing units; front is made square to up.
GRIPS = {
    "revolver": ((0.032, 0.0, -0.058), (-0.38, 0.0, 0.92), (-1.0, 0.0, 0.0)),
    "flare_gun": ((0.026, 0.0, -0.056), (-0.37, 0.0, 0.93), (-1.0, 0.0, 0.0)),
    "tommy_gun": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),
    # A straight stock's wrist is held like a stick: the knuckles run forward along it (the index foremost, toward the
    # trigger), the fingers point down round its underside, the thumb over the top.
    "lever_rifle": ((0.07, 0.0, 0.0), (-1.0, 0.0, -0.2), (0.0, 0.0, -1.0)),
    "double_shotgun": ((0.07, 0.0, 0.0), (-1.0, 0.0, -0.2), (0.0, 0.0, -1.0)),
    "baseball_bat": ((0.0, 0.0, 0.03), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)),
    "crowbar": ((0.0, 0.0, 0.025), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)),
    "fire_axe": ((0.0, 0.0, 0.01), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)),
    "hammer": ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)),
}
TRIGGERS = {
    "revolver": (-0.026, 0.0, -0.018),
    "flare_gun": (-0.023, 0.0, -0.012),
    "tommy_gun": (-0.018, 0.0, -0.038),
    "lever_rifle": (-0.063, 0.0, -0.075),
    "double_shotgun": (-0.031, 0.0, -0.074),
}
SUPPORTS = {
    # The rear of the fore-end, where the Soldier's short arm reaches with the stock at his shoulder.
    "lever_rifle": ((-0.36, 0.0, -0.02), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "double_shotgun": ((-0.36, 0.0, -0.02), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "tommy_gun": ((-0.37, 0.0, -0.045), (0.08, 0.0, 1.0), (-1.0, 0.0, 0.0)),
}
GRIP, TRIGGER, SUPPORT = "Grip", "Trigger", "Support"


def add_socket(o, node, origin, chunk, up=(0.0, 0.0, 1.0), front=(1.0, 0.0, 0.0)):
    """A hand socket empty under the weapon: at `origin`, local +Z along `up` and local +Y along `front` (both scaled
    by `chunk` like the drawing, then made square)."""
    k = Vector(chunk)
    z = (Vector(up) * k).normalized()
    y = Vector(front) * k
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    m = bpy.data.objects.new(node, None)
    m.empty_display_type = "ARROWS"
    m.empty_display_size = 0.04
    bpy.context.scene.collection.objects.link(m)
    m.parent = o
    m.matrix_basis = Matrix.Translation(Vector(origin) * k) @ Matrix((x, y, z)).transposed().to_4x4()
    return m


def add_sockets(o, name, chunk):
    """The `Grip`, `Trigger` and `Support` empties of `name` (GRIPS, TRIGGERS, SUPPORTS); returns them."""
    out = []
    if name in GRIPS:
        origin, up, front = GRIPS[name]
        out.append(add_socket(o, GRIP, origin, chunk, up, front))
    if name in TRIGGERS:
        # The press runs backward (+X), up stays up.
        out.append(add_socket(o, TRIGGER, TRIGGERS[name], chunk, (0.0, 0.0, 1.0), (1.0, 0.0, 0.0)))
    if name in SUPPORTS:
        origin, up, front = SUPPORTS[name]
        out.append(add_socket(o, SUPPORT, origin, chunk, up, front))
    return out


# name: (builder, chunk). Guns fatten across Y and Z (their length runs along X); melee across X and Y.
WEAPONS = {
    "lever_rifle": (lever_rifle, (1.0, 1.5, 1.5)),
    "double_shotgun": (double_shotgun, (1.0, 1.4, 1.5)),
    "baseball_bat": (baseball_bat, (1.35, 1.35, 1.0)),
    "fire_axe": (fire_axe, (1.0, 1.5, 1.0)),
    "grenade": (grenade, (1.2, 1.2, 1.2)),  # drawn at 0.5 m, held at the kit grenade's 0.6 m
    "hammer": (hammer, (1.3, 1.5, 1.3)),  # drawn at 0.56 m, enlarged 1.3x (and 1.15x more across)
    # The held weapons of #285 are drawn at their real length with their chunky cross-sections already in the
    # drawing (round parts stay round), so they need no fattening. The rule (docs/design/weapon-hold.md) puts each at
    # 0.88 of its real length in the game; inside the Soldier's 0.8 scale that is a hold `model_scale` of 1.1.
    "crowbar": (crowbar, (1.0, 1.0, 1.0)),
    "revolver": (revolver, (1.0, 1.0, 1.0)),
    "tommy_gun": (tommy_gun, (1.0, 1.0, 1.0)),
    "flare_gun": (flare_gun, (1.0, 1.0, 1.0)),
}


# Where the spent case leaves (#786): the centre of the ejection port, in drawing units like MUZZLES. The `Eject` empty
# keeps the weapon's axes, so its local +Y points out of the gun's right side (+Y in Blender), which is the
# node's -Z in Godot. A gun with no port (a revolver, the energy weapons) has none.
EJECTS = {}
EJECT = "Eject"


def add_eject(o, name, chunk):
    if name not in EJECTS:
        return None
    m = bpy.data.objects.new(EJECT, None)
    m.empty_display_type = "ARROWS"
    m.empty_display_size = 0.04
    bpy.context.scene.collection.objects.link(m)
    m.parent = o
    m.location = Vector(EJECTS[name]) * Vector(chunk)
    return m


# ---- one module a weapon (#786, docs/research/weapon-models.md#one-module-a-weapon) ----------------------------------
# A weapon added after the first ten lives in `weapon_specs/<id>.py`: its builders and one `SPEC` dict, so the model
# batches never edit the same lines of this file. Keys: `build` (the builder) and optionally `chunk` (default 1, 1, 1),
# `nodes` ({node: (builder, pivot)}), `muzzle`, `eject` (points), `grip` and `support` ((origin, up, front)),
# `trigger` (a point) and `ammo` ((builder, centre)): the same values as the tables above, in drawing units.
SPEC_DIR = Path(__file__).resolve().parent / "weapon_specs"
SPEC_TABLES = {
    "nodes": NODES,
    "muzzle": MUZZLES,
    "eject": EJECTS,
    "grip": GRIPS,
    "trigger": TRIGGERS,
    "support": SUPPORTS,
    "ammo": AMMO,
}


def load_specs(folder=SPEC_DIR):
    """Add every `weapon_specs/<id>.py` (not those whose name starts with `_`) to the tables; returns the ids."""
    ids = []
    for path in sorted(folder.glob("*.py")) if folder.is_dir() else []:
        if path.name.startswith("_"):
            continue
        name = path.stem
        module_spec = importlib.util.spec_from_file_location(f"weapon_specs.{name}", path)
        module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(module)
        spec = module.SPEC
        if name in WEAPONS:
            raise SystemExit(f"{path}: {name} is already a weapon")
        unknown = set(spec) - {"build", "chunk", *SPEC_TABLES}
        if unknown:
            raise SystemExit(f"{path}: unknown SPEC keys {sorted(unknown)}")
        if "ammo" in spec and spec["ammo"][0] is None:
            raise SystemExit(f"{path}: the ammo needs its own builder (reuse the node's)")
        WEAPONS[name] = (spec["build"], tuple(spec.get("chunk", (1.0, 1.0, 1.0))))
        for key, table in SPEC_TABLES.items():
            if key in spec:
                table[name] = spec[key]
        ids.append(name)
    return ids


def stats(o, offset=(0.0, 0.0, 0.0)):
    """Triangles, loose parts (after welding coincident vertices), bounding box (moved by `offset`)."""
    me = o.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    seen, parts = set(), 0
    for v in bm.verts:
        if v in seen:
            continue
        parts += 1
        stack = [v]
        while stack:
            u = stack.pop()
            if u in seen:
                continue
            seen.add(u)
            stack.extend(e.other_vert(u) for e in u.link_edges)
    bm.free()
    xs = [v.co + Vector(offset) for v in me.vertices]
    mn = [min(c[i] for c in xs) for i in range(3)]
    mx = [max(c[i] for c in xs) for i in range(3)]
    return tris, parts, mn, mx


def export(o, path):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    for k in o.children:  # pin, spoon, muzzle, hand sockets: separate nodes under the weapon
        k.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", choices=list(WEAPONS))
    ap.add_argument("--out", type=Path, default=Path("game/assets/weapons"))
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    args.out.mkdir(parents=True, exist_ok=True)
    img = wl.palette_image(args.out.resolve() / "weapons_palette.png")
    mat = wl.atlas_material(img)
    report = {}
    for name in args.only or WEAPONS:
        for lod in ("near", "far"):
            build, chunk = WEAPONS[name]
            b = wl.Builder(name, lod, mat, chunk)
            build(b)
            o = b.join()
            kids = []
            for node, (part, pivot) in NODES.get(name, {}).items():
                nb = wl.Builder(f"{name}_{node}", lod, mat, chunk)
                part(nb)
                k = nb.join()
                k.name = k.data.name = node
                pivot = Vector(pivot) * Vector(chunk)
                k.data.transform(Matrix.Translation(-pivot))
                k.parent = o
                k.location = pivot
                kids.append(k)
            muzzle = add_muzzle(o, name, chunk) or add_muzzle(o, name, chunk, FACES, FACE)
            sockets = add_sockets(o, name, chunk)
            eject = add_eject(o, name, chunk)
            if eject:
                sockets.append(eject)
            tris, parts, mn, mx = stats(o)
            for k in kids:
                kt, kp, kmn, kmx = stats(k, offset=k.location)
                tris, parts = tris + kt, parts + kp
                mn = [min(mn[i], kmn[i]) for i in range(3)]
                mx = [max(mx[i], kmx[i]) for i in range(3)]
            folder = args.out / name
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / (f"{name}.glb" if lod == "near" else f"{name}_far.glb")
            export(o, path)
            size = [round(mx[i] - mn[i], 3) for i in range(3)]
            report[f"{name}/{lod}"] = {"tris": tris, "parts": parts, "min": mn, "max": mx, "size": size}
            nodes = f", nodes {[k.name for k in kids]}" if kids else ""
            if muzzle:
                at = [round(c, 4) for c in muzzle.location]
                report[f"{name}/{lod}"][muzzle.name.lower()] = at
                nodes += f", {muzzle.name.lower()} {at}"
            for k in sockets:
                at = [round(c, 4) for c in k.location]
                report[f"{name}/{lod}"][k.name.lower()] = at
                nodes += f", {k.name.lower()} {at}"
            print(f"WEAPON {name} {lod}: {tris} tris, {parts} parts, size {size}{nodes}, file {path}")
            for k in kids:
                bpy.data.objects.remove(k)
            if muzzle:
                bpy.data.objects.remove(muzzle)
            for k in sockets:
                bpy.data.objects.remove(k)
            bpy.data.objects.remove(o)
        if name in AMMO:
            build, centre = AMMO[name]
            chunk = WEAPONS[name][1]
            b = wl.Builder(f"{name}_ammo", "near", mat, chunk)
            (build or tommy_gun_drum)(b)
            o = b.join()
            o.data.transform(Matrix.Translation(-Vector(centre) * Vector(chunk)))
            tris, parts, mn, mx = stats(o)
            path = args.out / name / f"{name}_ammo.glb"
            export(o, path)
            size = [round(mx[i] - mn[i], 3) for i in range(3)]
            report[f"{name}/ammo"] = {"tris": tris, "parts": parts, "size": size}
            print(f"WEAPON {name} ammo: {tris} tris, {parts} parts, size {size}, file {path}")
            bpy.data.objects.remove(o)
    print("REPORT " + json.dumps(report))


load_specs()
main()
