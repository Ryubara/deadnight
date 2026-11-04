"""Clips the zombie kit lacks, authored on the shared zombie rig into a file of their own (Deadnight #221).

Run with the pinned Blender, headless:

    blender -b --factory-startup -P tools/blender/build_zombie_clips.py -- \
        --zombie <workspace>/refs/polypizza/VlXjG0N8Eg/model.glb \
        --out game/assets/characters/zombies/clips

Writes `zombie_clips.glb` (the kit zombie's 50-bone skeleton, the kit mesh for previews, and only the clips built
here) and `clips.json` beside it (frames, events). The game adds these clips to the zombies' shared AnimationLibrary
(`ZombieRig`): same rig and track paths as every variant, so the variant files are not rebuilt.

The poses start from the kit's own: `Idle` frame 0 with the Walk's arms-forward stance filled in (build_zombies'
clean-up). Offsets are local Euler rotations in degrees per bone; the arm axes are the boss's measured ones
(build_boss.py `arms`): UpperArm X raises the hand up and in, Z spreads it (mirrored on the right), LowerArm X bends
the elbow. On the spine X pitches forward, Y yaws (the chest turns), Z rolls.
"""

import argparse
import itertools
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_zombies as bz
import soldier_clips as sc

# Tear_Boards: one board's work, looped while the zombie stands at the boards. The rules tear a board when a zombie's
# work reaches `seconds_per_board` (1.2 s for a walker, less by `barrier_speed`); the game plays the clip faster or
# slower so that `yank` lands on that moment (docs/design/zombies.md, "Tearing boards").
TEAR = "Tear_Boards"
TEAR_EVENTS = {"reach": 0, "grab": 9, "yank": 22, "end": 29}

