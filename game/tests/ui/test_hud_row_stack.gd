# Rows that ease into their slots: when a line above leaves, the lines below slide up instead of
# jumping; when lines arrive they take their own slots and never overlap. Time is stepped by hand,
# so no test waits on the clock.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	UIMotion.reduced = false


func _stack(count: int) -> HudRowStack:
	var stack := HudRowStack.new()
	_host.add_child(stack)
	stack.size.x = 300.0
	for i in count:
		stack.add_row(_row("ROW %d" % i))
	return stack


func _row(text: String) -> Label:
	return HudStyle.label(text, HudStyle.TEXT, Color.WHITE)


func _settle(stack: HudRowStack) -> void:
	for _i in 120:
		stack.advance(STEP)
	assert_bool(stack.is_settled()).is_true()


## The rows' rectangles in the stack, top to bottom.
func _rects(stack: HudRowStack) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in stack.get_children():
		rects.append(Rect2(child.position, child.size))
	return rects


func _assert_no_overlap(rects: Array[Rect2], when: String) -> void:
	for i in rects.size() - 1:
		(
			assert_bool(rects[i].end.y <= rects[i + 1].position.y + 0.01)
			. override_failure_message(
				"rows %d and %d overlap %s: %s then %s" % [i, i + 1, when, rects[i], rects[i + 1]]
			)
			. is_true()
		)


func test_rows_are_laid_out_one_under_the_other_once_settled() -> void:
	var stack := _stack(3)
	_settle(stack)
	var rects := _rects(stack)
	var height := rects[0].size.y
	assert_float(rects[0].position.y).is_equal_approx(0.0, 0.01)
	assert_float(rects[1].position.y).is_equal_approx(height + stack.gap, 0.01)
	assert_float(rects[2].position.y).is_equal_approx(2.0 * (height + stack.gap), 0.01)
	assert_float(stack.get_combined_minimum_size().y).is_equal_approx(
		3.0 * height + 2.0 * stack.gap, 0.01
	)


func test_new_rows_step_toward_their_slots_and_never_jump() -> void:
	var stack := _stack(3)
	var last := stack.get_child(2) as Control
	var distance := last.position.y - stack.target_y(last)
	assert_float(distance).is_greater(0.0)
	for _i in 8:
		stack.advance(STEP)
		var left := last.position.y - stack.target_y(last)
		assert_float(left).is_less(distance)
		assert_float(left).is_greater_equal(0.0)
		distance = left
	assert_float(distance).is_greater(0.0)
	_settle(stack)
	assert_float(last.position.y).is_equal_approx(stack.target_y(last), 0.01)


func test_rows_arriving_in_one_frame_never_overlap_at_any_step() -> void:
	var stack := _stack(0)
	for i in 6:
		stack.add_row(_row("LINE %d" % i))
		_assert_no_overlap(_rects(stack), "on arrival")
	for i in 40:
		stack.advance(STEP)
		_assert_no_overlap(_rects(stack), "at step %d" % i)
	_settle(stack)


func test_a_new_row_fades_in_as_it_rises() -> void:
	var stack := _stack(1)
	var row := stack.get_child(0) as Control
	assert_float(row.self_modulate.a).is_equal_approx(0.0, 0.001)
	stack.advance(HudRowStack.ENTER_TIME / 2.0)
	assert_float(row.self_modulate.a).is_between(0.3, 0.7)
	stack.advance(HudRowStack.ENTER_TIME)
	assert_float(row.self_modulate.a).is_equal_approx(1.0, 0.001)


func test_removing_a_row_does_not_move_the_rows_below_at_once() -> void:
	var stack := _stack(3)
	_settle(stack)
	var below := stack.get_child(2) as Control
	var before := below.position.y
	var slot := stack.target_y(below)
	stack.remove_row(stack.get_child(0))
	# Nothing jumped: it still stands where it stood, and its slot is a row higher.
	assert_float(below.position.y).is_equal_approx(before, 0.001)
	assert_float(stack.target_y(below)).is_less(slot - 10.0)
	var left := below.position.y - stack.target_y(below)
	for i in 120:
		stack.advance(STEP)
		var now := below.position.y - stack.target_y(below)
		assert_float(now).is_less_equal(left)
		if i == 0:
			assert_float(now).is_greater(0.0)  # partway, not there
		_assert_no_overlap(_rects(stack), "while sliding up (step %d)" % i)
		left = now
	assert_float(below.position.y).is_equal_approx(stack.target_y(below), 0.01)


func test_a_row_removed_from_the_middle_closes_the_gap_by_sliding() -> void:
	var stack := _stack(4)
	_settle(stack)
	var rows := stack.get_children()
	var first_y := (rows[0] as Control).position.y
	stack.remove_row(rows[1])
	assert_float((rows[0] as Control).position.y).is_equal_approx(first_y, 0.001)
	stack.advance(STEP)
	var third := rows[2] as Control
	assert_float(third.position.y - stack.target_y(third)).is_greater(0.5)
	_settle(stack)
	_assert_no_overlap(_rects(stack), "after the gap closed")


