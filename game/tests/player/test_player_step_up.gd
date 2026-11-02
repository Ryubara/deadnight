extends OmniHarness
## Low ledges are climbed by walking into them, up to the tuned step height, and the view eases
## up instead of popping (docs/research/player-controller.md, "Stepping up").

## The ledge's face, across the player's way north (-z) from START.
const FACE_Z := 7.0
const LEDGE_DEPTH := 6.0
## The monitor refresh rate the smoothness test draws at.
const FRAME_RATE := 144.0
const FRAME_DELTA := 1.0 / FRAME_RATE

var _jumps := 0


func before_test() -> void:
	await super.before_test()
	_jumps = 0
	_player.jumped.connect(func() -> void: _jumps += 1)


## A block `height` high whose south face is at `FACE_Z`, across the way.
func _add_ledge(height: float, depth := LEDGE_DEPTH, width := 16.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, depth)
	shape.shape = box
	body.add_child(shape)
	_player.get_parent().add_child(body)
	body.global_position = Vector3(START.x, height * 0.5, FACE_Z - depth * 0.5)
	return body


## A ceiling slab `gap` above the ledge's top, over the ledge.
func _add_beam(ledge_height: float, gap: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.4, LEDGE_DEPTH)
	shape.shape = box
	body.add_child(shape)
	_player.get_parent().add_child(body)
	body.global_position = Vector3(START.x, ledge_height + gap + 0.2, FACE_Z - LEDGE_DEPTH * 0.5)
	return body


func _walk_into_it(
	move := Vector2(0.0, -1.0), seconds := 1.2, sprint := false, aim := false
) -> void:
	await _seconds(move, seconds, sprint, aim)


func _on_top_of(height: float) -> bool:
	return (
		_player.state.on_floor
		and absf(_player.state.position.y - height) < 0.02
		and _player.state.position.z < FACE_Z - 0.2
	)


# --- climbing ---


func test_a_ledge_as_high_as_the_step_height_is_climbed_without_a_jump() -> void:
	# The issue's bar: 0.3 m, climbed without jumping.
	var height := 0.3
	assert_float(_tuning.step_height).is_greater_equal(height)
	_add_ledge(height)
	await _flush_physics()
	await _walk_into_it()
	assert_bool(_on_top_of(height)).is_true()
	assert_int(_jumps).is_equal(0)


func test_a_ledge_is_climbed_at_every_pace_and_from_an_angle() -> void:
	var height := 0.25
	_add_ledge(height)
	await _flush_physics()
	var attempts := {
		"run": [Vector2(0.0, -1.0), false, false],
		"sprint": [Vector2(0.0, -1.0), true, false],
		"aim": [Vector2(0.0, -1.0), false, true],
		"diagonal": [Vector2(0.7, -0.7), false, false],
		"sprint diagonal": [Vector2(-0.7, -0.7), true, false],
	}
	for key: String in attempts:
		_player.teleport(Vector3(START.x, START.y, FACE_Z + 1.2))
		await _run(Vector2.ZERO, 20)
		var attempt: Array = attempts[key]
		await _walk_into_it(attempt[0], 1.0, attempt[1], attempt[2])
		assert_bool(_on_top_of(height)).override_failure_message("not on top: " + key).is_true()
	assert_int(_jumps).is_equal(0)


func test_climbing_does_not_stall_the_walk() -> void:
	# The ledge costs next to nothing: a run into it is only a few centimetres behind a run on the
	# flat for the same time.
	await _run(Vector2(0.0, -1.0), 90)
	var flat := START.z - _player.state.position.z
	_player.teleport(START)
	await _run(Vector2.ZERO, 20)
	_add_ledge(_tuning.step_height, 6.0)
	await _flush_physics()
	await _run(Vector2(0.0, -1.0), 90)
	var with_ledge := START.z - _player.state.position.z
	assert_float(with_ledge).is_greater(flat - 0.25)


func test_a_ledge_above_the_step_height_stays_a_wall() -> void:
	_add_ledge(0.35)
	await _flush_physics()
	await _walk_into_it()
	assert_float(_player.state.position.y).is_less(0.02)
	assert_float(_player.state.position.z).is_greater(FACE_Z)


func test_a_low_ceiling_over_the_ledge_stops_the_climb() -> void:
	var height := 0.25
	_add_ledge(height)
	_add_beam(height, 1.2)  # lower than the body's 1.8 m
	await _flush_physics()
	await _walk_into_it()
	assert_float(_player.state.position.y).is_less(0.02)
	assert_float(_player.state.position.z).is_greater(FACE_Z)


func test_a_ledge_with_enough_headroom_is_climbed_under_a_beam() -> void:
	var height := 0.25
	_add_ledge(height)
	_add_beam(height, _tuning.height + 0.2)
	await _flush_physics()
	await _walk_into_it()
	assert_bool(_on_top_of(height)).is_true()


func test_a_slope_is_walked_not_stepped() -> void:
	# The ramp is the engine's: no tick of it reports a step.
	_player.teleport(Vector3(6.0, 0.05, -4.0))
	await _run(Vector2.ZERO, 20)
	var steps := 0
	for i in 90:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0)
		_step(command)
		if _player.state.stepped_up > 0.0:
			steps += 1
	assert_float(_player.state.position.y).is_greater(0.5)  # it did climb the ramp
	assert_int(steps).is_equal(0)


func test_a_narrow_curb_is_climbed() -> void:
	# Thinner than the body is wide: no landing to fit the whole capsule on.
	var height := 0.2
	_add_ledge(height, 0.3)
	await _flush_physics()
	await _walk_into_it(Vector2(0.0, -1.0), 1.5)
	assert_float(_player.state.position.z).is_less(FACE_Z - 0.3)  # carried on, over the curb


