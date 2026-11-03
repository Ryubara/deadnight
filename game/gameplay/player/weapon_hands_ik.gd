class_name WeaponHandsIK
extends SkeletonModifier3D
## Poses the Soldier's arms on his weapon: the right hand on the grip, the left on the fore-end,
## the stock at the shoulder and the barrel along the camera's aim. A child of the Skeleton3D, it
## runs after the clips and blends in by `weight` (0: the clip's arms, 1: this pose).
##
## The weapon rides the right hand (`hand_hold`, the kit's grip). The aim pose is described as a
## world transform of the weapon (`weapon_target`), the right hand follows from it, and two-bone
## IK reaches both hands there. Pure geometry on the current pose: no randomness, no clock.

const RIGHT: Array[String] = ["UpperArm.R", "LowerArm.R", "Index1.R"]
## The bone the stance turns (both shoulders hang from it).
const CHEST := "Torso"
const LEFT: Array[String] = ["UpperArm.L", "LowerArm.L", "Index1.L"]
## Every bone the pose turns: the chest and both arms with their hands.
const BLENDED: Array[String] = [CHEST] + RIGHT + LEFT
## Points the elbows out and down: this fraction of the shoulder width, plus straight down.
const ELBOW_OUT := 0.45
## How far the support hand's bone sits behind the fore-end it holds, in metres.
const SUPPORT_HAND_BACK := 0.07
## How much of the view's pitch the chest takes when the player looks up or down (#110): the
## upper body leans with the aim, the arms take the rest; at most `CHEST_PITCH_MAX` radians.
const CHEST_PITCH_SHARE := 0.5
const CHEST_PITCH_MAX := deg_to_rad(40.0)
## How far ahead of the camera the barrel meets the crosshair's ray, in metres.
const CONVERGE_DISTANCE := 12.0
## At the hip the barrel meets the crosshair's ray as well, while the view is near the body's
## heading: fully up to `HIP_CONVERGE_FULL` between the two, fading to nothing (the barrel along the
## body, as the pivot rules turn it) at `HIP_CONVERGE_NONE`, so a view behind the body never swings
## the gun round (`hip_share()`).
const HIP_CONVERGE_FULL := deg_to_rad(30.0)
const HIP_CONVERGE_NONE := deg_to_rad(90.0)

## How far the arms and the chest are on this pose, 0 (the clip's) to 1. The blend is done here,
## bone by bone, and not by the modifier's own `influence` (left at 1): the engine blends the chest
## and the hand by it but draws the upper and lower arms in this pose at any influence while the
## modifier is on, so the arms snapped to the clip's the frame the modifier went off (#619).
var weight := 1.0
## The weapon's hold (size, rest and support point).
var hold: WeaponHold
## The hold of the weapon on the hand bone (the weapon's `HandGrip.hold`, or the kit's), in the
## bone's space.
var hand_hold := Transform3D.IDENTITY
## The weapon's grip: where the left hand bone goes on it and how it is turned (`left_hand`, solved
## from the model's `Support` socket), or null (the left hand reaches `hold.support`).
var grip: HandGrip
## Where the weapon points: yaw and pitch in radians (the camera's).
var aim_yaw := 0.0
var aim_pitch := 0.0
## The barrel turns in a little to meet the crosshair's ray `CONVERGE_DISTANCE` ahead of the camera
## (the camera sits over the shoulder, the muzzle does not): `converge_on` is that point, and
## `converge` (0 to 1, the aim weight) is how far the aim turns toward it, so the pose eases into
## and out of it and never jumps. At the hip (`converge` 0) `hip_converge` does the same while the
## view is near the body's heading: the pose uses the larger of the two.
var converge := 0.0
var hip_converge := 0.0
var converge_on := Vector3.ZERO
## How far the weapon is tilted down for a reload, 0 to 1, and the angle of the full tilt in
## degrees. The pitch is added to the hold's, about the grip, so the pose it tilts from is the
## aim weight's (hip or aim) and it returns to that pose.
var reload_dip := 0.0
var reload_tilt_deg := 35.0
## Recoil of the last shot, 0 to 1: the weapon kicks back and up.
var recoil := 0.0
## Metres the weapon kicks back at full recoil, and degrees it kicks up.
var recoil_back := 0.05
var recoil_up_deg := 4.0
## The weapon's pose and the left hand bone's the last modification reached for, in the
## skeleton's space (read them with `solved_target()` and `solved_left()`).
var _solved_target := Transform3D.IDENTITY
var _solved_left := Transform3D.IDENTITY


## The weapon's pose the last modification reached for, in the world where the body is now (for
## tests: after the frame the skeleton hands back the clip's pose, and `weapon_target` reads that,
## without the stance's turn).
func solved_target() -> Transform3D:
	return get_skeleton().global_transform * _solved_target


## The left hand bone's pose the last modification reached for, likewise.
func solved_left() -> Transform3D:
	return get_skeleton().global_transform * _solved_left


## The aim basis: the camera's, whose -Z is the crosshair ray.
func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(aim_pitch, aim_yaw, 0.0))


## Where the weapon rests in the world (origin the grip, muzzle along its -X), from the shoulder
## joint of the current pose. Needs the skeleton's pose to be current.
func weapon_target() -> Transform3D:
	var skeleton := get_skeleton()
	var aim := aim_basis()
	var shoulder := _world(skeleton, skeleton.find_bone(RIGHT[0])).origin
	if not converge_on.is_zero_approx():
		var toward := converge_on - (shoulder + aim * hold.grip_offset)
		var meets := Basis.looking_at(toward.normalized(), Vector3.UP)
		aim = aim.slerp(meets, clampf(maxf(converge, hip_converge), 0.0, 1.0))
	var pitch := hold.pitch_offset_deg + recoil * recoil_up_deg - reload_dip * reload_tilt_deg
	var raise := Basis(aim.x, deg_to_rad(pitch))
	var forward_turn := Basis(Vector3.UP, -PI / 2.0)
	var offset := hold.grip_offset + Vector3(0.0, 0.0, recoil * recoil_back)
	return Transform3D(raise * aim * forward_turn, shoulder + aim * offset)


