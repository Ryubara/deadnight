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


def bake_static(arm, action):
    """Key every bone the action leaves out at its static pose (first and last frame), so the export samples the
    standing pose for it and not the rest pose or whatever the clip before left behind."""
    keyed = {(fc.data_path.split('"')[1], fc.data_path.rsplit(".", 1)[1]) for fc in fcurves(action)}
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


def write(arm, name, keys, bones, layer, loop, cls=None, events=None):
    """Create action `name` keyed at `keys` [(frame, pose)] on `bones`; every other bone at the static pose."""
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
    bake_static(arm, a)
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

    grenade(arm, up, idle, idle_mid, aim)
    repair(arm, up, aim)
    aim_moves(arm, acts, aim, every)
    sprint_carries(arm, acts, aim, up)
    return CLIPS


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
# The two-handed carry, per class, in the frame of the chest at SPRINT_REF (the Soldier faces -Y, his right is -X):
# the way the right upper arm hangs from the shoulder, the way the muzzle points and the top of the gun faces (the
# grip follows: the kit hold puts it 0.62 m out along the forearm), how far the gun swings across with the chest
# (degrees each way, on top of Run's own chest twist of 9 degrees each way), and how far it dips a frame after each
# footfall (degrees the muzzle drops). The support point is the left hand's place on the fore-end: the hold's
# `support` (game/gameplay/player/holds/<class>.tres, model units) times its `model_scale`, so the left hand meets
# the weapon the game draws.
SPRINT_CARRY = {
    "Rifle": {"upper": (-0.35, -0.05, -1.0), "muzzle": (0.85, -0.5, 0.45), "top": (-0.3, 0.2, 1.0),
              "swing": 6.0, "dip": 4.0, "support": (-0.45 * 0.71, -0.05 * 0.71)},
    "Shotgun": {"upper": (-0.35, -0.05, -1.0), "muzzle": (0.85, -0.52, 0.4), "top": (-0.3, 0.2, 1.0),
                "swing": 7.0, "dip": 5.0, "support": (-0.45 * 0.82, -0.03 * 0.82)},
}  # fmt: skip
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


def _gun_basis(obj):
    """World basis of a held kit gun: its local axis that points most ahead (-Y) in the gun hold is the muzzle, the
    one of the others that points most up is the top."""
    r = _rot(obj.matrix_world)
    axes = [s * r.col[i] for i in range(3) for s in (1, -1)]
    muzzle = max(axes, key=lambda a: -a.y)
    top = max((a for a in axes if abs(a.dot(muzzle)) < 0.5), key=lambda a: a.z)
    return _frame(muzzle, top)


def _phase(f, n):
    return 2 * math.pi * f / n


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

    # The gun hold's right arm and gun: every carry target is turned from it.
    _pose_arm(arm, aim)
    rl_aim, elbow_aim = _world(arm, "LowerArm.R")
    gun = _held("Shotgun")
    gun_aim = _gun_basis(gun) if gun else _frame((0, -1, 0.3), (0, 0, 1))
    grip_at = gun.matrix_world.translation if gun else _world(arm, "Index1.R")[1]
    grip_local = rl_aim.inverted() @ (grip_at - elbow_aim)
    _pose_arm(arm, base(SPRINT_REF))
    t_ref, _ = _world(arm, "Torso")

    report = {}
    for cls, c in SPRINT_CARRY.items():
        keys, grips, left = [], [], 0.0
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
            # The muzzle pitches down by the dip (about the chest's side axis), the rest of the gun with it.
            want = Matrix.Rotation(math.radians(dip), 3, side) @ swing @ follow @ _frame(c["muzzle"], c["top"])
            rl = want @ gun_aim.inverted() @ rl_aim
            shoulder = _world(arm, "UpperArm.R")[1]
            lu = (_world(arm, "LowerArm.R")[1] - shoulder).length
            hang = swing @ follow @ Vector(c["upper"]).normalized()
            _turn(arm, "UpperArm.R", _world(arm, "LowerArm.R")[1] - shoulder, hang * lu)
            _set_world_rot(arm, "LowerArm.R", rl)
            r_now, e_now = _world(arm, "LowerArm.R")
            reached = e_now + r_now @ grip_local
            grips.append(t.inverted() @ (reached - waist))
            # The left hand on the fore-end: the hold's support point along the barrel, a little under it.
            sup = reached + want.col[0] * -c["support"][0] + want.col[1] * c["support"][1]
            side = (_world(arm, "UpperArm.L")[1] - shoulder).normalized()
            pole = side * 0.45 + Vector((0, 0, -1))
            left = max(left, _reach(arm, ("UpperArm.L", "LowerArm.L", "Index1.L"), sup, pole, back=0.07))
            keys.append((f, _read_pose(arm, start)))
        write(arm, f"Sprint_{cls}", keys, up, "upper", True, cls)
        mid = sum(grips, Vector()) / len(grips)
        report[cls] = {"grip from the waist": tuple(round(v, 2) for v in mid), "left hand miss": round(left, 3)}

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
    print("SPRINT", {k: CLIPS[f"Sprint_{k}"]["frames"] for k in SPRINT_CLASSES}, report)
