"""Close-up contact sheets of the Soldier's hands on his weapons, from Godot's own pose (Deadnight #460).

Run with the pinned Blender, headless, on the folder `game/tests/art/grip_dump.gd` wrote (one OBJ per weapon and
pose, the posed body and the weapon in Godot's world, and `table.json` with the measured distances):

    blender -b --factory-startup -P tools/blender/render_grips.py -- --dump <dir> --out <dir>/sheets [--label before]

Writes `<out>/<weapon>.png`: a row per pose, columns the right hand from the gun's right (the trigger finger), from its
left (the thumb), from below, then the left hand from the outside and from below. Each tile is labelled with the
pose and the worst numbers of that hand (penetration negative, millimetres). Workbench, flat, outlined; the skin is
tan, the weapon grey, the trigger and the fore-end are not singled out: the numbers say which finger is off.
"""

import argparse
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

TILE = 300
ORTHO = 0.34  # metres across a tile, in the game's world (the fist is about 0.15 m)
KEEP = 0.17  # body faces farther than this from the hand are cut away, so the arm and the chest do not hide it


def gd(v):
    """Godot's Y-up world to Blender's Z-up (the OBJ import does the same turn)."""
    return Vector((v[0], -v[2], v[1]))


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = scene.render.resolution_y = TILE
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.show_cavity = True
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.86, 0.86, 0.84)
    scene.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ORTHO
    cam.data.clip_start = 0.01
    cam.data.clip_end = 10
    scene.collection.objects.link(cam)
    scene.camera = cam
    cu = bpy.data.curves.new("label", "FONT")
    cu.size = ORTHO * 0.055
    label = bpy.data.objects.new("label", cu)
    mat = bpy.data.materials.new("label")
    mat.diffuse_color = (0.05, 0.05, 0.05, 1)
    cu.materials.append(mat)
    scene.collection.objects.link(label)
    return scene, cam, label


def material(name, rgba):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = rgba
    return m


def load_obj(path):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=str(path), forward_axis="NEGATIVE_Z", up_axis="Y")
    new = [o for o in bpy.data.objects if o not in before]
    skin = material("skin", (0.80, 0.62, 0.45, 1))
    steel = material("weapon", (0.42, 0.44, 0.48, 1))
    for o in new:
        o.data.materials.clear()
        o.data.materials.append(steel if o.name.startswith("weapon") else skin)
    return new


def crop_body(objs, centre):
    """A copy of the body with only the faces near `centre` (the hand looked at); the full body is hidden."""
    import bmesh

    out = []
    for o in objs:
        o.hide_render = not o.name.startswith("weapon")
        if o.name.startswith("weapon"):
            continue
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        bm = bmesh.new()
        bm.from_mesh(c.data)
        far = [f for f in bm.faces if min((c.matrix_world @ v.co - centre).length for v in f.verts) > KEEP]
        bmesh.ops.delete(bm, geom=far, context="FACES")
        bm.to_mesh(c.data)
        bm.free()
        c.hide_render = False
        out.append(c)
    return out


def render_tile(scene, cam, label, centre, direction, up, text, tmp):
    """One tile: the camera on `direction` from `centre` (looking back at it), `up` reading up."""
    z = direction.normalized()
    y = (up - z * up.dot(z)).normalized()
    x = y.cross(z)
    cam.rotation_euler = Matrix((x, y, z)).transposed().to_euler()
    cam.location = centre + z * 2.0
    q = cam.rotation_euler.to_quaternion()
    label.data.body = text
    label.rotation_euler = cam.rotation_euler
    label.location = centre + direction * 1.0 + q @ Vector((-ORTHO * 0.47, ORTHO * 0.40, 0))
    scene.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(tmp))
    px = np.empty(TILE * TILE * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(TILE, TILE, 4)


def worst(parts, keys=None):
    """The deepest penetration and the part with it, and the farthest of `keys` (the parts that should touch)."""
    if not parts:
        return ""
    low = min(parts.items(), key=lambda kv: kv[1])
    txt = f"min {low[1]:.0f} ({low[0]})"
    if keys:
        far = max(((k, parts[k]) for k in keys if k in parts), key=lambda kv: kv[1], default=None)
        if far:
            txt += f"\nmax {far[1]:.0f} ({far[0]})"
    return txt


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--label", default="")
    ap.add_argument("--only", default="", help="comma-separated weapons")
    args = ap.parse_args(argv)
    rows = json.loads((args.dump / "table.json").read_text())
    args.out.mkdir(parents=True, exist_ok=True)
    tmp = args.out / "_tile.png"
    by_weapon = {}
    for row in rows:
        weapon, pose = row["tag"].rsplit("_", 1)
        by_weapon.setdefault(weapon, []).append((pose, row))
    only = {w for w in args.only.split(",") if w}
    for weapon, poses in by_weapon.items():
        if only and weapon not in only:
            continue
        grid = []
        for pose, row in poses:
            scene, cam, label = setup_scene()
            objs = load_obj(args.dump / f"{row['tag']}.obj")
            b = [gd(v) for v in row.get("weapon_basis", [[1, 0, 0], [0, 1, 0], [0, 0, 1]])]
            wx, wy, wz = b
            contacts = row.get("contacts", {})
            tiles = []
            r = gd(row["centre_R"])
            name = f"{args.label} {weapon} {pose}".strip()
            views_r = [("R: gun's right", -wz, wy), ("R: gun's left", wz, wy), ("R: below", -wy, -wx)]
            crop = crop_body(objs, r)
            for title, d, up in views_r:
                text = f"{name}\n{title}\n{worst(row['R'], contacts.get('R'))}"
                tiles.append(render_tile(scene, cam, label, r, d, up, text, tmp))
            left = gd(row["centre_L"])
            for c in crop:
                bpy.data.objects.remove(c)
            crop_body(objs, left)
            for title, d, up in [("L: outside", wz, wy), ("L: below", -wy, -wx)]:
                text = f"{name}\n{title}\n{worst(row['L'], contacts.get('L'))}"
                tiles.append(render_tile(scene, cam, label, left, d, up, text, tmp))
            grid.append(np.concatenate(tiles, axis=1))
        full_px = np.concatenate(grid[::-1], axis=0)
        h, w = full_px.shape[:2]
        out = bpy.data.images.new(weapon, w, h, alpha=True)
        out.pixels.foreach_set(full_px.ravel())
        out.filepath_raw = str(args.out / f"{weapon}.png")
        out.file_format = "PNG"
        out.save()
        print("SHEET", out.filepath_raw, len(poses), "poses")
    tmp.unlink(missing_ok=True)


main()
