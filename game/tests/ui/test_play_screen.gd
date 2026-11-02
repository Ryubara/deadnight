# The Play screen: the match settings as gds_ui controls, moved with the keyboard the way a player
# moves them, and Start opens a night that runs under exactly those settings (#414).
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const PLAY := "res://ui/screens/play_screen.tscn"
const WINDOW := Vector2(1280.0, 720.0)


func after_test() -> void:
	NightScreen.match_settings = null
	await RouterFixture.clear(get_tree())


func _open_play() -> PlayScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(PLAY, UITransition.Kind.CUT)
	await UIRouter.idle
	await get_tree().process_frame
	return UIRouter.top() as PlayScreen


func _tap(action: StringName, times: int = 1) -> void:
	for _i in times:
		for pressed in [true, false]:
			var event := InputEventAction.new()
			event.action = action
			event.pressed = pressed
			Input.parse_input_event(event)
			await get_tree().process_frame


func test_the_screen_opens_on_the_usual_rules() -> void:
	var screen := await _open_play()
	assert_bool(screen.panel.settings().is_default()).is_true()
	assert_str(screen.panel.count_selector.text()).is_equal("1x")
	assert_str(MatchSettingsPanel.alive_text(0)).is_equal("Auto")
	assert_str(MatchSettingsPanel.limit_text(0.0)).is_equal("Off")
	assert_str(MatchSettingsPanel.limit_text(90.0)).is_equal("1:30")
	assert_str(MatchSettingsPanel.limit_text(120.0)).is_equal("2 min")
	assert_str(MatchSettingsPanel.limit_text(30.0)).is_equal("30 s")


func test_the_panel_hands_back_what_it_was_given() -> void:
	var screen := await _open_play()
	var wanted := MatchSettings.new()
	wanted.count_multiplier = 3.0
	wanted.max_alive = 9
	wanted.break_seconds = 11.0
	wanted.round_time_limit = 90.0
	screen.panel.set_settings(wanted)
	assert_bool(screen.panel.settings().same_as(wanted)).is_true()
	screen.panel.set_settings(MatchSettings.new())
	assert_bool(screen.panel.settings().is_default()).is_true()


func test_the_break_follows_the_tuned_one_until_it_is_moved() -> void:
	var screen := await _open_play()
	var tuned := (load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).rounds.break_seconds
	assert_float(screen.panel.break_slider.value).is_equal(tuned)
	assert_float(screen.panel.settings().break_seconds).is_equal(0.0)
	screen.panel.break_slider.value = 12.0
	assert_float(screen.panel.settings().break_seconds).is_equal(12.0)


func test_the_keyboard_moves_every_control_and_the_panel_says_so() -> void:
	var screen := await _open_play()
	var heard: Array[MatchSettings] = []
	screen.panel.changed.connect(heard.append)
	screen.panel.count_selector.grab_focus()
	await _tap(&"ui_right", 2)
	assert_str(screen.panel.count_selector.text()).is_equal("3x")
	screen.panel.alive_slider.grab_focus()
	await _tap(&"ui_right", 5)
	screen.panel.limit_slider.grab_focus()
	await _tap(&"ui_right", 3)
	var now := screen.panel.settings()
	assert_float(now.count_multiplier).is_equal(3.0)
	assert_int(now.max_alive).is_equal(5)
	assert_float(now.round_time_limit).is_equal(90.0)
	assert_int(heard.size()).is_equal(2 + 5 + 3)
	assert_bool(heard.back().same_as(now)).is_true()


func test_the_controls_fit_a_720p_window_and_do_not_overlap() -> void:
	var holder := Control.new()
	holder.size = WINDOW
	add_child(holder)
	var screen := (load(PLAY) as PackedScene).instantiate() as PlayScreen
	holder.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var rows := [
		screen.panel.count_row,
		screen.panel.alive_row,
		screen.panel.break_row,
		screen.panel.limit_row,
	]
	for i in rows.size():
		var rect := (rows[i] as Control).get_global_rect()
		assert_float(rect.end.y).is_less_equal(WINDOW.y)
		assert_float(rect.end.x).is_less_equal(WINDOW.x)
		if i > 0:
			assert_float(rect.position.y).is_greater_equal(
				(rows[i - 1] as Control).get_global_rect().end.y - 0.5
			)
	for button in [screen.start_button, screen.back_button, screen.reset_button]:
		assert_float((button as Control).get_global_rect().end.y).is_less_equal(WINDOW.y)
	holder.free()


func test_usual_rules_puts_every_control_back() -> void:
	var screen := await _open_play()
	var loud := MatchSettings.new()
	loud.count_multiplier = 2.0
	loud.max_alive = 7
	screen.panel.set_settings(loud)
	screen.reset_button.pressed.emit()
	assert_bool(screen.panel.settings().is_default()).is_true()


func test_start_opens_a_night_under_the_chosen_settings() -> void:
	var screen := await _open_play()
	screen.panel.count_selector.grab_focus()
	await _tap(&"ui_right", 2)
	screen.panel.alive_slider.grab_focus()
	await _tap(&"ui_right", 8)
	var chosen := screen.panel.settings()
	screen.start_button.pressed.emit()
	await UIRouter.idle
	var night_screen := UIRouter.top() as NightScreen
	assert_object(night_screen).is_not_null()
	await night_screen.night.ready_to_play
	var rules := night_screen.night.server.rules
	assert_bool(rules.settings.same_as(chosen)).is_true()
	assert_float(rules.settings.count_multiplier).is_equal(3.0)
	assert_int(rules.settings.max_alive).is_equal(8)
	# Taken once: the next night starts from the usual rules.
	assert_object(NightScreen.match_settings).is_null()
	rules.apply(RulesAction.skip_break())
	var tuned := rules.tuning.rounds.zombies_for_round(1, 1)
	assert_int(rules._round_total).is_equal(roundi(tuned * 3.0))
