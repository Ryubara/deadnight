# The placeholder screen takes its first focus from a reference to its first action, not from a
# child index, so a change to its layout cannot move the focus (#85).
extends GdUnitTestSuite


func _screen(actions: PackedStringArray) -> PlaceholderScreen:
	var screen := PlaceholderScreen.new()
	screen.title = "Soon"
	screen.note = "Not built yet."
	screen.actions = actions
	add_child(auto_free(screen))
	return screen


func test_the_first_action_takes_the_focus() -> void:
	var screen := _screen(PackedStringArray(["Alpha", "Beta"]))
	await await_idle_frame()
	screen.focus_initial()
	assert_str(screen.first_action.text).is_equal("Alpha")
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.first_action)


func test_without_actions_back_takes_the_focus() -> void:
	var screen := _screen(PackedStringArray())
	await await_idle_frame()
	screen.focus_initial()
	assert_object(screen.first_action).is_null()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.back_button)
