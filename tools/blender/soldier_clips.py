"""The Soldier's weapon clips, authored from the kit Soldier's own poses (Deadnight #42).

Not run on its own: `build_soldier.py` (export) and `render_clips.py` (contact sheets) import it. The clip list,
names, the upper/lower split and the event frames are specified in docs/design/animation.md; this file is the one
place they are built, so the doc and the clips cannot drift (`CLIPS` is also written to clips.json beside the .glb).

Every new clip is keyed from poses the kit already has, never from a blank rig:

- `Idle_Shoot` frame 0 is the kit's two-handed gun hold (right hand on the grip at Index1.R, left on the fore-end):
  the base of every gun pose. Rotating Abdomen/Torso moves both arms and the gun together, so recoil, sway and the
  melee swing are spine rotations on top of it and the hands stay on the weapon.
- `Idle` frame 0 is the lowered pose (arms down): equip and unequip slerp between it and the aim pose per bone.
- Offsets are local Euler rotations (degrees) in each bone's own axes, applied on top of the base pose.

Axes measured on the kit rig (Blender, TEMPERANCE import, probe sheet in the PR): on the spine (Abdomen, Torso, Neck)
X is pitch (positive bends forward) and Y is yaw (positive turns the chest to the Soldier's right); on the arms X
raises the arm (up toward the head), Y twists and lifts it forward; on LowerArm.R, Z tips the hand (muzzle up).

Rotations only, in bone space: the clips are independent of the 100x armature scale the clean-up applies, except the
location keys (Body and the IK feet carry them), which are written in file units and scaled with every other key.
"""

import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gaitlib as gl

FPS = 24

# The upper-body set: the bones an upper clip keys and the Godot bone filter passes. Everything above Hips.
# Abdomen is in it so aim and recoil can bend the whole spine; the legs, Hips, Body and Root stay with locomotion.
UPPER_ROOTS = ("Abdomen",)
LOWER = ("Root", "Body", "Hips", "UpperLeg.L", "LowerLeg.L", "Foot.L", "PoleTarget.L",
         "UpperLeg.R", "LowerLeg.R", "Foot.R", "PoleTarget.R")  # fmt: skip

# Weapon classes and the kit weapon (held on Index1.R in the kit file) whose hold each uses. Deadnight's own weapons
# copy these holds (game/assets/weapons/: lever rifle and double shotgun as the kit Shotgun, bat and axe as the Shovel).
CLASSES = {"Rifle": "Shotgun", "Shotgun": "Shotgun", "Pistol": "Pistol", "Melee": "Shovel"}

# name -> {layer, loop, class, events}; frames at 24 fps, events at a frame of the clip.
CLIPS = {}
# The pose the glTF file's nodes hold (arms down, fingers curled), read right after the import: see capture_static.
STATIC = {}
# name -> bones the clip does not key. The glTF exporter samples every bone of every clip whatever its keys, so
# build_soldier.py takes these channels out of the file after the export (strip_channels).
UNKEYED = {}


def capture_static(arm):
    """Record the file's static pose. Call right after the import, before any frame change or clip evaluation.

    The kit clips key only the bones they move (Idle keys 7 of 43). Every other bone sits at its glTF node transform,
    which the importer writes into the pose bones; that is not the rest pose (the rest has the arms out and the
    fingers straight). Any later evaluation overwrites it, so it is read once, here, and used to fill every pose.
    """
    STATIC.clear()
    for pb in arm.pose.bones:
        STATIC[pb.name] = {"rot": pb.rotation_quaternion.copy(), "loc": pb.location.copy()}


def fcurves(action):
    """F-curves of a layered (4.4+) or legacy action."""
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    else:
        yield from getattr(action, "fcurves", [])


def upper_bones(arm):
    out = []
    for root in UPPER_ROOTS:
        b = arm.data.bones[root]
        out += [b.name] + [c.name for c in b.children_recursive]
    return out


def sample(action, frame):
    """Pose of every keyed bone at `frame`: {bone: {"rot": Quaternion, "loc": Vector}}."""
    pose = {}
    for fc in fcurves(action):
        if not fc.data_path.startswith('pose.bones["'):
            continue
        bone = fc.data_path.split('"')[1]
        prop = fc.data_path.rsplit(".", 1)[1]
        p = pose.setdefault(bone, {"rot": [1.0, 0.0, 0.0, 0.0], "loc": [0.0, 0.0, 0.0]})
        if prop == "rotation_quaternion":
            p["rot"][fc.array_index] = fc.evaluate(frame)
        elif prop == "location":
            p["loc"][fc.array_index] = fc.evaluate(frame)
    return {b: {"rot": Quaternion(v["rot"]).normalized(), "loc": Vector(v["loc"])} for b, v in pose.items()}


def full(arm, pose):
    """Fill bones missing from a pose with the file's static pose."""
    assert STATIC, "capture_static(arm) first"
    out = {b.name: {"rot": STATIC[b.name]["rot"].copy(), "loc": STATIC[b.name]["loc"].copy()} for b in arm.pose.bones}
    for b, v in pose.items():
        out[b] = {"rot": v["rot"].copy(), "loc": v["loc"].copy()}
    return out


def offset(pose, **bones):
    """Copy of `pose` with local Euler offsets (degrees): offset(p, Torso=(x, y, z), UpperArm_R=(...))."""
    out = {b: {"rot": v["rot"].copy(), "loc": v["loc"].copy()} for b, v in pose.items()}
    for key, deg in bones.items():
        bone = key.replace("_L", ".L").replace("_R", ".R")
        e = Euler([math.radians(d) for d in deg], "XYZ").to_quaternion()
        out[bone]["rot"] = out[bone]["rot"] @ e
    return out


def blend(a, b, t):
    """Per-bone slerp/lerp from pose a to pose b."""
    out = {}
    for k in a.keys() & b.keys():
        qa, qb = a[k]["rot"], b[k]["rot"]
        if qa.dot(qb) < 0:  # the same rotation can come as q or -q (UpperArm.L is stored with w < 0)
            qb = -qb
        out[k] = {"rot": qa.slerp(qb, t), "loc": a[k]["loc"].lerp(b[k]["loc"], t)}
    return out


def bake_static(arm, action, skip=()):
    """Key every bone the action leaves out at its static pose (first and last frame), so the export samples the
    standing pose for it and not the rest pose or whatever the clip before left behind. Bones in `skip` stay unkeyed
    (the fingers of the clips that leave the hands to `HandGripPose`)."""
    keyed = {(fc.data_path.split('"')[1], fc.data_path.rsplit(".", 1)[1]) for fc in fcurves(action)}
    keyed |= {(b, prop) for b in skip for prop in ("rotation_quaternion", "location")}
    end = action.frame_range[1]
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and action.slots:
        ad.action_slot = action.slots[0]
    for pb in arm.pose.bones:
        for prop, key in (("rotation_quaternion", "rot"), ("location", "loc")):
            if (pb.name, prop) in keyed:
                continue
            pb.rotation_mode = "QUATERNION"
            setattr(pb, prop, STATIC[pb.name][key])
            for f in (0, end):
                pb.keyframe_insert(prop, frame=f, group=pb.name)
    ad.action = None


def write(arm, name, keys, bones, layer, loop, cls=None, events=None, skip=()):
    """Create action `name` keyed at `keys` [(frame, pose)] on `bones`; every other bone at the static pose, except
    the bones in `skip`, which the clip does not key at all."""
    a = bpy.data.actions.new(name)
    a.use_fake_user = True
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = a
    prev = {}
    for frame, pose in keys:
        for b in bones:
            pb = arm.pose.bones[b]
            pb.rotation_mode = "QUATERNION"
            q = pose[b]["rot"].copy()
            # Keep the sign continuous from key to key: q and -q are the same rotation, but the curves interpolate
            # each component, and a sign flip between two keys swings the arm through a wild path (the gun went
            # behind the head mid-equip before this).
            if b in prev and prev[b].dot(q) < 0:
                q.negate()
            prev[b] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=b)
            # Location too: Body bobs, and the IK feet (Foot.L/R, which the boots are weighted to) move with the
            # legs. Keying Body alone left the boots at the static place and stretched them into sticks in Walk.
            pb.location = pose[b]["loc"]
            pb.keyframe_insert("location", frame=frame, group=b)
    ad.action = None
    bake_static(arm, a, skip)
    if skip:
        UNKEYED[name] = set(skip)
    CLIPS[name] = {
        "layer": layer,
        "loop": loop,
        "class": cls,
        "frames": int(keys[-1][0]),
        "seconds": round(keys[-1][0] / FPS, 3),
        "events": events or {},
    }
    return a


