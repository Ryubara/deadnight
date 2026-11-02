"""Build the third-person Soldier: the kit Soldier cleaned for Godot, with the kit clips and the weapon clips.

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/build_soldier.py -- \
        --soldier <bundle>/models/PpLF4rt4ah.glb --out game/assets/characters/soldier/soldier.glb

Writes the .glb and `clips.json` beside it (clip list, layer, loop, class, length and event frames, from
soldier_clips.CLIPS). The clean-up follows the kit's rig-sharing recipe (kit docs/blender/rig-sharing.md, script
sandbox/rig-sharing/blender/clean_export.py) with one change found here: the export writes the file's static pose,
not the rest pose, for every bone a clip leaves out (see soldier_clips.capture_static and docs/design/animation.md).
"""

import argparse
import json
import re
import struct
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib
import soldier_clips as sc


def strip_channels(path, unkeyed):
    """Take the channels of the bones a clip does not key out of a .glb: {clip: {bone, ...}}. Blender's exporter
    samples every bone of every clip, so a clip that leaves the fingers to the game's HandGripPose would still carry
    them, at the static pose. Unused samplers go too; their accessors stay in the buffer (unreferenced, valid glTF).
    Returns {clip: channels removed}."""
    data = path.read_bytes()
    size = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + size])
    rest = data[20 + size :]
    removed = {}
    for anim in gltf.get("animations", []):
        drop = unkeyed.get(anim["name"])
        if not drop:
            continue
        keep = [c for c in anim["channels"] if gltf["nodes"][c["target"]["node"]].get("name") not in drop]
        removed[anim["name"]] = len(anim["channels"]) - len(keep)
        used = sorted({c["sampler"] for c in keep})
        index = {old: new for new, old in enumerate(used)}
        anim["samplers"] = [anim["samplers"][i] for i in used]
        for c in keep:
            c["sampler"] = index[c["sampler"]]
        anim["channels"] = keep
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    chunk = struct.pack("<II", len(text), 0x4E4F534A) + text
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, 12 + len(chunk) + len(rest)) + chunk + rest)
    return removed


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--soldier", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument(
        "--keep-held",
        default="",
        help="comma-separated kit weapons to leave in the hand (Shotgun,Shovel): a measuring copy, to read the hold "
        "transforms in Godot; never the game's file",
    )
    ap.add_argument(
        "--clips",
        default="",
        help="export only the clips whose name starts with this, or with one of these comma-separated prefixes "
        "(Grenade_: the grenade clips as their own file, game/assets/characters/soldier/grenade/soldier_grenade.glb, "
        "for the controller to add to the Soldier's library; Walk_,Strafe_: the aim-move clips); clips.json beside "
        "it lists only those",
    )
    args = ap.parse_args(argv)
    out = args.out.resolve()

    objs = kitlib.import_glb(args.soldier)  # TEMPERANCE bones (recipe step 1)
    arm = kitlib.armature_of(objs)
    sc.capture_static(arm)  # before anything evaluates a clip
    ad = arm.animation_data
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    ad.action = None

    # Author the new clips in file units (rotations are unit-free; Body location keys get scaled below with the rest).
    sc.build(arm)
    kit_actions = [a for a in bpy.data.actions if "|" in a.name]
    for a in kit_actions:
        sc.bake_static(arm, a)

    # 2. Held items (the 14 kit weapons on Index1.R), strays, leaf empties.
    _body, held, stray = kitlib.split_parts(objs)
    keep = {k for k in args.keep_held.split(",") if k}
    held = [o for o in held if re.sub(r"\.\d+$", "", o.name) not in keep]
    for o in held + stray:
        bpy.data.objects.remove(o)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY" and o.name.endswith("_end")]:
        bpy.data.objects.remove(o)

    # 3. The armature becomes the root.
    root = arm.parent
    mw = arm.matrix_world.copy()
    arm.parent = None
    arm.matrix_world = mw
    if root is not None and root.type == "EMPTY":
        bpy.data.objects.remove(root)

    # 4. Apply the 100x scale; pin bone-attached meshes at rest; scale location keys.
    factor = arm.scale[0]
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    pinned = {c: c.matrix_world.copy() for c in arm.children if c.parent_type == "BONE"}
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True, properties=False)
    bpy.context.view_layer.update()
    for c, m in pinned.items():
        c.matrix_world = m
    arm.data.pose_position = "POSE"
    for c in arm.children:
        if c.type == "MESH" and c.parent_type != "BONE":
            bpy.ops.object.select_all(action="DESELECT")
            c.select_set(True)
            bpy.context.view_layer.objects.active = c
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 5. One clip per name, bare names; location keys scaled; one NLA track each. Kit clips the game does not use
    # (Wave, Yes, No, Punch, Duck, Jump x3) stay in the file: they cost nothing until played and the lobby may want them.
    for a in kit_actions:
        a.name = re.sub(r"^.*\|", "", a.name)
    if args.clips:
        prefixes = tuple(args.clips.split(","))
        for a in [a for a in bpy.data.actions if not a.name.startswith(prefixes)]:
            bpy.data.actions.remove(a)
        for name in [n for n in sc.CLIPS if not n.startswith(prefixes)]:
            del sc.CLIPS[name]
    clips = sorted(bpy.data.actions, key=lambda a: a.name)
    for a in clips:
        a.use_fake_user = True
        for fc in sc.fcurves(a):
            if fc.data_path.endswith(".location"):
                for k in fc.keyframe_points:
                    k.co[1] *= factor
                    k.handle_left[1] *= factor
                    k.handle_right[1] *= factor
    for a in clips:
        track = ad.nla_tracks.new()
        track.name = a.name
        strip = track.strips.new(a.name, int(a.frame_range[0]), a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    # The export's node transforms (Godot's skeleton rest) are the static pose, not Blender's rest (arms out).
    arm.data.pose_position = "POSE"
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = sc.STATIC[pb.name]["rot"]
        pb.location = sc.STATIC[pb.name]["loc"] * factor

    # 6. Meshes named like bones.
    bones = {b.name for b in arm.data.bones}
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        if o.name in bones:
            o.name = o.data.name = o.name + "_Mesh"

    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_reset_pose_bones=False,  # True resets to Blender's rest between clips: arms out on unkeyed bones
        export_optimize_animation_size=False,
    )
    stripped = strip_channels(out, {k: v for k, v in sc.UNKEYED.items() if k in sc.CLIPS})
    spec = {
        "source": "Quaternius Toon Shooter Game Kit, Soldier (CC0); clips authored by tools/blender/soldier_clips.py",
        "fps": sc.FPS,
        "upper_bones": sc.upper_bones(arm),
        "classes": sc.CLASSES,
        "clips": sc.CLIPS,
    }
    out.with_name("clips.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    print(
        "SOLDIER",
        out.name,
        {
            "bones": len(arm.data.bones),
            "clips": len(clips),
            "unkeyed_channels_removed": stripped,
            "tris": sum(kitlib.tris(o) for o in meshes),
            "meshes": {o.name: kitlib.tris(o) for o in meshes},
        },
    )


main()
