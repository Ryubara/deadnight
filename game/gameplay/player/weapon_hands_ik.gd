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
## The hips and the legs that give the belt's place and the body's frame for a reload.
const HIPS := "Hips"
const LEGS: Array[String] = ["UpperLeg.L", "UpperLeg.R"]
## Every bone the pose turns: the chest and both arms with their hands.
const BLENDED: Array[String] = [CHEST] + RIGHT + LEFT
## Points the elbows out and down: this fraction of the shoulder width, plus straight down.
const ELBOW_OUT := 0.45
## The elbows of a two-handed gun's hold (a stance turned), further out: with #978's shorter
## forearm the shouldered hold folded the right forearm into the jacket (night probe: 68 mm in a
## jacket firing the pump at 0.45, 45 mm at 1.0). One-handed holds and the reload keep `ELBOW_OUT`.
const ELBOW_OUT_TWO_HANDED := 1.0
## A two-handed weapon whose fore-end is out of the left arm's reach slides back along its barrel
## until the left hand reaches it (#978): in this many passes, by at most `PULL_MAX` metres, to
## `PULL_SLACK` metres inside the arm's full stretch (the two-bone reach stops 1 mm short of it).
const PULL_PASSES := 2
const PULL_MAX := 0.12
const PULL_SLACK := 0.002
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

## The reflection that makes a left-hand thing from a right-hand one: the rig is an exact mirror
## (each left bone is its right one with x turned about), so a weapon held mirrored in the left hand
## sits there as its right-hand place with this applied, and the model itself is flipped across its
## own side (`MODEL_FLIP`).
const MIRROR := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
const MODEL_FLIP := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))

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
## The reload's pose now (`ReloadMotion`, #683), or null, and how far it is in, 0 to 1 (a reload
## cut short by a swap eases out). The weapon's move and turn are added to the hold's, about the
## grip, so the pose it starts from is the aim weight's (hip or aim) and it returns to that pose;
## the left hand goes to the reload's points on the weapon or at the belt.
var reload: ReloadPose
var reload_weight := 0.0
## The weapon's moving part at rest, in the model's units (for a hand point on the part).
var part_rest := Transform3D.IDENTITY
## Recoil of the last shot, 0 to 1: the weapon kicks back and up.
var recoil := 0.0
## The left gun's recoil of a dual weapon (the shots alternate hands, so each gun kicks on its own).
var recoil_left := 0.0
## Metres the weapon kicks back at full recoil, and degrees it kicks up.
var recoil_back := 0.05
var recoil_up_deg := 4.0
## The weapon's pose and the left hand bone's the last modification reached for, in the
## skeleton's space (read them with `solved_target()` and `solved_left()`).
var _solved_target := Transform3D.IDENTITY
var _solved_left := Transform3D.IDENTITY
var _solved_offhand := Transform3D.IDENTITY
## How far the last modification slid the weapon back to bring its fore-end into the left arm's
## reach (metres; `PULL_MAX`), read with `pulled()`.
var _pulled := 0.0


## The weapon's pose the last modification reached for, in the world where the body is now (for
## tests: after the frame the skeleton hands back the clip's pose, and `weapon_target` reads that,
## without the stance's turn).
func solved_target() -> Transform3D:
	return get_skeleton().global_transform * _solved_target


## The left hand bone's pose the last modification reached for, likewise.
func solved_left() -> Transform3D:
	return get_skeleton().global_transform * _solved_left


## How far the last modification slid the weapon back along its barrel so the left hand reached
## its fore-end, in metres (0 when the fore-end was in reach).
func pulled() -> float:
	return _pulled


## The left gun's pose of a dual weapon the last modification reached for, likewise (the rigid
## pose: the model drawn there is flipped across its side).
func solved_offhand() -> Transform3D:
	return get_skeleton().global_transform * _solved_offhand


## The aim basis: the camera's, whose -Z is the crosshair ray.
func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(aim_pitch, aim_yaw, 0.0))


