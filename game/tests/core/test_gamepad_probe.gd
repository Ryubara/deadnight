# What the Activity tells a player about their controller (`GamepadProbe`).
extends GdUnitTestSuite


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


func test_a_listed_pad_is_connected() -> void:
	var report := {"iframe": true, "policy": true, "pads": 1}
	assert_str(GamepadProbe.note(report)).is_equal(GamepadProbe.READY)


func test_off_the_web_there_is_no_report() -> void:
	assert_dict(GamepadProbe.read()).is_empty()
