"""The shape of a weapon module (#786): copy this file to `weapon_specs/<id>.py` (the model's id, its asset
folder's name: `ppsh`, `mp5`, `m4a1`, `m249`, `fifty_cal`, `pump_870`, `service_pistol`, `ray_gun`, `freeze_gun`) and draw the
weapon. `build_weapons.py` loads every module here whose name does not start with `_`, so this one is never built.

Build and export it like the first ten:

    blender -b --factory-startup -P tools/blender/build_weapons.py -- --only <id>

Axes and units are the first ten's (docs/research/weapon-models.md): 1 unit = 1 m at the weapon's real length, the
muzzle along -X, up +Z, the gun's right side +Y, the origin at the grip (the middle of the handle where the middle
finger wraps). Draw the cross-sections chunky (1.5-2 times real) in the drawing itself and keep `chunk` (1, 1, 1), so
round parts stay round and the hold's `model_scale` is 1.3 x the size factor. Colours are `weaponlib.PALETTE` names.
The numbers below are a placeholder box gun, not a plan: the plan is the page's per-weapon section.
"""

from weaponlib import BEVEL  # noqa: F401  (the 17 mm chamfer every receiver, stock and barrel end takes)


def body(b):
    """The main node: everything that does not move in the reload."""
    b.box((-0.15, 0, 0.03), (0.30, 0.07, 0.10), "Grey")  # receiver: the big grey block, at least 0.26 m long
    b.cyl((-0.30, 0, 0.05), (-0.60, 0, 0.05), 0.02, "DarkGrey", segs=10, bevel=0)  # barrel
    b.cyl((-0.60, 0, 0.05), (-0.604, 0, 0.05), 0.011, "Black", segs=8, bevel=0, detail=True)  # bore: far drops it
    b.prism(
        [(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.034, -0.145), (0.005, -0.06)],
        -0.024,
        0.024,
        "Black",
        bevel=0.008,
    )  # fmt: skip  (pistol grip)
    b.bar(
        [(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, "Grey"
    )  # fmt: skip  (trigger guard: deep enough for the Soldier's finger, #460)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, "Black")  # trigger


def magazine(b):
    """A moving node: drawn where it sits on the gun; `SPEC["nodes"]` gives the pivot it turns or slides from."""
    b.box((-0.10, 0, -0.08), (0.05, 0.035, 0.14), "Black", bevel=0.006)


SPEC = {
    "build": body,
    "chunk": (1.0, 1.0, 1.0),
    # {node name: (builder, pivot)}: the reload's moving parts, each its own node under the weapon.
    "nodes": {"Magazine": (magazine, (-0.10, 0.0, -0.01))},
    "muzzle": (-0.60, 0.0, 0.05),  # the centre of the barrel's open end (the bore disc may stand up to 4 mm proud)
    "eject": (-0.12, 0.036, 0.05),  # the centre of the ejection port on the right side
    # (origin, up, front): the right hand's handle (see GRIPS in build_weapons.py).
    "grip": ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0)),
    "trigger": (-0.018, 0.0, -0.038),  # the middle of the trigger's front face
    # (origin, up, front): the left hand's handle; two-handed guns only.
    "support": ((-0.37, 0.0, -0.02), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6)),
    # (builder, centre): what the left hand brings in the reload, exported to `<id>_ammo.glb`.
    "ammo": (magazine, (-0.10, 0.0, -0.08)),
}