func test_step_height_zero_turns_stepping_off() -> void:
	_tuning = _tuning.duplicate()
	_tuning.step_height = 0.0
	_player.tuning = _tuning
	_add_ledge(0.2)
	await _flush_physics()
	await _walk_into_it()
	assert_float(_player.state.position.y).is_less(0.02)


# --- the network boundary ---


func test_a_replay_climbs_the_same_ledges() -> void:
	# The step is part of the simulation: the recorded commands, run again from the start state
	# (here in a later physics callback; the idle frame of a handler is the reconcile suite's, see
	# `test_player_crouch.gd`), end in the same place.
	_add_ledge(0.2)
	_add_ledge(0.3, 3.5, 3.0).global_position += Vector3(0.0, 0.0, -1.5)
	await _flush_physics()
	var recorded: Array[PackedByteArray] = []
	var start := _player.state.duplicate_state()
	for i in 75:
		var command := PlayerCommand.new()
		command.move = Vector2(0.4 * sin(i * 0.05), -1.0).limit_length(1.0)
		command.yaw = 0.02 * sin(i * 0.03)
		command.sprint = i % 90 > 50
		command.jump = i % 120 == 119
		recorded.append(command.to_bytes())
		_step(command)
	var first_end := _player.state.duplicate_state()
	assert_float(first_end.position.y).is_greater(0.25)  # it went up both ledges
	await _flush_physics()  # the replay is a later physics callback; see the note above
	_player.state.copy_from(start)
	_player.global_position = start.position
	_player.velocity = start.velocity
	var steps := 0
	for bytes in recorded:
		PlayerSimulation.simulate(
			_player, _player.state, PlayerCommand.from_bytes(bytes), _tuning, TICK
		)
		if _player.state.stepped_up > 0.0:
			steps += 1
	assert_int(steps).is_greater(0)
	assert_float(_player.state.position.distance_to(first_end.position)).is_less(0.001)
	assert_float(_player.state.velocity.distance_to(first_end.velocity)).is_less(0.001)


# --- what is drawn ---


func test_the_model_eases_up_instead_of_popping() -> void:
	_add_ledge(_tuning.step_height)
	await _flush_physics()
	var model := _player.get_node("Model") as Node3D
	var lags: Array[float] = []
	var rise := 0.0
	for i in 120:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0)
		_step(command)
		rise += _player.state.stepped_up
		if rise > 0.0:
			lags.append(_player.step_lag())
	assert_float(rise).is_equal_approx(_tuning.step_height, 0.01)
	# The model starts most of the way down and ends level, and never gets lower in between.
	assert_float(lags[0]).is_greater(_tuning.step_height * 0.5)
	assert_float(lags[lags.size() - 1]).is_equal(0.0)
	for i in range(1, lags.size()):
		assert_float(lags[i]).is_less_equal(lags[i - 1])
	assert_float(model.position.y).is_equal(0.0)
	# About 0.2 s to 95 percent.
	var settled := lags.find_custom(func(lag: float) -> bool: return lag < rise * 0.05)
	assert_float(settled * TICK).is_between(0.1, 0.3)


func test_teleporting_drops_the_lag() -> void:
	_add_ledge(_tuning.step_height)
	await _flush_physics()
	for i in 70:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0)
		_step(command)
		if _player.state.stepped_up > 0.0:
			break
	assert_float(_player.step_lag()).is_greater(0.0)
	_player.teleport(START)
	assert_float(_player.step_lag()).is_equal(0.0)


## The largest frame-to-frame move, in metres, of the drawn model and of the camera pivot over a
## climb at 144 Hz: the model as the engine blends it between the last two ticks, the pivot as the
## camera's own spring places it. The frames that fall in each tick are two or three, the blend
## growing from 0 to 1 across them. A jerk is what the eye sees as a pop.
func _climb_at_144_hz() -> Dictionary:
	_add_ledge(_tuning.step_height)
	await _flush_physics()
	var model := _player.get_node("Model") as Node3D
	var rig := _player.camera_rig
	var drawn: Array[float] = []
	var pivots: Array[float] = []
	var frame := 0
	var stepped := false
	for tick in 150:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, -1.0)
		var before_y := _player.global_position.y + model.position.y
		_step(command)
		var after_y := _player.global_position.y + model.position.y
		stepped = stepped or _player.state.stepped_up > 0.0
		while (frame + 1) * FRAME_DELTA * 60.0 <= tick + 1.0 + 1e-6:
			frame += 1
			var fraction := clampf(frame * FRAME_DELTA * 60.0 - tick, 0.0, 1.0)
			rig.step(FRAME_DELTA, fraction)
			drawn.append(lerpf(before_y, after_y, fraction))
			pivots.append(rig.pivot_position().y)
	assert_bool(stepped).is_true()
	return {"model": _largest_step(drawn), "pivot": _largest_step(pivots)}


func test_the_view_is_smooth_at_144_hz_over_a_climb() -> void:
	var worst: Dictionary = await _climb_at_144_hz()
	# A pop of the whole step over one tick would be 0.3 m / 2.4 frames = 125 mm a frame.
	assert_float(worst.model).is_less(0.04)
	assert_float(worst.pivot).is_less(0.012)


func test_without_the_easing_the_model_pops_and_the_measure_sees_it() -> void:
	_tuning = _tuning.duplicate()
	_tuning.step_view_frequency = 1000.0
	_player.tuning = _tuning
	var worst: Dictionary = await _climb_at_144_hz()
	assert_float(worst.model).is_greater(0.1)


func _largest_step(values: Array[float]) -> float:
	var worst := 0.0
	for i in range(1, values.size()):
		worst = maxf(worst, absf(values[i] - values[i - 1]))
	return worst
