"""The house pistol, every player's starting gun (#898; the plan: docs/research/weapon-models.md, "House pistol").

A 9 mm double-action service pistol of the 1980s type, generic (no maker's marks): a pale Grey slide over a Black
frame, the slide cut open over the barrel (the barrel and its locking block show in the cut, the one feature that
reads at 40 px a metre), a squared trigger guard with a hooked front, a Black grip with a flared foot and a lanyard
ring, a safety lever on the slide's rear. It reads apart from the 1911 type of the dual pistols (`service_pistol`:
a Black slide over a DarkGrey frame, Wood panels and a round guard) by its slide colour, its open cut, its squared guard
and its plain grip. Drawn at the real 0.22 m with the cross-sections about twice real, as the other pistols are; the
origin is the grip. The grip, the trigger and the magazine sit where the service pistol's do, so the hold, the grip
solve and the reload start from a pistol that is known to fit the Soldier's hand.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only house_pistol
"""

BORE = 0.045  # the barrel's axis height
D, K, G, G2, Y = "DarkGrey", "Black", "Grey", "Grey2", "Yellow"


def body(b):
    """The frame, the grip and everything else that stays when the slide runs back and the magazine drops."""
    # Frame: the dust cover with its rail under the slide's front, the block round the trigger.
    b.box((-0.09, 0, 0.02), (0.12, 0.034, 0.02), K, bevel=0.005)  # dust cover
    b.box((0.0, 0, 0.016), (0.09, 0.036, 0.034), K, bevel=0.005)  # frame over the trigger and the grip's top
    b.box((-0.125, 0, 0.008), (0.05, 0.026, 0.008), D, bevel=0, detail=True)  # the accessory rail's lugs
    # The locking block and the barrel's breech, seen through the slide's cut.
    b.box((-0.07, 0, 0.034), (0.04, 0.02, 0.02), D, bevel=0.003)
    # Grip: a Black frame raked back with a flared foot, Grey2 panel inlays proud on both sides (the plain grip).
    b.prism([(-0.012, 0.004), (0.04, 0.004), (0.078, -0.1), (0.018, -0.1)], -0.018, 0.018, K, bevel=0.005)
    b.prism([(0.0, -0.01), (0.034, -0.01), (0.062, -0.088), (0.026, -0.088)], -0.021, 0.021, G2, bevel=0.004)
    for y in (-0.022, 0.022):
        for x, z in ((0.014, -0.022), (0.04, -0.078)):
            b.cyl((x, y * 0.98, z), (x, y * 1.12, z), 0.005, K, segs=4, bevel=0, detail=True)  # grip screws
    b.bar([(0.074, -0.1), (0.086, -0.108), (0.084, -0.12)], 0.01, 0.01, D)  # the lanyard ring at the foot
    # The beavertail over the web of the hand.
    b.bar([(0.03, 0.02), (0.06, 0.03), (0.07, 0.024)], 0.03, 0.012, K)
    # Trigger guard: squared, with the hooked front, deep enough for the Soldier's finger (#460).
    b.bar([(-0.058, 0.01), (-0.062, -0.04), (-0.014, -0.04), (-0.004, -0.014)], 0.014, 0.008, K)
    b.bar([(-0.058, 0.002), (-0.066, -0.01)], 0.012, 0.008, K)  # the hook's lip, forward
    b.bar([(-0.026, 0.004), (-0.028, -0.014), (-0.022, -0.026)], 0.009, 0.008, D)  # trigger


def slide(b):
    """The slide: a Grey block over the frame with the large cut over the barrel, a Black barrel in the cut, sights, a
    safety lever and the rear serrations. Runs back +X 0.05 at the shot and locks back on empty."""
    b.box((0.0, 0, 0.0525), (0.092, 0.042, 0.045), G, bevel=0.006)  # the rear block with the breech face
    b.box((-0.135, 0, 0.0495), (0.07, 0.04, 0.039), G, bevel=0.006)  # the nose in front of the cut
    for y in (-0.0155, 0.0155):
        b.box((-0.066, y, 0.045), (0.055, 0.01, 0.034), G, bevel=0.003)  # the side walls round the cut
    b.cyl((-0.046, 0, BORE), (-0.171, 0, BORE), 0.011, D, segs=10, bevel=0)  # the barrel in the cut and in the nose
    b.cyl((-0.17, 0, BORE), (-0.18, 0, BORE), 0.0125, K, segs=10, bevel=0)  # the barrel's nose past the slide
    b.cyl((-0.18, 0, BORE), (-0.182, 0, BORE), 0.007, K, segs=8, bevel=0, detail=True)  # the bore
    b.box((-0.158, 0, 0.073), (0.012, 0.008, 0.01), K, bevel=0)  # front sight
    b.box((0.03, 0, 0.0795), (0.012, 0.032, 0.012), K, bevel=0)  # rear sight
    b.cyl((0.02, 0.0215, 0.052), (0.02, 0.0285, 0.052), 0.009, K, segs=8, bevel=0, detail=True)  # safety lever (right)
    b.cyl((0.02, -0.0215, 0.052), (0.02, -0.0285, 0.052), 0.009, K, segs=8, bevel=0, detail=True)  # (left)
    for i in range(3):
        x = 0.026 + 0.01 * i
        for y in (-0.021, 0.021):
            b.box((x, y, 0.0505), (0.004, 0.003, 0.03), D, bevel=0, detail=True)  # rear serrations


def magazine(b):
    """The magazine in the grip, raked with it: a Black box, a Yellow round at its lips and a DarkGrey floor plate.
    Hidden in the grip but for the plate; drops out the bottom along the grip (the reload's part)."""
    b.prism([(0.0, -0.002), (0.028, -0.002), (0.058, -0.096), (0.03, -0.096)], -0.013, 0.013, K, bevel=0.003)
    b.box((0.048, 0, -0.104), (0.054, 0.034, 0.012), D, bevel=0)  # floor plate, under the grip's flared foot
    b.cyl((0.0, 0, 0.0), (0.02, 0, 0.0), 0.007, Y, segs=6, bevel=0, detail=True)  # the top round


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Slide": (slide, (0.04, 0.0, 0.0525)),  # the slide's rear: it runs back along +X
        "Magazine": (magazine, (0.035, 0.0, -0.10)),  # the magazine well's foot: it drops along the grip (-Z)
    },
    "muzzle": (-0.18, 0.0, BORE),  # the barrel's nose (the bore disc stands 2 mm proud)
    "eject": (-0.07, 0.02, 0.065),  # the cut's right edge, where the case leaves
    # The service pistol's grip: the same rake and place, so the hand fits as it does there.
    "grip": ((0.032, 0.0, -0.058), (-0.31, 0.0, 0.95), (-1.0, 0.0, 0.0)),
    "trigger": (-0.03, 0.0, -0.012),
    "ammo": (magazine, (0.044, 0.0, -0.05)),
}
