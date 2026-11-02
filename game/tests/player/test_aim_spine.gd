# The aim pitch of the Soldier's body (docs/design/weapon-hold.md, "Aim pitch"): looking up leans
# the spine back and looking down leans it forward, clamped, and the arms still reach their
# targets from the bent shoulders: the grip on the right hand, the left hand on the fore-end.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## Degrees: how far the measured lean may be off the asked one (the bones share it, the rest pose
## is not quite upright).
const LEAN_TOLERANCE_DEG := 2.0
## Metres, as in the weapon hold test: the right hand's grip, the left hand's fore-end.
const GRIP_TOLERANCE := 0.03
const SUPPORT_TOLERANCE := 0.12
const BARREL_TOLERANCE_DEG := 5.0
## The shotgun's and the tommy gun's fore-ends sit about 1 to 2 cm past what the left arm can reach
## with its hand stopping `SUPPORT_HAND_BACK` short: the arm goes straight and the hand stops just
## short of the grip (measured, the same at every pitch). A fore-end farther than this is a bug.
const REACH_SLACK := 0.04
## The view pitches checked: the camera's lowest and highest, and some between (degrees).
const PITCHES: Array[float] = [-60.0, -30.0, 0.0, 30.0, 50.0]
const GUNS: Array[StringName] = [&"rifle", &"shotgun", &"pistol", &"smg", &"flare_gun"]
const WATCHED: Array[String] = [
	"Hips", "Torso", "Neck", "UpperArm.L", "LowerArm.L", "Index1.L", "UpperArm.R", "Index1.R"
]

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation
## The bones' world positions as the skeleton finished posing (the modifiers' result is only
## readable at `skeleton_updated`: after the frame the skeleton hands back the clip's pose).
var _bones := {}
var _target := Transform3D.IDENTITY


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
	for bone in WATCHED:
		_bones[bone] = (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
		)
	# The pose's weapon target needs the finished pose too (the shoulder it hangs from).
	var hands := _animation.hands() if _animation != null else null
	if hands != null and hands.hold != null and hands.hold.shouldered:
		_target = hands.weapon_target()


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


func _pitch_to(degrees: float, frames: int = 30) -> void:
	_rig.pitch = deg_to_rad(degrees)
	await _ticks(frames)


## How far the chest leans forward, in degrees: the angle of the torso bone's line (its joint to
## the neck's) from upright, seen from the side, forward positive. The chest carries the whole bend.
func _lean_deg() -> float:
	var forward := (_player.global_basis * Vector3.FORWARD).normalized()
	var line: Vector3 = _bones["Neck"] - _bones["Torso"]
	return rad_to_deg(atan2(line.dot(forward), line.y))


func _equip(weapon_id: StringName) -> void:
	_animation.equip(weapon_id)
	await _ticks(60)


func _muzzle_direction(weapon: Node3D) -> Vector3:
	return (weapon.global_basis * Vector3.LEFT).normalized()


func test_the_bend_is_a_share_of_the_pitch_and_clamped() -> void:
	# Looking up bends back (negative), down bends forward, by `follow` of the pitch.
	assert_float(AimSpine.bend_for(deg_to_rad(30.0), 0.6, 40.0)).is_equal_approx(
		deg_to_rad(-18.0), 0.0001
	)
	assert_float(AimSpine.bend_for(deg_to_rad(-30.0), 0.6, 40.0)).is_equal_approx(
		deg_to_rad(18.0), 0.0001
	)
	assert_float(AimSpine.bend_for(0.0, 0.6, 40.0)).is_equal(0.0)
	# Past the limit it holds, both ways.
	assert_float(AimSpine.bend_for(deg_to_rad(89.0), 1.0, 40.0)).is_equal_approx(
		deg_to_rad(-40.0), 0.0001
	)
	assert_float(AimSpine.bend_for(deg_to_rad(-89.0), 1.0, 40.0)).is_equal_approx(
		deg_to_rad(40.0), 0.0001
	)
	# The shares of the bones make the whole bend.
	(
		assert_float(
			AimSpine.SHARES.reduce(func(sum: float, share: float) -> float: return sum + share, 0.0)
		)
		. is_equal_approx(1.0, 0.0001)
	)


func test_the_player_uses_the_tuning_for_the_spine() -> void:
	var tuning := _player.tuning
	assert_float(tuning.spine_pitch_follow).is_between(0.2, 1.0)
	assert_float(tuning.spine_pitch_limit_degrees).is_between(20.0, 60.0)
	# The camera's whole pitch range is inside what the limit allows to see the clamp work.
	(
		assert_float(rad_to_deg(AimSpine.bend_for(deg_to_rad(tuning.pitch_min_degrees), 1.0, 90.0)))
		. is_greater(tuning.spine_pitch_limit_degrees - 1.0)
	)


func test_looking_up_leans_the_chest_back_and_looking_down_forward() -> void:
	await _equip(&"rifle")
	await _pitch_to(0.0)
	var level := _lean_deg()
	var follow := _player.tuning.spine_pitch_follow
	await _pitch_to(30.0)
	var up := _lean_deg() - level
	await _pitch_to(-30.0)
	var down := _lean_deg() - level
	assert_float(up).override_failure_message("up lean %.1f" % up).is_less(-5.0)
	assert_float(down).override_failure_message("down lean %.1f" % down).is_greater(5.0)
	# The lean is the asked share of the pitch.
	assert_float(up).is_equal_approx(-30.0 * follow, LEAN_TOLERANCE_DEG)
	assert_float(down).is_equal_approx(30.0 * follow, LEAN_TOLERANCE_DEG)


