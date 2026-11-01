extends GdUnitTestSuite
## The customization screen driven with simulated keyboard, gamepad and mouse input: pickers move
## the look, locked options refuse, presets and Randomize apply, Save and a fresh screen restore.

const SCREEN := "res://ui/screens/customize_screen.tscn"
const TEST_PATH := "user://customize_screen_test.cfg"

var _saved_path: String
var _screen: CustomizeScreen


func before_test() -> void:
	# Another suite may have left the router in a transition, which swallows input.
	if UIRouter.busy:
		await UIRouter.idle
	UIInputMode.pointer = false
	_release_pad()
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	_screen = _open({"seed": 11})


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	UIMotion.reduced = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## Releases every pad button the tests use, so a press another suite left held cannot swallow ours.
func _release_pad() -> void:
	for button: JoyButton in [
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT
	]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = false
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _open(params := {}) -> CustomizeScreen:
	# The screen is laid out for the 1920 by 1080 design size; a click only lands on what is inside
	# the window.
	get_window().size = Vector2i(1920, 1080)
	var screen := (load(SCREEN) as PackedScene).instantiate() as CustomizeScreen
	screen.params = params
	# On a layer of its own, above the test runner's own controls, so a click reaches the screen.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	auto_free(layer)
	layer.add_child(screen)
	return screen


func _send(event: InputEvent) -> void:
	# Straight into the viewport, the way a device event arrives: the `Input` singleton keeps its own
	# idea of which buttons are held, and a press another suite left held made it swallow ours.
	get_viewport().push_input(event)
	await get_tree().process_frame


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		await _send(event)


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		await _send(event)


func _click(control: Control, at_local: Vector2) -> void:
	var at := control.get_global_transform_with_canvas() * at_local
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _send(event)


func test_it_starts_on_the_saved_look_and_shows_it() -> void:
	assert_bool(_screen.look.equals(CharacterLook.default_look())).is_true()
	assert_bool(_screen.is_dirty()).is_false()
	assert_object(_screen.preview().model).is_not_null()
	# The default look is the first preset, so the selector reads its name.
	var selector := (
		_screen.find_children("*", "UIOptionSelector", true, false)[0] as UIOptionSelector
	)
	assert_str(selector.text()).is_equal("Greaser")


func test_the_first_focus_is_the_preset_selector() -> void:
	await await_idle_frame()
	_screen.focus_initial()
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_instanceof(UIOptionSelector)


func test_every_choosable_slot_has_a_strip() -> void:
	for slot in LookCatalog.choosable_part_slots():
		assert_object(_screen.strip("part:" + slot)).is_not_null()
	for slot in LookCatalog.colour_slots():
		assert_int(_screen.strip("colour:" + slot).entries.size()).is_equal(
			LookCatalog.palette(slot).size()
		)


func test_the_keyboard_moves_along_a_strip_and_the_look_follows() -> void:
	var strip := _screen.strip("colour:skin")
	strip.grab_focus()
	var start: int = _screen.look.colours[&"skin"]
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	assert_int(strip.selected).is_equal(start + 2)
	assert_int(_screen.look.colours[&"skin"]).is_equal(start + 2)
	await _key(KEY_LEFT)
	assert_int(_screen.look.colours[&"skin"]).is_equal(start + 1)
	assert_bool(_screen.is_dirty()).is_true()


func test_the_gamepad_dpad_moves_along_a_strip() -> void:
	var strip := _screen.strip("colour:secondary")
	strip.grab_focus()
	var start: int = _screen.look.colours[&"secondary"]
	for i in 3:
		# The game's own menu, still in the router under the test, takes focus back after a press
		# when the whole project runs in one process; the strip claims it again each time.
		strip.grab_focus()
		await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_int(_screen.look.colours[&"secondary"]).is_equal(start + 3)
	strip.grab_focus()
	await _pad(JOY_BUTTON_DPAD_LEFT)
	assert_int(_screen.look.colours[&"secondary"]).is_equal(start + 2)


func test_the_gamepad_walks_down_the_rows_and_back_up() -> void:
	var first := _screen.strip("part:headwear")
	first.grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(
		_screen.strip("colour:skin")
	)
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(first)


func test_the_mouse_clicks_a_swatch_and_a_text_chip() -> void:
	await await_idle_frame()
	var skin := _screen.strip("colour:skin")
	await _click(skin, skin.chip_rect(3).get_center())
	assert_int(_screen.look.colours[&"skin"]).is_equal(3)
	var shoulders := _screen.strip("part:headwear")
	await _click(shoulders, shoulders.chip_rect(1).get_center())
	assert_str(String(_screen.look.parts[&"headwear"])).is_equal("helmet")
	var head := _screen.preview().model.find_child("Head", true, false) as MeshInstance3D
	assert_float((head.get_active_material(1) as BaseMaterial3D).albedo_color.a).is_equal(1.0)


