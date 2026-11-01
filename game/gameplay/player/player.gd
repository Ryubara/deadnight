class_name Player
extends CharacterBody3D
## Third-person player node: samples the controls into a command each physics tick, runs the
## simulation, and shows the result (body facing, camera, signals).
##
## Movement lives in PlayerSimulation, not here. This node is the boundary: input goes in as a
## PlayerCommand, state comes out as a PlayerMotionState. The camera rig and the animation tree
## read the state; they never move the character. To drive the player from a server or a replay, set
## `local_input` to false and call `submit_command()` before each tick (or call `tick()`).

## A foot has landed. Hook footstep audio here.
signal footstep(speed: float, sprinting: bool)
signal jumped
## Back on the ground after a fall or jump; `impact_speed` is the downward speed in m/s.
signal landed(impact_speed: float)

## Below this the model counts as level with the body again.
const STEP_LAG_REST := 0.0005

const ACTION_FORWARD := &"move_forward"
const ACTION_BACK := &"move_back"
const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_SPRINT := &"sprint"
const ACTION_CROUCH := &"crouch"
const ACTION_JUMP := &"jump"
const ACTION_AIM := &"aim"
const ACTION_FIRE := &"fire"
const ACTION_SWAP_SHOULDER := &"swap_shoulder"
const ACTION_THROW_GRENADE := &"throw_grenade"
const ACTION_TOSS_GRENADE := &"toss_grenade"
const ACTION_LOOK_LEFT := &"look_left"
const ACTION_LOOK_RIGHT := &"look_right"
const ACTION_LOOK_UP := &"look_up"
const ACTION_LOOK_DOWN := &"look_down"

@export var tuning: PlayerTuning = preload("res://gameplay/player/player_tuning_default.tres")
## Sample the local keyboard, mouse and gamepad. Turn off to feed commands with `submit_command()`.
@export var local_input := true
## Hide and capture the mouse while controls are enabled.
@export var capture_mouse := true

## The authoritative-looking result of the last tick. Read-only for everything but `tick()`.
var state := PlayerMotionState.new()
var last_command := PlayerCommand.new()

var _controls_enabled := true
var _was_down := {}
var _submitted: PlayerCommand
## Metres the drawn model is still below the body after a step up (it eases up, the body does not).
var _step_lag := 0.0
var _model_rest := Vector3.ZERO

@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var _model: Node3D = $Model
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	_shape.shape = capsule
	_shape.position.y = tuning.height * 0.5
	_model.scale = Vector3.ONE * tuning.model_scale
	_model_rest = _model.position
	state.position = global_position
	state.facing = rotation.y
	dress(CharacterLook.default_look())
	camera_rig.setup(self, tuning)
	camera_rig.body_hidden_changed.connect(_on_body_hidden_changed)
	camera_rig.yaw = rotation.y
	refresh_settings()
	var service := get_tree().root.get_node_or_null(PlayerSettings.SERVICE_PATH)
	if service != null and service.has_signal(&"changed"):
		service.connect(&"changed", _on_setting_changed)
	set_controls_enabled(true)


func _physics_process(_delta: float) -> void:
	var command := _submitted
	if command == null:
		command = sample_command() if local_input else _idle_command()
	_submitted = null
	tick(command)


func _unhandled_input(event: InputEvent) -> void:
	if not local_input:
		return
	if event is InputEventMouseMotion and _controls_enabled:
		camera_rig.look_mouse((event as InputEventMouseMotion).relative)
	elif event.is_action_pressed(&"pause") and capture_mouse and _controls_enabled:
		set_controls_enabled(false)
	elif (
		event is InputEventMouseButton and event.pressed and capture_mouse and not _controls_enabled
	):
		set_controls_enabled(true)


## Re-read sensitivity, invert Y and camera shake from the settings service (defaults when there
## is none).
func refresh_settings() -> void:
	camera_rig.sensitivity = PlayerSettings.sensitivity(get_tree())
	camera_rig.invert_y = PlayerSettings.invert_y(get_tree())
	camera_rig.shake.scale = PlayerSettings.camera_shake(get_tree())


## Puts a look and the armband of a seat on the body's Soldier (`CharacterAssembler.dress`). A body
## wears the default look until the night says otherwise.
func dress(look: CharacterLook, seat := 0) -> void:
	CharacterAssembler.dress(_model, look, seat)


