# The sprint sway of the view (docs/design/camera-shake.md): a small bob and roll locked to the
# feet while sprinting, none at any other time, eased in and out, scaled by the camera shake setting
# and off under reduced motion, and never in the aim. Stepped by hand with fixed time steps: no wall
# time, so the same numbers come out on any machine.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
## "Very subtle": the sway's largest turn of the view stays under this many degrees. It was 0.5, and
## the maintainer found the sprint still too strong (issue #405): half of it now.
const SUBTLE_DEGREES := 0.25
## What main swayed at the sprint (pitch 0.4, yaw 0.2, roll 0.28): the sway's largest turn of the
## look direction, in degrees, before issue #405 halved it.
const MAIN_PEAK_DEGREES := 0.44721

var _player: Player
var _rig: ThirdPersonCamera
var _tuning: PlayerTuning
var _real_values := {}


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
	# Stepped by hand on the ground (the player's own ticks set this from the body, and the body of
	# a frozen player did not land yet).
	_rig.grounded = true
	await get_tree().physics_frame


func after_test() -> void:
	var settings := _settings()
	for key: StringName in _real_values:
		settings.call("set_value", key, _real_values[key])
	_real_values.clear()


## A ground speed at which a foot lands every `ticks` physics ticks.
func _speed_for(ticks: int) -> float:
	return _tuning.step_distance / (ticks * TICK)


func _render(seconds: float) -> void:
	for i in roundi(seconds / TICK):
		_rig.step(TICK, 1.0)


func _sprint(on: bool, speed: float) -> void:
	_rig.sprinting = on
	_rig.ground_speed = speed


## The angle in degrees between where the lens looks and where the aim looks.
func _view_error() -> float:
	var look := -_rig.camera().global_transform.basis.z
	return rad_to_deg(look.angle_to(-_rig.aim_transform().basis.z))


## The whole angle of the lens against the aim (roll included), in degrees.
func _lens_angle() -> float:
	var turn := _rig.aim_transform().basis.inverse() * _rig.camera().global_transform.basis
	return rad_to_deg(turn.get_rotation_quaternion().get_angle())


func _settings() -> Node:
	return get_tree().root.get_node_or_null(PlayerSettings.SERVICE_PATH)


func _set_setting(key: StringName, value: Variant) -> void:
	var settings := _settings()
	if not _real_values.has(key):
		_real_values[key] = settings.call("get_value", key)
	settings.call("set_value", key, value)


## A sway on its own, stepped with a footfall every `ticks_per_foot` ticks, for `ticks` ticks.
func _bare(ticks_per_foot: int, ticks: int, scale := 1.0) -> Array[Basis]:
	var shake := CameraShake.new(_tuning)
	shake.scale = scale
	var sway := SprintSway.new(_tuning, shake)
	var out: Array[Basis] = []
	for i in ticks:
		sway.step(TICK, true, _speed_for(ticks_per_foot))
		out.append(sway.rotation())
	return out


func _pitch_of(turn: Basis) -> float:
	return rad_to_deg(turn.get_euler().x)


## Rising zero crossings of the bob, from `from` on.
func _bobs(turns: Array[Basis], from: int) -> int:
	var count := 0
	for i in range(from + 1, turns.size()):
		if _pitch_of(turns[i - 1]) < 0.0 and _pitch_of(turns[i]) >= 0.0:
			count += 1
	return count


func test_there_is_no_sway_while_walking_standing_or_aiming() -> void:
	_sprint(false, _tuning.run_speed)
	_render(1.5)
	assert_float(_view_error()).is_less(0.0001)
	assert_float(_lens_angle()).is_less(0.0001)
	_sprint(false, 0.0)
	_render(0.5)
	assert_float(_lens_angle()).is_less(0.0001)
	# The sprint state with no way to go is no sway either (a sprint held against a wall).
	_sprint(true, 0.0)
	_render(0.5)
	assert_float(_lens_angle()).is_less(0.0001)
	# Aiming takes the sprint away: the sway does not show.
	_rig.aiming = true
	_sprint(true, _tuning.sprint_speed)
	_render(1.0)
	assert_float(_lens_angle()).is_less(0.0001)
	assert_float(_rig.sway.amount()).is_equal(0.0)


