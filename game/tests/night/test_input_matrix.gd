# gdlint:disable=max-returns
# Every gameplay action, pressed through the real input path on every device, and what the night
# does with it (#351). A grenade key that did nothing went unnoticed because each link of the chain
# had its own test (the action, the command, the grenade code) and nothing pressed a key and looked
# at the night. This does, for the keyboard and mouse, a gamepad that is not device 0 and the touch
# layer: the event goes in as a player's hardware would send it, the human controller reads it into
# the night's command, the server runs the command, and the row says what must then be true.
#
# A new action in the input map fails `test_every_action_has_a_row` until it has a row here, so
# adding a control cannot leave it unproven. A row's second field is the touch control that presses
# it on a phone (`stick` for the move stick, empty when a phone does not offer it).
# A night run by hand: a tick is 1/60 s and nothing waits on the clock.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const MAIN := "res://main.tscn"
## A pad that is not device 0: a reconnect or a virtual pad numbers them so.
const PAD := 3
const HOLD_TICKS := 24
const SETTLE_FRAMES := 6
const INTRO_SECONDS := 1.0
const FAR_OFF := 600.0
## Where a thumb lands in the stick's zone (canvas units) and how far each push goes.
const STICK_START := Vector2(300.0, 800.0)
const STICK_WALK := 70.0
const STICK_RIM := 150.0
## Input actions of the map that belong to menus, not to the night.
const MENU_PREFIX := "ui_"

## Each gameplay action and the touch control that presses it.
const ROWS: Array = [
	[&"move_forward", &"stick"],
	[&"move_back", &"stick"],
	[&"move_left", &"stick"],
	[&"move_right", &"stick"],
	[&"look_left", &""],
	[&"look_right", &""],
	[&"look_up", &""],
	[&"look_down", &""],
	[&"sprint", &"stick"],
	[&"crouch", &""],
	[&"jump", &"jump"],
	[&"aim", &"aim"],
	[&"swap_shoulder", &"swap_shoulder"],
	[&"fire", &"fire"],
	[&"reload", &"reload"],
	[&"interact", &"interact"],
	[&"swap_weapon", &"swap_weapon"],
	[&"throw_grenade", &"throw_grenade"],
	[&"toss_grenade", &""],
	[&"pause", &""],
	[&"scoreboard", &""],
]

var _night: Night
var _controller: HumanController
var _fixture: TouchFixture
var _heard: Array[Dictionary] = []
var _held: Array[InputEvent] = []
var _jumps := 0


func before_test() -> void:
	_heard = []
	_held = []
	_jumps = 0
	_controller = HumanController.new()
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = INTRO_SECONDS
	# A round that is on but whose first zombie is minutes away: nothing hurts the player here.
	tuning.rounds.first_spawn_delay = FAR_OFF
	_night = await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	NightFixture.run(_night, roundi((INTRO_SECONDS + 1.0) * 60.0))
	assert_int(_night.state.phase()).is_equal(GameRules.Phase.ACTIVE)
	_night.player().jumped.connect(func() -> void: _jumps += 1)


func after_test() -> void:
	for event in _held:
		_send(event, false)
	_held = []
	for action in _actions():
		Input.action_release(action)
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	TouchMode.device_is_touch = null
	# A night left standing holds the next night's player up on its own body (no jump from there)
	# and keeps ticking into the next test's events: free it before the next one is built.
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


## What the human controller must have read into the night's command while `action` was held.
func _read(action: StringName, c: NightCommand) -> bool:
	match action:
		&"move_forward":
			return c.motion.move.y < -0.5
		&"move_back":
			return c.motion.move.y > 0.5
		&"move_left":
			return c.motion.move.x < -0.5
		&"move_right":
			return c.motion.move.x > 0.5
		&"sprint":
			return c.motion.sprint
		&"crouch":
			return c.motion.crouch
		&"jump":
			return c.motion.jump
		&"aim":
			return c.motion.aim
		&"swap_shoulder":
			return c.motion.swap_shoulder
		&"fire":
			return c.fire
		&"reload":
			return c.reload
		&"interact":
			return c.use and c.use_held
		&"swap_weapon":
			return c.swap
		&"throw_grenade":
			return c.motion.throw_over
		&"toss_grenade":
			return c.motion.throw_under
	# The look stick turns the camera rig and not the command: `_shown` checks the view turned.
	return true


