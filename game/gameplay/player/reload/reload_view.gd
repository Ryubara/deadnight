class_name ReloadView
extends RefCounted
## A reload as one body draws it (#683): the clock of the weapon's `ReloadMotion` over the reload's
## seconds, the pose it gives the arms (`WeaponHandsIK.reload`), the weapon's moving part and the
## ammunition in the left hand. `PlayerAnimation` owns one and steps it every frame; every client
## draws every player's reload from the same `reload_started` event, so the player's own and a
## teammate's are the same motion.

## How fast the pose comes in and goes, per second (exponential): a reload cut short (a swap) lets
## the weapon and the left hand back in a few frames instead of jumping.
const FOLLOW := 30.0
## The bone the ammunition rides on (the left hand's, as `PlayerAnimation.HAND_BONE` is the
## right's).
const LEFT_HAND_BONE := "Index1.L"

## The pose now, eased between the motion's keys, and how far it is in, 0 to 1.
var pose := ReloadPose.new()
var weight := 0.0
## The weapon's moving part (a drum, the barrels, the cylinder, the lever; null for none) and the
## ammunition the left hand brings (null for none).
var part: Node3D
var ammo: Node3D
## The left gun's moving part of a dual weapon (the same part in the second model), or null.
var offpart: Node3D

var _motion: ReloadMotion
var _left := 0.0
var _length := 1.0
var _part_rest := Transform3D.IDENTITY
var _offpart_rest := Transform3D.IDENTITY
var _mount: BoneAttachment3D
## The ammunition is the part, taken where it was (the drum): placed by the hand, not the motion.
var _ammo_from_part := false
var _model_scale := 1.0


## The mount for the ammunition on `skeleton`'s left hand bone.
func _init(skeleton: Skeleton3D) -> void:
	_mount = BoneAttachment3D.new()
	_mount.name = "AmmoMount"
	_mount.bone_name = LEFT_HAND_BONE
	skeleton.add_child(_mount)


## The weapon `weapon_id` is now `weapon` (its model in the hand, at `model_scale`): its motion,
## its moving part and its ammunition. A class or a weapon that does not reload has none. A dual
## weapon's second gun is `offhand`: its part moves with the first's.
func setup(
	weapon_id: StringName, weapon: Node3D, model_scale: float, offhand: Node3D = null
) -> void:
	_motion = ReloadMotion.for_weapon(weapon_id) if weapon_id != &"" else null
	_model_scale = model_scale
	part = null
	offpart = null
	_part_rest = Transform3D.IDENTITY
	_offpart_rest = Transform3D.IDENTITY
	if ammo != null:
		ammo.free()
		ammo = null
	_ammo_from_part = false
	if _motion == null or weapon == null:
		return
	if _motion.part_node != &"":
		part = weapon.find_child(String(_motion.part_node), true, false) as Node3D
		if part != null:
			_part_rest = part.transform
		if offhand != null:
			offpart = offhand.find_child(String(_motion.part_node), true, false) as Node3D
			if offpart != null:
				_offpart_rest = offpart.transform
	if _motion.ammo_scene != "":
		ammo = (load(_motion.ammo_scene) as PackedScene).instantiate() as Node3D
		ammo.name = "Ammo"
		ammo.visible = false
		_mount.add_child(ammo)
		_place_ammo()


## A reload of `seconds` starts.
func start(seconds: float) -> void:
	_length = maxf(seconds, 0.01)
	_left = _length
	if ammo != null and _ammo_from_part:
		_place_ammo()
		_ammo_from_part = false


func cancel() -> void:
	_left = 0.0


func running() -> bool:
	return _left > 0.0


## One frame: the clock, the pose into `hands`, the part and the ammunition (shown only while the
## weapon `weapon_shown` is).
func step(delta: float, hands: WeaponHandsIK, weapon_shown: bool) -> void:
	var target := 0.0
	if _left > 0.0 and _motion != null:
		_left = maxf(_left - delta, 0.0)
		_motion.sample(1.0 - _left / _length, pose)
		target = 1.0 if _left > 0.0 else 0.0
	weight = lerpf(weight, target, 1.0 - exp(-FOLLOW * delta))
	if target == 0.0 and weight < 0.001:
		weight = 0.0
		pose.clear()
	hands.reload = pose if weight > 0.0 else null
	hands.reload_weight = weight
	hands.part_rest = _part_rest
	_pose_part(weapon_shown)


## How far the left hand is off its hold for the reload now, 0 to 1 (its fingers let go).
func left_away() -> float:
	return pose.left * weight


## The part opened as far as the pose says (closed again as a cut-short reload eases out), and the
## ammunition in the left hand while the pose holds it.
func _pose_part(weapon_shown: bool) -> void:
	var holding := weight > 0.5 and pose.ammo
	if part != null and _motion != null:
		part.transform = _motion.part_transform(_part_rest, pose.part * weight)
		part.visible = pose.part_shown or weight <= 0.5
		if offpart != null:
			offpart.transform = _motion.part_transform(_offpart_rest, pose.part * weight)
			offpart.visible = part.visible
	if ammo == null:
		return
	if holding and not ammo.visible and _motion.ammo_is_part and part != null:
		# The hand takes the part where it is: the drum stays in the fist as it was on the gun.
		ammo.global_transform = part.global_transform
		_ammo_from_part = true
	ammo.visible = holding and weapon_shown


## The ammunition's place on the left hand bone, at the weapon's size (`ammo_size` times it).
func _place_ammo() -> void:
	var turn := Basis.from_euler(_motion.ammo_turn * PI / 180.0)
	var size := _model_scale * _motion.ammo_size
	ammo.transform = Transform3D(turn, _motion.ammo_offset).scaled_local(Vector3.ONE * size)
