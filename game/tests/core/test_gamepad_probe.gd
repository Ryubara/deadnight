# What the Activity tells a player about their controller (`GamepadProbe`).
extends GdUnitTestSuite


func test_a_scripts_yes_is_a_yes_whatever_type_the_engine_hands_back() -> void:
	# The web runtime answers `true` as the integer 1; `answer == true` on it stops the function
	# in a release build, and the answer was asked for again at every read (#983).
	assert_bool(GamepadProbe.truthy(1)).is_true()
	assert_bool(GamepadProbe.truthy(true)).is_true()
	assert_bool(GamepadProbe.truthy(0)).is_false()
	assert_bool(GamepadProbe.truthy(false)).is_false()
	assert_bool(GamepadProbe.truthy(null)).is_false()


func test_no_report_says_nothing() -> void:
	assert_str(GamepadProbe.note({})).is_empty()


func test_a_policy_that_forbids_the_gamepad_is_blocked() -> void:
	var report := {"iframe": true, "policy": false, "pads": 0}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.BLOCKED)


func test_a_thrown_error_is_blocked_even_when_the_policy_is_unknown() -> void:
	var report := {"iframe": true, "policy": null, "error": "SecurityError"}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.BLOCKED)


func test_an_allowed_page_with_no_pad_yet_waits_for_a_button() -> void:
	var report := {"iframe": true, "policy": true, "pads": 0}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.WAITING)


func test_a_page_without_the_focus_is_told_to_click_first() -> void:
	var report := {"iframe": true, "focus": false, "policy": true, "pads": 0}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.UNFOCUSED)


func test_a_page_clicked_that_still_lacks_the_focus_says_discord_holds_it() -> void:
	var report := {"iframe": true, "focus": false, "clicks": 3, "policy": true, "pads": 0}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.NO_FOCUS)


func test_the_detail_gives_the_counts_the_page_saw() -> void:
	var report := {
		"focus": false,
		"clicks": 3,
		"focus_events": 1,
		"blur_events": 2,
		"pad_events": 0,
		"visible": "visible"
	}
	assert_str(GamepadProbe.detail(report)).is_equal(
		"focus no, clicks 3, focus changes 1/2, controller events 0, visible"
	)
	assert_str(GamepadProbe.detail({})).is_empty()


func test_a_frame_without_the_focus_gets_the_click_hint_and_nothing_else_does() -> void:
	assert_str(GamepadProbe.hint({"iframe": true, "focus": false})).is_equal(GamepadProbe.HINT)
	assert_str(GamepadProbe.hint({"iframe": true, "focus": true})).is_empty()
	assert_str(GamepadProbe.hint({"iframe": true})).is_empty()
	assert_str(GamepadProbe.hint({"iframe": false, "focus": false})).is_empty()
	assert_str(GamepadProbe.hint({})).is_empty()


func test_a_listed_pad_is_connected() -> void:
	var report := {"iframe": true, "policy": true, "pads": 1}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.READY)


func test_off_the_web_there_is_no_report() -> void:
	assert_dict(GamepadProbe.read()).is_empty()


func test_outside_a_frame_the_page_is_never_read() -> void:
	# A tab and the desktop are asked once and never again: no report, no polling.
	assert_bool(GamepadProbe.in_frame()).is_false()
	assert_dict(GamepadProbe.read()).is_empty()
	assert_str(GamepadProbe.hint(GamepadProbe.read())).is_empty()
