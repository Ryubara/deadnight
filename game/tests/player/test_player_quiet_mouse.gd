extends GdUnitTestSuite
## A program the kit's `gds godot` starts on its hidden desktop gets GDS_QUIET=1 and must
## never capture the mouse: Windows applies the cursor clip to the person's desktop too
## (kit docs/godot/no-focus.md).

var _saved := ""


func before_test() -> void:
	_saved = OS.get_environment("GDS_QUIET")


func after_test() -> void:
	if _saved.is_empty():
		OS.unset_environment("GDS_QUIET")
	else:
		OS.set_environment("GDS_QUIET", _saved)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_capture_is_allowed_outside_the_quiet_launcher() -> void:
	OS.unset_environment("GDS_QUIET")
	assert_bool(Player.mouse_capture_allowed()).is_true()


func test_capture_is_refused_under_the_quiet_launcher() -> void:
	OS.set_environment("GDS_QUIET", "1")
	assert_bool(Player.mouse_capture_allowed()).is_false()