## The lens is too close to the head (or clear again): draw or hide the body.
func _on_body_hidden_changed(hidden: bool) -> void:
	_model.visible = not hidden


func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	refresh_settings()


## Turn movement and look on or off (menus, death, cutscenes); also captures or frees the mouse.
func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if capture_mouse and local_input:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE


## Use this command for the next physics tick instead of sampling the controls.
func submit_command(command: PlayerCommand) -> void:
	_submitted = command


## Read the controls into a command (also the stick look for the camera).
func sample_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	if not _controls_enabled:
		camera_rig.set_stick(Vector2.ZERO)
	else:
		command.move = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACK)
		command.sprint = Input.is_action_pressed(ACTION_SPRINT)
		command.crouch = Input.is_action_pressed(ACTION_CROUCH)
		command.aim = Input.is_action_pressed(ACTION_AIM)
		command.fire = Input.is_action_pressed(ACTION_FIRE)
		command.jump = _pressed_edge(ACTION_JUMP)
		command.swap_shoulder = _pressed_edge(ACTION_SWAP_SHOULDER)
		command.throw_over = Input.is_action_pressed(ACTION_THROW_GRENADE)
		command.throw_under = Input.is_action_pressed(ACTION_TOSS_GRENADE)
		camera_rig.set_stick(
			Input.get_vector(
				ACTION_LOOK_LEFT,
				ACTION_LOOK_RIGHT,
				ACTION_LOOK_UP,
				ACTION_LOOK_DOWN,
				tuning.stick_deadzone
			)
		)
	command.yaw = camera_rig.yaw
	command.pitch = camera_rig.pitch
	return command


## True on the first tick an action is held. Polled once per tick rather than
## Input.is_action_just_pressed, which can report the same press on two consecutive physics frames.
func _pressed_edge(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _was_down.get(action, false)
	_was_down[action] = down
	return edge


## What a remotely driven player does on a tick with no command: stand still, keep looking.
func _idle_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = last_command.yaw
	command.pitch = last_command.pitch
	return command


## Run one tick of the simulation with `command` and show the result.
func tick(command: PlayerCommand) -> void:
	last_command = command
	PlayerSimulation.simulate(self, state, command, tuning, get_physics_process_delta_time())
	rotation.y = state.facing
	_ease_step(state.stepped_up, get_physics_process_delta_time())
	camera_rig.aiming = state.aiming
	camera_rig.hip_firing = state.fire_age < tuning.hip_fire_zoom_delay
	camera_rig.side = state.shoulder_side
	camera_rig.sprinting = state.sprinting
	camera_rig.crouching = state.crouching
	camera_rig.track(global_position)
	if state.jumped:
		jumped.emit()
	if state.landed:
		landed.emit(state.landed_speed)
	if state.footstep:
		footstep.emit(state.ground_speed(), state.sprinting)


## The body is lifted onto a ledge in one tick (the simulation's business), the model it carries
## eases up after it: it starts the step as low as it was and gains it back at
## `PlayerTuning.step_view_frequency`. The camera's own vertical spring does the same for the view.
func _ease_step(rise: float, delta: float) -> void:
	_step_lag = (_step_lag + rise) * exp(-tuning.step_view_frequency * delta)
	if _step_lag < STEP_LAG_REST:
		_step_lag = 0.0
	_model.position = _model_rest - Vector3(0.0, _step_lag, 0.0)


## The model's drop below the body, in metres, while it eases up a ledge (0 when level).
func step_lag() -> float:
	return _step_lag


## Put the player somewhere, at rest. Use this instead of setting global_position, which the
## simulation would overwrite from `state`.
func teleport(position: Vector3) -> void:
	state.position = position
	state.velocity = Vector3.ZERO
	state.on_floor = false
	global_position = position
	_step_lag = 0.0
	_model.position = _model_rest
	# Drawn here from the next frame on, not slid in from where it stood.
	reset_physics_interpolation()
	camera_rig.snap_to(position)


func controls_enabled() -> bool:
	return _controls_enabled


func is_sprinting() -> bool:
	return state.sprinting


func is_aiming() -> bool:
	return state.aiming


## Horizontal speed in metres per second.
func ground_speed() -> float:
	return state.ground_speed()
