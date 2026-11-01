"""Render a contact sheet of kit models side by side at one scale, for the style bible (docs/design/style.md).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_sheet.py -- \
        --model "Soldier=<bundle>/models/PpLF4rt4ah.glb" --model "Zombie=<refs>/VlXjG0N8Eg/model.glb" \
        --view front --pose Idle --out <workspace>/scratch/deadnight/<branch>/sheet-characters.png

Each `--model` is Title=path.glb; models are laid out left to right in the given order, held items and stray helper
meshes removed, at their own world size (1 Blender unit = 1 m). The camera always looks along +Y: `--view front`
shows models as they are (characters); `--view side` first turns each model so its long axis runs across the sheet
and up stays up (guns), laying upright blades flat. `--row-width` wraps to a new row. `--pose` names a clip to show
at its first frame; models without it (or `--pose rest`) show the rest pose. Workbench, flat lighting, texture colours
(so the zombie atlas shows), orthographic, a 1 m ruler with 0.5 m and 0.1 m ticks, and a label under each model with
its title, triangle count and size.
"""

import argparse
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

GAP = 0.25  # metres between models


def load(title, path, pose):
    """Import one model into a fresh collection, pose it, strip held items and strays; return (objects, tris)."""
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    kitlib.apply_base_colours(objs, path)
    arm = kitlib.armature_of(objs)
    if arm:
        action = None
        if pose != "rest":
            fresh = [a for a in bpy.data.actions if a not in kitlib.SEEN]
            action = next((a for a in fresh if re.sub(r"\.\d+$", "", a.name.split("|")[-1]) == pose), None)
        kitlib.SEEN.update(bpy.data.actions)
        if action:
            arm.animation_data.action = action
            if hasattr(arm.animation_data, "action_slot") and action.slots:
                arm.animation_data.action_slot = action.slots[0]
            arm.data.pose_position = "POSE"
            bpy.context.scene.frame_set(int(action.frame_range[0]))
        else:
            kitlib.rest_pose([arm])
    body, held, stray = kitlib.split_parts(objs)
    gone = {o.name for o in held + stray}
    keep = [o for o in objs if o.name not in gone]
    for o in held + stray:
        bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    return keep, sum(kitlib.tris(o) for o in body), body


def place(objs, body, view, cursor, base):
    """Move the model's root so its bbox starts at x = cursor and sits on z = base; return (width, height, depth)."""
    roots = [o for o in objs if o.parent is None]
    rot = Matrix.Identity(4)
    if view == "side":
        # Guns point along -X or +X in the kit; look at them from the side: long axis across, up stays up.
        pts = [p for o in body for p in kitlib.world_verts(o)]
        mn, mx = kitlib.bbox(pts)
        if (mx.y - mn.y) > (mx.x - mn.x):
            rot = Matrix.Rotation(math.radians(90), 4, "Z")
        if (mx.z - mn.z) > max(mx.x - mn.x, mx.y - mn.y):  # blades and the shovel stand upright: lay them down
            rot = Matrix.Rotation(math.radians(90), 4, "Y") @ rot
    for r in roots:
        r.matrix_world = rot @ r.matrix_world
    bpy.context.view_layer.update()
    pts = [p for o in body for p in kitlib.world_verts(o)]
    mn, mx = kitlib.bbox(pts)
    off = Vector((cursor - mn.x, -(mn.y + mx.y) / 2, base - mn.z))
    for r in roots:
        r.matrix_world = Matrix.Translation(off) @ r.matrix_world
    bpy.context.view_layer.update()
    return mx.x - mn.x, mx.z - mn.z, mx.y - mn.y


def flat_material(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    return m


def box(name, x0, x1, z0, z1, mat):
    me = bpy.data.meshes.new(name)
    y = -2.0
    me.from_pydata([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new(name, me)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)
    return o


def text(body, x, z, size, mat, align="CENTER"):
    cu = bpy.data.curves.new("label", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    o = bpy.data.objects.new("label", cu)
    o.location = (x, -2.0, z)
    o.rotation_euler = (math.radians(90), 0, 0)
    o.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(o)
    return o


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", required=True, help="Title=path.glb")
    ap.add_argument("--view", choices=["front", "side"], default="front")
    ap.add_argument("--pose", default="rest")
    ap.add_argument("--px-per-m", type=int, default=400)
    ap.add_argument("--row-width", type=float, default=0.0, help="wrap to a new row past this many metres (0: one row)")
    ap.add_argument("--row-height", type=float, default=1.3, help="metres from one row's ground to the next")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)

    kitlib.reset()
    kitlib.SEEN = set()
    scene = bpy.context.scene
    ink = flat_material("Ink", (0.02, 0.02, 0.02))
    light = flat_material("Tick", (0.6, 0.6, 0.6))

    cursor, tallest, labels, base, width = 0.6, 0.0, [], 0.0, 0.0
    for spec in args.model:
        title, path = spec.split("=", 1)
        objs, tris, body = load(title, path, args.pose)
        w, h, _d = place(objs, body, args.view, cursor, base)
        if args.row_width and cursor + w > args.row_width and cursor > 0.6:
            width = max(width, cursor)
            cursor, base = 0.6, base - args.row_height
            w, h, _d = place(objs, body, args.view, cursor, base)
        size = f"{h:.2f} m tall" if args.view == "front" else f"{w:.2f} m long"
        labels.append((cursor + w / 2, base, f"{title}\n{tris} tris\n{size}"))
        tallest = max(tallest, h)
        cursor += w + GAP
    width = max(width, cursor) + 0.1

    # Ruler at the left: 1 m tall bar with 0.5 m and 0.1 m ticks; a ground line under each row.
    for z in sorted({b for _, b, _ in labels}):
        box("ground", 0.0, width, z - 0.012, z, ink)
    box("ruler", 0.2, 0.23, 0.0, 1.0, ink)
    for i in range(11):
        z = i / 10
        long_ = i % 5 == 0
        box(f"tick{i}", 0.23, 0.23 + (0.1 if long_ else 0.05), z - 0.004, z + 0.004, ink if long_ else light)
    text("1 m", 0.215, 1.04, 0.07, ink)
    text("0.5", 0.36, 0.48, 0.05, ink, "LEFT")
    label_size = 0.06 if args.view == "front" else 0.055
    for x, z, body in labels:
        text(body, x, z - 0.09, label_size, ink)

    # Camera: orthographic, looking +Y at the XZ plane.
    top = max(tallest, 1.0) + 0.15
    bottom = base + (-0.32 if args.view == "front" else -0.26)
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
    r.resolution_x = round(width * args.px_per_m)
    r.resolution_y = round((top - bottom) * args.px_per_m)
    r.resolution_percentage = 100
    r.film_transparent = False
    r.image_settings.file_format = "PNG"
    sh = scene.display.shading
    sh.light = "FLAT"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.object_outline_color = (0.1, 0.1, 0.1)
    sh.show_cavity = False
    scene.world = bpy.data.worlds.new("bg") if not scene.world else scene.world
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.82, 0.82, 0.8)
    scene.view_settings.view_transform = "Standard"
    r.filepath = str(args.out)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"wrote {args.out} ({r.resolution_x}x{r.resolution_y})")


main()
