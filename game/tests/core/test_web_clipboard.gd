extends GdUnitTestSuite
## Copy and paste inside a Discord Activity (Deadnight #516). The frame may not use the browser's
## clipboard API, and the engine's web runtime cancels every key press on the canvas, so the page
## never gets a paste event from Ctrl+V. `WebClipboard` takes the paste event the page hears and
## puts it into the focused field, and copies through a user gesture. The tests stand in for the
## browser with `eval_js`; `tools/web_smoke/activity.py --clipboard` runs the real thing.


func _clipboard(in_frame := true) -> WebClipboard:
	var clipboard := auto_free(WebClipboard.new()) as WebClipboard
	clipboard.in_frame = in_frame
	add_child(clipboard)
	return clipboard


func _field(text := "", max_length := 0) -> LineEdit:
	var field := auto_free(LineEdit.new()) as LineEdit
	field.max_length = max_length
	add_child(field)
	field.text = text
	field.caret_column = text.length()
	field.grab_focus()
	return field


func test_a_paste_goes_into_the_focused_field_at_the_caret() -> void:
	var field := _field("AB")
	field.caret_column = 1
	var changes := [0]
	field.text_changed.connect(func(_text: String) -> void: changes[0] += 1)
	assert_bool(_clipboard().paste("xyz")).is_true()
	assert_str(field.text).is_equal("AxyzB")
	assert_int(field.caret_column).is_equal(4)
	assert_int(changes[0]).is_equal(1)


func test_a_paste_replaces_the_selection() -> void:
	var field := _field("ABCD")
	field.select(1, 3)
	_clipboard().paste("Z")
	assert_str(field.text).is_equal("AZD")


func test_a_code_pasted_with_spaces_and_a_line_break_is_one_line() -> void:
	var field := _field("")
	_clipboard().paste("  QZXW\n2345 \r\n")
	assert_str(field.text).is_equal("QZXW2345")


func test_a_paste_stops_at_the_fields_length() -> void:
	var field := _field("AB", 8)
	_clipboard().paste("CDEFGHIJKL")
	assert_str(field.text).is_equal("ABCDEFGH")


func test_a_field_that_cannot_be_edited_takes_nothing() -> void:
	var field := _field("AB")
	field.editable = false
	assert_bool(_clipboard().paste("CD")).is_false()
	assert_str(field.text).is_equal("AB")


func test_a_paste_with_nothing_focused_is_dropped() -> void:
	var field := _field("AB")
	field.release_focus()
	assert_bool(_clipboard().paste("CD")).is_false()
	assert_str(field.text).is_equal("AB")


func test_a_paste_the_page_heard_is_applied_on_the_next_frame() -> void:
	var field := _field("")
	var clipboard := _clipboard()
	clipboard.heard("QZXW2345")
	assert_str(field.text).is_equal("")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(field.text).is_equal("QZXW2345")


## What the page answers for `window.deadnightClipboard.write` after a copy: pending, then a result.
func _page_that_writes(answers: Array) -> Callable:
	var left := answers.duplicate()
	return func(js: String) -> Variant:
		if js.contains(".write"):
			return left.pop_front() if left.size() > 1 else left[0]
		return null


func test_a_copy_the_page_confirms_is_a_copy() -> void:
	var clipboard := _clipboard()
	clipboard.eval_js = _page_that_writes(["pending", "pending", "ok"])
	assert_bool(await clipboard.copy("QZXW2345")).is_true()


func test_a_copy_the_page_refuses_says_so() -> void:
	var clipboard := _clipboard()
	clipboard.eval_js = _page_that_writes(["pending", "NotAllowedError"])
	assert_bool(await clipboard.copy("QZXW2345")).is_false()


func test_a_copy_that_never_answers_is_not_a_copy() -> void:
	var clipboard := _clipboard()
	clipboard.eval_js = _page_that_writes(["pending"])
	clipboard.copy_wait = 0.1
	assert_bool(await clipboard.copy("QZXW2345")).is_false()


func test_outside_a_frame_the_engine_copies_as_before() -> void:
	# A tab or the desktop: no page layer in the way, and the answer is always yes.
	WebClipboard.current = null
	assert_bool(await WebClipboard.copy_text("QZXW2345")).is_true()


func test_text_selected_in_a_field_is_what_ctrl_c_offers() -> void:
	var field := _field("QZXW2345")
	field.select_all()
	assert_str(WebClipboard.selected_text(field)).is_equal("QZXW2345")
	field.deselect()
	assert_str(WebClipboard.selected_text(field)).is_equal("")
	assert_str(WebClipboard.selected_text(null)).is_equal("")


func test_the_line_says_what_the_clipboard_can_do_in_the_frame() -> void:
	assert_str(WebClipboard.note({})).is_equal("")
	assert_str(WebClipboard.note({"iframe": false})).is_equal("")
	var blocked := {"iframe": true, "policy_read": false, "policy_write": false}
	assert_str(WebClipboard.note(blocked)).is_equal(WebClipboard.BLOCKED)
	(
		assert_str(WebClipboard.note({"iframe": true, "policy_read": true, "policy_write": true}))
		. is_equal(WebClipboard.ALLOWED)
	)
	var refused := {"iframe": true, "policy_write": false, "write": "NotAllowedError", "copies": 0}
	assert_str(WebClipboard.note(refused)).contains("copy failed")


func test_the_detail_counts_what_the_page_saw() -> void:
	var report := {
		"iframe": true,
		"policy_read": false,
		"policy_write": false,
		"write": "ok",
		"ctrl_v": 2,
		"pastes": 1,
		"ctrl_c": 3,
		"copies": 3
	}
	(
		assert_str(WebClipboard.detail(report))
		. is_equal(
			"clipboard api read no, write no, button copy ok, Ctrl+V 2 seen 1 pasted, Ctrl+C 3 seen 3 copied"
		)
	)
