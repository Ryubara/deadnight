"""Measure the Soldier's arms against its height and shoulders, for every starting look and the kit characters (#978).

Run with the pinned Blender, headless, from the repository root:

    blender -b --factory-startup -P tools/blender/measure_arms.py -- \
        --parts game/assets/characters/soldier_parts/soldier_parts.glb \
        [--kit Soldier=<bundle>/models/PpLF4rt4ah.glb --kit Hazmat=... --kit Enemy=...] \
        [--json <scratch>/arms.json]

Every number is in kit metres (the game draws the Soldier at 0.8 of this), on the skinned meshes a look shows:

- at rest (the T-pose): the height (sole to the top of the head, hair and hats left out), the shoulder width (the
  trunk's width at the shoulder line, z 1.25-1.35, its arm vertices left out), and along the arm the upper arm
  (`UpperArm` joint to `LowerArm` joint), the forearm (to the wrist, where the fingers start) and the hand (the wrist
  to the furthest fingertip of the skin), and their sum, the arm;
- in the Idle clip's first frame (standing, the arms down): how low the fingertips hang, as a share of the height,
  and against the crotch (the `UpperLeg` joints).

It prints one `ARM` line per look and writes the numbers to `--json`.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

ARM_BONES = ("UpperArm", "LowerArm", "Index", "Middle", "Pinky", "Thumb")
FINGERS = ("Index", "Middle", "Pinky", "Thumb")
HEAD_BONES = ("Head", "Neck")
SHOULDER_Z = (1.25, 1.35)


def clean(name):
    return re.sub(r"\.\d+$", "", name.split("|")[-1])


def posed(o):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [o.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def dominant(o):
    names = [g.name for g in o.vertex_groups]
    out = []
    for v in o.data.vertices:
        g = max(v.groups, key=lambda g: g.weight) if v.groups else None
        out.append(clean(names[g.group]) if g else "")
    return out


def joint(arm, bone):
    return arm.matrix_world @ arm.data.bones[bone].head_local


def pose_clip(arm, clip, frame=None):
    a = next((a for a in bpy.data.actions if clean(a.name) == clip), None)
    if a is None:
        return False
    arm.data.pose_position = "POSE"
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = a
    if a.slots:
        arm.animation_data.action_slot = a.slots[0]
    bpy.context.scene.frame_set(round(a.frame_range[0]) if frame is None else frame)
    bpy.context.view_layer.update()
    return True


def rest(arm):
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()


def measure(arm, meshes, head_meshes):
    """The numbers for one look: `meshes` the skinned meshes it shows, `head_meshes` those whose top is the height."""
    rest(arm)
    doms = {o.name: dominant(o) for o in meshes}
    pts = {o.name: posed(o) for o in meshes}
    allp = [p for o in meshes for p in pts[o.name]]
    sole = min(p.z for p in allp)
    top = max(p.z for o in head_meshes for p in pts[o.name])
    height = top - sole
    trunk = [
        p
        for o in meshes
        for p, d in zip(pts[o.name], doms[o.name], strict=True)
        if SHOULDER_Z[0] < p.z < SHOULDER_Z[1] and not d.startswith(ARM_BONES) and not d.startswith(HEAD_BONES)
    ]
    shoulders = max(p.x for p in trunk) - min(p.x for p in trunk)
    out = {"height": height, "shoulders": shoulders}
    for side, sign in (("L", 1), ("R", -1)):
        sh = joint(arm, f"UpperArm.{side}")
        el = joint(arm, f"LowerArm.{side}")
        wr = joint(arm, f"Middle1.{side}")
        tip = max(
            p.x * sign
            for o in meshes
            for p, d in zip(pts[o.name], doms[o.name], strict=True)
            if d.startswith(FINGERS) and d.endswith(side)
        )
        out[side] = {
            "upper": (el - sh).length,
            "forearm": (wr - el).length,
            "hand": tip - wr.x * sign,
            "outer": tip,
        }
    a = out["L"]
    out["upper"], out["forearm"], out["hand"] = a["upper"], a["forearm"], a["hand"]
    out["arm"] = a["upper"] + a["forearm"] + a["hand"]
    out["span"] = out["L"]["outer"] + out["R"]["outer"]
    # Standing: Idle's first frame.
    if pose_clip(arm, "Idle"):
        pts = {o.name: posed(o) for o in meshes}
        tips = [p.z for o in meshes for p, d in zip(pts[o.name], doms[o.name], strict=True) if d.startswith(FINGERS)]
        crotch = (arm.matrix_world @ arm.pose.bones["UpperLeg.L"].head).z
        out["idle_tip"] = min(tips) - sole
        out["idle_crotch"] = crotch - sole
        rest(arm)
    return out


def ratios(m):
    h, s = m["height"], m["shoulders"]
    return {
        "arm/h": m["arm"] / h,
        "upper/h": m["upper"] / h,
        "forearm/h": m["forearm"] / h,
        "hand/h": m["hand"] / h,
        "arm/shoulders": m["arm"] / s,
        "shoulders/h": s / h,
        "span/h": m["span"] / h,
        "tip/h": m.get("idle_tip", 0) / h,
        "tip-crotch": m.get("idle_tip", 0) - m.get("idle_crotch", 0),
    }


def line(name, m):
    r = ratios(m)
    print(
        f"ARM {name:<16} h {m['height']:.3f} sh {m['shoulders']:.3f} | upper {m['upper']:.3f} fore {m['forearm']:.3f} "
        f"hand {m['hand']:.3f} arm {m['arm']:.3f} | arm/h {r['arm/h']:.3f} arm/sh {r['arm/shoulders']:.2f} "
        f"sh/h {r['shoulders/h']:.3f} span/h {r['span/h']:.3f} | idle tip/h {r['tip/h']:.3f} "
        f"tip-crotch {r['tip-crotch']:+.3f}",
        flush=True,
    )
    return {**m, **r}


def kit_character(path):
    objs = kitlib.import_glb(path)
    arm = kitlib.armature_of(objs)
    meshes = [
        o
        for o in objs
        if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers) and not kitlib.is_stray(o, arm)
    ]
    return arm, meshes


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", required=True)
    ap.add_argument("--kit", action="append", default=[], help="Title=path of a kit character")
    ap.add_argument("--json")
    args = ap.parse_args(argv)
    result = {}
    for spec in args.kit:
        title, path = spec.split("=", 1)
        arm, meshes = kit_character(path)
        heads = [o for o in meshes if o.name.startswith("Head")] or meshes
        result[f"kit:{title}"] = line(f"kit {title}", measure(arm, meshes, heads))
    parts = Path(args.parts)
    catalog = json.loads((parts.parent / "parts.json").read_text(encoding="utf-8"))
    objs = kitlib.import_glb(parts)
    arm = kitlib.armature_of(objs)
    by_name = {clean(o.name): o for o in objs if o.type == "MESH"}
    for preset in catalog["presets"]:
        body = preset["parts"].get("body", "male")
        names = []
        for slot, pid in preset["parts"].items():
            part = catalog["slots"][slot]["parts"][pid]
            if not part.get("mesh") or slot in ("hair", "headwear", "eyewear"):
                continue  # the height is the head's top: hair and hats left out
            names.append(part[body]["mesh"] if body in part else part["mesh"])
        meshes = [by_name[n] for n in names if n in by_name]
        heads = [o for o in meshes if clean(o.name).startswith("head__")]
        m = measure(arm, meshes, heads)
        m["body"] = body
        m["torso"] = preset["parts"]["torso"]
        result[preset["id"]] = line(f"{preset['id']} ({body[0]})", m)
    if args.json:
        Path(args.json).write_text(json.dumps(result, indent=1), encoding="utf-8")


main()
