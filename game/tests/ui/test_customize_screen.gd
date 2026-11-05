# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## The customization screen driven with simulated keyboard, gamepad and mouse input: the grid's
## move the look, locked ones refuse, presets and Randomize apply, Save and a fresh screen restore.
## The screen is opened at level 55 (everything is the player's) unless a test gives other unlocks.

const SCREEN := "res://ui/screens/customize_screen.tscn"
const TEST_PATH := "user://customize_screen_test.cfg"

var _saved_path: String
var _screen: CustomizeScreen


func before_test() -> void:
	# Another suite may have left the router in a transition, which swallows input, or a screen
	# whose timers take the focus from ours whenever they end.
	await RouterFixture.clear(get_tree())
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
	await RouterFixture.clear(get_tree())


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
	var given := params.duplicate()
	if not given.has("unlocks"):
		given["unlocks"] = LookUnlocks.at_level(LevelCurve.MAX_LEVEL)
	screen.params = given
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
	# The default look is the first preset: the Greaser costume is the one worn.
	assert_bool(_screen.costume_cell(0).worn).is_true()


func test_the_first_focus_is_the_body_tab() -> void:
	await await_idle_frame()
	_screen.focus_initial()
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(_screen.tab_button(&"body"))


func test_the_character_choice_switches_to_her_and_everything_follows() -> void:
	await await_idle_frame()
	assert_bool(_screen.cell("part:body", 0).worn).is_true()
	# A real click on her cell.
	var her := _screen.cell("part:body", 1)
	await _click(her, her.size * 0.5)
	assert_str(String(_screen.look.body())).is_equal("female")
	assert_bool(her.worn).is_true()
	assert_bool(_screen.cell("part:body", 0).worn).is_false()
	# The Greaser's pompadour is his: she gets her bob; the outfit stays.
	assert_str(String(_screen.look.parts[&"hair"])).is_equal("bob")
	assert_str(String(_screen.look.parts[&"torso"])).is_equal("jacket")
	# Her face's names and her model on the turntable.
	assert_str(_screen.cell("part:head", 0).shown_name()).is_equal("Natural")
	var shown := SoldierLook.visible_meshes(_screen.look.to_soldier_look())
	assert_array(shown).contains(
		["head__plain__female", "torso__jacket__female", "legs__cuffed__female"]
	)
	var model := _screen.preview().model
	(
		assert_bool((model.find_child("torso__jacket__female", true, false) as Node3D).visible)
		. is_true()
	)
	assert_object(model.find_child("torso__jacket", true, false)).is_null()
	# And back: his crew cut, his presets.
	var him := _screen.cell("part:body", 0)
	await _click(him, him.size * 0.5)
	assert_str(String(_screen.look.body())).is_equal("male")
	assert_str(String(_screen.look.parts[&"hair"])).is_equal("crew")
	assert_str(_screen.cell("part:head", 0).shown_name()).is_equal("Clean-shaven")


func test_her_preset_picks_her_and_randomize_keeps_her() -> void:
	_screen.apply_preset(9)
	assert_bool(_screen.cell("part:body", 1).worn).is_true()
	assert_bool(_screen.costume_cell(9).worn).is_true()
	for i in 20:
		_screen.randomize()
		assert_str(String(_screen.look.body())).is_equal("female")


func test_the_mouths_are_free_on_the_body_tab_under_the_face_and_saved() -> void:
	await await_idle_frame()
	var body_sections: Array = []
	for tab: Dictionary in CustomizeScreen.TABS:
		if tab["key"] == &"body":
			body_sections = tab["sections"]
	var parts: Array = (
		body_sections
		. filter(func(s: Dictionary) -> bool: return s.has("part"))
		. map(func(s: Dictionary) -> StringName: return s["part"])
	)
	assert_int(parts.find(&"mouth")).is_equal(parts.find(&"head") + 1)
	var mouths := _screen.cells("part:mouth")
	assert_int(mouths.size()).is_equal(LookCatalog.options(&"mouth").size())
	for mouth in mouths:
		assert_bool(mouth.locked).is_false()
	# At level 1 too: nothing about a mouth is gated.
	var starter := _open({"unlocks": LookUnlocks.new(), "seed": 4})
	for mouth in starter.cells("part:mouth"):
		assert_bool(mouth.locked).is_false()
	# The player's own way: focus the cell and press accept, and the turntable follows at once.
	var second: Dictionary = LookCatalog.options(&"mouth")[1]
	var cell := _screen.cell("part:mouth", 1)
	cell.grab_focus()
	await _key(KEY_ENTER)
	assert_str(String(_screen.look.parts[&"mouth"])).is_equal(String(second["id"]))
	var mesh := "mouth__%s" % second["id"]
	assert_bool((_screen.preview().model.find_child(mesh, true, false) as Node3D).visible).is_true()
	_screen.save()
	var back := LookStore.load_look(LookUnlocks.new())
	assert_str(String(back.parts[&"mouth"])).is_equal(String(second["id"]))


