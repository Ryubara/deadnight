"""Measure the female Soldier against the male one in every clip (#678): stretching, arms in the chest, hair in the
shoulders.

Run with the pinned Blender, headless, from the repository root, on a built parts file:

    blender -b --factory-startup -P tools/blender/measure_soldier_body.py -- \
        --parts game/assets/characters/soldier_parts/soldier_parts.glb \
        --clips game/assets/characters/soldier/sprint/soldier_sprint.glb [--clips ...] \
        --json <scratch>/body.json

For each clip (the parts file's own and those of every `--clips` file, same bones) it poses the armature at every
`--step`th frame and reads the skinned meshes:

- stretch: how much the edges of the trunk (rest z 0.85-1.40 kit metres, |x| < 0.35) change length, as |ln(posed /
  rest)|: the 99th percentile over the edges (the kit's own shoulder and hip edges stretch far in some clips, so the
  single worst edge says more about the kit than about her), for each torso part as built and as hers;
- arms in the chest: how deep (kit metres) the forearm and hand vertices of a torso part go inside its own trunk
  (closest-point test), as the mean of the ten deepest (one stray vertex by the trunk's open edge counts a tenth),
  his and hers: the kit's own carries lay a forearm on the chest, so his is not zero, and a fuller chest that the
  arms pass through shows as a deeper one (the count of vertices inside is printed too);
- hair in the shoulders: how many vertices of each hair cut are inside the torso (the jacket, the tall collar
  included) on her body; her cuts (bob, curls, bun) are held to the worst of his (crew, pompadour, flattop, ponytail).

It prints one line per clip and a summary, and writes the numbers to `--json`. It fails (exit 1) when her stretch
in a clip is more than `--stretch-margin` (a share of his) above his, her arms go more than `--depth-margin` deeper
into her chest than his into his, or one of her cuts has more than `--count-margin` vertices inside the torso beyond
the worst of his.
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kitlib

ARM_BONES = ("UpperArm", "LowerArm", "Index", "Middle", "Pinky", "Thumb")
TRUNK_Z = (0.85, 1.40)  # kit metres at rest
TRUNK_X = 0.35
DEEPEST = 10  # the arm depth is the mean of this many deepest vertices inside the trunk (missing ones count 0)
TORSOS = ("vest", "jacket", "shirt", "rolled", "tank", "letterman")
HIS_HAIR = ("crew", "pompadour", "flattop", "ponytail")
HER_HAIR = ("bob", "curls", "bun")


def clean(name):
    return re.sub(r"\.\d+$", "", name.split("|")[-1])


def posed(o):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    mw = o.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


class Part:
    """A torso part's rest data: its trunk edges, its trunk faces and its arm vertices."""

    def __init__(self, o, arm):
        self.o = o
        arm.data.pose_position = "REST"
        bpy.context.view_layer.update()
        rest = posed(o)
        arm.data.pose_position = "POSE"
        names = [g.name for g in o.vertex_groups]
        me = o.data
        dominant = []
        for v in me.vertices:
            g = max(v.groups, key=lambda g: g.weight) if v.groups else None
            dominant.append(names[g.group] if g else "")
        lo, hi = (TRUNK_Z[0] * self.scale(rest), TRUNK_Z[1] * self.scale(rest))
        x_max = TRUNK_X * self.scale(rest)
        self.trunk_v = {
            i
            for i, p in enumerate(rest)
            if lo < p.z < hi and abs(p.x) < x_max and not dominant[i].startswith(ARM_BONES)
        }
        self.edges = [(e.vertices[0], e.vertices[1]) for e in me.edges if set(e.vertices) <= self.trunk_v]
        self.rest_len = [max((rest[a] - rest[b]).length, 1e-6) for a, b in self.edges]
        self.faces = [list(p.vertices) for p in me.polygons if set(p.vertices) <= self.trunk_v]
        self.arm_v = [
            i for i, d in enumerate(dominant) if d.startswith(("LowerArm", "Index", "Middle", "Pinky", "Thumb"))
        ]

    @staticmethod
    def scale(rest):
        """Metres per kit metre for this file: the kit Soldier's trunk top (collar, 1.68) to the ground."""
        return max(p.z for p in rest) / 1.68

    def measure(self):
        pts = posed(self.o)
        logs = sorted(abs(math.log((pts[a] - pts[b]).length / r)) for (a, b), r in zip(self.edges, self.rest_len))
        stretch = logs[int(0.99 * (len(logs) - 1))] if logs else 0.0
        tree = BVHTree.FromPolygons(pts, self.faces)
        depths = []
        for i in self.arm_v:
            hit = tree.find_nearest(pts[i])
            if hit[0] is not None and hit[3] < 0.1 and (pts[i] - hit[0]).dot(hit[1]) < -0.004:
                depths.append(hit[3])
        deepest = sorted(depths, reverse=True)[:DEEPEST]
        return stretch, len(depths), sum(deepest) / DEEPEST