func test_the_sprint_sways_half_as_much_as_it_did() -> void:
	# The maintainer (issue #405): "camera shake when sprinting is too intensive, lower this down
	# by 50%".
	# The same run as on main (full sprint, the sway fully eased in): half of main's 0.447 degrees,
	# and each angle half of main's.
	_sprint(true, _tuning.sprint_speed)
	_render(_tuning.sprint_sway_ease_in + 0.2)
	assert_float(_rig.sway.peak_degrees()).is_equal_approx(MAIN_PEAK_DEGREES * 0.5, 0.002)
	assert_float(_tuning.sprint_sway_pitch_degrees).is_equal_approx(0.2, 0.0001)
	assert_float(_tuning.sprint_sway_yaw_degrees).is_equal_approx(0.1, 0.0001)
	assert_float(_tuning.sprint_sway_roll_degrees).is_equal_approx(0.14, 0.0001)
	# And what the lens does over a stride, not only the tuning: the worst turn of the look direction
	# measured on the camera stays at that peak or under, and is not nothing.
	var worst := 0.0
	for i in 120:
		_render(TICK)
		worst = maxf(worst, _view_error())
	assert_float(worst).is_between(0.05, MAIN_PEAK_DEGREES * 0.5 + 0.001)
	assert_float(_rig.sway.peak_degrees()).is_less(SUBTLE_DEGREES)


func test_sprinting_sways_within_its_bounds_and_is_never_more_than_subtle() -> void:
	_sprint(true, _tuning.sprint_speed)
	_render(_tuning.sprint_sway_ease_in + 0.2)
	var worst_look := 0.0
	var worst_pitch := 0.0
	for i in 120:
		_render(TICK)
		worst_look = maxf(worst_look, _view_error())
		worst_pitch = maxf(worst_pitch, absf(_pitch_of(_rig.sway.rotation())))
	assert_float(worst_look).is_greater(0.05)
	assert_float(worst_look).is_less_equal(_rig.sway.peak_degrees() + 0.0001)
	assert_float(worst_pitch).is_greater(_tuning.sprint_sway_pitch_degrees * 0.9)
	assert_float(worst_pitch).is_less_equal(_tuning.sprint_sway_pitch_degrees + 0.0001)
	assert_float(_tuning.sprint_sway_pitch_degrees).is_between(0.1, 0.225)
	for angle in [
		_tuning.sprint_sway_pitch_degrees,
		_tuning.sprint_sway_yaw_degrees,
		_tuning.sprint_sway_roll_degrees
	]:
		assert_float(angle).is_less(SUBTLE_DEGREES)


func test_the_sway_repeats_every_stride_and_never_drifts() -> void:
	# A foot lands every 30 ticks; a stride is two feet, so the sway repeats after 60 ticks.
	var turns := _bare(30, 400)
	for i in range(150, 300):
		assert_bool(turns[i].is_equal_approx(turns[i + 60])).is_true()
	# Not still: the bob goes both ways.
	var low := 0.0
	var high := 0.0
	for i in range(150, 210):
		low = minf(low, _pitch_of(turns[i]))
		high = maxf(high, _pitch_of(turns[i]))
	assert_float(high).is_greater(0.1)
	assert_float(low).is_less(-0.1)


func test_the_bob_is_locked_to_the_footfalls_not_to_the_clock() -> void:
	# After the ease-in, one foot every 30 ticks and then every 15.
	var slow := _bare(30, 480)
	var fast := _bare(15, 480)
	var from := 120
	# 360 ticks = 12 footfalls at the slow pace (one bob each), 24 at the fast pace.
	assert_int(_bobs(slow, from)).is_between(11, 12)
	assert_int(_bobs(fast, from)).is_between(23, 24)
	# The phase is the footfall count: metres over the metres to a step.
	var sway := SprintSway.new(_tuning, CameraShake.new(_tuning))
	for i in 120:
		sway.step(TICK, true, 7.0)
	assert_float(sway.phase).is_equal_approx(7.0 * 120 * TICK / _tuning.step_distance, 0.001)
	# A stopped body holds still.
	var held := sway.phase
	sway.step(TICK, true, 0.0)
	assert_float(sway.phase).is_equal(held)


func test_the_setting_scales_the_sway_and_zero_turns_it_off() -> void:
	var full := _bare(30, 300, 1.0)
	var half := _bare(30, 300, 0.5)
	var none := _bare(30, 300, 0.0)
	for i in range(100, 300):
		assert_float(_pitch_of(half[i])).is_equal_approx(_pitch_of(full[i]) * 0.5, 0.001)
		assert_bool(none[i].is_equal_approx(Basis.IDENTITY)).is_true()
	assert_float(_pitch_of(full[110])).is_not_equal(0.0)