func test_the_height_follows_the_rows() -> void:
	var stack := _stack(3)
	_settle(stack)
	var full := stack.get_combined_minimum_size().y
	stack.remove_row(stack.get_child(0))
	assert_float(stack.get_combined_minimum_size().y).is_equal_approx(full, 0.001)
	stack.advance(STEP)
	var partway := stack.get_combined_minimum_size().y
	assert_float(partway).is_less(full)
	assert_float(partway).is_greater(stack.target_height())
	_settle(stack)
	assert_float(stack.get_combined_minimum_size().y).is_equal_approx(stack.target_height(), 0.01)


func test_the_same_time_gives_the_same_place_at_any_frame_rate() -> void:
	var places: Array[float] = []
	for steps in [1, 2, 4, 8]:
		var stack := _stack(3)
		_settle(stack)
		stack.remove_row(stack.get_child(0))
		for _i in steps:
			stack.advance(0.08 / steps)
		places.append((stack.get_child(1) as Control).position.y)
	for place in places:
		assert_float(place).is_equal_approx(places[0], 0.05)


func test_with_reduced_motion_every_row_is_in_its_slot_at_once() -> void:
	UIMotion.reduced = true
	var stack := _stack(3)
	for row in stack.get_children():
		assert_float((row as Control).position.y).is_equal_approx(stack.target_y(row), 0.001)
		assert_float((row as Control).self_modulate.a).is_equal_approx(1.0, 0.001)
	stack.remove_row(stack.get_child(0))
	assert_bool(stack.is_settled()).is_true()
	assert_float(stack.get_child(0).position.y).is_equal_approx(0.0, 0.001)


# --- The parts that use it ---


func _hud_fixture() -> HudFixture:
	var fixture := HudFixture.make(_host, 1)
	fixture.hud.gains.set_process(false)
	fixture.hud.events_feed.set_process(false)
	return fixture


func test_the_gain_lines_slide_up_when_the_oldest_expires() -> void:
	var gains := _hud_fixture().hud.gains
	gains.add_gain(&"kill", 60)
	gains.advance(0.5)
	gains.add_gain(&"headshot_kill", 100)
	gains.advance(0.5)
	gains.add_gain(&"round_bonus", 50)
	for _i in 60:
		gains.advance(STEP)
	var middle := gains.rows[1]["label"] as Label
	var bottom := gains.rows[2]["label"] as Label
	var middle_slot := middle.position.y
	var bottom_slot := bottom.position.y
	assert_float(middle_slot).is_greater(0.5)
	# Run to the step in which the first line leaves.
	var steps := 0
	while gains.rows.size() == 3 and steps < 600:
		gains.advance(STEP)
		steps += 1
	assert_int(gains.rows.size()).is_equal(2)
	# It did not teleport: both lines are on their way, not at their new slots yet.
	assert_float(middle.position.y).is_less(middle_slot)
	assert_float(middle.position.y).is_greater(0.5)
	assert_float(bottom.position.y).is_less(bottom_slot)
	assert_float(bottom.position.y).is_greater(middle.position.y + middle.size.y)
	# The two lines settle well inside the half second the second one still has to live.
	for _i in 20:
		gains.advance(STEP)
	assert_float(middle.position.y).is_equal_approx(0.0, 0.01)
	assert_float(bottom.position.y).is_equal_approx(middle.size.y + HudStyle.XS, 0.01)


func test_a_burst_of_gains_in_one_frame_stacks_without_overlap() -> void:
	var gains := _hud_fixture().hud.gains
	for amount in [60, 100, 130, 60, 50, 70]:
		gains.add_gain(&"kill", amount)
	for i in 30:
		gains.advance(STEP)
		var rects: Array[Rect2] = []
		for row in gains.rows:
			var label := row["label"] as Label
			rects.append(Rect2(label.position, label.size))
		_assert_no_overlap(rects, "at step %d" % i)


func test_the_event_lines_slide_up_when_the_oldest_expires() -> void:
	var feed := _hud_fixture().hud.events_feed
	feed.push("RUBY OPENED THE CONCESSION STAND")
	feed.advance(1.0)
	feed.push("MOE IS DOWN")
	feed.advance(1.0)
	feed.push("GENERATOR RUNNING LOW")
	for _i in 30:
		feed.advance(STEP)
	var middle := feed.rows[1]["label"] as Label
	var rest := middle.position.y
	assert_float(rest).is_greater(0.5)
	var steps := 0
	while feed.rows.size() == 3 and steps < 900:
		feed.advance(STEP)
		steps += 1
	assert_int(feed.rows.size()).is_equal(2)
	assert_float(middle.position.y).is_greater(0.5)
	assert_float(middle.position.y).is_less(rest)
	for _i in 120:
		feed.advance(STEP)
	assert_float(middle.position.y).is_equal_approx(0.0, 0.01)
