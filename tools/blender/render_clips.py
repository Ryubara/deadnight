"""Contact sheets of the Soldier's clips: four moments of each clip, one sheet per weapon class (Deadnight #42).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_clips.py -- \
        --soldier <bundle>/models/PpLF4rt4ah.glb --out <workspace>/scratch/deadnight/<branch>/clips

Writes `<out>-<sheet>.png` for the sheets Rifle, Shotgun, Pistol, Melee, Body (full-body clips) and Split (upper
clips over moving legs; GrenadeSplit and RepairSplit the same for those clips; Revive the downed and reviver clips; `--view back` shows them from behind,
as the game's camera does). Each tile is posed the way Godot's upper/lower blend poses the character: upper-body bones
from the upper clip, every other bone from the base clip (Idle, or Run/Walk on the Split sheet), so the sheet shows
what the bone filter will. The class's kit weapon stays in the hand (Deadnight's weapons copy those holds). Moments:
first frame, two inner frames (the clip's first event when it has one), last frame. Workbench, flat lighting, seen
from the Soldier's front right at a third-person camera height.
"""

import argparse
import math
import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
import soldier_clips as sc

TILE_W, TILE_H = 360, 440


def key_moments(action, events, count=6):
    """`count` moments of a clip: its key frames and event frames, the widest gaps split until there are enough."""
    fs = {round(k.co[0]) for fc in sc.fcurves(action) for k in fc.keyframe_points}
    fs |= {v for v in events.values() if isinstance(v, int)}
    fs = sorted(fs)
    while len(fs) < count:
        i = max(range(len(fs) - 1), key=lambda j: fs[j + 1] - fs[j])
        fs.insert(i + 1, (fs[i] + fs[i + 1]) // 2)
    while len(fs) > count:  # drop the frame closest to its left neighbour, never the first or last
        i = min(range(1, len(fs) - 1), key=lambda j: fs[j] - fs[j - 1])
        fs.pop(i)
    return fs


def moments(name):
    c = sc.CLIPS[name]
    n = c["frames"]
    ev = sorted({v for v in c["events"].values() if isinstance(v, int) and 0 < v < n})
    inner = ev[:2] if len(ev) >= 2 else [round(n / 3), round(2 * n / 3)]
    if len(ev) == 1:
        inner = sorted({ev[0], round(2 * n / 3) if ev[0] < n / 2 else round(n / 3)})
    return [0, *inner, n]


# Events after which a part of the held weapon is gone (None: the whole weapon, thrown).
GONE_AFTER = {"pin_out": "Pin", "spoon_off": "Spoon", "release": None}


def attach(path, kit, turn=(180, 0, 0), scale=1.0):
    """Import our weapon and hold it where the kit weapon `kit` sits, turned by `turn` (degrees, XYZ, in the weapon's
    own axes: the grenade stands in the gun hold upside down, so it turns 180 about X); return its root object. The
    kit copy's mesh is in the armature's 1/100 units, so the child drops that scale."""
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    new = [o for o in bpy.data.objects if o not in before]
    root = next(o for o in new if o.type == "MESH" and (o.parent is None or o.parent not in new))
    for m in root.data.materials:  # Workbench draws the material colour, not the atlas: the body's olive
        m.diffuse_color = (0.067, 0.122, 0.016, 1)
    root.parent = kit
    root.matrix_parent_inverse = Matrix.Identity(4)
    root.matrix_basis = (
        Matrix.Scale(scale / kit.matrix_world.to_scale()[0], 4)
        @ Euler([math.radians(v) for v in turn]).to_matrix().to_4x4()
    )
    return root


def attach_grip(path, arm, hold):
    """Import our weapon and hold it the way the game draws it: on the hand bone Index1.R, where the solved grip of
    the hold file `hold` puts it (soldier_clips.game_grip); return its root object. The glTF import turns the model's
    Y-up axes to Z up, so that turn is undone before the grip's transform (written in the model's own axes)."""
    weapon, _left = sc.game_grip(hold)
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    new = [o for o in bpy.data.objects if o not in before]
    root = next(o for o in new if o.parent is None or o.parent not in new)
    for o in new:
        for m in getattr(o.data, "materials", []) or []:
            m.diffuse_color = (0.067, 0.122, 0.016, 1)
    y_up = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()  # Blender's Z up to the model's Y up
    bpy.context.view_layer.update()
    at = root.matrix_world.copy()
    bone = sc._bone_matrix(arm, "Index1.R")
    root.parent = arm
    root.parent_type = "BONE"
    root.parent_bone = "Index1.R"
    root.matrix_world = bone @ weapon @ y_up @ at
    return root


def set_hidden(o, hidden):
    for x in (o, *o.children_recursive):
        x.hide_render = hidden


def show_parts(weapon, events, frame):
    """Hide the weapon's parts whose event has passed at `frame` (the pin after pin_out, the grenade after release)."""
    if weapon is None:
        return
    for ev, part in GONE_AFTER.items():
        at = events.get(ev)
        gone = at is not None and (frame > at if part is None else frame >= at)
        if part is None:
            if gone:
                set_hidden(weapon, True)
        else:
            for c in weapon.children:
                if c.name.split(".")[0] == part:
                    c.hide_render = gone


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
    ap.add_argument(
        "--weapon",
        action="append",
        default=[],
        help="Class=path.glb=KitName[=scale[=rx,ry,rz]]: hold one of our weapons for a class's sheet, in the kit "
        "weapon's hold (the Grenade sheet: Grenade=game/assets/weapons/grenade/grenade.glb=Shotgun); scale is the hold's "
        "model_scale (game/gameplay/player/holds/), the turn (degrees) maps the model's axes onto the kit weapon's: "
        "180,0,0 for a gun (the default), -90,0,0 for a melee weapon on the kit Shovel",
    )
    ap.add_argument(
        "--view",
        default="front",
        choices=("front", "back", "side", "top"),
        help="front: from the Soldier's front right (the default); back: from behind his right shoulder, the way the "
        "third-person camera sees him; side: from his right; top: from above and behind (feet on a strafe)",
    )
    ap.add_argument(
        "--grip",
        action="append",
        default=[],
        help="Class=path.glb=hold: hold one of our weapons for a class's sheet the way the game does, through the "
        "solved grip of game/gameplay/player/holds/<hold>.tres (Rifle=game/assets/weapons/lever_rifle/lever_rifle.glb=rifle)",
    )
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
    kits = dict(held)  # the kit weapons, by name, even once one of ours takes a class's place
    for spec in args.weapon:
        cls, path, kit, *more = spec.split("=")
        scale = float(more[0]) if more else 1.0
        turn = tuple(float(v) for v in more[1].split(",")) if len(more) > 1 else (180, 0, 0)
        held[cls] = attach(path, kits[kit], turn, scale)
    for spec in args.grip:
        cls, path, hold = spec.split("=")
        held[cls] = attach_grip(path, arm, hold)
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
    view = {"front": (-0.55, -1.0, 0.25), "back": (-0.55, 1.0, 0.25), "side": (-1.0, 0.0, 0.05), "top": (0, 0.55, 1.0)}
    pos = target + Vector(view[args.view]).normalized() * 20
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
    for cls in dict.fromkeys([*sc.CLASSES, *(c["class"] for c in sc.CLIPS.values() if c["class"])]):
        names = [n for n, c in sc.CLIPS.items() if c["class"] == cls]
        sheets[cls] = [(n, None, cls) for n in names]
    sheets["Body"] = [(n, None, None) for n in ("Idle", "Walk", "Run", "HitReact", "Death", "Downed")]
    sheets["Split"] = [("Aim_Rifle", "Run", "Rifle"), ("Fire_Shotgun", "Walk", "Shotgun"),
                       ("Reload_Rifle", "Walk", "Rifle"), ("Swing_Melee", "Run", "Melee")]  # fmt: skip
    sheets["GrenadeSplit"] = [(n, "Run", "Grenade") for n in sc.CLIPS if n.startswith("Grenade_")]
    sheets["RepairSplit"] = [(n, "Walk", "Repair") for n in sc.CLIPS if n.startswith("Repair_")]
    # Moving while aiming: the kit Run for reference, then the four aim-move clips, every third frame of the cycle.
    sheets["AimMove"] = [(n, None, "Rifle") for n in ("Run", *sc.AIM_MOVES)]
    # Downed and revive (#504): the old Downed (Death's last frame) above the clips that replace it.
    sheets["Revive"] = [(n, None, None) for n in ("Downed", "Downed_Idle", "Downed_Crawl", "Revive_Kneel")]
    # The sprint carry: one stride (every second frame of Run's 17), each Sprint_<Class> over Run at the same frame
    # (the game plays them in phase); SprintBefore is what a sprint showed before them, Aim_<Class> over Run.
    sheets["Sprint"] = [(f"Sprint_{c}", "Run", c) for c in (*sc.SPRINT_CLASSES, *sc.SPRINT_MODELS)]
    sheets["SprintBefore"] = [(f"Aim_{c}", "Run", c) for c in sc.SPRINT_CLASSES]
    only = {s for s in args.only.split(",") if s}
    tmp = args.out.parent / "_tiles"
    tmp.mkdir(parents=True, exist_ok=True)
    for sheet, rows in sheets.items():
        if only and sheet not in only:
            continue
        grid = []
        for name, base, cls in rows:
            # One of ours for the class when given (--weapon), else the kit weapon whose hold the class uses. Hide
            # every weapon, then show that one: hide_render is not inherited, so ours shows under a hidden kit parent.
            weapon = (cls if cls in held else sc.CLASSES.get(cls, cls)) if cls else None
            for o in [*kits.values(), *held.values()]:
                set_hidden(o, True)
            if weapon in held:
                set_hidden(held[weapon], False)
            row = []
            if sheet == "AimMove":
                frames = list(range(0, sc.CLIPS[name]["frames"], 3))
            elif sheet.startswith("Sprint"):
                frames = list(range(0, sc.CLIPS["Run"]["frames"], 2))
            elif sheet.startswith(("Grenade", "Repair", "Revive")):
                frames = key_moments(acts[name], sc.CLIPS[name]["events"])
            else:
                frames = moments(name)
            for i, f in enumerate(frames):
                layer = sc.CLIPS[name]["layer"]
                if base and sheet.startswith("Sprint"):  # in phase: Run at the same frame
                    bpose = sc.full(arm, sc.sample(acts[base], f))
                elif base:  # base clip at the same moment of its own cycle
                    bn = sc.CLIPS[base]["frames"]
                    bpose = sc.full(arm, sc.sample(acts[base], round(i / len(frames) * bn)))
                else:
                    bpose = idle0
                clip = sc.full(arm, sc.sample(acts[name], f % (sc.CLIPS[name]["frames"] + 1)))
                if layer == "upper":
                    apply_pose(arm, up, clip, bpose)
                else:
                    apply_pose(arm, up, None, clip)
                over = f" over {base}" if base else ""
                ev = [k for k, v in sc.CLIPS[name]["events"].items() if v == f or (isinstance(v, list) and f in v)]
                show_parts(held.get(weapon), sc.CLIPS[name]["events"], f)
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
