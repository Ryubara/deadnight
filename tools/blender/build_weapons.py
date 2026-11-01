"""Build Deadnight's original weapons in the Toon Shooter kit's style and export them to glTF.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/build_weapons.py -- [--only lever_rifle] [--out game/assets/weapons]

Writes, for each weapon, `<out>/<name>/<name>.glb` (gameplay: first person and world) and `<name>_far.glb` (the far
level), plus the shared palette `<out>/weapons_palette.png`, and prints one `WEAPON` line per file with its triangle
and part counts. Every number follows the style bible's weapon rules (docs/design/style.md); the part helpers are in
weaponlib.py.

Axes are the kit's: 1 unit = 1 m, up is +Z, a gun's muzzle points along -X and a melee weapon stands up along +Z, thin
across Y. The origin is the grip, where the hand bone holds the weapon with no offset.

Every firearm also carries an empty named `Muzzle` (`MUZZLES`), parented to the weapon at the centre of its barrel's
open end (between the barrels of a double gun), turned so its local +Y points out of the barrel: after the glTF's Y-up
conversion that is the node's -Z in Godot, the engine's forward. The flash and the shot leave from it.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import weaponlib as wl

# Palette names, short.
G, D, K, W, R = "Grey", "DarkGrey", "Black", "Wood", "Red"
G2, GN, Y = "Grey2", "Green", "Yellow"


def lever_rifle(b):
    """A lever-action rifle: round barrel over a tube magazine, a box receiver, a big loop lever, wood stock and forend."""
    # Stock, from the wrist (the grip, at the origin) back to a slanted butt.
    b.prism([(-0.02, 0.05), (0.10, 0.04), (0.37, 0.06), (0.41, -0.115), (0.34, -0.12), (0.10, -0.045),
             (-0.02, -0.045)], -0.048, 0.048, W)  # fmt: skip
    b.box((0.40, 0, -0.03), (0.022, 0.1, 0.18), D, bevel=0.006, rot=(0, -0.22, 0))  # butt plate
    b.box((0.05, 0, 0.056), (0.13, 0.03, 0.012), G, bevel=0)  # upper tang
    for x in (0.0, 0.09):
        b.box((x, 0, 0.064), (0.014, 0.014, 0.006), K, bevel=0, detail=True)  # tang screws
    for x, z in ((0.40, 0.03), (0.422, -0.08)):
        b.box((x, 0, z), (0.006, 0.016, 0.016), K, bevel=0, detail=True)  # butt plate screws
    # Receiver: the main block, a bolt on top, a loading gate on the right, screws both sides.
    b.box((-0.15, 0, 0.01), (0.28, 0.086, 0.14), G)
    b.box((-0.12, 0, 0.086), (0.2, 0.04, 0.022), D, bevel=0.006)  # bolt
    b.box((-0.16, 0.045, -0.02), (0.08, 0.01, 0.036), D, bevel=0)  # loading gate
    for y in (-0.044, 0.044):
        for x, z in ((-0.26, 0.045), (-0.04, 0.045), (-0.15, -0.04)):
            b.box((x, y, z), (0.018, 0.008, 0.018), K, bevel=0, detail=True)
    b.bar([(-0.012, 0.07), (0.008, 0.112), (0.034, 0.122)], 0.022, 0.022, D)  # hammer
    # Barrel over the tube magazine, held by a band; a black bore at the muzzle.
    b.cyl((-0.29, 0, 0.045), (-1.22, 0, 0.045), 0.032, D)
    b.cyl((-1.22, 0, 0.045), (-1.224, 0, 0.045), 0.018, K, bevel=0, detail=True)
    b.cyl((-0.29, 0, -0.02), (-1.06, 0, -0.02), 0.024, D, segs=10, bevel=0)
    b.cyl((-1.06, 0, -0.02), (-1.10, 0, -0.02), 0.027, G, segs=10, bevel=0.008)  # magazine cap
    b.box((-1.0, 0, 0.012), (0.04, 0.074, 0.11), G, bevel=0.008)  # barrel band
    b.box((-1.0, -0.038, 0.012), (0.014, 0.006, 0.014), K, bevel=0, detail=True)  # band screw
    # Forend, with a steel cap.
    b.prism([(-0.29, 0.035), (-0.68, 0.035), (-0.70, 0.0), (-0.68, -0.05), (-0.29, -0.062)], -0.044, 0.044, W)
    b.box((-0.70, 0, -0.005), (0.03, 0.092, 0.092), G, bevel=0.008)
    for y in (-0.045, 0.045):
        b.box((-0.48, y, -0.02), (0.016, 0.006, 0.016), K, bevel=0, detail=True)  # forend screws
    # Sights.
    b.box((-1.17, 0, 0.078), (0.05, 0.03, 0.012), D, bevel=0, detail=True)
    b.box((-1.17, 0, 0.094), (0.03, 0.012, 0.03), K, bevel=0)
    b.box((-0.45, 0, 0.08), (0.04, 0.04, 0.02), D, bevel=0)
    b.box((-0.45, 0, 0.098), (0.012, 0.054, 0.022), K, bevel=0, detail=True)
    # The lever: a trigger guard that runs back into a finger loop under the wrist, on a pivot pin.
    b.bar([(-0.22, -0.06), (-0.19, -0.11), (-0.08, -0.125), (0.0, -0.115), (0.03, -0.09)], 0.03, 0.022, G)
    b.arc((0.06, -0.13), 0.055, 150, 420, 9, 0.03, 0.022, G)
    b.bar([(0.087, -0.083), (0.06, -0.052)], 0.03, 0.022, G)
    b.cyl((-0.21, -0.05, -0.045), (-0.21, 0.05, -0.045), 0.012, K, segs=8, bevel=0, detail=True)
    b.bar([(-0.06, -0.058), (-0.056, -0.09), (-0.044, -0.102)], 0.016, 0.014, K)  # trigger


def double_shotgun(b):
    """A side-by-side double-barrel shotgun with outside hammers, a splinter forend and a straight stock."""
    b.prism([(-0.02, 0.05), (0.10, 0.04), (0.36, 0.055), (0.40, -0.11), (0.33, -0.115), (0.10, -0.045),
             (-0.02, -0.045)], -0.05, 0.05, W)  # fmt: skip
    b.box((0.395, 0, -0.028), (0.03, 0.104, 0.18), K, bevel=0.008, rot=(0, -0.24, 0))  # butt pad
    b.box((0.05, 0, 0.051), (0.13, 0.03, 0.012), G, bevel=0)  # tang
    for x in (0.0, 0.09):
        b.box((x, 0, 0.059), (0.014, 0.014, 0.006), K, bevel=0, detail=True)
    # Action: the block, side plates, fences around the barrel breeches, hammers, top lever.
    b.box((-0.13, 0, 0.0), (0.26, 0.124, 0.13), G)
    for y in (-0.063, 0.063):
        b.box((-0.09, y, -0.005), (0.16, 0.008, 0.085), D, bevel=0.004)
        for x in (-0.15, -0.03):
            b.box((x, y * 1.06, -0.005), (0.016, 0.006, 0.016), K, bevel=0, detail=True)
    for y in (-0.036, 0.036):
        b.cyl((-0.255, y, 0.035), (-0.285, y, 0.035), 0.042, G, segs=12, bevel=0.008)  # fences
        b.bar([(-0.03, 0.055), (-0.015, 0.09), (0.012, 0.1)], 0.02, 0.024, D, y=y * 1.3)  # hammers
    b.box((0.005, 0, 0.07), (0.07, 0.03, 0.016), D, bevel=0, rot=(0, -0.15, 0))  # top lever
    # Barrels side by side, a rib on top and below, black bores and a bead sight.
    for y in (-0.036, 0.036):
        b.cyl((-0.28, y, 0.035), (-1.08, y, 0.035), 0.036, D)
        b.cyl((-1.08, y, 0.035), (-1.084, y, 0.035), 0.022, K, bevel=0, detail=True)
    b.box((-0.68, 0, 0.074), (0.8, 0.024, 0.012), K, bevel=0)  # top rib
    b.box((-0.68, 0, 0.0), (0.8, 0.024, 0.024), D, bevel=0)  # bottom rib
    b.box((-1.065, 0, 0.086), (0.016, 0.016, 0.016), G, bevel=0, detail=True)  # bead
    # Splinter forend with its iron and latch.
    b.prism([(-0.30, 0.015), (-0.60, 0.015), (-0.62, -0.01), (-0.60, -0.05), (-0.30, -0.055)], -0.058, 0.058, W)
    b.box((-0.29, 0, -0.02), (0.03, 0.12, 0.072), G, bevel=0.008)
    b.box((-0.46, 0, -0.056), (0.05, 0.03, 0.012), G, bevel=0, detail=True)
    b.cyl((-0.23, -0.068, -0.03), (-0.23, 0.068, -0.03), 0.015, D, segs=8, bevel=0, detail=True)  # hinge pin
    # Trigger guard and two triggers.
    b.bar([(-0.12, -0.06), (-0.10, -0.10), (-0.02, -0.112), (0.04, -0.09), (0.07, -0.052)], 0.026, 0.018, G)
    b.bar([(-0.065, -0.058), (-0.06, -0.094)], 0.014, 0.014, K)
    b.bar([(-0.025, -0.058), (-0.02, -0.094)], 0.014, 0.014, K)


def baseball_bat(b):
    """A wooden bat with a taped grip and nails driven through the barrel."""
    b.lathe([(0.040, -0.17), (0.053, -0.16), (0.053, -0.142), (0.040, -0.126), (0.030, -0.11), (0.030, 0.25),
             (0.041, 0.40), (0.058, 0.56), (0.066, 0.70), (0.066, 0.90), (0.058, 0.926), (0.040, 0.936)], W, segs=14)  # fmt: skip
    b.lathe([(0.031, -0.112), (0.035, -0.104), (0.035, 0.17), (0.031, 0.178)], K, segs=14)  # grip tape
    for z in (-0.07, 0.03, 0.13):
        b.lathe([(0.036, z), (0.038, z + 0.004), (0.038, z + 0.016), (0.036, z + 0.02)], K, segs=14, detail=True)
    b.box((0.04, 0, 0.175), (0.012, 0.03, 0.05), K, bevel=0, rot=(0, 0.3, 0), detail=True)  # loose tape end
    for i, (deg, z) in enumerate(((10, 0.64), (75, 0.70), (150, 0.76), (215, 0.67), (280, 0.82), (340, 0.86))):
        a = math.radians(deg)
        r = 0.068 + 0.012 * (i % 2)
        b.box((r * math.cos(a), r * math.sin(a), z), (0.07, 0.009, 0.009), G, bevel=0, rot=(0, 0.15, a))
        b.box((0.064 * math.cos(a), 0.064 * math.sin(a), z), (0.006, 0.022, 0.022), G, bevel=0, rot=(0, 0, a),
              detail=True)  # fmt: skip


def fire_axe(b):
    """A fire axe: wood haft with a black grip, a red head with a bare steel edge and a back pick."""
    b.prism([(-0.046, -0.17), (0.046, -0.17), (0.05, -0.12), (0.034, -0.06), (0.03, 1.02), (-0.03, 1.02),
             (-0.034, -0.06), (-0.05, -0.12)], -0.024, 0.024, W, bevel=0.012)  # fmt: skip
    b.box((0, 0, 0.01), (0.074, 0.054, 0.22), K, bevel=0.012)  # grip
    b.box((0, 0, -0.098), (0.078, 0.058, 0.014), K, bevel=0, detail=True)  # grip collars
    b.box((0, 0, 0.118), (0.078, 0.058, 0.014), K, bevel=0, detail=True)
    # Head: the eye block, the blade and its steel edge, the pick and its steel tip.
    b.box((0, 0, 0.93), (0.1, 0.066, 0.14), R)
    b.prism([(-0.045, 0.99), (-0.045, 0.87), (-0.14, 0.855), (-0.205, 0.83), (-0.205, 1.05), (-0.14, 1.01)],
            -0.024, 0.024, R)  # fmt: skip
    b.prism([(-0.20, 0.825), (-0.20, 1.055), (-0.25, 1.075), (-0.25, 0.805)], -0.014, 0.014, G, bevel=0.008)
    b.prism([(0.045, 0.975), (0.045, 0.885), (0.15, 0.915), (0.20, 0.932), (0.15, 0.952)], -0.021, 0.021, R)
    b.prism([(0.18, 0.924), (0.27, 0.94), (0.18, 0.954)], -0.014, 0.014, G, bevel=0.004)
    b.box((0, 0, 1.024), (0.008, 0.034, 0.008), G, bevel=0, detail=True)  # wedge in the haft
    for y in (-0.034, 0.034):
        for z in (0.905, 0.955):
            b.box((-0.02, y, z), (0.016, 0.006, 0.016), G, bevel=0, detail=True)  # rivets


def grenade(b):
    """A 1950s-flavoured hand grenade: an olive egg ringed by three raised bands, a yellow band under the fuze
    (the period marking for a high-explosive filler) and a squat grey fuze. The spoon and the pin are their own nodes
    (`grenade_spoon`, `grenade_pin`) so the pin pull and the spoon flying off can show. Stands up along +Z; the origin
    (the grip) is the centre of the body, where the fist closes."""
    # Body: one turned egg, fuller at the bottom; the bands are short steps in the radius (the chamfers are in the
    # profile, as on the bat).
    b.lathe([(0.0, -0.215), (0.07, -0.21), (0.118, -0.185), (0.142, -0.15), (0.142, -0.13), (0.156, -0.115),
             (0.156, -0.085), (0.146, -0.07), (0.15, -0.045), (0.164, -0.03), (0.164, 0.0), (0.15, 0.015),
             (0.146, 0.04), (0.156, 0.055), (0.156, 0.085), (0.138, 0.1), (0.118, 0.125), (0.09, 0.145),
             (0.0, 0.15)], GN, segs=14)  # fmt: skip
    b.lathe([(0.112, 0.1), (0.14, 0.094), (0.14, 0.122), (0.1, 0.14), (0.07, 0.149)], Y, segs=14)  # HE band
    b.lathe([(0.03, -0.226), (0.06, -0.218), (0.06, -0.205), (0.03, -0.2)], D, segs=14, detail=True)  # base plug
    # Fuze: a neck, the body with the striker hump, a lug on the right for the spoon hinge.
    b.cyl((0, 0, 0.13), (0, 0, 0.19), 0.062, D, segs=12, bevel=0)
    b.box((0, 0, 0.215), (0.13, 0.11, 0.07), D, bevel=0.014)
    b.box((0.055, 0, 0.245), (0.06, 0.07, 0.03), G2, bevel=0.008)  # striker housing
    b.box((0.075, 0, 0.21), (0.03, 0.08, 0.05), G2, bevel=0, detail=True)  # hinge lug
    for y in (-0.059, 0.059):
        b.cyl((0.0, y, 0.215), (0.0, y * 1.12, 0.215), 0.016, G2, segs=8, bevel=0, detail=True)  # pin bosses


def grenade_spoon(b):
    """The spoon (safety lever): over the fuze and down the body's right side (+X). Pivots at its hinge."""
    b.bar([(-0.035, 0.262), (0.06, 0.268), (0.095, 0.24), (0.15, 0.16), (0.175, 0.07), (0.178, -0.02)],
          0.07, 0.022, G)  # fmt: skip


