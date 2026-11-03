class_name HeldWeapon
extends RefCounted
## The weapon in the Soldier's hands, built one way for every view of him (Deadnight #621): the
## night's `PlayerAnimation` and the menu's stage both ask this for the mount on the hand bone, the
## weapon node at its solved place in the hand (`HandGrip.hold`), the arms' pose (`WeaponHandsIK`
## with the weapon's hold and grip) and the fingers' (`HandGripPose`). A view that built them on its
## own, as the menu did before, kept the kit's fist when the grips were solved from the models
## (#507); with one builder a change to how a weapon is held reaches every view at once.
##
## It owns the nodes it adds to the skeleton and never reads a clock: a view drives `hands`
## (aim, converge, weight) and `fingers` (weights) as it needs.

## The mount on the right hand bone, the arms' pose and the fingers' pose, children of the skeleton
## in that order (the fingers run after the arms). `offmount` is the left hand's, for the second
## gun of a dual weapon.
var mount: BoneAttachment3D
var offmount: BoneAttachment3D
var hands: WeaponHandsIK
var fingers: HandGripPose
## The weapon in the hand now (null: nothing held), its hold data and its grip.
var weapon: Node3D
## The second gun of a dual weapon (`WeaponHold.dual`) in the left hand: the same model, mirrored,
## or null.
var offhand: Node3D
var hold: WeaponHold
var grip: HandGrip


func _init(skeleton: Skeleton3D) -> void:
	mount = BoneAttachment3D.new()
	mount.name = "WeaponMount"
	mount.bone_name = PlayerAnimation.HAND_BONE
	skeleton.add_child(mount)
	offmount = BoneAttachment3D.new()
	offmount.name = "OffhandMount"
	offmount.bone_name = PlayerAnimation.OFFHAND_BONE
	skeleton.add_child(offmount)
	hands = WeaponHandsIK.new()
	hands.name = "WeaponHandsIK"
	hands.hand_hold = PlayerAnimation.HOLD_GUN
	skeleton.add_child(hands)
	# After the arms' IK: the fingers close on what the hand holds, the palm turns as one.
	fingers = HandGripPose.new()
	fingers.name = "HandGripPose"
	skeleton.add_child(fingers)


## The model's place under the hand bone: its grip's (solved from its sockets), or `fallback` (the
## kit's hold) for a model with no grip file yet.
static func grip_hold(solved: HandGrip, fallback: Transform3D) -> Transform3D:
	return solved.hold if solved != null else fallback


## The muzzle point of a hold: at its `muzzle` (the model's units), turned so `-Z` runs out of the
## barrel (the model's `-X`).
static func make_muzzle(of: WeaponHold) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = PlayerAnimation.MUZZLE_NODE
	marker.transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), of.muzzle)
	return marker


## Puts the weapon of `new_hold` (class `weapon_class`) in the right hand, or nothing for a null
## hold; the previous weapon goes. The weapon's model, its place in the hand and the arms' pose are
## taken from the hold and its grip file, the same for every view. Returns the weapon node.
func hold_weapon(weapon_class: StringName, new_hold: WeaponHold) -> Node3D:
	if weapon != null:
		weapon.free()
		weapon = null
	if offhand != null:
		offhand.free()
		offhand = null
	hold = new_hold
	hands.hold = hold
	grip = null
	hands.grip = null
	fingers.left_mirrors = hold != null and hold.dual
	if hold == null:
		return null
	weapon = (load(hold.scene) as PackedScene).instantiate() as Node3D
	weapon.name = "Weapon"
	grip = HandGrip.for_scene(hold.scene)
	hands.grip = grip
	var fallback := (
		PlayerAnimation.HOLD_MELEE if weapon_class == &"Melee" else PlayerAnimation.HOLD_GUN
	)
	var in_hand := grip_hold(grip, fallback)
	weapon.transform = in_hand.scaled_local(Vector3.ONE * hold.model_scale)
	# The arms' IK works the hand out from the weapon's pose through the same grip.
	hands.hand_hold = in_hand
	if weapon.find_child(PlayerAnimation.MUZZLE_NODE, true, false) == null:
		weapon.add_child(make_muzzle(hold))
	mount.add_child(weapon)
	if hold.dual:
		offhand = _mirrored_copy(in_hand)
		offmount.add_child(offhand)
	return weapon


## The second gun of a dual weapon: the model again, in the left hand where the right one's place
## reflects to (the rig is an exact mirror, so the bone-space place is the right one's with x turned
## about), the model flipped across its side so the left gun is the right one seen in a mirror.
func _mirrored_copy(in_hand: Transform3D) -> Node3D:
	var copy := (load(hold.scene) as PackedScene).instantiate() as Node3D
	copy.name = "Offhand"
	var mirrored := Transform3D(
		WeaponHandsIK.MIRROR * in_hand.basis, WeaponHandsIK.MIRROR * in_hand.origin
	)
	copy.transform = mirrored.scaled_local(Vector3.ONE * hold.model_scale)
	if copy.find_child(PlayerAnimation.MUZZLE_NODE, true, false) == null:
		copy.add_child(make_muzzle(hold))
	return copy


## Whether the arms are posed to hold the weapon at the shoulder (a gun), not left to a clip
## (melee).
func shoulders() -> bool:
	return hold != null and hold.shouldered


## Both hands closed on the weapon, for a view that has no blend of its own (the menu): the right
## hand on its grip and, for a two-handed gun, the left on the fore-end.
func close_hands() -> void:
	fingers.grip = grip
	fingers.right_weight = 1.0 if grip != null else 0.0
	var left_holds := grip != null and (hold.dual or (grip.has_left and shoulders()))
	fingers.left_weight = 1.0 if left_holds else 0.0


## Takes the mount, the arms' pose and the fingers off the skeleton.
func release() -> void:
	for node: Node in [mount, offmount, hands, fingers]:
		if node != null and is_instance_valid(node):
			# Out of the skeleton now, so the next holder's nodes take the same names.
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	mount = null
	offmount = null
	hands = null
	fingers = null
	weapon = null
	offhand = null
