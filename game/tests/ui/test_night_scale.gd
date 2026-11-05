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
var _arrival := false


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func before_test() -> void:
	_arrival = NightScreen.arrival_enabled
	# No drop due, as headless always has it (`--noarrival`): this suite is not about the drop.
	NightScreen.arrival_enabled = false
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	NightScreen.arrival_enabled = _arrival
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
	await get_tree().process_frame
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


func test_a_screen_under_the_night_gets_the_menus_factor_when_the_night_ends() -> void:
	# Leave night returns to the Play screen, with the menu's shell hidden below it: the shell
	# cannot put the factor back, the night does (#1197). On a real page the Play screen was left
	# at the night's 0.36 CSS pixels to the unit.
	var menu := await _phone_menu()
	var own := float(Settings.get_value(SettingsService.UI_SCALE))
	UIRouter.push("res://ui/screens/play_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	assert_bool(menu.shell.is_visible_in_tree()).is_false()
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	assert_float(get_window().content_scale_factor).is_equal(own)
	UIRouter.pop(UITransition.Kind.CUT)
	await UIRouter.idle
	for _i in 3:
		await get_tree().process_frame
	assert_bool(menu.shell.is_visible_in_tree()).is_false()
	assert_float(get_window().content_scale_factor).is_equal(own * MenuScale.PHONE_FACTOR)


func _paused_night(page: Vector2i, ratio: float) -> NightScreen:
	# A phone's page: the window is the canvas, the page the canvas over the pixel ratio.
	TouchMode.device_is_touch = true
	PageSize.css_override = Vector2(page) / ratio
	MenuScale.pixel_ratio = ratio
	get_window().size = page
	NightScreen.arrival_enabled = false
	RouterFixture.forget_join()
	UIRouter.reset(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	screen._pause()
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _end_page() -> void:
	PageSize.css_override = null
	MenuScale.pixel_ratio = -1.0
	TouchMode.device_is_touch = null


func test_the_pause_card_is_laid_out_at_the_phone_factor_and_the_night_is_not() -> void:
	var saved_size := get_window().size
	var saved_touch: Variant = TouchMode.device_is_touch
	var screen := await _paused_night(Vector2i(1688, 780), 2.0)
	var own := float(Settings.get_value(SettingsService.UI_SCALE))
	# The window (so the HUD and the touch layer) keeps the interface size alone.
	assert_float(get_window().content_scale_factor).is_equal(own)
	var layer: PhoneScale = screen._scaled
	assert_float(layer.factor).is_equal(MenuScale.PHONE_FACTOR)
	assert_vector(layer.scale).is_equal(Vector2(2.0, 2.0))
	# Its canvas is the menu's: 1169 x 540 units, a unit 0.72 CSS px.
	assert_float(layer.size.y).is_equal_approx(540.0, 0.5)
	assert_float(layer.size.x).is_equal_approx(1168.5, 0.5)
	# The card's buttons are tap targets (44 CSS px = 61 units here) and its type is the 14 px floor.
	var audit := UiAudit.scan(screen._overlay, PageSize.css_per_pixel(get_window().size))
	assert_float(audit.tap_min).is_greater_equal(44.0)
	assert_float(audit.text_min).is_greater_equal(14.0)
	_end_page()
	get_window().size = saved_size
	TouchMode.device_is_touch = saved_touch


func test_the_pause_card_goes_back_to_the_interface_size_on_a_page_that_is_not_a_phone() -> void:
	var saved_size := get_window().size
	var saved_touch: Variant = TouchMode.device_is_touch
	var screen := await _paused_night(Vector2i(1688, 780), 2.0)
	var layer: PhoneScale = screen._scaled
	assert_float(layer.factor).is_equal(2.0)
	# A tablet's page: the page's short side is over the limit.
	PageSize.css_override = Vector2(1024, 768)
	get_window().size = Vector2i(2048, 1536)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(layer.factor).is_equal(1.0)
	assert_vector(layer.scale).is_equal(Vector2.ONE)
	assert_vector(layer.size).is_equal_approx(screen._overlay.size, Vector2(0.5, 0.5))
	_end_page()
	get_window().size = saved_size
	TouchMode.device_is_touch = saved_touch
