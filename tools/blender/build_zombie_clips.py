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


def solve_leg(arm, pose, upper, lower, foot, shape):
    """Turn `upper` and `lower` so the ankle meets the Foot bone (a two-bone solve in the plane of the kit's knee). A
    foot out of the leg's reach is pulled back along the line to the hip until it is in reach (`REACH_USE` of the
    leg), so the boot never stretches away from the shin. Returns how far it was pulled (kit metres)."""
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
    bend = (knee - hip) - d * (knee - hip).dot(d)  # the kit knee's side of the hip-foot line
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
    miss, shape = sprint(arm, acts["Run"], every)
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
    return [TEAR, SPRINT, CRAWL_ATTACK, *(["Probe"] if probe else [])]


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
