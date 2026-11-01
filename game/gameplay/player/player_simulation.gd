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
	state.stepped_up = 0.0
	body.global_position = state.position
	body.velocity = state.velocity
	# The body's shape follows the carried state, so a rewind to a crouch (or a stand) restores it.
	_set_stance(body, state.crouching, tuning)

	state.view_yaw = command.yaw
	state.view_pitch = command.pitch
	state.crouching = _next_stance(body, state, command, tuning)
	_set_stance(body, state.crouching, tuning)
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
		and not state.crouching
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
	var crouch_scale := tuning.crouch_speed / tuning.run_speed if state.crouching else 1.0
	if command.aim:
		var push := command.move.length()
		var back := maxf(command.move.y, 0.0) / push if push > 0.001 else 0.0
		return tuning.aim_speed * lerpf(1.0, tuning.aim_backpedal_scale, back) * crouch_scale
	return (tuning.sprint_speed if state.sprinting else tuning.run_speed) * crouch_scale


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
	if state.jump_buffer > 0.0 and state.coyote > 0.0 and not state.crouching:
		velocity.y = sqrt(2.0 * gravity * tuning.jump_height)
		state.jump_buffer = 0.0
		state.coyote = 0.0
		state.jumped = true

	var fall_speed := -velocity.y
	body.velocity = velocity
	if on_floor and velocity.y <= 0.0:
		state.stepped_up = _step_up(body, tuning, delta)
	# While a step settles the foot is over the ledge's edge: a snap would pull it back down.
	_slide(body, on_floor and state.step_settle <= 0.0 and state.stepped_up <= 0.0, delta)

	state.on_floor = body.is_on_floor()
	_settle_step(body, state, tuning, delta)
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


## A low ledge in the way of this tick's walk: lifts the body onto its top and returns the rise in
## metres (0 when there is no ledge to climb), and the slide that follows carries it on over the
## top. A ledge is a wall (not a slope) the body is blocked by whose top is within `step_height`
## above its feet, with room for the body above it and a walkable top; anything else is left to the
## engine. Only physics queries are used, so a replay from the same state climbs the same ledges.
static func _step_up(body: CharacterBody3D, tuning: PlayerTuning, delta: float) -> float:
	if tuning.step_height <= 0.0:
		return 0.0
	var motion := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if motion.length_squared() < 0.000001:
		return 0.0
	var origin := body.global_transform
	var hit := KinematicCollision3D.new()
	if not body.test_move(origin, motion, hit):
		return 0.0
	if hit.get_normal().angle_to(Vector3.UP) <= body.floor_max_angle:
		return 0.0  # a slope: the engine walks it
	# The top of the thing in the way, a hair inside its face where the body is blocked.
	var inside := -Vector3(hit.get_normal().x, 0.0, hit.get_normal().z).normalized() * 0.03
	var reach := hit.get_position() + inside
	var feet := origin.origin.y
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(reach.x, feet + tuning.step_height + tuning.step_clearance, reach.z),
		Vector3(reach.x, feet, reach.z),
		body.collision_mask,
		[body.get_rid()]
	)
	var top := body.get_world_3d().direct_space_state.intersect_ray(query)
	if top.is_empty():
		return 0.0
	var normal: Vector3 = top.normal
	var rise: float = (top.position as Vector3).y - feet
	if normal.angle_to(Vector3.UP) > body.floor_max_angle:
		return 0.0
	if rise < tuning.step_min_rise or rise > tuning.step_height:
		return 0.0
	# Room for the body: nothing overhead on the way up, nothing in the way once over the ledge.
	var lifted := rise + 2.0 * body.safe_margin
	if body.test_move(origin, Vector3.UP * lifted):
		return 0.0
	var over := origin.translated(Vector3.UP * lifted)
	if body.test_move(over, motion):
		return 0.0
	body.global_position += Vector3.UP * lifted
	return rise


## Right after a step up the lifted body's rounded foot is still over the ledge's edge, not on its
## top: the engine says "no floor" for a few ticks though the body is where it should be. For
## `step_settle_distance` of walking the carried flag stays "on the floor" (no fall, no landing, no
## sag); once the foot is over the top the engine's own answer is back.
static func _settle_step(
	body: CharacterBody3D, state: PlayerMotionState, tuning: PlayerTuning, delta: float
) -> void:
	if state.stepped_up > 0.0:
		state.step_settle = tuning.step_settle_distance
	elif state.step_settle > 0.0:
		var walked := Vector2(body.velocity.x, body.velocity.z).length() * delta
		state.step_settle = maxf(state.step_settle - walked, 0.0)
	if not state.on_floor and state.step_settle > 0.0:
		state.on_floor = true
	elif state.on_floor:
		state.step_settle = 0.0


## Crouching starts on the ground when the key is down, and ends when it is let go and the standing
## body fits where it is: under a low beam the crouch holds, key or not. In the air a crouch does
## not start (one that was on the ground carries over until the body can stand).
static func _next_stance(
	body: CharacterBody3D, state: PlayerMotionState, command: PlayerCommand, tuning: PlayerTuning
) -> bool:
	if state.crouching:
		return command.crouch or not _standing_fits(body, tuning)
	return command.crouch and state.on_floor


## The capsule of the body, resized to the stance: the feet stay where they are, so the shape grows
## up from them. A body with no capsule (a test's stand-in) is left alone.
static func _set_stance(body: CharacterBody3D, crouching: bool, tuning: PlayerTuning) -> void:
	var node := _capsule_node(body)
	if node == null:
		return
	var capsule := node.shape as CapsuleShape3D
	var height := tuning.crouch_height if crouching else tuning.height
	if not is_equal_approx(capsule.height, height):
		capsule.height = height
		node.position.y = height * 0.5


static func _capsule_node(body: CharacterBody3D) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			return child
	return null


## Whether the standing capsule would be clear of the world from the body's feet: a probe of the
## standing shape a `crouch_probe_skin` shorter at both ends and narrower, so the floor under the
## feet and the walls beside them do not count, only what is overhead.
static func _standing_fits(body: CharacterBody3D, tuning: PlayerTuning) -> bool:
	var skin := tuning.crouch_probe_skin
	var probe := CapsuleShape3D.new()
	probe.radius = maxf(tuning.radius - skin, 0.05)
	probe.height = maxf(tuning.height - 2.0 * skin, probe.radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = body.global_transform.translated_local(Vector3.UP * tuning.height * 0.5)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
