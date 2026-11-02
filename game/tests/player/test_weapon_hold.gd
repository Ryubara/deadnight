# The weapons in the Soldier's hands (docs/design/weapon-hold.md): sized by one rule, the grip on
# the right hand, the support hand on the fore-end, the stock at the shoulder and the barrel along
# the camera's aim, in the hip and the aim pose, standing and running.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## Tolerances: metres for places, degrees for angles.
const GRIP_TOLERANCE := 0.03
const SUPPORT_TOLERANCE := 0.12
## A weapon with a grip puts the left hand bone on the grip's own place for it (#460).
const LEFT_HAND_TOLERANCE := 0.01
const STOCK_TOLERANCE := 0.16
const SIZE_TOLERANCE := 0.05
const BARREL_TOLERANCE_DEG := 3.0
## The barrel turns in to meet the crosshair's ray, so in the aim pose it is a few degrees off the
## ray's direction but crosses it at the convergence distance.
const AIM_TOE_IN_DEG := 5.0
const CONVERGE_TOLERANCE_DEG := 1.0
## How far away the crosshair's target is for the convergence check.
const TARGET_DISTANCE := WeaponHandsIK.CONVERGE_DISTANCE
## The catalogue's guns, each with its own model and hold, and what is held in one hand.
const GUNS: Array[StringName] = [&"rifle", &"shotgun", &"pistol", &"smg", &"flare_gun"]
## The weapons given a size other than the rule's (docs/design/weapon-hold.md, "The size rule").
const SIZE_EXCEPTIONS := {&"pistol": 1.75, &"flare_gun": 1.7}

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
## The bones' world positions as the skeleton finished posing: once a frame is done the skeleton
## hands back the clip's pose, so the modifiers' result is only readable at `skeleton_updated`.
var _bones := {}


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.skeleton_updated.connect(_record_bones.bind(skeleton))
	_player.teleport(START)
	await _ticks(20)


func _record_bones(skeleton: Skeleton3D) -> void:
	for bone: String in ["Index1.L", "Index1.R", "UpperArm.R", "UpperArm.L", "Neck", "Hips"]:
		var pose := skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		_bones[bone] = skeleton.global_transform * pose.origin


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	# The skeleton's modifiers and the bone attachments run on the idle frame.
	await get_tree().process_frame


func _equip(weapon_class: StringName) -> void:
	_animation.equip(weapon_class)
	await _ticks(60)


func _equip_weapon(weapon_id: StringName) -> void:
	_animation.equip(weapon_id)
	await _ticks(60)


func _bone_position(bone: String) -> Vector3:
	return _bones[bone]


func _muzzle_direction(weapon: Node3D) -> Vector3:
	return (weapon.global_basis * Vector3.LEFT).normalized()


func _world_scale() -> float:
	return absf((_player.get_node("Model") as Node3D).global_basis.get_scale().x)


func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


func test_one_rule_sizes_every_weapon() -> void:
	for weapon_class in PlayerAnimation.HOLD_CLASSES:
		var hold := PlayerAnimation.hold_of(weapon_class)
		var length := hold.world_length(_world_scale())
		assert_float(length / hold.rule_length()).is_between(
			1.0 - SIZE_TOLERANCE, 1.0 + SIZE_TOLERANCE
		)


func test_one_rule_sizes_every_catalogue_weapon_but_the_two_small_guns() -> void:
	for id in WeaponCatalog.IDS:
		var hold := WeaponHoldMap.hold_for(id)
		assert_object(hold).override_failure_message("%s: no model" % id).is_not_null()
		var factor: float = SIZE_EXCEPTIONS.get(id, 1.0)
		assert_float(hold.size_factor).override_failure_message("%s: factor" % id).is_equal(factor)
		var length := hold.world_length(_world_scale())
		(
			assert_float(length / hold.sized_length())
			. override_failure_message("%s: length off its size" % id)
			. is_between(1.0 - SIZE_TOLERANCE, 1.0 + SIZE_TOLERANCE)
		)


