class_name PlayerSimulation
extends RefCounted
## The player's movement rules: `simulate(body, state, command, tuning, delta)` advances one tick.
##
## It reads only its arguments and the physics world, and writes only `state` and `body`. It does
## not read the Input singleton, the camera, the animation or the clock, so the same commands from
## the same state give the same result on a client (prediction, replay) and on the server.
## It can run in any callback, physics frame or not (a network handler replaying a batch in an idle
## frame): `_slide` makes `move_and_slide` step by `delta` whatever delta the engine would use, and
## the floor snap is done here from the carried `on_floor` instead of the body's own contact cache,
## which a rewind does not restore (docs/research/player-controller.md).


static func simulate(
	body: CharacterBody3D,
	state: PlayerMotionState,
	command: PlayerCommand,
	tuning: PlayerTuning,
	delta: float
) -> void:
	state.jumped = false
	state.landed = false
	state.footstep = false
	body.global_position = state.position
	body.velocity = state.velocity

	state.view_yaw = command.yaw
	state.view_pitch = command.pitch
	state.crouching = command.crouch
	state.aiming = command.aim
	if command.fire:
		state.fire_age = 0.0
	else:
		state.fire_age = minf(state.fire_age + delta, PlayerMotionState.NEVER_FIRED)
	if command.swap_shoulder:
		state.shoulder_side = -state.shoulder_side

	var wish := (
		(Basis(Vector3.UP, command.yaw) * Vector3(command.move.x, 0.0, command.move.y))
		. limit_length(1.0)
	)
	state.sprinting = _sprint_allowed(state, command, tuning)
	_face(state, wish, command, tuning, delta)
	_move(body, state, wish, command, tuning, delta)

	state.position = body.global_position
	state.velocity = body.velocity


## Sprint works in every direction while not aiming: the body turns to face the way it goes, so a
## sprint backward (toward the camera) is a sprint forward for the body. It needs the ground (and
## keeps going through a jump from a sprint), and input pushed past `sprint_min_input`.
static func _sprint_allowed(
	state: PlayerMotionState, command: PlayerCommand, tuning: PlayerTuning
) -> bool:
	return (
		command.sprint
		and not command.aim
		and (state.on_floor or state.sprinting)
		and command.move.length() >= tuning.sprint_min_input
	)


static func _face(
	state: PlayerMotionState,
	wish: Vector3,
	command: PlayerCommand,
	tuning: PlayerTuning,
	delta: float
) -> void:
	if command.aim:
		state.facing = rotate_toward(state.facing, command.yaw, tuning.aim_turn_speed * delta)
	elif state.fire_age < tuning.hip_fire_hold:
		# Firing from the hip: the body faces where the shots go, whichever way it walks.
		state.facing = rotate_toward(state.facing, command.yaw, tuning.hip_fire_turn_speed * delta)
	elif wish.length_squared() > 0.01:
		var wanted := atan2(-wish.x, -wish.z)
		var rate := tuning.sprint_turn_speed if state.sprinting else tuning.turn_speed
		if absf(angle_difference(state.facing, wanted)) > deg_to_rad(tuning.pivot_angle_degrees):
			rate = maxf(rate, tuning.pivot_turn_speed)
		state.facing = rotate_toward(state.facing, wanted, rate * delta)


## The speed the input asks for, at full push: sprint, aim (slower, and slower still backing away
## from the view) or run.
static func _target_speed(
	state: PlayerMotionState, command: PlayerCommand, tuning: PlayerTuning
) -> float:
	if command.aim:
		var push := command.move.length()
		var back := maxf(command.move.y, 0.0) / push if push > 0.001 else 0.0
		return tuning.aim_speed * lerpf(1.0, tuning.aim_backpedal_scale, back)
	return tuning.sprint_speed if state.sprinting else tuning.run_speed


## Straight acceleration toward `target` (a velocity): gains at the ground or sprint rate, loses
## at the friction rate with no input and at the deceleration rate when slowing to a lower pace.
static func _approach(
	horizontal: Vector3, target: Vector3, tuning: PlayerTuning, delta: float
) -> Vector3:
	var speed := horizontal.length()
	var wanted := target.length()
	var rate: float
	if wanted < 0.001:
		rate = tuning.sprint_friction if speed > tuning.run_speed else tuning.ground_friction
	elif wanted < speed:
		rate = tuning.ground_deceleration
	else:
		rate = (
			tuning.sprint_acceleration if speed >= tuning.run_speed else tuning.ground_acceleration
		)
	return horizontal.move_toward(target, rate * delta)


