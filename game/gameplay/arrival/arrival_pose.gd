class_name ArrivalPose
extends RefCounted
## The Soldier's pose on the rope (#1057), made by script from the standing pose: the arms up the
## rope, the legs hanging a little apart, the body turning a little with the sway; and the blend
## back
## to the standing pose as the boots reach the ground. The model has no rope clip, and the show is
## watched from 25 m, so a pose built from a few directions is all it needs.
##
## The Soldier's skeleton is Blender's: +Z up, the character's left is +X, forward is -Y. A bone is
## made to point along a direction of that space (`_aim`), parents first.

## The idle clip the standing pose is taken from, a frame in.
const IDLE := "Idle"
## What each limb bone points along on the rope, parent first: (bone, the bone after it, direction).
## Both arms go up the rope in front of the face and the hands meet over the head; the knees bend
## a little and the legs hang apart.
const ROPE_AIMS: Array = [
	["UpperArm.L", "LowerArm.L", Vector3(0.02, -0.28, 1.0)],
	["LowerArm.L", "Index1.L", Vector3(-0.2, -0.12, 1.0)],
	["UpperArm.R", "LowerArm.R", Vector3(-0.02, -0.28, 1.0)],
	["LowerArm.R", "Index1.R", Vector3(0.2, -0.12, 1.0)],
	["UpperLeg.L", "LowerLeg.L", Vector3(0.16, -0.42, -1.0)],
	["LowerLeg.L", "", Vector3(0.1, 0.18, -1.0)],
	["UpperLeg.R", "LowerLeg.R", Vector3(-0.1, -0.2, -1.0)],
	["LowerLeg.R", "", Vector3(-0.06, 0.12, -1.0)],
]

var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _idle: Dictionary = {}
var _rope: Dictionary = {}
var _feet: Dictionary = {}
var _rope_feet: Dictionary = {}


## Takes the standing pose of `model` (an assembled Soldier) and builds the rope pose from it; stops
## the model's own animation, which would write over both.
func setup(model: Node) -> bool:
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null:
		return false
	if _player != null and _player.has_animation(IDLE):
		_player.play(IDLE)
		_player.seek(0.2, true)
	_idle = _read()
	for foot in ["Foot.L", "Foot.R"]:
		var bone := _skeleton.find_bone(foot)
		if bone >= 0:
			_feet[bone] = _skeleton.get_bone_pose_position(bone)
	if _player != null:
		_player.stop()
		_player.active = false
	_rope = _build_rope()
	return true


## The pose of the moment: `stood` 0 is the rope, 1 the standing pose; `sway` turns the body a
## little about its vertical, radians.
func apply(stood: float, sway: float) -> void:
	if _skeleton == null:
		return
	for bone: int in _idle:
		var from: Quaternion = _rope.get(bone, _idle[bone])
		_skeleton.set_bone_pose_rotation(bone, from.slerp(_idle[bone], stood))
	for bone: int in _feet:
		var hung: Vector3 = _rope_feet.get(bone, _feet[bone])
		_skeleton.set_bone_pose_position(bone, hung.lerp(_feet[bone], stood))
	var hips := _skeleton.find_bone("Body")
	if hips >= 0 and _idle.has(hips):
		var turn := Quaternion(Vector3.BACK, sway * (1.0 - stood))
		_skeleton.set_bone_pose_rotation(
			hips, (_rope.get(hips, _idle[hips]) as Quaternion).slerp(_idle[hips], stood) * turn
		)


func _read() -> Dictionary:
	var pose := {}
	for bone in _skeleton.get_bone_count():
		pose[bone] = _skeleton.get_bone_pose_rotation(bone)
	return pose


## The rope pose: every bone's rotation of the standing pose, but for the limbs, which are aimed.
func _build_rope() -> Dictionary:
	var rope := _idle.duplicate()
	for bone: int in _idle:
		_skeleton.set_bone_pose_rotation(bone, _idle[bone])
	for aim: Array in ROPE_AIMS:
		var bone := _skeleton.find_bone(aim[0])
		if bone < 0:
			continue
		_aim(
			bone,
			_skeleton.find_bone(aim[1]) if aim[1] != "" else _only_child(bone),
			(aim[2] as Vector3).normalized()
		)
		rope[bone] = _skeleton.get_bone_pose_rotation(bone)
	_hang_feet()
	for bone: int in _idle:
		_skeleton.set_bone_pose_rotation(bone, _idle[bone])
	return rope


func _only_child(bone: int) -> int:
	var children := _skeleton.get_bone_children(bone)
	return children[0] if not children.is_empty() else -1


## Points `bone` along `direction` (the skeleton's space) by turning it from where its parent's
## current pose leaves it; `child` gives the bone's own axis.
func _aim(bone: int, child: int, direction: Vector3) -> void:
	if child < 0:
		return
	var rest_here := _skeleton.get_bone_global_rest(bone)
	var along := (
		(
			rest_here.basis.inverse()
			* (_skeleton.get_bone_global_rest(child).origin - rest_here.origin)
		)
		. normalized()
	)
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := (
		_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	)
	var current := parent_basis * _skeleton.get_bone_rest(bone).basis
	var turn := Quaternion(current * along, direction)
	var wanted := Basis(turn) * current
	_skeleton.set_bone_pose_rotation(
		bone, (parent_basis.inverse() * wanted).get_rotation_quaternion()
	)


## The feet follow the legs: each foot bone (a child of the root, not of the leg) goes to the end of
## its shin, which is as long as the shin and the foot are apart in the standing pose.
func _hang_feet() -> void:
	_rope_feet.clear()
	for pair in [["Foot.L", "LowerLeg.L"], ["Foot.R", "LowerLeg.R"]]:
		var foot := _skeleton.find_bone(pair[0])
		var shin := _skeleton.find_bone(pair[1])
		if foot < 0 or shin < 0:
			continue
		var length := (
			(
				_skeleton.get_bone_global_rest(foot).origin
				- _skeleton.get_bone_global_rest(shin).origin
			)
			. length()
		)
		var knee := _skeleton.get_bone_global_pose(shin).origin
		var end := knee + _aim_of(pair[1]) * length
		var root := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(foot))
		_rope_feet[foot] = root.affine_inverse() * end


func _aim_of(bone_name: String) -> Vector3:
	for aim: Array in ROPE_AIMS:
		if aim[0] == bone_name:
			return (aim[2] as Vector3).normalized()
	return Vector3.DOWN
