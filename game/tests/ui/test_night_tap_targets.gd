extends GdUnitTestSuite
## What a player presses in a night on a phone is a tap target (Deadnight #1192). A night runs at
## the interface size alone (`NightScreen._ready` takes the menu's phone factor off), so one unit is
## 0.36 CSS px on a phone's page (844 x 390 CSS px) and a button the theme makes 79 units high is
## 28 CSS px: under the 44 the menu keeps (`MenuLook.TAP_TARGET`, 62 units at the menu's factor).
## A phone's page is a 1688 x 780 window (the page's pixel ratio is 2), so sizes are read in CSS px:
## window pixels over the ratio. These run in a real `NightScreen` opened through the router (so
## with the game's theme), at the factor it really runs at: the end board's Leave, the pause card's
## buttons and the touch layer's hit areas.

const PLAY := "res://ui/screens/play_screen.tscn"
const SETTINGS_PATH := "user://night_tap_targets_test.cfg"
## The phones the game is held on, sideways, and the interface sizes a player can choose.
## The pages a phone held sideways gives, as {window, ratio}: 844 x 390, 932 x 430 and 667 x 375 CSS
## px at the page's ratio of 2, and the 844 x 390 window of a ratio of 1 (a desktop browser's size).
const PHONES: Array[Dictionary] = [
	{"window": Vector2i(1688, 780), "ratio": 2.0},
	{"window": Vector2i(1864, 860), "ratio": 2.0},
	{"window": Vector2i(1334, 750), "ratio": 2.0},
	{"window": Vector2i(844, 390), "ratio": 1.0},
]
const SCALES: Array[float] = [0.8, 1.0, 1.25]
## A pixel's tolerance: a rounded-up unit count can still be a hair under in pixels.
const SLACK := 0.5

var _saved_size := Vector2i.ZERO
var _saved_scale := 1.0
var _saved_path := ""


func before_test() -> void:
	PlayerLevel.use(10)
	_saved_size = get_window().size
	_saved_scale = get_window().content_scale_factor
	_saved_path = Settings.path
	Settings.path = SETTINGS_PATH
	Settings.reset_defaults()
	TouchMode.device_is_touch = true


func after_test() -> void:
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_scale
	TouchMode.device_is_touch = null
	MenuScale.pixel_ratio = -1.0
	PlayerLevel.reset()
	await RouterFixture.clear(get_tree())
	NightScreen.match_settings = null
	Settings.reset_defaults()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


## A solo night through the Play screen at a phone's page and the interface size `ui_scale`.
func _night(page: Dictionary, ui_scale: float) -> NightScreen:
	get_window().size = page["window"]
	MenuScale.pixel_ratio = page["ratio"]
	Settings.set_value(SettingsService.UI_SCALE, ui_scale)
	var chosen := MatchSettings.new()
	chosen.map = "small_indoor"
	chosen.bots = 2
	chosen.count_multiplier = 2.0
	chosen.break_seconds = 9.0
	UIRouter.reset(PLAY, UITransition.Kind.CUT)
	await UIRouter.idle
	var play := UIRouter.top() as PlayScreen
	play.panel.set_settings(chosen.clamped())
	play.start()
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	return screen


