"""Locomotion helpers for clips authored on the kit rigs (Deadnight #74): feet that sweep the ground at a known speed,
legs solved to meet them, and the planted-foot ground speed read back.

Not run on its own: soldier_clips.py imports it. Poses are {bone: {"rot": Quaternion, "loc": Vector}} in the bones'
own (local) space, as soldier_clips writes them. Positions are in the world (metres at kit scale, Blender Z up); the
armature may carry an object scale (the Soldier is authored in file units under a 100x object scale), so every
distance is measured through `arm.matrix_world`.

Why not Blender's IK constraint: the kit bones are imported from glTF with arbitrary tails (every leg bone of the
zombie is 0.518 long), so the solver works on the wrong lengths. The legs here are measured from a kit clip instead:
the thigh (hip to knee) and the ankle, the Foot bone's head, which on the kit rigs is the IK target the boots are
weighted to and sits at a fixed place in the lower leg's frame in every kit frame.
"""

import itertools
import math

import bpy
from mathutils import Quaternion, Vector

LEGS = (("UpperLeg.L", "LowerLeg.L", "Foot.L"), ("UpperLeg.R", "LowerLeg.R", "Foot.R"))
REACH_USE = 0.97  # the furthest a foot may be from the hip, of the thigh and shin together (a knee never locks)


def apply_pose(arm, pose):
    """Put `pose` on the pose bones and evaluate it: no action, NLA tracks muted (an unmuted track overrides the pose
    bones on every update, so a pose set by hand reads back as the track's)."""
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in ad.nla_tracks:
        t.mute = True
    for b, v in pose.items():
        pb = arm.pose.bones[b]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = v["rot"]
        pb.location = v["loc"]
    bpy.context.view_layer.update()


def up_axis(arm):
    """World up (Blender +Z) in the armature's own space."""
    return (arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, 1))).normalized()


def leg_shape(arm, poses):
    """Each leg's thigh length and its ankle (the Foot bone's head) in the lower leg's frame, averaged over `poses`
    (the frames of a kit clip). `spread` is how far the ankle strays from its mean: small on a rig whose kit clips
    were solved with IK, which is what lets a two-bone solve stand in for the kit's."""
    shape = {}
    for upper, lower, foot in LEGS:
        thigh, locals_ = [], []
        for pose in poses:
            apply_pose(arm, pose)
            hip, knee = arm.pose.bones[upper].head, arm.pose.bones[lower].head
            locals_.append(arm.pose.bones[lower].matrix.to_3x3().inverted() @ (arm.pose.bones[foot].head - knee))
            thigh.append((knee - hip).length)
        ankle = sum(locals_, Vector()) / len(locals_)
        shape[lower] = {"thigh": sum(thigh) / len(thigh), "ankle": ankle,
                        "spread": max((v - ankle).length for v in locals_)}  # fmt: skip
    return shape


def solve_leg(arm, pose, leg, shape, bend_turn=0.0):
    """Turn the leg's upper and lower bones so the ankle meets the Foot bone: a two-bone solve in the plane of the
    pose's own knee, that plane turned `bend_turn` degrees about the vertical (a knee that follows a sideways step).
    A foot out of reach is pulled back along the line to the hip (`REACH_USE` of the leg) so the boot never
    stretches off the shin. Returns how far it was pulled, in armature units."""
    upper, lower, foot = leg
    apply_pose(arm, pose)
    pu, pl = arm.pose.bones[upper], arm.pose.bones[lower]
    hip, knee, target = pu.head.copy(), pl.head.copy(), arm.pose.bones[foot].head.copy()
    l1, ankle = shape["thigh"], shape["ankle"]
    l2 = ankle.length
    to = target - hip
    reach = (l1 + l2) * REACH_USE
    miss = max(0.0, to.length - reach)
    dist = min(to.length, reach)
    d = to.normalized()
    if miss:
        pose[foot]["loc"] = arm.data.bones[foot].matrix_local.inverted() @ (hip + d * dist)  # Root holds still
    bend = (knee - hip) - d * (knee - hip).dot(d)  # the knee's side of the hip-foot line
    if bend_turn:
        bend = Quaternion(up_axis(arm), math.radians(bend_turn)) @ bend
        bend -= d * bend.dot(d)
    bend.normalize()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    new_knee = hip + d * a + bend * math.sqrt(max(l1 * l1 - a * a, 0.0))
    r1 = (knee - hip).rotation_difference(new_knee - hip).to_matrix()
    mu_new = r1 @ pu.matrix.to_3x3()
    ml_turned = r1 @ pl.matrix.to_3x3()
    r2 = (ml_turned @ ankle).rotation_difference(hip + d * dist - new_knee).to_matrix()
    ml_new = r2 @ ml_turned
    # Back to each bone's own rotation: posed = parent_posed @ (parent_rest^-1 @ rest) @ local.
    bu, bl = arm.data.bones[upper], arm.data.bones[lower]
    rest_u = (bu.parent.matrix_local.inverted() @ bu.matrix_local).to_3x3()
    rest_l = (bu.matrix_local.inverted() @ bl.matrix_local).to_3x3()
    pose[upper]["rot"] = ((pu.parent.matrix.to_3x3() @ rest_u).inverted() @ mu_new).to_quaternion()
    pose[lower]["rot"] = ((mu_new @ rest_l).inverted() @ ml_new).to_quaternion()
    return miss