func test_the_lean_is_held_at_the_limit_at_the_cameras_extremes() -> void:
	await _equip(&"rifle")
	var limit := _player.tuning.spine_pitch_limit_degrees
	var follow := _player.tuning.spine_pitch_follow
	for degrees: float in [_player.tuning.pitch_min_degrees, _player.tuning.pitch_max_degrees]:
		await _pitch_to(degrees)
		var bend := rad_to_deg(_animation.spine_bend())
		assert_float(absf(bend)).is_less_equal(limit + 0.001)
		assert_float(absf(bend)).is_equal_approx(minf(absf(degrees) * follow, limit), 0.01)


func test_the_lean_eases_with_the_view_and_does_not_jump() -> void:
	await _equip(&"rifle")
	await _pitch_to(0.0)
	var before := _lean_deg()
	# The view swings from level to the top in one step: the chest follows the view's value, the
	# arms and gun follow the chest, nothing steps by more than the swing's own share.
	_rig.pitch = deg_to_rad(50.0)
	await _ticks(1)
	var after := _lean_deg()
	assert_float(absf(after - before)).is_less_equal(50.0 * _player.tuning.spine_pitch_follow + 1.0)


func test_both_hands_stay_on_the_gun_at_every_view_pitch() -> void:
	for weapon_id in GUNS:
		await _equip(weapon_id)
		for aiming in [true, false]:
			if aiming:
				_runner.simulate_action_press("aim")
			for degrees in PITCHES:
				await _pitch_to(degrees, 40)
				var weapon := _animation.weapon()
				var hold := _animation.weapon_hold()
				var tag := "%s, pitch %d, %s: " % [weapon_id, degrees, "aim" if aiming else "hip"]
				var target := _target
				(
					assert_float(weapon.global_position.distance_to(target.origin))
					. override_failure_message(
						(
							tag
							+ (
								"grip off the target by %.3f"
								% weapon.global_position.distance_to(target.origin)
							)
						)
					)
					. is_less(GRIP_TOLERANCE)
				)
				if hold.support != Vector3.ZERO:
					var fore_end := weapon.to_global(hold.support)
					var reach := _arm_length("L")
					(
						assert_float(_bones["UpperArm.L"].distance_to(fore_end))
						. override_failure_message(
							(
								tag
								+ (
									"fore-end %.3f from the shoulder, arm reaches %.3f"
									% [_bones["UpperArm.L"].distance_to(fore_end), reach]
								)
							)
						)
						. is_less(reach + WeaponHandsIK.SUPPORT_HAND_BACK + REACH_SLACK)
					)
					(
						assert_float(_bones["Index1.L"].distance_to(fore_end))
						. override_failure_message(
							(
								tag
								+ (
									"left hand off the fore-end by %.3f"
									% _bones["Index1.L"].distance_to(fore_end)
								)
							)
						)
						. is_less(SUPPORT_TOLERANCE)
					)
				if aiming:
					var camera := _rig.get_node("Camera3D") as Camera3D
					(
						assert_float(
							rad_to_deg(_muzzle_direction(weapon).angle_to(-camera.global_basis.z))
						)
						. override_failure_message(tag + "barrel off the camera ray")
						. is_less(BARREL_TOLERANCE_DEG)
					)
			if aiming:
				_runner.simulate_action_release("aim")
				await _ticks(10)


## The left arm's length, shoulder joint to hand bone, as the clip leaves it (it does not stretch).
func _arm_length(side: String) -> float:
	return (
		_bones["UpperArm." + side].distance_to(_bones["LowerArm." + side])
		+ _bones["LowerArm." + side].distance_to(_bones["Index1." + side])
	)


func test_the_stock_follows_the_shoulder_when_the_chest_leans() -> void:
	await _equip(&"rifle")
	_runner.simulate_action_press("aim")
	await _pitch_to(0.0, 40)
	var level_shoulder: Vector3 = _bones["UpperArm.R"]
	await _pitch_to(-45.0, 40)
	var down_shoulder: Vector3 = _bones["UpperArm.R"]
	# The shoulder is where the lean put it (it moved), and the stock is still against it.
	assert_float(down_shoulder.distance_to(level_shoulder)).is_greater(0.03)
	var weapon := _animation.weapon()
	var hold := _animation.weapon_hold()
	assert_float(weapon.to_global(hold.butt).distance_to(down_shoulder)).is_less(0.16)


func test_a_full_body_clip_lets_go_of_the_lean_and_it_comes_back() -> void:
	await _equip(&"rifle")
	await _pitch_to(-40.0, 40)
	var leaning := _animation.spine_bend()
	assert_float(leaning).is_greater(deg_to_rad(10.0))
	_animation.play_full_body(&"HitReact")
	await _ticks(20)
	assert_float(absf(_animation.spine_bend())).is_less(absf(leaning) * 0.2)
	await _ticks(90)
	assert_float(_animation.spine_bend()).is_equal_approx(leaning, 0.01)


func test_the_modifier_runs_before_the_arms_reach() -> void:
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var spine := skeleton.get_node("AimSpine")
	var hands := skeleton.get_node("WeaponHandsIK")
	assert_int(spine.get_index()).is_less(hands.get_index())
