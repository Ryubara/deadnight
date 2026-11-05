# The night as a screen: Play starts it, Esc pauses and resumes, the result shows when the night is
# over, and the way out leads back to the main menu.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"

var _arrival := false


func before_test() -> void:
	# The helicopter drop a window plays at the start of a night (#1057) holds the look, the
	# touch layer and the HUD until it ends; a headless run has none. This suite is about
	# the night as a screen, in a night the player has control of (`--noarrival`);
	# `test_arrival_night` is about the drop.
	_arrival = NightScreen.arrival_enabled
	NightScreen.arrival_enabled = false


func after_test() -> void:
	NightScreen.arrival_enabled = _arrival
	# The way out leads back to the menu, which would stay on the shared router for the next suite.
	await RouterFixture.clear(get_tree())


func _enter_night() -> NightScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	return screen


func _press_escape(action := &"pause") -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame


func _leave(screen: NightScreen) -> void:
	UIRouter.pop()
	await UIRouter.idle
	await get_tree().process_frame
	assert_bool(is_instance_valid(screen)).is_false()


func test_play_starts_a_night_the_player_can_move_in() -> void:
	var screen := await _enter_night()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(screen.night.running).is_true()
	assert_int(screen.night.server.tick_count).is_greater(0)
	assert_bool(screen.night.player().controls_enabled()).is_true()
	await _leave(screen)


func test_the_hud_is_on_the_night_and_hears_it() -> void:
	var screen := await _enter_night()
	# The night's first frame (the server's first tick) comes a few physics frames after the start:
	# how many depends on the machine (a window with its loading screen has the HUD's events before
	# it, a headless run neither), so the test waits for it instead of counting frames.
	for _i in 120:
		if screen.night.state.frame.has("tick"):
			break
		await get_tree().physics_frame
	assert_bool(screen.night.state.frame.has("tick")).is_true()
	var huds := screen.find_children("*", "Hud", true, false)
	assert_array(huds).has_size(1)
	var hud := huds[0] as Hud
	assert_bool(hud.state.team.has(Night.PLAYER_ID)).is_true()
	assert_int(hud.state.phase).is_equal(HudState.PHASE_BREAK)
	assert_int(hud.state.points).is_equal(screen.night.state.points())
	assert_int(hud.state.points).is_equal(screen.night.rules_tuning.economy.start_points)
	await _leave(screen)


func test_a_left_hand_flips_the_hud_corners_with_the_touch_layout_and_keeps_them_in_a_menu(
) -> void:
	var settings: SettingsService = get_tree().root.get_node("Settings")
	var before: Variant = settings.get_value(SettingsService.LEFT_HANDED)
	TouchMode.device_is_touch = true
	settings.set_value(SettingsService.LEFT_HANDED, true)
	var screen := await _enter_night()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hud := screen.find_children("*", "Hud", true, false)[0] as Hud
	assert_bool(hud.mirrored).is_true()
	assert_float(hud.ammo.get_global_rect().get_center().x).is_less(hud.size.x * 0.5)
	assert_float(hud.health.get_global_rect().get_center().x).is_greater(hud.size.x * 0.5)
	await _press_escape()
	assert_bool(hud.mirrored).is_true()
	settings.set_value(SettingsService.LEFT_HANDED, false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(hud.mirrored).is_false()
	assert_float(hud.ammo.get_global_rect().get_center().x).is_greater(hud.size.x * 0.5)
	TouchMode.device_is_touch = null
	settings.set_value(SettingsService.LEFT_HANDED, before)
	await _leave(screen)


func test_escape_pauses_and_resume_goes_on() -> void:
	var screen := await _enter_night()
	await _press_escape()
	assert_bool(screen.night.is_paused()).is_true()
	assert_bool(screen.night.running).is_false()
	var resume: UIButton = null
	for candidate in screen.find_children("*", "UIButton", true, false):
		if (candidate as UIButton).text == "Resume":
			resume = candidate
	assert_object(resume).is_not_null()
	resume.pressed.emit()
	assert_bool(screen.night.is_paused()).is_false()
	assert_bool(screen.night.running).is_true()
	await _leave(screen)


func test_the_reticle_hides_under_the_pause_card_and_returns_on_resume() -> void:
	var screen := await _enter_night()
	var hud := screen.find_children("*", "Hud", true, false)[0] as Hud
	await get_tree().physics_frame
	assert_bool(hud.reticle.visible).is_true()
	await _press_escape()
	assert_bool(hud.reticle.visible).is_false()
	await _press_escape()
	assert_bool(hud.reticle.visible).is_true()
	await _leave(screen)


func test_b_crouches_in_the_night_it_neither_pauses_nor_leaves() -> void:
	var screen := await _enter_night()
	await _press_escape(&"ui_cancel")
	await get_tree().physics_frame
	assert_bool(screen.night.is_paused()).is_false()
	assert_object(UIRouter.top()).is_same(screen)
	await _press_escape()
	assert_bool(screen.night.is_paused()).is_true()
	await _press_escape(&"ui_cancel")
	assert_bool(screen.night.is_paused()).is_false()
	await _leave(screen)


func test_the_way_out_returns_to_the_menu() -> void:
	var screen := await _enter_night()
	await _press_escape()
	for candidate in screen.find_children("*", "UIButton", true, false):
		if (candidate as UIButton).text == "Leave night":
			candidate.pressed.emit()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)


func test_a_night_keeps_challenges_only_where_the_game_asks_it_to() -> void:
	NightScreen.challenge_path = ""
	var screen := await _enter_night()
	assert_object(screen.night.challenge_board).is_null()
	await _leave(screen)
	var path := ChallengeFixture.save_path("screen")
	NightScreen.challenge_path = path
	screen = await _enter_night()
	NightScreen.challenge_path = ""
	assert_object(screen.night.challenge_board).is_not_null()
	assert_str(screen.night.challenge_board.path).is_equal(path)
	assert_object(screen.night.challenges).is_not_null()
	await _leave(screen)
