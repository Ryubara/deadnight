# The move stick's walk and its sprint latch (#1276): a ring only under a finger, full walking speed
# at its edge, a sprint past the edge that stays on until that finger lifts.
extends GdUnitTestSuite

const START := Vector2(300.0, 800.0)
## Canvas units per CSS pixel of the two phones the edge must be the same on (a 1080 unit canvas
## over 375 and 390 CSS pixels).
const SMALL_PHONE := 375.0 / 1080.0
const BIG_PHONE := 390.0 / 1080.0

var _fixture: TouchFixture
var _starts := 0


func before_test() -> void:
	_fixture = TouchFixture.make(self)
	_starts = 0
	_fixture.controls.sprint_started.connect(func() -> void: _starts += 1)


func after_test() -> void:
	_fixture.free_all()


func _controls() -> TouchControls:
	return _fixture.controls


## The finger goes from `from` to `to` in one drag.
func _move_to(index: int, from: Vector2, to: Vector2) -> void:
	await _fixture.drag(index, to, to - from)


func _up(distance: float) -> Vector2:
	return START + Vector2(0.0, -distance)


func test_nothing_is_on_the_left_until_a_finger_is_down() -> void:
	assert_object(_controls().stick_pad()).is_null()
	await _fixture.touch(0, START)
	assert_object(_controls().stick_pad()).is_not_null()
	assert_vector(_controls().stick_pad().origin).is_equal(START)
	await _fixture.lift(0)
	assert_object(_controls().stick_pad()).is_null()


func test_the_edge_of_the_ring_walks_at_full_speed_and_does_not_sprint() -> void:
	var radius := _controls().stick_radius()
	await _fixture.touch(0, START)
	await _move_to(0, START, _up(radius))
	assert_float(Input.get_action_strength(&"move_forward")).is_equal_approx(1.0, 0.001)
	assert_bool(_controls().is_sprinting()).is_false()
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	# A little past the edge, inside the margin: still walking, still full speed.
	await _move_to(0, _up(radius), _up(radius + _controls().sprint_margin() - 2.0))
	assert_float(Input.get_action_strength(&"move_forward")).is_equal_approx(1.0, 0.001)
	assert_bool(_controls().is_sprinting()).is_false()
	assert_int(_starts).is_equal(0)
	await _fixture.lift(0)


