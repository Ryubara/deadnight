class_name ThirdPersonCamera
extends Node3D
## Over-the-shoulder camera rig: look (mouse and stick), spring-damped follow of the body, aim and
## sprint transitions, shoulder swap, wall and head clearance. Why each number is what it is:
## docs/research/shoulder-camera.md.
##
## The rig is a top-level node and the view's yaw and pitch are the player's input, applied raw so
## the reticle always points where the shots go. Everything else is eased with critically damped
## springs (`DampedSpring`): the pivot that follows the body, the aim zoom, the sprint pull-back
## and the shoulder swap. The body itself is never read at render time: `track()` records its
## position after each physics tick and `step()` draws the blend of the last two, so the picture
## moves smoothly at any frame rate (physics interpolation done by hand, since the camera is a
## free node). `step()` takes the time step and the blend as arguments, so a test drives it with
## fixed numbers and no wall time.
##
## A shot shakes the view (`shake`, docs/design/camera-shake.md) but never the aim: the lens node
## turns by the shake, while `aim_transform()` stays the unshaken view the crosshair ray and the
## weapon's aim are taken from.

## The body is hidden or shown (the lens is too close to the head, or clear of it again).
signal body_hidden_changed(hidden: bool)

## Every player's body is in this group; the camera looks through all of them.
const BODY_GROUP := &"player_bodies"

## Yaw in radians; the player's body follows this while aiming.
var yaw := 0.0
## Pitch in radians; positive looks up.
var pitch := 0.0
var invert_y := false
var sensitivity := 1.0
## +1 camera over the right shoulder, -1 over the left. Set from the player's state.
var side := 1.0
var aiming := false
## True while the player fires from the hip (the trigger was held within the hip-fire delay): the
## camera eases part of the way into the aim view. The player sets it from the motion state.
var hip_firing := false
## True while the body sprints (not just the key: `PlayerMotionState.sprinting`).
var sprinting := false

## The shot shake of the view (trauma, scale); null before `setup`.
var shake: CameraShake

var _tuning: PlayerTuning
var _aim_transform := Transform3D.IDENTITY
var _target: CharacterBody3D
var _previous := Vector3.ZERO
var _current := Vector3.ZERO
var _pivot := DampedSpring3.new()
var _aim := DampedSpring.new()
var _hip := DampedSpring.new()
var _sprint := DampedSpring.new()
var _side := DampedSpring.new(1.0)
var _shoulder_cap := 1.0
var _arm_cap := 1.0
var _line_cap := 1.0
var _lens_distance := 0.0
var _body_hidden := false
var _look_input := Vector2.ZERO
var _steering := false
var _steer_yaw := 0.0
var _steer_pitch := 0.0
var _steer_velocity := Vector2.ZERO

@onready var _camera: Camera3D = $Camera3D


## Called by the player once: which body to follow, and the numbers.
func setup(target: CharacterBody3D, tuning: PlayerTuning) -> void:
	_target = target
	_tuning = tuning
	shake = CameraShake.new(tuning)
	top_level = true
	# The rig and its lens are placed every drawn frame from the body's last two ticks (`step`):
	# the engine's physics interpolation would blend that a second time and lag it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	target.add_to_group(BODY_GROUP)
	_side.snap(side)
	snap_to(target.global_position)


## The body is at `position` after a physics tick. Call once per tick.
func track(position: Vector3) -> void:
	if position.distance_to(_current) > _tuning.snap_distance:
		snap_to(position)
		return
	_previous = _current
	_current = position


## Jump to `position` at rest (spawn, teleport, a correction too big to ease).
func snap_to(position: Vector3) -> void:
	_previous = position
	_current = position
	var head := position + Vector3(0.0, _tuning.pivot_height, 0.0)
	_pivot.snap(head)
	_aim.snap(1.0 if aiming else 0.0)
	_hip.snap(0.0)
	_sprint.snap(0.0)
	_side.snap(side)
	_shoulder_cap = 1.0
	_arm_cap = 1.0
	_line_cap = 1.0
	_place(head, 0.0)


