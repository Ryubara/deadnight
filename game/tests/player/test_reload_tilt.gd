# The weapon tilts down while it reloads and is back up when the reload is done (#383), whatever the
# aim weight is: the tilt is added to the pose the weight gives. Stepped by hand with fixed ticks.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## The most the barrel may turn in one tick through a reload, in degrees (the tilt is 35 over a
## fifth of the shortest reload, 1.3 s).
const MAX_BARREL_TURN_DEG := 4.0
## How far below its starting pitch the barrel is at the bottom, at least, in degrees.
const MIN_DIP_DEG := 25.0

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	# The suite ticks the player by hand (PlayerHandStep), not at the physics clock's pace.
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.teleport(START)
	# The physics server learns of the room's static bodies on its first step: take that one by
	# the clock, then tick by hand.
	await get_tree().physics_frame
	await _ticks(1)


func after_test() -> void:
	Input.action_release("aim")


func _ticks(count: int) -> void:
	for i in count:
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


func _equip(weapon_id: StringName) -> void:
	_animation.equip(weapon_id)
	await _ticks(60)


## The barrel's pitch in degrees, without the recoil kick.
func _pitch_deg() -> float:
	var hands := _animation.hands()
	var kick := hands.recoil
	hands.recoil = 0.0
	var barrel := -hands.weapon_target().basis.x
	hands.recoil = kick
	return rad_to_deg(asin(clampf(barrel.y, -1.0, 1.0)))


func _barrel() -> Vector3:
	return -_animation.hands().weapon_target().basis.x


## Reloads for `seconds` and samples the pitch every tick for `seconds` plus a little after.
func _sample_reload(seconds: float) -> Dictionary:
	var start_pitch := _pitch_deg()
	var pitches: Array[float] = [start_pitch]
	var worst_turn := 0.0
	var last := _barrel()
	_animation.reload(seconds)
	for i in roundi((seconds + 0.3) / TICK):
		await _ticks(1)
		pitches.append(_pitch_deg())
		var now := _barrel()
		worst_turn = maxf(worst_turn, rad_to_deg(now.angle_to(last)))
		last = now
	return {"start": start_pitch, "pitches": pitches, "turn": worst_turn}


func _check_dips(weapon_id: StringName, aiming: bool) -> void:
	await _equip(weapon_id)
	if aiming:
		_runner.simulate_action_press("aim")
		await _seconds(1.0)
	var seconds: float = WeaponCatalog.get_def(weapon_id).reload_time
	var tag := "%s%s" % [weapon_id, " aiming" if aiming else ""]
	var weight_before := _rig.aim_amount()
	var run := await _sample_reload(seconds)
	var low := 1000.0
	var bottom_at := 0.0
	for i in run["pitches"].size():
		if run["pitches"][i] < low:
			low = run["pitches"][i]
			bottom_at = i * TICK
	assert_float(run["start"] - low).override_failure_message(tag + ": no dip").is_greater(
		MIN_DIP_DEG
	)
	# Down in the first part, back at the start pitch within the reload time.
	assert_float(bottom_at).override_failure_message(tag + ": bottom").is_between(
		seconds * 0.15, seconds * 0.85
	)
	var at_end: float = run["pitches"][roundi(seconds / TICK)]
	assert_float(at_end).override_failure_message(tag + ": not back by the end").is_equal_approx(
		run["start"], 1.5
	)
	assert_float(run["pitches"].back()).is_equal_approx(run["start"], 0.2)
	assert_float(run["turn"]).override_failure_message(tag + ": barrel turn").is_less(
		MAX_BARREL_TURN_DEG
	)
	# The tilt never touches the aim weight.
	assert_float(_rig.aim_amount()).override_failure_message(tag + ": weight").is_equal_approx(
		weight_before, 0.001
	)


func _seconds(seconds: float) -> void:
	await _ticks(roundi(seconds / TICK))


func test_every_gun_dips_and_is_back_within_its_reload_time() -> void:
	for weapon_id: StringName in [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]:
		await _check_dips(weapon_id, false)
		_animation.cancel_reload()
		await _seconds(0.5)


func test_a_reload_while_aiming_dips_and_returns_to_the_aim() -> void:
	for weapon_id: StringName in [&"pistol", &"rifle"]:
		await _check_dips(weapon_id, true)
		_runner.simulate_action_release("aim")
		await _seconds(1.5)


func test_putting_the_weapon_away_ends_the_reload() -> void:
	await _equip(&"rifle")
	_animation.reload(2.2)
	await _seconds(0.5)
	assert_float(_animation.reload_dip()).is_greater(0.9)
	_animation.equip(&"pistol")
	await _seconds(0.5)
	assert_float(_animation.reload_dip()).is_equal_approx(0.0, 0.001)


func test_a_gun_not_reloading_is_not_tilted() -> void:
	await _equip(&"rifle")
	await _seconds(0.5)
	assert_float(_animation.reload_dip()).is_equal(0.0)