func test_a_drag_past_the_edge_sprints_once_and_it_stays_on_until_the_finger_lifts() -> void:
	var radius := _controls().stick_radius()
	var past := _up(radius + _controls().sprint_margin() + 3.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	assert_bool(_controls().is_sprinting()).is_true()
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_int(_starts).is_equal(1)
	# Back inside the ring, to the middle of it and out again: the latch holds, no second buzz.
	await _move_to(0, past, _up(radius * 0.5))
	assert_bool(_controls().is_sprinting()).is_true()
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	await _move_to(0, _up(radius * 0.5), _controls().stick_pad().origin)
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	await _move_to(0, START, _up(radius + 200.0))
	assert_int(_starts).is_equal(1)
	await _fixture.lift(0)
	assert_bool(_controls().is_sprinting()).is_false()
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()


func test_a_new_press_walks_even_after_a_sprint() -> void:
	var past := _up(_controls().stick_radius() + _controls().sprint_margin() + 20.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	await _fixture.lift(0)
	await _fixture.touch(0, START)
	assert_bool(_controls().is_sprinting()).is_false()
	await _move_to(0, START, _up(_controls().stick_radius()))
	assert_bool(_controls().is_sprinting()).is_false()
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	await _fixture.lift(0)


func test_a_finger_that_reuses_the_index_without_a_lift_starts_walking() -> void:
	var past := _up(_controls().stick_radius() + _controls().sprint_margin() + 20.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	assert_bool(_controls().is_sprinting()).is_true()
	# The browser reports a press on index 0 again with no lift between (a lost touch end).
	await _fixture.touch(0, START + Vector2(40.0, 0.0))
	assert_bool(_controls().is_sprinting()).is_false()
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	assert_vector(_controls().stick_pad().origin).is_equal(START + Vector2(40.0, 0.0))
	await _fixture.lift(0)


func test_losing_the_layer_clears_the_latch_and_the_next_press_walks() -> void:
	var past := _up(_controls().stick_radius() + _controls().sprint_margin() + 20.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	_controls().live = false  # a menu, the result
	assert_bool(_controls().is_sprinting()).is_false()
	assert_bool(Input.is_action_pressed(&"sprint")).is_false()
	_controls().live = true
	assert_bool(_controls().is_stick_down()).is_false()
	await _fixture.touch(0, START)
	assert_bool(_controls().is_sprinting()).is_false()
	await _fixture.lift(0)


func test_the_latch_belongs_to_the_stick_finger_and_other_fingers_leave_it_alone() -> void:
	var past := _up(_controls().stick_radius() + _controls().sprint_margin() + 20.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	# A look finger and a button finger come and go: the sprint holds.
	var look := Vector2(1800.0, 500.0)
	await _fixture.touch(1, look)
	await _fixture.drag(1, look + Vector2(50.0, 0.0), Vector2(50.0, 0.0))
	await _fixture.lift(1)
	await _fixture.touch(2, _fixture.at(TouchLayout.FIRE))
	await _fixture.lift(2, _fixture.at(TouchLayout.FIRE))
	assert_bool(_controls().is_sprinting()).is_true()
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	# A second finger with the lifted stick finger's number does not inherit it.
	await _fixture.lift(0)
	await _fixture.touch(1, START)
	assert_bool(_controls().is_sprinting()).is_false()
	await _fixture.lift(1)


func test_aiming_leaves_the_latch_on_and_the_player_ignores_it_while_the_aim_is_held() -> void:
	var past := _up(_controls().stick_radius() + _controls().sprint_margin() + 20.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	await _fixture.touch(1, _fixture.at(TouchLayout.AIM))
	# The sprint action stays pressed; `PlayerSimulation._sprint_allowed` refuses it while `aim` is.
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_bool(Input.is_action_pressed(&"aim")).is_true()
	await _fixture.lift(1, _fixture.at(TouchLayout.AIM))
	assert_bool(_controls().is_sprinting()).is_true()
	await _fixture.lift(0)


## Crouch is a toggle on a phone (#1277): the tap stands the body down and the latch stays, so the
## sprint is back when a second tap (or a Jump) stands it with the stick finger still down.
func test_a_crouch_tap_leaves_the_latch_on_and_the_sprint_returns_when_the_body_stands() -> void:
	var past := _up(_controls().stick_radius() + _controls().sprint_margin() + 20.0)
	await _fixture.touch(0, START)
	await _move_to(0, START, past)
	var crouch := _fixture.at(TouchLayout.CROUCH)
	await _fixture.touch(1, crouch)
	await _fixture.lift(1, crouch)
	assert_bool(_controls().is_crouch_latched()).is_true()
	# The action stays pressed; `PlayerSimulation._sprint_allowed` refuses it while the body crouches.
	assert_bool(_controls().is_sprinting()).is_true()
	assert_bool(Input.is_action_pressed(&"sprint")).is_true()
	assert_bool(Input.is_action_pressed(&"crouch")).is_true()
	await _fixture.touch(1, crouch)
	await _fixture.lift(1, crouch)
	assert_bool(_controls().is_crouch_latched()).is_false()
	assert_bool(_controls().is_sprinting()).is_true()
	assert_int(_starts).is_equal(1)
	await _fixture.lift(0)


## The edge is a circle: a drag past it sprints on every side, not only at the top.
func test_a_drag_past_the_edge_sprints_in_every_direction() -> void:
	var far := _controls().stick_radius() + _controls().sprint_margin() + 6.0
	for direction: Vector2 in [
		Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(1.0, -1.0).normalized()
	]:
		await _fixture.touch(0, START)
		await _move_to(0, START, START + direction * far)
		assert_bool(_controls().is_sprinting()).override_failure_message(str(direction)).is_true()
		await _fixture.lift(0)
		assert_bool(_controls().is_sprinting()).is_false()


func test_a_sideways_drag_to_the_edge_walks_without_sprinting() -> void:
	var radius := _controls().stick_radius()
	await _fixture.touch(0, START)
	await _move_to(0, START, START + Vector2(radius, 0.0))
	assert_float(Input.get_action_strength(&"move_right")).is_equal_approx(1.0, 0.001)
	assert_bool(_controls().is_sprinting()).is_false()
	await _fixture.lift(0)


## The ring and the margin are CSS pixels of the page, so they are the same movement of the thumb
## on a 667 x 375 phone and an 844 x 390 one, whatever the canvas units are.
func test_the_edge_is_the_same_distance_in_css_pixels_on_both_phones() -> void:
	for per_unit: float in [SMALL_PHONE, BIG_PHONE]:
		_controls().css_per_unit = func() -> float: return per_unit
		var radius := _controls().stick_radius()
		var margin := _controls().sprint_margin()
		assert_float(radius * per_unit).is_equal_approx(_controls().tuning.stick_radius_px, 0.01)
		assert_float(margin * per_unit).is_equal_approx(_controls().tuning.sprint_margin_px, 0.01)
		var edge_px := (radius + margin) * per_unit
		await _fixture.touch(0, START)
		# One CSS pixel short of the edge walks, one CSS pixel past it sprints.
		await _move_to(0, START, _up(edge_px / per_unit - 1.0 / per_unit))
		assert_bool(_controls().is_sprinting()).override_failure_message("short").is_false()
		await _move_to(
			0, _up(edge_px / per_unit - 1.0 / per_unit), _up(edge_px / per_unit + 1.0 / per_unit)
		)
		assert_bool(_controls().is_sprinting()).override_failure_message("past").is_true()
		await _fixture.lift(0)


func test_the_stick_works_the_same_for_a_left_hand() -> void:
	_fixture.left_handed()
	var from := Vector2(2000.0, 800.0)
	var past := (
		from + Vector2(0.0, -(_controls().stick_radius() + _controls().sprint_margin() + 8.0))
	)
	await _fixture.touch(0, from)
	assert_bool(_controls().is_stick_down()).is_true()
	await _move_to(0, from, past)
	assert_bool(_controls().is_sprinting()).is_true()
	await _fixture.lift(0)
	assert_bool(_controls().is_sprinting()).is_false()