def build(arm):
    """Author every new clip on `arm` (a kit Soldier armature with the kit's actions loaded); fill CLIPS."""
    CLIPS.clear()
    UNKEYED.clear()
    acts = {a.name.split("|")[-1]: a for a in bpy.data.actions}
    up = upper_bones(arm)
    every = [b.name for b in arm.pose.bones]
    idle = full(arm, sample(acts["Idle"], 0))
    idle_mid = full(arm, sample(acts["Idle"], 20))
    aim = full(arm, sample(acts["Idle_Shoot"], 0))
    # Kit clips the game uses as they are (full body): recorded in the spec with their kit names.
    for kit, layer, loop in (("Idle", "full", True), ("Run", "full", True), ("HitReact", "full", False),
                             ("Death", "full", False), ("Run_Gun", "full", True), ("Idle_Shoot", "upper", False)):  # fmt: skip
        CLIPS[kit] = {"layer": layer, "loop": loop, "class": None, "kit": True,
                      "frames": int(acts[kit].frame_range[1]), "seconds": round(acts[kit].frame_range[1] / FPS, 3),
                      "events": {}}  # fmt: skip

    # ---- Locomotion the kit Soldier lacks -------------------------------------------------------------------------
    # Walk: the kit Run at 60 % of its stride (each key slerped toward the Idle stance), stretched to 1.0 s.
    run = acts["Run"]
    n_run = int(run.frame_range[1])
    keys = []
    for i in range(n_run + 1):
        p = blend(idle, full(arm, sample(run, i)), 0.6)
        keys.append((round(i * 24 / n_run), p))
    write(arm, "Walk", keys, every, "full", True, events={"step_left": 0, "step_right": 12})

    # Downed: on the ground after Death, breathing, for the co-op revive state (loops).
    death = acts["Death"]
    last = full(arm, sample(death, death.frame_range[1]))
    keys = [(0, last), (24, offset(last, Torso=(-4, 0, 0), Neck=(-4, 0, 0))), (48, last)]
    write(arm, "Downed", keys, every, "full", True)

    # ---- Guns: Rifle and Shotgun share the kit Shotgun hold -----------------------------------------------------
    for cls, kick, reload in (("Rifle", 1.0, "lever"), ("Shotgun", 1.8, "break")):
        hold = aim
        # Aim: the gun hold with a slow 2-degree breathing sway (loops).
        keys = [(0, hold), (24, offset(hold, Abdomen=(1.5, 1, 0), Torso=(1, 0, 0))), (48, hold)]
        write(arm, f"Aim_{cls}", keys, up, "upper", True, cls)
        # Fire: muzzle up and the shoulder pushed back, then settle (one-shot). Shotgun kicks harder and longer.
        n = 8 if cls == "Rifle" else 14
        kicked = offset(hold, Abdomen=(-4 * kick, 0, 0), Torso=(-6 * kick, -2 * kick, 0), Neck=(3 * kick, 0, 0),
                        Shoulder_R=(0, 0, 4 * kick))  # fmt: skip
        keys = [(0, hold), (2, kicked), (n, hold)]
        write(arm, f"Fire_{cls}", keys, up, "upper", False, cls, {"muzzle": 0, "can_fire_again": n})
        # Reload.
        if reload == "lever":
            # Lever rifle: tip the gun right and down, left hand feeds rounds at the loading gate (three times),
            # back to aim. The lever cycle is the last stroke.
            tipped = offset(hold, Torso=(8, -10, -12), UpperArm_R=(0, 0, 10), Head=(14, 0, 0))
            feed_out = offset(tipped, UpperArm_L=(-15, 0, 0))  # hand back at the cartridge belt
            feed_in = offset(tipped, UpperArm_L=(40, 0, 0))  # hand up at the loading gate
            keys = [(0, hold), (8, tipped)]
            f = 8
            for _ in range(3):
                keys += [(f + 6, feed_out), (f + 12, feed_in)]
                f += 12
            lever = offset(hold, LowerArm_R=(0, 0, -25), Torso=(-3, 0, 0))
            keys += [(f + 6, tipped), (f + 12, lever), (f + 18, hold)]
            ev = {"round_in": [20, 32, 44], "lever": f + 12, "can_fire_again": f + 18}
        else:
            # Double shotgun: break open (muzzle down), left hand drops shells at the belt and back to the breech,
            # snap shut (muzzle up), back to aim.
            opened = offset(hold, Torso=(18, -8, -6), UpperArm_R=(0, 0, 12), Head=(20, 0, 0))
            belt = offset(opened, UpperArm_L=(-15, 0, 0))
            breech = offset(opened, UpperArm_L=(40, 0, 0))
            keys = [(0, hold), (8, opened), (16, belt), (24, breech), (28, breech),
                    (34, offset(hold, Torso=(-4, 0, 0))), (40, hold)]  # fmt: skip
            f = 40
            ev = {"break_open": 6, "shells_in": 26, "snap_shut": 34, "can_fire_again": 40}
        write(arm, f"Reload_{cls}", keys, up, "upper", False, cls, ev)

    # ---- Pistol: both arms pushed forward from the gun hold to eye line --------------------------------------------
    # Pistol: the kit gun hold already points the right hand forward; lift the arm to the eye line (one-handed, as
    # the kit holds it).
    pistol = offset(aim, UpperArm_R=(0, 20, 0), Head=(4, 0, 0))
    write(arm, "Aim_Pistol", [(0, pistol), (24, offset(pistol, Abdomen=(1, 1, 0))), (48, pistol)], up, "upper", True,
          "Pistol")  # fmt: skip
    kicked = offset(pistol, LowerArm_R=(0, 0, 15), Torso=(-3, 0, 0))
    write(arm, "Fire_Pistol", [(0, pistol), (2, kicked), (6, pistol)], up, "upper", False, "Pistol",
          {"muzzle": 0, "can_fire_again": 6})  # fmt: skip
    low = offset(pistol, Torso=(10, 0, 0), UpperArm_R=(0, -20, 0), Head=(10, 0, 0))
    belt = offset(low, UpperArm_L=(-15, 0, 0))
    at_gun = offset(low, UpperArm_L=(40, 0, 0))
    write(arm, "Reload_Pistol", [(0, pistol), (6, low), (14, belt), (22, at_gun), (28, pistol)], up, "upper", False,
          "Pistol", {"mag_out": 6, "mag_in": 22, "can_fire_again": 28})  # fmt: skip

    # ---- Melee: an overhead diagonal chop (bat and axe), the weapon raised at the shoulder when ready ------------
    # Pitch and arm-raise driven: big yaw on the pitched spine bones leans the whole body sideways (first try).
    ready = offset(aim, UpperArm_R=(-10, 0, 0))
    write(arm, "Aim_Melee", [(0, ready), (24, offset(ready, Abdomen=(1.5, 1, 0))), (48, ready)], up, "upper", True,
          "Melee")  # fmt: skip
    windup = offset(ready, UpperArm_R=(55, 0, 0), LowerArm_R=(0, 0, 30), Torso=(-8, 15, 0))
    strike = offset(ready, UpperArm_R=(-25, 0, 0), LowerArm_R=(0, 0, -20), Torso=(18, -12, 0))
    follow = offset(ready, UpperArm_R=(-35, 0, 0), LowerArm_R=(0, 0, -25), Torso=(22, -18, 0))
    keys = [(0, ready), (6, windup), (10, strike), (13, follow), (22, ready)]
    write(arm, "Swing_Melee", keys, up, "upper", False, "Melee", {"whoosh": 6, "hit_start": 9, "hit_end": 12,
                                                                   "can_swing_again": 22})  # fmt: skip

    # ---- Equip / unequip per class: per-bone slerp from the lowered Idle arms to the class aim pose ---------------
    aims = {"Rifle": aim, "Shotgun": aim, "Pistol": pistol, "Melee": ready}
    for cls, target in aims.items():
        keys = [(0, idle), (4, blend(idle, target, 0.45)), (10, target)]
        write(arm, f"Equip_{cls}", keys, up, "upper", False, cls, {"weapon_visible": 2, "ready": 10})
        keys = [(0, target), (6, blend(target, idle_mid, 0.55)), (10, idle_mid)]
        write(arm, f"Unequip_{cls}", keys, up, "upper", False, cls, {"weapon_hidden": 8})

    strikes(arm, {"Rifle": aim, "Shotgun": aim, "Pistol": pistol, "Melee": ready}, up)
    grenade(arm, up, idle, idle_mid, aim)
    repair(arm, up, aim)
    aim_moves(arm, acts, aim, every)
    revive(arm, acts)
    sprint_carries(arm, acts, aim, up)
    dual(arm, up, idle, idle_mid, pistol)
    return CLIPS


# The quick melee (#411): one blow for every weapon, a short club-like bash with whatever is in the hands. The motion
# is the same for each class; `arm` is how much of it the right arm does on its own (a gun in two hands is mostly
# the spine, which carries both hands and the weapon, so the left hand stays on the fore-end; one hand holds a
# pistol, a bat or an axe and swings freely). 13 frames, under the quick melee's cooldown (0.6 s).
STRIKE = {"Rifle": 0.45, "Shotgun": 0.45, "Pistol": 0.9, "Melee": 1.0}
STRIKE_EVENTS = {"whoosh": 3, "hit": 6, "can_strike_again": 13}


