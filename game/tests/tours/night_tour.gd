extends Control
## An unattended tour of the first round for captures, at the shipped tuning: from the main menu,
## Play starts the night; the player turns to face the field, waits for the first dead, aims and
## shoots them with the real input actions (a hit with its damage number and tracer, a kill and
## the points), walks to the concession door when the round is over, and buys it at the prompt;
## then Esc pauses, Resume goes on, and Back to the menu leaves. Not part of the game.
##
## The player is a person's stand-in: it reads only what a screen shows (the dead's places from the
## client's state, the prompt) and answers with key and button presses and mouse look, which turns
## at a limited speed like a hand. Record it at 60 frames a second, one frame a physics tick:
##
##     godot --path game res://tests/tours/night_tour.tscn --no-window \
##         --write-movie <abs>/fight.avi --fixed-fps 60 --quit-after 9000
##
## Prints `TOUR <what> <seconds>` as each stage starts, and `TOUR end`.

const MENU := "res://ui/screens/main_menu.tscn"
const TICKS_PER_SECOND := 60.0
const SETTLE := 2.4
const LOOK := 1.5
const STEP_KEYS := 0.4
## Seconds the audio mixer gets to drop stopped voices before the program quits.
const QUIT_SETTLE := 0.3
## Radians a second the mouse can turn the view, a quick flick.
const LOOK_RATE := 6.0
## The view is on a dead when the aim ray is within this many degrees of its chest.
const ON_TARGET_DEGREES := 3.0
## Metres above the ground of the point the player aims at on a dead.
const AIM_HEIGHT := 1.35
## The dead are shot from this far, and no further: close enough that a number over one reads.
const SHOOT_RANGE := 15.0
## The tour gives up on the round after this long, whatever has happened.
const ROUND_LIMIT_SECONDS := 240.0
## The player stands in the field, looking at the lot: south, along +z.
const FIELD_YAW := PI
## The door the tour buys, and the spot north of it the player stands on to read its prompt.
const DOOR := &"door_concession"
const DOOR_SPOT := Vector3(0.0, 0.0, -6.0)
const ARRIVED_WITHIN := 1.2
const WAYPOINT_REACHED := 1.4
const DOOR_LIMIT_SECONDS := 60.0

var _night: Night
var _player: Player
var _clock := 0.0


func _ready() -> void:
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(SETTLE)
	await _tap(KEY_ENTER)
	await UIRouter.idle
	_night = (UIRouter.top() as NightScreen).night
	await _night.ready_to_play
	_player = _night.player()
	# The mouse of whoever uses this machine must not turn the view: the look below is the tour's.
	_player.local_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(LOOK)
	_stage("face the field")
	await _turn_to(FIELD_YAW)
	_stage("wait for the first dead")
	while _nearest_dead(INF).is_empty() and not _night.state.over:
		await _tick()
	_stage("fight")
	await _fight_the_round()
	_stage("walk to the door")
	await _walk_to(DOOR_SPOT)
	await _buy_the_door()
	await _wait(LOOK)
	_stage("pause menu")
	await _tap(KEY_ESCAPE)
	await _wait(LOOK)
	await _tap(KEY_ENTER)
	await _wait(LOOK)
	await _tap(KEY_ESCAPE)
	await _wait(STEP_KEYS)
	await _tap(KEY_DOWN)
	await _wait(STEP_KEYS)
	await _tap(KEY_ENTER)
	await UIRouter.idle
	await _wait(LOOK)
	print("TOUR end %.1f" % _clock)
	# A voice stopped in the moment the engine quits is reported as a leak: let the mixer drop them.
	Audio.stop_all()
	await _wait(QUIT_SETTLE)
	get_tree().quit()


# --- Stages ---


## Shoots the nearest dead in range until the round is over (the break begins) or the night is.
func _fight_the_round() -> void:
	var began := _clock
	while not _night.state.over and _clock - began < ROUND_LIMIT_SECONDS:
		if _night.state.rounds_started >= 1 and _night.state.phase() == GameRules.Phase.BREAK:
			break
		var target := _nearest_dead(SHOOT_RANGE)
		if target.is_empty():
			_release([&"aim", &"fire"])
			target = _nearest_dead(INF)
			if not target.is_empty():
				_look_at(_aim_point(target))
		else:
			Input.action_press(&"aim")
			var off := _look_at(_aim_point(target))
			_hold(&"fire", off <= ON_TARGET_DEGREES)
		if int(_night.state.me().get("ammo", 1)) == 0 and not _is_reloading():
			_tap_action(&"reload")
		await _tick()
	_release([&"aim", &"fire"])
	await _wait(LOOK)