func test_a_preset_keeps_its_mouth_and_randomize_reaches_every_mouth() -> void:
	_screen.choose("part:mouth", LookCatalog.option_index(&"mouth", &"teeth"))
	_screen.apply_preset(1)
	assert_str(String(_screen.look.parts[&"mouth"])).is_equal("smile")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for _i in 200:
		seen[CharacterLook.randomized(rng, _screen.unlocks).parts[&"mouth"]] = true
	assert_int(seen.size()).is_equal(LookCatalog.options(&"mouth").size())


func test_every_slot_and_colour_has_a_grid_on_a_tab() -> void:
	var on_tabs := {}
	for tab: Dictionary in CustomizeScreen.TABS:
		for section: Dictionary in tab["sections"]:
			for kind: String in ["part", "colour"]:
				if section.has(kind):
					on_tabs[kind + ":" + section[kind]] = true
	for slot in LookCatalog.choosable_part_slots():
		(
			assert_bool(on_tabs.has("part:%s" % slot))
			. override_failure_message("slot %s is on no tab" % slot)
			. is_true()
		)
		# Every catalogue entry has a cell, and the wearables with no model yet come after.
		assert_int(_screen.cells("part:" + slot).size()).is_equal(
			LookCatalog.options(slot).size() + LookCatalog.pending(slot).size()
		)
	assert_bool(on_tabs.has("part:body")).is_true()
	for slot in LookCatalog.colour_slots():
		assert_bool(on_tabs.has("colour:%s" % slot)).is_true()
		assert_int(_screen.cells("colour:" + slot).size()).is_equal(
			LookCatalog.palette(slot).size()
		)


func test_the_keyboard_walks_along_the_skin_swatches_and_accept_wears() -> void:
	await await_idle_frame()
	var start: int = _screen.look.colours[&"skin"]
	_screen.cell("colour:skin", start).grab_focus()
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	# Walking is not choosing: the look changes on accept.
	assert_int(_screen.look.colours[&"skin"]).is_equal(start)
	await _key(KEY_ENTER)
	assert_int(_screen.look.colours[&"skin"]).is_equal(start + 2)
	assert_bool(_screen.cell("colour:skin", start + 2).worn).is_true()
	assert_bool(_screen.is_dirty()).is_true()


func test_the_gamepad_dpad_walks_the_grid_and_a_wears() -> void:
	await await_idle_frame()
	var start: int = _screen.look.colours[&"hair"]
	_screen.show_tab(&"hair")
	await await_idle_frame()
	_screen.cell("colour:hair", start).grab_focus()
	for i in 3:
		await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	assert_int(_screen.look.colours[&"hair"]).is_equal(start + 3)
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	assert_int(_screen.look.colours[&"hair"]).is_equal(start + 2)


func test_the_gamepad_walks_from_a_tab_down_into_the_grid_and_back_up() -> void:
	await await_idle_frame()
	var tab := _screen.tab_button(&"torso")
	_screen.show_tab(&"torso")
	await await_idle_frame()
	await await_idle_frame()
	tab.grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var first := _screen.cells("part:torso")[0]
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(first)
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(tab)
	# Along the strip the focus walks and a press shows the tab.
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(_screen.tab_button(&"legs"))
	assert_str(String(_screen.current_tab())).is_equal("torso")
	await _pad(JOY_BUTTON_A)
	assert_str(String(_screen.current_tab())).is_equal("legs")


