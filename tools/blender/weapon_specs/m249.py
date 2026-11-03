"""The M249 (`m249`, #796): a belt-fed light machine gun of the SAW type (docs/research/weapon-models.md#m249-m249-796).

Drawn at 0.93 m (muzzle -0.62, butt +0.31: the real gun is 1.04 m, its stock shortened as the .50's) with the cross-sections about 1.5-2 times real; the origin is the
pistol grip, behind the trigger (the Tommy gun's grip, guard, trigger and sockets). Its read: the green ammo box
hanging under the left of the receiver with the belt rising from it, the carry handle over the barrel, a long black
body. Studied from public-domain photos (refs/weapons/m249/); a generic type, no maker's marks.

The reload's parts are their own nodes: `Cover` (the feed cover, turns up on its front hinge), `Box` (the ammo box,
off down), `Belt` (the belt from the box into the feed tray, shown and hidden with the box) and `Bolt` (the charging
handle on the right, back +X 0.10).
"""

G, D, K, GN, Y = "Grey", "DarkGrey", "Black", "Green", "Yellow"
BORE = 0.05


def pistol_grip(b, colour=K, guard=D):
    """The Tommy gun's pistol grip, guard (deep enough for the Soldier's finger, #460) and trigger."""
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, colour, bevel=0.008)  # fmt: skip
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, guard)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, K)


def body(b):
    """Everything that stays put in the reload."""
    # Receiver: the long black box, a rear sight behind the feed cover, the feed tray's lip on the left, the low
    # ejection port on the right, a plate under the front where the left hand rides.
    b.box((-0.135, 0, 0.04), (0.33, 0.085, 0.12), K)
    b.box((0.0, 0, 0.108), (0.05, 0.04, 0.016), D, bevel=0)  # rear sight base
    b.box((0.0, 0, 0.125), (0.012, 0.03, 0.022), K, bevel=0, detail=True)  # rear sight leaf
    b.box((-0.14, -0.047, 0.07), (0.1, 0.012, 0.03), D, bevel=0)  # feed tray lip on the left
    b.box((-0.10, 0.0435, 0.0), (0.09, 0.004, 0.03), D, bevel=0, detail=True)  # ejection port, low on the right
    b.box((-0.24, 0.0445, 0.045), (0.11, 0.004, 0.012), D, bevel=0, detail=True)  # the charging handle's slot
    for y in (-0.044, 0.044):
        b.box((-0.03, y, 0.065), (0.014, 0.006, 0.014), D, bevel=0, detail=True)  # pins
    # Hand guard under the barrel's root and the receiver's front: where the left hand holds the gun from below, its
    # rear within the Soldier's left arm.
    b.box((-0.34, 0, 0.01), (0.18, 0.072, 0.072), K, bevel=0.012)
    for x in (-0.405, -0.37, -0.335, -0.30):
        b.box((x, 0, -0.027), (0.012, 0.06, 0.004), D, bevel=0, detail=True)  # ribs underneath
    # Barrel, the gas tube under it, the gas block and front sight, the flash hider.
    b.cyl((-0.30, 0, BORE), (-0.58, 0, BORE), 0.022, D, segs=12, bevel=0)
    b.cyl((-0.30, 0, BORE), (-0.33, 0, BORE), 0.03, D, segs=12, bevel=0.006)  # barrel collar
    b.cyl((-0.44, 0, 0.005), (-0.50, 0, 0.005), 0.015, D, segs=8, bevel=0)  # gas tube
    b.box((-0.51, 0, 0.03), (0.04, 0.04, 0.07), D, bevel=0.006)  # gas block
    b.box((-0.51, 0, 0.09), (0.016, 0.01, 0.05), K, bevel=0)  # front sight post
    b.cyl((-0.58, 0, BORE), (-0.62, 0, BORE), 0.027, K, segs=10, bevel=0.004)  # flash hider
    for z in (BORE + 0.02, BORE - 0.02):
        b.box((-0.605, 0, z), (0.026, 0.06, 0.005), D, bevel=0, detail=True)  # its slots
    b.cyl((-0.62, 0, BORE), (-0.624, 0, BORE), 0.012, D, segs=8, bevel=0, detail=True)  # bore
    # The carry handle: one arm up from the barrel's collar, the grip running back over the barrel.
    b.bar([(-0.40, 0.07), (-0.38, 0.155)], 0.016, 0.016, D)
    b.box((-0.345, 0, 0.158), (0.1, 0.03, 0.026), K, bevel=0.006)
    # The folded bipod under the barrel: a clamp and two legs lying back along the hand guard's sides.
    b.box((-0.535, 0, 0.0), (0.03, 0.05, 0.03), D, bevel=0)
    for y in (-0.03, 0.03):
        b.box((-0.495, y, -0.005), (0.09, 0.012, 0.012), D, bevel=0, detail=True)
    # The box's seat under the receiver, on the left.
    b.box((-0.14, -0.02, -0.03), (0.12, 0.07, 0.02), D, bevel=0)
    # Trigger housing, the pistol grip.
    b.box((-0.01, 0, -0.025), (0.08, 0.05, 0.02), K, bevel=0)
    pistol_grip(b)
    # Stock: a long black triangle with a butt plate.
    # Shorter than the real one's (+0.42; +0.31 here with the plate), as the .50's: with the butt at the shoulder, the hand guard stays within the
    # Soldier's left arm (the shoulder to the support about 0.70 m in the game, the double's).
    b.prism([(0.02, 0.085), (0.12, 0.075), (0.285, 0.05), (0.30, -0.07), (0.26, -0.075), (0.12, -0.02),
             (0.02, -0.02)], -0.032, 0.032, K, bevel=0.012)  # fmt: skip
    b.box((0.30, 0, -0.01), (0.02, 0.07, 0.125), D, bevel=0.004, rot=(0, -0.1, 0))


