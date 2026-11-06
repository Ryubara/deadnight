# A finger that is on the screen while the touch layer is down (the helicopter drop, a pause) is
# the player's again when the layer is back up (#1329). On a phone a thumb resting on the screen
# through the drop is ordinary play: it looks or walks from its first move, with no lift first.
extends GdUnitTestSuite

const LOOK_AT := Vector2(1638.0, 324.0)
const STICK_AT := Vector2(300.0, 800.0)
const STEP := Vector2(-20.0, 0.0)

var _fixture: TouchFixture
var _looks := Vector2.ZERO


func before_test() -> void:
	_fixture = TouchFixture.make(self)
	_looks = Vector2.ZERO
	_fixture.controls.looked.connect(func(look: Vector2) -> void: _looks += look)


func after_test() -> void:
	_fixture.free_all()


func _move() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## What `units` of finger travel turn the view in mouse pixels at a still finger's gain.
func _look_for(units: Vector2) -> Vector2:
	return units * TouchLook.tuning.radians_per_height / 1080.0 / TouchLook.mouse_radians_per_pixel


## Drags a finger `steps` steps of `STEP` from `from`, one canvas unit sample each.
func _drag_steps(index: int, from: Vector2, steps: int) -> void:
	for i in steps:
		await _fixture.drag(index, from + STEP * (i + 1), STEP)


func test_a_look_finger_held_through_the_drop_turns_the_view_from_its_first_move() -> void:
	_fixture.controls.live = false
	await _fixture.touch(0, LOOK_AT)
	_fixture.controls.live = true
	await _drag_steps(0, LOOK_AT, 1)
	assert_float(_looks.x).is_equal_approx(_look_for(STEP).x, 0.001)
	await _drag_steps(0, LOOK_AT, 10)
	assert_float(_looks.x).is_less(_look_for(STEP * 10.0).x * 0.95)


func test_a_finger_that_moved_during_the_drop_looks_from_where_it_is_now() -> void:
	_fixture.controls.live = false
	await _fixture.touch(0, LOOK_AT)
	var moved := LOOK_AT + Vector2(-400.0, 100.0)
	await _fixture.drag(0, moved, moved - LOOK_AT)
	_fixture.controls.live = true
	await _fixture.drag(0, moved + STEP, STEP)
	# The move the finger made under the drop is not turned late: only the one after it.
	assert_float(_looks.x).is_equal_approx(_look_for(STEP).x, 0.001)
	assert_float(_looks.y).is_equal_approx(0.0, 0.001)


func test_the_look_finger_held_through_the_drop_is_no_tap_when_it_lifts() -> void:
	var swaps := [0]
	_fixture.controls.shoulder_swapped.connect(func() -> void: swaps[0] += 1)
	_fixture.controls.live = false
	await _fixture.touch(0, LOOK_AT)
	_fixture.controls.live = true
	await _fixture.lift(0)
	await _fixture.touch(0, LOOK_AT)
	await _fixture.lift(0)
	# The held finger's lift does not count as the first tap of a double: the second tap alone is
	# a tap, not a swap.
	assert_int(swaps[0]).is_equal(0)


func test_a_stick_finger_held_through_the_drop_walks_from_where_it_rests() -> void:
	_fixture.controls.live = false
	await _fixture.touch(0, STICK_AT)
	_fixture.controls.live = true
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	assert_float(_move().length()).is_equal(0.0)
	await _fixture.drag(0, STICK_AT + Vector2(90.0, 0.0), Vector2(90.0, 0.0))
	assert_float(_move().x).is_greater(0.6)
	await _fixture.lift(0)
	assert_bool(_fixture.controls.is_stick_down()).is_false()
	assert_float(_move().length()).is_equal(0.0)