# Sprint (Deadnight #278): the fastest dead's gait. Built from the kit Run frame by frame on the Run's own timing (16
# frames), so the two clips stay in step and the game blends them linearly by speed (ZombieRig). The kit Run already
# plants its feet as far as these short legs reach (thigh 0.24 m and shin 0.26 m at kit scale, hips 0.4 m up), so the
# sprint keeps the kit's contact length and shortens the contact instead: each foot (the IK targets `Foot.L/R`, which
# the boots are weighted to) sweeps back along the ground at one steady speed, `SPRINT_SPEED`, and the kit's swing
# path is replayed in the rest of the cycle with a higher kick. A steady sweep also makes the ground speed well
# defined: the kit's planted foot barely moves at touchdown and then sweeps fast, so its median foot speed jumps
# with small changes (the Run reads 4.4 in Godot, 5.7 in Blender). The hips drop, the legs are solved to meet the
# feet, the trunk leans in and the arms pump wider with more bend. `measure_gait` reads it back the way
# docs/research/zombie-gait.md measures the Run.
SPRINT = "Sprint"
SPRINT_SPEED = 7.0  # m/s at the walker's size (GAIT_SCALE): the planted foot's sweep
SPRINT_STRIDE = 1.0  # the contact length along the walk, times the kit Run's (0.6 m at kit scale)
SPRINT_LIFT = 1.25  # the foot's height above its lowest point, times the Run's (a higher back kick)
SWING_EASE = 0.15  # share of the swing at each end over which the foot comes down to the ground
SPRINT_DROP = 0.05  # metres (kit scale) the hips sit lower
SPRINT_ARMS = 1.6  # the arm swing (Shoulder, UpperArm, LowerArm) about its cycle mean, times the Run's
SPRINT_ELBOW = 18  # degrees more elbow bend (LowerArm X)
# The lean (local Euler degrees; X pitches forward on Body and the spine, measured): the head comes back up to look
# ahead.
SPRINT_LEAN = {"Body": (6, 0, 0), "Abdomen": (9, 0, 0), "Torso": (7, 0, 0), "Neck": (-9, 0, 0), "Head": (-10, 0, 0)}
# Crawl_Attack (Deadnight #971): a crawler's own attack, a lunge and a grab at the ankles, made from the kit Crawl's
# own frame 0 (both hands planted ahead of the head) so the body never leaves the ground: the chest lifts on the left
# arm to coil (the telegraph), the whole body throws forward on its hands and the right arm sweeps low across the
# floor, closes on the ankles (`strike`: the blow lands here, the game plays the clip at the pace that puts this frame
# on the type's `telegraph_seconds`), drags back, and settles into the crawl's first frame. The highest part of the body
# stays inside the Crawl's own envelope (docs/design/zombies.md, "The crawler's attack").
CRAWL_ATTACK = "Crawl_Attack"
CLAW = {"Index": (35, 45), "Middle": (35, 45), "Pinky": (30, 40)}  # degrees of curl at each finger bone
CRAWL_ATTACK_EVENTS = {"gather": 0, "coil": 8, "strike": 13, "grab": 16, "end": 30}
# Crawl_Stagger and Crawl_Death (Deadnight #1000): a crawler's flinch when a shot hits it and its fall when it dies,
# from the Crawl's first frame like the attack, so neither stands the body up as the walker's HitReact (1.66 m
# against the crawl's 0.85) and Death (1.81 m) did. The flinch jerks the body back on its planted hands and snaps
# the head; it is as long as the type's stagger (the game plays it from the start of each stagger). The fall lets the
# arms go and drops the chest and head to the floor, and the last frame is held while it lies.
CRAWL_STAGGER = "Crawl_Stagger"
CRAWL_STAGGER_EVENTS = {"hit": 0, "recoil": 3, "recover": 7, "end": 10}
CRAWL_DEATH = "Crawl_Death"
CRAWL_DEATH_EVENTS = {"buckle": 4, "drop": 9, "settle": 15, "end": 20}
# Climb_Sill and Crawl_Climb (Deadnight #991): the dead going over a window's sill, for a body that stands and for one
# that crawls. The simulation carries the zombie's origin along a lift (`ZombieGate.lift_at`): up on a ramp, along at
# the sill's height over the wall and its body's clearance, down on a ramp; the clip's frames are places on that way,
# not times, and the view seeks them from where the snapshot says the zombie is, so the clip is right at any pace
# (docs/design/zombies.md, "Over the sill"). So a pose here is written in the window's own space, game metres at a
# walker's size: `depth` from the wall's middle (positive into the room), height over the floor, `side` to the body's
# left. Every frame puts the origin on its place of the lift and takes it off the targets: the hands and the feet stay
# where they were put on the sill and the floor, whatever the lift does under them. The thickest wall is the one
# written (the field's 0.56 m frame): a thinner one only brings the far face nearer, and leaves more room.
CLIMB = "Climb_Sill"
CRAWL_CLIMB = "Crawl_Climb"
# Every window on both maps (test_zombie_climb_clip.gd reads them); a sill of another height needs a new clip.
SILL = 0.9
WALL = 0.56
HELD = WALL / 2 + 0.4  # ZombieGate.BODY_CLEARANCE: the lift is the whole sill out to here on each side
RAMP = 0.4  # ZombieGate.CLIMB_RAMP
CLIMB_RISE, CLIMB_OVER, CLIMB_FRAMES = 8, 36, 44  # the frames that end the way up and the way along, and the last
CLIMB_EVENTS = {"rise": 0, "over": CLIMB_RISE, "down": CLIMB_OVER, "end": CLIMB_FRAMES}
STANCE = 0.03  # a planted foot's bone over the ground (Idle's, at a walker's size)
GRIP = 0.96  # the knuckles' height on the sill
# The way of a body that stands, in the window's space. `pelvis` (depth, height) moves on through its keys; `lean` is the
# whole body's pitch forward (Body), `bend` the spine's (Abdomen and Torso each) and `look` the neck and head coming back
# up to look ahead; hands and feet (depth, height, side) stop at their keys, holding between two keys that are the same.
CLIMB_POSE = {
    "pelvis": [(0, (-1.267, 0.50)), (4, (-1.04, 0.45)), (8, (-0.84, 0.52)), (13, (-0.60, 0.84)), (18, (-0.30, 1.14)),
               (24, (0.02, 1.24)), (29, (0.24, 1.16)), (33, (0.46, 0.92)), (37, (0.62, 0.58)), (40, (0.72, 0.42)),
               (44, (0.893, 0.50))],
    "lean": [(0, 0), (4, 6), (8, 10), (13, 22), (18, 36), (24, 42), (29, 38), (33, 28), (37, 18), (40, 14), (44, 0)],
    "bend": [(0, 0), (4, 4), (8, 6), (13, 12), (18, 18), (24, 16), (29, 14), (33, 12), (37, 10), (40, 10), (44, 0)],
    "look": [(0, 0), (4, -14), (8, -26), (13, -32), (18, -32), (29, -28), (37, -14), (44, 0)],
    "foot_L": [(0, (-1.22, STANCE, 0.19)), (2, (-1.22, STANCE, 0.19)), (7, (-0.68, STANCE, 0.19)),
               (9, (-0.68, STANCE, 0.19)), (12, (-0.62, 0.45, 0.24)), (15, (-0.52, 1.04, 0.26)),
               (18, (-0.16, 0.95, 0.24)), (21, (-0.16, 0.95, 0.24)), (25, (0.14, 0.95, 0.24)),
               (27, (0.16, 0.95, 0.24)), (29, (0.46, 0.98, 0.22)), (31, (0.56, 0.72, 0.2)), (33, (0.62, 0.42, 0.2)),
               (37, (0.66, STANCE, 0.19)),
               (40, (0.66, STANCE, 0.19)), (44, (0.96, STANCE, 0.19))],
    "foot_R": [(0, (-1.34, STANCE, -0.19)), (4, (-1.34, STANCE, -0.19)), (9, (-0.90, STANCE, -0.19)),
               (10, (-0.90, STANCE, -0.19)), (14, (-0.58, 0.40, -0.2)), (18, (-0.56, 0.70, -0.22)),
               (21, (-0.46, 1.04, -0.24)), (24, (-0.12, 0.95, -0.24)), (29, (-0.12, 0.95, -0.24)),
               (32, (0.20, 0.95, -0.22)), (35, (0.40, 0.97, -0.2)), (37, (0.50, 0.60, -0.2)),
               (39, (0.58, STANCE, -0.19)),
               (41, (0.58, STANCE, -0.19)), (44, (0.82, STANCE, -0.19))],
    "hand_L": [(0, (-0.734, 0.78, 0.39)), (6, (-0.22, GRIP, 0.27)), (15, (-0.22, GRIP, 0.27)), (19, (0.10, GRIP, 0.27)),
               (24, (0.10, GRIP, 0.27)), (26, (0.22, GRIP, 0.27)), (29, (0.22, GRIP, 0.27)), (31, (0.44, 1.02, 0.3)), (33, (0.72, 0.68, 0.33)),
               (38, (1.0, 0.62, 0.37)), (44, (1.426, 0.78, 0.39))],
    "hand_R": [(0, (-0.734, 0.8, -0.43)), (7, (-0.22, GRIP, -0.27)), (18, (-0.22, GRIP, -0.27)), (22, (0.12, GRIP, -0.27)),
               (26, (0.12, GRIP, -0.27)), (28, (0.22, GRIP, -0.27)), (30, (0.22, GRIP, -0.27)),
               (32, (0.44, 1.02, -0.3)), (34, (0.72, 0.66, -0.35)), (39, (1.0, 0.62, -0.39)), (44, (1.426, 0.8, -0.43))],
}  # fmt: skip
# The way of a body that crawls: from the Crawl's first frame the chest rears up the wall, the hands take the sill and
# pull, the belly goes over it with the legs dragging after it, and it comes down head first onto its hands, back to
# the Crawl's first frame. `lean` is the chest's pitch against the crawl's (negative rears up).
CRAWL_CLIMB_POSE = {
    "pelvis": [(0, (-1.25, 0.19)), (4, (-1.10, 0.24)), (8, (-0.82, 0.42)), (13, (-0.60, 0.74)), (18, (-0.30, 1.13)),
               (24, (0.02, 1.25)), (29, (0.25, 1.19)), (33, (0.48, 0.96)), (37, (0.68, 0.55)), (40, (0.80, 0.33)),
               (44, (0.91, 0.19))],
    "lean": [(0, 0), (4, -28), (8, -40), (13, -40), (18, -18), (24, 8), (29, 28), (33, 38), (37, 30), (40, 14), (44, 0)],
    "bend": [(0, 0), (8, -8), (18, 0), (29, 8), (37, 6), (44, 0)],
    "look": [(0, 0), (8, 10), (18, 4), (29, -18), (37, -14), (44, 0)],
    "foot_L": [(0, (-1.51, 0.18, 0.19)), (6, (-1.51, 0.18, 0.19)), (13, (-0.86, 0.25, 0.2)), (18, (-0.62, 0.72, 0.2)),
               (24, (-0.36, 1.1, 0.2)), (29, (-0.10, 1.14, 0.2)), (33, (0.12, 1.14, 0.2)), (37, (0.46, 1.12, 0.2)),
               (40, (0.66, 0.66, 0.2)), (44, (0.72, 0.18, 0.19))],
    "foot_R": [(0, (-1.84, 0.16, -0.28)), (5, (-1.84, 0.16, -0.28)), (8, (-1.4, 0.16, -0.26)), (13, (-0.95, 0.4, -0.24)),
               (18, (-0.70, 0.70, -0.22)), (24, (-0.42, 1.1, -0.22)), (29, (-0.18, 1.14, -0.22)),
               (33, (0.02, 1.14, -0.22)), (37, (0.40, 1.12, -0.22)), (40, (0.62, 0.66, -0.24)), (44, (0.66, 0.16, -0.28))],
    "hand_L": [(0, (-0.69, 0.015, 0.32)), (3, (-0.69, 0.015, 0.32)), (6, (-0.36, 1.08, 0.3)), (8, (-0.22, GRIP, 0.27)), (16, (-0.22, GRIP, 0.27)),
               (20, (0.20, GRIP, 0.27)), (25, (0.20, GRIP, 0.27)), (28, (0.50, 1.02, 0.3)), (30, (0.66, 0.40, 0.32)), (33, (0.78, 0.015, 0.32)),
               (38, (0.78, 0.015, 0.32)), (44, (1.47, 0.015, 0.32))],
    "hand_R": [(0, (-0.69, 0.015, -0.36)), (5, (-0.69, 0.015, -0.36)), (8, (-0.36, 1.08, -0.3)), (10, (-0.22, GRIP, -0.27)),
               (18, (-0.22, GRIP, -0.27)), (23, (0.20, GRIP, -0.27)), (27, (0.20, GRIP, -0.27)), (30, (0.50, 1.02, -0.3)),
               (33, (0.72, 0.40, -0.34)), (36, (1.0, 0.015, -0.36)), (40, (1.0, 0.015, -0.36)),
               (44, (1.47, 0.015, -0.36))],
}  # fmt: skip
# Armature space (X left, Y down, Z back: the file's world turned): the knees go up and out, the elbows out and back; a
# hand on the sill lies flat, its fingers forward and a little down. A crawler's legs hang: their knees point down.
CLIMB_POLES = {"Foot.L": Vector((0.8, -0.3, -1.0)), "Foot.R": Vector((-0.8, -0.3, -1.0)),
               "L": Vector((1.0, 0.2, 0.6)), "R": Vector((-1.0, 0.2, 0.6))}  # fmt: skip
