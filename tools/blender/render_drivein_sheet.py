"""Render a contact sheet of the drive-in props (build_drivein_props.py) beside a kit character, at one scale.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_drivein_sheet.py -- --dir game/assets/drivein \
        --ref <bundle>/models/PpLF4rt4ah.glb --out <scratch>/sheet.png [--names a,b] [--angle 35]

The props stand left to right in a row with the reference character (the kit Soldier, at the style bible's 0.8) at
the left; a three-quarter orthographic Workbench view with the atlas colours, the camera's height and angle set by
`--angle` (degrees from the front, round Z).
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

GAP = 0.6


def imported(path):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    return [o for o in bpy.data.objects if o not in before]


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
    return Vector([min(p[k] for p in pts) for k in range(3)]), Vector([max(p[k] for p in pts) for k in range(3)])


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="game/assets/drivein")
    ap.add_argument("--names", default="")
    ap.add_argument("--ref", default="")
    ap.add_argument("--angle", type=float, default=35.0)
    ap.add_argument("--px", type=int, default=2400)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = [n for n in a.names.split(",") if n] or sorted(p.stem for p in Path(a.dir).glob("*.gltf"))
    x = 0.0
    groups = []
    if a.ref:
        objs = imported(a.ref)
        for o in objs:
            if o.type == "MESH" and (kitlib.is_stray(o, kitlib.armature_of(objs)) or "Gun" in o.name or o.parent_bone):
                o.hide_render = True
        for o in objs:
            if o.parent is None:
                o.scale = (0.8, 0.8, 0.8)
        groups.append(("Soldier (kit, x0.8)", [o for o in objs if not o.hide_render]))
    for n in names:
        groups.append((n, imported(str(Path(a.dir) / f"{n}.gltf"))))
    bpy.context.view_layer.update()
    for _title, objs in groups:
        mn, mx = bounds(objs)
        roots = [o for o in objs if o.parent is None]
        for o in roots:
            o.location.x += x - mn.x
        x += (mx.x - mn.x) + GAP
    bpy.context.view_layer.update()
    allobjs = [o for _t, objs in groups for o in objs if not o.hide_render]
    mn, mx = bounds(allobjs)
    centre = (mn + mx) / 2
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    ang = math.radians(a.angle)
    d = Vector((math.sin(ang) * 0.35, -math.cos(ang), 0.45)).normalized()
    cam.location = centre + d * 100
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    span = mx - mn
    cam.data.ortho_scale = max(span.x * 1.05, span.z * 2.6)
    cam.data.clip_end = 400
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x = a.px
    sc.render.resolution_y = int(a.px * min(0.6, max(0.3, span.z * 2.6 / cam.data.ortho_scale)))
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.12, 0.13, 0.17)
    sc.render.filepath = str(Path(a.out).resolve())
    bpy.ops.render.render(write_still=True)
    print("SHEET", a.out, [t for t, _ in groups])


main()
