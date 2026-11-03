"""The pump shotgun (`pump_870`, #796): a pump-action 12 gauge of the 870 type with a pistol-grip stock
(docs/research/weapon-models.md#870-style-pump-shotgun-pump_870-796).

Drawn at 0.92 m (muzzle -0.62, butt +0.30: the real gun is 0.98 m, its stock shortened so the pump is in reach) with the cross-sections about 1.5-2 times real; the origin is the
pistol grip, behind the trigger (the Tommy gun's grip, guard, trigger and sockets). Its read against the double: one
barrel over a full-length magazine tube, the ribbed black pump with the bare tube showing either side of it, a grey
receiver and a black pistol-grip stock. Studied from photos (refs/weapons/pump_870/); a generic type, no maker's marks.

The reload's part is its own node: `Pump` (the fore-end, slides back +X 0.045 along the tube, its rear then
5 mm short of the receiver, and forward again, after each shot and at the end of the reload). Shells go in one by one through the loading port under the receiver.
"""

G, D, K, R, Y = "Grey", "DarkGrey", "Black", "Red", "Yellow"
BORE = 0.05
TUBE = 0.0  # the magazine tube's axis height


def pistol_grip(b, colour=K, guard=D):
    """The Tommy gun's pistol grip, guard (deep enough for the Soldier's finger, #460) and trigger."""
    b.prism([(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
            -0.024, 0.024, colour, bevel=0.008)  # fmt: skip
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, guard)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, K)


def body(b):
    """Everything that stays put in the reload."""
    # Receiver: the grey slab, the ejection port on the right, the loading port underneath, a safety button.
    b.box((-0.09, 0, 0.032), (0.26, 0.072, 0.104), G)
    b.box((-0.08, 0.0365, 0.05), (0.09, 0.004, 0.036), K, bevel=0, detail=True)  # ejection port
    b.box((-0.12, 0, -0.0215), (0.09, 0.04, 0.004), K, bevel=0)  # loading port
    b.cyl((0.02, -0.04, -0.005), (0.02, 0.04, -0.005), 0.007, K, segs=6, bevel=0, detail=True)  # safety
    for x in (-0.18, -0.02):
        b.cyl((x, -0.038, 0.01), (x, 0.038, 0.01), 0.006, D, segs=6, bevel=0, detail=True)  # trigger plate pins
    # Barrel: the collar at the receiver, a bead at the muzzle; the magazine tube under it with its cap, a band
    # joining the two at the front.
    b.cyl((-0.22, 0, BORE), (-0.62, 0, BORE), 0.026, D, segs=12, bevel=0)
    b.cyl((-0.22, 0, BORE), (-0.25, 0, BORE), 0.031, D, segs=12, bevel=0.006)
    b.cyl((-0.62, 0, BORE), (-0.624, 0, BORE), 0.017, K, segs=8, bevel=0, detail=True)  # bore
    b.box((-0.605, 0, BORE + 0.031), (0.012, 0.012, 0.012), G, bevel=0)  # bead
    b.cyl((-0.22, 0, TUBE), (-0.575, 0, TUBE), 0.024, D, segs=10, bevel=0)
    b.cyl((-0.575, 0, TUBE), (-0.60, 0, TUBE), 0.027, G, segs=10, bevel=0.006)  # cap
    b.box((-0.555, 0, 0.025), (0.022, 0.034, 0.06), G, bevel=0)  # band
    pistol_grip(b)
    # Stock: a black buttstock on the pistol grip, a dark recoil pad.
    # Shorter than the real one's (+0.36; +0.30 here with the pad), so with the butt at the shoulder the pump stays
    # within the Soldier's left arm.
    b.prism([(0.03, 0.075), (0.12, 0.065), (0.27, 0.05), (0.285, -0.09), (0.245, -0.095), (0.12, -0.02),
             (0.03, -0.02)], -0.032, 0.032, K, bevel=0.012)  # fmt: skip
    b.box((0.29, 0, -0.02), (0.02, 0.07, 0.145), D, bevel=0.004, rot=(0, -0.1, 0))
    # A side saddle of four shells on the left, heads up.
    b.box((-0.10, -0.041, 0.035), (0.13, 0.01, 0.05), K, bevel=0)
    for i in range(4):
        x = -0.145 + 0.03 * i
        b.cyl((x, -0.056, 0.0), (x, -0.056, 0.06), 0.012, R, segs=6, bevel=0, detail=True)
        b.cyl((x, -0.056, 0.06), (x, -0.056, 0.072), 0.013, Y, segs=6, bevel=0, detail=True)


def pump(b):
    """The pump: a black fore-end round the tube, ribbed, with the bare tube showing either side."""
    # Deep enough to hang below the tube as a block (7 cm in the game, what reads on a phone at 8 m).
    b.box((-0.35, 0, -0.022), (0.16, 0.08, 0.088), K, bevel=0.014)  # under the barrel, round the tube
    for x in (-0.415, -0.385, -0.355, -0.325, -0.295):
        b.box((x, 0, -0.022), (0.012, 0.088, 0.094), K, bevel=0, detail=True)  # ribs


def shell(b):
    """One red shell with a brass head, the size of the bore, what the left hand brings."""
    b.cyl((-0.045, 0, 0.0), (0.03, 0, 0.0), 0.026, R, segs=10, bevel=0.004)
    b.cyl((0.03, 0, 0.0), (0.05, 0, 0.0), 0.029, Y, segs=10, bevel=0.003)


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {"Pump": (pump, (-0.35, 0.0, TUBE))},  # slides back +X 0.045 along the tube, to the receiver
    "muzzle": (-0.62, 0.0, BORE),
    "eject": (-0.08, 0.0365, 0.05),
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),
    "trigger": (-0.018, 0.0, -0.038),
    # On the pump: the hand rides it (the hold's support follows the `Pump` node's slide).
    "support": ((-0.32, 0.0, -0.02), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    "ammo": (shell, (0.0, 0.0, 0.0)),
}