CRAWL_CLIMB_POLES = {"Foot.L": Vector((0.5, 1.0, 0.0)), "Foot.R": Vector((-0.5, 1.0, 0.0)),
                     "L": Vector((1.0, 0.2, 0.6)), "R": Vector((-1.0, 0.2, 0.6))}  # fmt: skip
CLIMB_FLAT = Vector((0.0, 0.15, -1.0)).normalized()
GAIT_SCALE = 1.3  # the walker's size in the game (ZombieModels): the speeds below are at that size
REACH_USE = 0.97  # the furthest a foot may be from the hip, of the thigh and shin together (a knee never locks)
LEGS = (("UpperLeg.L", "LowerLeg.L", "Foot.L"), ("UpperLeg.R", "LowerLeg.R", "Foot.R"))
ARM_BONES = ("Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R")


def filled(arm, pose):
    out = {b.name: {"rot": Euler((0, 0, 0)).to_quaternion(), "loc": Vector()} for b in arm.pose.bones}
    for b, v in pose.items():
        out[b] = {"rot": v["rot"].copy(), "loc": v["loc"].copy()}
    return out


def arms(raise_=0, spread=0, elbow=0, right=None):
    """Both arms (the boss's measured axes); `right` overrides the right arm as (raise, spread, elbow)."""
    r = right or (raise_, spread, elbow)
    return {"UpperArm_L": (raise_, 0, spread), "UpperArm_R": (r[0], 0, -r[1]),
            "LowerArm_L": (elbow, 0, 0), "LowerArm_R": (r[2], 0, 0)}  # fmt: skip


def mean_rotation(qs):
    """The normalised average of a bone's rotations over a cycle (signs aligned with the first)."""
    acc = Quaternion((0, 0, 0, 0))
    for q in qs:
        acc += q if q.dot(qs[0]) >= 0 else -q
    return acc.normalized()


def scaled_turn(mean, q, k):
    """`q` as a turn away from `mean`, `k` times as far (same axis)."""
    d = mean.inverted() @ q
    if d.w < 0:
        d.negate()
    axis, angle = d.to_axis_angle()
    return mean @ Quaternion(axis, angle * k)


def apply_pose(arm, pose):
    """Put `pose` on the pose bones and evaluate (no action, NLA muted: the clean-up leaves every clip on a track,
    and an unmuted track overrides the pose bones), to read the posed bone matrices."""
    ad = arm.animation_data
    ad.action = None
    for t in ad.nla_tracks:
        t.mute = True
    for b, v in pose.items():
        pb = arm.pose.bones[b]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = v["rot"]
        pb.location = v["loc"]
    bpy.context.view_layer.update()