## Turn the view by radians: yaw to the right, pitch down (mouse convention). Honours invert Y.
func apply_look(yaw_right: float, pitch_down: float) -> void:
	yaw = wrapf(yaw - yaw_right, -PI, PI)
	var direction := 1.0 if invert_y else -1.0
	pitch = clampf(
		pitch + direction * pitch_down,
		deg_to_rad(_tuning.pitch_min_degrees),
		deg_to_rad(_tuning.pitch_max_degrees)
	)


## Mouse motion in pixels.
func look_mouse(relative: Vector2) -> void:
	var scale_factor := _tuning.mouse_radians_per_pixel * sensitivity * _look_scale()
	apply_look(relative.x * scale_factor, relative.y * scale_factor)


## Right stick, x right and y down, -1..1; held until set again and applied every frame.
func set_stick(stick: Vector2) -> void:
	_look_input = stick


## Turn the view toward `target_yaw` and `target_pitch` (radians) with a spring, every `step()`
## until `stop_steering()` (the first call sets the view there at once). For a driver that gives
## a new heading in steps (the autopilot).
func steer(target_yaw: float, target_pitch: float) -> void:
	if not _steering:
		# The first heading is where the driver starts looking: no swing from wherever it was.
		yaw = target_yaw
		pitch = target_pitch
	_steering = true
	_steer_yaw = target_yaw
	_steer_pitch = target_pitch


func stop_steering() -> void:
	_steering = false
	_steer_velocity = Vector2.ZERO


func is_aim_zoomed() -> bool:
	return aim_amount() > 0.5


## How far the aim zoom has eased in, 0 to 1.
func aim_amount() -> float:
	return clampf(_aim.value, 0.0, 1.0)


## How far the view is zoomed toward the aim view, 0 to 1: the full aim zoom, or the share
## `PlayerTuning.hip_fire_zoom` of it while firing from the hip. Placement reads this; the look
## sensitivity reads only `aim_amount()` (a burst from the hip does not slow the view down).
func zoom_amount() -> float:
	var hip := clampf(_hip.value, 0.0, 1.0) * _tuning.hip_fire_zoom
	var aim := aim_amount()
	return aim + (1.0 - aim) * hip


## How far the hip-fire zoom has eased in, 0 to 1 (of its own share, not of the aim view).
func hip_amount() -> float:
	return clampf(_hip.value, 0.0, 1.0)


## How far the sprint pull-back has eased in, 0 to 1.
func sprint_amount() -> float:
	return clampf(_sprint.value, 0.0, 1.0)


func camera() -> Camera3D:
	return _camera


## Adds a shot's trauma to the view shake (`WeaponDef.shake_trauma`); the player's setting scales
## it.
func add_shake(trauma: float) -> void:
	if shake != null:
		shake.add(trauma)


## The view the crosshair sees, without the shake: the lens place (`origin`) and turn (`-basis.z`)
## the aim ray, the weapon's aim and the shot are taken from.
func aim_transform() -> Transform3D:
	return _aim_transform


## Distance from the player's head (the pivot height) to the lens, after the walls.
func lens_distance() -> float:
	return _lens_distance


## True while the lens is too close to the head to draw the body (with a margin so it does not
## flicker at the edge).
func is_body_hidden() -> bool:
	return _body_hidden


## The smoothed pivot the camera orbits; it lags the body a little.
func pivot_position() -> Vector3:
	return global_position


func _process(delta: float) -> void:
	if _tuning != null:
		step(delta, Engine.get_physics_interpolation_fraction())


## Advance the eases by `delta` seconds and place the camera, drawing the body `fraction` (0 to 1)
## of the way from where it was one physics tick ago to where it is now.
func step(delta: float, fraction: float) -> void:
	if _look_input != Vector2.ZERO:
		var stick := _look_input * _look_input.length()
		var rate := (
			deg_to_rad(_tuning.stick_degrees_per_second) * sensitivity * _look_scale() * delta
		)
		apply_look(stick.x * rate, stick.y * rate)
	if _steering:
		_steer_view(delta)
	shake.step(delta)
	_aim.step(1.0 if aiming else 0.0, _tuning.aim_frequency, delta)
	var hip_in := hip_firing and not aiming
	_hip.step(
		1.0 if hip_in else 0.0,
		_tuning.hip_fire_zoom_frequency if hip_in else _tuning.hip_fire_release_frequency,
		delta
	)
	_sprint.step(1.0 if sprinting and not aiming else 0.0, _tuning.sprint_frequency, delta)
	_side.step(side, _tuning.swap_frequency, delta)
	var head := _previous.lerp(_current, fraction) + Vector3(0.0, _tuning.pivot_height, 0.0)
	var follow := lerpf(_tuning.follow_frequency, _tuning.sprint_follow_frequency, sprint_amount())
	_pivot.step(head, Vector3(follow, _tuning.follow_frequency_vertical, follow), delta)
	_place(head, delta)


