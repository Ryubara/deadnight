# The map picker (#624), driven the way a player drives it: the keyboard, a gamepad and a finger
# move the focus over the cards and choose, a card for a map that is not built yet can be read but
# chooses nothing, and the settings panel hands the choice out with the other rules. A stub second
# map makes the choice real (the lot is the one map that ships).
extends GdUnitTestSuite

const PHONE_CANVAS := Vector2(1168.0, 540.0)

var _heard: Array[String] = []
var _blocked: Array[String] = []


func before_test() -> void:
	StubMaps.install()
	UIInputMode.reset()
	_heard.clear()
	_blocked.clear()


func after_test() -> void:
	StubMaps.remove()
	UIInputMode.reset()


func _picker() -> MapPicker:
	var holder := Control.new()
	holder.size = Vector2(1280.0, 720.0)
	add_child(holder)
	var picker := MapPicker.new()
	holder.add_child(picker)
	picker.chosen.connect(func(id: String) -> void: _heard.append(id))
	picker.blocked.connect(func(info: MapInfo) -> void: _blocked.append(info.id))
	await get_tree().process_frame
	await get_tree().process_frame
	return picker


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)
		await get_tree().process_frame


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event)
		await get_tree().process_frame


## A finger on `control`: the touch screen's emulated mouse, which is what a tap becomes.
func _tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = at
		touch.pressed = pressed
		get_viewport().push_input(touch)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		click.device = InputEvent.DEVICE_ID_EMULATION
		get_viewport().push_input(click, true)
		await get_tree().process_frame


func _focused(picker: MapPicker) -> String:
	var owner := picker.get_viewport().gui_get_focus_owner()
	return str(owner.name) if owner != null else ""


func test_there_is_a_card_for_every_map_and_the_lot_is_chosen() -> void:
	var picker := await _picker()
	assert_int(picker.cards.size()).is_equal(MapRegistry.all().size())
	assert_str(picker.selected_id).is_equal("drive_in")
	assert_bool(picker.card_for("drive_in").selected).is_true()
	assert_bool(picker.card_for("small_indoor").selected).is_false()
	assert_bool(picker.card_for("small_indoor").is_locked()).is_true()
	assert_bool(picker.card_for(StubMaps.ID).is_locked()).is_false()
	# A screen reader gets the name, the facts and the state of each card.
	assert_str(picker.card_for("drive_in").accessibility_name).is_equal(
		"Drive-in lot, 13,200 m² · 1 to 4 players, selected"
	)
	assert_str(picker.card_for("small_indoor").accessibility_name).is_equal(
		"The back rooms, 600 m² · 1 to 4 players, coming soon"
	)


func test_the_keyboard_walks_the_cards_and_chooses_with_enter() -> void:
	var picker := await _picker()
	picker.card_for("drive_in").grab_focus()
	await _key(KEY_DOWN)
	assert_str(_focused(picker)).is_equal("small_indoor")
	await _key(KEY_DOWN)
	assert_str(_focused(picker)).is_equal(StubMaps.ID)
	# Down at the last card and left and right stay on the card.
	await _key(KEY_DOWN)
	await _key(KEY_LEFT)
	await _key(KEY_RIGHT)
	assert_str(_focused(picker)).is_equal(StubMaps.ID)
	await _key(KEY_ENTER)
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	assert_array(_heard).is_equal([StubMaps.ID])
	assert_bool(picker.card_for(StubMaps.ID).selected).is_true()
	assert_bool(picker.card_for("drive_in").selected).is_false()
	await _key(KEY_UP)
	await _key(KEY_UP)
	assert_str(_focused(picker)).is_equal("drive_in")
	await _key(KEY_SPACE)
	assert_str(picker.selected_id).is_equal("drive_in")
	assert_array(_heard).is_equal([StubMaps.ID, "drive_in"])


