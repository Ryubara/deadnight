"""The ray gun (#797; the plan: docs/research/weapon-models.md, "Ray gun"): our own design, the drive-in's wonder weapon.

A projection pistol: a blue energy pistol that throws its bolt through a lens the way the projector throws the film.
Its read is the wide round lens barrel (0.08 m across: twice the pistols' signature rule) and the glowing cell lying
in the open body, seen from the side through a notch in the side plates and from above. Not the genre's ray gun: no
ring stack or fins round the barrel, no dish, no green. Everything that burns is the palette's Glow cell (the lens,
the cell's core, three vents), which the game lights with an emission texture of the atlas's layout (`ModelGlow`).
Drawn at 0.30 m, held as a pistol at 2.275 (the revolver's size factor 1.75); the origin is the grip.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only ray_gun
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _revolve import revolve_x

BORE = 0.05  # the lens barrel's axis height
CELL = (-0.03, 0.0, 0.065)  # the cell's centre: lying along the body, under the open top
B, G, K, L = "Blue", "Grey", "Black", "Glow"


def body(b):
    """The lens barrel, the open body, the grip: everything but the cell and the lid."""
    # The lens barrel (the signature mass), its Grey bezel ring, the Glow lens set 3 mm inside the ring.
    b.cyl((-0.098, 0, BORE), (-0.19, 0, BORE), 0.04, B, segs=12, bevel=0.006)
    revolve_x(b, [(-0.188, 0.031), (-0.188, 0.044), (-0.2, 0.044), (-0.2, 0.031)], G, segs=12,
              z=BORE, closed=True)  # fmt: skip
    b.cyl((-0.185, 0, BORE), (-0.197, 0, BORE), 0.032, L, segs=12, bevel=0)  # the lens
    for x in (-0.17, -0.15, -0.13):
        b.box((x, 0, BORE + 0.039), (0.007, 0.034, 0.006), L, bevel=0, detail=True)  # vents on the barrel's top
    b.cyl((-0.11, 0, BORE), (-0.09, 0, BORE), 0.046, G, segs=12, bevel=0, detail=True)  # collar at the body
    # The open body: two Blue side plates notched over the cell, a floor, a rear wall.
    notch = [(-0.11, 0.005), (0.06, 0.005), (0.06, 0.1), (0.032, 0.1), (0.02, 0.07), (-0.07, 0.07), (-0.082, 0.1),
             (-0.11, 0.1)]  # fmt: skip
    for y in (-0.034, 0.022):
        b.prism(notch, y, y + 0.012, B, bevel=0.005)
    b.box((-0.025, 0, 0.016), (0.17, 0.05, 0.022), B, bevel=0.005)  # floor
    b.box((0.054, 0, 0.055), (0.012, 0.05, 0.09), B, bevel=0)  # rear wall
    b.cyl((0.06, 0, 0.055), (0.078, 0, 0.055), 0.016, G, segs=8, bevel=0, detail=True)  # the focus knob at the back
    b.box((-0.1, 0, 0.088), (0.03, 0.05, 0.024), B, bevel=0)  # the front wall over the cell's end
    # Grip: the flare gun's raked grip in Black with proud plates, a Grey butt plate; round Grey guard; trigger.
    b.prism([(-0.01, 0.01), (0.022, 0.01), (0.04, -0.03), (0.062, -0.094), (0.026, -0.1), (0.008, -0.05),
             (-0.008, -0.016)], -0.019, 0.019, K, bevel=0.005)  # fmt: skip
    b.prism([(0.0, -0.004), (0.028, -0.004), (0.054, -0.086), (0.028, -0.09)], -0.022, 0.022, K, bevel=0, detail=True)
    b.box((0.045, 0, -0.098), (0.04, 0.042, 0.01), G, bevel=0, rot=(0, -0.3, 0))
    b.bar([(-0.04, 0.008), (-0.042, -0.024), (-0.025, -0.04), (-0.002, -0.035), (0.006, -0.012)], 0.014, 0.009, G)
    b.bar([(-0.016, 0.006), (-0.02, -0.018), (-0.012, -0.028)], 0.009, 0.009, K)


def cell(b):
    """The energy cell: a Glow core between two Grey end caps and a Grey band. The reload's part: it slides out
    back and up (+X 0.10) once the lid is open."""
    x, y, z = CELL
    b.cyl((x - 0.04, y, z), (x + 0.04, y, z), 0.018, L, segs=10, bevel=0)
    for x0, x1 in ((x - 0.06, x - 0.038), (x + 0.038, x + 0.06)):
        b.cyl((x0, y, z), (x1, y, z), 0.021, G, segs=10, bevel=0)  # end caps
    b.cyl((x - 0.006, y, z), (x + 0.006, y, z), 0.02, G, segs=10, bevel=0, detail=True)  # the middle band


def lid(b):
    """The hinged lid over the body's rear and the cell's back cap: turns 80 degrees up on its front edge."""
    b.box((0.031, 0, 0.106), (0.062, 0.07, 0.012), G, bevel=0.004)
    b.box((0.06, 0, 0.098), (0.008, 0.03, 0.014), K, bevel=0, detail=True)  # the latch


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Lid": (lid, (0.0, 0.0, 0.1)),  # the hinge on its front edge
        "Cell": (cell, CELL),  # the cell's centre: slides out back and up
    },
    "muzzle": (-0.2, 0.0, BORE),  # the bezel's front face, on the lens's axis
    # The flare gun's grip and trigger (the same raked grip).
    "grip": ((0.026, 0.0, -0.056), (-0.37, 0.0, 0.93), (-1.0, 0.0, 0.0)),
    "trigger": (-0.023, 0.0, -0.012),
    "ammo": (cell, CELL),
}