## How far the barrel turns toward the crosshair's point at the hip, 0 to 1, when the view is `gap`
## radians from the body's heading: all of it near the body, none behind it, a smooth fade between.
static func hip_share(gap: float) -> float:
	return 1.0 - smoothstep(HIP_CONVERGE_FULL, HIP_CONVERGE_NONE, absf(gap))


## The support hand's point in the world, for the weapon at `target`.
func support_point(target: Transform3D) -> Vector3:
	return target.origin + target.basis * (hold.support * _scale())


## The left hand bone's world pose on the weapon whose node is at `weapon` (scale included; the
## grip's `left_hand` is in the model's own space): rotation orthonormal, origin where the bone
## goes.
func left_hand_on(weapon: Transform3D) -> Transform3D:
	var pose := weapon * grip.left_hand
	return Transform3D(pose.basis.orthonormalized(), pose.origin)


func _scale() -> float:
	return hold.model_scale * absf(get_skeleton().global_basis.get_scale().x)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null or not hold.shouldered or weight <= 0.0:
		return
	var clip := _pose_of(skeleton)
	_solve(skeleton)
	if weight < 1.0:
		for bone: int in clip:
			var solved := skeleton.get_bone_pose_rotation(bone)
			skeleton.set_bone_pose_rotation(bone, (clip[bone] as Quaternion).slerp(solved, weight))


## The local rotation of every bone this pose turns, as the clips left it.
func _pose_of(skeleton: Skeleton3D) -> Dictionary:
	var pose := {}
	for name: String in BLENDED:
		var bone := skeleton.find_bone(name)
		pose[bone] = skeleton.get_bone_pose_rotation(bone)
	return pose


## The pose itself, at full weight: the chest's turn and lean, then both arms.
func _solve(skeleton: Skeleton3D) -> void:
	if hold.stance_turn_deg != 0.0:
		_turn_chest(skeleton, hold.stance_turn_deg)
	_pitch_chest(skeleton)
	var target := weapon_target()
	_solved_target = skeleton.global_transform.affine_inverse() * target
	var right_shoulder := _world(skeleton, skeleton.find_bone(RIGHT[0])).origin
	var left_shoulder := _world(skeleton, skeleton.find_bone(LEFT[0])).origin
	var side := (right_shoulder - left_shoulder).normalized()
	var model_scale := absf(skeleton.global_basis.get_scale().x)
	# The right hand: the weapon's world pose through the kit's grip gives the hand bone's pose.
	var hand_basis := target.basis * hand_hold.basis.inverse()
	var hand_origin := target.origin - hand_basis * (hand_hold.origin * model_scale)
	_reach(skeleton, RIGHT, hand_origin, side * ELBOW_OUT + Vector3.DOWN, hand_basis, false)
	# The left hand: on the fore-end, turned to hold it (the grip's), or reaching the support point.
	# It goes where the weapon is now, after the right arm (which may fall a little short of the
	# target), so the two hands always hold the same weapon.
	if grip != null and grip.has_left:
		var right_hand := (
			skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(RIGHT[2]))
		)
		var weapon := right_hand * hand_hold.scaled_local(Vector3.ONE * hold.model_scale)
		var left := left_hand_on(weapon)
		_solved_left = skeleton.global_transform.affine_inverse() * left
		_reach(skeleton, LEFT, left.origin, -side * ELBOW_OUT + Vector3.DOWN, left.basis, false)
	elif hold.support != Vector3.ZERO:
		_reach(
			skeleton, LEFT, support_point(target), -side * ELBOW_OUT + Vector3.DOWN, Basis(), true
		)


## Turns the chest `degrees` about the world's up, the left shoulder forward (toward the aim): a
## two-handed gun's stance, so the short left arm reaches the fore-end. The right shoulder goes back
## with it, and the weapon's place is taken from it after the turn.
func _turn_chest(skeleton: Skeleton3D, degrees: float) -> void:
	var chest := skeleton.find_bone(CHEST)
	var left := _world(skeleton, skeleton.find_bone(LEFT[0])).origin
	var right := _world(skeleton, skeleton.find_bone(RIGHT[0])).origin
	var ahead := -aim_basis().z
	# The turn's sense that brings the left shoulder forward along the aim.
	var across := left - right
	var sense := signf(Vector3.UP.dot(across.cross(ahead)))
	var turn := Basis(Vector3.UP, deg_to_rad(degrees) * sense)
	_set_world_basis(skeleton, chest, turn * _world(skeleton, chest).basis)


## Leans the chest with the view's pitch (a share of it, clamped), about the aim's right: looking up
## the upper body tips back, looking down it bends over the weapon. Pure geometry on `aim_pitch`.
func _pitch_chest(skeleton: Skeleton3D) -> void:
	var lean := clampf(aim_pitch * CHEST_PITCH_SHARE, -CHEST_PITCH_MAX, CHEST_PITCH_MAX)
	if is_zero_approx(lean):
		return
	var chest := skeleton.find_bone(CHEST)
	var turn := Basis(aim_basis().x.normalized(), lean)
	_set_world_basis(skeleton, chest, turn * _world(skeleton, chest).basis)


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
