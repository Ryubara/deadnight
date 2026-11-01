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

import bpy
from mathutils import Euler, Quaternion, Vector

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
