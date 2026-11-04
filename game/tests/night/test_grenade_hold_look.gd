# The camera while a grenade is held (#599). The hold from #285 keeps the pin out for as long as the
# button is down, and the player aims the throw by turning the view meanwhile. On a phone the finger
# on the Grenade button is the right thumb, the stick has the left, and nothing was left to turn
# with: a drag that began on Grenade looked at nothing. Every device is held on the grenade and then
# turns the view; the grenade must still be in the hand after, and leave when the button comes up.
# A night run by hand: a tick is 1/60 s, a frame each, and nothing waits on the clock.
extends GdUnitTestSuite

const PAD := 3
const INTRO_SECONDS := 1.0
const FAR_OFF := 600.0
const PLAYER_ID := 1
const COOK_TICKS := 12
## The arm swings before the grenade leaves (the throw clip's release frame).
const THROW_TICKS := 60
const LOOK_STEPS := 8
## How far the view must have turned (radians) for the hold to count as looked with.
const TURNED := 0.05

var _night: Night
var _fixture: TouchFixture
var _held: Array[InputEvent] = []


func before_test() -> void:
	_held = []
	var tuning := RulesFixture.full_hands()
	tuning.rounds.intro_seconds = INTRO_SECONDS
	tuning.rounds.first_spawn_delay = FAR_OFF
	_night = await NightFixture.start(self, Night.Mode.HUMAN, tuning)
	_night.ticks_per_frame = 0
	for _i in roundi((INTRO_SECONDS + 1.0) * 60.0):
		_night.tick()
	assert_int(_night.state.phase()).is_equal(GameRules.Phase.ACTIVE)
	_night.player().capture_mouse = false


func after_test() -> void:
	for event in _held:
		_send(event, false)
	_held = []
	for action in [&"throw_grenade", &"look_right", &"look_left", &"look_up", &"look_down"]:
		Input.action_release(action)
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	TouchMode.device_is_touch = null
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _send(event: InputEvent, pressed: bool) -> void:
	var copy := event.duplicate() as InputEvent
	if copy is InputEventKey:
		(copy as InputEventKey).pressed = pressed
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


## The first event of one device that the map binds to `action`.
func _bound(action: StringName, pad: bool) -> InputEvent:
	for event in InputMap.action_get_events(action):
		var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_pad == pad and (is_pad or event is InputEventKey):
			var copy := event.duplicate() as InputEvent
			if pad:
				copy.device = PAD
			return copy
	return null


## Frames of the night: a tick each, with what the human controller reads of the devices.
func _play(ticks: int) -> void:
	for _i in ticks:
		_night.tick()
		await get_tree().process_frame


## The touch layer lets the look out a share each frame (#598): what is waiting turns the view now.
## A layer without the smoother (before #598) has nothing waiting.
func _settle_look() -> void:
	if _fixture.controls.has_method(&"flush_look"):
		_fixture.controls.call(&"flush_look")
	await _play(4)


func _cooking() -> bool:
	return _night.server.grenades.is_cooking(PLAYER_ID)


## The grenade button is down: plays until the pin is out.
func _pull_pin() -> void:
	await _play(COOK_TICKS)
	assert_bool(_cooking()).is_true()


func _assert_turned_and_still_held(yaw_before: float) -> void:
	var turned := absf(angle_difference(yaw_before, _night.player().camera_rig.yaw))
	assert_float(turned).is_greater(TURNED)
	assert_bool(_cooking()).is_true()


func _assert_thrown_on_release() -> void:
	await _play(THROW_TICKS)
	assert_bool(_cooking()).is_false()


func test_the_mouse_turns_the_view_while_a_grenade_is_held() -> void:
	var key := _bound(&"throw_grenade", false)
	_send(key, true)
	await _pull_pin()
	var yaw := _night.player().camera_rig.yaw
	for _i in LOOK_STEPS:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(20.0, 0.0)
		motion.screen_relative = motion.relative
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await _play(1)
	_assert_turned_and_still_held(yaw)
	_send(key, false)
	await _assert_thrown_on_release()


func test_the_gamepad_stick_turns_the_view_while_a_grenade_is_held() -> void:
	var button := _bound(&"throw_grenade", true)
	_send(button, true)
	await _pull_pin()
	var yaw := _night.player().camera_rig.yaw
	var stick := _bound(&"look_right", true)
	_send(stick, true)
	await _play(LOOK_STEPS * 4)
	_assert_turned_and_still_held(yaw)
	_send(stick, false)
	_send(button, false)
	await _assert_thrown_on_release()


func test_a_thumb_that_holds_the_grenade_button_turns_the_view_by_dragging() -> void:
	_fixture = TouchFixture.make(self)
	var grenade := _fixture.at(TouchLayout.GRENADE)
	await _fixture.touch(0, grenade)
	await _pull_pin()
	var yaw := _night.player().camera_rig.yaw
	var at := grenade
	for _i in LOOK_STEPS:
		at += Vector2(20.0, 0.0)
		await _fixture.drag(0, at, Vector2(20.0, 0.0))
		await _play(1)
	await _settle_look()
	_assert_turned_and_still_held(yaw)
	await _fixture.lift(0)
	await _assert_thrown_on_release()


func test_another_finger_on_the_look_area_turns_the_view_while_the_grenade_is_held() -> void:
	_fixture = TouchFixture.make(self)
	var grenade := _fixture.at(TouchLayout.GRENADE)
	await _fixture.touch(0, grenade)
	await _pull_pin()
	var yaw := _night.player().camera_rig.yaw
	var at := Vector2(1500.0, 300.0)
	await _fixture.touch(1, at)
	for _i in LOOK_STEPS:
		at += Vector2(20.0, 0.0)
		await _fixture.drag(1, at, Vector2(20.0, 0.0))
		await _play(1)
	await _settle_look()
	_assert_turned_and_still_held(yaw)
	await _fixture.lift(1)
	await _fixture.lift(0)
	await _assert_thrown_on_release()