def leg_shape(arm, run_poses):
    """The kit Run's leg geometry: thigh length, and the ankle (the Foot bone's head) in the lower leg's frame.
    Measured, not taken from the bones: the imported bones' tails are arbitrary (every leg bone is 0.518 long), which
    is also why Blender's IK constraint cannot solve these legs."""
    shape = {}
    for upper, lower, foot in LEGS:
        thigh, ankle, spread = [], Vector(), []
        for pose in run_poses:
            apply_pose(arm, pose)
            hip, knee = arm.pose.bones[upper].head, arm.pose.bones[lower].head
            local = arm.pose.bones[lower].matrix.to_3x3().inverted() @ (arm.pose.bones[foot].head - knee)
            thigh.append((knee - hip).length)
            ankle += local
            spread.append(local)
        ankle /= len(run_poses)
        shape[lower] = {"thigh": sum(thigh) / len(thigh), "ankle": ankle,
                        "ankle_spread": max((v - ankle).length for v in spread)}  # fmt: skip
    return shape


def two_bones(arm, pose, upper, lower, goal, shape, pole=None):
    """Turn `upper` and `lower` so the end of the limb (`shape["ankle"]`, in the lower bone's frame) reaches `goal`, in
    the armature's space, in the plane of the kit's joint or toward `pole`, a direction in the armature's space. A goal
    out of reach is pulled back along the line to the limb's root until it is in reach (`REACH_USE` of the limb).
    Returns how far it was pulled (kit metres) and the point it was pulled to. `pose` is on the bones already."""
    pu, pl = arm.pose.bones[upper], arm.pose.bones[lower]
    hip, knee = pu.head.copy(), pl.head.copy()
    l1, ankle = shape["thigh"], shape["ankle"]
    l2 = ankle.length
    to = goal - hip
    reach = (l1 + l2) * REACH_USE
    miss = max(0.0, to.length - reach)
    dist = min(to.length, reach)
    d = to.normalized()
    side = (knee - hip) if pole is None else pole  # the kit knee's side of the hip-foot line, or the one asked for
    bend = side - d * side.dot(d)
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
    return miss, hip + d * dist


def solve_leg(arm, pose, upper, lower, foot, shape, pole=None):
    """Turn `upper` and `lower` so the ankle meets the Foot bone (`two_bones`). A foot out of the leg's reach is pulled
    back along the line to the hip, so the boot never stretches away from the shin. Returns how far it was pulled (kit
    metres)."""
    apply_pose(arm, pose)
    miss, reached = two_bones(arm, pose, upper, lower, arm.pose.bones[foot].head.copy(), shape, pole)
    if miss:
        pose[foot]["loc"] = arm.data.bones[foot].matrix_local.inverted() @ reached  # Root holds still
    return miss


def contact(path, n, planted=0.2, step=0.01):
    """A foot's contact on the kit clip: (touchdown, lift-off) times around its lowest frame, where its height crosses
    `planted` of its lift (the measure's planted share), and that height. `path(t)` is the foot's world position."""
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


def foot_path(path, n, t, plan):
    """Where a sprinting foot is at frame `t` (world, kit scale) and the kit time its rotation is read at: the kit's
    contact span swept at a steady speed in `plan["frames"]`, and the kit's swing replayed in the rest of the cycle,
    stretched to the new contact's ends and lifted `SPRINT_LIFT` times as high."""
    on, off, low, limit = plan["kit"]
    y_on, y_off, frames, mid = plan["y_on"], plan["y_off"], plan["frames"], plan["mid"]
    u = (t - mid + n / 2) % n - n / 2  # frames from mid-contact, -n/2..n/2
    if abs(u) <= frames / 2:
        k = (u + frames / 2) / frames
        return Vector((plan["x"], y_on + (y_off - y_on) * k, low)), on + (off - on) * k
    swing = (u - frames / 2) % n / (n - frames)  # 0 at lift-off, 1 at touchdown
    kit_t = off + (on + n - off) * swing
    p = path(kit_t % n)
    ky_on, ky_off = plan["ky_on"], plan["ky_off"]
    y = y_off + (p.y - ky_off) / (ky_on - ky_off) * (y_on - y_off)
    # Within SWING_EASE of either end the foot comes onto the sweep's line: it touches down and lifts off already
    # moving back at ground speed, and the kit's planted height is taken off, so it meets the ground where the sweep
    # starts and ends. Elsewhere it is lifted as the kit lifts it, times SPRINT_LIFT.
    ease = max(0.0, 1.0 - min(swing, 1.0 - swing) / SWING_EASE)
    y += ease * (y_on + (y_off - y_on) * (u + frames / 2) / frames - y)
    z = low + SPRINT_LIFT * (p.z - low) - ease * SPRINT_LIFT * (limit - low)
    return Vector((plan["x"], y, max(z, low))), kit_t % n


