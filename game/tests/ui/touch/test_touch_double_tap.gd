# gdlint:disable=max-public-methods
# The double tap that changes shoulder (#1288), in the touch layer with a clock the test keeps: two
# taps on free ground press `swap_shoulder`, and nothing else does; no look is lost to it.
extends GdUnitTestSuite

const FREE := Vector2(1700.0, 300.0)
## A tap's lift and the next landing, inside the 350 ms between a tap and its second.
const QUICK := 0.1
const HELD := 0.08

var _fixture: TouchFixture
var _swaps := 0
var _looks := Vector2.ZERO


func before_test() -> void:
	_fixture = TouchFixture.make(self)
	# Only this test's own seconds, to the millisecond: the boundaries are the subject here.
	_fixture.controls.clock = func() -> float: return _fixture.now
	_swaps = 0
	_looks = Vector2.ZERO
	_fixture.controls.shoulder_swapped.connect(func() -> void: _swaps += 1)
	_fixture.controls.looked.connect(func(look: Vector2) -> void: _looks += look)


func after_test() -> void:
	_fixture.free_all()


## A tap that lasts `held` seconds, then `after` seconds of quiet.
func _tap(at := FREE, held := HELD, after := QUICK, index := 0) -> void:
	await _fixture.touch(index, at)
	_fixture.pass_time(held)
	await _fixture.lift(index, at)
	_fixture.pass_time(after)


## What `units` of finger travel turn the view in mouse pixels at a still finger's gain.
func _look_for(units: float) -> float:
	return units * TouchLook.tuning.radians_per_height / 1080.0 / TouchLook.mouse_radians_per_pixel


# --- The gesture ---


func test_the_numbers_are_the_ones_the_issue_names() -> void:
	# Written out, so a changed constant fails here and not silently in every boundary test below.
	assert_float(TouchDoubleTap.TAP_SECONDS).is_equal(0.25)
	assert_float(TouchDoubleTap.GAP_SECONDS).is_equal(0.35)
	assert_float(TouchSlop.CSS_PIXELS).is_equal(10.0)
	assert_str(String(TouchDoubleTap.ACTION)).is_equal("swap_shoulder")
	assert_float(_fixture.controls.tuning.min_hold).is_greater_equal(0.09)


func test_two_quick_taps_press_swap_shoulder_for_at_least_a_press() -> void:
	await _tap()
	assert_int(_swaps).is_equal(0)
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_false()
	await _fixture.touch(0, FREE)
	_fixture.pass_time(HELD)
	await _fixture.lift(0, FREE)
	assert_int(_swaps).is_equal(1)
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_true()
	await await_millis(40)
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_true()
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_false()


func test_two_taps_in_two_places_still_swap_and_the_hand_does_not_matter() -> void:
	await _tap(Vector2(1500.0, 250.0))
	await _tap(Vector2(1900.0, 200.0))
	assert_int(_swaps).is_equal(1)
	_fixture.left_handed(true)
	_fixture.controls.refresh()
	# The left hand's free ground is on the left; the stick side is the right.
	await _tap(Vector2(300.0, 300.0))
	await _tap(Vector2(300.0, 300.0))
	assert_int(_swaps).is_equal(2)


func test_a_third_tap_is_the_first_of_a_new_pair() -> void:
	await _tap()
	await _tap()
	assert_int(_swaps).is_equal(1)
	await _tap()
	assert_int(_swaps).is_equal(1)
	await _tap()
	assert_int(_swaps).is_equal(2)


func test_the_second_tap_may_land_up_to_350_ms_after_the_first_lifts_and_no_later() -> void:
	await _tap(FREE, HELD, TouchDoubleTap.GAP_SECONDS)
	await _tap()
	assert_int(_swaps).is_equal(1)
	# 10 ms too late: the second is a first.
	await _tap(FREE, HELD, TouchDoubleTap.GAP_SECONDS + 0.01)
	await _tap()
	assert_int(_swaps).is_equal(1)
	await _tap()
	assert_int(_swaps).is_equal(2)


func test_a_touch_of_250_ms_or_more_is_not_a_tap() -> void:
	await _tap(FREE, TouchDoubleTap.TAP_SECONDS)
	await _tap()
	assert_int(_swaps).is_equal(0)
	await _tap(FREE, TouchDoubleTap.TAP_SECONDS - 0.01)
	await _tap(FREE, TouchDoubleTap.TAP_SECONDS - 0.01)
	assert_int(_swaps).is_equal(1)


