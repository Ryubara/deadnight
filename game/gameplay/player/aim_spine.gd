class_name AimSpine
extends SkeletonModifier3D
## Bends the Soldier's spine with the view's pitch: looking up leans the upper body back, looking
## down leans it forward, so the shoulders (and the stock against the right one) go where the
## camera looks and the gun is not the only thing that turns. A child of the Skeleton3D that runs
## after the clips and before `WeaponHandsIK`, so the arms reach from the bent shoulders.
##
## The clips hold one pitch (docs/design/animation.md); this adds the bend on top of whatever
## they pose, about each bone's own X axis, shared between `Abdomen` and `Torso`. Pure geometry
## on the current pose: no randomness, no clock. `influence` fades it (a full-body clip).

## The bones that bend and the share of the whole bend each takes (they sum to 1): the lower back
## a little, the chest most, so the hips stay with the legs.
const BONES: Array[String] = ["Abdomen", "Torso"]
const SHARES: Array[float] = [0.4, 0.6]
## Which way about a bone's X axis the rig's forward bend goes (-1: the rig's bones point down
## their -Z, so a positive turn about X leans the chest back; measured by `test_aim_spine.gd`).
const FORWARD_SIGN := 1.0

## The view's pitch in radians, up positive (the camera's).
var pitch := 0.0
## How much of the view's pitch the spine takes, and the most it bends either way, in degrees.
var follow := 0.6
var limit_deg := 40.0


## The whole bend for a view pitch, in radians, forward positive: `follow` of the pitch, held to
## `limit_deg` either way. Looking up is a negative (backward) bend.
static func bend_for(view_pitch: float, follow_share: float, limit: float) -> float:
	var limit_rad := deg_to_rad(limit)
	return clampf(-view_pitch * follow_share, -limit_rad, limit_rad)


## The whole bend of the current pose, in radians, forward positive.
func bend() -> float:
	return bend_for(pitch, follow, limit_deg)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var whole := bend()
	for i in BONES.size():
		var bone := skeleton.find_bone(BONES[i])
		if bone < 0:
			continue
		var turn := Quaternion(Vector3.RIGHT, FORWARD_SIGN * whole * SHARES[i])
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * turn)
