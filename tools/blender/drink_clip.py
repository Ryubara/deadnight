"""Drink_Perk (Deadnight #912): the Soldier drinks a perk. Not run on its own: `soldier_clips.build` calls `drink`, and
`build_soldier.py --clips Drink_` writes it to its own file (game/assets/characters/soldier/drink/), as the grenade
and repair clips are (docs/design/animation.md, "Drink").

An upper clip of 60 frames (2.5 s, the rules' `PerkTuning.drink_seconds`): the gun goes down, the bottle comes up
from the hip, the left hand twists the cap off, the bottle goes to the mouth and is drunk with the head tipped back
(two gulps), is flung away to the right, and the gun comes back up. The game plays it over the night's own drink
(`PlayerAnimation.drink`), at the pace of the server's seconds, so it ends as the perk is had.

Built in world space like the sprint carries: for each key the bottle's lip and axis are set (the lip on the mouth
while drinking, which moves with the head), the right hand is turned so the bottle, through its solved grip
(`grips/perk_bottle.tres`, at `holds/perk_bottle.tres`'s size), points that way, and the arm is solved onto it by
two-bone IK (`soldier_clips._reach`). The left hand reaches the cap the same way. The spine and the head are offsets
on the lowered arms (`Idle` frame 20, where `Unequip_<Class>` ends).
"""

import math

import gaitlib as gl
import soldier_clips as sc
from mathutils import Matrix, Vector

FPS = sc.FPS
FRAMES = 60
HOLD = "perk_bottle"
# Events: the gun is put away and the bottle is in the hand; the cap comes off (the open sound); the first sip and the
# gulps (the drink sound); the bottle leaves the hand (the discard: it flies off and lands); the gun is back.
EVENTS = {"weapon_hidden": 6, "bottle_visible": 6, "cap_off": 17, "drink": 24, "gulp": [30, 37], "discard": 46,
          "weapon_visible": 53, "done": FRAMES}  # fmt: skip
# The mouth in Idle frame 0 (world, kit metres; the Soldier faces -Y, his right is -X): just in front of the lower
# face, over the chin guard (probed on a render, scratch probe in the pull request). It rides the Head bone.
MOUTH = Vector((0.0, -0.69, 1.46))
# The bottle's lip and axis at each key (world, kit metres, the axis from the bottom to the lip), and the elbow's pull.
# A key whose lip is "mouth" puts the lip on the mouth where the head has it at that key, `tip` degrees from upright
# toward his face (90: level, more: the bottom raised). Spine and head: degrees of pitch (+ forward) on the lowered
# arms' spine. The head tips back only a little: the kit's head is a third of his height, and tipped back 20 degrees
# or more it read in the game as pouring the bottle over the helmet (the first capture).
KEYS = [
    # frame, lip (or "mouth"), axis (or (tip, side)), elbow pole, spine {bone: (x, y, z)}
    # At the hip the bottle is out from the side (the fingers sank 50 mm into the hip a few centimetres in).
    (8, (-0.40, -0.50, 0.98), (0.0, -0.25, 1.0), (-1.0, 0.4, -0.4), {}),
    (13, (-0.08, -0.86, 1.22), (0.05, -0.05, 1.0), (-1.0, 0.1, -0.6), {"Head": (6, 0, 0)}),
    (17, (-0.08, -0.86, 1.22), (0.05, -0.05, 1.0), (-1.0, 0.1, -0.6), {"Head": (6, 0, 0)}),
    (21, (-0.16, -0.84, 1.36), (0.25, 0.45, 1.0), (-1.0, -0.1, -0.2), {"Head": (0, 0, 0)}),
    # On the mouth from his right: the bottom out to the right and raised, the elbow up and out, so from the camera
    # over his right shoulder the bottle and the arm show beside the helmet. The bottom comes round 45 degrees, not
    # 58, raised to 126 at most, not 135, and the elbow points back a little (pole y 0.2): further round and higher
    # the fist sank 60 mm into the big head (ClipFit, #990); now 13 mm at most, the build's ARMS line clear.
    (24, "mouth", (100, 45), (-1.0, 0.0, 0.1), {"Neck": (-2, 0, 0), "Head": (-3, 0, 0)}),
    (30, "mouth", (118, 45), (-1.0, 0.2, 0.3), {"Torso": (-2, 0, 0), "Neck": (-4, 0, 0), "Head": (-6, 0, 0)}),
    (33, "mouth", (114, 45), (-1.0, 0.2, 0.3), {"Torso": (-2, 0, 0), "Neck": (-3, 0, 0), "Head": (-4, 0, 0)}),
    (37, "mouth", (120, 42), (-1.0, 0.2, 0.3), {"Torso": (-3, 0, 0), "Neck": (-5, 0, 0), "Head": (-8, 0, 0)}),
    (41, "mouth", (122, 42), (-1.0, 0.2, 0.3), {"Torso": (-3, 0, 0), "Neck": (-5, 0, 0), "Head": (-9, 0, 0)}),
    (44, (-0.34, -0.72, 1.42), (-0.2, 0.6, 1.0), (-1.0, 0.2, -0.2), {"Head": (-2, 0, 0)}),
    (46, (-0.62, -0.42, 1.36), (-0.7, 0.4, 0.6), (-0.6, 0.8, -0.3), {"Torso": (2, 0, -6), "Head": (0, 0, -8)}),
]
# The left hand at the cap: its wrist this far from the lip (world), its fingers pointing at the cap; then a twist.
CAP_WRIST = Vector((0.15, -0.02, 0.1))
CAP_TWIST = -70.0  # degrees about the bottle's axis between the grab (13) and cap_off (17)
LEFT_POLE = Vector((1.0, 0.2, -0.5))