def sprint(arm, run, every):
    """The Sprint clip from the kit Run (see SPRINT above); returns (largest reach miss, leg shape), kit metres."""
    n = int(run.frame_range[1])
    base = [filled(arm, sc.sample(run, f)) for f in range(n + 1)]
    shape = leg_shape(arm, base)
    mw = arm.matrix_world
    per_frame = SPRINT_SPEED / GAIT_SCALE / sc.FPS  # kit metres a frame
    plans = {}
    for _u, _l, foot in LEGS:
        rest = mw @ arm.data.bones[foot].matrix_local

        def path(t, rest=rest, foot=foot):
            return rest @ sc.sample(run, t)[foot]["loc"]

        on, off, low, limit = contact(path, n)
        ky_on, ky_off = path(on % n).y, path(off % n).y
        centre, half = (ky_on + ky_off) / 2, (ky_off - ky_on) / 2 * SPRINT_STRIDE
        plans[foot] = {"rest": rest, "path": path, "kit": (on, off, low, limit), "ky_on": ky_on, "ky_off": ky_off,
                       "y_on": centre - half, "y_off": centre + half, "frames": 2 * half / per_frame,
                       "mid": (on + off) / 2, "x": path(0).x}  # fmt: skip
    means = {b: mean_rotation([p[b]["rot"] for p in base[:-1]]) for b in ARM_BONES}
    keys, worst = [], 0.0  # worst: the furthest a foot was pulled back into reach
    for f in range(n + 1):
        pose = sc.offset(base[f], **{k.replace(".", "_"): v for k, v in SPRINT_LEAN.items()})
        for b in ARM_BONES:
            pose[b]["rot"] = scaled_turn(means[b], base[f][b]["rot"], SPRINT_ARMS)
        pose = sc.offset(pose, LowerArm_L=(SPRINT_ELBOW, 0, 0), LowerArm_R=(SPRINT_ELBOW, 0, 0))
        pose["Body"]["loc"] = pose["Body"]["loc"] + Vector((0, 0, SPRINT_DROP))  # Body's local +Z is down
        for _u, _l, foot in LEGS:
            plan = plans[foot]
            at, kit_t = foot_path(plan["path"], n, f % n, plan)
            pose[foot] = {"rot": sc.sample(run, kit_t)[foot]["rot"], "loc": plan["rest"].inverted() @ at}
        for upper, lower, foot in LEGS:
            worst = max(worst, solve_leg(arm, pose, upper, lower, foot, shape[lower]))
        keys.append((f, pose))
    events = {f"step_{side}": round(plans[foot]["mid"] - plans[foot]["frames"] / 2) % n
              for side, (_u, _l, foot) in (("left", LEGS[0]), ("right", LEGS[1]))}  # fmt: skip
    print("SPRINT_CONTACT", {f: (round(p["frames"], 2), round(p["mid"], 2)) for f, p in plans.items()})
    sc.write(arm, SPRINT, keys, every, "full", True, events=dict(sorted(events.items(), key=lambda kv: kv[1])))
    return worst, shape


def hand_at(arm, pose, side):
    """Where the hand (the Index1 bone's head, the knuckles) is in the file's world, kit metres."""
    apply_pose(arm, pose)
    return arm.matrix_world @ arm.pose.bones[f"Index1.{side}"].head


def aim_hand(arm, pose, side, target, upper=(0, 0, 0), lower=0.0):
    """`pose` with the `side` arm turned (UpperArm in three axes, LowerArm bending the elbow) so that the hand is at
    `target` (the file's world, kit metres), found by a coordinate descent on the angles (degrees) from `upper` and
    `lower`, with a pull toward them so that the arm does not wind itself up. Returns the pose."""
    x = {"UpperArm": list(upper), "LowerArm": [lower, 0, 0]}
    start = {b: list(v) for b, v in x.items()}

    def posed(a):
        return sc.offset(pose, **{f"UpperArm_{side}": tuple(a["UpperArm"]), f"LowerArm_{side}": tuple(a["LowerArm"])})

    def cost(a):
        miss = (hand_at(arm, posed(a), side) - Vector(target)).length
        pull = sum((a[b][i] - start[b][i]) ** 2 for b in a for i in range(3)) * 1e-6
        return miss + pull

    best = cost(x)
    for step in (24, 12, 6, 3, 1.5, 0.75):
        improved = True
        while improved:
            improved = False
            for b, idx in (("UpperArm", 0), ("UpperArm", 1), ("UpperArm", 2), ("LowerArm", 0)):
                for d in (step, -step):
                    x[b][idx] += d
                    c = cost(x)
                    if c < best - 1e-5:
                        best, improved = c, True
                    else:
                        x[b][idx] -= d
    return posed(x)


def crawl_attack(arm, acts, every):
    """The crawler's attack from the kit Crawl's first frame (see CRAWL_ATTACK above). Body's local Y is forward (the
    body moves along -Y in the file) and Z down; on the spine X pitches the chest down (negative lifts it)."""
    base = filled(arm, sc.sample(acts["Crawl"], 0))

    def moved(pose, forward=0.0, down=0.0, side=0.0, **bones):
        out = sc.offset(pose, **bones)
        out["Body"]["loc"] = out["Body"]["loc"] + Vector((side, forward, down))
        return out

    def claw(k):
        """The right hand's fingers closing (local Z curls them toward the palm), `k` of the way."""
        return {f"{b}{i}_R": (0, 0, deg * k) for b, degs in CLAW.items() for i, deg in enumerate(degs, 1)}

    f = CRAWL_ATTACK_EVENTS

    def reaching(pose, side, target, **kw):
        return aim_hand(arm, pose, side, target, **kw)

    # The left hand stays on the floor where the crawl's first frame has it, pulling the body over it.
    planted = hand_at(arm, base, "L")
    gather = moved(base, forward=-0.05, Abdomen=(-4, 0, 0), Torso=(-4, 0, 0), Neck=(3, 0, 0))
    gather = reaching(gather, "R", Vector((-0.50, -0.38, 0.30)))
    coil = moved(base, forward=-0.14, Abdomen=(-3, -6, 0), Torso=(-2, -6, 0), Neck=(2, 4, 0))
    coil = reaching(coil, "R", Vector((-0.52, -0.10, 0.27)), upper=(18, 0, 0), lower=40)
    coil = reaching(coil, "L", planted + Vector((0.0, 0.04, 0.0)))
    coil2 = moved(coil, forward=-0.02, Abdomen=(-1, -1, 0))
    coil2 = reaching(coil2, "L", planted + Vector((0.0, 0.06, 0.0)))
    strike = moved(base, forward=0.46, down=-0.02, Abdomen=(2, 14, 0), Torso=(2, 12, 0), Neck=(-6, -8, 0))
    strike = reaching(strike, "R", Vector((-0.22, -1.05, 0.05)), upper=(-30, 0, 0), lower=-20)
    strike = reaching(strike, "L", planted + Vector((0.0, -0.30, 0.12)))
    grab = moved(strike, forward=-0.08, Abdomen=(-1, 3, 0))
    grab = reaching(grab, "R", Vector((-0.12, -0.96, 0.05)), upper=(-30, 0, 0), lower=-20)
    grab = reaching(grab, "L", planted + Vector((0.0, -0.2, 0.12)))
    grab = sc.offset(grab, **claw(1.0))
    drag = moved(base, forward=-0.02, Abdomen=(2, 4, 0))
    drag = reaching(drag, "R", Vector((-0.20, -0.62, 0.05)), upper=(-10, 0, 0), lower=10)
    drag = sc.offset(drag, **claw(0.8))
    strike = sc.offset(strike, **claw(0.2))
    keys = [(0, base), (4, gather), (f["coil"], coil), (10, coil2), (f["strike"], strike),
            (f["grab"], grab), (22, drag), (f["end"], base)]  # fmt: skip
    sc.write(arm, CRAWL_ATTACK, keys, every, "full", False, events=dict(f))


