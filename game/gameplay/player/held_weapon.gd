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
## in that order (the fingers run after the arms).
var mount: BoneAttachment3D
var hands: WeaponHandsIK
var fingers: HandGripPose
## The weapon in the hand now (null: nothing held), its hold data and its grip.
var weapon: Node3D
var hold: WeaponHold
var grip: HandGrip
## Whether the weapon in the hand is re-cut and wears the skin (`RecutSkin`, Deadnight #787): kept
## across weapons, so the one put in the hand next is dressed the same until it is told otherwise
## (`set_recut`). The skin is on the surface's material, so it follows the weapon through every
## view: the night's bodies (the player's own, the others'), the menu's.
var recut := false

var _skin: RecutSkin
## 0 to 1: how far the skin's ignition has run (1 is finished); `advance` moves it.
var _ignition := 1.0
var _style: RecutStyle = RecutStyle.shipped()


func _init(skeleton: Skeleton3D) -> void:
	mount = BoneAttachment3D.new()
	mount.name = "WeaponMount"
	mount.bone_name = PlayerAnimation.HAND_BONE
	skeleton.add_child(mount)
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
	_skin = null
	hold = new_hold
	hands.hold = hold
	grip = null
	hands.grip = null
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
	if recut:
		_skin = RecutSkin.wear(weapon, 1.0, _style)
	return weapon


## Dresses the weapon in the hand in the re-cut skin, or takes it off, and keeps that for the
## weapons
## put in the hand after it. `ignite` sweeps the skin on over `RecutStyle.ignite_seconds` (the
## weapon
## has just been re-cut) instead of showing it finished; `advance` runs the sweep.
func set_recut(on: bool, ignite: bool = false) -> void:
	if on == recut:
		return
	recut = on
	if weapon == null:
		return
	if on:
		_ignition = 0.0 if ignite else 1.0
		_skin = RecutSkin.wear(weapon, _ignition, _style)
	else:
		RecutSkin.strip(weapon)
		_skin = null


## Runs the skin's ignition on by `delta` seconds (the view's frame time).
func advance(delta: float) -> void:
	if _skin == null or _ignition >= 1.0:
		return
	_ignition = minf(_ignition + delta / maxf(_style.ignite_seconds, 0.01), 1.0)
	_skin.reveal = _ignition
	# The flash of the front's first moment: it falls as the skin goes over.
	_skin.boost = 1.2 * pow(1.0 - _ignition, 2.0)


## Whether the weapon in the hand wears the skin now.
func is_skinned() -> bool:
	return weapon != null and RecutSkin.worn_by(weapon) != null


## Whether the arms are posed to hold the weapon at the shoulder (a gun), not left to a clip
## (melee).
func shoulders() -> bool:
	return hold != null and hold.shouldered


## Both hands closed on the weapon, for a view that has no blend of its own (the menu): the right
## hand on its grip and, for a two-handed gun, the left on the fore-end.
func close_hands() -> void:
	fingers.grip = grip
	fingers.right_weight = 1.0 if grip != null else 0.0
	fingers.left_weight = 1.0 if grip != null and grip.has_left and shoulders() else 0.0


## Takes the mount, the arms' pose and the fingers off the skeleton.
func release() -> void:
	for node: Node in [mount, hands, fingers]:
		if node != null and is_instance_valid(node):
			# Out of the skeleton now, so the next holder's nodes take the same names.
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	mount = null
	hands = null
	fingers = null
	weapon = null
