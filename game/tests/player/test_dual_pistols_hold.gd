# The dual pistols in the Soldier's hands (Deadnight #789, docs/design/weapon-hold.md, "The dual
# pistols"): a pistol in each hand, the left one the right one mirrored. Each hand holds its gun on
# its grip, both barrels run along the crosshair's ray, the two guns sit either side of the aim,
# the left gun is the same model as the right drawn in a mirror, and the clips around the aim
# (equip, sprint, the quick melee) keep a pistol in each hand.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
const WEAPON := &"dual_pistols"
## Metres a grip may be off the place the pose reached for, and a hand bone off the grip's place.
const GRIP_TOLERANCE := 0.03
const HAND_TOLERANCE := 0.01
## Degrees a barrel may be off the crosshair's point, and how far apart (metres) the two guns are
## at the least: a pistol in each hand reads as two.
const CONVERGE_TOLERANCE_DEG := 1.5
const MIN_GAP := 0.2
## Metres the hands may be from each other's mirror in the pose, across the aim's plane.
const MIRROR_TOLERANCE := 0.06

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
## The bones' world places as the skeleton finished posing (the modifiers' result is only readable
## at `skeleton_updated`).
var _bones := {}
var _contact: HandContact
## The measurement asked for and taken at the next `skeleton_updated`.
var _want := false
var _measured := {}


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_record_bones)
	_player.teleport(START)
	await get_tree().physics_frame
	await _ticks(20)
	_animation.equip(WEAPON)
	await _ticks(60)
	_contact = HandContact.new(_skeleton)


func after_test() -> void:
	Input.action_release("aim")
	Input.action_release("sprint")
	Input.action_release("move_forward")


func _record_bones() -> void:
	if _want:
		_want = false
		_contact.set_weapon(_animation.weapon())
		_measured = {"R": _contact.measure("R")}
		_contact.set_weapon(_animation.offhand_weapon())
		_measured["L"] = _contact.measure("L")
	for bone: String in ["Index1.L", "Index1.R", "UpperArm.R", "UpperArm.L"]:
		var pose := _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))
		_bones[bone] = _skeleton.global_transform * pose.origin


func _ticks(count: int) -> void:
	for i in count:
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


func _barrel(gun: Node3D) -> Vector3:
	return (gun.global_basis * Vector3.LEFT).normalized()


func _crosshair_target() -> Vector3:
	var camera := _rig.get_node("Camera3D") as Camera3D
	return camera.global_position - camera.global_basis.z * WeaponHandsIK.CONVERGE_DISTANCE


func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


func test_the_pair_is_two_guns_the_left_one_the_right_one_mirrored() -> void:
	assert_str(str(_animation.weapon_class)).is_equal("Dual")
	var right := _animation.weapon()
	var left := _animation.offhand_weapon()
	assert_object(right).is_not_null()
	assert_object(left).is_not_null()
	assert_bool(right.visible and left.visible).is_true()
	assert_str(left.get_parent().get_parent().get_class()).is_equal("Skeleton3D")
	assert_str(str(_animation.weapon_hold().scene)).is_equal(
		"res://assets/weapons/revolver/revolver.glb"
	)
	# One model drawn twice: the left in a mirror, so its basis turns the other way about.
	assert_float(right.global_basis.determinant()).is_greater(0.0)
	assert_float(left.global_basis.determinant()).is_less(0.0)
	assert_float(absf(left.global_basis.determinant())).is_equal_approx(
		right.global_basis.determinant(), 0.001
	)


func test_each_hand_holds_its_gun_on_the_grip_in_the_aim_pose() -> void:
	_runner.simulate_action_press("aim")
	await _ticks(40)
	assert_float(_animation.shoulder_blend()).is_equal(1.0)
	var hands := _animation.hands()
	var right := _animation.weapon()
	var left := _animation.offhand_weapon()
	(
		assert_float(right.global_position.distance_to(hands.solved_target().origin))
		. override_failure_message("the right grip is off its target")
		. is_less(GRIP_TOLERANCE)
	)
	(
		assert_float(left.global_position.distance_to(hands.solved_offhand().origin))
		. override_failure_message("the left grip is off its target")
		. is_less(GRIP_TOLERANCE)
	)
	# The left hand bone is where the mirrored grip puts it, as the right's is.
	(
		assert_float(_bones["Index1.L"].distance_to(hands.solved_left().origin))
		. override_failure_message("the left hand is off its grip")
		. is_less(HAND_TOLERANCE)
	)


func test_both_barrels_meet_the_crosshair_and_the_guns_are_a_hands_width_apart() -> void:
	_runner.simulate_action_press("aim")
	await _ticks(40)
	var hold := _animation.weapon_hold()
	for gun: Node3D in [_animation.weapon(), _animation.offhand_weapon()]:
		var muzzle := gun.to_global(hold.muzzle)
		(
			assert_float(_angle_deg(_barrel(gun), (_crosshair_target() - muzzle).normalized()))
			. override_failure_message("%s: the barrel misses the crosshair's point" % gun.name)
			. is_less(CONVERGE_TOLERANCE_DEG)
		)
	var camera := _rig.get_node("Camera3D") as Camera3D
	var across := _animation.weapon().global_position - _animation.offhand_weapon().global_position
	assert_float(absf(across.dot(camera.global_basis.x))).is_greater(MIN_GAP)
	# The right gun is the one on the right of the view, the left on the left.
	assert_float(across.dot(camera.global_basis.x)).is_greater(0.0)


