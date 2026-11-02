# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## The main menu's tab shell with real input from every device: keys, the pad's bumpers and
## D-pad, mouse clicks and a tap, and each panel showing what the save and the challenge board
## hold. The stage behind it is the real one, stepped by hand.

const TEST_PATH := "user://menu_shell_test.cfg"

var _saved_path: String
var _window_before: Vector2i
var _board: FakeChallengeBoard
var _actions: Array[StringName] = []


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	UIInputMode.reset()
	_actions.clear()
	_window_before = get_window().size
	get_window().size = Vector2i(1920, 1080)


func after_test() -> void:
	get_window().size = _window_before
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	UIMotion.reduced = false
	UIInputMode.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	await RouterFixture.clear(get_tree())


func _open(phone := false, profile_text := "") -> MenuShell:
	_board = FakeChallengeBoard.new()
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 1 if phone else 0
	shell.context.board = _board
	shell.context.profile = MenuProfile.from_json(
		(
			profile_text
			if profile_text != ""
			else MenuProfile.to_json("Ann", MenuProfile.xp_at(7) + 90, 1250, {"rifle": 900})
		)
	)
	shell.context.action.connect(func(id: StringName) -> void: _actions.append(id))
	# On a layer of its own, above the test runner's controls, so a click reaches it.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	auto_free(layer)
	layer.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	return shell


