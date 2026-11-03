class_name HandGripPose
extends SkeletonModifier3D
## Closes the Soldier's hands on what they hold (Deadnight #460): a child of the Skeleton3D after
## `WeaponHandsIK`, it bends every finger to the held model's `HandGrip` (solved from the model's
## sockets) and keeps the palm whole. The clips never move the fingers, so without it every weapon
## gets the same fist, made for the kit's guns.
##
## The palm is four bones from the wrist (`Index1`, `Middle1`, `Pinky1`, `Thumb1`); the weapon rides
## `Index1.R` and `WeaponHandsIK` turns only that one, so the others are turned with it here (they
## keep their place relative to it: the grip's for the thumb, the rest pose's for the others). Then
## the finger joints take the grip's rotations. The right hand follows `right_weight`, the left
## `left_weight` (the left hand is the grip's only while it holds the weapon). Pure data: no clock.

const ROOTS: Array[String] = ["Middle1", "Pinky1", "Thumb1"]
const HAND := "Index1"

## The grip of what the right hand holds, or null (the clip's fist).
var grip: HandGrip
## How far each hand is on the grip, 0 (the clip's fingers) to 1.
var right_weight := 0.0
var left_weight := 0.0
## The left hand holds a mirror of the weapon the right holds (the dual pistols): its fingers are
## the grip's right-hand ones mirrored (`HandGrip.mirrored`), not the grip's own `left`.
var left_mirrors := false


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_close(skeleton, "R", grip.right if grip != null else {}, right_weight)
	var left := {}
	if grip != null and left_mirrors:
		left = grip.mirrored()
	elif grip != null and grip.has_left:
		left = grip.left
	_close(skeleton, "L", left, left_weight)


func _close(skeleton: Skeleton3D, side: String, fingers: Dictionary, weight: float) -> void:
	var hand := skeleton.find_bone(HAND + "." + side)
	if hand < 0:
		return
	# How far the hand bone is turned off its rest relative to the forearm (by the IK, or a clip).
	var turn := (
		skeleton.get_bone_pose_rotation(hand)
		* skeleton.get_bone_rest(hand).basis.get_rotation_quaternion().inverse()
	)
	for root in ROOTS:
		var bone := skeleton.find_bone(root + "." + side)
		var key := root + "." + side
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var with_hand := turn * rest
		if fingers.has(key) and weight > 0.0:
			with_hand = with_hand.slerp(turn * (fingers[key] as Quaternion), weight)
		skeleton.set_bone_pose_rotation(bone, with_hand)
	if weight <= 0.0:
		return
	for key: String in fingers:
		if key.begins_with("Thumb1") or key.begins_with("Middle1") or key.begins_with("Pinky1"):
			continue
		var bone := skeleton.find_bone(key)
		var current := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, current.slerp(fingers[key] as Quaternion, weight))