## What the night must show since `before` (a `_snapshot`) once `action` was held, or true when the
## action has nothing to see in an idle night (the command is all there is to read).
func _shown(action: StringName, before: Dictionary) -> bool:
	var player := _night.player()
	match action:
		&"move_forward", &"move_back", &"move_left", &"move_right":
			# The body ran the command (the lot's fences and cars may stop it from getting far).
			return player.last_command.move.length() > 0.5
		&"look_left", &"look_right":
			return player.camera_rig.yaw != before[&"yaw"]
		&"look_up", &"look_down":
			return player.camera_rig.pitch != before[&"pitch"]
		&"jump":
			return _jumps > before[&"jumps"]
		&"aim":
			return player.state.aiming
		&"swap_shoulder":
			return player.state.shoulder_side != before[&"shoulder"]
		&"fire":
			return _count_since(&"shot_fired", before) > 0
		&"reload":
			return _count_since(&"reload_started", before) > 0
		&"swap_weapon":
			return _count_since(&"weapon_equipped", before) > 0
		&"throw_grenade", &"toss_grenade":
			return _count_since(&"cook_started", before) > 0
	return true


func _snapshot() -> Dictionary:
	var player := _night.player()
	return {
		&"yaw": player.camera_rig.yaw,
		&"pitch": player.camera_rig.pitch,
		&"shoulder": player.state.shoulder_side,
		&"jumps": _jumps,
		&"heard": _heard.size(),
	}


func _count_since(type: StringName, before: Dictionary) -> int:
	var since := _heard.slice(before[&"heard"])
	return since.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


## The gameplay actions of the input map.
func _actions() -> Array[StringName]:
	var found: Array[StringName] = []
	for action in InputMap.get_actions():
		if (
			not String(action).begins_with(MENU_PREFIX)
			and ProjectSettings.has_setting("input/" + action)
		):
			found.append(action)
	return found


func _send(event: InputEvent, pressed: bool) -> void:
	var copy := event.duplicate() as InputEvent
	if copy is InputEventKey:
		(copy as InputEventKey).pressed = pressed
	elif copy is InputEventMouseButton:
		(copy as InputEventMouseButton).pressed = pressed
	elif copy is InputEventJoypadButton:
		(copy as InputEventJoypadButton).pressed = pressed
	elif copy is InputEventJoypadMotion and not pressed:
		(copy as InputEventJoypadMotion).axis_value = 0.0
	if pressed:
		_held.append(event)
	else:
		_held.erase(event)
	Input.parse_input_event(copy)
	Input.flush_buffered_events()


## The events the map binds to `action` that a gamepad sends (`pad`), or a keyboard or a mouse does.
func _bound(action: StringName, pad: bool) -> Array[InputEvent]:
	var found: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_pad == pad and (is_pad or event is InputEventKey or event is InputEventMouseButton):
			var copy := event.duplicate() as InputEvent
			# A keyboard and a mouse keep the device ids the engine gives them (16 and 32).
			if pad:
				copy.device = PAD
			found.append(copy)
	return found


## Holds one input for `HOLD_TICKS` ticks, each sending what the controller reads, then checks what
## reached the command and what the night shows of it.
func _hold(who: String, action: StringName) -> void:
	var before := _snapshot()
	var seen := false
	for _i in HOLD_TICKS:
		var command := _controller.command(_night.player(), 1)
		seen = seen or _read(action, command)
		NightFixture.run(_night, 1, command)
	# The camera rig turns on frames, not ticks.
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	(
		assert_bool(seen)
		. override_failure_message("%s: %s never reached the night's command" % [who, action])
		. is_true()
	)
	(
		assert_bool(_shown(action, before))
		. override_failure_message(
			"%s: %s reached the command, the night did not show it" % [who, action]
		)
		. is_true()
	)


func _let_go() -> void:
	for _i in 4:
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))


# --- The table is complete ---


func test_every_action_has_a_row() -> void:
	var rowed: Array[StringName] = []
	for row in ROWS:
		rowed.append(row[0])
	for action in _actions():
		(
			assert_bool(rowed.has(action))
			. override_failure_message(
				"%s is in the input map but has no row in test_input_matrix.gd" % action
			)
			. is_true()
		)
	for action in rowed:
		assert_bool(InputMap.has_action(action)).is_true()


func test_every_action_but_the_look_stick_has_a_key_or_mouse_binding() -> void:
	for row in ROWS:
		var action: StringName = row[0]
		if String(action).begins_with("look_"):
			continue
		(
			assert_array(_bound(action, false))
			. override_failure_message("%s has no keyboard or mouse binding" % action)
			. is_not_empty()
		)


