extends GdUnitTestSuite
## The wardrobe's Costumes tab (#1066), driven the way a player drives it: the twelve presets as
## costumes, each lit or a `???` silhouette by what the player owns at levels 1, 10, 30 and 55, a
## real click, key or pad press that wears one whole, the "Default" colours option on the Colours
## tab, and a costume the player does not own that no input can wear.

const SCREEN := "res://ui/screens/customize_screen.tscn"
const TEST_PATH := "user://costumes_tab_test.cfg"
const LEVELS: Array[int] = [1, 10, 30, 55]
const USHER := 1
const MECHANIC := 2
const SODA_JERK := 4
const CARHOP := 8

var _saved_path: String
var _window_before: Vector2i


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	UIInputMode.pointer = true
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	_window_before = get_window().size
	get_window().size = Vector2i(1920, 1080)


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	get_window().size = _window_before
	UIInputMode.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	await RouterFixture.clear(get_tree())


func _open(level: int, extra := {}) -> CustomizeScreen:
	var screen := (load(SCREEN) as PackedScene).instantiate() as CustomizeScreen
	var given := {"unlocks": LookUnlocks.at_level(level), "seed": 5}
	given.merge(extra)
	screen.params = given
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	auto_free(layer)
	layer.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## Shows a tab and lets the grid lay out (the focus links are set in a deferred call).
func _show(screen: CustomizeScreen, tab: StringName) -> void:
	screen.show_tab(tab)
	await get_tree().process_frame
	await get_tree().process_frame


func _point_at(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame


func _click(screen: CustomizeScreen, control: Control) -> void:
	screen.reveal(control)
	await get_tree().process_frame
	await _point_at(control)
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_viewport().push_input(click, true)
		await get_tree().process_frame


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
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


func _colour_index(channel: StringName, id: StringName) -> int:
	var palette := LookCatalog.palette(channel)
	for i in palette.size():
		if palette[i]["id"] == id:
			return i
	return -1


func test_the_costumes_tab_comes_first_and_holds_a_cell_for_each_preset() -> void:
	var screen := await _open(55)
	assert_array(screen.tab_keys().slice(0, 2)).is_equal([&"costumes", &"body"])
	assert_str(screen.tab_button(&"costumes").label()).is_equal("Costumes")
	assert_int(screen.cells(CustomizeScreen.COSTUME_KEY).size()).is_equal(
		LookCatalog.presets().size()
	)
	for index in LookCatalog.presets().size():
		var cell := screen.costume_cell(index)
		assert_object(cell).is_not_null()
		assert_str(cell.title).is_equal(LookCatalog.presets()[index]["name"])


func test_every_costume_is_lit_or_a_silhouette_by_the_level_at_1_10_30_and_55() -> void:
	for level in LEVELS:
		var screen := await _open(level)
		await _show(screen, &"costumes")
		var lit := 0
		for index in Costumes.count():
			var cell := screen.costume_cell(index)
			var owned := Costumes.level_needed(index) <= level
			(
				assert_bool(cell.locked)
				. override_failure_message(
					"%s at level %d: locked should be %s" % [cell.title, level, not owned]
				)
				. is_equal(not owned)
			)
			if owned:
				lit += 1
				assert_str(cell.shown_name()).is_equal(cell.title)
				# (The saved look is the Greaser, so that one reads "wearing".)
				var words := "wearing" if cell.worn else "press to wear it in its own colours"
				assert_str(cell.detail()).is_equal("%s - %s" % [cell.title, words])
			else:
				assert_str(cell.shown_name()).is_equal("???")
				assert_str(cell.instructions).is_equal(
					"Reach level %d (you are level %d)" % [Costumes.level_needed(index), level]
				)
				assert_str(cell.accessibility_name).starts_with("Locked item, Reach level")
		# The counts the data gives today: the two of starting pieces, the projectionist at 4.
		var counts := {1: 2, 10: 3, 30: Costumes.count(), 55: Costumes.count()}
		assert_int(lit).is_equal(counts[level])
		screen.queue_free()
		await get_tree().process_frame


func test_the_costumes_of_starting_pieces_are_lit_at_level_one_and_lead_the_grid() -> void:
	var screen := await _open(1)
	await _show(screen, &"costumes")
	var cells := screen.cells(CustomizeScreen.COSTUME_KEY)
	assert_bool(cells[0].locked).is_false()
	assert_bool(cells[1].locked).is_false()
	assert_array([cells[0].id, cells[1].id]).contains_exactly_in_any_order(
		[&"soda_jerk", &"carhop"]
	)
	for i in range(2, cells.size()):
		assert_bool(cells[i].locked).is_true()
	# A new player can put one on, with a real click, from the first night.
	await _click(screen, screen.costume_cell(SODA_JERK))
	assert_bool(screen.look.equals(CharacterLook.from_preset(SODA_JERK))).is_true()


func test_a_click_wears_a_costume_whole_its_pieces_face_hair_and_colours() -> void:
	var screen := await _open(55)
	await _show(screen, &"costumes")
	var cell := screen.costume_cell(USHER)
	await _click(screen, cell)
	assert_bool(screen.look.equals(CharacterLook.from_preset(USHER))).is_true()
	assert_bool(cell.worn).is_true()
	assert_bool(screen.costume_cell(0).worn).is_false()
	assert_str(screen.detail_text()).is_equal("Usher - wearing")
	assert_bool(screen.is_dirty()).is_true()
	# The soldier on the turntable has the pieces on.
	var model := screen.preview().model
	for mesh in ["headwear__pillbox", "torso__jacket", "legs__striped"]:
		assert_bool((model.find_child(mesh, true, false) as Node3D).visible).is_true()
	# The player may then change any part they own. The face, the hair and the mouth are theirs and
	# it is still the costume; a piece of the outfit makes it their own mix.
	screen.choose("part:hair", LookCatalog.option_index(&"hair", &"flattop"))
	screen.choose("part:mouth", LookCatalog.option_index(&"mouth", &"grin"))
	assert_bool(cell.worn).is_true()
	screen.choose("part:feet", LookCatalog.option_index(&"feet", &"boots"))
	assert_str(String(screen.look.parts[&"feet"])).is_equal("boots")
	assert_bool(cell.worn).is_false()
	await _click(screen, cell)
	assert_bool(cell.worn).is_true()
	# A costume's colours are data on the preset: the same five indices (the hair colour too).
	for channel in LookCatalog.colour_slots():
		assert_int(screen.look.colours[channel]).is_equal(
			LookCatalog.presets()[USHER]["colours"][channel]
		)


func test_a_costume_of_the_other_character_changes_the_character() -> void:
	var screen := await _open(55)
	await _show(screen, &"costumes")
	await _click(screen, screen.costume_cell(9))
	assert_str(String(screen.look.body())).is_equal("female")
	assert_bool(screen.cell("part:body", 1).worn).is_true()
	assert_bool(screen.look.equals(CharacterLook.from_preset(9))).is_true()


func test_the_keyboard_wears_a_costume_with_accept() -> void:
	var screen := await _open(55)
	await _show(screen, &"costumes")
	UIInputMode.pointer = false
	var cell := screen.costume_cell(MECHANIC)
	screen.reveal(cell)
	cell.grab_focus()
	assert_str(screen.detail_text()).is_equal("Mechanic - press to wear it in its own colours")
	await _key(KEY_ENTER)
	assert_bool(screen.look.equals(CharacterLook.from_preset(MECHANIC))).is_true()
	assert_bool(cell.worn).is_true()


func test_the_gamepad_walks_down_from_the_tab_and_wears_with_a_without_changing_the_page() -> void:
	var screen := await _open(55)
	await _show(screen, &"costumes")
	UIInputMode.pointer = false
	var tab := screen.tab_button(&"costumes")
	tab.grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var first := screen.cells(CustomizeScreen.COSTUME_KEY)[0]
	assert_object(get_viewport().gui_get_focus_owner()).is_same(first)
	await _pad(JOY_BUTTON_A)
	assert_bool(screen.look.equals(CharacterLook.from_preset(first.index))).is_true()
	# Along the grid, then back up to the tab on show; walking the strip does not change the page.
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		screen.cells(CustomizeScreen.COSTUME_KEY)[1]
	)
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(tab)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.tab_button(&"body"))
	assert_str(String(screen.current_tab())).is_equal("costumes")
	await _pad(JOY_BUTTON_A)
	assert_str(String(screen.current_tab())).is_equal("body")


