"""The MP5 (#795): a compact 9 mm submachine gun with a fixed stock, an original take on the type (no maker's marks),
drawn from public reference photos in the workspace's `refs/weapons/mp5/` (docs/research/weapon-models.md#mp5-mp5-795).

Read: short and straight, a strongly curved Grey magazine against the black gun, the round hood over the front sight.
Drawn at the real 0.68 m with the cross-sections about 1.5-2 times real in the drawing (`chunk` 1, 1, 1), so
`model_scale` is the rule's 1.3. The pistol grip, guard, trigger and their sockets are the Tommy gun's.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only mp5
"""

import math

import bmesh

BORE = 0.045
D, G, K = "DarkGrey", "Grey", "Black"


def ring(b, x, z, r_in, r_out, depth, colour, segs=12, detail=False):
    """A flat ring standing across the barrel (its axis along X) at (x, 0, z): the front sight's hood. One closed part;
    the far level keeps half the sides, as `cyl` does."""
    if not b.near:
        segs = max(6, segs // 2)
    bm = bmesh.new()
    quads = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        cy, cz = math.cos(a), math.sin(a)
        quads.append(
            [bm.verts.new((x + dx, r * cy, z + r * cz)) for dx in (-depth / 2, depth / 2) for r in (r_in, r_out)]
        )
    for i in range(segs):
        a, c = quads[i], quads[(i + 1) % segs]
        # each corner list: back-in, back-out, front-in, front-out
        bm.faces.new((a[1], c[1], c[3], a[3]))  # outside
        bm.faces.new((a[0], a[2], c[2], c[0]))  # inside
        bm.faces.new((a[0], c[0], c[1], a[1]))  # back face
        bm.faces.new((a[2], a[3], c[3], c[2]))  # front face
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return b._finish(bm, colour, 0, detail)


def body(b):
    """Everything that stays put in the reload."""
    # Barrel stub with its three lugs, out of the front of the cocking tube's housing.
    b.cyl((-0.33, 0, BORE), (-0.40, 0, BORE), 0.017, D, segs=10, bevel=0)
    b.cyl((-0.392, 0, BORE), (-0.40, 0, BORE), 0.02, D, segs=10, bevel=0)  # the muzzle's collar
    b.cyl((-0.40, 0, BORE), (-0.403, 0, BORE), 0.01, K, segs=8, bevel=0, detail=True)  # bore
    for a in (90, 210, 330):
        r = math.radians(a)
        b.box((-0.375, 0.02 * math.cos(r), BORE + 0.02 * math.sin(r)), (0.016, 0.01, 0.01), D, bevel=0, detail=True)
    # The receiver: a long black body, the cocking tube's housing running forward over the barrel to the front sight.
    b.box((-0.07, 0, 0.055), (0.22, 0.066, 0.09), K, bevel=0.012)  # x -0.18..0.04, z 0.01..0.10
    b.cyl((-0.17, 0, 0.074), (-0.37, 0, 0.074), 0.027, K, segs=12, bevel=0.006)  # cocking tube housing
    b.box((-0.07, 0, 0.1), (0.2, 0.036, 0.008), D, bevel=0, detail=True)  # the top rail's ridge
    b.box((-0.06, 0.0335, 0.06), (0.06, 0.004, 0.022), K, bevel=0, detail=True)  # ejection port (right)
    b.box((-0.24, -0.0275, 0.074), (0.12, 0.004, 0.01), D, bevel=0, detail=True)  # the cocking handle's slot (left)
    # The front sight: a base clamped round the tube's front and the round hood (signature) with its post.
    b.box((-0.36, 0, 0.09), (0.03, 0.044, 0.05), K, bevel=0.004)
    ring(b, -0.36, 0.128, 0.02, 0.031, 0.014, K, segs=10)
    b.box((-0.36, 0, 0.122), (0.008, 0.006, 0.018), D, bevel=0, detail=True)  # the post
    # The rear sight: a drum across the gun on a small base.
    b.box((0.0, 0, 0.105), (0.032, 0.03, 0.016), K, bevel=0)
    b.cyl((0.004, -0.02, 0.122), (0.004, 0.02, 0.122), 0.016, D, segs=10, bevel=0)
    # The hand guard under the barrel: slim, its top wrapping up the sides, the left hand's place.
    b.prism([(-0.335, 0.0), (-0.32, -0.018), (-0.14, -0.018), (-0.14, 0.064), (-0.335, 0.064)],
            -0.037, 0.037, D, bevel=0.012)  # fmt: skip
    for x in (-0.3, -0.18):
        b.box((x, 0, 0.0), (0.016, 0.077, 0.016), K, bevel=0, detail=True)  # the guard's pin heads
    # The lower: the trigger group and the magazine well.
    b.box((-0.045, 0, -0.0), (0.17, 0.06, 0.05), K, bevel=0.008)  # x -0.13..0.04, z -0.025..0.025
    b.box((-0.1, 0, -0.035), (0.054, 0.05, 0.04), K, bevel=0.004)  # the well
    b.box((-0.06, 0, -0.03), (0.014, 0.024, 0.012), D, bevel=0, detail=True)  # magazine release
    for y in (-0.031, 0.031):
        b.box((0.0, y, 0.0), (0.03, 0.004, 0.014), D, bevel=0, detail=True)  # selector
    # Pistol grip, guard and trigger: the Tommy gun's (its sockets fit the Soldier's hand, #460).
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, K, bevel=0.008)  # fmt: skip
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, K)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, D)
    # The fixed stock: its top runs on from the receiver's, the bottom drops to a near-upright butt.
    b.prism([(0.03, 0.01), (0.12, -0.005), (0.268, -0.058), (0.284, -0.054), (0.278, 0.084), (0.03, 0.098)],
            -0.027, 0.027, K, bevel=0.01)  # fmt: skip
    b.box((0.288, 0, 0.015), (0.014, 0.06, 0.145), D, bevel=0.004, rot=(0, -0.043, 0))  # butt pad


def magazine(b):
    """The curved magazine, Grey so it reads against the black gun: four pieces bent forward at the foot and a floor
    plate. The reload's part: out down along its own axis from the well."""
    pts = [(-0.1, -0.01), (-0.103, -0.075), (-0.115, -0.135), (-0.137, -0.18), (-0.163, -0.212)]
    b.bar(pts, 0.036, 0.062, G, bevel=0.006)
    b.box((-0.166, 0, -0.222), (0.072, 0.042, 0.014), D, bevel=0, rot=(0, -0.9, 0))  # floor plate


def bolt(b):
    """The cocking handle on the left of the tube: a stalk and a knob. Slides back (+X) 0.09 and up into its notch."""
    b.cyl((-0.24, -0.026, 0.074), (-0.24, -0.05, 0.074), 0.006, D, segs=6, bevel=0)
    b.cyl((-0.24, -0.046, 0.074), (-0.24, -0.06, 0.074), 0.012, K, segs=8, bevel=0)  # the knob


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Magazine": (magazine, (-0.10, 0.0, -0.02)),  # the well
        "Bolt": (bolt, (-0.24, -0.026, 0.074)),  # the stalk's root on the tube
    },
    "muzzle": (-0.40, 0.0, BORE),
    "eject": (-0.06, 0.036, 0.06),
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),  # the Tommy gun's
    "trigger": (-0.018, 0.0, -0.038),
    # The hand guard's rear, held from below.
    "support": ((-0.24, 0.0, 0.02), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "ammo": (magazine, (-0.13, 0.0, -0.12)),
}
