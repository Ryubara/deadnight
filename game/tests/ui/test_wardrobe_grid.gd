extends GdUnitTestSuite
## The wardrobe's grid (#1065), driven the way a player drives it: what is lit and what is a
## silhouette at level 1, 12 and 55 on every tab, `???` and the unlock instructions under a real
## pointer and under the focus alone, a locked item that cannot be worn (no fitting room), and a
## real click that does wear a lit one.

const SCREEN := "res://ui/screens/customize_screen.tscn"
const TEST_PATH := "user://wardrobe_grid_test.cfg"
const LEVELS: Array[int] = [1, 12, 55]
## The tabs whose items carry the ladder; the others are free and carry no lock mark.
const LADDER_TABS: Array[StringName] = [
	&"headwear", &"torso", &"legs", &"feet", &"eyewear", &"neck", &"colours"
]
const FREE_TABS: Array[StringName] = [&"body", &"hair"]

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


## A real pointer motion to the middle of `control`.
func _point_at(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame


func _click(control: Control) -> void:
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


func _keys_of(tab: StringName) -> Array[String]:
	var out: Array[String] = []
	for tab_def: Dictionary in CustomizeScreen.TABS:
		if tab_def["key"] != tab:
			continue
		for section: Dictionary in tab_def["sections"]:
			if section.has("part"):
				out.append(CustomizeScreen.PART_PREFIX + section["part"])
			elif section.has("colour"):
				out.append(CustomizeScreen.COLOUR_PREFIX + section["colour"])
	return out


func test_each_tab_at_each_level_lights_what_the_level_opens_and_blanks_the_rest() -> void:
	for level in LEVELS:
		var screen := await _open(level)
		for tab: StringName in LADDER_TABS:
			screen.show_tab(tab)
			for key in _keys_of(tab):
				for item in screen.cells(key):
					var gate := _gate_of(item)
					var wanted := LookUnlocks.level_of(gate) > level
					(
						assert_bool(item.locked)
						. override_failure_message(
							"%s at level %d: locked should be %s" % [item.id, level, wanted]
						)
						. is_equal(wanted)
					)
					if item.locked:
						assert_str(item.shown_name()).is_equal("???")
						assert_str(item.instructions).is_equal(
							(
								"Reach level %d (you are level %d)"
								% [LookUnlocks.level_of(gate), level]
							)
						)
					else:
						assert_str(item.shown_name()).is_equal(item.title)
						assert_str(item.shown_name()).is_not_equal("???")
		# At 55 nothing is locked, anywhere.
		if level == LevelCurve.MAX_LEVEL:
			for key: String in screen._cells:
				for item in screen.cells(key):
					assert_bool(item.locked).is_false()
		screen.queue_free()
		await get_tree().process_frame


func _gate_of(item: WardrobeCell) -> Dictionary:
	if item.kind == WardrobeCell.Kind.COLOUR:
		return LookCatalog.palette(item.slot)[item.index]["gate"]
	if item.index >= 0:
		return LookCatalog.options(item.slot)[item.index]["gate"]
	for waiting: Dictionary in LookCatalog.pending(item.slot):
		if waiting["id"] == item.id:
			return waiting["gate"]
	return {}


func test_the_free_tabs_carry_no_lock_mark_at_level_one() -> void:
	var screen := await _open(1)
	for tab: StringName in FREE_TABS:
		screen.show_tab(tab)
		for key in _keys_of(tab):
			for item in screen.cells(key):
				(
					assert_bool(item.locked)
					. override_failure_message("%s on the %s tab is locked" % [item.id, tab])
					. is_false()
				)
				assert_bool(item.soon).is_false()
	# The armband beside the neckwear is free too, and "None" of every slot that has one.
	for item in screen.cells("part:arm"):
		assert_bool(item.locked).is_false()
	for slot: StringName in [&"headwear", &"eyewear", &"neck"]:
		assert_bool(screen.cell_of(slot, &"none").locked).is_false()


func test_a_locked_cell_shows_its_name_as_question_marks_and_the_pointer_reads_how_to_get_it(
) -> void:
	var screen := await _open(12)
	screen.show_tab(&"torso")
	await get_tree().process_frame
	var locked := screen.first_locked_cell()
	assert_object(locked).is_not_null()
	assert_str(locked.shown_name()).is_equal("???")
	await _point_at(locked)
	assert_str(screen.detail_text()).is_equal("??? - Reach level 16 (you are level 12)")
	# The pointer on a lit cell reads its own name instead, and leaving reads the rest line.
	var lit := screen.cell_of(&"torso", &"jacket")
	await _point_at(lit)
	assert_str(screen.detail_text()).is_equal("Jacket - wearing")
	var other := screen.cell_of(&"torso", &"shirt")
	await _point_at(other)
	assert_str(screen.detail_text()).is_equal("Short sleeves - press to wear")
	var nowhere := InputEventMouseMotion.new()
	nowhere.position = Vector2(2.0, 2.0)
	nowhere.global_position = nowhere.position
	get_viewport().push_input(nowhere, true)
	await get_tree().process_frame
	assert_str(screen.detail_text()).is_equal(CustomizeScreen.REST_HINT)


func test_the_focus_alone_reads_the_same_words_as_the_pointer() -> void:
	var screen := await _open(12)
	UIInputMode.pointer = false
	for tab: StringName in LADDER_TABS:
		screen.show_tab(tab)
		await get_tree().process_frame
		var locked := screen.first_locked_cell()
		if locked == null:
			continue
		locked.grab_focus()
		var need := LookUnlocks.level_of(_gate_of(locked))
		assert_str(screen.detail_text()).is_equal("??? - Reach level %d (you are level 12)" % need)
		var lit := screen.cells(_keys_of(tab)[0])[0]
		lit.grab_focus()
		assert_str(screen.detail_text()).contains(lit.title)
		assert_str(screen.detail_text()).not_contains("???")


func test_a_locked_item_is_never_worn_not_by_a_click_a_key_or_a_pad() -> void:
	var screen := await _open(1)
	screen.show_tab(&"headwear")
	await get_tree().process_frame
	var locked := screen.cell_of(&"headwear", &"helmet")
	var before := screen.look.duplicate_look()
	var refused: Array[bool] = []
	locked.refused.connect(func() -> void: refused.append(true))
	await _click(locked)
	assert_bool(screen.look.equals(before)).is_true()
	locked.grab_focus()
	UIInputMode.pointer = false
	for press in [KEY_ENTER, KEY_SPACE]:
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.keycode = press
			key.physical_keycode = press
			key.pressed = pressed
			get_viewport().push_input(key)
			await get_tree().process_frame
	for pressed in [true, false]:
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_A
		pad.pressed = pressed
		get_viewport().push_input(pad)
		await get_tree().process_frame
	assert_bool(screen.look.equals(before)).is_true()
	assert_bool(refused.size() >= 3).is_true()
	assert_bool(locked.worn).is_false()
	# The turntable shows what the look has, not the locked piece: there is no fitting room.
	var model := screen.preview().model
	var helmet := model.find_child("headwear__helmet", true, false) as Node3D
	assert_bool(helmet == null or not helmet.visible).is_true()
	assert_str(screen.detail_text()).starts_with("???")


func test_a_click_on_a_lit_wearable_puts_it_on_the_soldier() -> void:
	var screen := await _open(1)
	screen.show_tab(&"headwear")
	await get_tree().process_frame
	var cap := screen.cell_of(&"headwear", &"ballcap")
	assert_bool(cap.locked).is_false()
	await _click(cap)
	assert_str(String(screen.look.parts[&"headwear"])).is_equal("ballcap")
	assert_bool(cap.worn).is_true()
	(
		assert_bool(screen.preview().model.find_child("headwear__ballcap", true, false).visible)
		. is_true()
	)
	assert_bool(screen.is_dirty()).is_true()
	# And "None" takes it off again.
	await _click(screen.cell_of(&"headwear", &"none"))
	assert_str(String(screen.look.parts[&"headwear"])).is_equal("none")
	assert_bool(cap.worn).is_false()


func test_the_grid_runs_the_ladder_from_the_starting_pieces_upward() -> void:
	var screen := await _open(1)
	for key in ["part:torso", "part:headwear", "part:feet", "colour:primary"]:
		var last := 0
		for item in screen.cells(key):
			var need := LookUnlocks.level_of(_gate_of(item))
			assert_int(need).override_failure_message("%s out of order" % item.id).is_greater_equal(
				last
			)
			last = need
	# Two lit wearables to start with besides "None", then the locked ones.
	var lit := screen.cells("part:feet").filter(func(c: WardrobeCell) -> bool: return not c.locked)
	assert_int(lit.size()).is_equal(2)


func test_a_piece_with_no_model_yet_is_only_its_icon_and_cannot_be_worn() -> void:
	var waiting := LookCatalog.pending(&"feet")
	if waiting.is_empty():
		return
	var screen := await _open(LevelCurve.MAX_LEVEL)
	screen.show_tab(&"feet")
	await get_tree().process_frame
	var item := screen.cell_of(&"feet", waiting[0]["id"])
	assert_object(item).is_not_null()
	assert_bool(item.locked).is_false()
	assert_bool(item.soon).is_true()
	assert_int(item.index).is_equal(-1)
	var before := screen.look.duplicate_look()
	await _click(item)
	assert_bool(screen.look.equals(before)).is_true()
	assert_str(screen.detail_text()).contains("not drawn yet")
	# Below its level it is a silhouette like any other.
	var low := await _open(1)
	var shut := low.cell_of(&"feet", waiting[0]["id"])
	assert_bool(shut.locked).is_true()
	assert_str(shut.shown_name()).is_equal("???")


func test_a_cell_names_itself_to_a_screen_reader_without_giving_away_a_locked_name() -> void:
	var screen := await _open(1)
	var shut := screen.cell_of(&"torso", &"jacket")
	assert_bool(shut.locked).is_true()
	assert_str(shut.accessibility_name).is_equal("Locked item, Reach level 8 (you are level 1)")
	var open := screen.cell_of(&"torso", &"vest")
	assert_str(open.accessibility_name).starts_with(open.title)


func test_the_phone_layout_keeps_every_cell_and_tab_a_tap_target() -> void:
	var screen := await _open(12, {"embedded": true, "compact": true})
	for key: String in screen._cells:
		for item in screen.cells(key):
			assert_bool(item.compact).is_true()
			assert_float(item.custom_minimum_size.x).is_greater_equal(MenuLook.TAP_TARGET)
			assert_float(item.custom_minimum_size.y).is_greater_equal(MenuLook.TAP_TARGET)
	for tab: StringName in screen.tab_keys():
		assert_float(screen.tab_button(tab).custom_minimum_size.y).is_greater_equal(
			MenuLook.TAP_TARGET
		)
