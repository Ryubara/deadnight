"""The service pistol the dual pistols carry (#797; the plan: docs/research/weapon-models.md, "Service pistol").

A period semi-automatic service pistol of the 1911 type, a generic one (no maker's marks): a long Black slide over a
DarkGrey frame, Wood grip panels on a grip raked 18 degrees back, a round hammer spur, a grip safety's tang and a round
guard deep enough for the Soldier's finger (#460). Studied from public photos (workspace `refs/weapons/service_pistol/`)
for shape and proportion only. Drawn at the real 0.21 m with the cross-sections about twice real, as the revolver is;
the origin is the grip. One model held in both hands (#789): the left hand's copy is the same mesh, not mirrored.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only service_pistol
"""

BORE = 0.045  # the barrel's axis height
D, K, G, W, Y = "DarkGrey", "Black", "Grey", "Wood", "Yellow"


def body(b):
    """The frame, the grip and everything else that stays when the slide runs back and the magazine drops."""
    # Frame: the dust cover under the slide's front, the block round the trigger, the slide rails' top line.
    b.box((-0.085, 0, 0.021), (0.13, 0.034, 0.02), D, bevel=0.005)  # dust cover
    b.box((0.0, 0, 0.016), (0.09, 0.036, 0.034), D, bevel=0.005)  # frame over the trigger and the grip's top
    b.box((-0.025, 0.019, 0.021), (0.03, 0.006, 0.01), K, bevel=0, detail=True)  # slide stop lever (right)
    b.cyl((-0.06, -0.02, 0.021), (-0.06, 0.02, 0.021), 0.005, K, segs=6, bevel=0, detail=True)  # its pin
    # Grip: the DarkGrey frame raked back, Wood panels proud on both sides, the mainspring housing at the back.
    b.prism([(-0.012, 0.004), (0.04, 0.004), (0.074, -0.1), (0.022, -0.1)], -0.017, 0.017, D, bevel=0.005)
    b.prism([(-0.004, -0.008), (0.034, -0.008), (0.062, -0.09), (0.024, -0.09)], -0.021, 0.021, W, bevel=0.004)
    for y in (-0.022, 0.022):
        for x, z in ((0.012, -0.02), (0.04, -0.08)):
            b.cyl((x, y * 0.98, z), (x, y * 1.12, z), 0.005, K, segs=4, bevel=0, detail=True)  # grip screws
    # The grip safety's tang over the web of the hand and the round hammer spur above it.
    b.bar([(0.03, 0.02), (0.058, 0.03), (0.068, 0.026)], 0.03, 0.012, D)
    b.cyl((0.052, -0.008, 0.07), (0.052, 0.008, 0.07), 0.013, K, segs=10, bevel=0)  # hammer spur
    b.bar([(0.038, 0.05), (0.05, 0.068)], 0.014, 0.012, K)  # hammer neck
    # Trigger guard (round, as deep as the revolver's for the Soldier's finger) and the trigger.
    b.bar([(-0.058, 0.01), (-0.06, -0.022), (-0.044, -0.04), (-0.014, -0.04), (0.0, -0.016)], 0.014, 0.008, D)
    b.bar([(-0.026, 0.004), (-0.028, -0.014), (-0.022, -0.026)], 0.009, 0.008, K)


def slide(b):
    """The slide: the long Black block over the frame with the sights, the ejection port on the right, the rear
    serrations and the barrel's end in the bushing. Runs back +X 0.05 at the shot and locks back on empty."""
    b.box((-0.065, 0, 0.0525), (0.21, 0.04, 0.045), K, bevel=0.006)
    b.cyl((-0.17, 0, BORE), (-0.173, 0, BORE), 0.013, D, segs=10, bevel=0)  # barrel bushing
    b.cyl((-0.173, 0, BORE), (-0.175, 0, BORE), 0.008, K, segs=8, bevel=0, detail=True)  # the bore
    b.box((-0.155, 0, 0.08), (0.012, 0.008, 0.01), K, bevel=0)  # front sight
    b.box((0.026, 0, 0.08), (0.012, 0.03, 0.012), K, bevel=0)  # rear sight
    b.box((-0.06, 0.0205, 0.064), (0.044, 0.004, 0.016), G, bevel=0, detail=True)  # ejection port, the chamber
    for i in range(3):
        x = 0.004 + 0.01 * i
        for y in (-0.0205, 0.0205):
            b.box((x, y, 0.052), (0.004, 0.003, 0.032), D, bevel=0, detail=True)  # rear serrations


def magazine(b):
    """The magazine in the grip, raked with it: a DarkGrey box, a Yellow round at its lips and a Black floor plate.
    Hidden in the grip but for the plate; drops out the bottom along the grip (the reload's part)."""
    b.prism([(0.0, -0.002), (0.028, -0.002), (0.058, -0.096), (0.03, -0.096)], -0.013, 0.013, D, bevel=0.003)
    b.box((0.048, 0, -0.104), (0.05, 0.03, 0.012), K, bevel=0)  # floor plate, under the grip's flat foot
    b.cyl((0.0, 0, 0.0), (0.02, 0, 0.0), 0.007, Y, segs=6, bevel=0, detail=True)  # the top round


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Slide": (slide, (0.04, 0.0, 0.0525)),  # the slide's rear: it runs back along +X
        "Magazine": (magazine, (0.035, 0.0, -0.10)),  # the magazine well's foot: it drops along the grip (-Z)
    },
    "muzzle": (-0.17, 0.0, BORE),  # the slide's front face on the bore (the bushing stands 3-5 mm proud)
    "eject": (-0.06, 0.02, 0.065),  # the ejection port on the slide's right
    # The revolver's grip, the rake a little straighter (the grip runs 18 degrees back).
    "grip": ((0.032, 0.0, -0.058), (-0.31, 0.0, 0.95), (-1.0, 0.0, 0.0)),
    "trigger": (-0.03, 0.0, -0.012),
    "ammo": (magazine, (0.044, 0.0, -0.05)),
}