def cover(b):
    """The feed cover: a flat lid over the receiver's front half, hinged at its front edge."""
    b.box((-0.135, 0, 0.11), (0.27, 0.088, 0.03), D, bevel=0.008)
    b.box((-0.03, 0, 0.128), (0.04, 0.06, 0.008), K, bevel=0, detail=True)  # latch


def box(b):
    """The ammo box, green, with a lid ridge and a latch."""
    b.box((-0.14, -0.02, -0.12), (0.14, 0.10, 0.12), GN, bevel=0.012)
    b.box((-0.14, -0.02, -0.058), (0.146, 0.106, 0.012), GN, bevel=0, detail=True)  # lid ridge
    b.box((-0.14, -0.072, -0.08), (0.03, 0.006, 0.02), D, bevel=0, detail=True)  # latch


def belt(b):
    """Five rounds on their links rising from the box into the feed tray on the left."""
    for i in range(5):
        z = -0.045 + 0.024 * i
        b.cyl((-0.11, -0.058, z), (-0.17, -0.058, z), 0.009, Y, segs=6, bevel=0)  # round
        b.cyl((-0.17, -0.058, z), (-0.185, -0.058, z), 0.004, Y, segs=6, bevel=0, detail=True)  # bullet
        b.box((-0.10, -0.058, z), (0.016, 0.024, 0.02), D, bevel=0, detail=True)  # link


def bolt(b):
    """The charging handle on the right."""
    b.box((-0.21, 0.056, 0.045), (0.024, 0.024, 0.018), K, bevel=0)


def ammo(b):
    """A full box with a belt stub, what the left hand brings."""
    box(b)
    for i in range(2):
        z = -0.045 + 0.024 * i
        b.cyl((-0.11, -0.058, z), (-0.17, -0.058, z), 0.009, Y, segs=6, bevel=0)
        b.box((-0.10, -0.058, z), (0.016, 0.024, 0.02), D, bevel=0)


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Cover": (cover, (-0.27, 0.0, 0.11)),  # the front hinge: the rear lifts 70 degrees
        "Box": (box, (-0.14, -0.02, -0.06)),  # the top of the box, under its seat
        "Belt": (belt, (-0.14, -0.058, 0.06)),  # where the belt enters the feed tray
        "Bolt": (bolt, (-0.21, 0.056, 0.045)),  # the handle: slides back +X 0.10
    },
    "muzzle": (-0.62, 0.0, BORE),
    "eject": (-0.10, 0.0435, 0.0),  # the port, low on the right
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),
    "trigger": (-0.018, 0.0, -0.038),
    # Under the hand guard: the gunner's left hand holds the gun from below.
    "support": ((-0.30, 0.0, -0.025), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "ammo": (ammo, (-0.14, -0.02, -0.10)),
}