## Where the weapon rests in the world (origin the grip, muzzle along its -X), from the shoulder
## joint of the current pose. Needs the skeleton's pose to be current.
func weapon_target(offhand := false) -> Transform3D:
	var skeleton := get_skeleton()
	var aim := aim_basis()
	var shoulder := _world(skeleton, skeleton.find_bone(LEFT[0] if offhand else RIGHT[0])).origin
	# The left gun of a dual weapon is the right one's mirror: from the left shoulder, out to the
	# left, turned the other way in a reload.
	var side := MIRROR if offhand else Basis.IDENTITY
	var rest := side * hold.grip_offset
	if not converge_on.is_zero_approx():
		var toward := converge_on - (shoulder + aim * rest)
		var meets := Basis.looking_at(toward.normalized(), Vector3.UP)
		aim = aim.slerp(meets, clampf(maxf(converge, hip_converge), 0.0, 1.0))
	var kick := recoil_left if offhand else recoil
	var pitch := hold.pitch_offset_deg + kick * recoil_up_deg
	var raise := Basis(aim.x, deg_to_rad(pitch))
	var forward_turn := Basis(Vector3.UP, -PI / 2.0)
	var offset := rest + Vector3(0.0, 0.0, kick * recoil_back)
	var basis := raise * aim * forward_turn
	if reload != null and reload_weight > 0.0:
		offset += side * reload.weapon_offset * reload_weight
		var turn := reload.weapon_turn
		if offhand:  # the muzzle up stays up; to the left and the top to the left turn the other way
			turn = Vector3(turn.x, -turn.y, -turn.z)
		basis = _reload_turn(aim, turn * reload_weight) * basis
	return Transform3D(basis, shoulder + aim * offset)


## The reload's turn of the weapon about the grip, in the aim's frame (degrees: x the muzzle up,
## y to the left, z the top to the left).
static func _reload_turn(aim: Basis, degrees: Vector3) -> Basis:
	var yaw := Basis(aim.y.normalized(), deg_to_rad(degrees.y))
	var pitch := Basis(aim.x.normalized(), deg_to_rad(degrees.x))
	var roll := Basis(-aim.z.normalized(), deg_to_rad(degrees.z))
	return yaw * pitch * roll


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
	var stance := hold.stance_turn_deg
	if reload != null:
		stance += reload.chest_turn * reload_weight
	if stance != 0.0:
		_turn_chest(skeleton, stance)
	_pitch_chest(skeleton)
	var target := weapon_target()
	var right_shoulder := _world(skeleton, skeleton.find_bone(RIGHT[0])).origin
	var left_shoulder := _world(skeleton, skeleton.find_bone(LEFT[0])).origin
	var side := (right_shoulder - left_shoulder).normalized()
	var out := ELBOW_OUT_TWO_HANDED if hold.stance_turn_deg > 0.0 else ELBOW_OUT
	var model_scale := absf(skeleton.global_basis.get_scale().x)
	var weapon := Transform3D.IDENTITY
	var pulled := 0.0
	for attempt in PULL_PASSES + 1:
		# The right hand: the weapon's world pose through the kit's grip gives the hand bone's pose.
		var hand_basis := target.basis * hand_hold.basis.inverse()
		var hand_origin := target.origin - hand_basis * (hand_hold.origin * model_scale)
		_reach(skeleton, RIGHT, hand_origin, side * out + Vector3.DOWN, hand_basis, false)
		# The left hand goes where the weapon is now, after the right arm (which may fall a little
		# short of the target), so the two hands always hold the same weapon.
		var right_hand := (
			skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(RIGHT[2]))
		)
		weapon = right_hand * hand_hold.scaled_local(Vector3.ONE * hold.model_scale)
		if attempt == PULL_PASSES or hold.dual or grip == null or not grip.has_left:
			break
		# A fore-end out of the left arm's reach (the view far down, #978's shorter forearm): the
		# weapon slides back along its barrel, toward the shoulder, until the left hand reaches it.
		var step := minf(
			_pull_to_reach(skeleton, left_hand_on(weapon).origin, target), PULL_MAX - pulled
		)
		if step <= 0.0:
			break
		target.origin += target.basis.x.normalized() * step
		pulled += step
	_solved_target = skeleton.global_transform.affine_inverse() * target
	_pulled = pulled
	# The left hand: on the fore-end, turned to hold it (the grip's), or reaching the support point.
	if hold.dual:
		_reach_offhand(skeleton, -side * ELBOW_OUT + Vector3.DOWN, model_scale)
	elif grip != null and grip.has_left:
		var left := left_hand_on(weapon)
		_solved_left = skeleton.global_transform.affine_inverse() * left
		_reach(skeleton, LEFT, left.origin, -side * out + Vector3.DOWN, left.basis, false)
	elif hold.support != Vector3.ZERO:
		_reach(
			skeleton, LEFT, support_point(target), -side * ELBOW_OUT + Vector3.DOWN, Basis(), true
		)
	if reload != null and reload_weight > 0.0 and reload.left > 0.0:
		_reach_reload(skeleton, weapon, -side * ELBOW_OUT + Vector3.DOWN)