func test_both_thumbs_held_through_the_drop_walk_and_look() -> void:
	_fixture.controls.live = false
	await _fixture.touch(0, STICK_AT)
	await _fixture.touch(1, LOOK_AT)
	_fixture.controls.live = true
	await _fixture.drag(0, STICK_AT + Vector2(0.0, -80.0), Vector2(0.0, -80.0))
	await _fixture.drag(1, LOOK_AT + STEP, STEP)
	assert_float(_move().y).is_less(-0.6)
	assert_float(_looks.x).is_equal_approx(_look_for(STEP).x, 0.001)


func test_a_finger_that_lifted_during_the_drop_is_not_there_when_it_ends() -> void:
	_fixture.controls.live = false
	await _fixture.touch(0, STICK_AT)
	await _fixture.touch(1, LOOK_AT)
	await _fixture.lift(0)
	await _fixture.lift(1)
	_fixture.controls.live = true
	assert_bool(_fixture.controls.is_stick_down()).is_false()
	# A finger that lands now is a fresh one: the stick floats under it, and its drag looks.
	await _fixture.touch(0, STICK_AT)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	await _fixture.touch(1, LOOK_AT)
	await _drag_steps(1, LOOK_AT, 3)
	await _fixture.lift(0)
	await _fixture.lift(1)
	assert_float(_looks.x).is_less(0.0)


func test_a_finger_resting_on_a_button_through_the_drop_presses_nothing_and_looks() -> void:
	var fire := _fixture.at(&"fire")
	_fixture.controls.live = false
	await _fixture.touch(0, fire)
	_fixture.controls.live = true
	assert_bool(Input.is_action_pressed(&"fire")).is_false()
	await _fixture.drag(0, fire + STEP, STEP)
	assert_bool(Input.is_action_pressed(&"fire")).is_false()
	assert_float(_looks.x).is_equal_approx(_look_for(STEP).x, 0.001)
	await _fixture.lift(0)
	assert_bool(Input.is_action_pressed(&"fire")).is_false()


func test_a_fresh_tap_after_the_drop_is_still_a_tap() -> void:
	_fixture.controls.live = false
	await _fixture.touch(0, LOOK_AT)
	_fixture.controls.live = true
	await _fixture.lift(0)
	var swaps := [0]
	_fixture.controls.shoulder_swapped.connect(func() -> void: swaps[0] += 1)
	# Two taps on free ground inside the double tap's window swap the shoulder, as before.
	await _fixture.touch(0, LOOK_AT)
	await _fixture.lift(0)
	_fixture.pass_time(0.1)
	await _fixture.touch(0, LOOK_AT)
	await _fixture.lift(0)
	assert_int(swaps[0]).is_equal(1)


func test_a_fresh_finger_on_a_button_after_the_drop_presses_it() -> void:
	_fixture.controls.live = false
	await _fixture.touch(1, LOOK_AT)
	_fixture.controls.live = true
	await _fixture.touch(0, _fixture.at(&"jump"))
	assert_bool(Input.is_action_pressed(&"jump")).is_true()
	await _fixture.lift(0)
	# Let go after the least a press is held, so a physics tick sees it.
	await await_millis(300)
	assert_bool(Input.is_action_pressed(&"jump")).is_false()


func test_a_finger_down_under_a_pause_is_still_there_when_it_closes() -> void:
	await _fixture.touch(0, STICK_AT)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	_fixture.controls.live = false
	assert_bool(_fixture.controls.is_stick_down()).is_false()
	assert_float(_move().length()).is_equal(0.0)
	_fixture.controls.live = true
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	await _fixture.drag(0, STICK_AT + Vector2(90.0, 0.0), Vector2(90.0, 0.0))
	assert_float(_move().x).is_greater(0.6)


func test_a_finger_lifted_under_a_pause_is_gone_when_it_closes() -> void:
	await _fixture.touch(0, STICK_AT)
	_fixture.controls.live = false
	await _fixture.lift(0)
	_fixture.controls.live = true
	assert_bool(_fixture.controls.is_stick_down()).is_false()
