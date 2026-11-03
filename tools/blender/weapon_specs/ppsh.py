"""The PPSh (#795): a WWII drum-fed submachine gun, an original take on the type (no maker's marks), drawn from public
reference photos in the workspace's `refs/weapons/ppsh/` (docs/research/weapon-models.md#ppsh-ppsh-795).

Its read against the Tommy gun, the other drum gun: a full wood rifle stock with no pistol grip and no foregrip, the
drum set forward against the guard, and a slotted barrel jacket with a slanted nose. Drawn at the real 0.84 m with the
cross-sections about 1.5-2 times real in the drawing (`chunk` 1, 1, 1), so `model_scale` is the rule's 1.3. Held at
the wrist like the lever rifle; the left hand under the jacket's rear.

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only ppsh
"""

BORE = 0.04  # the barrel's axis height
D, G, G2, K, W = "DarkGrey", "Grey", "Grey2", "Black", "Wood"


def body(b):
    """Everything that stays put in the reload: jacket, receiver, wood stock, guard and trigger."""
    # The barrel jacket: a round tube with two rows of slots each side, ending in the slanted nose (the compensator),
    # its top reaching furthest forward.
    b.cyl((-0.235, 0, BORE), (-0.47, 0, BORE), 0.033, D, segs=12, bevel=0.008)
    b.prism([(-0.488, 0.008), (-0.462, 0.008), (-0.462, 0.072), (-0.506, 0.072)], -0.03, 0.03, D, bevel=0.006)
    b.cyl((-0.49, 0, BORE), (-0.501, 0, BORE), 0.012, K, segs=8, bevel=0, detail=True)  # bore
    b.box((-0.494, 0, 0.083), (0.022, 0.034, 0.024), D, bevel=0)  # front sight hood
    b.box((-0.494, 0, 0.088), (0.008, 0.008, 0.02), K, bevel=0, detail=True)  # its post
    for x in (-0.28, -0.325, -0.37, -0.415):
        for y in (-0.031, 0.031):
            b.box((x, y, BORE), (0.032, 0.006, 0.012), K, bevel=0, detail=True)  # jacket slots
    # Receiver: the long dark block the jacket runs into; the rear sight on top, the ejection port, the cocking
    # handle's slot on the right (the handle is the `Bolt` node).
    b.box((-0.11, 0, 0.04), (0.26, 0.07, 0.09), D, bevel=0.012)
    b.box((-0.215, 0, 0.04), (0.04, 0.074, 0.074), G, bevel=0.006)  # the jacket's collar on the receiver
    b.box((-0.02, 0, 0.093), (0.05, 0.034, 0.014), G, bevel=0)  # rear sight base
    b.box((-0.01, 0, 0.104), (0.01, 0.024, 0.016), K, bevel=0, detail=True)  # its leaf
    b.box((-0.12, 0, 0.0855), (0.06, 0.032, 0.004), K, bevel=0, detail=True)  # ejection port
    b.box((-0.08, 0.0355, 0.05), (0.11, 0.004, 0.012), K, bevel=0, detail=True)  # cocking slot
    b.box((0.012, 0, 0.065), (0.022, 0.06, 0.03), G, bevel=0, detail=True)  # receiver latch
    for y in (-0.036, 0.036):
        b.box((-0.03, y, 0.012), (0.014, 0.006, 0.014), K, bevel=0, detail=True)  # safety and screw
    # The wood stock: from under the receiver back through the wrist (the grip) to the slanted butt, one piece with
    # no pistol grip. The drum's well cuts into its front (the drum is the `Drum` node).
    b.prism([(-0.205, -0.036), (0.03, -0.04), (0.07, -0.058), (0.14, -0.07), (0.345, -0.132), (0.33, 0.03),
             (0.12, 0.018), (0.06, 0.028), (0.035, 0.058), (0.01, 0.058), (0.01, 0.0), (-0.205, 0.0)],
            -0.04, 0.04, W, bevel=0.012)  # fmt: skip
    b.box((0.346, 0, -0.051), (0.016, 0.086, 0.172), G, bevel=0.005, rot=(0, -0.091, 0))  # butt plate
    for z in (0.0, -0.1):
        b.box((0.355, 0, z), (0.004, 0.014, 0.014), K, bevel=0, detail=True)  # butt plate screws
    b.box((-0.15, 0, -0.03), (0.07, 0.05, 0.02), D, bevel=0)  # the drum's well under the receiver
    # Trigger guard (deep enough for the Soldier's finger, #460) and the trigger.
    b.bar([(-0.062, -0.034), (-0.064, -0.086), (-0.042, -0.106), (-0.006, -0.101), (0.03, -0.05)], 0.02, 0.012, G)
    b.bar([(-0.022, -0.035), (-0.026, -0.062), (-0.018, -0.077)], 0.01, 0.01, K)


def drum(b):
    """The drum: a short wide cylinder across Y in Grey2 with a DarkGrey band round its rim, a hub and a winding key
    each side, and its neck into the well. The reload's part (`ammo_is_part`, as the Tommy's): off down and forward."""
    c = (-0.15, -0.10)
    b.cyl((c[0], -0.036, c[1]), (c[0], 0.036, c[1]), 0.093, G2, segs=16, bevel=0.008)
    b.cyl((c[0], -0.016, c[1]), (c[0], 0.016, c[1]), 0.096, D, segs=16, bevel=0)  # the band round the rim
    b.cyl((c[0], -0.04, c[1]), (c[0], 0.04, c[1]), 0.03, D, segs=10, bevel=0)  # hub
    b.box((c[0], -0.043, c[1]), (0.05, 0.006, 0.014), K, bevel=0, detail=True)  # winding key
    b.box((c[0], 0, -0.012), (0.056, 0.04, 0.03), D, bevel=0)  # the neck into the well


def bolt(b):
    """The cocking handle, in its slot on the right: slides back (+X) 0.08 to cock."""
    b.box((-0.11, 0.043, 0.05), (0.02, 0.016, 0.014), G, bevel=0)
    b.box((-0.11, 0.054, 0.05), (0.026, 0.012, 0.022), K, bevel=0.003)  # the knob


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {
        "Drum": (drum, (-0.15, 0.0, -0.10)),  # the drum's centre
        "Bolt": (bolt, (-0.11, 0.036, 0.05)),  # the handle's root in its slot
    },
    "muzzle": (-0.50, 0.0, BORE),  # the bore's front on the slanted nose (its top 6 mm further forward)
    "eject": (-0.10, 0.036, 0.05),
    # The wrist held like the lever rifle's, a stick: the knuckles forward along it, the fingers round its underside.
    "grip": ((0.07, 0.0, -0.02), (-1.0, 0.0, 0.25), (0.0, 0.0, -1.0)),
    "trigger": (-0.031, 0.0, -0.06),
    # Under the jacket's rear, held from below.
    "support": ((-0.33, 0.0, 0.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "ammo": (drum, (-0.15, 0.0, -0.10)),
}
