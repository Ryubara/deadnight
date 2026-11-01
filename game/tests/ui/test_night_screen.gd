# The night as a screen: Play starts it, Esc pauses and resumes, the result shows when the night is
# over, and the way out leads back to the main menu.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"


func _enter_night() -> NightScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	return screen


func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
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
	await get_tree().physics_frame
	await get_tree().physics_frame
	var huds := screen.find_children("*", "Hud", true, false)
	assert_array(huds).has_size(1)
	var hud := huds[0] as Hud
	assert_bool(hud.state.team.has(Night.PLAYER_ID)).is_true()
	assert_int(hud.state.phase).is_equal(HudState.PHASE_BREAK)
	assert_int(hud.state.points).is_equal(screen.night.state.points())
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


func test_the_way_out_returns_to_the_menu() -> void:
	var screen := await _enter_night()
	await _press_escape()
	for candidate in screen.find_children("*", "UIButton", true, false):
		if (candidate as UIButton).text == "Back to the menu":
			candidate.pressed.emit()
	await UIRouter.idle
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