func test_a_finger_that_slips_a_slop_is_not_a_tap_and_one_inside_it_is() -> void:
	var slop := _fixture.controls.tap_slop
	await _fixture.touch(0, FREE)
	await _fixture.drag(0, FREE + Vector2(slop + 1.0, 0.0), Vector2(slop + 1.0, 0.0))
	_fixture.pass_time(HELD)
	await _fixture.lift(0)
	_fixture.pass_time(QUICK)
	await _tap()
	assert_int(_swaps).is_equal(0)
	# Inside the slop, and back: a tap with a shaky thumb.
	for tap in 2:
		await _fixture.touch(0, FREE)
		await _fixture.drag(0, FREE + Vector2(slop - 4.0, 0.0), Vector2(slop - 4.0, 0.0))
		await _fixture.drag(0, FREE, Vector2(4.0 - slop, 0.0))
		_fixture.pass_time(HELD)
		await _fixture.lift(0)
		_fixture.pass_time(QUICK)
	assert_int(_swaps).is_equal(1)


# --- What never counts ---


func test_taps_on_a_button_never_count_and_a_button_between_two_taps_ends_the_pair() -> void:
	var reload := _fixture.at(TouchLayout.RELOAD)
	await _tap(reload)
	await _tap(reload)
	assert_int(_swaps).is_equal(0)
	await _tap(_fixture.at(TouchLayout.FIRE))
	await _tap(_fixture.at(TouchLayout.FIRE))
	assert_int(_swaps).is_equal(0)
	await _tap()
	await _tap(reload)
	await _tap()
	assert_int(_swaps).is_equal(0)
	await _tap()
	assert_int(_swaps).is_equal(1)


func test_taps_on_the_stick_side_never_count() -> void:
	var stick_side := Vector2(300.0, 800.0)
	await _tap(stick_side)
	await _tap(stick_side)
	assert_int(_swaps).is_equal(0)
	# A finger on the stick already, a second one tapping its side of the screen: not free ground.
	await _fixture.touch(0, stick_side)
	await _tap(Vector2(500.0, 700.0), HELD, QUICK, 1)
	await _tap(Vector2(500.0, 700.0), HELD, QUICK, 1)
	await _fixture.lift(0)
	assert_int(_swaps).is_equal(0)


func test_ping_is_a_button_so_two_taps_on_it_never_count_and_the_stick_zone_is_the_layers_own(
) -> void:
	var ping := _fixture.at(TouchLayout.PING)
	await _tap(ping)
	await _tap(ping)
	assert_int(_swaps).is_equal(0)
	# The stick zone starts below Ping's hit area (#1289): the layer's own zone decides which side of
	# its top edge is the stick's, and free ground is the strip above it, beside Ping.
	var zone := _fixture.controls._stick_zone()
	var x := zone.position.x + 100.0
	await _tap(Vector2(x, zone.position.y + 20.0))
	await _tap(Vector2(x, zone.position.y + 20.0))
	assert_int(_swaps).is_equal(0)
	var above := Vector2(x, zone.position.y - 20.0)
	assert_bool(zone.has_point(above)).is_false()
	await _tap(above)
	await _tap(above)
	assert_int(_swaps).is_equal(1)


func test_strikes_place_is_free_ground_while_it_is_hidden_and_a_button_while_it_is_up() -> void:
	var strike := _fixture.at(TouchLayout.STRIKE)
	# Hidden (no dead in reach): nothing is there, two taps are a double tap.
	await _tap(strike)
	await _tap(strike)
	assert_int(_swaps).is_equal(1)
	await await_millis(250)
	# Up: the place is Strike's, two taps are two blows and never Side.
	_fixture.controls.strike_ready = func() -> bool: return true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_fixture.controls.strike_up).is_true()
	await _tap(strike)
	assert_bool(Input.is_action_pressed(&"quick_melee")).is_true()
	await _tap(strike)
	assert_int(_swaps).is_equal(1)
	assert_bool(Input.is_action_pressed(&"swap_shoulder")).is_false()
	await await_millis(250)
	_fixture.controls.strike_ready = Callable()


func test_a_tap_on_the_stick_between_two_free_taps_ends_the_pair() -> void:
	await _tap()
	await _tap(Vector2(300.0, 800.0))
	await _tap()
	assert_int(_swaps).is_equal(0)


