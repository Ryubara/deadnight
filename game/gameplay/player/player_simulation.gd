class_name PlayerSimulation
extends RefCounted
## The player's movement rules: `simulate(body, state, command, tuning, delta)` advances one tick.
##
## It reads only its arguments and the physics world, and writes only `state` and `body`. It does
## not read the Input singleton, the camera, the animation or the clock, so the same commands from
## the same state give the same result on a client (prediction, replay) and on the server.
## `delta` must be the engine's physics delta because CharacterBody3D.move_and_slide uses it.


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
	if command.swap_shoulder:
		state.shoulder_side = -state.shoulder_side

	var wish := (
		(Basis(Vector3.UP, command.yaw) * Vector3(command.move.x, 0.0, command.move.y))
		. limit_length(1.0)
	)
	_face(state, wish, command, tuning, delta)
	_move(body, state, wish, command, tuning, delta)

	state.position = body.global_position
	state.velocity = body.velocity


static func _face(
	state: PlayerMotionState,
	wish: Vector3,
	command: PlayerCommand,
	tuning: PlayerTuning,
	delta: float
) -> void:
	if command.aim:
		state.facing = rotate_toward(state.facing, command.yaw, tuning.aim_turn_speed * delta)
	elif wish.length_squared() > 0.01:
		state.facing = rotate_toward(
			state.facing, atan2(-wish.x, -wish.z), tuning.turn_speed * delta
		)


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

	state.sprinting = command.sprint and not command.aim and on_floor and command.move.y < -0.1
	var speed := (
		tuning.aim_speed
		if command.aim
		else (tuning.sprint_speed if state.sprinting else tuning.run_speed)
	)

	var velocity := body.velocity
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length_squared() > 0.0:
		var accel := tuning.ground_acceleration if on_floor else tuning.air_acceleration
		horizontal = horizontal.move_toward(wish * speed, accel * delta)
	elif on_floor:
		horizontal = horizontal.move_toward(Vector3.ZERO, tuning.ground_friction * delta)
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
	body.move_and_slide()

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