func test_reduced_motion_and_the_slider_reach_the_sway_through_the_settings() -> void:
	_sprint(true, _tuning.sprint_speed)
	_render(1.0)
	var full := _rig.sway.amount()
	assert_float(full).is_greater(0.99)
	_set_setting(PlayerSettings.KEY_CAMERA_SHAKE, 50)
	assert_float(_rig.sway.amount()).is_equal_approx(full * 0.5, 0.001)
	_set_setting(PlayerSettings.KEY_CAMERA_SHAKE, 100)
	_set_setting(PlayerSettings.KEY_REDUCED_MOTION, true)
	_render(0.1)
	assert_float(_rig.sway.amount()).is_equal(0.0)
	assert_float(_lens_angle()).is_less(0.0001)
	_set_setting(PlayerSettings.KEY_REDUCED_MOTION, false)
	_set_setting(PlayerSettings.KEY_CAMERA_SHAKE, 0)
	_render(0.1)
	assert_float(_lens_angle()).is_less(0.0001)


func test_the_aim_ray_does_not_move_with_the_sway() -> void:
	_rig.yaw = 0.6
	_rig.pitch = 0.1
	_render(0.3)
	var rest_origin := _rig.aim_transform().origin
	var rest_direction := -_rig.aim_transform().basis.z
	# Not the sprint pull-back (that moves the lens by design): the sprint state stays off here, the
	# sway is stepped on its own and the lens turned by it.
	_rig.sway.level = 1.0
	_rig.sway.phase = 0.3
	var worst := 0.0
	for i in 60:
		_rig.sway.phase += 0.05
		_rig.sway.level = 1.0
		_rig.step(TICK, 1.0)
		worst = maxf(worst, _view_error())
		assert_vector(_rig.aim_transform().origin).is_equal_approx(
			rest_origin, Vector3.ONE * 0.0001
		)
		assert_vector(-_rig.aim_transform().basis.z).is_equal_approx(
			rest_direction, Vector3.ONE * 0.0001
		)
	# The picture did sway, so the test has something to prove.
	assert_float(worst).is_greater(0.05)
	var command := HumanController.new().command(_player, 1)
	assert_vector(command.dir).is_equal_approx(rest_direction, Vector3.ONE * 0.0001)
	assert_vector(command.origin).is_equal_approx(rest_origin, Vector3.ONE * 0.0001)


func test_easing_in_and_out_has_no_jump() -> void:
	# The fastest the lens can turn in steady sprint, per tick (the bob's slope), as a cap.
	var step_cap := (
		_tuning.sprint_sway_pitch_degrees
		* TAU
		* _tuning.sprint_speed
		/ _tuning.step_distance
		* TICK
	)
	_render(0.5)
	_sprint(true, _tuning.sprint_speed)
	var last := _rig.sway.amount()
	var before := _lens_angle()
	var ticks_in := 0
	var worst_amount := 0.0
	var worst_turn := 0.0
	while _rig.sway.level < 1.0 and ticks_in < 200:
		_render(TICK)
		ticks_in += 1
		worst_amount = maxf(worst_amount, absf(_rig.sway.amount() - last))
		last = _rig.sway.amount()
		worst_turn = maxf(worst_turn, absf(_lens_angle() - before))
		before = _lens_angle()
	# Full after the ease-in time, to a tick; and no step of the amount bigger than the ramp.
	var in_ticks := _tuning.sprint_sway_ease_in / TICK
	assert_int(ticks_in).is_between(int(in_ticks) - 1, int(in_ticks) + 2)
	assert_float(worst_amount).is_less(2.0 * TICK / _tuning.sprint_sway_ease_in)
	assert_float(worst_turn).is_less(step_cap * 2.0)
	# Out: the sprint stops and the speed falls away over a few ticks, as the body slows.
	_render(0.3)
	var speed := _tuning.sprint_speed
	var ticks_out := 0
	worst_amount = 0.0
	worst_turn = 0.0
	last = _rig.sway.amount()
	before = _lens_angle()
	_rig.sprinting = false
	while _rig.sway.level > 0.0 and ticks_out < 200:
		speed = maxf(speed - 20.0 * TICK, 0.0)
		_rig.ground_speed = speed
		_render(TICK)
		ticks_out += 1
		worst_amount = maxf(worst_amount, absf(_rig.sway.amount() - last))
		last = _rig.sway.amount()
		worst_turn = maxf(worst_turn, absf(_lens_angle() - before))
		before = _lens_angle()
	var out_ticks := _tuning.sprint_sway_ease_out / TICK
	assert_int(ticks_out).is_between(int(out_ticks) - 1, int(out_ticks) + 2)
	assert_float(worst_amount).is_less(2.0 * TICK / _tuning.sprint_sway_ease_out)
	assert_float(worst_turn).is_less(step_cap * 2.0)
	assert_float(_lens_angle()).is_less(0.0001)