func test_a_locked_option_can_be_looked_at_but_not_chosen() -> void:
	var strip := _screen.strip("colour:primary")
	strip.grab_focus()
	var blocked: Array[int] = []
	strip.blocked.connect(func(index: int) -> void: blocked.append(index))
	for i in 10:
		await _key(KEY_RIGHT)
	assert_int(strip.selected).is_equal(10)
	assert_int(_screen.look.colours[&"primary"]).is_equal(10)
	await _key(KEY_RIGHT)
	assert_int(strip.cursor).is_equal(11)
	assert_int(strip.selected).is_equal(10)
	assert_int(_screen.look.colours[&"primary"]).is_equal(10)
	assert_array(blocked).contains([11])
	# Accept on it is refused too, and the screen says how to get it.
	await _key(KEY_ENTER)
	assert_int(_screen.look.colours[&"primary"]).is_equal(10)
	assert_bool(_hint_text().contains("Billing level 10")).is_true()


func test_locked_swatches_are_flagged_and_unlocking_opens_them() -> void:
	assert_bool(_screen.strip("colour:primary").entries[11]["locked"]).is_true()
	assert_bool(_screen.strip("colour:primary").entries[0]["locked"]).is_false()
	var rich := LookUnlocks.new()
	rich.billing_level = 10
	var opened := _open({"unlocks": rich, "seed": 3})
	assert_bool(opened.strip("colour:primary").entries[11]["locked"]).is_false()
	opened.strip("colour:primary").move_to(11)
	assert_int(opened.look.colours[&"primary"]).is_equal(11)


func test_a_preset_picked_with_the_keyboard_applies_and_shows_its_name() -> void:
	var selector := (
		_screen.find_children("*", "UIOptionSelector", true, false)[0] as UIOptionSelector
	)
	selector.grab_focus()
	await _key(KEY_RIGHT)
	assert_bool(_screen.look.equals(CharacterLook.from_preset(1))).is_true()
	assert_str(selector.text()).is_equal("Usher")
	# Editing a colour leaves the preset: the selector reads Custom.
	_screen.strip("colour:hair").move_to(3)
	assert_str(selector.text()).is_equal(CustomizeScreen.CUSTOM_LABEL)


func test_every_preset_can_be_applied_and_the_preview_follows() -> void:
	for i in LookCatalog.presets().size():
		_screen.apply_preset(i)
		assert_bool(_screen.look.equals(CharacterLook.from_preset(i))).is_true()
		for slot in LookCatalog.colour_slots():
			assert_int(_screen.strip("colour:" + slot).selected).is_equal(
				CharacterLook.from_preset(i).colours[slot]
			)


func test_randomize_is_repeatable_with_a_seed_and_never_locked() -> void:
	var other := _open({"seed": 11})
	_screen.randomize()
	other.randomize()
	assert_bool(_screen.look.equals(other.look)).is_true()
	var unlocks := LookUnlocks.new()
	for i in 20:
		_screen.randomize()
		assert_bool(_screen.look.equals(_screen.look.without_locked(unlocks))).is_true()


func test_save_then_open_a_fresh_screen_restores_the_look() -> void:
	_screen.apply_preset(4)
	_screen.strip("colour:accent").move_to(4)
	var expected := _screen.look.duplicate_look()
	_screen.save()
	assert_bool(_screen.is_dirty()).is_false()
	# As after a restart: the file is read again.
	Settings.load_from_disk()
	var fresh := _open({"seed": 1})
	assert_bool(fresh.look.equals(expected)).is_true()
	assert_int(fresh.strip("colour:accent").selected).is_equal(4)
	assert_bool(fresh.is_dirty()).is_false()


func test_leaving_without_saving_keeps_the_old_look() -> void:
	_screen.apply_preset(2)
	assert_bool(_screen.is_dirty()).is_true()
	var fresh := _open({"seed": 1})
	assert_bool(fresh.look.equals(CharacterLook.default_look())).is_true()


func test_the_turntable_turns_by_itself_but_stands_still_with_reduced_motion() -> void:
	var preview := _screen.preview()
	var start := preview.angle
	await await_millis(300)
	assert_float(preview.angle).is_greater(start)
	UIMotion.reduced = true
	var held := preview.angle
	await await_millis(300)
	assert_float(preview.angle).is_equal(held)


func test_dragging_the_preview_turns_it() -> void:
	await await_idle_frame()
	UIMotion.reduced = true
	var preview := _screen.preview()
	var before := preview.angle
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	preview._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(100.0, 0.0)
	preview._gui_input(drag)
	assert_float(preview.angle - before).is_equal_approx(100.0 * LookPreview.DRAG_SPEED, 0.001)


func test_the_main_menu_opens_the_wardrobe() -> void:
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var button := UIRouter.top().find_child("Customize", true, false) as UIButton
	assert_object(button).is_not_null()
	button.pressed.emit()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(CustomizeScreen)
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle


func _hint_text() -> String:
	for label in _screen.find_children("*", "UILabel", true, false):
		if (label as Label).text.begins_with("Locked:"):
			return (label as Label).text
	return ""