def strikes(arm, bases, up):
    """Strike_Rifle, Strike_Shotgun, Strike_Pistol and Strike_Melee, each from its class's aim pose."""
    for cls, base in bases.items():
        k = STRIKE[cls]
        windup = offset(
            base, UpperArm_R=(35 * k, 0, 0), LowerArm_R=(0, 0, 25 * k), Torso=(-8, 14, 0), Abdomen=(-2, 6, 0)
        )
        strike = offset(
            base, UpperArm_R=(-15 * k, 0, 0), LowerArm_R=(0, 0, -15 * k), Torso=(15, -11, 0), Abdomen=(5, -5, 0)
        )
        follow = offset(
            base, UpperArm_R=(-22 * k, 0, 0), LowerArm_R=(0, 0, -18 * k), Torso=(19, -15, 0), Abdomen=(6, -7, 0)
        )
        keys = [(0, base), (3, windup), (6, strike), (8, follow), (13, base)]
        write(arm, f"Strike_{cls}", keys, up, "upper", False, cls, dict(STRIKE_EVENTS))  # fmt: skip


# The grenade is held on the same bone as every weapon, so the projectile leaves from there at `release`.
GRENADE_HAND = "Index1.R"


def grenade(arm, up, idle, idle_mid, aim):
    """Grenade_Cook, Grenade_Throw and Grenade_Toss (Deadnight #102, for the grenades of #99): upper body only, so the
    legs keep running under them. Named Grenade_<Action> (the grenade is thrown, not aimed: it has no Aim loop).

    Cook starts from the lowered Idle arms (where Unequip ends), brings the grenade to the chest from the gun hold's
    right arm (`aim`), the left hand pulls the pin and the spoon flies when the cook starts; it ends on the cooked hold,
    which is frame 0 of both throws. Throw and Toss end on the lowered arms, where Equip_<Class> starts.
    """
    # Arm offsets below were solved for a hand position (Index1, world metres at kit scale; the Soldier faces -Y,
    # his right is -X) with the spine set first, then rounded: the probe is in the pull request. Measured axes from
    # the cooked hold: on Abdomen and Torso, X pitches forward, Y leans sideways, Z turns the chest (+ to his right);
    # on UpperArm.R, X raises the hand, Y swings it across to the left; on LowerArm.R, Z bends the hand up; on
    # UpperArm.L, Y- swings the hand forward.
    # The cooked hold: the grenade at the right of the chest in the gun hold's hand (x -0.16, y -0.92, z 1.17).
    held = offset(aim, UpperArm_R=(-10, 0, 0), LowerArm_R=(0, 0, 12))
    grab = offset(held, Torso=(0, 0, 6), UpperArm_L=(26, -100, -19), LowerArm_L=(1, 0, 16))  # left hand on the ring
    pulled = offset(held, Torso=(0, 0, -4), UpperArm_L=(36, -22, 0), LowerArm_L=(8, 0, -37))  # ring out to the left
    keys = [(0, idle), (5, blend(idle, held, 0.7)), (8, held), (11, grab), (14, pulled), (20, held)]
    write(arm, "Grenade_Cook", keys, up, "upper", False, "Grenade",
          {"grenade_visible": 0, "pin_out": 14, "spoon_off": 18, "cooked": 20})  # fmt: skip

    # Overhand: the chest turns right and leans back, the hand high behind the right of the head (z 1.85) and the
    # left hand pointing ahead; the chest whips left and forward, the arm comes over the top and lets go high in front
    # (z 1.75), follows through across the body to the left knee; arms down.
    cocked = offset(held, Abdomen=(-6, 0, 10), Torso=(-6, 0, 15), UpperArm_R=(35, -56, 1), LowerArm_R=(49, 0, 23),
                    UpperArm_L=(39, -58, 0), LowerArm_L=(2, 0, 5), Head=(4, 0, -10))  # fmt: skip
    release = offset(held, Abdomen=(6, 0, -8), Torso=(8, 0, -14), UpperArm_R=(30, 46, -40), LowerArm_R=(-4, 0, 36),
                     UpperArm_L=(36, -22, 0), LowerArm_L=(8, 0, -37), Head=(-6, 0, 8))  # fmt: skip
    follow = offset(held, Abdomen=(10, 0, -12), Torso=(14, 0, -18), UpperArm_R=(0, -44, -3), LowerArm_R=(-40, 0, 60),
                    Head=(-8, 0, 10))  # fmt: skip
    keys = [(0, held), (6, cocked), (9, release), (13, follow), (22, idle_mid)]
    write(arm, "Grenade_Throw", keys, up, "upper", False, "Grenade", {"release": 9, "done": 22})

    # Underarm: the arm swings back low behind the right hip (z 0.7) as the chest dips and turns right, then forward
    # and up; let go in front at the waist (z 0.85), the hand rises on to the chest (z 1.35); arms down.
    back = offset(held, Abdomen=(8, 0, 8), Torso=(8, 0, 10), UpperArm_R=(-40, -88, 0), LowerArm_R=(6, 0, -10),
                  Head=(-6, 0, -6))  # fmt: skip
    toss = offset(held, Abdomen=(4, 0, -5), Torso=(2, 0, -6), UpperArm_R=(0, -32, -2), LowerArm_R=(-26, 0, 4))
    lift = offset(held, Abdomen=(-2, 0, -6), Torso=(-4, 0, -8), UpperArm_R=(-4, 9, -42), LowerArm_R=(18, 0, 5))
    keys = [(0, held), (6, back), (10, toss), (13, lift), (22, idle_mid)]
    write(arm, "Grenade_Toss", keys, up, "upper", False, "Grenade", {"release": 10, "done": 22})


def repair(arm, up, aim):
    """Repair_Board (Deadnight #221): the Soldier puts a board back across a breach of the fence. Upper body only, so
    the legs keep their locomotion; one loop is one board, 24 frames (1.0 s), the night's `repair_interval`: the
    controller plays it at 1 / interval and seeks it to `board_set` on each `board_repaired` of its player.

    The left hand holds the board flat against the gap at chest height (no IK); the right fist comes down on it twice,
    a tap from half height and a full blow from above the head that drives it home (`board_set`, the frame the
    board lands in the game). The weapon is hidden for the length of the repair by the controller.
    """
    # Hand positions (Index1, world metres at kit scale; the Soldier faces -Y, his right is -X), probed: the board's
    # face is about 0.95 m in front of him. Held: left hand (0.25, -0.92, 1.18), right fist at the board beside it
    # (-0.25, -0.97, 1.14). Raised: the fist above the head behind the right shoulder (-0.32, -0.59, 1.93).
    hold = offset(aim, Abdomen=(4, 0, 0), UpperArm_L=(15, -75, 0))
    struck = offset(hold, Torso=(5, 0, -3), UpperArm_R=(-6, 0, 0), Head=(4, 0, 0))
    lifted = offset(hold, UpperArm_R=(25, 0, 0), LowerArm_R=(0, 0, 14))
    raised = offset(hold, Torso=(-5, 0, 5), UpperArm_R=(52, 0, 0), LowerArm_R=(0, 0, 26), Head=(-3, 0, 0))
    keys = [(0, lifted), (3, struck), (6, struck), (10, lifted), (15, raised), (18, struck), (21, struck),
            (24, lifted)]  # fmt: skip
    write(arm, "Repair_Board", keys, up, "upper", True, "Repair", {"hammer": [3, 18], "board_set": 18})


# Moving while aiming (Deadnight #74): the player keeps facing the camera and moves at `aim_speed` (2.6 m/s) in any
# direction, so the legs need a clip per direction, played under the aim (the upper bones come from Aim_<Class>
# through the bone filter). The four are one gait turned four ways, so they blend in step in a 2D blend space and
# cover the same ground speed in every direction. Name -> direction of travel, degrees clockwise from ahead.
AIM_MOVES = {"Walk_Shoot": 0, "Strafe_Right": 90, "Walk_Back": 180, "Strafe_Left": -90}
AIM_MOVE_SPEED = 2.6  # m/s in the game: PlayerTuning.aim_speed
GAME_SCALE = 0.8  # the Soldier's size in the game (style bible)
AIM_MOVE_LENGTH = 0.85  # a planted foot's sweep, times the kit Run's contact (0.45 m at kit scale)
AIM_MOVE_LIFT = 0.55  # the swing's height, times the kit Run's (a low, careful jog that keeps the gun level)
AIM_MOVE_BOB = 0.45  # the hips' rise and fall, times the kit Run's, vertical only
AIM_MOVE_DROP = 0.05  # metres (kit scale) the hips sit lower: knees bent under the aim
AIM_MOVE_STAGGER = 0.16  # metres (kit scale) the feet's lanes move ahead and behind on a strafe, so they pass
AIM_MOVE_TURN = 0.35  # how far the knees and toes turn toward a sideways step, of the step's angle
AIM_MOVE_FLAT = 0.65  # how much of the kit Run's toe pitch is taken out on a strafe (all of it going backward)
AIM_MOVE_ARC = 0.16  # metres (kit scale): off the forward direction the swing is an even arc this high at mid-swing


