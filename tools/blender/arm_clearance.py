"""How deep the forearms and hands go into the rest of the body in a pose (Deadnight #939), in Blender.

The game's check is `ClipFit` (game/tests/art/clip_fit.gd) on the dressed parts in Godot; this is the same test on
the kit Soldier's own skinned meshes, so a clip can be measured while it is authored, before any export: the build
prints one `ARMS` line per clip it writes (build_soldier.py), and a pose can be tried and changed in one Blender run.

A vertex is inside when all six axis rays from it (0.5 m) first meet a face that faces away from the ray, as in
`BodyFit.depth_inside`; its depth is the nearest of those faces. Each vertex belongs to the group of the bone that
carries most of its weight (`BodyFit.GROUPS`); the left arm's forearm and hand are tested against the trunk, the head,
the legs and the right forearm and hand, and the right arm's likewise. Kit metres: the game draws 0.8 of them.
"""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

GROUPS = {
    "head": ("Head", "Neck"),
    "trunk": ("Torso", "Abdomen", "Hips", "Body", "Shoulder.L", "Shoulder.R"),
    "upper_arm.L": ("UpperArm.L",),
    "upper_arm.R": ("UpperArm.R",),
    "forearm.L": ("LowerArm.L",),
    "forearm.R": ("LowerArm.R",),
    "thigh.L": ("UpperLeg.L",),
    "thigh.R": ("UpperLeg.R",),
    "shin.L": ("LowerLeg.L", "Foot.L"),
    "shin.R": ("LowerLeg.R", "Foot.R"),
}
HAND_PREFIXES = ("Index", "Middle", "Pinky", "Thumb", "Ring", "Palm", "Wrist", "Hand")
# The game's tolerance (ClipFit.TOLERANCE): skin on skin, a hand laid on a thigh, is not a fault.
TOLERANCE = 0.03
REACH = 0.5
AXES = tuple(Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)))


def group_of(bone):
    if bone.startswith(HAND_PREFIXES):
        return "hand." + bone[-1]
    return next((g for g, bones in GROUPS.items() if bone in bones), "")


def movers(side):
    return {f"hand.{side}", f"forearm.{side}"}


def targets(side):
    other = "R" if side == "L" else "L"
    return {"trunk", "head", "thigh.L", "thigh.R", "shin.L", "shin.R", f"hand.{other}", f"forearm.{other}"}


class Body:
    """The skinned meshes of an armature, each vertex tagged with its group."""

    def __init__(self, arm):
        # Skinned meshes, and meshes that follow one bone (the kit head and shoulder pads); not what the hands hold.
        self.meshes = [
            o
            for o in bpy.data.objects
            if o.type == "MESH"
            and o.parent == arm
            and (o.vertex_groups or (o.parent_type == "BONE" and group_of(o.parent_bone) not in ("hand.L", "hand.R")))
        ]
        self.groups = []
        for o in self.meshes:
            if o.parent_type == "BONE":
                self.groups += [group_of(o.parent_bone)] * len(o.data.vertices)
                continue
            names = {vg.index: vg.name for vg in o.vertex_groups}
            for v in o.data.vertices:
                best = max(v.groups, key=lambda g: g.weight, default=None)
                self.groups.append(group_of(names[best.group]) if best is not None else "")

    def posed(self):
        """(points, triangles) of the meshes as the armature poses them now."""
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        pts, tris = [], []
        for o in self.meshes:
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            base = len(pts)
            mw = o.matrix_world
            pts += [mw @ v.co for v in me.vertices]
            me.calc_loop_triangles()
            tris += [tuple(base + i for i in t.vertices) for t in me.loop_triangles]
            ev.to_mesh_clear()
        return pts, tris

    def depths(self, stride=2):
        """{side: (deepest metres, group it is in, the mover's group)} for the arms in the current pose."""
        pts, tris = self.posed()
        out = {}
        for side in ("L", "R"):
            want, into = movers(side), targets(side)
            # Every part the arm must stay out of in one surface, as ClipFit tests it: the group surfaces are open
            # where one bone's skin meets the next, so a hand in a fold (the lap, an armpit) can see a back face of
            # one part or another down every axis without being deep in any of them, and that counts too.
            faces = [t for t in tris if self.groups[t[0]] in into]
            best = (0.0, "", "")
            if faces:
                tree = BVHTree.FromPolygons(pts, faces)
                for i in range(0, len(pts), stride):
                    if self.groups[i] not in want:
                        continue
                    d, face = _depth(tree, pts[i])
                    if d > best[0]:
                        best = (d, self.groups[faces[face][0]], self.groups[i])
            out[side] = best
        return out


def _depth(tree, p):
    """(depth, the nearest back face's index) of a point inside the surface, or (0, -1)."""
    deepest, nearest = REACH, -1
    for axis in AXES:
        hit, normal, index, dist = tree.ray_cast(p, axis, REACH)
        if hit is None or normal.dot(axis) <= 0.0:
            return 0.0, -1
        if dist < deepest:
            deepest, nearest = dist, index
    return deepest, nearest


def clip_depths(arm, body, action, samples=8):
    """The deepest of each arm over `samples` evenly spread frames of `action` (each at the middle of its slice, as
    ClipFit samples), and over its key frames: {side: (depth, into, mover, frame)}."""
    ad = arm.animation_data or arm.animation_data_create()
    for t in ad.nla_tracks:
        t.mute = True
    ad.action = action
    if hasattr(ad, "action_slot") and action.slots:
        ad.action_slot = action.slots[0]
    end = action.frame_range[1]
    frames = {end * (k + 0.5) / samples for k in range(samples)}
    for fc in action.fcurves if hasattr(action, "fcurves") and action.fcurves else _curves(action):
        frames |= {k.co[0] for k in fc.keyframe_points}
    worst = {"L": (0.0, "", "", 0.0), "R": (0.0, "", "", 0.0)}
    scene = bpy.context.scene
    for f in sorted(frames):
        scene.frame_set(int(f), subframe=f - int(f))
        for side, (d, into, mover) in body.depths().items():
            if d > worst[side][0]:
                worst[side] = (d, into, mover, f)
    ad.action = None
    return worst


def _curves(action):
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def line(name, worst):
    """One `ARMS` line: each arm's deepest, what it went into and at which frame."""
    parts = [
        f"{s} {d * 1000:.0f} mm ({mover} in {into} at {f:.1f})" if d > TOLERANCE else f"{s} ok"
        for s, (d, into, mover, f) in sorted(worst.items())
    ]
    return f"ARMS {name}: " + ", ".join(parts)