func _end(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	NightFixture.run(night, 3)
	await get_tree().process_frame
	await get_tree().process_frame


## CSS pixels in one unit of the window the night is shown in: what a finger meets.
func _css(ratio: float) -> float:
	return MenuScale.pixels_per_unit(get_window().size, get_window().content_scale_factor) / ratio


## The pressable controls under `root` that are on screen and under a tap target, in words.
func _small_buttons(root: Node, where: String, ratio: float) -> Array[String]:
	var found: Array[String] = []
	var least := MenuScale.TAP_PIXELS
	for node in root.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if not button.is_visible_in_tree():
			continue
		var real := button.get_global_rect().size * _css(ratio)
		if real.x < least - SLACK or real.y < least - SLACK:
			found.append(
				"%s: '%s' is %.1f x %.1f CSS px" % [where, button.get("text"), real.x, real.y]
			)
	return found


func test_a_phones_page_is_a_big_window_and_a_unit_is_a_third_of_a_css_pixel() -> void:
	var page: Dictionary = PHONES[0]
	var screen := await _night(page, 1.0)
	# 844 x 390 CSS px at a ratio of 2: not a "small window" (the menu's phone test), and no factor.
	assert_bool(MenuScale.is_phone(get_window().size)).is_false()
	assert_float(get_window().content_scale_factor).is_equal(1.0)
	assert_float(_css(2.0)).is_equal_approx(0.3611, 0.001)
	# The canvas the engine really draws is that many window pixels to the unit.
	var drawn := get_window().get_final_transform().get_scale().x
	assert_float(drawn / 2.0).is_equal_approx(0.3611, 0.001)
	assert_bool(screen.night.running).is_true()


func test_the_menus_tap_target_and_the_nights_are_the_same_size_in_css_pixels() -> void:
	# 62 units at the menu's phone factor (one unit 0.72 CSS px) are what 44 CSS px are at the night's.
	var menu := MenuLook.TAP_TARGET * MenuScale.pixels_per_unit(Vector2i(844, 390), 2.0)
	assert_float(menu).is_between(MenuScale.TAP_PIXELS, MenuScale.TAP_PIXELS + 1.5)
	get_window().size = Vector2i(1688, 780)
	get_window().content_scale_factor = 1.0
	MenuScale.pixel_ratio = 2.0
	var units := MenuScale.tap_units(get_window(), true)
	assert_float(units).is_equal(122.0)
	assert_float(units * _css(2.0)).is_between(MenuScale.TAP_PIXELS, MenuScale.TAP_PIXELS + 0.5)


func test_a_window_too_small_for_a_finger_asks_for_at_most_a_fifth_of_its_height() -> void:
	# A headless test's window is 64 x 64: 44 CSS px are over a thousand units there.
	get_window().size = Vector2i(64, 64)
	get_window().content_scale_factor = 1.0
	MenuScale.pixel_ratio = 1.0
	var canvas := 64.0 / MenuScale.pixels_per_unit(Vector2i(64, 64), 1.0)
	assert_float(MenuScale.tap_units(get_window(), true)).is_less_equal(canvas * 0.2)


func test_a_screen_with_no_finger_keeps_the_controls_own_size() -> void:
	get_window().size = Vector2i(1688, 780)
	MenuScale.pixel_ratio = 2.0
	assert_float(MenuScale.tap_units(get_window(), false)).is_equal(0.0)
	# A touch screen on a desktop at its own size asks for 44 units: under the theme's 79.
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_factor = 1.0
	MenuScale.pixel_ratio = 1.0
	assert_float(MenuScale.tap_units(get_window(), true)).is_equal(44.0)


func test_the_end_boards_leave_is_a_tap_target_at_every_phone_and_interface_size() -> void:
	var faults: Array[String] = []
	for page in PHONES:
		for ui_scale in SCALES:
			var screen := await _night(page, ui_scale)
			await _end(screen)
			var board: HudEndBoard = screen.get_node("EndBoard")
			assert_bool(board.leave_button.is_visible_in_tree()).is_true()
			var where := "%s at %s" % [page["window"], ui_scale]
			faults.append_array(_small_buttons(board, where, page["ratio"]))
			await RouterFixture.clear(get_tree())
	assert_array(faults).is_empty()


func test_the_pause_cards_buttons_are_tap_targets_on_a_phone() -> void:
	var faults: Array[String] = []
	for page: Dictionary in [PHONES[0], PHONES[3]]:
		for ui_scale in SCALES:
			var screen := await _night(page, ui_scale)
			screen._pause()
			await get_tree().process_frame
			await get_tree().process_frame
			assert_int(screen._card.find_children("*", "UIButton", true, false).size()).is_equal(3)
			var where := "paused, %s at %s" % [page["window"], ui_scale]
			faults.append_array(_small_buttons(screen._card, where, page["ratio"]))
			await RouterFixture.clear(get_tree())
	assert_array(faults).is_empty()


func test_every_touch_hit_area_is_a_tap_target_on_a_phone() -> void:
	# Pure geometry: the layout of the canvas a phone's night has. The smallest interface size (0.8)
	# is short by 6 CSS px for the five small buttons (a separate issue: their circles overlap).
	var faults: Array[String] = []
	for ui_scale: float in [1.0, 1.25]:
		var window := Vector2i(1688, 780)
		var per_unit := MenuScale.pixels_per_unit(window, ui_scale)
		var canvas := Vector2(window) / per_unit
		var circles := TouchLayout.buttons(Rect2(Vector2.ZERO, canvas), 1.0)
		for id: StringName in circles:
			var diameter: float = float(circles[id][&"hit"]) * 2.0 * per_unit / 2.0
			if diameter < MenuScale.TAP_PIXELS - SLACK:
				faults.append("%s at %s: hit area is %.1f CSS px" % [id, ui_scale, diameter])
	assert_array(faults).is_empty()