def hair_inside(hair, torso_pts, torso_faces):
    tree = BVHTree.FromPolygons(torso_pts, torso_faces)
    n = 0
    for p in posed(hair):
        hit = tree.find_nearest(p)
        if hit[0] is not None and hit[3] < 0.08 and (p - hit[0]).dot(hit[1]) < -0.004:
            n += 1
    return n


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", required=True)
    ap.add_argument("--clips", action="append", default=[])
    ap.add_argument("--step", type=int, default=3)
    ap.add_argument("--json", type=Path)
    ap.add_argument("--stretch-margin", type=float, default=0.1)
    ap.add_argument("--depth-margin", type=float, default=0.012)
    ap.add_argument("--count-margin", type=int, default=6)
    args = ap.parse_args(argv)

    kitlib.reset()
    acts = {}
    for path in args.clips:
        before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
        kitlib.gltf_import(path)
        for o in [o for o in bpy.data.objects if o not in before_o]:
            bpy.data.objects.remove(o)
        acts.update({clean(a.name): a for a in bpy.data.actions if a not in before_a})
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    kitlib.gltf_import(args.parts)
    objs = [o for o in bpy.data.objects if o not in before_o]
    own = {clean(a.name): a for a in bpy.data.actions if a not in before_a}
    acts = {**own, **{k: v for k, v in acts.items() if k not in own}}
    arm = kitlib.armature_of(objs)
    arm.animation_data_create()
    mesh = {o.name: o for o in objs if o.type == "MESH"}
    for o in mesh.values():
        o.hide_set(False)

    torsos = {}
    for t in TORSOS:
        for who, name in (("he", f"torso__{t}"), ("she", f"torso__{t}__female")):
            torsos[t, who] = Part(mesh[name], arm)
    jacket = {who: torsos["jacket", who] for who in ("he", "she")}

    results = {}
    failures = []
    for clip in sorted(acts):
        a = acts[clip]
        arm.animation_data.action = a
        if a.slots:
            arm.animation_data.action_slot = a.slots[0]
        f0, f1 = (round(v) for v in a.frame_range)
        row = {"stretch": {"he": 0.0, "she": 0.0}, "arms_in_chest": {"he": 0, "she": 0},
               "arm_depth": {"he": 0.0, "she": 0.0},
               "hair_in_torso": {h: 0 for h in HIS_HAIR + HER_HAIR}}  # fmt: skip
        for frame in range(f0, f1 + 1, args.step):
            bpy.context.scene.frame_set(frame)
            for who in ("he", "she"):
                for t in TORSOS:
                    s, inside, depth = torsos[t, who].measure()
                    row["stretch"][who] = max(row["stretch"][who], s)
                    row["arms_in_chest"][who] = max(row["arms_in_chest"][who], inside)
                    row["arm_depth"][who] = max(row["arm_depth"][who], depth)
            pts = posed(jacket["she"].o)
            faces = [list(p.vertices) for p in jacket["she"].o.data.polygons]
            for h in HIS_HAIR + HER_HAIR:
                row["hair_in_torso"][h] = max(row["hair_in_torso"][h], hair_inside(mesh[f"hair__{h}"], pts, faces))
        results[clip] = row
        bad = []
        if row["stretch"]["she"] > row["stretch"]["he"] * (1 + args.stretch_margin):
            bad.append("stretch")
        if row["arm_depth"]["she"] > row["arm_depth"]["he"] + args.depth_margin:
            bad.append("arm_depth")
        his_worst = max(row["hair_in_torso"][h] for h in HIS_HAIR)
        bad += [f"hair:{h}" for h in HER_HAIR if row["hair_in_torso"][h] > his_worst + args.count_margin]
        if bad:
            failures.append((clip, bad))
        print(
            f"CLIP {clip:18s} stretch he {row['stretch']['he']:.3f} she {row['stretch']['she']:.3f}  "
            f"arms-in-chest he {row['arms_in_chest']['he']:3d} ({row['arm_depth']['he'] * 1000:3.0f} mm) "
            f"she {row['arms_in_chest']['she']:3d} ({row['arm_depth']['she'] * 1000:3.0f} mm)  "
            "hair-in-torso "
            + " ".join(f"{h} {n}" for h, n in row["hair_in_torso"].items())
            + ("  FAIL " + ",".join(bad) if bad else "")
        )
    print("CLIPS", len(results), "FAILURES", json.dumps(failures))
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(results, indent=1) + "\n", encoding="utf-8")
    if failures:
        sys.exit(1)


try:
    main()
except SystemExit as e:
    import os

    sys.stdout.flush()
    os._exit(e.code or 0)