def grenade_pin(b):
    """The pin through the fuze (across Y) and its pull ring, on the -Y side. Pulls out along -Y."""
    b.cyl((0.0, 0.07, 0.215), (0.0, -0.09, 0.215), 0.01, G2, segs=6, bevel=0)
    b.arc((0.0, 0.215), 0.055, -90, 270, 10, 0.018, 0.018, G2, y=-0.1)


# Weapons made of more than one node: {weapon: {node: (builder, pivot)}}. Each node is joined on its own, its origin
# at the pivot (where it turns or slides from), parented to the weapon's main node so it keeps the weapon's origin.
NODES = {
    "grenade": {"Spoon": (grenade_spoon, (0.075, 0.0, 0.235)), "Pin": (grenade_pin, (0.0, 0.0, 0.215))},
}


# Firearms: the centre of the barrel's open end, in drawing units (before `chunk`, like the NODES pivots). A gun with
# two barrels side by side gets one muzzle centred between them. Melee weapons and the grenade have none.
MUZZLES = {
    "lever_rifle": (-1.22, 0.0, 0.045),  # the barrel's front face (the bore disc stands 4 mm proud on the held level)
    "double_shotgun": (-1.08, 0.0, 0.035),  # between the two barrels' front faces
}
MUZZLE = "Muzzle"


