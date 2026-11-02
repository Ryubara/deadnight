# The view shake of a shot (docs/design/camera-shake.md): trauma rises with a shot and drains to
# nothing, the lens turns by it while the aim ray stays where the crosshair is, the player's setting
# scales it or turns it off, and each weapon carries its own amount. Stepped by hand with fixed time
# steps: no wall time, so the same numbers come out on any machine.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## "Very subtle": the strongest weapon's peak turn of the view stays under this many degrees.
const SUBTLE_DEGREES := 1.0

var _player: Player
var _rig: ThirdPersonCamera
var _tuning: PlayerTuning


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.set_physics_process(false)
	_player.set_process(false)
	_rig = _player.camera_rig
	_rig.set_process(false)
	_tuning = _player.tuning
	_player.global_position = START
	_player.state.position = START
	_rig.snap_to(START)
	await get_tree().physics_frame


func _render(seconds: float) -> void:
	for i in roundi(seconds / TICK):
		_rig.step(TICK, 1.0)


## The angle in degrees between where the lens looks and where the aim looks.
func _view_error() -> float:
	var look := -_rig.camera().global_transform.basis.z
	return rad_to_deg(look.angle_to(-_rig.aim_transform().basis.z))


func _def(id: StringName) -> WeaponDef:
	return WeaponCatalog.get_def(id)


func test_a_shot_adds_trauma_and_it_never_goes_past_one() -> void:
	assert_float(_rig.shake.trauma).is_equal(0.0)
	_rig.add_shake(_def(&"rifle").shake_trauma)
	assert_float(_rig.shake.trauma).is_equal_approx(_def(&"rifle").shake_trauma, 0.0001)
	for i in 5:
		_rig.add_shake(_def(&"shotgun").shake_trauma)
	assert_float(_rig.shake.trauma).is_equal(1.0)


func test_trauma_drains_to_zero_and_the_view_comes_to_rest() -> void:
	_rig.add_shake(_def(&"shotgun").shake_trauma)
	_render(0.1)
	assert_float(_view_error()).is_greater(0.0)
	var seconds := _def(&"shotgun").shake_trauma / _tuning.shake_decay
	_render(seconds + 0.1)
	assert_float(_rig.shake.trauma).is_equal(0.0)
	assert_float(_view_error()).is_less(0.0001)
	assert_bool(_rig.shake.rotation().is_equal_approx(Basis.IDENTITY)).is_true()


func test_the_aim_ray_does_not_move_with_the_shake() -> void:
	_rig.yaw = 0.6
	_rig.pitch = 0.1
	_render(0.3)
	var rest_origin := _rig.aim_transform().origin
	var rest_direction := -_rig.aim_transform().basis.z
	_rig.add_shake(1.0)
	var worst := 0.0
	for i in 30:
		_render(TICK)
		worst = maxf(worst, _view_error())
		assert_vector(_rig.aim_transform().origin).is_equal_approx(
			rest_origin, Vector3.ONE * 0.0001
		)
		assert_vector(-_rig.aim_transform().basis.z).is_equal_approx(
			rest_direction, Vector3.ONE * 0.0001
		)
	# The picture did shake, so the test has something to prove.
	assert_float(worst).is_greater(0.1)


func test_the_human_controller_aims_with_the_unshaken_view() -> void:
	_rig.yaw = -0.4
	_render(0.3)
	_rig.add_shake(1.0)
	_render(0.05)
	var command := HumanController.new().command(_player, 1)
	assert_vector(command.dir).is_equal_approx(-_rig.aim_transform().basis.z, Vector3.ONE * 0.0001)
	assert_vector(command.origin).is_equal_approx(_rig.aim_transform().origin, Vector3.ONE * 0.0001)
	assert_float(_view_error()).is_greater(0.0)


func test_every_weapon_stays_subtle_and_heavier_guns_shake_more() -> void:
	for id in WeaponCatalog.IDS:
		var trauma := _def(id).shake_trauma
		var peak := _tuning.shake_max_degrees * pow(trauma, _tuning.shake_exponent)
		assert_float(peak).override_failure_message("%s peaks at %.2f deg" % [id, peak]).is_less(
			SUBTLE_DEGREES
		)
	assert_float(_def(&"crowbar").shake_trauma).is_equal(0.0)
	assert_float(_def(&"shotgun").shake_trauma).is_greater(_def(&"rifle").shake_trauma)
	assert_float(_def(&"rifle").shake_trauma).is_greater(_def(&"pistol").shake_trauma)
	assert_float(_def(&"pistol").shake_trauma).is_greater(_def(&"smg").shake_trauma)
	assert_float(_def(&"smg").shake_trauma).is_greater(0.0)


func test_the_measured_turn_never_passes_the_peak_the_numbers_give() -> void:
	_rig.add_shake(_def(&"shotgun").shake_trauma)
	for i in 40:
		var bound := _rig.shake.peak_degrees()
		_render(TICK)
		# Pitch and yaw each reach the peak, so the look direction is off by at most about the peak
		# times root two (the roll turns about the look axis and adds nothing to it).
		assert_float(_view_error()).is_less_equal(bound * 1.5 + 0.0001)


func test_the_setting_scales_the_shake_and_zero_turns_it_off() -> void:
	_rig.shake.scale = 0.0
	_rig.add_shake(1.0)
	assert_float(_rig.shake.trauma).is_equal(0.0)
	_render(0.2)
	assert_float(_view_error()).is_less(0.0001)
	var full := CameraShake.new(_tuning)
	full.add(0.6)
	full.step(TICK)
	var half := CameraShake.new(_tuning)
	half.scale = 0.5
	half.add(0.6)
	half.step(TICK)
	assert_float(half.peak_degrees()).is_equal_approx(full.peak_degrees() * 0.5, 0.0001)


func test_the_same_shots_shake_the_same_way_each_time() -> void:
	var a := CameraShake.new(_tuning)
	var b := CameraShake.new(_tuning)
	a.add(0.5)
	b.add(0.5)
	for i in 20:
		a.step(TICK)
		b.step(TICK)
		assert_bool(a.rotation().is_equal_approx(b.rotation())).is_true()


func test_the_settings_key_defaults_to_full_and_is_kept_in_range() -> void:
	var settings := auto_free(SettingsService.new()) as SettingsService
	assert_int(settings.get_value(SettingsService.CAMERA_SHAKE)).is_equal(100)
	settings.set_value(SettingsService.CAMERA_SHAKE, 250)
	assert_int(settings.get_value(SettingsService.CAMERA_SHAKE)).is_equal(100)
	settings.set_value(SettingsService.CAMERA_SHAKE, -5)
	assert_int(settings.get_value(SettingsService.CAMERA_SHAKE)).is_equal(0)
	assert_float(PlayerSettings.camera_shake(null)).is_equal(1.0)


func test_a_long_machine_gun_burst_stays_subtle() -> void:
	var smg := _def(&"smg")
	var shake := CameraShake.new(_tuning)
	var worst := 0.0
	var ticks_between := roundi(smg.fire_interval / TICK)
	# The whole magazine, one shot every fire interval.
	for shot in smg.magazine_size:
		shake.add(smg.shake_trauma)
		for i in ticks_between:
			shake.step(TICK)
			worst = maxf(worst, shake.peak_degrees())
	assert_float(worst).is_less(SUBTLE_DEGREES)