func test_a_double_tap_works_while_the_other_thumb_walks_or_holds_fire() -> void:
	# The use of it: a corner while walking, or while Fire is held by a second finger.
	await _fixture.touch(0, Vector2(300.0, 800.0))
	await _fixture.drag(0, Vector2(300.0, 740.0), Vector2(0.0, -60.0))
	await _tap(FREE, HELD, QUICK, 1)
	await _tap(FREE, HELD, QUICK, 1)
	assert_int(_swaps).is_equal(1)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	assert_float(Input.get_action_strength(&"move_forward")).is_greater(0.3)
	await _fixture.lift(0)
	await _fixture.touch(0, _fixture.at(TouchLayout.FIRE))
	await _tap(FREE, HELD, QUICK, 1)
	await _tap(FREE, HELD, QUICK, 1)
	assert_int(_swaps).is_equal(2)
	assert_bool(Input.is_action_pressed(&"fire")).is_true()
	await _fixture.lift(0)


# --- No look is lost or late ---


func test_a_tap_turns_nothing_not_even_its_shake() -> void:
	await _fixture.touch(0, FREE)
	await _fixture.drag(0, FREE + Vector2(5.0, 3.0), Vector2(5.0, 3.0))
	_fixture.pass_time(HELD)
	await _fixture.lift(0)
	_fixture.controls.flush_look()
	assert_vector(_looks).is_equal(Vector2.ZERO)


func test_a_drag_turns_all_it_made_even_the_part_before_it_left_the_slop() -> void:
	await _fixture.touch(0, FREE)
	for step in 10:
		var at := FREE + Vector2(10.0 * (step + 1), 0.0)
		await _fixture.drag(0, at, Vector2(10.0, 0.0))
		_fixture.pass_time(0.01)
	_fixture.pass_time(HELD)
	await _fixture.lift(0)
	assert_float(_looks.x).is_equal_approx(_look_for(100.0), 0.001)
	assert_int(_swaps).is_equal(0)


func test_a_fast_flick_turns_all_it_made_and_never_counts_as_a_tap() -> void:
	# One 160 unit move in 30 ms and a lift: shorter than a tap, but it travelled.
	await _fixture.touch(0, FREE)
	_fixture.pass_time(0.03)
	await _fixture.drag(0, FREE + Vector2(160.0, 0.0), Vector2(160.0, 0.0))
	await _fixture.lift(0)
	assert_float(_looks.x).is_equal_approx(_look_for(160.0), 0.001)
	_fixture.pass_time(QUICK)
	await _tap()
	assert_int(_swaps).is_equal(0)