def crawl_stagger(arm, acts, every):
    """The crawler's flinch (see CRAWL_STAGGER above): the Crawl's first frame, both hands planted; a shot throws the
    body back along the floor, the chest twists and lifts a little, the head snaps, then it settles on its hands."""
    base = filled(arm, sc.sample(acts["Crawl"], 0))
    left, right = hand_at(arm, base, "L"), hand_at(arm, base, "R")

    def moved(pose, forward=0.0, down=0.0, **bones):
        out = sc.offset(pose, **bones)
        out["Body"]["loc"] = out["Body"]["loc"] + Vector((0.0, forward, down))
        return out

    f = CRAWL_STAGGER_EVENTS
    recoil = moved(base, forward=-0.24, Abdomen=(-12, 16, 0), Torso=(-9, 12, 0), Neck=(-14, -14, 0), Head=(-16, -8, 0))
    recoil = aim_hand(arm, recoil, "L", left + Vector((0.0, 0.10, 0.02)))
    recoil = aim_hand(arm, recoil, "R", right + Vector((0.0, 0.10, 0.02)))
    after = moved(base, forward=-0.08, Abdomen=(-4, 6, 0), Torso=(-3, 4, 0), Neck=(-5, -5, 0), Head=(-6, -3, 0))
    after = aim_hand(arm, after, "L", left + Vector((0.0, 0.04, 0.0)))
    after = aim_hand(arm, after, "R", right + Vector((0.0, 0.04, 0.0)))
    keys = [(0, base), (f["recoil"], recoil), (f["recover"], after), (f["end"], base)]
    sc.write(arm, CRAWL_STAGGER, keys, every, "full", False, events=dict(f))


def crawl_death(arm, acts, every):
    """The crawler's fall (see CRAWL_DEATH above): the arms buckle, the chest and then the head drop to the floor, the
    body slides a little forward and lies still."""
    base = filled(arm, sc.sample(acts["Crawl"], 0))
    left, right = hand_at(arm, base, "L"), hand_at(arm, base, "R")

    def moved(pose, forward=0.0, down=0.0, **bones):
        out = sc.offset(pose, **bones)
        out["Body"]["loc"] = out["Body"]["loc"] + Vector((0.0, forward, down))
        return out

    f = CRAWL_DEATH_EVENTS
    buckle = moved(base, forward=-0.04, Abdomen=(-4, 6, 0), Torso=(-3, 5, 0), Neck=(6, -6, 0), Head=(8, -4, 0))
    buckle = aim_hand(arm, buckle, "L", left + Vector((0.0, 0.02, 0.0)))
    buckle = aim_hand(arm, buckle, "R", right + Vector((0.0, 0.02, 0.0)))
    drop = moved(base, forward=0.06, down=-0.0, Abdomen=(10, 8, 0), Torso=(8, 6, 0), Neck=(12, -6, 0), Head=(10, -4, 0))
    drop = aim_hand(arm, drop, "L", left + Vector((0.12, -0.1, 0.0)))
    drop = aim_hand(arm, drop, "R", right + Vector((-0.12, -0.2, 0.0)))
    lie = moved(drop, forward=0.10, Abdomen=(2, 0, 0), Torso=(2, 0, 0), Neck=(2, 2, 0), Head=(2, 2, 0))
    lie = aim_hand(arm, lie, "L", left + Vector((0.16, -0.16, 0.0)))
    lie = aim_hand(arm, lie, "R", right + Vector((-0.16, -0.3, 0.0)))
    keys = [(0, base), (f["buckle"], buckle), (f["drop"], drop), (f["settle"], lie), (f["end"], lie)]
    sc.write(arm, CRAWL_DEATH, keys, every, "full", False, events=dict(f))


def climb_origin(frame):
    """Where the simulation has the zombie's origin at a frame of the climb, in the window's space: (depth, lift)
    (`ZombieGate.lift_at` for the thickest wall; the frames are even along each part of the way)."""

    def ease(t):
        return t * t * (3 - 2 * t)

    if frame <= CLIMB_RISE:
        k = frame / CLIMB_RISE
        return -HELD - RAMP * (1 - k), SILL * ease(k)
    if frame <= CLIMB_OVER:
        return -HELD + 2 * HELD * (frame - CLIMB_RISE) / (CLIMB_OVER - CLIMB_RISE), SILL
    k = (frame - CLIMB_OVER) / (CLIMB_FRAMES - CLIMB_OVER)
    return HELD + RAMP * k, SILL * (1 - ease(k))


def window_point(frame, depth, height, side=0.0):
    """A place in the window's space as the file's world has it at `frame` (kit metres, the origin at the file's)."""
    at, lift = climb_origin(frame)
    return Vector((side, -(depth - at), height - lift)) / GAIT_SCALE


def along(keys, frame, moving=False):
    """The value of a track of (frame, value) keys at `frame`: stopping at each key, or `moving` on through them (a
    cubic with the slope of the neighbouring keys)."""
    keys = [(t, Vector(v) if isinstance(v, tuple) else Vector((v, 0.0))) for t, v in keys]
    if frame <= keys[0][0]:
        return keys[0][1]
    for i in range(len(keys) - 1):
        (t0, v0), (t1, v1) = keys[i], keys[i + 1]
        if frame > t1:
            continue
        u, span = (frame - t0) / (t1 - t0), t1 - t0
        if not moving:
            return v0.lerp(v1, u * u * (3 - 2 * u))
        m0 = (v1 - keys[i - 1][1]) / (t1 - keys[i - 1][0]) * span if i > 0 else v0 * 0
        m1 = (keys[i + 2][1] - v0) / (keys[i + 2][0] - t0) * span if i + 2 < len(keys) else v0 * 0
        return ((2 * u**3 - 3 * u**2 + 1) * v0 + (u**3 - 2 * u**2 + u) * m0
                + (-2 * u**3 + 3 * u**2) * v1 + (u**3 - u**2) * m1)  # fmt: skip
    return keys[-1][1]