func test_every_weapon_class_has_a_hold_with_its_model() -> void:
	for weapon_class in PlayerAnimation.HOLD_CLASSES:
		var hold := PlayerAnimation.hold_of(weapon_class)
		assert_object(hold).is_not_null()
		assert_str(str(hold.weapon_class)).is_equal(str(weapon_class))
		assert_bool(ResourceLoader.exists(hold.scene)).is_true()


func test_guns_are_shouldered_in_the_aim_pose() -> void:
	for weapon_class: StringName in GUNS:
		await _equip_weapon(weapon_class)
		_runner.simulate_action_press("aim")
		await _ticks(40)
		var weapon := _animation.weapon()
		var hold := _animation.weapon_hold()
		var tag := "%s: " % weapon_class
		assert_float(_animation.shoulder_blend()).override_failure_message(tag + "blend").is_equal(
			1.0
		)
		# The grip is where the pose put it, and the right hand is on it.
		var target := _animation.hands().solved_target()
		(
			assert_float(weapon.global_position.distance_to(target.origin))
			. override_failure_message(tag + "grip off the target")
			. is_less(GRIP_TOLERANCE)
		)
		# The support hand is at the fore-end (a one-handed gun has none): on the grip's own place for
		# it where the weapon has a grip (the fingers are `test_hand_grips.gd`'s), else near `support`.
		var fore_end := weapon.to_global(hold.support)
		var grip := _animation.weapon_grip()
		if grip != null and grip.has_left:
			(
				assert_float(
					_bone_position("Index1.L").distance_to(_animation.hands().solved_left().origin)
				)
				. override_failure_message(tag + "support hand off its grip on the fore-end")
				. is_less(LEFT_HAND_TOLERANCE)
			)
		elif hold.support != Vector3.ZERO:
			(
				assert_float(_bone_position("Index1.L").distance_to(fore_end))
				. override_failure_message(tag + "support hand off the fore-end")
				. is_less(SUPPORT_TOLERANCE)
			)
		# The stock is against the shoulder (a pistol has none to speak of).
		var butt := weapon.to_global(hold.butt)
		if hold.support != Vector3.ZERO:
			(
				assert_float(butt.distance_to(_bone_position("UpperArm.R")))
				. override_failure_message(tag + "stock off the shoulder")
				. is_less(STOCK_TOLERANCE)
			)
		# The barrel runs along the crosshair's ray, and the muzzle sees the crosshair's target.
		var camera := _rig.get_node("Camera3D") as Camera3D
		var ray := -camera.global_basis.z
		(
			assert_float(_angle_deg(_muzzle_direction(weapon), ray))
			. override_failure_message(tag + "barrel off the camera ray")
			. is_less(AIM_TOE_IN_DEG)
		)
		var aim_point := camera.global_position + ray * TARGET_DISTANCE
		var muzzle := weapon.to_global(hold.muzzle)
		(
			assert_float(_angle_deg(_muzzle_direction(weapon), (aim_point - muzzle).normalized()))
			. override_failure_message(tag + "barrel does not meet the crosshair target")
			. is_less(CONVERGE_TOLERANCE_DEG)
		)
		# The size in the world is the rule's.
		var span := muzzle.distance_to(butt)
		assert_float(span / hold.sized_length()).is_between(
			1.0 - SIZE_TOLERANCE, 1.0 + SIZE_TOLERANCE
		)
		_runner.simulate_action_release("aim")
		await _ticks(10)


func test_guns_point_along_the_body_at_the_hip_and_running() -> void:
	for weapon_class: StringName in GUNS:
		await _equip_weapon(weapon_class)
		var weapon := _animation.weapon()
		var forward := -_player.global_basis.z
		assert_float(_animation.shoulder_blend()).is_equal(1.0)
		(
			assert_float(_angle_deg(_muzzle_direction(weapon), forward))
			. override_failure_message("%s at the hip" % weapon_class)
			. is_less(BARREL_TOLERANCE_DEG)
		)
		_runner.simulate_action_press("move_forward")
		await _ticks(40)
		forward = -_player.global_basis.z
		(
			assert_float(_angle_deg(_muzzle_direction(weapon), forward))
			. override_failure_message("%s running" % weapon_class)
			. is_less(BARREL_TOLERANCE_DEG)
		)
		(
			assert_float(
				weapon.global_position.distance_to(_animation.hands().solved_target().origin)
			)
			. is_less(GRIP_TOLERANCE)
		)
		_runner.simulate_action_release("move_forward")
		await _ticks(10)


