"""The perk bottle (`perk_bottle`, Deadnight #912): what the Soldier drinks a perk from. Not a weapon: the drink clip
(`Drink_Perk`) puts it in the right fist in the weapon's place, the left hand twists its cap off, and it is thrown
away empty. One model for the six perks; the game colours it per perk (`PerkBottle`): the glass in the drink's colour
of the perk's machine, the label band in the machine's body colour, the cap left chrome.

A plain 1950s soda bottle of our own: a straight body with a raised label band, a round shoulder, a tapering neck
with a lip and a crown cap. Drawn at a real 0.21 m with the body 7 cm across (a real one is 6), chunky as the kit
draws its small things; the hold (`holds/perk_bottle.tres`) shows it at 0.35 m in the hand, as the grenade is drawn
two times real so the fist does not hide it. Stands up along +Z; the origin (the grip) is the middle of the body below
the label, where the fist closes, so the neck stands out of the thumb's side. Its nodes: `Label` (the band, coloured
apart) and `Cap` (pops off at the clip's `cap_off`, pivot on the lip).
"""

import math

GLASS, LABEL, CAP = "Frost", "Tan", "Grey"

# (radius, z): the glass from the base up, the chamfers in the profile (a lathe is never bevelled again).
GLASS_PROFILE = [(0.0, -0.075), (0.027, -0.075), (0.033, -0.071), (0.035, -0.064), (0.035, 0.036), (0.033, 0.046),
                 (0.028, 0.058), (0.021, 0.07), (0.015, 0.082), (0.0125, 0.096), (0.0115, 0.122), (0.0145, 0.125),
                 (0.0145, 0.131), (0.012, 0.133), (0.0, 0.133)]  # fmt: skip
LIP = 0.133
# The label band stands 1.5 mm proud of the body, between these heights.
LABEL_PROFILE = [(0.0345, -0.03), (0.0365, -0.028), (0.0365, 0.022), (0.0345, 0.024)]
# A crown cap: a short skirt with a crimped edge (the crimp is the far level's first loss) and a flat top.
CAP_PROFILE = [(0.0, LIP - 0.004), (0.016, LIP - 0.004), (0.0165, LIP + 0.002), (0.0155, LIP + 0.009),
               (0.012, LIP + 0.012), (0.0, LIP + 0.012)]  # fmt: skip


def glass(b):
    """The main node: the glass, full of the perk's drink."""
    b.lathe(GLASS_PROFILE, GLASS, segs=16)


def label(b):
    b.lathe(LABEL_PROFILE, LABEL, segs=16)


def cap(b):
    b.lathe(CAP_PROFILE, CAP, segs=12)
    for i in range(6):  # the crimp: six small teeth round the skirt
        a = 2 * math.pi * i / 6
        b.box((0.0165 * math.cos(a), 0.0165 * math.sin(a), LIP + 0.002), (0.004, 0.006, 0.008), CAP, bevel=0,
              rot=(0, 0, a), detail=True)  # fmt: skip


SPEC = {
    "build": glass,
    "chunk": (1.0, 1.0, 1.0),
    "nodes": {"Label": (label, (0.0, 0.0, 0.0)), "Cap": (cap, (0.0, 0.0, LIP))},
    # The fist's handle: the body, up the bottle toward the neck (the index finger's side), the straight fingers
    # pointing -X (any way: the bottle is round).
    "grip": ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (-1.0, 0.0, 0.0)),
}