def add_muzzle(o, name, chunk):
    """The `Muzzle` empty under the weapon: at the barrel end, local +Y out of the barrel (-X), so Godot's -Z."""
    if name not in MUZZLES:
        return None
    m = bpy.data.objects.new(MUZZLE, None)
    m.empty_display_type = "ARROWS"
    m.empty_display_size = 0.05
    bpy.context.scene.collection.objects.link(m)
    m.parent = o
    m.location = Vector(MUZZLES[name]) * Vector(chunk)
    m.rotation_euler = (0.0, 0.0, math.pi / 2)  # +Y -> -X
    return m


# name: (builder, chunk). Guns fatten across Y and Z (their length runs along X); melee across X and Y.
WEAPONS = {
    "lever_rifle": (lever_rifle, (1.0, 1.5, 1.5)),
    "double_shotgun": (double_shotgun, (1.0, 1.4, 1.5)),
    "baseball_bat": (baseball_bat, (1.35, 1.35, 1.0)),
    "fire_axe": (fire_axe, (1.0, 1.5, 1.0)),
    "grenade": (grenade, (1.2, 1.2, 1.2)),  # drawn at 0.5 m, held at the kit grenade's 0.6 m
}


def stats(o, offset=(0.0, 0.0, 0.0)):
    """Triangles, loose parts (after welding coincident vertices), bounding box (moved by `offset`)."""
    me = o.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    seen, parts = set(), 0
    for v in bm.verts:
        if v in seen:
            continue
        parts += 1
        stack = [v]
        while stack:
            u = stack.pop()
            if u in seen:
                continue
            seen.add(u)
            stack.extend(e.other_vert(u) for e in u.link_edges)
    bm.free()
    xs = [v.co + Vector(offset) for v in me.vertices]
    mn = [min(c[i] for c in xs) for i in range(3)]
    mx = [max(c[i] for c in xs) for i in range(3)]
    return tris, parts, mn, mx