func _key(code: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _pad(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _tap(event: InputEvent) -> void:
	get_viewport().push_input(event)
	await get_tree().process_frame


func _click(control: Control, touch := false) -> void:
	var at := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		if touch:
			click.device = InputEvent.DEVICE_ID_EMULATION
		get_viewport().push_input(click, true)
		await get_tree().process_frame


# ---------------------------------------------------------------- tab navigation per device


func test_the_shell_has_five_tabs_and_starts_on_play() -> void:
	var shell := await _open()
	assert_int(shell.tab).is_equal(MenuTab.Id.PLAY)
	for id in MenuTab.ORDER:
		assert_object(shell.panel(id)).is_not_null()
		assert_bool(shell.tab_bar.button(id).is_visible_in_tree()).is_true()
	assert_bool(shell.panel(MenuTab.Id.PLAY).visible).is_true()
	assert_bool(shell.panel(MenuTab.Id.SHOP).visible).is_false()


func test_the_keyboard_walks_the_tabs_both_ways_and_round() -> void:
	var shell := await _open()
	for expected in [
		MenuTab.Id.LOADOUT, MenuTab.Id.SHOP, MenuTab.Id.CHALLENGES, MenuTab.Id.MORE, MenuTab.Id.PLAY
	]:
		await _tap(_key(KEY_E))
		assert_int(shell.tab).is_equal(expected)
		assert_bool(shell.panel(expected).visible).is_true()
	await _tap(_key(KEY_Q))
	assert_int(shell.tab).is_equal(MenuTab.Id.MORE)


func test_the_bumpers_walk_the_tabs() -> void:
	var shell := await _open()
	UIInputMode.gamepad = true
	UIInputMode.pointer = false
	await _tap(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	await _tap(_pad(JOY_BUTTON_RIGHT_SHOULDER, false))
	assert_int(shell.tab).is_equal(MenuTab.Id.LOADOUT)
	await _tap(_pad(JOY_BUTTON_LEFT_SHOULDER))
	await _tap(_pad(JOY_BUTTON_LEFT_SHOULDER, false))
	assert_int(shell.tab).is_equal(MenuTab.Id.PLAY)
	await _tap(_pad(JOY_BUTTON_LEFT_SHOULDER))
	assert_int(shell.tab).is_equal(MenuTab.Id.MORE)


func test_a_bumper_puts_the_focus_in_the_new_panel() -> void:
	var shell := await _open()
	await _tap(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	var focused := get_viewport().gui_get_focus_owner()
	assert_object(focused).is_not_null()
	assert_bool(shell.panel(MenuTab.Id.LOADOUT).is_ancestor_of(focused)).is_true()


func test_the_dpad_and_a_walk_the_tab_bar() -> void:
	var shell := await _open()
	shell.tab_bar.button(MenuTab.Id.PLAY).grab_focus()
	await _tap(_pad(JOY_BUTTON_DPAD_RIGHT))
	await _tap(_pad(JOY_BUTTON_DPAD_RIGHT, false))
	assert_object(get_viewport().gui_get_focus_owner()).is_equal(
		shell.tab_bar.button(MenuTab.Id.LOADOUT)
	)
	await _tap(_pad(JOY_BUTTON_A))
	await _tap(_pad(JOY_BUTTON_A, false))
	assert_int(shell.tab).is_equal(MenuTab.Id.LOADOUT)


func test_a_click_on_a_tab_opens_it() -> void:
	var shell := await _open()
	await _click(shell.tab_bar.button(MenuTab.Id.CHALLENGES))
	assert_int(shell.tab).is_equal(MenuTab.Id.CHALLENGES)
	assert_bool(shell.panel(MenuTab.Id.CHALLENGES).visible).is_true()
	assert_bool(shell.panel(MenuTab.Id.PLAY).visible).is_false()


func test_a_tap_on_a_tab_opens_it_and_hides_the_key_hints() -> void:
	var shell := await _open()
	UIInputMode.touch = true
	UIInputMode.pointer = true
	await _click(shell.tab_bar.button(MenuTab.Id.SHOP), true)
	assert_int(shell.tab).is_equal(MenuTab.Id.SHOP)
	await get_tree().process_frame
	assert_bool(shell.hints.visible).is_false()


func test_the_hints_follow_the_device() -> void:
	var shell := await _open()
	assert_int(shell.hints.kind).is_equal(MenuHints.Kind.KEYS)
	UIInputMode.gamepad = true
	UIInputMode.pointer = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(shell.hints.kind).is_equal(MenuHints.Kind.PAD)
	assert_str(shell.hints.pairs()[2][0]).is_equal("LB RB")
	UIInputMode.touch = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(shell.hints.kind).is_equal(MenuHints.Kind.NONE)


func test_the_stage_camera_follows_the_tab() -> void:
	var shell := await _open()
	for id in MenuTab.ORDER:
		shell.show_tab(id)
		assert_int(shell.view.stage.rig.tab).is_equal(id)


func test_the_menu_never_captures_the_pointer() -> void:
	var shell := await _open()
	for id in MenuTab.ORDER:
		shell.show_tab(id)
		assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_int(shell.view.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_back_from_a_panel_goes_to_the_tab_bar() -> void:
	var shell := await _open()
	await _tap(_key(KEY_E))
	await _tap(_key(KEY_E))
	assert_int(shell.tab).is_equal(MenuTab.Id.SHOP)
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await _tap(_key(KEY_ESCAPE))
	assert_object(get_viewport().gui_get_focus_owner()).is_equal(
		shell.tab_bar.button(MenuTab.Id.SHOP)
	)


# ---------------------------------------------------------------- panels show the save


func test_the_plate_shows_the_profile() -> void:
	var shell := await _open()
	assert_str(shell.plate.name_text()).is_equal("ANN")
	assert_str(shell.plate.level_text()).is_equal("BILLING 7")
	assert_str(shell.plate.stubs_text()).is_equal("1,250 STUBS")
	assert_float(shell.plate.level_fraction()).is_equal_approx(
		90.0 / MenuProfile.xp_to_next(7), 0.0001
	)


func test_the_play_panel_shows_todays_dailies_and_asks_for_the_three_routes() -> void:
	var shell := await _open()
	var panel := shell.panel(MenuTab.Id.PLAY) as PlayPanel
	var rows := panel.rows()
	var dailies := _board.dailies()
	assert_int(rows.size()).is_equal(PlayPanel.DAILIES_SHOWN)
	for index in rows.size():
		assert_str(rows[index].text()).is_equal(dailies[index]["text"])
		assert_str(rows[index].count_text()).is_equal(
			MenuNav.fraction_text(dailies[index]["progress"], dailies[index]["target"])
		)
	for id in [&"together", &"quick_join", &"solo"]:
		panel.button(id).pressed.emit()
	assert_array(_actions).is_equal([&"together", &"quick_join", &"solo"])


func test_the_loadout_panel_shows_the_saved_look_weapon_and_mastery() -> void:
	var look := CharacterLook.from_preset(3)
	LookStore.save_look(look)
	Settings.set_value(SettingsService.SHOWCASE_WEAPON, "shotgun")
	var shell := await _open()
	shell.show_tab(MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	assert_str(String(panel.weapons()[panel.selector().selected])).is_equal("shotgun")
	assert_bool(panel.wardrobe.look.equals(look)).is_true()
	assert_str(panel.mastery_text()).starts_with("Mastery 1 of 10")
	panel.selector().select(panel.weapons().find(&"rifle"))
	# Held while the tab is open; the file changes when the player leaves (test_loadout_keeps_choices).
	assert_str(String(Settings.get_value(SettingsService.SHOWCASE_WEAPON))).is_equal("shotgun")
	assert_str(panel.mastery_text()).starts_with("Mastery 2 of 10")
	shell.show_tab(MenuTab.Id.PLAY)
	assert_str(String(Settings.get_value(SettingsService.SHOWCASE_WEAPON))).is_equal("rifle")


func test_a_change_in_the_wardrobe_shows_on_the_stage_and_leaving_keeps_it() -> void:
	LookStore.save_look(CharacterLook.from_preset(1))
	var shell := await _open()
	shell.show_tab(MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	panel.wardrobe.apply_preset(5)
	assert_bool(shell.view.stage.hero.look.equals(CharacterLook.from_preset(5))).is_true()
	shell.show_tab(MenuTab.Id.PLAY)
	assert_bool(shell.view.stage.hero.look.equals(CharacterLook.from_preset(5))).is_true()
	assert_bool(LookStore.load_look().equals(CharacterLook.from_preset(5))).is_true()


func test_leaving_the_loadout_tab_writes_the_look_the_stage_then_keeps() -> void:
	var shell := await _open()
	shell.show_tab(MenuTab.Id.LOADOUT)
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	panel.wardrobe.apply_preset(4)
	shell.show_tab(MenuTab.Id.PLAY)
	assert_bool(LookStore.load_look().equals(CharacterLook.from_preset(4))).is_true()
	assert_bool(shell.view.stage.hero.look.equals(CharacterLook.from_preset(4))).is_true()


func test_the_shop_shows_the_balance_the_gated_items_and_marked_placeholders() -> void:
	var shell := await _open()
	shell.show_tab(MenuTab.Id.SHOP)
	var panel := shell.panel(MenuTab.Id.SHOP) as ShopPanel
	assert_str(panel.balance_text()).is_equal("You have 1,250 stubs")
	var rows := panel.rows()
	assert_int(rows.size()).is_equal(LookCatalog.PALETTE_GATES.size() + ShopPanel.CATEGORIES.size())
	var real := 0
	for row in rows:
		if not row.placeholder:
			real += 1
		else:
			assert_str(row.note).is_equal("Coming")
	assert_int(real).is_equal(LookCatalog.PALETTE_GATES.size())
	# Billing 7 has not reached the level-10 colour; it asks for it by name.
	assert_str(rows[0].note).is_equal("Billing 10")


func test_the_challenges_panel_shows_dailies_orders_and_milestones_and_filters_by_family() -> void:
	var shell := await _open()
	shell.show_tab(MenuTab.Id.CHALLENGES)
	var panel := shell.panel(MenuTab.Id.CHALLENGES) as ChallengesPanel
	var all := panel.rows()
	assert_int(all.size()).is_equal(3 + 3 + 4)
	assert_str(all[0].count_text()).is_equal("3/5")
	assert_str(all[5].count_text()).is_equal("1,850/3,000")
	panel.show_family(ChallengesPanel.Family.ORDER)
	assert_int(panel.rows().size()).is_equal(3)
	panel.show_family(ChallengesPanel.Family.MILESTONE)
	assert_int(panel.rows().size()).is_equal(4)
	assert_str(panel.rows()[0].count_text()).is_equal("23/50")
	panel.show_family(ChallengesPanel.Family.DAILY)
	assert_array(ChallengeRow.tags_of(panel.rows()[2].entry)).is_equal(PackedStringArray(["Short"]))
	assert_int(panel.rows()[1].punched()).is_equal(7)


func test_pressing_an_order_swaps_it() -> void:
	var shell := await _open()
	shell.show_tab(MenuTab.Id.CHALLENGES)
	var panel := shell.panel(MenuTab.Id.CHALLENGES) as ChallengesPanel
	panel.show_family(ChallengesPanel.Family.ORDER)
	panel.rows()[1].pressed.emit()
	assert_array(_board.swaps).is_equal([1])


func test_the_more_panel_has_settings_credits_and_quit_and_asks_for_them() -> void:
	var shell := await _open()
	shell.show_tab(MenuTab.Id.MORE)
	var panel := shell.panel(MenuTab.Id.MORE) as MorePanel
	for id in [&"settings", &"credits"]:
		panel.button(id).pressed.emit()
	if MainMenu.has_quit():
		panel.button(&"quit").pressed.emit()
	assert_bool(_actions.has(&"settings") and _actions.has(&"credits")).is_true()
	assert_bool(MainMenu.has_quit(true)).is_false()


func test_an_empty_profile_is_a_new_player_everywhere() -> void:
	var shell := await _open(false, "{}")
	assert_str(shell.plate.level_text()).is_equal("BILLING 1")
	assert_str(shell.plate.stubs_text()).is_equal("0 STUBS")
	shell.show_tab(MenuTab.Id.SHOP)
	assert_str((shell.panel(MenuTab.Id.SHOP) as ShopPanel).balance_text()).is_equal(
		"You have 0 stubs"
	)


# ---------------------------------------------------------------- phone and reduced motion


func test_on_a_phone_the_type_and_the_targets_meet_the_written_minimums() -> void:
	var shell := await _open(true)
	var per_unit := MenuScale.pixels_per_unit(Vector2i(844, 390), MenuScale.PHONE_FACTOR)
	assert_float(per_unit).is_equal_approx(0.7222, 0.001)
	assert_bool(shell.is_compact()).is_true()
	for id in MenuTab.ORDER:
		shell.show_tab(id)
		await get_tree().process_frame
		for node in shell.find_children("*", "Label", true, false):
			var label := node as Label
			if not label.is_visible_in_tree() or label.text == "":
				continue
			var size := label.get_theme_font_size(&"font_size")
			(
				assert_float(size * per_unit)
				. override_failure_message(
					"'%s' is %.1f px on a phone" % [label.text, size * per_unit]
				)
				. is_greater_equal(14.0)
			)
		for node in shell.panel(id).find_children("*", "Control", true, false):
			var control := node as Control
			var pressable := (
				control is MenuItemButton
				or control is ChallengesPanel.FamilyChip
				or control is UIOptionSelector
				or control is UIButton
			)
			if pressable and control.is_visible_in_tree():
				(
					assert_float(control.custom_minimum_size.y * per_unit)
					. override_failure_message(
						(
							"%s %s is %.1f px tall"
							% [id, control.name, control.custom_minimum_size.y * per_unit]
						)
					)
					. is_greater_equal(43.5)
				)
		for button in [shell.tab_bar.button(id)]:
			assert_float(button.custom_minimum_size.y * per_unit).is_greater_equal(43.5)


func test_a_phone_shows_two_dailies_and_no_subtitles() -> void:
	var shell := await _open(true)
	var panel := shell.panel(MenuTab.Id.PLAY) as PlayPanel
	assert_int(panel.rows().size()).is_equal(PlayPanel.DAILIES_SHOWN_COMPACT)
	assert_str(panel.button(&"solo").subtitle).is_equal("")


func test_every_panel_fits_inside_every_canvas() -> void:
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		get_window().size = size
		var shell := await _open()
		var rect := Rect2(Vector2.ZERO, MenuScale.DESIGN)
		for id in MenuTab.ORDER:
			shell.show_tab(id, false)
			await get_tree().process_frame
			var panel := shell.panel(id)
			var panel_rect := panel.get_global_rect()
			(
				assert_bool(rect.encloses(panel_rect))
				. override_failure_message(
					"%s panel %s is outside the picture %s" % [id, panel_rect, rect]
				)
				. is_true()
			)
			# No tab overlaps the panel's column.
			assert_bool(shell.tab_bar.get_global_rect().intersects(panel_rect)).is_false()


func test_reduced_motion_shows_a_panel_at_once() -> void:
	UIMotion.reduced = true
	var shell := await _open()
	shell.show_tab(MenuTab.Id.CHALLENGES)
	assert_float(shell.panel(MenuTab.Id.CHALLENGES).modulate.a).is_equal(1.0)
	assert_bool(shell.view.stage.rig.arrived()).is_true()


# ---------------------------------------------------------------- numbers never clip


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x - 0.5
		and inner.end.x <= outer.end.x + 0.5
		and inner.position.y >= outer.position.y - 0.5
		and inner.end.y <= outer.end.y + 0.5
	)


func test_the_longest_count_fits_its_row_on_every_panel_and_canvas() -> void:
	for phone in [false, true]:
		var shell := await _open(phone)
		_board.extreme = true
		for id in [MenuTab.Id.PLAY, MenuTab.Id.CHALLENGES]:
			shell.show_tab(id, false)
			var panel := shell.panel(id)
			panel.refresh()
			if id == MenuTab.Id.CHALLENGES:
				(panel as ChallengesPanel).show_family(ChallengesPanel.Family.ALL)
			await get_tree().process_frame
			await get_tree().process_frame
			var rows: Array[ChallengeRow] = []
			rows.assign(panel.find_children("*", "ChallengeRow", true, false))
			assert_int(rows.size()).is_greater(0)
			var widest := 0
			for row in rows:
				var count := row.count_label()
				widest = maxi(widest, count.text.length())
				(
					assert_bool(_inside(count.get_global_rect(), row.get_global_rect()))
					. override_failure_message(
						(
							"phone %s %s: '%s' is %s, its row is %s"
							% [
								phone,
								id,
								count.text,
								count.get_global_rect(),
								row.get_global_rect()
							]
						)
					)
					. is_true()
				)
				# The count has all the room it needs: its box is as wide as its text.
				assert_float(count.size.x).is_greater_equal(count.get_minimum_size().x - 0.5)
			assert_int(widest).is_greater_equal("1,000,000/1,000,000".length())
		# The widest count is the longest value a goal can carry: 380 units or less.
		var font := UITokens.active().font_display
		var width := (
			font
			. get_string_size(
				"1,000,000/1,000,000", HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_NUMBER
			)
			. x
		)
		assert_float(width).is_less(400.0)


func test_a_menu_under_another_screen_does_not_answer_the_bumpers() -> void:
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	UIRouter.push("res://ui/screens/credits_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	await _tap(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	assert_int(menu.shell.tab).is_equal(MenuTab.Id.PLAY)
	UIRouter.pop()
	await UIRouter.idle
	await _tap(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	assert_int(menu.shell.tab).is_equal(MenuTab.Id.LOADOUT)