func test_a_card_that_is_not_built_can_be_read_but_chooses_nothing() -> void:
	var picker := await _picker()
	picker.card_for("drive_in").grab_focus()
	await _key(KEY_DOWN)
	assert_str(_focused(picker)).is_equal("small_indoor")
	await _key(KEY_ENTER)
	assert_str(picker.selected_id).is_equal("drive_in")
	assert_array(_heard).is_empty()
	assert_array(_blocked).is_equal(["small_indoor"])
	assert_bool(picker.card_for("drive_in").selected).is_true()
	assert_bool(picker.card_for("small_indoor").selected).is_false()


func test_a_gamepad_walks_the_cards_and_chooses_with_a() -> void:
	var picker := await _picker()
	picker.card_for("drive_in").grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_str(_focused(picker)).is_equal(StubMaps.ID)
	await _pad(JOY_BUTTON_A)
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_str(_focused(picker)).is_equal("small_indoor")
	await _pad(JOY_BUTTON_A)
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	assert_array(_blocked).is_equal(["small_indoor"])
	await _pad(JOY_BUTTON_DPAD_UP)
	await _pad(JOY_BUTTON_A)
	assert_str(picker.selected_id).is_equal("drive_in")
	assert_array(_heard).is_equal([StubMaps.ID, "drive_in"])


func test_a_finger_chooses_a_card_and_a_tap_on_a_locked_one_does_nothing() -> void:
	var picker := await _picker()
	UIInputMode.touch = true
	await _tap(picker.card_for(StubMaps.ID))
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	assert_array(_heard).is_equal([StubMaps.ID])
	await _tap(picker.card_for("small_indoor"))
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	assert_array(_blocked).is_equal(["small_indoor"])
	await _tap(picker.card_for("drive_in"))
	assert_str(picker.selected_id).is_equal("drive_in")
	# A tap on the card already chosen says nothing new.
	await _tap(picker.card_for("drive_in"))
	assert_array(_heard).is_equal([StubMaps.ID, "drive_in"])


func test_the_pointer_over_a_card_gives_it_the_focus() -> void:
	var picker := await _picker()
	var card := picker.card_for(StubMaps.ID)
	var at := card.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	assert_str(_focused(picker)).is_equal(StubMaps.ID)


func test_set_selected_says_nothing_and_an_unplayable_id_is_the_lot() -> void:
	var picker := await _picker()
	picker.set_selected(StubMaps.ID)
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	picker.set_selected("small_indoor")
	assert_str(picker.selected_id).is_equal("drive_in")
	picker.set_selected("nope")
	assert_str(picker.selected_id).is_equal("drive_in")
	assert_array(_heard).is_empty()