def aim_moves(arm, acts, aim, every):
    """Walk_Shoot, Walk_Back, Strafe_Left and Strafe_Right (full body: the gun hold of Idle_Shoot frame 0 above the
    hips, which the game replaces with Aim_<Class>; a steady Body, so the aim does not sway).

    The legs come from the kit Run on its own 17 frames: each foot's path is the Run's, turned toward the direction
    of travel about its lane (gaitlib.sweep_plan, swept_foot): the planted foot sweeps the ground at the aim speed
    over 0.85 of the Run's contact, and the Run's swing fills the rest of the cycle, lower. On a strafe the lanes
    are staggered ahead and behind so the feet pass instead of colliding, and the knees and toes turn a third of
    the way toward the step. The legs are solved to meet the feet (gaitlib.solve_leg).
    """
    run = acts["Run"]
    n = int(run.frame_range[1])
    base = [full(arm, sample(run, f)) for f in range(n + 1)]
    shape = gl.leg_shape(arm, base)
    mw = arm.matrix_world
    unit = mw.to_scale()[0]  # armature units to metres (the Soldier is authored under a 100x object scale)
    per_frame = AIM_MOVE_SPEED / GAME_SCALE / FPS
    plans = {}
    for leg in gl.LEGS:
        foot = leg[2]
        rest = mw @ arm.data.bones[foot].matrix_local

        def path(t, rest=rest, foot=foot):
            return rest @ sample(run, t)[foot]["loc"]

        plans[foot] = dict(gl.sweep_plan(path, n, per_frame, AIM_MOVE_LENGTH), rest=rest, path=path)
    # The hips' bob: the Run's Body location about its mean, its vertical part only, in Body's own space.
    up = gl.up_axis(arm)
    body_rest = arm.data.bones["Body"].matrix_local.to_3x3()
    mean = sum((p["Body"]["loc"] for p in base[:-1]), Vector()) / (len(base) - 1)

    def vertical(local):
        return body_rest.inverted() @ (up * up.dot(body_rest @ local))

    drop = body_rest.inverted() @ (-up * AIM_MOVE_DROP / unit)
    report = {}
    for name, angle in AIM_MOVES.items():
        theta = math.radians(angle)
        side = math.sin(theta)
        turn = -AIM_MOVE_TURN * math.degrees(math.asin(side))  # about world up: clockwise (to his right) is negative
        ahead = max(math.cos(theta), 0.0)
        flat = AIM_MOVE_FLAT * abs(side) + max(-math.cos(theta), 0.0)
        arc = 1.0 - ahead  # forward keeps the kit's swing; sideways and backward an even arc
        travel = Quaternion((0, 0, 1), -theta)  # turns "backward along the walk" (+Y) into "against the travel"
        keys, pulled = [], 0.0
        for f in range(n + 1):
            pose = {b: {"rot": v["rot"].copy(), "loc": v["loc"].copy()} for b, v in aim.items()}
            pose["Body"]["loc"] = aim["Body"]["loc"] + vertical(base[f]["Body"]["loc"] - mean) * AIM_MOVE_BOB + drop
            for leg in gl.LEGS:
                foot = leg[2]
                plan = plans[foot]
                along, height, kit_t = gl.swept_foot(plan["path"], n, f % n, plan, AIM_MOVE_LIFT, arc=arc,
                                                     arc_height=AIM_MOVE_ARC)  # fmt: skip
                lead = -1.0 if foot.endswith(".R") else 1.0
                lane = Vector((plan["x"], plan["centre"] + lead * AIM_MOVE_STAGGER * side, plan["kit"][2]))
                at = lane + travel @ Vector((0, along, 0)) + Vector((0, 0, height))
                pose[foot]["loc"] = plan["rest"].inverted() @ at
                toe = aim[foot]["rot"].slerp(sample(run, kit_t)[foot]["rot"], 1.0 - flat)
                pose[foot]["rot"] = gl.turned_about_up(arm, foot, toe, turn)
            for leg in gl.LEGS:
                pulled = max(pulled, gl.solve_leg(arm, pose, leg, shape[leg[1]], turn) * unit)
            keys.append((f, pose))
        events = {f"step_{s}": round(plans[f"Foot.{s[0].upper()}"]["mid"] - plans[f"Foot.{s[0].upper()}"]["frames"] / 2) % n
                  for s in ("left", "right")}  # fmt: skip
        write(arm, name, keys, every, "full", True, None, dict(sorted(events.items(), key=lambda kv: kv[1])))
        report[name] = round(pulled, 4)
    for name, angle in AIM_MOVES.items():
        CLIPS[name]["ground_speed"] = round(gl.measure_gait(arm, bpy.data.actions[name], GAME_SCALE), 2)
        CLIPS[name]["direction"] = angle
    print("AIM_MOVES", {k: (CLIPS[k]["ground_speed"], report[k]) for k in AIM_MOVES},
          {k: (round(v["thigh"] * unit, 3), round(v["ankle"].length * unit, 3), round(v["spread"] * unit, 4))
           for k, v in shape.items()})  # fmt: skip


# ---- Downed and revive (Deadnight #504, for the revives of #486) ---------------------------------------------------
# Positions here are world metres at kit scale (Blender Z up; the Soldier faces -Y, his right is -X), the probe's frame;
# the game draws the Soldier at GAME_SCALE. Poses are built by turning bones about world axes and solving arms and legs
# onto world targets, not by local Euler offsets: lying down and kneeling move every bone far from the standing axes
# the offsets above were measured in.

# The finger bones: no clip here keys them, so the hand keeps the skeleton's rest fist (the file's static pose) and
# HandGripPose (#507) is free to close it on whatever the hand holds.
FINGERS = tuple(f"{f}{i}.{s}" for f in ("Pinky", "Middle", "Index", "Thumb") for i in (1, 2, 3) for s in ("L", "R")
                if not (f == "Thumb" and i == 3))  # fmt: skip
DOWNED_CRAWL_SPEED = 0.45  # m/s in the game: the planted heel's sweep (#505 may change it; the rate follows)
DOWNED_CRAWL_FRAMES = 32  # one pull of each heel
REVIVE_FRAMES = 24  # one loop, two presses
REVIVE_HANDS = (-0.66, 0.36)  # the hands ahead (y) and up (z) at the top of a press, kit metres; 0.07 lower pressed


def world_axis(arm, axis):
    """A world direction in the armature's space."""
    return (arm.matrix_world.to_3x3().normalized().inverted() @ Vector(axis)).normalized()


def turn(arm, pose, bone, axis, degrees):
    """Turn `bone`, and everything hanging from it, `degrees` about a world axis through its head (right hand rule:
    about +X a positive turn takes +Y toward +Z, so it raises a torso lying along +Y and leans a standing one forward)."""
    gl.apply_pose(arm, pose)
    m = arm.pose.bones[bone].matrix.to_3x3().normalized()
    r = Quaternion(world_axis(arm, axis), math.radians(degrees)).to_matrix()
    pose[bone]["rot"] = pose[bone]["rot"] @ (m.inverted() @ r @ m).to_quaternion()


def head_at(arm, pose, bone):
    """World position of a bone's head in `pose`."""
    gl.apply_pose(arm, pose)
    return arm.matrix_world @ arm.pose.bones[bone].head


def move(arm, pose, bone, delta):
    """Move a bone's head by `delta` (world metres) through its location key."""
    gl.apply_pose(arm, pose)
    b = arm.data.bones[bone]
    base = b.matrix_local
    if b.parent:
        base = arm.pose.bones[b.parent.name].matrix @ b.parent.matrix_local.inverted() @ b.matrix_local
    d = arm.matrix_world.inverted().to_3x3() @ Vector(delta)
    pose[bone]["loc"] = pose[bone]["loc"] + base.to_3x3().inverted() @ d


def place(arm, pose, bone, target):
    """Put a bone's head at a world position (the IK feet, which hang from Root)."""
    move(arm, pose, bone, Vector(target) - head_at(arm, pose, bone))


def reach(arm, pose, upper, lower, end, target, pole, tip=None):
    """Two-bone solve: turn `upper` and `lower` so the head of `end` (a child of `lower`) meets `target` (world), the
    middle joint bent toward the world direction `pole`. The arm's own lengths, measured in the pose; out of reach,
    the end stops on the line to the target. `tip` is the end in the lower bone's frame when `end` does not hang
    from it (a leg: the ankle of gaitlib.leg_shape, since the IK foot hangs from Root)."""
    gl.apply_pose(arm, pose)
    inv = arm.matrix_world.inverted()
    pu, pl, pe = arm.pose.bones[upper], arm.pose.bones[lower], arm.pose.bones[end]
    root, mid = pu.head.copy(), pl.head.copy()
    if tip is None:
        tip = pl.matrix.to_3x3().inverted() @ (pe.head - mid)
    l1, l2 = (mid - root).length, tip.length
    to = inv @ Vector(target) - root
    dist = min(to.length, (l1 + l2) * 0.995)
    d = to.normalized()
    bend = inv.to_3x3() @ Vector(pole)
    bend = (bend - d * bend.dot(d)).normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    new_mid = root + d * a + bend * math.sqrt(max(l1 * l1 - a * a, 0.0))
    r1 = (mid - root).rotation_difference(new_mid - root).to_matrix()
    mu = r1 @ pu.matrix.to_3x3()
    ml = r1 @ pl.matrix.to_3x3()
    ml = (ml @ tip).rotation_difference(root + d * dist - new_mid).to_matrix() @ ml
    bu, bl = arm.data.bones[upper], arm.data.bones[lower]
    rest_u = (bu.parent.matrix_local.inverted() @ bu.matrix_local).to_3x3()
    rest_l = (bu.matrix_local.inverted() @ bl.matrix_local).to_3x3()
    pose[upper]["rot"] = ((pu.parent.matrix.to_3x3() @ rest_u).inverted() @ mu).to_quaternion()
    pose[lower]["rot"] = ((mu @ rest_l).inverted() @ ml).to_quaternion()


