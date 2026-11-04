"""The Soldier's forearms, shortened at rest (Deadnight #978): the kit arm is too long for the body.

Not run on its own: `build_soldier.py` and `build_soldier_parts.py` call `shorten_forearms` on the imported kit
Soldier, before any clip is authored, so the skeleton every file carries, the meshes cut from the body and the clips
solved by reach (soldier_clips.py) all have the one arm.

The kit Soldier's arm is 0.547 of his height (upper arm 0.388, forearm 0.440, hand 0.384 kit metres against 2.22),
its forearm longer than its upper arm, and standing (Idle) his fingertips hang below his knees, 0.45 m under the
crotch; the Hazmat and the Enemy share the bones. The forearm is made `FOREARM` of its length: each wrist moves along
the forearm toward the elbow, the hand bones and the hand's skin with it, the forearm's skin is drawn in along it in
proportion to how far it is from the elbow, and a vertex shared by the forearm and a hand bone moves by its weights.
The hand (the oversized mitt the grips are solved on) and the upper arm keep their size, so every grip holds.
"""

import bpy
from mathutils import Vector

# The forearm's share of the kit's (0.440 kit metres): no longer than the upper arm (0.388), as a person's is shorter.
FOREARM = 0.80
FINGERS = ("Index", "Middle", "Pinky", "Thumb")
# The kit's elbow and wrist along the arm at rest (|x| of the LowerArm and finger joints, kit metres, the arms along X).
KIT_ELBOW_X, KIT_WRIST_X = 0.538, 0.978


def along(x):
    """Where a place `x` along the kit's arm at rest (|x|, kit metres, measured before the forearm was shortened) is
    now: the upper arm's do not move, the forearm's are drawn toward the elbow, the hand's move with the wrist. The
    parts build's rules that pick a place along the arm (the cuff, the wrist seam) are written in the kit's numbers
    and read through this."""
    a = abs(x)
    if a > KIT_WRIST_X:
        a -= (KIT_WRIST_X - KIT_ELBOW_X) * (1.0 - FOREARM)
    elif a > KIT_ELBOW_X:
        a = KIT_ELBOW_X + (a - KIT_ELBOW_X) * FOREARM
    return a if x >= 0 else -a


SIDES = ("L", "R")


def _hand_bones(arm, side):
    return [b.name for b in arm.data.bones if b.name.startswith(FINGERS) and b.name.endswith("." + side)]


def shorten_forearms(arm, factor=FOREARM):
    """Shorten both forearms of `arm` (at rest) and of every mesh skinned to it, to `factor` of their length.

    Returns {side: metres the wrist moved, in the armature's own units}."""
    if factor == 1.0:
        return {}
    rest = arm.data.bones
    moves = {}
    for side in SIDES:
        elbow = rest[f"LowerArm.{side}"].head_local.copy()
        wrist = rest[f"Middle1.{side}"].head_local.copy()
        length = (wrist - elbow).length
        moves[side] = (elbow, (wrist - elbow) / length, length, length * (1.0 - factor))

    # The meshes first, from the rest weights (armature space).
    inv = arm.matrix_world.inverted()
    for o in bpy.data.objects:
        if o.type != "MESH" or not any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers):
            continue
        names = [g.name for g in o.vertex_groups]
        to_arm = inv @ o.matrix_world
        to_mesh = to_arm.inverted()
        for v in o.data.vertices:
            total = 0.0
            shift = Vector()
            co = to_arm @ v.co
            for g in v.groups:
                name = names[g.group]
                side = name[-1:] if name[-2:-1] == "." else ""
                if side not in moves or g.weight <= 0.0:
                    total += g.weight
                    continue
                elbow, along, length, delta = moves[side]
                if name.startswith(FINGERS):
                    shift -= along * delta * g.weight
                elif name.startswith("LowerArm"):
                    t = min(max((co - elbow).dot(along) / length, 0.0), 1.0)
                    shift -= along * delta * t * g.weight
                total += g.weight
            if total > 0.0 and shift.length > 0.0:
                v.co = to_mesh @ (co + shift / total)
        o.data.update()

    # Then the bones: the hand's move with the wrist, the forearm's tail with them.
    active = bpy.context.view_layer.objects.active
    mode = arm.mode
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for side, (_elbow, along, _length, delta) in moves.items():
        offset = along * delta
        hand = _hand_bones(arm, side)
        connected = {n: eb[n].use_connect for n in hand}
        for n in hand:
            eb[n].use_connect = False
        lower = eb[f"LowerArm.{side}"]
        lower.tail = lower.tail - offset
        for n in hand:
            eb[n].head = eb[n].head - offset
            eb[n].tail = eb[n].tail - offset
        for n, c in connected.items():
            eb[n].use_connect = c
    bpy.ops.object.mode_set(mode="OBJECT" if mode != "EDIT" else mode)
    bpy.context.view_layer.objects.active = active
    return {side: m[3] for side, m in moves.items()}
