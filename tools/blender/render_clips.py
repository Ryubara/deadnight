"""Contact sheets of the Soldier's clips: four moments of each clip, one sheet per weapon class (Deadnight #42).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_clips.py -- \
        --soldier <bundle>/models/PpLF4rt4ah.glb --out <workspace>/scratch/deadnight/<branch>/clips

Writes `<out>-<sheet>.png` for the sheets Rifle, Shotgun, Pistol, Melee, Body (full-body clips) and Split (upper
clips over moving legs). Each tile is posed the way Godot's upper/lower blend poses the character: upper-body bones
from the upper clip, every other bone from the base clip (Idle, or Run/Walk on the Split sheet), so the sheet shows
what the bone filter will. The class's kit weapon stays in the hand (Deadnight's weapons copy those holds). Moments:
first frame, two inner frames (the clip's first event when it has one), last frame. Workbench, flat lighting, seen
from the Soldier's front right at a third-person camera height.
"""

import argparse
import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
import soldier_clips as sc

TILE_W, TILE_H = 360, 440


def moments(name):
    c = sc.CLIPS[name]
    n = c["frames"]
    ev = sorted({v for v in c["events"].values() if isinstance(v, int) and 0 < v < n})
    inner = ev[:2] if len(ev) >= 2 else [round(n / 3), round(2 * n / 3)]
    if len(ev) == 1:
        inner = sorted({ev[0], round(2 * n / 3) if ev[0] < n / 2 else round(n / 3)})
    return [0, *inner, n]


def apply_pose(arm, up, upper_pose, base_pose):
    for pb in arm.pose.bones:
        src = upper_pose if (pb.name in up and upper_pose is not None) else base_pose
        v = src.get(pb.name)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = v["rot"] if v else (1, 0, 0, 0)
        pb.location = v["loc"] if v else (0, 0, 0)
    bpy.context.view_layer.update()


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--soldier", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--only", default="", help="comma-separated sheet names")
    args = ap.parse_args(argv)
    args.out = args.out.resolve()

    objs = kitlib.import_glb(args.soldier)
    arm = kitlib.armature_of(objs)
    sc.capture_static(arm)  # before anything evaluates a clip
    kitlib.apply_base_colours(objs, args.soldier)
    arm = kitlib.armature_of(objs)
    _body, held, stray = kitlib.split_parts(objs)
    for o in stray:
        bpy.data.objects.remove(o)
    held = {re.sub(r"\.\d+$", "", o.name): o for o in held}
    for o in [o for o in bpy.data.objects if o.type == "EMPTY" and o.name.endswith("_end")]:
        o.hide_render = True
    sc.build(arm)
    arm.animation_data.action = None
    for t in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(t)
    arm.data.pose_position = "POSE"
    acts = {a.name.split("|")[-1]: a for a in bpy.data.actions}
    up = set(sc.upper_bones(arm))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = TILE_W, TILE_H
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.82, 0.82, 0.8)
    scene.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3.3
    scene.collection.objects.link(cam)
    scene.camera = cam
    # The Soldier faces -Y; his right is -X. Camera in front, to his right, a little above the chest.
    target = Vector((0, 0, 0.92))
    pos = target + Vector((-0.55, -1.0, 0.25)).normalized() * 20
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
    label_mat = bpy.data.materials.new("label")
    label_mat.diffuse_color = (0.1, 0.1, 0.1, 1)
    cu = bpy.data.curves.new("label", "FONT")
    cu.size = 0.13
    cu.align_x = "CENTER"
    label = bpy.data.objects.new("label", cu)
    label.data.materials.append(label_mat)
    scene.collection.objects.link(label)
    fwd = (target - pos).normalized()
    label.location = Vector((0.35, 0, -0.3)) - fwd * 3
    label.rotation_euler = cam.rotation_euler

    idle0 = sc.full(arm, sc.sample(acts["Idle"], 0))
    sheets = {}
    for cls in sc.CLASSES:
        names = [n for n, c in sc.CLIPS.items() if c["class"] == cls]
        sheets[cls] = [(n, None, cls) for n in names]
    sheets["Body"] = [(n, None, None) for n in ("Idle", "Walk", "Run", "HitReact", "Death", "Downed")]
    sheets["Split"] = [("Aim_Rifle", "Run", "Rifle"), ("Fire_Shotgun", "Walk", "Shotgun"),
                       ("Reload_Rifle", "Walk", "Rifle"), ("Swing_Melee", "Run", "Melee")]  # fmt: skip
    only = {s for s in args.only.split(",") if s}
    tmp = args.out.parent / "_tiles"
    tmp.mkdir(parents=True, exist_ok=True)
    for sheet, rows in sheets.items():
        if only and sheet not in only:
            continue
        grid = []
        for name, base, cls in rows:
            weapon = sc.CLASSES.get(cls) if cls else None
            for n, o in held.items():
                o.hide_render = n != weapon
            row = []
            frames = moments(name)
            for i, f in enumerate(frames):
                layer = sc.CLIPS[name]["layer"]
                if base:  # base clip at the same moment of its own cycle
                    bn = sc.CLIPS[base]["frames"]
                    bpose = sc.full(arm, sc.sample(acts[base], round(i / 4 * bn)))
                else:
                    bpose = idle0
                clip = sc.full(arm, sc.sample(acts[name], f))
                if layer == "upper":
                    apply_pose(arm, up, clip, bpose)
                else:
                    apply_pose(arm, up, None, clip)
                over = f" over {base}" if base else ""
                ev = [k for k, v in sc.CLIPS[name]["events"].items() if v == f or (isinstance(v, list) and f in v)]
                cu.body = f"{name}{over}\nframe {f}/{frames[-1]}" + (f"\n{ev[0]}" if ev else "")
                path = tmp / f"{sheet}_{name}_{i}.png"
                scene.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                img = bpy.data.images.load(str(path))
                px = np.empty(TILE_W * TILE_H * 4, dtype=np.float32)
                img.pixels.foreach_get(px)
                bpy.data.images.remove(img)
                row.append(px.reshape(TILE_H, TILE_W, 4))
            grid.append(np.concatenate(row, axis=1))
        # Rows top to bottom (Blender image rows run bottom-up).
        full_px = np.concatenate(grid[::-1], axis=0)
        h, w = full_px.shape[:2]
        out = bpy.data.images.new(sheet, w, h, alpha=True)
        out.pixels.foreach_set(full_px.ravel())
        out.filepath_raw = str(args.out.with_name(f"{args.out.name}-{sheet.lower()}.png"))
        out.file_format = "PNG"
        out.save()
        print("SHEET", out.filepath_raw, len(rows), "clips")


main()