def legs(arm, pose, shape, feet, knees):
    """Put each IK foot at its world target and solve its leg to meet it, the knee bent toward its world direction:
    feet {"Foot.L": (x, y, z), ...}, knees {"Foot.L": (x, y, z), ...}. A foot out of reach is pulled in to the leg's
    reach (gaitlib.REACH_USE), so the boot never stretches off the shin."""
    for upper, lower, foot in gl.LEGS:
        hip = head_at(arm, pose, upper)
        to = Vector(feet[foot]) - hip
        most = (shape[lower]["thigh"] + shape[lower]["ankle"].length) * gl.REACH_USE * arm.matrix_world.to_scale()[0]
        place(arm, pose, foot, hip + to.normalized() * min(to.length, most))
        reach(arm, pose, upper, lower, foot, head_at(arm, pose, foot), knees[foot], tip=shape[lower]["ankle"])


def copy(pose):
    return {b: {"rot": v["rot"].copy(), "loc": v["loc"].copy()} for b, v in pose.items()}


# The downed sit (world, kit scale): the hips over the player's place, the chest raised 30 degrees off the ground and
# leaned on to the left elbow, the right hand pressed on the belly, the heels out in front and the right knee drawn up.
# Leaned, not sat up straight: from the shoulder camera behind him a straight sit is all helmet; leaned, the back, the
# right arm and the legs show beside it.
DOWNED_SHIFT = (0.0, -0.45, 0.0)  # moves Death's last frame so the hips sit over the player's place
DOWNED_SIT = {"Abdomen": 20, "Torso": 14, "Neck": 8, "Head": 8}  # degrees about world X, off the ground
DOWNED_LEAN = 12  # degrees about world Y, on to his left side (+X)
# The whole body turned about the vertical (the head to his left, the feet to his right), so the shoulder camera behind
# him does not look along the body over the helmet: the legs show past it.
DOWNED_TURN = -20
DOWNED_KNEES = {"Foot.L": (0.2, 0.0, 1.0), "Foot.R": (-0.3, 0.0, 1.0)}  # up, and a little out
DOWNED_ELBOW = ((0.38, 0.12, 0.18), (0.3, 0.8, -0.5))  # left hand from the hips (x, y) and up (z); elbow pole
DOWNED_WOUND = (-0.05, 0.08, 0.2)  # right hand: to his right, up the spine and out of the belly, from Abdomen
DOWNED_WOUND_POLE = (-1.0, 0.3, -0.3)
DOWNED_FEET = {"Foot.L": (0.2, -0.8, 0.05), "Foot.R": (-0.22, -0.55, 0.06)}  # from the hips; the right knee up


def at_hips(arm, pose, x, y, z):
    """A world point from the hips' centre: (x, y) in the frame of the turned body, z from the ground."""
    c = (head_at(arm, pose, "UpperLeg.L") + head_at(arm, pose, "UpperLeg.R")) / 2
    v = Quaternion((0, 0, 1), math.radians(DOWNED_TURN)) @ Vector((x, y, 0))
    return Vector((c.x + v.x, c.y + v.y, z))


def belly(arm, pose):
    """The front of the belly (world): from Abdomen, along the spine and out of the chest's front."""
    root, neck = head_at(arm, pose, "Abdomen"), head_at(arm, pose, "Neck")
    spine = (neck - root).normalized()
    ahead = Vector((0, -1, 0))
    front = (ahead - spine * ahead.dot(spine)).normalized()
    x, along, out = DOWNED_WOUND
    return root + Vector((x, 0, 0)) + spine * along + front * out


def downed_base(arm, acts, shape):
    death = acts["Death"]
    pose = full(arm, sample(death, death.frame_range[1]))
    move(arm, pose, "Body", DOWNED_SHIFT)
    for foot in ("Foot.L", "Foot.R"):
        move(arm, pose, foot, DOWNED_SHIFT)
    for bone, deg in DOWNED_SIT.items():
        turn(arm, pose, bone, (1, 0, 0), deg)
    turn(arm, pose, "Abdomen", (0, 1, 0), DOWNED_LEAN)
    turn(arm, pose, "Body", (0, 0, 1), DOWNED_TURN)
    legs(arm, pose, shape, {f: at_hips(arm, pose, *v) for f, v in DOWNED_FEET.items()}, DOWNED_KNEES)
    return pose


def downed_arms(arm, pose, elbow=None):
    (x, y, z), pole = elbow or DOWNED_ELBOW
    reach(arm, pose, "UpperArm.L", "LowerArm.L", "Index1.L", at_hips(arm, pose, x, y, z), pole)
    reach(arm, pose, "UpperArm.R", "LowerArm.R", "Index1.R", belly(arm, pose), DOWNED_WOUND_POLE)
    return pose