func test_a_costume_the_player_does_not_own_is_read_by_hover_and_focus_and_never_worn() -> void:
	var screen := await _open(12)
	await _show(screen, &"costumes")
	var usher := screen.costume_cell(USHER)
	assert_bool(usher.locked).is_true()
	var before := screen.look.duplicate_look()
	var refused: Array[bool] = []
	usher.refused.connect(func() -> void: refused.append(true))
	# The pointer reads how to get it ...
	await _point_at(usher)
	assert_str(screen.detail_text()).is_equal("??? - Reach level 20 (you are level 12)")
	# ... and so does the focus alone ...
	UIInputMode.pointer = false
	screen.costume_cell(CARHOP).grab_focus()
	assert_str(screen.detail_text()).starts_with("Carhop")
	usher.grab_focus()
	assert_str(screen.detail_text()).is_equal("??? - Reach level 20 (you are level 12)")
	# ... and a click, a key and a pad press change nothing.
	await _click(screen, usher)
	usher.grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_SPACE)
	await _pad(JOY_BUTTON_A)
	assert_bool(screen.look.equals(before)).is_true()
	assert_bool(usher.worn).is_false()
	assert_int(refused.size()).is_greater_equal(3)
	assert_bool(screen.wear_costume(USHER)).is_false()
	# The turntable shows what the look has, not the costume: there is no fitting room.
	var pillbox := screen.preview().model.find_child("headwear__pillbox", true, false) as Node3D
	assert_bool(pillbox == null or not pillbox.visible).is_true()