def _vector3(text):
    """A Godot `Vector3(x, y, z)` as written in a .tres."""
    return Vector([float(x) for x in text[text.index("(") + 1 : text.rindex(")")].split(",")])


def bottle():
    """(weapon, lip): the bottle node's transform under the hand bone (the solved grip's `hold` at the hold's
    `model_scale`, as `soldier_clips.game_grip`) and its lip in the model's own space (the hold's `muzzle`)."""
    h = sc._tres(sc.GAME / "gameplay/player/holds" / f"{HOLD}.tres")
    scale = float(h["model_scale"])
    g = sc._tres(sc.GAME / "gameplay/player/grips" / f"{HOLD}.tres")
    assert abs(float(g["model_scale"]) - scale) < 1e-6, f"grips/{HOLD}.tres was solved at another size: solve again"
    return sc._transform(g["hold"]) @ Matrix.Scale(scale, 4), _vector3(h["muzzle"])


def _tip(tip, side):
    """The axis `tip` degrees from upright toward his face (+Y), its bottom `side` degrees round to his right (the
    axis then leans to his left, +X)."""
    t, s = math.radians(tip), math.radians(side)
    return Vector((math.sin(s) * math.sin(t), math.cos(s) * math.sin(t), math.cos(t)))


def _hold(arm, weapon, lip_local, hand_ref, axis_ref, lip, axis, pole):
    """Turn the right hand so the bottle's axis is `axis` (the least turn from the aim's hand), then reach the arm so
    the lip lands on `lip`. Returns how far the hand ended from its goal (metres)."""
    axis = Vector(axis).normalized()
    hand = axis_ref.rotation_difference(axis).to_matrix() @ hand_ref
    model = hand @ weapon.to_3x3()
    origin = Vector(lip) - model @ lip_local
    goal = origin - hand @ weapon.translation
    miss = sc._reach(arm, ("UpperArm.R", "LowerArm.R", "Index1.R"), goal, Vector(pole).normalized())
    sc._set_world_rot(arm, "Index1.R", hand)
    return miss


def _lip_now(arm, weapon, lip_local):
    return sc._bone_matrix(arm, "Index1.R") @ weapon @ lip_local


def _axis_now(arm, weapon):
    m = sc._bone_matrix(arm, "Index1.R") @ weapon
    return (m.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()


def drink(arm, up, idle, idle_mid, aim):
    """Write Drink_Perk; returns a report (each key's hand miss and the lip's distance from the mouth)."""
    weapon, lip_local = bottle()
    # The hand and the bottle's axis in the gun hold: every hand turn below is the least turn from there.
    gl.apply_pose(arm, aim)
    hand_ref = sc._world(arm, "Index1.R")[0]
    axis_ref = _axis_now(arm, weapon)
    # The mouth in the Head bone's frame, from Idle frame 0.
    gl.apply_pose(arm, idle)
    mouth_local = sc._bone_matrix(arm, "Head").inverted() @ MOUTH
    print("DRINK mouth in the Head bone's frame", [round(v, 4) for v in mouth_local])

    keys = [(0, aim), (4, sc.blend(aim, idle_mid, 0.55))]
    report = {}
    for frame, lip, axis, pole, spine in KEYS:
        pose = sc.offset(idle_mid, **{k.replace(".", "_"): v for k, v in spine.items()})
        gl.apply_pose(arm, pose)
        if lip == "mouth":
            lip = sc._bone_matrix(arm, "Head") @ mouth_local
            axis = _tip(*axis)
        miss = _hold(arm, weapon, lip_local, hand_ref, axis_ref, lip, axis, pole)
        if frame in (13, 17):
            # The left hand on the cap, its fingers toward it; at cap_off turned about the bottle's axis.
            at = _lip_now(arm, weapon, lip_local)
            sc._reach(arm, ("UpperArm.L", "LowerArm.L", "Index1.L"), at + CAP_WRIST, LEFT_POLE)
            r, wrist = sc._world(arm, "Index1.L")
            fingers = r @ Vector((0.0, 1.0, 0.0))
            sc._turn(arm, "Index1.L", fingers, (at - wrist).normalized())
            if frame == 17:
                r, _w = sc._world(arm, "Index1.L")
                twist = Matrix.Rotation(math.radians(CAP_TWIST), 3, _axis_now(arm, weapon))
                sc._set_world_rot(arm, "Index1.L", twist @ r)
        got = _lip_now(arm, weapon, lip_local)
        report[frame] = {"hand_miss": round(miss, 3), "lip_off": round((got - Vector(lip)).length, 3)}
        keys.append((frame, sc._read_pose(arm, pose)))
    keys += [(50, sc.blend(keys[-1][1], idle_mid, 0.6)), (53, idle_mid), (56, sc.blend(idle, aim, 0.45)),
             (FRAMES, aim)]  # fmt: skip
    sc.write(arm, "Drink_Perk", keys, up, "upper", False, "Drink", dict(EVENTS))
    print("DRINK", report)
    return report