def revive(arm, acts):
    """Downed_Idle, Downed_Crawl and Revive_Kneel (Deadnight #504): the downed player and the teammate pulling them up.
    Full body (they own the legs too), keyed on every bone but the fingers. Built into their own files:
    `--clips Downed_Idle,Revive_` (game/assets/characters/soldier/revive/) and `--clips Downed_Crawl`
    (game/assets/characters/soldier/crawl/, kept apart so it can be dropped if downed players do not move, #505).

    Downed_Idle reads from the shoulder camera and from above: sitting up on the left hand, the right hand on the
    wound, the right knee drawn up, the head turning to look for help; where the old `Downed` (Death's last frame) lay
    flat with the head away from the camera, a helmet and two boots seen from behind.
    """
    every = [b.name for b in arm.pose.bones if b.name not in FINGERS]
    run = acts["Run"]
    shape = gl.leg_shape(arm, [full(arm, sample(run, f)) for f in range(int(run.frame_range[1]) + 1)])

    # ---- Downed_Idle: two slow breaths over 2 s, the head looking left on the first and right on the second --------
    sit = downed_base(arm, acts, shape)
    downed_arms(arm, sit)

    def breath(look):
        p = copy(sit)
        turn(arm, p, "Torso", (1, 0, 0), 3)  # the chest lifts
        turn(arm, p, "Neck", (0, 0, 1), look * 0.4)
        turn(arm, p, "Head", (0, 0, 1), look * 0.6)
        turn(arm, p, "Head", (1, 0, 0), -4)  # chin up, looking for someone
        return downed_arms(arm, p)

    keys = [(0, sit), (12, breath(22)), (24, sit), (36, breath(-22)), (48, sit)]
    write(arm, "Downed_Idle", keys, every, "full", True, skip=FINGERS)

    # ---- Downed_Crawl: the heels dig in ahead and pull him forward, one then the other; the left hand pushes -------
    n = DOWNED_CRAWL_FRAMES
    half = n // 2
    sweep = DOWNED_CRAWL_SPEED / GAME_SCALE / FPS * half  # kit metres a planted heel travels
    lift = 0.06
    keys = []
    for f in range(n + 1):
        p = copy(sit)
        rock = math.sin(2 * math.pi * f / half)  # a lean into each pull
        turn(arm, p, "Abdomen", (1, 0, 0), 3 * rock)
        turn(arm, p, "Body", (0, 0, 1), 4 * math.sin(2 * math.pi * f / n))
        feet = {}
        for foot, phase in (("Foot.R", 0), ("Foot.L", half)):
            t = (f + phase) % n
            x = DOWNED_FEET[foot][0]
            reach_y = DOWNED_FEET["Foot.L"][1]  # both heels reach as far as the straight leg
            if t <= half:  # planted: sweeps back toward the hips at the crawl speed
                y, z = reach_y + sweep * t / half, 0.05
            else:  # lifted a little and carried forward again
                s = (t - half) / half
                y = reach_y + sweep * (1 - s)
                z = 0.05 + lift * math.sin(math.pi * s)
            feet[foot] = at_hips(arm, p, x, y, z)
        legs(arm, p, shape, feet, DOWNED_KNEES)
        tl = (f + half) % n  # the left elbow pushes with the left heel: planted, it slides back with the ground
        (ex, ey, ez), pole = DOWNED_ELBOW
        push = sweep * 0.5
        dy = push * tl / half if tl <= half else push * (1 - (tl - half) / half)
        dz = 0.0 if tl <= half else 0.06 * math.sin(math.pi * (tl - half) / half)
        downed_arms(arm, p, elbow=((ex, ey + dy, ez + dz), pole))
        keys.append((f, p))
    events = {"pull_right": 0, "pull_left": half}
    write(arm, "Downed_Crawl", keys, every, "full", True, events=events, skip=FINGERS)
    CLIPS["Downed_Crawl"]["ground_speed"] = round(gl.measure_gait(arm, bpy.data.actions["Downed_Crawl"], GAME_SCALE), 2)

    # ---- Revive_Kneel: down on the right knee, both hands on the teammate's chest, pressing twice a second ----------
    stand = full(arm, sample(acts["Idle"], 0))
    kneel = copy(stand)
    move(arm, kneel, "Body", (0.0, 0.04, -0.4))
    # Upright, the arms reaching out and down: leaned over the hands, his big head met the teammate's.
    turn(arm, kneel, "Abdomen", (1, 0, 0), 4)
    turn(arm, kneel, "Torso", (1, 0, 0), 4)
    turn(arm, kneel, "Head", (1, 0, 0), 16)
    # The left foot flat ahead, its knee up and forward; the right knee down, the ankle raised behind it and the toes
    # curled under on the ground (the boot is 0.29 m long: 36 degrees down from the flat foot's 7 puts its toe at 0).
    legs(arm, kneel, shape, {"Foot.L": (0.2, -0.4, 0.022), "Foot.R": (-0.19, 0.4, 0.2)},
         {"Foot.L": (0.0, -1.0, 0.6), "Foot.R": (0.0, -1.0, -0.6)})  # fmt: skip
    turn(arm, kneel, "Foot.R", (1, 0, 0), 36)

    def hands(p, down):
        z = REVIVE_HANDS[1] - down
        reach(arm, p, "UpperArm.L", "LowerArm.L", "Index1.L", (0.09, REVIVE_HANDS[0], z), (1.0, 0.4, -0.2))
        reach(arm, p, "UpperArm.R", "LowerArm.R", "Index1.R", (-0.09, REVIVE_HANDS[0], z), (-1.0, 0.4, -0.2))
        return p

    up_pose = hands(copy(kneel), 0.0)
    pressed = copy(kneel)
    turn(arm, pressed, "Torso", (1, 0, 0), 5)
    hands(pressed, 0.07)
    n = REVIVE_FRAMES
    keys = [(0, up_pose), (n // 4, pressed), (n // 2, up_pose), (3 * n // 4, pressed), (n, up_pose)]
    write(arm, "Revive_Kneel", keys, every, "full", True, events={"press": [n // 4, 3 * n // 4]}, skip=FINGERS)


# ---- Sprint carry (Deadnight #459) -------------------------------------------------------------------------------
# While the body sprints, the legs play the kit Run and the upper body plays Sprint_<Class>: the weapon rides the
# swing of the arms and the chest instead of hanging in the aim pose. Each clip is the kit Run's own 17 frames, frame
# for frame (its spine twist and bob, its left arm), so the swing lands on Run's footfalls by construction and the
# game only has to play it at Run's time. The right arm comes from the kit's Run_Gun (the one-handed gun run, which
# the kit keys on the same 17 frames); the two-handed guns are carried low across the chest with both hands on.
SPRINT_CLASSES = ("Rifle", "Shotgun", "Pistol", "Melee")
# Run's frames where the Body is lowest, one frame after each foot plants (right foot at 3.5, left at 12.5): the
# carried gun dips a frame after the body, so it reads heavy.
SPRINT_LOW = (5, 14)
# The frame of Run whose chest is the reference for the carry targets below (Torso turned least: 1 degree).
SPRINT_REF = 4
# Sprint_Pistol's keys, for the dual pistols' carry (`dual`).
PISTOL_SPRINT = []
# The two-handed carry, per class: the weapon's pose, in the world's axes at SPRINT_REF (the Soldier faces -Y, his
# right is -X), turned with the chest: where its grip is from the waist (the Torso bone's head, metres), the way the
# muzzle points and the top of the gun faces, how far it swings across with the chest (degrees each way, on top of
# Run's own chest twist of 9 degrees each way), and how far it dips a frame after each footfall (degrees the muzzle
# drops). Both hands reach the weapon there by two-bone IK, as WeaponHandsIK does while aiming (Deadnight #527): the
# right hand bone turned so the weapon, through its solved grip (`HandGrip.hold` in grips/<model>.tres, at the hold's
# `model_scale`; `hold` names the hold file, game/gameplay/player/holds/<hold>.tres), points that way and its grip
# lands on the point; the left hand bone on the grip's `left_hand` point of that weapon, turned the same way. A carry
# built the other way (the forearm fixed, the weapon wherever the hand's hold put it) moved with every new grip: with
# #507's grips the gun hung by the right leg and the left hand missed the fore-end by 0.2 m.
SPRINT_CARRY = {
    "Rifle": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
              "swing": 6.0, "dip": 4.0, "hold": "rifle"},
    "Shotgun": {"grip": (0.1, -0.33, -0.03), "muzzle": (0.85, -0.52, 0.4), "top": (-0.3, 0.2, 1.0),
                "swing": 7.0, "dip": 5.0, "hold": "shotgun"},
    # A weapon whose grip turns it in the hand far from its class's (the Tommy gun's pistol grip stands 90 degrees
    # off the lever rifle's wrist) gets its own carry, `Sprint_<model>`, the same pose through its own grip:
    # SprintCarry.clip_for picks it for that model and the class's for the rest.
    "tommy_gun": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
                  "swing": 6.0, "dip": 4.0, "hold": "smg", "class": "Rifle"},
    # The six firearms of #793: pistol-grip guns like the Tommy gun, each carried through its own grip.
    "ppsh": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
                  "swing": 6.0, "dip": 4.0, "hold": "ppsh", "class": "Rifle"},
    "mp5": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
                  "swing": 6.0, "dip": 4.0, "hold": "mp5", "class": "Rifle"},
    "m4a1": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
                  "swing": 6.0, "dip": 4.0, "hold": "m4a1", "class": "Rifle"},
    "m249": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
                  "swing": 6.0, "dip": 4.0, "hold": "m249", "class": "Rifle"},
    "fifty_cal": {"grip": (0.1, -0.33, 0.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
                  "swing": 6.0, "dip": 4.0, "hold": "fifty_cal", "class": "Rifle"},
    "pump_870": {"grip": (0.1, -0.33, -0.03), "muzzle": (0.85, -0.52, 0.4), "top": (-0.3, 0.2, 1.0),
                 "swing": 7.0, "dip": 5.0, "hold": "pump_870", "class": "Shotgun"},
}  # fmt: skip
# The carries of single models, after the class ones (named Sprint_<model>).
SPRINT_MODELS = tuple(k for k, c in SPRINT_CARRY.items() if "class" in c)
# The game's data the carries are built against (the hold and grip files).
GAME = Path(__file__).resolve().parents[2] / "game"
# Pistol: Run_Gun's right arm (the kit's own one-handed gun run: the forearm pumps 46 degrees a stride), with the upper
# arm swinging this share of the left arm's swing, half a stride later, so the gun hand swings at the side too.
SPRINT_PISTOL_SWING = 0.35
# Melee: a runner's arm with the bat in the fist. The upper arm hangs (`upper`, chest frame) and swings fore and aft
# from the shoulder, against the left arm (back at frame 0, when the left hand leads), `swing` degrees each way; the
# forearm stays bent forward (`fore`) and pumps `pump` times the arm's swing, so the bat stays up and rocks with the
# stride instead of hanging toward the legs. The arm is held out from the side so the weapon clears the body and the
# head from the shoulder camera behind him.
# `shaft` is the way the weapon's shaft leans (chest frame): the forearm is turned about its own axis to bring it as
# close as it can, up and back over the shoulder and a little out.
SPRINT_MELEE = {"upper": (-0.5, 0.1, -1.0), "fore": (-0.3, -1.0, 0.3), "shaft": (-0.25, 0.45, 1.0), "swing": 24.0,
                "pump": 1.2}  # fmt: skip


def _rot(m):
    """The rotation of a world or pose matrix with its scale taken out."""
    return m.to_3x3().normalized()


def _world(arm, bone):
    """(rotation, head) of a pose bone in the world: the rotation orthonormal, the head in metres."""
    m = arm.matrix_world @ arm.pose.bones[bone].matrix
    return _rot(m), m.translation.copy()


def _set_world_rot(arm, bone, rot):
    """Turn a pose bone so its world rotation is `rot`; its head stays where its parent puts it."""
    pb = arm.pose.bones[bone]
    pose_rot = _rot(arm.matrix_world).inverted() @ rot
    pb.matrix = Matrix.Translation(pb.matrix.translation) @ pose_rot.to_4x4()
    bpy.context.view_layer.update()


def _turn(arm, bone, frm, to):
    """Turn a pose bone in the world so the direction `frm` becomes `to` (the shortest turn)."""
    r, _ = _world(arm, bone)
    _set_world_rot(arm, bone, frm.rotation_difference(to).to_matrix() @ r)