func test_a_costume_that_needs_two_levels_names_the_last_piece_to_reach() -> void:
	# Level 7 has the Usher's cap (6) but not the jacket (8) nor the striped trousers (20).
	var screen := await _open(7)
	assert_str(screen.costume_cell(USHER).instructions).is_equal("Reach level 20 (you are level 7)")
	var lifeguard := screen.costume_cell(3)
	assert_str(lifeguard.instructions).is_equal("Reach level 16 (you are level 7)")


func test_the_body_tab_has_no_preset_row_now_that_costumes_have_a_tab() -> void:
	var screen := await _open(55)
	for tab: Dictionary in CustomizeScreen.TABS:
		for section: Dictionary in tab["sections"]:
			assert_bool(section.has("presets")).is_false()
	assert_array(screen.find_children("*", "UIOptionSelector", true, false)).is_empty()


func test_default_gives_the_costume_its_own_colours_back_after_a_click_on_the_colours_tab() -> void:
	var screen := await _open(55)
	await _show(screen, &"costumes")
	await _click(screen, screen.costume_cell(MECHANIC))
	var default := screen.default_cell()
	assert_bool(default.is_off()).is_false()
	assert_bool(default.worn).is_true()
	var own := screen.look.duplicate_look()
	# The player's own colours: three clicks on the Colours tab.
	await _show(screen, &"colours")
	var red := _colour_index(&"primary", &"red")
	var cream := _colour_index(&"secondary", &"cream")
	var grey := _colour_index(&"accent", &"grey")
	for pair: Array in [[&"primary", red], [&"secondary", cream], [&"accent", grey]]:
		await _click(screen, screen.cell("colour:" + pair[0], pair[1]))
		assert_int(screen.look.colours[pair[0]]).is_equal(pair[1])
	assert_bool(default.worn).is_false()
	assert_bool(screen.look.equals(own)).is_false()
	# Default is the first thing on the tab; a real click restores the costume's colours.
	await _click(screen, default)
	assert_bool(screen.look.equals(own)).is_true()
	assert_bool(default.worn).is_true()
	assert_bool(screen.cell("colour:primary", own.colours[&"primary"]).worn).is_true()
	assert_str(screen.detail_text()).is_equal("Default - wearing")
	# It never touches the pieces, the skin or the hair.
	screen.choose("colour:skin", 5)
	await _click(screen, default)
	assert_int(screen.look.colours[&"skin"]).is_equal(5)


func test_default_is_off_until_a_costume_is_on_the_character_and_says_so() -> void:
	var screen := await _open(55)
	await _show(screen, &"colours")
	# The saved look is the Greaser, so a costume is on: change a piece to take it off.
	var default := screen.default_cell()
	assert_bool(default.is_off()).is_false()
	screen.choose("part:torso", LookCatalog.option_index(&"torso", &"vest"))
	assert_bool(default.is_off()).is_true()
	assert_bool(screen.use_default_colours()).is_false()
	var before := screen.look.duplicate_look()
	await _click(screen, default)
	assert_bool(screen.look.equals(before)).is_true()
	assert_str(screen.detail_text()).is_equal("Default - %s" % CustomizeScreen.NO_COSTUME_NOTE)
	assert_str(default.accessibility_name).contains("wear a costume")
	# Wearing a costume again turns it back on.
	await _show(screen, &"costumes")
	await _click(screen, screen.costume_cell(0))
	assert_bool(default.is_off()).is_false()


func test_the_colours_tab_pad_walk_goes_from_the_tab_to_default_and_back() -> void:
	var screen := await _open(55)
	await _show(screen, &"colours")
	UIInputMode.pointer = false
	var tab := screen.tab_button(&"colours")
	tab.grab_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.default_cell())
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(tab)


func test_an_owned_costumes_locked_colours_are_kept_whole_and_the_palette_decides_once_one_changes(
) -> void:
	# The Usher at level 20: its gold trim asks level 42, the player has the costume.
	var screen := await _open(20)
	await _show(screen, &"costumes")
	await _click(screen, screen.costume_cell(USHER))
	var gold := _colour_index(&"accent", &"gold")
	assert_int(screen.look.colours[&"accent"]).is_equal(gold)
	# The cell of gold is not a padlock while it is worn as part of the Default.
	await _show(screen, &"colours")
	var gold_cell := screen.cell("colour:accent", gold)
	assert_bool(gold_cell.worn).is_true()
	assert_bool(gold_cell.locked).is_false()
	# It is kept when saved and read back.
	screen.save()
	var back := LookStore.load_look(screen.unlocks)
	assert_int(back.colours[&"accent"]).is_equal(gold)
	# A colour of the player's own on the main colour: the gold is not theirs on its own.
	await _click(screen, screen.cell("colour:primary", _colour_index(&"primary", &"red")))
	assert_int(screen.look.colours[&"accent"]).is_not_equal(gold)
	assert_bool(gold_cell.locked).is_true()
	assert_bool(screen.default_cell().worn).is_false()
	# And Default brings the whole costume back, gold and all.
	await _click(screen, screen.default_cell())
	assert_int(screen.look.colours[&"accent"]).is_equal(gold)
	assert_bool(gold_cell.locked).is_false()
