"""Render Soldier heads close up, back faces culled as Godot draws them, one row per model and one column per turn (#895).

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/render_soldier_heads.py -- \
        --model "Greaser=<previews>/greaser.glb" --model "Pit crew=<previews>/pit_crew.glb" \
        [--turns 0,35,90,180] [--pose Idle@0] [--target 1.38] [--distance 1.6] [--elevation 8] [--cell 360] \
        [--small 24] --out <workspace>/scratch/deadnight/<branch>/heads.png

Each `--model` is Title=path.glb (build_soldier_parts.py --preview writes one per preset). The model stands at the
game's scale (0.8) in a clip frame; a perspective camera looks at `--target` (metres above the floor) from
`--distance` metres, `--elevation` degrees up, turned by each `--turns` angle (0 is the front). Back faces are culled
(Workbench draws the inside of an open shell otherwise, which hid the see-through neck of #895). `--small N` adds a
column per turn drawn at N pixels a head and scaled back up: the face at the night's distance on a phone.
"""

import argparse
import math
import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

GAME_SCALE = 0.8
BACKGROUND = (0.16, 0.18, 0.24)  # the night's sky, about


def clean(name):
    return re.sub(r"\.\d+$", "", name.split("|")[-1])


def render(scene, cam, target, distance, elevation, turn, size, tmp):
    a, e = math.radians(turn), math.radians(elevation)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * distance
    cam.location = target + d
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(tmp))
    px = np.array(img.pixels[:]).reshape(size, size, 4)
    bpy.data.images.remove(img)
    return px


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", action="append", required=True, help="Title=path.glb")
    ap.add_argument("--turns", default="0,35,90,180")
    ap.add_argument("--pose", default="Idle@0")
    ap.add_argument("--target", type=float, default=1.38)
    ap.add_argument("--distance", type=float, default=1.6)
    ap.add_argument("--elevation", type=float, default=8.0)
    ap.add_argument("--cell", type=int, default=360)
    ap.add_argument("--small", type=int, default=0, help="also each turn at this many pixels, scaled back up")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)
    turns = [float(t) for t in args.turns.split(",")]

    kitlib.reset()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.image_settings.file_format = "PNG"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_backface_culling = True
    sh.background_type = "VIEWPORT"
    sh.background_color = BACKGROUND
    scene.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, args.target))
    tmp = args.out.parent / "_render_soldier_heads.png"
    clip, _, frame = args.pose.partition("@")

    rows = []
    for spec in args.model:
        _title, path = spec.split("=", 1)
        before, acts = set(bpy.data.objects), set(bpy.data.actions)
        kitlib.gltf_import(path)
        objs = [o for o in bpy.data.objects if o not in before]
        kitlib.base_colour_active()
        arm = kitlib.armature_of(objs)
        action = next(a for a in bpy.data.actions if a not in acts and clean(a.name) == clip)
        arm.animation_data_create()
        arm.animation_data.action = action
        if action.slots:
            arm.animation_data.action_slot = action.slots[0]
        scene.frame_set(int(action.frame_range[0]) + int(frame or 0))
        for o in objs:
            if o.parent is None:
                o.matrix_world = Matrix.Scale(GAME_SCALE, 4) @ o.matrix_world
        bpy.context.view_layer.update()
        row = [render(scene, cam, target, args.distance, args.elevation, t, args.cell, tmp) for t in turns]
        if args.small:
            for t in turns[:2]:
                small = render(scene, cam, target, args.distance, args.elevation, t, args.small, tmp)
                k = math.ceil(args.cell / args.small)
                big = np.repeat(np.repeat(small, k, axis=0), k, axis=1)[: args.cell, : args.cell]
                row.append(big)
        rows.append(np.concatenate(row, axis=1))
        for o in objs:
            bpy.data.objects.remove(o)
        for a in [a for a in bpy.data.actions if a not in acts]:
            bpy.data.actions.remove(a)
    sheet = np.concatenate(rows[::-1], axis=0)
    img = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    img.pixels = sheet.ravel()
    img.filepath_raw = str(args.out)
    img.file_format = "PNG"
    img.save()
    tmp.unlink(missing_ok=True)
    print("HEADS", args.out)


main()