def _reach(arm, bones, goal, pole, back=0.0):
    """Two-bone IK in the world (WeaponHandsIK._reach in the game): turn upper and lower so the hand bone's head
    reaches `goal`, the elbow toward `pole`; with `back` the hand stops that far short along the forearm. Returns how
    far the hand ended from where it was sent (metres)."""
    upper, lower, hand = bones
    target = goal
    for _ in range(2):
        root, elbow, wrist = (_world(arm, b)[1] for b in bones)
        lu, ll = (elbow - root).length, (wrist - elbow).length
        target = goal - (wrist - elbow).normalized() * back
        to = target - root
        dist = min(max(to.length, abs(lu - ll) + 0.01), lu + ll - 0.001)
        d = to.normalized()
        along = (lu * lu - ll * ll + dist * dist) / (2 * dist)
        height = math.sqrt(max(lu * lu - along * along, 0.0))
        bend = (pole - d * pole.dot(d)).normalized()
        new_elbow = root + d * along + bend * height
        _turn(arm, upper, elbow - root, new_elbow - root)
        e, w = _world(arm, lower)[1], _world(arm, hand)[1]
        _turn(arm, lower, w - e, root + d * dist - new_elbow)
    return (_world(arm, hand)[1] - target).length


def _pose_arm(arm, pose):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = pose[pb.name]["rot"]
        pb.location = pose[pb.name]["loc"]
    bpy.context.view_layer.update()


def _read_pose(arm, like):
    """The armature's pose now, rotations only: locations stay as `like` has them (turning a bone through its matrix
    must not move it)."""
    return {
        pb.name: {"rot": pb.rotation_quaternion.copy(), "loc": like[pb.name]["loc"].copy()} for pb in arm.pose.bones
    }


def _held(kit):
    """The kit weapon `kit` on Index1.R, or None (build_soldier removes them only after build)."""
    return next((o for o in bpy.data.objects if o.parent_type == "BONE" and o.parent_bone == "Index1.R"
                 and re.sub(r"\.\d+$", "", o.name) == kit), None)  # fmt: skip


def _frame(muzzle, top):
    """A gun's basis from where its muzzle points and its top faces (columns: muzzle, top, side)."""
    m = Vector(muzzle).normalized()
    t = Vector(top)
    t = (t - m * t.dot(m)).normalized()
    return Matrix((m, t, m.cross(t))).transposed()


def _phase(f, n):
    return 2 * math.pi * f / n


def _tres(path):
    """The `key = value` lines of a Godot .tres resource, values as written."""
    return dict(re.findall(r"^(\w+) = (.+)$", path.read_text(encoding="utf-8"), re.MULTILINE))


def _transform(text):
    """A Godot `Transform3D(...)` as a 4x4 matrix: the basis written row by row, then the origin."""
    v = [float(x) for x in text[text.index("(") + 1 : text.rindex(")")].split(",")]
    return Matrix.Translation(v[9:12]) @ Matrix((v[0:3], v[3:6], v[6:9])).to_4x4()


def game_grip(hold):
    """(weapon, left) for the hold file `hold`: the weapon node's transform under the hand bone (the grip's `hold`
    scaled by the hold's `model_scale`: `hold.scaled_local(Vector3.ONE * model_scale)` in PlayerAnimation) and the
    left hand bone's transform on the weapon (`HandGrip.left_hand`, in the model's own space).

    Godot's bones are Blender's pose bones with the same local axes (the exporter only turns the world to Y up:
    measured on soldier.glb, every node's world rotation is the pose bone's, turned from Z up to Y up), so a bone's
    world matrix here times these is where the game draws the weapon and puts the left hand."""
    h = _tres(GAME / "gameplay/player/holds" / f"{hold}.tres")
    scale = float(h["model_scale"])
    model = Path(h["scene"].strip('"')).stem
    g = _tres(GAME / "gameplay/player/grips" / f"{model}.tres")
    assert abs(float(g["model_scale"]) - scale) < 1e-6, f"grips/{model}.tres was solved at another size: solve again"
    assert g.get("has_left") == "true", f"grips/{model}.tres has no left hand"
    return _transform(g["hold"]) @ Matrix.Scale(scale, 4), _transform(g["left_hand"])


def _bone_matrix(arm, bone):
    """A pose bone's world matrix, rotation orthonormal and head in metres."""
    r, head = _world(arm, bone)
    return Matrix.Translation(head) @ r.to_4x4()


def _weapon_frame(weapon):
    """The basis of a weapon placed at `weapon` (a world matrix of the model): the model's muzzle is its -X, its top
    +Y (the hold's `muzzle`, Godot's model axes), in the columns of `_frame`."""
    m = weapon.to_3x3()
    return _frame(-m.col[0], m.col[1])


def sprint_carries(arm, acts, aim, up):
    """Sprint_Rifle, Sprint_Shotgun, Sprint_Pistol and Sprint_Melee: upper-body loops on the kit Run's 17 frames.

    Every frame starts from Run at the same frame (its spine, shoulders and left arm: the chest twist and bob that
    belong to the stride) with the right arm and the fingers of the gun hold (`aim`, Idle_Shoot frame 0; no kit clip
    keys a finger, so they stay the static grip every weapon clip has), then poses the arms for the class. Only the
    spine, the shoulders and the arms move: no finger curls and no change to the weapon's place in the hand, which
    the game's hold owns.
    """
    run, run_gun = acts["Run"], acts["Run_Gun"]
    n = int(run.frame_range[1])
    assert n == int(run_gun.frame_range[1]), "Run_Gun and Run must share their cycle"
    body = ("Abdomen", "Torso", "Neck", "Head", "Shoulder", "UpperArm", "LowerArm")
    fingers = [b for b in up if b.split(".")[0] not in body]

    def base(f, source=run):
        p = full(arm, sample(source, f))
        for b in [*fingers, "UpperArm.R", "LowerArm.R"] if source is run else fingers:
            p[b] = {"rot": aim[b]["rot"].copy(), "loc": aim[b]["loc"].copy()}
        return p

    _pose_arm(arm, base(SPRINT_REF))
    t_ref, _ = _world(arm, "Torso")

    report = {}
    for cls, c in SPRINT_CARRY.items():
        # The class's weapon in the gun hold's right hand, through its solved grip: the hand's turn for the carry is
        # worked out from it, the way WeaponHandsIK works the hand out from the weapon's pose.
        weapon, left_hand = game_grip(c["hold"])
        _pose_arm(arm, aim)
        hand_aim = _world(arm, "Index1.R")[0]
        gun_aim = _weapon_frame(_bone_matrix(arm, "Index1.R") @ weapon)
        keys, grips = [], []
        miss, turned = {"R": 0.0, "L": 0.0}, {"R": 0.0, "L": 0.0}
        for f in range(n + 1):
            phase = _phase(f % n, n)
            start = base(f % n)
            _pose_arm(arm, start)
            t, waist = _world(arm, "Torso")
            follow = t @ t_ref.inverted()  # the chest's turn since the reference: the gun turns with it
            # Across with the chest once a stride (the left hand leads at frame 0, as Run's left arm does), and down
            # a frame after each footfall.
            swing = Matrix.Rotation(math.radians(c["swing"]) * math.cos(phase), 3, "Z")
            dip = c["dip"] * (math.cos(_phase(f - SPRINT_LOW[0], n / 2)) * 0.5 + 0.5)
            side = (follow @ Vector((1, 0, 0))).normalized()
            # The muzzle pitches down by the dip (about the chest's side axis), the rest of the gun with it, about
            # the grip.
            turn_by = swing @ follow
            want = Matrix.Rotation(math.radians(dip), 3, side) @ turn_by @ _frame(c["muzzle"], c["top"])
            grip = waist + turn_by @ Vector(c["grip"])
            # The right hand on the grip: turned so the weapon points where `want` says, its bone where the grip's
            # hold then puts it.
            hand = want @ gun_aim.inverted() @ hand_aim
            right_shoulder, left_shoulder = _world(arm, "UpperArm.R")[1], _world(arm, "UpperArm.L")[1]
            out = (right_shoulder - left_shoulder).normalized() * 0.45
            goal = grip - hand @ weapon.translation
            miss["R"] = max(miss["R"], _reach(arm, ("UpperArm.R", "LowerArm.R", "Index1.R"), goal,
                                              out + Vector((0, 0, -1))))  # fmt: skip
            _set_world_rot(arm, "Index1.R", hand)
            grips.append(turn_by.inverted() @ (grip - waist))
            # The left hand on the fore-end where the grip puts it on the weapon the game draws, turned to hold it
            # (WeaponHandsIK does the same while aiming: the hand bone's head on the point, its basis the grip's).
            hold = _bone_matrix(arm, "Index1.R") @ weapon @ left_hand
            miss["L"] = max(miss["L"], _reach(arm, ("UpperArm.L", "LowerArm.L", "Index1.L"), hold.translation,
                                              -out + Vector((0, 0, -1))))  # fmt: skip
            _set_world_rot(arm, "Index1.L", hold.to_3x3().normalized())
            # How far each wrist is turned off the kit's own two-handed hold (Idle_Shoot), in degrees.
            for s in "RL":
                q = arm.pose.bones[f"Index1.{s}"].rotation_quaternion.rotation_difference(aim[f"Index1.{s}"]["rot"])
                turned[s] = max(turned[s], math.degrees(q.angle))
            keys.append((f, _read_pose(arm, start)))
        write(arm, f"Sprint_{cls}", keys, up, "upper", True, c.get("class", cls))
        report[cls] = {"hand miss (m)": {k: round(v, 3) for k, v in miss.items()},
                       "wrist turn off the aim hold (deg)": {k: round(v, 1) for k, v in turned.items()}}  # fmt: skip

    # Pistol: Run_Gun's right arm, its upper arm swinging with the stride too (the left arm's swing, half a stride on).
    left_arm = [full(arm, sample(run, f))["UpperArm.L"]["rot"] for f in range(n)]
    mean = left_arm[0].slerp(left_arm[round(n / 2)], 0.5)
    keys = []
    for f in range(n + 1):
        p = base(f % n, run_gun)
        other = full(arm, sample(run, (f + n / 2) % n))["UpperArm.L"]["rot"]
        e = (mean.inverted() @ other).to_euler("XYZ")  # the left arm's swing about its mean, in its own axes
        mirrored = Euler((e.x, -e.y, -e.z), "XYZ").to_quaternion()  # the same swing on the right side
        p["UpperArm.R"]["rot"] = p["UpperArm.R"]["rot"] @ Quaternion().slerp(mirrored, SPRINT_PISTOL_SWING)
        keys.append((f, p))
    write(arm, "Sprint_Pistol", keys, up, "upper", True, "Pistol")
    PISTOL_SPRINT.clear()
    PISTOL_SPRINT.extend(keys)

    # Melee: the runner's arm, from the gun hold's arm (the bat upright in the fist) turned by the shortest way, then
    # the forearm rolled so the shaft leans where SPRINT_MELEE says. The shaft is the kit Shovel's long axis (its local
    # Y, up in the gun hold), the hold every melee weapon copies.
    m = SPRINT_MELEE
    _pose_arm(arm, aim)
    shovel = _held("Shovel")
    shaft_up = _rot(shovel.matrix_world).col[1] if shovel else Vector((0, 0, 1))
    shaft_local = _world(arm, "LowerArm.R")[0].inverted() @ shaft_up.normalized()
    keys = []
    for f in range(n + 1):
        start = base(f % n)
        _pose_arm(arm, start)
        t, _ = _world(arm, "Torso")
        follow = t @ t_ref.inverted()
        side = (follow @ Vector((1, 0, 0))).normalized()
        back = math.radians(m["swing"]) * math.cos(_phase(f % n, n))  # positive: the hand behind
        s = _world(arm, "UpperArm.R")[1]
        hang = Matrix.Rotation(back, 3, side) @ follow @ Vector(m["upper"]).normalized()
        _turn(arm, "UpperArm.R", _world(arm, "LowerArm.R")[1] - s, hang)
        fore = Matrix.Rotation(back * m["pump"], 3, side) @ follow @ Vector(m["fore"]).normalized()
        e = _world(arm, "LowerArm.R")[1]
        _turn(arm, "LowerArm.R", _world(arm, "Index1.R")[1] - e, fore)
        r, e = _world(arm, "LowerArm.R")
        axis = (_world(arm, "Index1.R")[1] - e).normalized()
        want = follow @ Vector(m["shaft"]).normalized()
        now, goal = (v - axis * v.dot(axis) for v in (r @ shaft_local, want))
        roll = now.angle(goal) * (1 if now.cross(goal).dot(axis) > 0 else -1)
        _set_world_rot(arm, "LowerArm.R", Matrix.Rotation(roll, 3, axis) @ r)
        keys.append((f, _read_pose(arm, start)))
    write(arm, "Sprint_Melee", keys, up, "upper", True, "Melee")
    print("SPRINT", {k: CLIPS[f"Sprint_{k}"]["frames"] for k in (*SPRINT_CLASSES, *SPRINT_MODELS)}, report)


