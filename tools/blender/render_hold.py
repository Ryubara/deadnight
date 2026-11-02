"""Check that a weapon swaps into the kit Soldier's hand: render the Soldier holding kit weapons and ours, side by side.

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/render_hold.py -- --soldier <bundle>/models/PpLF4rt4ah.glb \
        --kit "Shotgun=<bundle>/models/TyWl27dUz6.glb" --kit "Shovel=<bundle>/models/NrMejTU6kz.glb" \
        --weapon "Lever rifle=Shotgun=game/assets/weapons/lever_rifle/lever_rifle.glb" ... \
        --pose Idle_Shoot --out <workspace>/scratch/deadnight/<branch>/hold.png

The kit Soldier carries every kit weapon as a mesh parented to the `Index1.R` bone. For each `--kit` weapon the script
finds the transform that maps the standalone kit file onto the copy in the hand (the copy carries the same mesh
data, its origin on the bone) and prints it in the bone's space; for each `--weapon` (Title=KitName=path.glb, or
Title=KitName=path.glb=scale with a hold's `model_scale`, its size on the Soldier in the game) it attaches our
file to the same bone with the same transform. If our origin (the grip) and axes (muzzle -X, up +Z for guns; up +Z
for melee) follow the kit's, our weapon sits in the hand exactly where the kit one does. One Soldier per column, seen
over the right shoulder (the third-person camera) and from the side.
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

BONE = "Index1.R"


def mesh_points(objs):
    pts = [p for o in objs if o.type == "MESH" for p in kitlib.world_verts(o)]
    return np.array([tuple(p) for p in pts])


def soldier(path, pose):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    kitlib.apply_base_colours(objs, path)
    arm = kitlib.armature_of(objs)
    fresh = [a for a in bpy.data.actions if a not in kitlib.SEEN]
    kitlib.SEEN.update(bpy.data.actions)
    action = next((a for a in fresh if re.sub(r"\.\d+$", "", a.name.split("|")[-1]) == pose), None)
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and action.slots:
        arm.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(int(action.frame_range[0]))
    _body, held, stray = kitlib.split_parts(objs)
    for o in stray:
        bpy.data.objects.remove(o)
    return objs, arm, {re.sub(r"\.\d+$", "", o.name): o for o in held}


def bone_world(arm):
    return arm.matrix_world @ arm.pose.bones[BONE].matrix


def import_weapon(path):
    before = set(bpy.data.objects)
    kitlib.gltf_import(path)
    objs = [o for o in bpy.data.objects if o not in before]
    kitlib.apply_base_colours(objs, path)
    return objs


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--soldier", required=True)
    ap.add_argument("--kit", action="append", required=True, help="KitName=path.glb (KitName as held in the Soldier)")
    ap.add_argument("--weapon", action="append", default=[], help="Title=KitName=path.glb[=scale]")
    ap.add_argument("--pose", default="Idle_Shoot")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)

    kitlib.reset()
    kitlib.SEEN = set()
    columns = []  # (title, kit name, weapon path or None, kit path or None, scale)
    holds = {}
    for spec in args.kit:
        name, path = spec.split("=", 1)
        columns.append((f"Kit {name}", name, None, path, 1.0))
    for spec in args.weapon:
        title, name, path, *scale = spec.split("=", 3)
        columns.append((title, name, path, None, float(scale[0]) if scale else 1.0))

    # The hold transform of each kit weapon, in the bone's space, from a Soldier at the origin.
    objs, arm, held = soldier(args.soldier, args.pose)
    for spec in args.kit:
        name, path = spec.split("=", 1)
        src_objs = import_weapon(path)
        # The held copy carries the standalone file's own mesh data: the hold is held world @ standalone world^-1.
        src_mesh = next(o for o in src_objs if o.type == "MESH")
        m = held[name].matrix_world @ src_mesh.matrix_world.inverted()
        moved = np.array([tuple(m @ Vector(p)) for p in mesh_points(src_objs)])
        dst = mesh_points([held[name]])
        err = np.abs(moved.min(0) - dst.min(0)).max() + np.abs(moved.max(0) - dst.max(0)).max()
        holds[name] = bone_world(arm).inverted() @ m
        loc, rot, sca = holds[name].decompose()
        muzzle = (holds[name].to_3x3().normalized() @ Vector((-1, 0, 0))).normalized()
        print(
            f"HOLD {name}: bounding-box check {err * 1000:.2f} mm; in {BONE} space: offset {loc.length * 1000:.1f} mm, "
            f"scale {sca.x:.3f}, rotation {[round(math.degrees(a), 1) for a in rot.to_euler()]}, "
            f"weapon -X along bone {[round(c, 2) for c in muzzle]}"
        )
        for o in src_objs:
            bpy.data.objects.remove(o)
    for o in objs:
        bpy.data.objects.remove(o)

    # One Soldier per column, 2.2 m apart, holding one weapon.
    for i, (title, name, path, _kit, scale) in enumerate(columns):
        objs, arm, held = soldier(args.soldier, args.pose)
        arm.location.x = i * 2.2
        bpy.context.view_layer.update()
        for n, o in held.items():
            if path or n != name:
                bpy.data.objects.remove(o)
        if path:
            wobjs = import_weapon(path)
            root = next(o for o in wobjs if o.parent is None)
            root.parent = arm
            root.parent_type = "BONE"
            root.parent_bone = BONE
            bpy.context.view_layer.update()
            root.matrix_world = bone_world(arm) @ holds[name] @ Matrix.Scale(scale, 4)
        cu = bpy.data.curves.new("label", "FONT")
        cu.body = title
        cu.size = 0.16
        cu.align_x = "CENTER"
        t = bpy.data.objects.new("label", cu)
        t.location = (i * 2.2, 0.0, -0.3)
        t.rotation_euler = (math.radians(70), 0, math.radians(180))
        bpy.context.scene.collection.objects.link(t)
        bpy.context.view_layer.update()

    scene = bpy.context.scene
    width = (len(columns) - 1) * 2.2
    r = scene.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x, r.resolution_y = 600 * len(columns), 1300
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_object_outline = True
    sh.background_type = "VIEWPORT"
    sh.background_color = (0.82, 0.82, 0.8)
    scene.view_settings.view_transform = "Standard"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    # Two views stacked: over the shoulder (from behind, a little right and above) and from the Soldier's right.
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, rot, loc in (
        ("shoulder", (math.radians(75), 0, math.radians(200)), (width / 2 + 3.0, 15.0, 5.0)),
        ("side", (math.radians(90), 0, math.radians(-90)), (-20.0, 0.0, 1.2)),
    ):
        cam.rotation_euler = rot
        if view == "shoulder":
            fwd = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
            target = Vector((width / 2, 0, 1.2))
            cam.location = target - fwd * 20
            cam.data.ortho_scale = width + 2.4
        else:
            # Side view: columns overlap along X, so lay the Soldiers out along the camera's right instead.
            r.resolution_x, r.resolution_y = 600 * len(columns), 1100
            for o in bpy.data.objects:
                if o.type == "ARMATURE":
                    o.location = (0, -o.location.x, 0)
                elif o.name.startswith("label"):
                    o.location = (0, -o.location.x, -0.3)
                    o.rotation_euler = (math.radians(90), 0, math.radians(-90))
            bpy.context.view_layer.update()
            cam.location = (20.0, -width / 2, 1.1)
            cam.rotation_euler = (math.radians(90), 0, math.radians(90))
            cam.data.ortho_scale = width + 2.4
        r.filepath = str(args.out.with_name(f"{args.out.stem}-{view}{args.out.suffix}"))
        bpy.ops.render.render(write_still=True)
        print(f"wrote {r.filepath}")


main()
