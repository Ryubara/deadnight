"""The M4A1 (#795): a 5.56 mm carbine, an original take on the type (no maker's marks), drawn from public reference
photos in the workspace's `refs/weapons/m4a1/` (docs/research/weapon-models.md#m4a1-m4a1-795).

Read: the carry handle on top, the triangle front sight, the straight magazine and a tube stock, with Tan furniture
(the palette's polymer cell) against the black MP5. Drawn at the real 0.80 m with the cross-sections about 1.5-2 times
real in the drawing (`chunk` 1, 1, 1), so `model_scale` is the rule's 1.3. The pistol grip, guard, trigger and their
sockets are the Tommy gun's.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only m4a1
"""

import math

BORE = 0.045
D, K, T = "DarkGrey", "Black", "Tan"


def body(b):
    """Everything that stays put in the reload."""
    # Barrel and the birdcage flash hider with its slots.
    b.cyl((-0.13, 0, BORE), (-0.42, 0, BORE), 0.016, D, segs=10, bevel=0)
    b.cyl((-0.42, 0, BORE), (-0.47, 0, BORE), 0.02, D, segs=10, bevel=0)
    b.cyl((-0.47, 0, BORE), (-0.473, 0, BORE), 0.011, K, segs=8, bevel=0, detail=True)  # bore
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        b.box(
            (-0.447, 0.0185 * math.cos(r), BORE + 0.0185 * math.sin(r)),
            (0.03, 0.006, 0.006),
            K,
            bevel=0,
            rot=(r, 0, 0),
            detail=True,
        )  # fmt: skip  (slots)
    # The triangle front sight (signature): a collar on the barrel, a frame tapering up to its ears, the post.
    b.box((-0.333, 0, BORE), (0.034, 0.04, 0.044), K, bevel=0)
    b.prism([(-0.358, 0.05), (-0.31, 0.05), (-0.322, 0.122), (-0.346, 0.122)], -0.011, 0.011, K, bevel=0.003)
    b.box((-0.334, 0, 0.128), (0.026, 0.026, 0.014), K, bevel=0)  # the ears
    b.box((-0.334, 0, 0.13), (0.006, 0.006, 0.02), D, bevel=0, detail=True)  # the post
    b.box((-0.345, 0, 0.012), (0.012, 0.012, 0.03), K, bevel=0, detail=True)  # sling swivel
    # The round ribbed Tan hand guard, a Black cap at its front and the delta ring at its rear.
    b.cyl((-0.13, 0, BORE), (-0.31, 0, BORE), 0.04, T, segs=12, bevel=0.008)
    b.cyl((-0.31, 0, BORE), (-0.322, 0, BORE), 0.034, K, segs=12, bevel=0)  # front cap
    b.cyl((-0.11, 0, BORE), (-0.135, 0, BORE), 0.046, K, segs=12, bevel=0)  # delta ring
    for x in (-0.17, -0.22, -0.27):
        b.cyl((x - 0.004, 0, BORE), (x + 0.004, 0, BORE), 0.042, T, segs=12, bevel=0, detail=True)  # ribs
    # The upper receiver, Black, a big flat side; the dust cover and the forward assist on the right.
    b.box((-0.03, 0, 0.058), (0.2, 0.064, 0.064), K, bevel=0.012)  # x -0.13..0.07, z 0.026..0.09
    b.box((-0.03, 0.0335, 0.05), (0.07, 0.004, 0.024), D, bevel=0, detail=True)  # dust cover
    b.cyl((0.04, 0.03, 0.068), (0.06, 0.042, 0.068), 0.011, D, segs=8, bevel=0, detail=True)  # forward assist
    # The carry handle over it (signature), its rear sight block at the back.
    b.box((-0.03, 0, 0.13), (0.15, 0.03, 0.022), K, bevel=0.006)  # top bar x -0.105..0.045
    b.box((-0.095, 0, 0.105), (0.024, 0.03, 0.04), K, bevel=0)  # front leg
    b.box((0.035, 0, 0.115), (0.04, 0.034, 0.06), K, bevel=0)  # rear block
    b.box((0.04, 0, 0.152), (0.024, 0.028, 0.016), D, bevel=0)  # the rear sight's aperture
    b.box((0.04, 0, 0.152), (0.026, 0.008, 0.008), K, bevel=0, detail=True)  # its hole
    b.cyl((0.035, -0.024, 0.118), (0.035, 0.024, 0.118), 0.012, D, segs=8, bevel=0, detail=True)  # windage knob
    # The lower receiver: the trigger group, the magazine well (flared at its mouth), the buffer tube's root.
    # x -0.10..0.06, z -0.02..0.027 (the Tommy's guard gap)
    b.box((-0.02, 0, 0.0035), (0.16, 0.06, 0.047), K, bevel=0.008)
    # the well, x -0.125..-0.045: its rear meets the guard's front
    b.box((-0.085, 0, -0.04), (0.08, 0.05, 0.05), K, bevel=0)
    b.box((-0.06, 0.027, -0.03), (0.016, 0.006, 0.016), D, bevel=0, detail=True)  # magazine release, on the well
    for y in (-0.031, 0.031):
        b.box((0.035, y, 0.008), (0.02, 0.004, 0.012), D, bevel=0, detail=True)  # selector
    # Pistol grip (Tan), guard and trigger: the Tommy gun's (its sockets fit the Soldier's hand, #460).
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, T, bevel=0.008)  # fmt: skip
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, K)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, D)
    # The buffer tube and the Tan stock on it: a flat top, the bottom dropping to the butt; a Black pad. The bottom's
    # front stays high (z 0.02 at x 0.22): the shouldered wrist is under it at x 0.2, z 0.01.
    b.cyl((0.06, 0, 0.055), (0.25, 0, 0.055), 0.022, K, segs=10, bevel=0)
    b.prism([(0.15, 0.035), (0.22, 0.02), (0.322, -0.06), (0.33, 0.08), (0.15, 0.08)], -0.028, 0.028, T,
            bevel=0.01)  # fmt: skip
    b.box((0.336, 0, 0.01), (0.014, 0.062, 0.145), K, bevel=0.004)  # butt pad


def magazine(b):
    """The straight magazine, Tan like the furniture, a slight forward curve at its foot and a Black floor plate. The
    reload's part: out down along its own axis from the well."""
    b.bar([(-0.085, -0.02), (-0.087, -0.11), (-0.099, -0.19)], 0.034, 0.07, T, bevel=0.006)
    b.box((-0.101, 0, -0.2), (0.078, 0.04, 0.012), K, bevel=0, rot=(0, -0.14, 0))  # floor plate


def bolt(b):
    """The charging handle under the carry handle's rear: a T, slides back (+X) 0.06."""
    b.box((0.08, 0, 0.083), (0.03, 0.016, 0.012), D, bevel=0)
    b.box((0.094, 0, 0.083), (0.012, 0.05, 0.014), K, bevel=0)  # the latch bar


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Magazine": (magazine, (-0.085, 0.0, -0.03)),  # the well
        "Bolt": (bolt, (0.07, 0.0, 0.083)),  # the handle's root at the receiver's rear
    },
    "muzzle": (-0.47, 0.0, BORE),
    "eject": (-0.03, 0.036, 0.05),  # the dust cover
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),  # the Tommy gun's
    "trigger": (-0.018, 0.0, -0.038),
    # The hand guard's rear, held from below.
    "support": ((-0.25, 0.0, 0.03), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "ammo": (magazine, (-0.093, 0.0, -0.11)),
}
