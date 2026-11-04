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
## The platform took the mouse back (a browser's Esc frees the pointer lock without a key press,
## a window lost focus) and the controls are off: the night opens its menu, as Esc would.
signal grip_lost

## The downward speed (m/s) a puppet's landing is told with: the frames carry no speed, and the
## animation's landing does not read it.
const PUPPET_LANDING_SPEED := 4.0
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
## Hide and capture the mouse while controls are enabled (never under `GDS_QUIET`, see
## `mouse_capture_allowed`).
@export var capture_mouse := true

## The authoritative-looking result of the last tick. Read-only for everything but `tick()`.
var state := PlayerMotionState.new()
## False for a body made by `strip_model`: nothing to dress or animate.
var has_model := true
## True for a body made by `make_puppet`: the drawn copy of a player on another machine.
var is_puppet := false
var last_command := PlayerCommand.new()
## Whether the mouse really is captured, as the platform says.
var grip := MouseGrip.new()
## The look belongs to something else for now (the bot command wheel reads the mouse and the right
## stick to pick an order): neither turns the view, and the move and the buttons go on.
var look_locked := false

var _controls_enabled := true
var _was_down := {}
var _submitted: PlayerCommand
## The stance the last `puppet_to` was given (`PlayerStance`), to see a jump begin and a landing.
var _puppet_stance := 0
## Metres the drawn model is still below the body after a step up (it eases up, the body does not).
var _step_lag := 0.0
var _model_rest := Vector3.ZERO

@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var _model: Node3D = $Model
@onready var _shape: CollisionShape3D = $CollisionShape3D
## Null on a body stripped of its model (a game server's).
@onready var _animation := get_node_or_null(^"AnimationTree") as PlayerAnimation


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
	# A puppet is placed by `puppet_to`; the engine turns physics processing back on when a node is
	# ready, whatever `make_puppet` asked for, so a puppet says no here (a simulated puppet fell
	# through the floor it has no collision with and was never `on_floor`).
	if is_puppet:
		return
	var command := _submitted
	if command == null:
		command = sample_command() if local_input else _idle_command()
	_submitted = null
	tick(command)


func _process(_delta: float) -> void:
	if grip.poll():
		release_grip()


func _notification(what: int) -> void:
	# A window that lost focus no longer has the cursor: the night is not played blind.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and grip.is_wanted():
		release_grip()


func _unhandled_input(event: InputEvent) -> void:
	if not local_input:
		return
	if event is InputEventMouseMotion and mouse_enabled() and not TouchLook.is_stray(event):
		if look_locked:
			return
		# Screen pixels, not the stretched `relative` (#928, `MouseMotion`).
		camera_rig.look_mouse(MouseMotion.pixels(event as InputEventMouseMotion))
	elif event.is_action_pressed(&"pause") and capture_mouse and _controls_enabled:
		set_controls_enabled(false)
	elif event is InputEventMouseButton and event.pressed and capture_mouse:
		if not _controls_enabled:
			set_controls_enabled(true)
		elif grip.is_pending():
			# The lock a click is needed for: asked again here, from the click.
			grip.retry()


## Re-read sensitivity, invert Y and camera shake from the settings service (defaults when there
## is none).
func refresh_settings() -> void:
	camera_rig.sensitivity = PlayerSettings.sensitivity(get_tree())
	camera_rig.invert_y = PlayerSettings.invert_y(get_tree())
	camera_rig.shake.scale = PlayerSettings.camera_shake(get_tree())


## Takes the Soldier's model, skeleton and animation out of a body that is not in the tree yet,
## leaving the collision and the simulation: what a game server needs of a player (`add_body`).
func strip_model() -> void:
	get_node("AnimationTree").free()
	get_node("Model").free()
	var stub := Node3D.new()
	stub.name = "Model"
	add_child(stub)
	has_model = false


## Makes this body the drawn copy of a player on another machine (`RemoteAvatars`), before it is in
## the tree: no input, no mouse, no collision (it is where the frames say, and nothing bumps into
## it), no camera of its own and no simulation. `puppet_to` places it; its `PlayerAnimation` draws
## the weapon, the pose and the clips from the same events as a body that is played.
func make_puppet() -> void:
	is_puppet = true
	local_input = false
	capture_mouse = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	var rig := get_node(^"CameraRig") as ThirdPersonCamera
	rig.set_process(false)
	release_view()


## Gives up the view: the body's camera does not start `current`, so a body that enters the tree
## after the person's never takes the view from it (the scene's camera is `current`, and the last
## one to enter would win). Call it before the body is in the tree, on every body that is not the
## one a person plays: a bot, a copy of another machine's player (#702). The camera stays, for
## aiming.
func release_view() -> void:
	(get_node(^"CameraRig/Camera3D") as Camera3D).current = false