func test_every_action_has_a_gamepad_binding() -> void:
	for row in ROWS:
		var action: StringName = row[0]
		(
			assert_array(_bound(action, true))
			. override_failure_message("%s has no gamepad binding" % action)
			. is_not_empty()
		)


# --- The devices ---


func test_the_keyboard_and_mouse_do_every_action() -> void:
	for row in ROWS:
		if row[0] == &"pause" or row[0] == &"scoreboard":
			continue
		for event in _bound(row[0], false):
			_send(event, true)
			await _hold("keyboard/mouse", row[0])
			_send(event, false)
			_let_go()


func test_a_gamepad_that_is_not_device_zero_does_every_action() -> void:
	for row in ROWS:
		if row[0] == &"pause" or row[0] == &"scoreboard":
			continue
		for event in _bound(row[0], true):
			_send(event, true)
			await _hold("gamepad %d" % PAD, row[0])
			_send(event, false)
			_let_go()


func test_the_touch_layer_does_every_action_it_offers() -> void:
	var hud_state := HudState.new()
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, hud_state)
	# The interact button shows only where there is something to use.
	hud_state.set_prompt(&"repair", "Broken fence", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	for row in ROWS:
		var how: StringName = row[1]
		if how == &"":
			continue
		if how == &"stick":
			await _push_stick(row[0])
		else:
			await _fixture.touch(0, _fixture.at(how))
			await _hold("touch", row[0])
			await _fixture.lift(0)
			_let_go()


## A thumb in the stick's zone pushed the way the action goes (to the rim for a sprint).
func _push_stick(action: StringName) -> void:
	var push := (
		{
			&"move_forward": Vector2(0.0, -STICK_WALK),
			&"move_back": Vector2(0.0, STICK_WALK),
			&"move_left": Vector2(-STICK_WALK, 0.0),
			&"move_right": Vector2(STICK_WALK, 0.0),
			&"sprint": Vector2(0.0, -STICK_RIM),
		}[action]
		as Vector2
	)
	await _fixture.touch(0, STICK_START)
	await _fixture.drag(0, STICK_START + push, push)
	await _hold("touch", action)
	await _fixture.lift(0)
	_let_go()


# --- Pause and the scoreboard belong to the screen, not the command ---


## The game's own root, loaded as in a real run, with the night on top.
func _enter_night() -> NightScreen:
	var main := (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	auto_free(main)
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	await get_tree().physics_frame
	return screen


func _leave() -> void:
	UIRouter.pop()
	await UIRouter.idle


func test_the_scoreboard_shows_while_held_on_every_device() -> void:
	var screen := await _enter_night()
	var board := screen.night.hud.scoreboard
	for pad in [false, true]:
		for event in _bound(&"scoreboard", pad):
			assert_bool(board.visible).is_false()
			_send(event, true)
			await get_tree().process_frame
			await get_tree().process_frame
			(
				assert_bool(board.visible)
				. override_failure_message("%s did not show the scoreboard" % event.as_text())
				. is_true()
			)
			_send(event, false)
			await get_tree().process_frame
			await get_tree().process_frame
			assert_bool(board.visible).is_false()
	await _leave()


## Each pause event, as the first press on a live night and again on the paused one. A gamepad's
## Start is also `ui_accept`: the router once spent it on a menu's focus, so a Start pressed after
## the keyboard's Esc (which had put a button in focus) looked fine here and did nothing on its
## own (#494).
func test_pause_on_every_device() -> void:
	var screen := await _enter_night()
	for pad in [true, false]:
		for event in _bound(&"pause", pad):
			for expected_paused in [true, false]:
				_send(event, true)
				await get_tree().process_frame
				await get_tree().process_frame
				(
					assert_bool(screen.night.is_paused())
					. override_failure_message(
						(
							"pause by %s left the night %s"
							% [event.as_text(), "running" if expected_paused else "paused"]
						)
					)
					. is_equal(expected_paused)
				)
				_send(event, false)
				await get_tree().process_frame
	await _leave()


func test_pause_by_touch() -> void:
	TouchMode.device_is_touch = true
	var screen := await _enter_night()
	var controls := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	_fixture = TouchFixture.attach(self, controls)
	controls.refresh()
	await get_tree().process_frame
	assert_bool(screen.night.is_paused()).is_false()
	await _fixture.touch(0, _fixture.at(TouchLayout.PAUSE))
	await _fixture.lift(0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(screen.night.is_paused()).is_true()
	await _leave()