func _steer_view(delta: float) -> void:
	var yaw_step := DampedSpring.advance(
		-angle_difference(yaw, _steer_yaw), _steer_velocity.x, _tuning.steer_frequency, delta
	)
	var pitch_step := DampedSpring.advance(
		pitch - _steer_pitch, _steer_velocity.y, _tuning.steer_frequency, delta
	)
	yaw = wrapf(_steer_yaw + yaw_step.x, -PI, PI)
	pitch = _steer_pitch + pitch_step.x
	_steer_velocity = Vector2(yaw_step.y, pitch_step.y)


## The bodies of every player, which the camera sweeps through.
func _bodies() -> Array[RID]:
	var bodies: Array[RID] = []
	for node in get_tree().get_nodes_in_group(BODY_GROUP):
		if node is CollisionObject3D:
			bodies.append((node as CollisionObject3D).get_rid())
	return bodies


func _look_scale() -> float:
	return lerpf(1.0, _tuning.aim_sensitivity_scale, aim_amount())


## The lens for the current eases, swept through the world from the true `head` (never from the
## lagging pivot alone, which may be behind a corner): pulled in at once, let out slowly.
func _place(head: Vector3, delta: float) -> void:
	var aim := zoom_amount()
	var sprint := sprint_amount()
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var space := get_world_3d().direct_space_state
	var mask := _target.collision_mask
	var exclude := _bodies()
	# The lagging pivot may be behind a corner or a wall: stop it at the first thing on the way.
	var lag := _pivot.value - head
	var lag_fraction := CameraPlacement.sweep(space, exclude, mask, head, lag, _tuning.arm_margin)
	var pivot := head + lag * lag_fraction
	var shoulder := lerpf(_tuning.shoulder_offset, _tuning.shoulder_offset_aim, aim)
	var arm := (
		lerpf(_tuning.arm_length, _tuning.arm_length_aim, aim) + _tuning.sprint_arm_extra * sprint
	)
	var placed := CameraPlacement.place(
		space,
		exclude,
		mask,
		pivot,
		basis,
		clampf(_side.value, -1.0, 1.0) * shoulder,
		arm,
		_tuning.arm_margin,
		_shoulder_cap,
		_arm_cap,
		_line_cap
	)
	_shoulder_cap = _let_out(_shoulder_cap, placed["raw_shoulder"], delta)
	_arm_cap = _let_out(_arm_cap, placed["raw_arm"], delta)
	_line_cap = _let_out(_line_cap, placed["raw_line"], delta)
	var lens: Vector3 = placed["camera"]
	_aim_transform = Transform3D(basis, lens)
	# The lens turns where it stands; the aim keeps the unshaken view.
	_camera.global_transform = Transform3D(basis * shake.rotation(), lens)
	_camera.fov = lerpf(_tuning.fov, _tuning.fov_aim, aim) + _tuning.sprint_fov_kick * sprint
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pivot)
	_lens_distance = lens.distance_to(head)
	_update_body_visibility()


## A cap on how much of the shoulder or arm may be used: down at once to what the sweep allows,
## back up at the release speed.
func _let_out(cap: float, allowed: float, delta: float) -> float:
	if allowed <= cap:
		return allowed
	return minf(allowed, lerpf(cap, allowed, 1.0 - exp(-_tuning.release_frequency * delta)))


func _update_body_visibility() -> void:
	var limit := _tuning.show_body_distance if _body_hidden else _tuning.hide_body_distance
	var hide := _lens_distance < limit
	if hide != _body_hidden:
		_body_hidden = hide
		body_hidden_changed.emit(hide)