## The left arm of a dual weapon: the left gun's own place (`weapon_target(true)`) and the left hand
## bone turned so the mirrored gun sits in it as the right gun sits in the right hand. The right
## hand's place is the grip's (`hand_hold`); the left's is its reflection, the rig being an exact
## mirror: the model's side flipped, the bone's frame mirrored.
func _reach_offhand(skeleton: Skeleton3D, pole: Vector3, model_scale: float) -> void:
	var target := weapon_target(true)
	_solved_offhand = skeleton.global_transform.affine_inverse() * target
	var held := hand_hold.basis.orthonormalized()
	var basis := target.basis * MODEL_FLIP * held.inverse() * MIRROR
	var origin := target.origin - basis * (MIRROR * hand_hold.origin * model_scale)
	_solved_left = skeleton.global_transform.affine_inverse() * Transform3D(basis, origin)
	_reach(skeleton, LEFT, origin, pole, basis, false)


## The left hand on the reload's point: reached from the pose the hold left it in, and blended
## from it by the reload's `left` weight bone by bone, so the hand leaves the fore-end (or the
## clip's arm) and comes back without a jump.
func _reach_reload(skeleton: Skeleton3D, weapon: Transform3D, pole: Vector3) -> void:
	var held := {}
	for name: String in LEFT:
		var bone := skeleton.find_bone(name)
		held[bone] = skeleton.get_bone_pose_rotation(bone)
	var a := reload_point(skeleton, weapon, reload.left_from)
	var b := reload_point(skeleton, weapon, reload.left_to)
	var goal := a.origin.lerp(b.origin, reload.left_mix)
	_reach(skeleton, LEFT, goal, pole, Basis(), false)
	# The hand turned as on the fore-end at a point on the weapon, as the arm leaves it at the belt.
	var hand := skeleton.find_bone(LEFT[2])
	var natural := _world(skeleton, hand).basis
	var turn_a := natural if a.basis == Basis() else a.basis
	var turn_b := natural if b.basis == Basis() else b.basis
	var turned := Basis(
		turn_a.get_rotation_quaternion().slerp(turn_b.get_rotation_quaternion(), reload.left_mix)
	)
	_set_world_basis(skeleton, hand, turned)
	_solved_left = (
		skeleton.global_transform.affine_inverse()
		* Transform3D(turned, _world(skeleton, hand).origin)
	)
	var w := clampf(reload.left * reload_weight, 0.0, 1.0)
	if w >= 1.0:
		return
	for bone: int in held:
		var solved := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, (held[bone] as Quaternion).slerp(solved, w))


## Where a reload key puts the left hand bone, in the world: its origin, and its basis on the
## weapon (the grip's `left_hand` turn) or `Basis()` where the arm keeps its own turn (the belt, or
## a weapon with no left grip).
func reload_point(skeleton: Skeleton3D, weapon: Transform3D, key: ReloadKey) -> Transform3D:
	if key.left_space == ReloadKey.Space.BELT:
		var hips := _world(skeleton, skeleton.find_bone(HIPS)).origin
		var legs := (
			_world(skeleton, skeleton.find_bone(LEGS[1])).origin
			- _world(skeleton, skeleton.find_bone(LEGS[0])).origin
		)
		var right := Vector3(legs.x, 0.0, legs.z).normalized()
		var back := right.cross(Vector3.UP)
		var p := key.left_point
		return Transform3D(Basis(), hips + right * p.x + Vector3.UP * p.y + back * p.z)
	var point := key.left_point
	var turn := Basis()
	if key.left_on_part and reload.motion != null:
		point = reload.motion.point_on_part(point, part_rest, reload.part)
		var open := reload.motion.part_transform(part_rest, reload.part)
		turn = open.basis * part_rest.basis.inverse()
	var basis := Basis()
	if grip != null and grip.has_left:
		basis = (weapon.basis.orthonormalized() * turn * grip.left_hand.basis).orthonormalized()
	return Transform3D(basis, weapon * point)


## How far the weapon at `target` must slide back along its barrel (its +X, toward the butt) for
## the left arm to reach `goal` (the left hand bone's place on it), in metres; 0 when it reaches.
func _pull_to_reach(skeleton: Skeleton3D, goal: Vector3, target: Transform3D) -> float:
	var shoulder := _world(skeleton, skeleton.find_bone(LEFT[0])).origin
	var elbow := _world(skeleton, skeleton.find_bone(LEFT[1])).origin
	var wrist := _world(skeleton, skeleton.find_bone(LEFT[2])).origin
	var reach := shoulder.distance_to(elbow) + elbow.distance_to(wrist) - PULL_SLACK
	var r := goal - shoulder
	if r.length() <= reach:
		return 0.0
	# |r + back * s| = reach, the smaller root; past the closest point the slide stops there.
	var back := target.basis.x.normalized()
	var along := r.dot(back)
	var under := along * along - r.length_squared() + reach * reach
	return maxf(-along - sqrt(maxf(under, 0.0)), 0.0)


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
	if reload != null:
		# A positive turn about the aim's right tips the chest back: a lean forward is negative.
		lean -= deg_to_rad(reload.chest_lean * reload_weight)
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