def contact(path, n, planted=0.2, step=0.01):
    """A foot's contact in a kit clip: (touchdown, lift-off, ground height, planted height). `path(t)` is the foot's
    world position at frame `t`; the contact is where its height is within `planted` of its lift above its lowest
    point, around its lowest frame (the planted share the ground-speed measure uses)."""
    zs = [path(i * step).z for i in range(round(n / step))]
    low, high = min(zs), max(zs)
    limit = low + (high - low) * planted
    mid = zs.index(low) * step
    t_on = mid
    while path(t_on % n).z <= limit:
        t_on -= step
    t_off = mid
    while path(t_off % n).z <= limit:
        t_off += step
    return t_on + step, t_off - step, low, limit


def sweep_plan(path, n, per_frame, length=1.0):
    """How a foot that followed `path` (a kit clip's foot, walking toward world -Y) sweeps the ground instead: its
    kit contact, `length` times as long, crossed at a steady `per_frame` (metres a frame). Positions in the plan are
    offsets along the walk (+ backward) from the contact's centre."""
    on, off, low, limit = contact(path, n)
    ky_on, ky_off = path(on % n).y, path(off % n).y
    centre = (ky_on + ky_off) / 2
    half = (ky_off - ky_on) / 2 * length
    return {"kit": (on, off, low, limit), "ky": (ky_on, ky_off), "centre": centre, "half": half,
            "frames": 2 * half / per_frame, "mid": (on + off) / 2, "x": path(0).x}  # fmt: skip


def swept_foot(path, n, t, plan, lift=1.0, ease=0.15, arc=0.0, arc_height=0.0):
    """A foot at frame `t` of the new clip: (offset along the walk from the contact's centre, + backward; height above
    the ground; the kit frame to read its rotation at). In contact it crosses the plan's length at a steady speed;
    out of it the kit's swing is replayed in the rest of the cycle, stretched to the contact's ends and lifted `lift`
    times as high. Within `ease` of either end of the swing it comes onto the sweep's line and down to the ground,
    so it touches down and lifts off already moving at ground speed. `arc` (0 to 1) blends the kit's lift toward an
    even arc `arc_height` high at mid-swing: the kit's high back-kick only suits running forward."""
    on, off, low, limit = plan["kit"]
    ky_on, ky_off = plan["ky"]
    half, frames, mid = plan["half"], plan["frames"], plan["mid"]
    u = (t - mid + n / 2) % n - n / 2  # frames from mid-contact, -n/2..n/2
    if abs(u) <= frames / 2:
        k = (u + frames / 2) / frames
        return -half + 2 * half * k, 0.0, on + (off - on) * k
    swing = (u - frames / 2) % n / (n - frames)  # 0 at lift-off, 1 at touchdown
    kit_t = off + (on + n - off) * swing
    p = path(kit_t % n)
    along = half - (p.y - ky_off) / (ky_on - ky_off) * 2 * half
    w = max(0.0, 1.0 - min(swing, 1.0 - swing) / ease)
    along += w * (-half + 2 * half * (u + frames / 2) / frames - along)
    height = lift * (p.z - low) - w * lift * (limit - low)
    height += arc * (arc_height * math.sin(math.pi * swing) - height)
    return along, max(height, 0.0), kit_t % n


def measure_gait(arm, action, scale=1.0, hz=60, planted=0.2, settle=0.5, seconds=5.0):
    """The ground speed (m/s at `scale` times kit size) a clip's planted feet cover at its authored rate, as the
    game's tests measure it (Deadnight docs/research/zombie-gait.md): from `settle` seconds in, `seconds` of the feet
    sampled at `hz`, linearly between frames; a foot is planted within `planted` of its own lift from its lowest
    point; the median over both feet of its speed along the ground, in any direction."""
    n = int(action.frame_range[1])
    ad = arm.animation_data
    for t in ad.nla_tracks:
        t.mute = True
    ad.action = action
    if hasattr(ad, "action_slot") and action.slots:
        ad.action_slot = action.slots[0]
    track = {foot: [] for _u, _l, foot in LEGS}
    fps = bpy.context.scene.render.fps
    for f in range(n + 1):
        bpy.context.scene.frame_set(f)
        for foot, points in track.items():
            points.append(arm.matrix_world @ arm.pose.bones[foot].head * scale)
    ad.action = None
    speeds, step = [], 1 / hz
    for pts in track.values():
        samples = []
        for i in range(round(seconds * hz) + 1):
            t = ((settle + i * step) * fps) % n
            k = int(t)
            samples.append(pts[k].lerp(pts[k + 1], t - k))
        low, high = min(p.z for p in samples), max(p.z for p in samples)
        limit = low + (high - low) * planted
        for a, b in itertools.pairwise(samples):
            if a.z <= limit and b.z <= limit:
                speeds.append(math.hypot(b.x - a.x, b.y - a.y) / step)
    speeds.sort()
    return speeds[len(speeds) // 2]


def turned_about_up(arm, bone, rot, degrees):
    """`rot` (a bone's local rotation, its parent at rest) turned `degrees` about the world vertical."""
    rest = arm.data.bones[bone].matrix_local.to_3x3()
    turn = Quaternion(up_axis(arm), math.radians(degrees)).to_matrix()
    return (rest.inverted() @ turn @ rest @ rot.to_matrix()).to_quaternion()
