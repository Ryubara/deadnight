# The quick melee on a phone (#588): real touches on the real layer press the button, the human
# controller turns that into the night's command, the server strikes a zombie in reach, and the
# cooldown holds against a thumb that taps again at once. Nothing here sends the action itself.
extends GdUnitTestSuite

const SETTLE := 30
const REACH_AHEAD := 1.1
## The quick melee's cooldown (0.6 s), in ticks, and a little over it.
const COOLDOWN_TICKS := 40
## Ticks a finger rests on the button: shorter than the cooldown, longer than a press needs.
const HOLD_TICKS := 6

var _night: Night
var _controller: HumanController
var _fixture: TouchFixture
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	_controller = HumanController.new()
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	NightFixture.run(_night, SETTLE)
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, HudState.new())
	await get_tree().process_frame
	await get_tree().process_frame


func after_test() -> void:
	_fixture.free_all()
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _count(type: StringName) -> int:
	return _heard.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _zombie_in_reach() -> ZombieBody:
	var id := NightFixture.first_zombie(_night)
	assert_int(id).is_greater(0)
	var body: ZombieBody = _night.server.sim.zombies[id]
	_place(body)
	return body


## Not through the controller: reading it consumes a press.
func _place(body: ZombieBody) -> void:
	var dir := -_night.player().camera_rig.aim_transform().basis.z
	body.position = _night.state.position() + Vector3(dir.x, 0.0, dir.z).normalized() * REACH_AHEAD
	body.velocity = Vector3.ZERO


## Ticks the night, `ticks` of them, with the zombie held in reach and the controller read
## once each.
func _run(body: ZombieBody, ticks: int) -> void:
	for _i in ticks:
		_place(body)
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))


## A real tap on the button: the finger goes down, rests, lifts.
func _tap(body: ZombieBody) -> void:
	await _fixture.touch(0, _fixture.at(TouchLayout.MELEE))
	_run(body, HOLD_TICKS)
	await _fixture.lift(0)
	_run(body, 2)
	# A short tap is held on for the layer's minimum press (it runs on frames): wait it out, as the
	# frames of a real night do, or the next press is no new edge.
	for _i in 120:
		if not Input.is_action_pressed(TouchLayout.MELEE):
			break
		await get_tree().process_frame


func test_a_tap_on_the_button_strikes_the_zombie_in_reach() -> void:
	var zombie := _zombie_in_reach()
	await _tap(zombie)
	assert_int(_count(&"quick_melee")).is_equal(1)
	assert_int(_count(&"damage_dealt")).is_equal(1)
	assert_int(_count(&"shot_fired")).is_equal(0)


func test_a_thumb_that_taps_again_at_once_is_held_by_the_cooldown() -> void:
	var zombie := _zombie_in_reach()
	await _tap(zombie)
	await _tap(zombie)
	await _tap(zombie)
	# Three taps inside 0.6 s: one blow.
	assert_int(_count(&"quick_melee")).is_equal(1)
	_run(zombie, COOLDOWN_TICKS)
	await _tap(zombie)
	assert_int(_count(&"quick_melee")).is_equal(2)


func test_holding_the_button_is_one_blow_and_not_a_stream() -> void:
	var zombie := _zombie_in_reach()
	await _fixture.touch(0, _fixture.at(TouchLayout.MELEE))
	_run(zombie, COOLDOWN_TICKS * 2)
	await _fixture.lift(0)
	assert_int(_count(&"quick_melee")).is_equal(1)


func test_a_left_hand_has_the_button_too() -> void:
	_fixture.left_handed(true)
	await get_tree().process_frame
	_fixture.controls.refresh()
	var zombie := _zombie_in_reach()
	await _tap(zombie)
	assert_int(_count(&"quick_melee")).is_equal(1)