func test_a_guest_sees_the_map_and_cannot_change_it() -> void:
	var picker := await _picker()
	picker.set_selected(StubMaps.ID)
	picker.set_editable(false)
	assert_int(picker.card_for(StubMaps.ID).focus_mode).is_equal(Control.FOCUS_NONE)
	assert_int(picker.card_for("drive_in").mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	picker.card_for("drive_in").pressed.emit()
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	assert_array(_heard).is_empty()
	picker.set_editable(true)
	assert_int(picker.card_for("drive_in").focus_mode).is_equal(Control.FOCUS_ALL)
	picker.card_for("drive_in").pressed.emit()
	assert_str(picker.selected_id).is_equal("drive_in")


func test_the_phone_form_has_no_picture_and_is_a_tap_target_high() -> void:
	var picker := await _picker()
	var desktop_height := picker.card_for("drive_in").custom_minimum_size.y
	picker.set_compact(true)
	for card in picker.cards:
		assert_float(card.custom_minimum_size.y).is_greater_equal(MenuLook.TAP_TARGET)
		assert_float(card.custom_minimum_size.y).is_less(desktop_height)
	picker.set_compact(false)
	assert_float(picker.card_for("drive_in").custom_minimum_size.y).is_equal(desktop_height)


func test_the_phone_form_puts_the_cards_two_to_a_row_and_the_arrows_follow() -> void:
	var picker := await _picker()
	picker.set_compact(true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(picker.columns).is_equal(2)
	var lot := picker.card_for("drive_in")
	var small := picker.card_for("small_indoor")
	var stub := picker.card_for(StubMaps.ID)
	# Two cards fit the 440 units a row's control column has, side by side.
	assert_float(small.global_position.y).is_equal_approx(lot.global_position.y, 0.5)
	assert_float(small.get_global_rect().end.x).is_less_equal(
		lot.global_position.x + MapPicker.WIDTH + 0.5
	)
	assert_float(stub.global_position.y).is_greater(lot.global_position.y)
	lot.grab_focus()
	await _key(KEY_RIGHT)
	assert_str(_focused(picker)).is_equal("small_indoor")
	await _key(KEY_RIGHT)
	assert_str(_focused(picker)).is_equal("small_indoor")
	await _key(KEY_DOWN)
	assert_str(_focused(picker)).is_equal(StubMaps.ID)
	await _key(KEY_LEFT)
	assert_str(_focused(picker)).is_equal(StubMaps.ID)
	await _key(KEY_UP)
	assert_str(_focused(picker)).is_equal("drive_in")
	# A finger chooses in this form too.
	UIInputMode.touch = true
	await _tap(stub)
	assert_str(picker.selected_id).is_equal(StubMaps.ID)
	assert_array(picker.top_row()).contains_exactly([lot, small])
	picker.set_compact(false)
	assert_int(picker.columns).is_equal(1)
	assert_array(picker.top_row()).contains_exactly([lot])


func test_the_panel_hands_the_choice_out_with_the_other_rules() -> void:
	var holder := Control.new()
	add_child(holder)
	var panel := MatchSettingsPanel.new()
	holder.add_child(panel)
	await get_tree().process_frame
	var heard: Array[MatchSettings] = []
	panel.changed.connect(heard.append)
	assert_str(panel.settings().map).is_equal("drive_in")
	assert_bool(panel.settings().is_default()).is_true()
	panel.map_picker.card_for(StubMaps.ID).pressed.emit()
	assert_str(panel.settings().map).is_equal(StubMaps.ID)
	assert_int(heard.size()).is_equal(1)
	assert_str(heard[0].map).is_equal(StubMaps.ID)
	assert_bool(panel.settings().is_default()).is_false()
	# What the panel is given it shows, without saying changed; the usual rules put the lot back.
	var given := MatchSettings.new()
	given.count_multiplier = 3.0
	given.map = StubMaps.ID
	panel.set_settings(given)
	assert_bool(panel.settings().same_as(given)).is_true()
	assert_int(heard.size()).is_equal(1)
	panel.set_settings(MatchSettings.new())
	assert_str(panel.map_picker.selected_id).is_equal("drive_in")
	# A map nobody can play is shown as the lot.
	var locked := MatchSettings.new()
	locked.map = "small_indoor"
	panel.set_settings(locked)
	assert_str(panel.map_picker.selected_id).is_equal("drive_in")
	assert_str(panel.row_for("map").hint).is_not_empty()
	# The picker is the first control of the form, and a guest's panel is read only.
	assert_array(panel.first_controls()).contains_exactly([panel.map_picker.first_card()])
	panel.set_editable(false)
	assert_int(panel.map_picker.card_for("drive_in").focus_mode).is_equal(Control.FOCUS_NONE)
	holder.free()


func test_the_compact_panel_fits_a_phone_held_sideways() -> void:
	var holder := Control.new()
	holder.size = PHONE_CANVAS
	add_child(holder)
	var screen := (load("res://ui/screens/play_screen.tscn") as PackedScene).instantiate()
	holder.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var play := screen as PlayScreen
	for card in play.panel.map_picker.cards:
		var rect := card.get_global_rect()
		assert_float(rect.position.y).is_greater_equal(-0.5)
		assert_float(rect.end.y).is_less_equal(PHONE_CANVAS.y + 0.5)
		assert_float(rect.size.y).is_greater_equal(MenuLook.TAP_TARGET - 0.5)
	holder.free()