def pelvis_at(arm, pose):
    """The middle of the hip joints in the file's world."""
    apply_pose(arm, pose)
    left, right = arm.pose.bones["UpperLeg.L"].head, arm.pose.bones["UpperLeg.R"].head
    return arm.matrix_world @ ((left + right) / 2)


def place_pelvis(arm, pose, target):
    """Move the Body bone so the pelvis is at `target`, the file's world (its pitch has moved it: two passes)."""
    rest = arm.data.bones["Body"].matrix_local.to_3x3().inverted() @ arm.matrix_world.to_3x3().inverted()
    for _ in range(2):
        pose["Body"]["loc"] = pose["Body"]["loc"] + rest @ (target - pelvis_at(arm, pose))


def solve_arm(arm, pose, side, target, pole):
    """Turn the arm so the knuckles (Index1) are at `target`, the file's world, the elbow toward `pole` (a direction in
    the armature's space): the legs' two-bone solve with the knuckles as the ankle. Returns the miss, kit metres."""
    apply_pose(arm, pose)
    upper, lower = arm.pose.bones[f"UpperArm.{side}"], arm.pose.bones[f"LowerArm.{side}"]
    knuckle = arm.pose.bones[f"Index1.{side}"].head
    shape = {"thigh": (lower.head - upper.head).length,
             "ankle": lower.matrix.to_3x3().inverted() @ (knuckle - lower.head)}  # fmt: skip
    goal = arm.matrix_world.inverted() @ target
    return two_bones(arm, pose, upper.name, lower.name, goal, shape, pole)[0]


def lay_fingers(arm, pose, side, flat):
    """Turn the fingers of a hand so that each lies along `flat`, a direction in the armature's space (the kit's curled
    fingers and hanging thumb would go through a sill the knuckles rest on)."""
    apply_pose(arm, pose)
    for finger in ("Index", "Middle", "Pinky", "Thumb"):
        pb = arm.pose.bones[f"{finger}1.{side}"]
        now = arm.pose.bones[f"{finger}2.{side}"].head - pb.head
        turned = now.rotation_difference(flat).to_matrix() @ pb.matrix.to_3x3()
        bone = arm.data.bones[pb.name]
        rest = (bone.parent.matrix_local.inverted() @ bone.matrix_local).to_3x3()
        pose[pb.name]["rot"] = ((pb.parent.matrix.to_3x3() @ rest).inverted() @ turned).to_quaternion()


def climb_frames(arm, base, shape, table, offsets, poles):
    """The poses of a way over the sill from a table of the window's space (see CLIMB_POSE). `offsets(frame)` turns the
    body and `poles` says where the elbows and knees point. Returns keys and the worst misses of a hand and of a foot
    (metres at a walker's size)."""
    keys, hand_miss, foot_miss = [], 0.0, 0.0
    mw = arm.matrix_world
    for frame in range(CLIMB_FRAMES + 1):
        pose = sc.offset(base, **offsets(frame))
        place_pelvis(arm, pose, window_point(frame, *along(table["pelvis"], frame, moving=True)))
        for side, (upper, lower, foot) in zip(("L", "R"), LEGS, strict=True):
            depth, height, left = along(table[f"foot_{side}"], frame)
            at = window_point(frame, depth, height, left)
            pose[foot] = {
                "rot": base[foot]["rot"].copy(),
                "loc": (mw @ arm.data.bones[foot].matrix_local).inverted() @ at,
            }
            foot_miss = max(foot_miss, solve_leg(arm, pose, upper, lower, foot, shape[lower], poles[foot]))
        for side in ("L", "R"):
            depth, height, left = along(table[f"hand_{side}"], frame)
            hand_miss = max(
                hand_miss, solve_arm(arm, pose, side, window_point(frame, depth, height, left), poles[side])
            )
            if abs(height - GRIP) < 0.02 or height < 0.05:  # on the sill or on the floor
                lay_fingers(arm, pose, side, CLIMB_FLAT)
        keys.append((frame, pose))
    return keys, hand_miss * GAIT_SCALE, foot_miss * GAIT_SCALE


def climb_clip(arm, name, base, shape, table, poles, every):
    """A way over the sill from its table: the body's pitch from `lean`, `bend` (each of Abdomen and Torso) and `look`
    (half each to the neck and head), on top of `base`."""

    def offsets(frame):
        lean, bend, look = [along(table[k], frame, moving=True).x for k in ("lean", "bend", "look")]
        return {"Body": (lean, 0, 0), "Abdomen": (bend, 0, 0), "Torso": (bend, 0, 0),
                "Neck": (look * 0.5, 0, 0), "Head": (look * 0.5, 0, 0)}  # fmt: skip

    keys, hands, feet = climb_frames(arm, base, shape, table, offsets, poles)
    print("CLIMB_REACH", name, "hands", round(hands, 3), "feet", round(feet, 3))
    sc.write(arm, name, keys, every, "full", False, events=dict(CLIMB_EVENTS))