## Puts a puppet where the frames say: at `at`, turned `facing`, moving at `velocity` (the gait
## follows it), holding the aim pose or not, looking `pitch` up (radians), in `stance` (a
## `PlayerStance`: the sprint carry, the crouch, the jump and the fall are the animation's own,
## drawn from the same state a played body has). The weapon's barrel is aimed along that look from
## the head. A step off the floor upward says `jumped`, a step back onto it `landed`, as a played
## body does.
func puppet_to(
	at: Vector3, facing: float, velocity: Vector3, aiming: bool, pitch: float, stance := 0
) -> void:
	var was_in_air := _puppet_stance & PlayerStance.AIR != 0
	var in_air := stance & PlayerStance.AIR != 0
	var rising := stance & PlayerStance.RISING != 0
	state.position = at
	state.velocity = Vector3(velocity.x, 1.0 if rising else (-1.0 if in_air else 0.0), velocity.z)
	state.facing = facing
	state.on_floor = not in_air
	state.sprinting = stance & PlayerStance.SPRINT != 0
	state.crouching = stance & PlayerStance.CROUCH != 0
	state.aiming = aiming
	position = at
	rotation.y = facing
	camera_rig.aim_along(at + Vector3(0.0, tuning.pivot_height, 0.0), facing, pitch)
	if in_air and rising and not was_in_air:
		jumped.emit()
	elif was_in_air and not in_air:
		landed.emit(PUPPET_LANDING_SPEED)
	_puppet_stance = stance


## Puts a look and the armband of a seat on the body's Soldier (`CharacterAssembler.dress`). A body
## wears the default look until the night says otherwise.
func dress(look: CharacterLook, seat := 0) -> void:
	if has_model:
		CharacterAssembler.dress(_model, look, seat)


## The lens is too close to the head (or clear again): draw or hide the body.
func _on_body_hidden_changed(hidden: bool) -> void:
	if not is_puppet:
		_model.visible = not hidden


func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	refresh_settings()


## False when the kit's `gds godot` started this program on its hidden desktop
## (`GDS_QUIET=1`): a captured mouse there clips the real cursor of the person at the
## machine to the hidden window (kit docs/godot/no-focus.md).
static func mouse_capture_allowed() -> bool:
	return OS.get_environment("GDS_QUIET") != "1"


## Turn movement and look on or off (menus, death, cutscenes); also captures or frees the mouse.
func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if capture_mouse and local_input and mouse_capture_allowed():
		grip.want(enabled)


## The controls go off because the platform freed the mouse; `grip_lost` tells the night.
func release_grip() -> void:
	set_controls_enabled(false)
	grip_lost.emit()


## Use this command for the next physics tick instead of sampling the controls.
func submit_command(command: PlayerCommand) -> void:
	_submitted = command


## Read the controls into a command (also the stick look for the camera).
func sample_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	if not controls_enabled():
		camera_rig.set_stick(Vector2.ZERO)
	else:
		command.move = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACK)
		command.sprint = Input.is_action_pressed(ACTION_SPRINT)
		command.crouch = Input.is_action_pressed(ACTION_CROUCH)
		command.aim = Input.is_action_pressed(ACTION_AIM)
		command.fire = trigger_held()
		command.jump = _pressed_edge(ACTION_JUMP)
		command.swap_shoulder = _pressed_edge(ACTION_SWAP_SHOULDER)
		command.throw_over = Input.is_action_pressed(ACTION_THROW_GRENADE)
		command.throw_under = Input.is_action_pressed(ACTION_TOSS_GRENADE)
		camera_rig.set_stick(
			(
				Vector2.ZERO
				if look_locked
				else Input.get_vector(
					ACTION_LOOK_LEFT,
					ACTION_LOOK_RIGHT,
					ACTION_LOOK_UP,
					ACTION_LOOK_DOWN,
					tuning.stick_deadzone
				)
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
	camera_rig.side = state.shoulder_side
	camera_rig.sprinting = state.sprinting
	camera_rig.crouching = state.crouching
	camera_rig.downed = _animation != null and _animation.is_downed()
	camera_rig.ground_speed = state.ground_speed()
	camera_rig.grounded = state.on_floor
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


## Whether the controls act. A gamepad needs no mouse: it plays while the mouse waits for its lock.
func controls_enabled() -> bool:
	return _controls_enabled


## Whether the mouse acts: the controls are on and the mouse is not waiting for a lock a click has
## to bring (a browser gives the lock to a click or a key, never to a gamepad button).
func mouse_enabled() -> bool:
	return _controls_enabled and not grip.is_pending()


## Whether the trigger is held. A mouse click that is only asking for the lock is not a shot; a
## gamepad's trigger always is one.
func trigger_held() -> bool:
	if not _controls_enabled:
		return false
	if grip.is_pending() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	return Input.is_action_pressed(ACTION_FIRE)


func is_sprinting() -> bool:
	return state.sprinting


func is_aiming() -> bool:
	return state.aiming


## Horizontal speed in metres per second.
func ground_speed() -> float:
	return state.ground_speed()
