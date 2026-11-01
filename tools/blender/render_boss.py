"""Contact sheets of the boss zombie's clips, from the exported .glb (Deadnight #98).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_boss.py --         --boss game/assets/characters/zombie_boss/zombie_boss.glb --out <workspace>/scratch/deadnight/<branch>/boss

Writes `<out>-clips.png`: one row per clip in clips.json (plus `--extra` clips such as `Probe`, every frame), each
tile a moment of the clip (first frame, every event, last frame; or evenly spaced), Workbench with the atlas colours,
orthographic at one scale. `--view` picks front, side or three-quarter (the boss's front right, the default);
`--clip` limits the rows. The night look is judged in Godot (game/tests/captures/boss_tour.gd).
"""

import argparse
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

TILE_W, TILE_H = 300, 360


def action_named(name):
    return next((a for a in bpy.data.actions if a.name.split("|")[-1] == name), None)


def pose(arm, name, frame):
    a = action_named(name)
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = a
    if hasattr(ad, "action_slot") and a.slots:
        ad.action_slot = a.slots[0]
    bpy.context.scene.frame_set(int(frame))


def moments(clip, cap=6):
    n = clip["frames"]
    ev = sorted({v for v in clip.get("events", {}).values() if isinstance(v, int) and 0 < v < n})
    frames = sorted({0, *ev, n})
    if len(frames) < 4:
        frames = sorted({round(i * n / (cap - 1)) for i in range(cap)})
    return (
        frames[:cap] if len(frames) <= cap else [frames[round(i * (len(frames) - 1) / (cap - 1))] for i in range(cap)]
    )


def label_obj(scene, cam):
    mat = bpy.data.materials.new("label")
    mat.diffuse_color = (0.1, 0.1, 0.1, 1)
    cu = bpy.data.curves.new("label", "FONT")
    cu.size = 0.15
    cu.align_x = "LEFT"
    o = bpy.data.objects.new("label", cu)
    o.data.materials.append(mat)
    scene.collection.objects.link(o)
    o.rotation_euler = cam.rotation_euler
    return o


def clips_sheet(args, spec):
    objs = kitlib.import_glb(args.boss)
    arm = kitlib.armature_of(objs)
    kitlib.base_colour_active()
    for o in objs:
        if o.type == "MESH" and o.name.startswith("Zombie_Far"):
            o.hide_render = True
        if o.type == "EMPTY":
            o.hide_render = True
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
    cam.data.ortho_scale = 3.4
    scene.collection.objects.link(cam)
    scene.camera = cam
    # The zombie faces -Y; its right is -X. In front, to its right, a little above the chest.
    target = Vector((0, 0, 1.2))
    view = {"front": (0, -1, 0.05), "side": (-1, 0, 0.05)}.get(args.view, (-0.6, -1.0, 0.18))
    pos = target + Vector(view).normalized() * 20
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
    label = label_obj(scene, cam)
    right = cam.matrix_world.to_quaternion() @ Vector((1, 0, 0))
    up = cam.matrix_world.to_quaternion() @ Vector((0, 1, 0))
    fwd = (target - pos).normalized()
    label.location = target - right * 1.45 + up * 1.45 - fwd * 4
    tmp = args.out.parent / "_tiles"
    tmp.mkdir(parents=True, exist_ok=True)
    names = [n for n in list(spec["clips"]) + args.extra if not args.clip or n in args.clip]
    rows = []
    for name in names:
        clip = spec["clips"].get(name) or {"frames": int(action_named(name).frame_range[1]), "events": {}}
        if name not in spec["clips"]:
            clip["frames"] = int(action_named(name).frame_range[1])
            frames = list(range(clip["frames"] + 1))
        else:
            frames = moments(clip)
        tiles = []
        for f in frames:
            pose(arm, name, f)
            label.data.body = f"{name}  f{f}"
            p = tmp / f"{name}_{f}.png"
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
    out.filepath_raw = str(args.out) + "-clips.png"
    out.file_format = "PNG"
    out.save()
    print("wrote", out.filepath_raw)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--boss", required=True)
    ap.add_argument("--clips", help="clips.json (default: beside the .glb)")
    ap.add_argument("--extra", action="append", default=[], help="another clip to show, every frame (Probe)")
    ap.add_argument("--view", choices=["front", "side", "three-quarter"], default="three-quarter")
    ap.add_argument("--clip", action="append", help="only these clips")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)
    args.out = args.out.resolve()
    spec = json.loads(Path(args.clips or Path(args.boss).with_name("clips.json")).read_text())
    clips_sheet(args, spec)


main()