func test_the_mouse_clicks_a_swatch_a_tab_and_a_wearable() -> void:
	await await_idle_frame()
	var skin := _screen.cell("colour:skin", 3)
	_screen.reveal(skin)
	await await_idle_frame()
	await _click(skin, skin.size * 0.5)
	assert_int(_screen.look.colours[&"skin"]).is_equal(3)
	# The Hats tab, by a click, then the helmet.
	var tab := _screen.tab_button(&"headwear")
	await _click(tab, tab.size * 0.5)
	assert_str(String(_screen.current_tab())).is_equal("headwear")
	await await_idle_frame()
	var helmet := _screen.cell_of(&"headwear", &"helmet")
	await _click(helmet, helmet.size * 0.5)
	assert_str(String(_screen.look.parts[&"headwear"])).is_equal("helmet")
	assert_bool(helmet.worn).is_true()
	(
		assert_bool(_screen.preview().model.find_child("headwear__helmet", true, false).visible)
		. is_true()
	)


func test_a_locked_item_can_be_looked_at_but_not_worn() -> void:
	var poor := _open({"unlocks": LookUnlocks.at_level(10), "seed": 3})
	poor.show_tab(&"colours")
	await await_idle_frame()
	var locked := poor.first_locked_cell()
	assert_object(locked).is_not_null()
	var before := poor.look.duplicate_look()
	locked.grab_focus()
	# The focus alone reads how to get it; accept is refused and the look stays.
	assert_str(poor.detail_text()).is_equal("??? - Reach level 15 (you are level 10)")
	await _key(KEY_ENTER)
	assert_bool(poor.look.equals(before)).is_true()
	assert_bool(locked.worn).is_false()
	assert_str(poor.detail_text()).contains("Reach level 15")


func test_unlocking_opens_the_items() -> void:
	var poor := _open({"unlocks": LookUnlocks.at_level(10), "seed": 3})
	var gold := poor.cell("colour:primary", 11)
	assert_bool(gold.locked).is_true()
	assert_bool(poor.cell("colour:primary", 0).locked).is_false()
	var rich := _open({"unlocks": LookUnlocks.at_level(42), "seed": 3})
	assert_bool(rich.cell("colour:primary", 11).locked).is_false()
	rich.choose("colour:primary", 11)
	assert_int(rich.look.colours[&"primary"]).is_equal(11)
	# Choosing a locked one does nothing.
	poor.choose("colour:primary", 11)
	assert_int(poor.look.colours[&"primary"]).is_not_equal(11)


func test_every_preset_can_be_applied_and_the_preview_follows() -> void:
	for i in LookCatalog.presets().size():
		_screen.apply_preset(i)
		assert_bool(_screen.look.equals(CharacterLook.from_preset(i))).is_true()
		for slot in LookCatalog.colour_slots():
			var worn := _screen.cell("colour:" + slot, CharacterLook.from_preset(i).colours[slot])
			assert_bool(worn.worn).is_true()


func test_a_preset_a_player_cannot_wear_whole_is_put_on_in_what_they_may_wear() -> void:
	var starter := _open({"unlocks": LookUnlocks.new(), "seed": 1})
	starter.apply_preset(5)
	assert_bool(starter.look.equals(starter.look.without_locked(starter.unlocks))).is_true()
	assert_bool(starter.look.equals(CharacterLook.from_preset(5))).is_false()


func test_randomize_is_repeatable_with_a_seed_and_never_locked() -> void:
	var other := _open({"seed": 11})
	_screen.randomize()
	other.randomize()
	assert_bool(_screen.look.equals(other.look)).is_true()
	var starter := _open({"unlocks": LookUnlocks.new(), "seed": 5})
	for i in 20:
		starter.randomize()
		assert_bool(starter.look.equals(starter.look.without_locked(starter.unlocks))).is_true()


func test_save_then_open_a_fresh_screen_restores_the_look() -> void:
	_screen.apply_preset(4)
	_screen.choose("colour:accent", 4)
	var expected := _screen.look.duplicate_look()
	_screen.save()
	assert_bool(_screen.is_dirty()).is_false()
	# As after a restart: the file is read again.
	Settings.load_from_disk()
	var fresh := _open({"seed": 1})
	assert_bool(fresh.look.equals(expected)).is_true()
	assert_bool(fresh.cell("colour:accent", 4).worn).is_true()
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


func test_the_main_menu_hosts_the_wardrobe_on_its_loadout_tab() -> void:
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	menu.shell.show_tab(MenuTab.Id.LOADOUT)
	var panel := menu.shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	assert_object(panel.wardrobe).is_instanceof(CustomizeScreen)
	# Embedded: the pickers and the footer, no title, turntable or Back of its own.
	assert_object(panel.wardrobe.preview()).is_null()
	assert_object(panel.wardrobe.find_child("Back", true, false)).is_null()
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