def measure_gait(arm, action, scale=GAIT_SCALE, hz=60, planted=0.2, settle=0.5, seconds=5.0):
    """The ground speed (m/s at `scale`) a clip's planted feet cover at its authored rate, as the game's test measures
    it (game/tests/zombies/test_zombie_gait.gd, docs/research/zombie-gait.md): from `settle` seconds in, `seconds`
    of the feet sampled at `hz`, linearly between frames; a foot is planted within `planted` of its own lift from its
    lowest point; the median of its backward speed over the planted samples of both feet."""
    n = int(action.frame_range[1])
    ad = arm.animation_data
    for t in ad.nla_tracks:
        t.mute = True
    ad.action = action
    if hasattr(ad, "action_slot") and action.slots:
        ad.action_slot = action.slots[0]
    track = {foot: [] for _u, _l, foot in LEGS}
    for f in range(n + 1):
        bpy.context.scene.frame_set(f)
        for foot, points in track.items():
            points.append(arm.matrix_world @ arm.pose.bones[foot].head * scale)
    ad.action = None
    speeds, step = [], 1 / hz
    for pts in track.values():
        samples = []
        for i in range(round(seconds * hz) + 1):
            t = ((settle + i * step) * sc.FPS) % n
            k = int(t)
            samples.append(pts[k].lerp(pts[k + 1], t - k))
        low, high = min(p.z for p in samples), max(p.z for p in samples)
        limit = low + (high - low) * planted
        for a, b in itertools.pairwise(samples):
            if a.z <= limit and b.z <= limit:
                speeds.append(abs(b.y - a.y) / step)
    speeds.sort()
    return speeds[len(speeds) // 2]


def build(arm, probe=False):
    sc.CLIPS.clear()
    acts = {a.name: a for a in bpy.data.actions}
    every = [b.name for b in arm.pose.bones]
    idle = filled(arm, sc.sample(acts["Idle"], 0))

    # Reach: lean in, both hands up and forward to a board at chest height. Grab: the hands close on it, elbows give.
    # Pull: lean back against it, elbows bent, straining (a small shake). Yank: the chest throws back and turns, the
    # hands come back past the shoulders (the board leaves here). Follow-through: the arms fling out and down, then
    # back to the stance the next reach starts from.
    reach = sc.offset(idle, Abdomen=(20, 0, 0), Torso=(18, 0, 0), Neck=(-14, 0, 0), Head=(-10, 0, 0),
                      **arms(14, 8, -15))  # fmt: skip
    grab = sc.offset(idle, Abdomen=(16, 0, 0), Torso=(12, 0, 0), Neck=(-10, 0, 0), Head=(-6, 0, 0),
                     **arms(10, -4, 12))  # fmt: skip
    strain = sc.offset(idle, Abdomen=(-4, 0, 0), Torso=(-8, -4, 0), Neck=(4, 0, 0), Head=(4, 0, 0),
                       **arms(-4, -6, 40))  # fmt: skip
    strain2 = sc.offset(strain, Torso=(-3, 6, 0), Head=(0, 0, 4))
    yank = sc.offset(idle, Abdomen=(-12, 14, 0), Torso=(-18, 22, 0), Neck=(8, -8, 0), Head=(6, -6, 0),
                     **arms(-20, 14, 85, right=(-35, 30, 70)))  # fmt: skip
    fling = sc.offset(idle, Abdomen=(-6, 20, 0), Torso=(-8, 26, 0), Neck=(4, -10, 0),
                      **arms(-45, 35, 30, right=(-50, 45, 20)))  # fmt: skip
    settle = sc.offset(idle, Abdomen=(6, 6, 0), Torso=(4, 8, 0), **arms(-10, 10, 10))
    f = TEAR_EVENTS
    keys = [(f["reach"], idle), (6, reach), (f["grab"], grab), (14, strain), (17, strain2), (20, strain),
            (f["yank"], yank), (25, fling), (27, settle), (f["end"], idle)]  # fmt: skip
    sc.write(arm, TEAR, keys, every, "full", True, events=dict(f))

    crawl_attack(arm, acts, every)
    crawl_stagger(arm, acts, every)
    crawl_death(arm, acts, every)
    miss, shape = sprint(arm, acts["Run"], every)
    climb_clip(arm, CLIMB, idle, shape, CLIMB_POSE, CLIMB_POLES, every)
    crawl = filled(arm, sc.sample(acts["Crawl"], 0))
    climb_clip(arm, CRAWL_CLIMB, crawl, shape, CRAWL_CLIMB_POSE, CRAWL_CLIMB_POLES, every)
    print("SPRINT_LEGS", {k: (round(v["thigh"], 3), round(v["ankle"].length, 3), round(v["ankle_spread"], 4))
                          for k, v in shape.items()}, "reach miss", round(miss, 4))  # fmt: skip
    for clip in ("Walk", "Run", SPRINT):
        speed = round(measure_gait(arm, bpy.data.actions[clip]), 2)
        print("GAIT", clip, speed)
        if clip == SPRINT:
            sc.CLIPS[SPRINT]["ground_speed"] = speed

    if probe:  # the spine and arm axes, one bone turned per frame, for reading off a sheet
        keys, n = [(0, idle)], 1
        for bone in ("Abdomen", "Torso", "UpperArm_R", "LowerArm_R"):
            for ax in range(3):
                deg = [0, 0, 0]
                deg[ax] = 40
                keys.append((n, sc.offset(idle, **{bone: tuple(deg)})))
                n += 1
        sc.write(arm, "Probe", keys, every, "full", False)
        sc.CLIPS.pop("Probe")
    return [TEAR, SPRINT, CRAWL_ATTACK, CRAWL_STAGGER, CRAWL_DEATH, CLIMB, CRAWL_CLIMB, *(["Probe"] if probe else [])]


def add_tracks(arm, names):
    ad = arm.animation_data
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for name in names:
        a = bpy.data.actions[name]
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 0, a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zombie", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--probe", action="store_true", help="add a Probe clip (one bone turned per frame)")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    args.out.mkdir(parents=True, exist_ok=True)
    arm, body, _kit = bz.clean(args.zombie)
    names = build(arm, args.probe)
    add_tracks(arm, names)
    body.name = body.data.name = "Zombie_Mesh"
    bz.export(args.out / "zombie_clips.glb", arm, [body], True)
    spec = {
        "fps": sc.FPS,
        "bones": len(arm.data.bones),
        "clips": {
            n: {k: c[k] for k in ("loop", "frames", "seconds", "events", "ground_speed") if k in c}
            for n, c in sc.CLIPS.items()
        },
    }
    (args.out / "clips.json").write_text(json.dumps(spec, indent=1) + "\n", newline="\n")
    print("ZOMBIE_CLIPS", spec)


if __name__ == "__main__":
    main()