func test_a_look_that_begins_right_after_a_tap_is_whole_and_the_pair_is_over() -> void:
	await _tap()
	await _fixture.touch(0, FREE)
	await _fixture.drag(0, FREE + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	await _fixture.drag(0, FREE + Vector2(120.0, 0.0), Vector2(60.0, 0.0))
	_fixture.pass_time(HELD)
	await _fixture.lift(0)
	assert_float(_looks.x).is_equal_approx(_look_for(120.0), 0.001)
	assert_int(_swaps).is_equal(0)
	# The look ended the pair: a tap right after it is a first tap.
	await _tap()
	assert_int(_swaps).is_equal(0)
	await _tap()
	assert_int(_swaps).is_equal(1)


func test_a_slow_nudge_inside_the_slop_is_let_out_once_it_has_lasted_a_tap() -> void:
	var slop := _fixture.controls.tap_slop
	await _fixture.touch(0, FREE)
	await _fixture.drag(0, FREE + Vector2(slop * 0.5, 0.0), Vector2(slop * 0.5, 0.0))
	assert_vector(_looks).is_equal(Vector2.ZERO)
	_fixture.pass_time(TouchDoubleTap.TAP_SECONDS + 0.05)
	await _fixture.drag(0, FREE + Vector2(slop * 0.6, 0.0), Vector2(slop * 0.1, 0.0))
	assert_float(_looks.x).is_equal_approx(_look_for(slop * 0.6), 0.001)
	await _fixture.lift(0)


func test_a_nudge_that_lifts_after_a_tap_long_is_not_lost() -> void:
	var slop := _fixture.controls.tap_slop
	await _fixture.touch(0, FREE)
	await _fixture.drag(0, FREE + Vector2(slop * 0.5, 0.0), Vector2(slop * 0.5, 0.0))
	_fixture.pass_time(TouchDoubleTap.TAP_SECONDS + 0.05)
	await _fixture.lift(0)
	assert_float(_looks.x).is_equal_approx(_look_for(slop * 0.5), 0.001)
	assert_int(_swaps).is_equal(0)


func test_a_finger_down_on_fire_or_the_stick_still_looks_and_a_second_look_is_whole() -> void:
	# Fire's finger looks as it always did, with no hold-back at all.
	await _fixture.touch(0, _fixture.at(TouchLayout.FIRE))
	await _fixture.drag(0, _fixture.at(TouchLayout.FIRE) + Vector2(5.0, 0.0), Vector2(5.0, 0.0))
	assert_float(_looks.x).is_equal_approx(_look_for(5.0), 0.001)
	await _fixture.lift(0)
	_looks = Vector2.ZERO
	# With the stick held, a look finger on free ground is whole when it leaves the slop.
	await _fixture.touch(0, Vector2(300.0, 800.0))
	await _fixture.touch(1, FREE)
	for step in 6:
		var at := FREE + Vector2(12.0 * (step + 1), 0.0)
		await _fixture.drag(1, at, Vector2(12.0, 0.0))
	await _fixture.lift(1)
	await _fixture.lift(0)
	assert_float(_looks.x).is_equal_approx(_look_for(72.0), 0.001)
	assert_int(_swaps).is_equal(0)


func test_the_layer_going_down_forgets_a_tap_that_waits() -> void:
	await _tap()
	_fixture.controls.live = false
	_fixture.controls.live = true
	await _tap()
	assert_int(_swaps).is_equal(0)


# --- The rule on its own ---


func test_the_rule_counts_press_to_lift_and_lift_to_press_not_press_to_press() -> void:
	var rule := TouchDoubleTap.new()
	rule.press(0, Vector2.ZERO, 0.0)
	assert_bool(rule.release(0, 0.2)).is_false()
	# 0.4 s after the first LANDED but 0.2 after it lifted: a double tap.
	rule.press(0, Vector2.ZERO, 0.4)
	assert_bool(rule.release(0, 0.45)).is_true()
	assert_bool(rule.is_waiting()).is_false()


func test_a_touch_the_rule_dropped_is_no_tap() -> void:
	var rule := TouchDoubleTap.new()
	rule.press(0, Vector2.ZERO, 0.0)
	assert_bool(rule.is_tap(0, Vector2(5.0, 0.0), 0.1, 10.0)).is_true()
	assert_bool(rule.is_tap(0, Vector2(10.0, 0.0), 0.1, 10.0)).is_false()
	assert_bool(rule.is_tap(0, Vector2.ZERO, 0.25, 10.0)).is_false()
	rule.drop(0)
	assert_bool(rule.release(0, 0.3)).is_false()
	assert_bool(rule.is_tap(0, Vector2.ZERO, 0.1, 10.0)).is_false()


func test_the_slop_is_in_css_pixels_so_each_phone_moves_the_same_finger() -> void:
	# 10 CSS pixels (`TouchSlop`), asked at each press in the units of the window it is in.
	for phone in [Vector2i(1688, 780), Vector2i(1334, 750)]:
		var units := TouchSlop.units_for(phone, 1.0)
		var css := units * MenuScale.css_per_unit(phone, 1.0)
		assert_float(css).is_equal_approx(TouchSlop.CSS_PIXELS, 0.01)


# --- The players' column (#1287) ---


func test_the_players_column_is_never_free_ground_for_a_hold_or_two_taps() -> void:
	# The HUD's column is a place a finger holds for the scoreboard: a hold on it or two taps on it
	# never swap the shoulder, a tap on it between two free taps ends the pair, and the double tap
	# still starts from free ground.
	_fixture.free_all()
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, null, false, true)
	_fixture.controls.clock = func() -> float: return _fixture.now
	_fixture.controls.shoulder_swapped.connect(func() -> void: _swaps += 1)
	_fixture.controls.looked.connect(func(look: Vector2) -> void: _looks += look)
	var rules := GameRules.new((load(HudFixture.TUNING) as RulesTuning).duplicate(true), 1958)
	_fixture.hud.state.set_player_name(1, "Player 1")
	_fixture.hud.feed(rules.apply(RulesAction.add_player(1)))
	for _i in 5:
		await get_tree().process_frame
	var column := Vector2.INF
	for zone in _fixture.hud.touch_zones():
		if zone[&"action"] == &"scoreboard":
			column = (zone[&"rect"] as Rect2).get_center()
	assert_bool(column.is_finite()).is_true()
	# Two taps on the column.
	await _tap(column)
	await _tap(column)
	assert_int(_swaps).is_equal(0)
	# A hold on it, however long, and a hold with a free tap after it.
	await _fixture.touch(0, column)
	_fixture.pass_time(1.5)
	await _fixture.lift(0, column)
	_fixture.pass_time(QUICK)
	await _tap()
	assert_int(_swaps).is_equal(0)
	# A tap on the column between two free taps ends the pair.
	_fixture.pass_time(1.0)
	await _tap()
	await _tap(column)
	await _tap()
	assert_int(_swaps).is_equal(0)
	assert_vector(_looks).is_equal(Vector2.ZERO)
	# Free ground still swaps.
	await _tap()
	assert_int(_swaps).is_equal(1)