## Free movement on the ground (not aiming): the velocity turns toward the wish like the body does,
## an arc at the turn rate, so the body faces where it goes. A change of direction wider than the
## pivot angle plants instead: the speed is shed along the old heading, then the way is open.
static func _steer(
	horizontal: Vector3,
	wish: Vector3,
	speed: float,
	state: PlayerMotionState,
	tuning: PlayerTuning,
	delta: float
) -> Vector3:
	if wish.length_squared() < 0.0001:
		return _approach(horizontal, Vector3.ZERO, tuning, delta)
	var target := wish.length() * speed
	var direction := wish.normalized()
	var pivot := deg_to_rad(tuning.pivot_angle_degrees)
	var current := horizontal.length()
	# The body has to face the way before it hurries: no moonwalking out of a turn on the spot.
	var facing_error := absf(angle_difference(state.facing, atan2(-direction.x, -direction.z)))
	if facing_error > pivot:
		target = minf(target, tuning.pivot_walk_speed)
	if current > tuning.steer_min_speed:
		var angle := horizontal.signed_angle_to(direction, Vector3.UP)
		if absf(angle) > pivot:
			var planted := maxf(current - tuning.pivot_brake * delta, 0.0)
			return horizontal / current * planted
		var rate := tuning.sprint_turn_speed if state.sprinting else tuning.turn_speed
		var turned := horizontal.rotated(Vector3.UP, clampf(angle, -rate * delta, rate * delta))
		return _approach(turned, turned / current * target, tuning, delta)
	# Standing or nearly: no arc to follow.
	return _approach(horizontal, direction * target, tuning, delta)


static func _move(
	body: CharacterBody3D,
	state: PlayerMotionState,
	wish: Vector3,
	command: PlayerCommand,
	tuning: PlayerTuning,
	delta: float
) -> void:
	var on_floor := state.on_floor
	if on_floor:
		state.coyote = tuning.coyote_time
	else:
		state.coyote = maxf(state.coyote - delta, 0.0)
	state.jump_buffer = (
		tuning.jump_buffer_time if command.jump else maxf(state.jump_buffer - delta, 0.0)
	)

	var speed := _target_speed(state, command, tuning)

	var velocity := body.velocity
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if not on_floor:
		if wish.length_squared() > 0.0:
			horizontal = horizontal.move_toward(wish * speed, tuning.air_acceleration * delta)
	elif command.aim or state.fire_age < tuning.hip_fire_hold:
		# Strafing (aiming, or firing from the hip): the body faces the view, so the velocity goes
		# straight to the wish and the pivot rules, which follow the body's heading, do not apply.
		horizontal = _approach(horizontal, wish * speed, tuning, delta)
	else:
		horizontal = _steer(horizontal, wish, speed, state, tuning, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var gravity := (
		float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * tuning.gravity_scale
	)
	if on_floor:
		velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -tuning.terminal_velocity)
	if state.jump_buffer > 0.0 and state.coyote > 0.0:
		velocity.y = sqrt(2.0 * gravity * tuning.jump_height)
		state.jump_buffer = 0.0
		state.coyote = 0.0
		state.jumped = true

	var fall_speed := -velocity.y
	body.velocity = velocity
	_slide(body, on_floor, delta)

	state.on_floor = body.is_on_floor()
	if state.on_floor and not on_floor and fall_speed > 0.0:
		state.landed = true
		state.landed_speed = fall_speed

	var ground_speed := Vector2(body.velocity.x, body.velocity.z).length()
	if state.on_floor and ground_speed >= 0.5:
		state.step_travelled += ground_speed * delta
		if state.step_travelled >= tuning.step_distance:
			state.step_travelled -= tuning.step_distance
			state.footstep = true


## `CharacterBody3D.move_and_slide` ignores its caller's time: it steps by the physics delta in a
## physics frame and by the frame (wall time) delta anywhere else. So the velocity is scaled to make
## the engine's step equal `delta`, and scaled back after, which is exact because sliding only
## projects the velocity. The body's own floor snap is off for the call and done after from
## `was_on_floor` (the carried state, the same rule as the engine's): the engine's cache of whether
## the last call touched the floor is not restored by a rewind, so it would snap or not at random.
static func _slide(body: CharacterBody3D, was_on_floor: bool, delta: float) -> void:
	var engine_delta := (
		body.get_physics_process_delta_time()
		if Engine.is_in_physics_frame()
		else body.get_process_delta_time()
	)
	var scale := 1.0
	if engine_delta > 0.0 and delta > 0.0:
		scale = delta / engine_delta
	else:
		push_error("PlayerSimulation: no engine delta to step the body by (first frame?)")
	var snap_length := body.floor_snap_length
	var facing_up := body.velocity.y > 0.0
	body.floor_snap_length = 0.0
	body.velocity *= scale
	body.move_and_slide()
	body.velocity /= scale
	body.floor_snap_length = snap_length
	if was_on_floor and not facing_up and not body.is_on_floor():
		body.apply_floor_snap()