func test_a_shot_while_sprinting_adds_to_the_sway_and_the_sway_gives_way() -> void:
	_sprint(true, _tuning.sprint_speed)
	_render(1.0)
	var quiet := _rig.sway.amount()
	var shotgun := WeaponCatalog.get_def(&"shotgun")
	_rig.add_shake(shotgun.shake_trauma)
	_render(TICK)
	var ducked := _rig.sway.amount()
	assert_float(ducked).is_less(quiet)
	assert_float(ducked).is_greater(quiet * 0.4)
	# Together they stay under the sum of the two bounds, and well under a degree.
	var worst := 0.0
	for i in 40:
		var bound := _rig.shake.peak_degrees() * 1.5 + _rig.sway.peak_degrees()
		_render(TICK)
		worst = maxf(worst, _view_error())
		assert_float(_view_error()).is_less_equal(bound + 0.0001)
	assert_float(worst).is_less(1.0)
	# The shot has drained and the sway is back in full.
	_render(0.5)
	assert_float(_rig.shake.trauma).is_equal(0.0)
	assert_float(_rig.sway.amount()).is_equal_approx(quiet, 0.0001)


func test_the_players_sprint_drives_the_sway_and_stopping_or_downed_ends_it() -> void:
	_player.set_physics_process(true)
	var run := PlayerCommand.new()
	run.move = Vector2(0.0, -1.0)
	run.sprint = true
	for i in 90:
		_player.submit_command(run)
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
	assert_bool(_player.state.sprinting).is_true()
	assert_float(_rig.ground_speed).is_greater(_tuning.sprint_speed * 0.9)
	assert_float(_rig.sway.amount()).is_greater(0.99)
	# A downed body is ticked with a command that does nothing: no sprint, so the sway goes.
	for i in 40:
		_player.submit_command(PlayerCommand.new())
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
	assert_bool(_player.state.sprinting).is_false()
	assert_float(_rig.sway.amount()).is_equal(0.0)


func test_the_sway_stops_on_the_first_tick_in_the_air_and_stays_off_until_landing() -> void:
	# The maintainer (issue #405): a sprint-jump with Shift still held must not sway in the air, and
	# the sway stops "as soon as player is ever in the air", not over the ease-out.
	_sprint(true, _tuning.sprint_speed)
	_render(1.0)
	assert_float(_rig.sway.amount()).is_greater(0.99)
	assert_float(_lens_angle()).is_greater(0.0)
	# Leaves the ground, sprint still held and the body still fast: gone on that very tick.
	_rig.grounded = false
	_render(TICK)
	assert_float(_rig.sway.amount()).is_equal(0.0)
	assert_float(_rig.sway.peak_degrees()).is_equal(0.0)
	assert_float(_lens_angle()).is_less(0.0001)
	assert_float(_view_error()).is_less(0.0001)
	# Stays zero through the whole jump (0.9 s in the air, the sprint key held the whole time).
	for i in 54:
		_render(TICK)
		assert_float(_lens_angle()).is_less(0.0001)
	# Lands with the sprint still held: it comes back with the normal ease-in, from nothing.
	_rig.grounded = true
	_render(TICK)
	var first := _rig.sway.amount()
	assert_float(first).is_between(0.0, 0.01)
	_render(_tuning.sprint_sway_ease_in * 0.5)
	assert_float(_rig.sway.amount()).is_between(0.3, 0.7)
	_render(_tuning.sprint_sway_ease_in * 0.5 + 0.05)
	assert_float(_rig.sway.amount()).is_greater(0.99)


func test_a_sprint_jump_of_the_player_has_no_sway_from_the_first_airborne_tick() -> void:
	_player.set_physics_process(true)
	var run := PlayerCommand.new()
	run.move = Vector2(0.0, -1.0)
	run.sprint = true
	for i in 90:
		_player.submit_command(run)
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
	assert_bool(_player.state.on_floor).is_true()
	assert_float(_rig.sway.amount()).is_greater(0.99)
	# Jump with the sprint key held until the body is on the ground again.
	var jump := PlayerCommand.new()
	jump.move = Vector2(0.0, -1.0)
	jump.sprint = true
	jump.jump = true
	var airborne_ticks := 0
	var worst := 0.0
	for i in 120:
		_player.submit_command(jump)
		await get_tree().physics_frame
		_rig.step(TICK, 1.0)
		jump.jump = false
		if not _player.state.on_floor:
			airborne_ticks += 1
			worst = maxf(worst, _lens_angle())
			assert_bool(_player.state.sprinting).is_true()
			assert_float(_rig.sway.amount()).is_equal(0.0)
	# It really was a jump, with the sprint held in the air, and the view did not move for it.
	assert_int(airborne_ticks).is_greater(20)
	assert_float(worst).is_less(0.0001)
	# Back on the ground and still sprinting: the sway is coming back.
	assert_bool(_player.state.on_floor).is_true()
	assert_float(_rig.sway.level).is_greater(0.0)
