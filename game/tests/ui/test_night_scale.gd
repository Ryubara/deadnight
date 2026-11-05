# A night is not run on the menu's phone factor (#606). The factor doubles the units' size on a
# phone, which halves the canvas to 540 units high: right for the menu, but the night's HUD and
# touch layer are made for 1080, and half the touch buttons were off the top. The night puts the
# player's own scale on the window while it runs, and the menu takes the phone factor back when it
# shows again.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const TEST_PATH := "user://night_scale_test.cfg"

var _saved_path: String


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	Settings.reset_defaults()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	get_window().content_scale_factor = float(Settings.get_value(SettingsService.UI_SCALE))
	Audio.stop_all()


func _phone_menu() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	# A headless window is nobody's phone: say it is one, and let the shell see the "resize".
	menu.shell.phone_mode = 1
	get_window().size_changed.emit()
	return menu


func test_the_night_runs_on_the_players_scale_and_the_menu_gets_the_phone_factor_back() -> void:
	var menu := await _phone_menu()
	var own := float(Settings.get_value(SettingsService.UI_SCALE))
	assert_float(get_window().content_scale_factor).is_equal(own * MenuScale.PHONE_FACTOR)
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	assert_float(get_window().content_scale_factor).is_equal(own)
	UIRouter.pop(UITransition.Kind.CUT)
	await UIRouter.idle
	assert_object(UIRouter.top()).is_same(menu)
	assert_float(get_window().content_scale_factor).is_equal(own * MenuScale.PHONE_FACTOR)


func test_a_ui_scale_change_in_the_night_does_not_bring_the_phone_factor_back() -> void:
	await _phone_menu()
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	Settings.set_value(SettingsService.UI_SCALE, 1.2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(get_window().content_scale_factor).is_equal_approx(1.2, 0.001)