# ---- Dual pistols (Deadnight #789) -----------------------------------------------------------------------------------
# A pistol in each hand: the Pistol clips with the left arm doing what the right does. The rig is an exact mirror (each
# left bone's local rotation is its right one's with y and z negated: measured on the file and in Godot, where the same
# sign flip mirrors the finger poses), so a mirrored pose is the right arm's rotations with that flip, bone by bone, and
# the chest, which both arms hang from, keeps its own. While a weapon is up the game's hand IK (WeaponHandsIK) holds the
# arms, so these are what they do around it: equipping and putting away, the sprint and the quick melee, and the pose
# the IK is blended from. 6 clips in their own file, built with
#   --clips Aim_Dual,Fire_Dual,Equip_Dual,Unequip_Dual,Strike_Dual,Sprint_Dual
DUAL_ARM = ("Shoulder", "UpperArm", "LowerArm", "Index1")


def mirror_arm(pose):
    """Copy of `pose` with the left arm's rotations the right arm's mirrored."""
    out = {b: {"rot": v["rot"].copy(), "loc": v["loc"].copy()} for b, v in pose.items()}
    for bone in DUAL_ARM:
        q = pose[f"{bone}.R"]["rot"]
        out[f"{bone}.L"]["rot"] = Quaternion((q.w, q.x, -q.y, -q.z))
    return out


def check_mirror(arm, pose):
    """How far (metres) the left hand ends from the right hand's reflection across the body's middle plane, in the
    pose `pose` mirrored: 0 for an exact mirror rig."""
    _pose_arm(arm, mirror_arm(pose))
    right, left = _world(arm, "Index1.R")[1], _world(arm, "Index1.L")[1]
    middle = (_world(arm, "UpperArm.R")[1] + _world(arm, "UpperArm.L")[1]) / 2
    side = (_world(arm, "UpperArm.R")[1] - _world(arm, "UpperArm.L")[1]).normalized()
    reflected = right - 2 * side * (right - middle).dot(side)
    return (reflected - left).length


def shifted(keys, n, shift):
    """The pose `shift` frames on (fractions blended) of a looped key list of frames 0..n (n the same as 0)."""
    out = []
    for f, _pose in keys:
        at = (f + shift) % n
        lo = math.floor(at)
        out.append((f, blend(keys[lo][1], keys[(lo + 1) % n][1], at - lo) if at != lo else keys[lo][1]))
    return out


def dual(arm, up, idle, idle_mid, pistol):
    """Aim_Dual, Fire_Dual, Equip_Dual, Unequip_Dual, Strike_Dual and Sprint_Dual from the Pistol poses."""
    gap = check_mirror(arm, pistol)
    assert gap < 0.002, f"the rig is not a mirror: the hands end {gap:.4f} m from each other's reflection"
    base = mirror_arm(pistol)
    write(arm, "Aim_Dual", [(0, base), (24, mirror_arm(offset(pistol, Abdomen=(1, 1, 0)))), (48, base)], up, "upper",
          True, "Dual")  # fmt: skip
    kicked = mirror_arm(offset(pistol, LowerArm_R=(0, 0, 15), Torso=(-3, 0, 0)))
    write(arm, "Fire_Dual", [(0, base), (2, kicked), (6, base)], up, "upper", False, "Dual",
          {"muzzle": 0, "can_fire_again": 6})  # fmt: skip
    write(arm, "Equip_Dual", [(0, idle), (4, blend(idle, base, 0.45)), (10, base)], up, "upper", False, "Dual",
          {"weapon_visible": 2, "ready": 10})  # fmt: skip
    write(arm, "Unequip_Dual", [(0, base), (6, blend(base, idle_mid, 0.55)), (10, idle_mid)], up, "upper", False,
          "Dual", {"weapon_hidden": 8})  # fmt: skip
    k = STRIKE["Pistol"]
    windup = offset(pistol, UpperArm_R=(35 * k, 0, 0), LowerArm_R=(0, 0, 25 * k), Torso=(-8, 14, 0), Abdomen=(-2, 6, 0))
    blow = offset(
        pistol, UpperArm_R=(-15 * k, 0, 0), LowerArm_R=(0, 0, -15 * k), Torso=(15, -11, 0), Abdomen=(5, -5, 0)
    )
    follow = offset(pistol, UpperArm_R=(-22 * k, 0, 0), LowerArm_R=(0, 0, -18 * k), Torso=(19, -15, 0),
                    Abdomen=(6, -7, 0))  # fmt: skip
    keys = [(0, base), (3, mirror_arm(windup)), (6, mirror_arm(blow)), (8, mirror_arm(follow)), (13, base)]
    write(arm, "Strike_Dual", keys, up, "upper", False, "Dual", dict(STRIKE_EVENTS))
    # The sprint: Sprint_Pistol's gun arm on the right, and on the left the same arm mirrored half a stride on, so
    # the two pistols pump against each other as a runner's arms do.
    n = len(PISTOL_SPRINT) - 1
    opposite = shifted(PISTOL_SPRINT, n, n / 2)
    keys = []
    for (f, right), (_f, other) in zip(PISTOL_SPRINT, opposite):
        pose = {b: {"rot": v["rot"].copy(), "loc": v["loc"].copy()} for b, v in right.items()}
        for bone in DUAL_ARM:
            q = other[f"{bone}.R"]["rot"]
            pose[f"{bone}.L"]["rot"] = Quaternion((q.w, q.x, -q.y, -q.z))
        keys.append((f, pose))
    write(arm, "Sprint_Dual", keys, up, "upper", True, "Dual")
    print("DUAL", {k: CLIPS[k]["frames"] for k in CLIPS if k.endswith("_Dual")}, "mirror gap (m)", round(gap, 5))