def export(o, path):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    for k in o.children:  # pin, spoon, muzzle: separate nodes under the weapon
        k.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", choices=list(WEAPONS))
    ap.add_argument("--out", type=Path, default=Path("game/assets/weapons"))
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    args.out.mkdir(parents=True, exist_ok=True)
    img = wl.palette_image(args.out.resolve() / "weapons_palette.png")
    mat = wl.atlas_material(img)
    report = {}
    for name in args.only or WEAPONS:
        for lod in ("near", "far"):
            build, chunk = WEAPONS[name]
            b = wl.Builder(name, lod, mat, chunk)
            build(b)
            o = b.join()
            kids = []
            for node, (part, pivot) in NODES.get(name, {}).items():
                nb = wl.Builder(f"{name}_{node}", lod, mat, chunk)
                part(nb)
                k = nb.join()
                k.name = k.data.name = node
                pivot = Vector(pivot) * Vector(chunk)
                k.data.transform(Matrix.Translation(-pivot))
                k.parent = o
                k.location = pivot
                kids.append(k)
            muzzle = add_muzzle(o, name, chunk)
            tris, parts, mn, mx = stats(o)
            for k in kids:
                kt, kp, kmn, kmx = stats(k, offset=k.location)
                tris, parts = tris + kt, parts + kp
                mn = [min(mn[i], kmn[i]) for i in range(3)]
                mx = [max(mx[i], kmx[i]) for i in range(3)]
            folder = args.out / name
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / (f"{name}.glb" if lod == "near" else f"{name}_far.glb")
            export(o, path)
            size = [round(mx[i] - mn[i], 3) for i in range(3)]
            report[f"{name}/{lod}"] = {"tris": tris, "parts": parts, "min": mn, "max": mx, "size": size}
            nodes = f", nodes {[k.name for k in kids]}" if kids else ""
            if muzzle:
                at = [round(c, 4) for c in muzzle.location]
                report[f"{name}/{lod}"]["muzzle"] = at
                nodes += f", muzzle {at}"
            print(f"WEAPON {name} {lod}: {tris} tris, {parts} parts, size {size}{nodes}, file {path}")
            for k in kids:
                bpy.data.objects.remove(k)
            if muzzle:
                bpy.data.objects.remove(muzzle)
            bpy.data.objects.remove(o)
    print("REPORT " + json.dumps(report))


main()
