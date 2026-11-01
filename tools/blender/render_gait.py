"""Side-view sheets of locomotion clips on the zombie rig, for comparing gaits at one scale (Deadnight #278).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_gait.py -- \
        --row Run=game/assets/characters/zombies/zombie_walker.glb \
        --row Sprint=game/assets/characters/zombies/clips/zombie_clips.glb \
        --out <workspace>/scratch/deadnight/<branch>/gait.png

One row per `--row CLIP=FILE` (the clip is read from that file), every `--every`th frame of its cycle, Workbench with
the atlas colours, orthographic at one scale, seen from the zombie's right side (`--view side`) or front right
(`--view three-quarter`). A ground line with a tick every 0.25 m (kit scale) sits under the feet, so stride and lift
can be compared tile to tile.
"""

import argparse
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

TILE_W, TILE_H = 260, 300


def action_named(name):
    return next((a for a in bpy.data.actions if a.name.split("|")[-1] == name), None)


def setup(view):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = TILE_W, TILE_H
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.82, 0.82, 0.8)
    scene.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.9
    scene.collection.objects.link(cam)
    scene.camera = cam
    # The zombie faces -Y; its right is -X.
    target = Vector((0, -0.05, 0.62))
    direction = {"side": (-1, 0, 0.0), "three-quarter": (-0.8, -0.6, 0.15)}[view]
    pos = target + Vector(direction).normalized() * 20
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
    ground(scene)
    return scene, cam


def ground(scene):
    """A dark ground line along the walk with a light tick every 0.25 m."""
    dark = bpy.data.materials.new("ground")
    dark.diffuse_color = (0.25, 0.25, 0.25, 1)
    tick = bpy.data.materials.new("tick")
    tick.diffuse_color = (0.95, 0.95, 0.95, 1)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0.3, 0, -0.012))
    line = bpy.context.object
    line.scale = (0.02, 4, 0.02)
    line.data.materials.append(dark)
    for i in range(-12, 13):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0.29, i * 0.25, -0.012))
        t = bpy.context.object
        t.scale = (0.03, 0.012, 0.024)
        t.data.materials.append(tick)


def label_obj(scene, cam):
    mat = bpy.data.materials.new("label")
    mat.diffuse_color = (0.1, 0.1, 0.1, 1)
    cu = bpy.data.curves.new("label", "FONT")
    cu.size = 0.09
    o = bpy.data.objects.new("label", cu)
    o.data.materials.append(mat)
    scene.collection.objects.link(o)
    o.rotation_euler = cam.rotation_euler
    right = cam.matrix_world.to_quaternion() @ Vector((1, 0, 0))
    up = cam.matrix_world.to_quaternion() @ Vector((0, 1, 0))
    fwd = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
    o.location = Vector((0, -0.05, 0.62)) - right * 0.88 + up * 0.8 - fwd * 4
    return o


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--row", action="append", required=True, help="CLIP=FILE")
    ap.add_argument("--every", type=int, default=2)
    ap.add_argument("--view", choices=["side", "three-quarter"], default="side")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)
    args.out = args.out.resolve()
    tmp = args.out.parent / "_gait_tiles"
    tmp.mkdir(parents=True, exist_ok=True)
    rows = []
    for spec in args.row:
        clip, path = spec.split("=", 1)
        objs = kitlib.import_glb(path)
        arm = kitlib.armature_of(objs)
        kitlib.base_colour_active()
        for o in objs:
            if o.type == "EMPTY" or (o.type == "MESH" and o.name.startswith("Zombie_Far")):
                o.hide_render = True
        scene, cam = setup(args.view)
        label = label_obj(scene, cam)
        a = action_named(clip)
        ad = arm.animation_data or arm.animation_data_create()
        for t in ad.nla_tracks:
            t.mute = True
        ad.action = a
        if hasattr(ad, "action_slot") and a.slots:
            ad.action_slot = a.slots[0]
        n = int(a.frame_range[1])
        tiles = []
        for f in range(0, n + 1, args.every):
            scene.frame_set(f)
            label.data.body = f"{clip}  f{f}"
            p = tmp / f"{clip}_{f}.png"
            scene.render.filepath = str(p)
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(str(p))
            tiles.append(np.array(img.pixels[:]).reshape(TILE_H, TILE_W, 4))
            bpy.data.images.remove(img)
        rows.append(tiles)
    cols = max(len(r) for r in rows)
    sheet = np.ones((TILE_H * len(rows), TILE_W * cols, 4))
    sheet[..., :3] = 0.82
    for ri, tiles in enumerate(rows):
        y0 = TILE_H * (len(rows) - 1 - ri)  # Blender pixels start at the bottom
        for ci, t in enumerate(tiles):
            sheet[y0 : y0 + TILE_H, ci * TILE_W : (ci + 1) * TILE_W] = t
    out = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0])
    out.pixels = sheet.ravel()
    out.filepath_raw = str(args.out)
    out.file_format = "PNG"
    out.save()
    print("wrote", out.filepath_raw)


main()
