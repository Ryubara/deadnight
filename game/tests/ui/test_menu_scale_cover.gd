extends GdUnitTestSuite
## A page turned or resized across the phone limit while a screen covers the menu (#1197). The
## shell hides under Settings and Play together, and those screens run on its factor all the same:
## when the window crosses the limit the factor has to follow there too, or the screen keeps the
## layout of the size the page had. A night is the exception: it sets its own and keeps it.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const TEST_PATH := "user://menu_scale_cover_test.cfg"

var _saved_path: String
var _arrival := false


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the night's warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	# A night with no drop, as the screens here are what is read (`test_arrival_night` is about it).
	_arrival = NightScreen.arrival_enabled
	NightScreen.arrival_enabled = false


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	NightScreen.arrival_enabled = _arrival
	Settings.reset_defaults()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	get_window().content_scale_factor = float(Settings.get_value(SettingsService.UI_SCALE))
	Audio.stop_all()


func _menu(phone: bool) -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var menu := UIRouter.top() as MainMenu
	# A headless window is nobody's phone: say what it is, and let the shell see the "resize".
	menu.shell.phone_mode = 1 if phone else 0
	get_window().size_changed.emit()
	return menu


func _turn(menu: MainMenu, phone: bool) -> void:
	menu.shell.phone_mode = 1 if phone else 0
	get_window().size_changed.emit()
	await get_tree().process_frame


func test_a_screen_over_the_menu_follows_the_window_across_the_phone_limit() -> void:
	var own := float(Settings.get_value(SettingsService.UI_SCALE))
	var menu := await _menu(true)
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await UIRouter.idle
	assert_bool(menu.shell.is_visible_in_tree()).is_false()
	assert_float(get_window().content_scale_factor).is_equal(own * MenuScale.PHONE_FACTOR)
	await _turn(menu, false)
	assert_float(get_window().content_scale_factor).is_equal(own)
	await _turn(menu, true)
	assert_float(get_window().content_scale_factor).is_equal(own * MenuScale.PHONE_FACTOR)


func test_a_night_over_the_menu_keeps_its_own_scale_when_the_window_changes() -> void:
	var own := float(Settings.get_value(SettingsService.UI_SCALE))
	var menu := await _menu(false)
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	assert_float(get_window().content_scale_factor).is_equal(own)
	await _turn(menu, true)
	assert_float(get_window().content_scale_factor).is_equal(own)
	UIRouter.pop(UITransition.Kind.CUT)
	await UIRouter.idle
	assert_float(get_window().content_scale_factor).is_equal(own * MenuScale.PHONE_FACTOR)