func test_the_barrel_follows_the_camera_pitch() -> void:
	await _equip(&"Rifle")
	_runner.simulate_action_press("aim")
	_rig.pitch = deg_to_rad(20.0)
	await _ticks(40)
	var camera := _rig.get_node("Camera3D") as Camera3D
	var weapon := _animation.weapon()
	assert_float(_angle_deg(_muzzle_direction(weapon), -camera.global_basis.z)).is_less(
		AIM_TOE_IN_DEG
	)
	assert_float(_muzzle_direction(weapon).y).is_greater(0.25)


# Looking down bends the upper body over the weapon, looking up tips it back (#110): the chest
# takes half the view's pitch, clamped, while the arms hold the gun.
func test_the_chest_leans_with_the_view_pitch() -> void:
	await _equip(&"Rifle")
	_runner.simulate_action_press("aim")
	var lean := {}
	for pitch: float in [-0.6, 0.0, 0.6]:
		_rig.pitch = pitch
		await _ticks(40)
		var forward := -_player.global_basis.z
		lean[pitch] = (_bone_position("Neck") - _bone_position("Hips")).dot(forward)
	assert_float(lean[-0.6] - lean[0.0]).is_greater(0.04)
	assert_float(lean[0.0] - lean[0.6]).is_greater(0.04)


func test_the_clip_keeps_the_hands_while_reloading() -> void:
	await _equip(&"Rifle")
	assert_float(_animation.shoulder_blend()).is_equal(1.0)
	_animation.play_action(&"Reload")
	await _ticks(30)
	assert_float(_animation.shoulder_blend()).is_less(0.1)
	await _ticks(180)
	assert_float(_animation.shoulder_blend()).is_equal(1.0)


func test_the_bat_is_in_the_right_hand_at_the_rule_size() -> void:
	await _equip(&"Melee")
	var weapon := _animation.weapon()
	var hold := _animation.weapon_hold()
	assert_bool(hold.shouldered).is_false()
	assert_float(_animation.shoulder_blend()).is_equal(0.0)
	var hand := _bone_position(PlayerAnimation.HAND_BONE)
	# The grip is the hold's offset from the hand bone, 0.15 m at the kit's hold.
	assert_float(weapon.global_position.distance_to(hand)).is_between(0.1, 0.2)
	var length := weapon.to_global(hold.muzzle).distance_to(weapon.to_global(hold.butt))
	assert_float(length / hold.rule_length()).is_between(1.0 - SIZE_TOLERANCE, 1.0 + 0.2)


func test_the_crowbar_is_its_own_model_in_the_right_hand() -> void:
	await _equip_weapon(&"crowbar")
	var weapon := _animation.weapon()
	var hold := _animation.weapon_hold()
	assert_str(weapon.scene_file_path).is_equal("res://assets/weapons/crowbar/crowbar.glb")
	assert_bool(hold.shouldered).is_false()
	assert_float(_animation.shoulder_blend()).is_equal(0.0)
	var hand := _bone_position(PlayerAnimation.HAND_BONE)
	assert_float(weapon.global_position.distance_to(hand)).is_between(0.05, 0.25)
	var length := weapon.to_global(hold.muzzle).distance_to(weapon.to_global(hold.butt))
	assert_float(length / hold.rule_length()).is_between(1.0 - SIZE_TOLERANCE, 1.0 + 0.2)


func test_a_gun_given_the_aim_shows_in_the_hand_and_the_hand_is_not_empty() -> void:
	for id: StringName in [&"pistol", &"flare_gun", &"smg"]:
		await _equip_weapon(id)
		assert_bool(_animation.weapon().visible).override_failure_message(id).is_true()
		assert_bool(_animation.weapon().is_inside_tree()).is_true()