func test_the_pose_is_symmetric_about_the_aim() -> void:
	_runner.simulate_action_press("aim")
	await _ticks(40)
	var camera := _rig.get_node("Camera3D") as Camera3D
	var up := camera.global_basis.y
	var forward := -camera.global_basis.z
	var right := _animation.weapon().global_position
	var left := _animation.offhand_weapon().global_position
	# Level and as far forward as each other (the shoulders are level and the offsets mirrored).
	assert_float(absf((right - left).dot(up))).is_less(MIRROR_TOLERANCE)
	assert_float(absf((right - left).dot(forward))).is_less(MIRROR_TOLERANCE)


func test_the_left_fingers_are_the_right_ones_mirrored() -> void:
	var grip := _animation.weapon_grip()
	var mirrored := grip.mirrored()
	assert_int(mirrored.size()).is_equal(grip.right.size())
	for key: String in grip.right:
		var left_key := key.trim_suffix(".R") + ".L"
		assert_bool(mirrored.has(left_key)).override_failure_message(left_key).is_true()
		var q: Quaternion = grip.right[key]
		var m: Quaternion = mirrored[left_key]
		assert_float(m.x).is_equal_approx(q.x, 0.0001)
		assert_float(m.y).is_equal_approx(-q.y, 0.0001)
		assert_float(m.z).is_equal_approx(-q.z, 0.0001)
	# And the pose shows them: the left hand's fingers are bent as the right's, mirrored.
	_runner.simulate_action_press("aim")
	await _ticks(40)
	for finger in ["Index2", "Middle2", "Pinky2", "Thumb1"]:
		var r := _skeleton.get_bone_pose_rotation(_skeleton.find_bone(finger + ".R"))
		var l := _skeleton.get_bone_pose_rotation(_skeleton.find_bone(finger + ".L"))
		# A finger that is closed on the grip is turned off its rest on both hands by as much.
		var turn_r := r.angle_to(
			(
				_skeleton
				. get_bone_rest(_skeleton.find_bone(finger + ".R"))
				. basis
				. get_rotation_quaternion()
			)
		)
		var turn_l := l.angle_to(
			(
				_skeleton
				. get_bone_rest(_skeleton.find_bone(finger + ".L"))
				. basis
				. get_rotation_quaternion()
			)
		)
		assert_float(turn_l).override_failure_message(finger).is_equal_approx(turn_r, 0.15)


func test_the_hip_pose_keeps_a_pistol_in_each_hand_pointing_ahead() -> void:
	assert_float(_animation.aim_weight()).is_equal(0.0)
	var forward := -_player.global_basis.z
	for gun: Node3D in [_animation.weapon(), _animation.offhand_weapon()]:
		(
			assert_float(_angle_deg(_barrel(gun), forward))
			. override_failure_message("%s: off the body at the hip" % gun.name)
			. is_less(8.0)
		)


func test_a_swap_to_another_weapon_takes_the_second_gun_away() -> void:
	_animation.equip(&"pistol")
	await _ticks(60)
	assert_object(_animation.offhand_weapon()).is_null()
	assert_str(str(_animation.weapon_class)).is_equal("Pistol")
	_animation.equip(WEAPON)
	await _ticks(60)
	assert_object(_animation.offhand_weapon()).is_not_null()
	assert_bool(_animation.offhand_weapon().visible).is_true()


func test_the_second_gun_goes_with_the_first_when_the_hands_are_empty() -> void:
	_animation.set_downed(true)
	await _ticks(5)
	assert_bool(_animation.weapon().visible).is_false()
	assert_bool(_animation.offhand_weapon().visible).is_false()
	_animation.set_downed(false)
	await _ticks(5)
	assert_bool(_animation.offhand_weapon().visible).is_true()


func test_the_clips_around_the_aim_exist_and_keep_both_arms_up() -> void:
	var library := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in DualClips.CLIPS:
		assert_bool(library.has_animation(clip)).override_failure_message(str(clip)).is_true()


## Both hands against the gun each holds, as the skin is drawn: nothing more than 2 mm into it and
## every part the grip says touches within 5 mm (the right hand's grip for the right gun, the same
## grip mirrored for the left).
func _hands_hold(tag: String) -> Array[String]:
	_want = true
	await _ticks(1)
	var grip := _animation.weapon_grip()
	var fails: Array[String] = []
	# Something was measured on each hand (a weapon with no triangles reads nothing).
	for side: String in ["R", "L"]:
		(
			assert_int(_measured[side].size())
			. override_failure_message("%s: nothing measured on the %s hand" % [tag, side])
			. is_greater(5)
		)
	fails.append_array(HandContact.failures(tag + " R", _measured["R"], grip.right_contacts))
	fails.append_array(HandContact.failures(tag + " L", _measured["L"], grip.right_contacts))
	return fails


func test_each_hand_closes_on_its_gun_in_every_pose() -> void:
	var fails: Array[String] = []
	fails.append_array(await _hands_hold("equipped"))
	_runner.simulate_action_press("aim")
	await _ticks(40)
	fails.append_array(await _hands_hold("aim"))
	_animation.play_action(&"Fire", 0)
	await _ticks(3)
	fails.append_array(await _hands_hold("fire right"))
	_animation.play_action(&"Fire", 1)
	await _ticks(3)
	fails.append_array(await _hands_hold("fire left"))
	_runner.simulate_action_release("aim")
	_runner.simulate_action_press("move_forward")
	await _ticks(30)
	fails.append_array(await _hands_hold("run"))
	_player.teleport(START)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_runner.simulate_action_press("sprint")
	await _ticks(40)
	for i in 3:
		fails.append_array(await _hands_hold("sprint %d" % i))
		assert_float(_animation.sprint_carry()).is_greater(0.99)
		await _ticks(9)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
