"""Render a contact sheet of built small-map kit pieces beside the Soldier and the game's own props, on the 0.5 m grid.

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_smallmap_outside_sheet.py -- --out <scratch>/sheet.png \
        [--dir game/assets/smallmap] [--names a,b] [--compare a.gltf,b.gltf] [--angle 28] [--elev 0.32]

The Soldier (1.8 m, its Idle frame) and the `--compare` props stand at the left at their game scale, then the pieces
left to right; a three-quarter orthographic Workbench view with the atlas colours over a grid with a line every
0.5 m and a brighter one every 2 m.
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
from smallmap_kit import Piece, atlas_material, palette_image


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" and not o.hide_render for c in o.bound_box]
    return Vector([min(p[k] for p in pts) for k in range(3)]), Vector([max(p[k] for p in pts) for k in range(3)])


def imported(path):
    before = set(bpy.data.objects)
    kitlib.gltf_import(str(path))
    return [o for o in bpy.data.objects if o not in before]


def character(path, height):
    """A game character with its strays and held items hidden, `height` metres tall in its Idle frame."""
    objs = imported(path)
    arm = kitlib.armature_of(objs)
    for o in objs:
        if o.type == "MESH" and (kitlib.is_stray(o, arm) or o.parent_bone.startswith(kitlib.HAND_BONE_PREFIXES)):
            o.hide_render = True
    if arm and arm.animation_data and bpy.data.actions:
        idle = next((a for a in bpy.data.actions if a.name.lower().startswith("idle")), None)
        if idle:
            arm.animation_data.action = idle
            if idle.slots:  # Blender 5: an action plays only through a slot
                arm.animation_data.action_slot = idle.slots[0]
            bpy.context.scene.frame_set(int(idle.frame_range[0]))
    bpy.context.view_layer.update()
    mn, mx = bounds(objs)
    k = height / (mx.z - mn.z)
    for o in objs:
        if o.parent is None:
            o.scale = [v * k for v in o.scale]
    bpy.context.view_layer.update()
    return objs


def place(objs, at):
    for o in objs:
        if o.parent is None:
            # glTF roots import in quaternion mode, where rotation_euler is ignored: move the world matrix instead.
            o.matrix_world = Matrix.Translation(Vector(at)) @ o.matrix_world
    bpy.context.view_layer.update()


def grid_floor(mat, mn, mx):
    p = Piece("Grid")
    w, d = mx[0] - mn[0], mx[1] - mn[1]
    p.box((w, d, 0.02), ((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, -0.01), "Soot", 0.0)
    for i in range(round(w / 0.5) + 1):
        major = i % 4 == 0
        p.box(
            (0.03 if major else 0.015, d, 0.004),
            (mn[0] + i * 0.5, (mn[1] + mx[1]) / 2, 0.002),
            "Grey" if major else "Grey2",
            0.0,
        )
    for j in range(round(d / 0.5) + 1):
        major = j % 4 == 0
        p.box(
            (w, 0.03 if major else 0.015, 0.004),
            ((mn[0] + mx[0]) / 2, mn[1] + j * 0.5, 0.002),
            "Grey" if major else "Grey2",
            0.0,
        )
    return p.obj(mat)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--dir", default="game/assets/smallmap")
    ap.add_argument("--names", default="")
    ap.add_argument("--soldier", default="game/assets/characters/soldier/soldier.glb")
    ap.add_argument("--compare", default="game/assets/props/fence.gltf,game/assets/props/tree.gltf")
    ap.add_argument("--angle", type=float, default=28.0)
    ap.add_argument("--elev", type=float, default=0.32)
    ap.add_argument("--px", type=int, default=3200)
    a = ap.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = []
    if a.soldier:
        groups.append(character(a.soldier, 1.8))
    for path in filter(None, a.compare.split(",")):
        groups.append(imported(path))
    names = [n for n in a.names.split(",") if n] or sorted(p.stem for p in Path(a.dir).glob("*.gltf"))
    for n in names:
        groups.append(imported(Path(a.dir) / f"{n}.gltf"))
    x = 0.0
    for objs in groups:
        mn, mx = bounds(objs)
        place(objs, (x - mn.x, -(mn.y + mx.y) / 2, -mn.z))
        x += (mx.x - mn.x) + 0.5
    mn, mx = bounds([o for g in groups for o in g])
    img = palette_image(Path(a.out).resolve().with_name("sheet_palette.png"))
    grid_floor(
        atlas_material(img, "Grid"),
        Vector((math.floor(mn.x) - 0.5, math.floor(mn.y) - 0.5, 0)),
        Vector((math.ceil(mx.x) + 0.5, math.ceil(mx.y) + 0.5, 0)),
    )
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    ang = math.radians(a.angle)
    d = Vector((math.sin(ang), -math.cos(ang), a.elev)).normalized()
    centre = (mn + mx) / 2
    cam.location = centre + d * 80
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    span = mx - mn
    cam.data.ortho_scale = max(span.x, span.z * 2.6) * 1.06
    cam.data.clip_end = 300
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
    sc.world.color = (0.03, 0.035, 0.06)
    sc.render.filepath = str(Path(a.out).resolve())
    bpy.ops.render.render(write_still=True)
    print("SHEET", a.out, len(groups))


main()
