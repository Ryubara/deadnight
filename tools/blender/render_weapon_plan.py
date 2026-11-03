"""Render the weapon set side by side at its size in the game, with the planned weapons as outlined boxes.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_weapon_plan.py -- --out <png> \
        [--plan docs/research/weapon-models-plan.json] [--silhouette] [--px-per-m 360] [--far]

Each weapon in `game/assets/weapons/` that a hold file names is drawn from its right side (muzzle to the left) at
model x `model_scale` x the Soldier's 0.8, one row per hold class (pistols, SMGs and carbines, long guns, melee), on a
ruler with the Soldier's height (1.4 m) marked. Its hand and effect points show as dots: `Grip` green, `Trigger`
yellow, `Support` blue, `Muzzle` red. `--plan` adds each planned weapon of a JSON list ({id, row, length, height,
grip_from_muzzle}) as a box of its planned size in the game beside its row. `--silhouette` draws every model flat
black on white with no dots or labels, at `--px-per-m` (42 is a teammate 8 m away on a phone, 130 the player's own
weapon): what a shape keeps at that size is what reads. `--far` draws the far levels. `--add id=row@model_scale` adds a
model that no hold file names yet at the end of a row (#797: `--add ray_gun=pistols@2.275`).
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

SOLDIER_SCALE = 0.8
SOLDIER_HEIGHT = 1.4  # the Soldier in the game (docs/design/weapon-hold.md)
GAP = 0.18
ROWS = {  # hold class rows, top to bottom
    "pistols": ["revolver", "flare_gun"],
    "smgs": ["tommy_gun"],
    "long": ["lever_rifle", "double_shotgun"],
    "melee": ["baseball_bat", "crowbar", "fire_axe", "hammer"],
}
ROW_HEIGHT = {"pistols": 0.55, "smgs": 0.55, "long": 0.75, "melee": 0.45}
DOTS = {"Grip": (0.1, 0.75, 0.2), "Trigger": (0.95, 0.8, 0.1), "Support": (0.15, 0.4, 0.95), "Muzzle": (0.9, 0.1, 0.1)}


def hold_scales(root, classes=None):
    """{model: model_scale} from the hold files; `classes` (a dict) also gets {model: (weapon_class, real_length)}."""
    out = {}
    for f in sorted((root / "game/gameplay/player/holds").glob("*.tres")):
        text = f.read_text(encoding="utf-8")
        scene = re.search(r'scene = "res://assets/weapons/([^/]+)/', text)
        scale = re.search(r"model_scale = ([0-9.]+)", text)
        if scene and scale:
            out.setdefault(scene.group(1), float(scale.group(1)))
            if classes is not None:
                kind = re.search(r'weapon_class = &"(\w+)"', text)
                real = re.search(r"real_length = ([0-9.]+)", text)
                classes.setdefault(scene.group(1), (kind.group(1) if kind else "", float(real.group(1)) if real else 0))
    return out


def rows_with_new(root, classes):
    """`ROWS` plus every held model it does not list, in the row of its hold's class (#795): a pistol with the
    pistols, a rifle-class gun under 0.95 m real with the SMGs and carbines, any other gun with the long guns. So a
    new weapon shows once its glb and hold file are in, and the model batches never edit the same lines here."""
    rows = {row: list(names) for row, names in ROWS.items()}
    listed = {n for names in ROWS.values() for n in names}
    for name, (kind, real) in sorted(classes.items()):
        if name in listed or not (root / f"game/assets/weapons/{name}/{name}.glb").exists():
            continue
        if kind == "Pistol":
            rows["pistols"].append(name)
        elif kind == "Rifle" and real < 0.95:
            rows["smgs"].append(name)
        elif kind in ("Rifle", "Shotgun"):
            rows["long"].append(name)
    return rows


def flat_material(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    return m


def quad(name, x0, x1, z0, z1, mat, y=-1.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new(name, me)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)
    return o


def frame(name, x0, x1, z0, z1, mat, t=0.008):
    for i, (a, b, c, d) in enumerate(((x0, x1, z0, z0 + t), (x0, x1, z1 - t, z1), (x0, x0 + t, z0, z1),
                                      (x1 - t, x1, z0, z1))):  # fmt: skip
        quad(f"{name}{i}", a, b, c, d, mat)


def dot(x, z, mat, r=0.014):
    bpy.ops.mesh.primitive_circle_add(vertices=12, radius=r, fill_type="NGON", location=(x, -1.5, z),
                                      rotation=(math.radians(90), 0, 0))  # fmt: skip
    bpy.context.object.data.materials.append(mat)


def text(body, x, z, size, mat, align="LEFT"):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    o = bpy.data.objects.new("label", cu)
    o.location = (x, -1.0, z)
    o.rotation_euler = (math.radians(90), 0, 0)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)


def load(path, scale):
    """Import a weapon, scale it to the game, lay a standing (melee) one down with its head to the left; return its
    objects and meshes."""
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    kitlib.apply_base_colours(objs, path)
    roots = [o for o in objs if o.parent is None]
    meshes = [o for o in objs if o.type == "MESH"]
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    mn, mx = kitlib.bbox(pts)
    rot = Matrix.Identity(4)
    if (mx.z - mn.z) > (mx.x - mn.x):  # melee stands up along +Z: lay it down, head toward -X like a muzzle
        rot = Matrix.Rotation(math.radians(-90), 4, "Y")
    for r in roots:
        r.matrix_world = Matrix.Diagonal((scale, scale, scale, 1)) @ rot @ r.matrix_world
    bpy.context.view_layer.update()
    return objs, meshes


def bounds(meshes):
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    return kitlib.bbox(pts)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path("."))
    ap.add_argument("--plan", type=Path)
    ap.add_argument("--silhouette", action="store_true")
    ap.add_argument("--far", action="store_true")
    ap.add_argument("--px-per-m", type=int, default=360)
    ap.add_argument("--add", action="append", default=[], help="id=row@model_scale: a model with no hold file yet")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)

    kitlib.reset()
    scene = bpy.context.scene
    ink = flat_material("Ink", (0.02, 0.02, 0.02))
    tick = flat_material("Tick", (0.55, 0.55, 0.55))
    plan_mat = flat_material("Plan", (0.75, 0.2, 0.55))
    dots = {k: flat_material(k, c) for k, c in DOTS.items()}
    classes = {}
    scales = hold_scales(args.root, classes)
    for spec in args.add:
        name, _, rest = spec.partition("=")
        row, _, scale = rest.partition("@")
        ROWS[row] = [*ROWS[row], name]
        scales[name] = float(scale)
    plan = json.loads(args.plan.read_text(encoding="utf-8")) if args.plan else []
    label = not args.silhouette

    base, width, left = 0.0, 0.0, 0.45
    row_bases = []
    for row, names in rows_with_new(args.root, classes).items():
        base -= ROW_HEIGHT[row]
        row_bases.append(base)
        cursor = left
        for name in names:
            suffix = "_far" if args.far else ""
            path = (args.root / f"game/assets/weapons/{name}/{name}{suffix}.glb").resolve()
            scale = scales.get(name, 1.0) * SOLDIER_SCALE
            objs, meshes = load(path, scale)
            mn, mx = bounds(meshes)
            off = Vector((cursor - mn.x, 0, base + 0.06 - mn.z))
            for r in (o for o in objs if o.parent is None):
                r.matrix_world = Matrix.Translation(off) @ r.matrix_world
            bpy.context.view_layer.update()
            w = mx.x - mn.x
            if label:
                for o in objs:
                    key = re.sub(r"\.\d+$", "", o.name)
                    if o.type == "EMPTY" and key in dots:
                        p = o.matrix_world.translation
                        dot(p.x, p.z, dots[key])
                tris = sum(kitlib.tris(o) for o in meshes)
                text(f"{name}  {w:.2f} m, {tris} tris", cursor, base + 0.012, 0.03, ink)
            cursor += w + GAP
        for p in (p for p in plan if p["row"] == row):
            x0, z0 = cursor, base + 0.06
            frame(f"plan_{p['id']}", x0, x0 + p["length"], z0, z0 + p["height"], plan_mat)
            g = p.get("grip_from_muzzle")
            if g is not None and label:
                dot(x0 + g, z0 + p.get("grip_up", p["height"] * 0.45), dots["Grip"])
            if label:
                text(f"{p['id']} (plan) {p['length']:.2f} m", x0, base + 0.012, 0.03, plan_mat)
            cursor += p["length"] + GAP
        width = max(width, cursor)

    # The Soldier's height as a ruler at the left, 0.1 m ticks.
    top = row_bases[0] + ROW_HEIGHT["pistols"]
    if label:
        quad("ruler", 0.1, 0.12, top - SOLDIER_HEIGHT, top, ink)
        for i in range(15):
            z = top - i / 10
            quad(
                f"tick{i}",
                0.12,
                0.12 + (0.06 if i % 5 == 0 else 0.03),
                z - 0.003,
                z + 0.003,
                ink if i % 5 == 0 else tick,
            )
        text("Soldier\n1.4 m", 0.2, top - SOLDIER_HEIGHT + 0.02, 0.035, ink)
        for b in row_bases:
            quad("ground", left - 0.05, width, b + 0.055, b + 0.058, tick)

    width += 0.05
    bottom = base - 0.02
    top += 0.04  # a margin over the ruler
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(width, top - bottom)
    cam.location = (width / 2, -20, (top + bottom) / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.clip_end = 100
    scene.collection.objects.link(cam)
    scene.camera = cam

    r = scene.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x = max(16, round(width * args.px_per_m))
    r.resolution_y = max(16, round((top - bottom) * args.px_per_m))
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    sh = scene.display.shading
    sh.light = "FLAT"
    sh.show_cavity = False
    sh.background_type = "VIEWPORT"
    if args.silhouette:
        sh.color_type = "SINGLE"
        sh.single_color = (0.0, 0.0, 0.0)
        sh.background_color = (1.0, 1.0, 1.0)
        sh.show_object_outline = False
    else:
        sh.color_type = "TEXTURE"
        sh.show_object_outline = True
        sh.object_outline_color = (0.1, 0.1, 0.1)
        sh.background_color = (0.84, 0.84, 0.82)
    scene.view_settings.view_transform = "Standard"
    r.filepath = str(args.out.resolve())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"wrote {args.out} ({r.resolution_x}x{r.resolution_y})")


main()
