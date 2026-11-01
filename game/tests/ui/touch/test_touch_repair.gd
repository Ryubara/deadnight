# Holding the touch Interact button at a broken breach repairs board after board (#297): the
# finger is a real touch event, the button presses the `interact` action, the human controller
# turns that into the press and the held level, and the night's server puts a board back every
# `repair_interval`. A night run by hand: a tick is 1/60 s and nothing waits on the clock.
extends GdUnitTestSuite

const BREACH := &"nw"
const TICKS_PER_SECOND := 60
const SETTLE := 30
const HELD_SECONDS := 4.5

var _fixture: TouchFixture
var _night: Night
var _controller: HumanController


func before_test() -> void:
	# A fresh one each test: it remembers whether the button was down for the press edge.
	_controller = HumanController.new()
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 60.0
	_night = await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(_night, SETTLE)
	for _i in tuning.barricades.boards:
		_night.server.rules.barricades.tear(BREACH)
	_night.world.barricade(BREACH).set_boards(_boards())
	_night.player().teleport(_night.world.repair_spot(BREACH))
	NightFixture.run(_night, 2)


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
	Input.action_release(&"interact")


func _boards() -> int:
	return _night.server.rules.barricades.boards_of(BREACH)


## `ticks` ticks of the night, each sending what the human controller reads from the input now.
func _play(ticks: int) -> void:
	for _i in ticks:
		var command := _controller.command(_night.player(), 1)
		NightFixture.run(_night, 1, command)


func _with_prompt() -> HudState:
	var state := HudState.new()
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, state)
	state.set_prompt(&"repair", "Broken fence", 0)
	# The button reads the prompt in its own frame: give it two.
	await get_tree().process_frame
	await get_tree().process_frame
	return state


func test_the_button_says_hold_at_a_breach() -> void:
	await _with_prompt()
	assert_str(_fixture.controls.interact_verb()).is_equal("HOLD")


func test_holding_the_touch_button_repairs_board_after_board_until_let_go() -> void:
	await _with_prompt()
	var interval := _night.server.tuning.repair_interval
	assert_int(_boards()).is_equal(0)
	await _fixture.touch(0, _fixture.at(TouchLayout.INTERACT))
	assert_bool(Input.is_action_pressed(&"interact")).is_true()
	_play(1)
	assert_int(_boards()).is_equal(1)
	_play(roundi(interval * TICKS_PER_SECOND) * 2)
	assert_int(_boards()).is_equal(3)
	_play(roundi((HELD_SECONDS - 2.0 * interval) * TICKS_PER_SECOND))
	assert_int(_boards()).is_equal(_night.server.rules.tuning.barricades.boards)
	await _fixture.lift(0)
	await await_millis(200)
	assert_bool(Input.is_action_pressed(&"interact")).is_false()


func test_lifting_the_finger_stops_the_boards() -> void:
	await _with_prompt()
	var interval := _night.server.tuning.repair_interval
	await _fixture.touch(0, _fixture.at(TouchLayout.INTERACT))
	assert_bool(Input.is_action_pressed(&"interact")).is_true()
	_play(1)
	_play(roundi(interval * TICKS_PER_SECOND * 1.5))
	var held := _boards()
	assert_int(held).is_greater(1)
	await _fixture.lift(0)
	await await_millis(200)
	_play(roundi(interval * TICKS_PER_SECOND * 3.0))
	assert_int(_boards()).is_equal(held)