## Walks to `spot` by the navigation path, the view turned to each next point, sprinting.
func _walk_to(spot: Vector3) -> void:
	var began := _clock
	while not _night.state.over and _clock - began < DOOR_LIMIT_SECONDS:
		var here := _night.state.position()
		if _flat(here, spot) <= ARRIVED_WITHIN:
			break
		var path := NavigationServer3D.map_get_path(_night.world.map(), here, spot, true)
		var next := spot
		for point in path:
			if _flat(here, point) > WAYPOINT_REACHED:
				next = point
				break
		_look_at(next + Vector3(0.0, _eye_height(), 0.0), true)
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		await _tick()
	_release([&"move_forward", &"sprint"])


## Faces the door, shows its prompt for a moment and presses `interact`.
func _buy_the_door() -> void:
	var door_at: Vector3 = _night.world.door_points(DOOR)[0]
	for _i in roundi(LOOK * TICKS_PER_SECOND):
		_look_at(door_at)
		await _tick()
	_stage("buy the door")
	_tap_action(&"interact")
	await _wait(LOOK * 2.0)


# --- What a person does ---


## Turns the view toward `yaw` (radians) at the mouse's speed and waits for it to arrive.
func _turn_to(yaw: float) -> void:
	while absf(angle_difference(_player.camera_rig.yaw, yaw)) > deg_to_rad(1.0):
		var step := clampf(
			angle_difference(_player.camera_rig.yaw, yaw),
			-LOOK_RATE / TICKS_PER_SECOND,
			LOOK_RATE / TICKS_PER_SECOND
		)
		_player.camera_rig.apply_look(-step, 0.0)
		await _tick()


## One tick of mouse look toward a point in the world, at most `LOOK_RATE`. With `level` the
## pitch is left alone. Returns how far off the aim ray still is, in degrees.
func _look_at(point: Vector3, level := false) -> float:
	var rig := _player.camera_rig
	var from := rig.camera().global_position
	var wanted := (point - from).normalized()
	var want_yaw := atan2(-wanted.x, -wanted.z)
	var want_pitch := 0.0 if level else asin(clampf(wanted.y, -1.0, 1.0))
	var yaw_error := angle_difference(rig.yaw, want_yaw)
	var pitch_error := want_pitch - rig.pitch if not level else -rig.pitch * 0.2
	var limit := LOOK_RATE / TICKS_PER_SECOND
	rig.apply_look(-clampf(yaw_error, -limit, limit), -clampf(pitch_error, -limit, limit))
	return rad_to_deg((-rig.camera().global_transform.basis.z).angle_to(wanted))


## The nearest dead that is up (not falling) within `reach` metres of the player, as the client
## has heard it; `{}` when there is none.
func _nearest_dead(reach: float) -> Dictionary:
	if not _night.state.has_frame():
		return {}
	var here := _night.state.position()
	var best := {}
	var best_apart := reach
	for entry: Dictionary in _night.state.zombies:
		if entry["mode"] == ZombieBody.Mode.DYING:
			continue
		var apart := _flat(here, entry["position"])
		if apart <= best_apart:
			best = entry
			best_apart = apart
	return best


func _aim_point(entry: Dictionary) -> Vector3:
	return (entry["position"] as Vector3) + Vector3(0.0, AIM_HEIGHT, 0.0)


func _eye_height() -> float:
	return _night.server.tuning.eye_height


func _is_reloading() -> bool:
	return bool(_night.state.me().get("reloading", false))


## Holds or lets go of an action.
func _hold(action: StringName, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release(actions: Array[StringName]) -> void:
	for action in actions:
		Input.action_release(action)


## Presses an action for a physics tick or two: a tap of the key.
func _tap_action(action: StringName) -> void:
	Input.action_press(action)
	get_tree().create_timer(2.0 / TICKS_PER_SECOND, true, true).timeout.connect(
		func() -> void: Input.action_release(action)
	)


# --- Time ---


func _stage(what: String) -> void:
	print("TOUR %s %.1f" % [what, _clock])


## One physics tick of the tour's clock (the night's own step).
func _tick() -> void:
	await get_tree().physics_frame
	_clock += 1.0 / TICKS_PER_SECOND


func _wait(seconds: float) -> void:
	for _i in roundi(seconds * TICKS_PER_SECOND):
		await _tick()


func _tap(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
