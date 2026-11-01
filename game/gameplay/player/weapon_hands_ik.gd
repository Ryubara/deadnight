class_name WeaponHandsIK
extends SkeletonModifier3D
## Poses the Soldier's arms on his weapon: the right hand on the grip, the left on the fore-end,
## the stock at the shoulder and the barrel along the camera's aim. A child of the Skeleton3D, it
## runs after the clips and blends in by `influence` (0: the clip's arms, 1: this pose).
##
## The weapon rides the right hand (`hand_hold`, the kit's grip). The aim pose is described as a
## world transform of the weapon (`weapon_target`), the right hand follows from it, and two-bone
## IK reaches both hands there. Pure geometry on the current pose: no randomness, no clock.

const RIGHT: Array[String] = ["UpperArm.R", "LowerArm.R", "Index1.R"]
const LEFT: Array[String] = ["UpperArm.L", "LowerArm.L", "Index1.L"]
## Points the elbows out and down: this fraction of the shoulder width, plus straight down.
const ELBOW_OUT := 0.45
## How far the support hand's bone sits behind the fore-end it holds, in metres.
const SUPPORT_HAND_BACK := 0.07
## How far ahead of the camera the barrel meets the crosshair's ray, in metres.
const CONVERGE_DISTANCE := 12.0

## The weapon's hold (size, rest and support point).
var hold: WeaponHold
## The hold of the weapon on the hand bone (the kit's grip), in the bone's space.
var hand_hold := Transform3D.IDENTITY
## Where the weapon points: yaw and pitch in radians (the camera's).
var aim_yaw := 0.0
var aim_pitch := 0.0
## While aiming the barrel turns in a little to meet the crosshair's ray `CONVERGE_DISTANCE` ahead
## of the camera (the camera sits over the shoulder, the muzzle does not): `converge_on` is that
## point, used when `converging`.
var converging := false
var converge_on := Vector3.ZERO
## Recoil of the last shot, 0 to 1: the weapon kicks back and up.
var recoil := 0.0
## Metres the weapon kicks back at full recoil, and degrees it kicks up.
var recoil_back := 0.05
var recoil_up_deg := 4.0


## The aim basis: the camera's, whose -Z is the crosshair ray.
func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(aim_pitch, aim_yaw, 0.0))


## Where the weapon rests in the world (origin the grip, muzzle along its -X), from the shoulder
## joint of the current pose. Needs the skeleton's pose to be current.
func weapon_target() -> Transform3D:
	var skeleton := get_skeleton()
	var aim := aim_basis()
	var shoulder := _world(skeleton, skeleton.find_bone(RIGHT[0])).origin
	if converging:
		var toward := converge_on - (shoulder + aim * hold.grip_offset)
		aim = Basis.looking_at(toward.normalized(), Vector3.UP)
	var raise := Basis(aim.x, deg_to_rad(hold.pitch_offset_deg + recoil * recoil_up_deg))
	var forward_turn := Basis(Vector3.UP, -PI / 2.0)
	var offset := hold.grip_offset + Vector3(0.0, 0.0, recoil * recoil_back)
	return Transform3D(raise * aim * forward_turn, shoulder + aim * offset)


## The support hand's point in the world, for the weapon at `target`.
func support_point(target: Transform3D) -> Vector3:
	return target.origin + target.basis * (hold.support * _scale())


func _scale() -> float:
	return hold.model_scale * absf(get_skeleton().global_basis.get_scale().x)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null or not hold.shouldered:
		return
	var target := weapon_target()
	var right_shoulder := _world(skeleton, skeleton.find_bone(RIGHT[0])).origin
	var left_shoulder := _world(skeleton, skeleton.find_bone(LEFT[0])).origin
	var side := (right_shoulder - left_shoulder).normalized()
	var model_scale := absf(skeleton.global_basis.get_scale().x)
	# The right hand: the weapon's world pose through the kit's grip gives the hand bone's pose.
	var hand_basis := target.basis * hand_hold.basis.inverse()
	var hand_origin := target.origin - hand_basis * (hand_hold.origin * model_scale)
	_reach(skeleton, RIGHT, hand_origin, side * ELBOW_OUT + Vector3.DOWN, hand_basis, false)
	# The left hand: on the fore-end.
	if hold.support != Vector3.ZERO:
		_reach(
			skeleton, LEFT, support_point(target), -side * ELBOW_OUT + Vector3.DOWN, Basis(), true
		)


## Two-bone IK in the world: the arm `bones` (upper, lower, hand) so the hand bone reaches
## `goal`, the elbow toward `pole`. With a `hand_basis` the hand takes that orientation; with
## `along_forearm` the goal is the fore-end and the hand bone stops `SUPPORT_HAND_BACK` short.
func _reach(
	skeleton: Skeleton3D,
	bones: Array[String],
	goal: Vector3,
	pole: Vector3,
	hand_basis: Basis,
	along_forearm: bool
) -> void:
	var upper := skeleton.find_bone(bones[0])
	var lower := skeleton.find_bone(bones[1])
	var hand := skeleton.find_bone(bones[2])
	for _pass in 2:
		var root := _world(skeleton, upper).origin
		var elbow := _world(skeleton, lower).origin
		var wrist := _world(skeleton, hand).origin
		var upper_length := root.distance_to(elbow)
		var lower_length := elbow.distance_to(wrist)
		var target := goal
		if along_forearm:
			target = goal - (wrist - elbow).normalized() * SUPPORT_HAND_BACK
		var to_target := target - root
		var distance := clampf(
			to_target.length(),
			absf(upper_length - lower_length) + 0.01,
			upper_length + lower_length - 0.001
		)
		var direction := to_target.normalized()
		var along := (
			(upper_length * upper_length - lower_length * lower_length + distance * distance)
			/ (2.0 * distance)
		)
		var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
		var bend := (pole - direction * pole.dot(direction)).normalized()
		var new_elbow := root + direction * along + bend * height
		var reached := root + direction * distance
		_aim_bone(skeleton, upper, elbow - root, new_elbow - root)
		var forearm := _world(skeleton, hand).origin - _world(skeleton, lower).origin
		_aim_bone(skeleton, lower, forearm, reached - new_elbow)
	if hand_basis != Basis():
		_set_world_basis(skeleton, hand, hand_basis)


## Turns `bone` so the direction `from` becomes `to`.
func _aim_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	var turn := Quaternion(from.normalized(), to.normalized())
	var current := _world(skeleton, bone).basis
	_set_world_basis(skeleton, bone, Basis(turn) * current)


func _set_world_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := _world(skeleton, parent).basis
	var local := parent_basis.inverse() * basis
	skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


## The bone's current pose in the world: rotation orthonormal, origin where the bone is.
func _world(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	return Transform3D(pose.basis.orthonormalized(), pose.origin)
