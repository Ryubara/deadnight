extends GdUnitTestSuite
## On a phone's web page every menu screen has text of at least 14 CSS pixels and every control a
## finger presses is at least 44 CSS pixels high (#1197). The page is 844 x 390 CSS pixels: the
## window is its canvas, 1688 x 780 at the pixel ratio of 2 the game reports (`PhoneRender`) and
## 2532 x 1170 at the phone's own 3. A unit must be 0.72 CSS pixels on all of them (0.8 on the
## taller 932 x 430 page); before the test for a phone read the page, it was 0.36 and the type
## 7.9 px.
##
## The measuring is `UiAudit`, the numbers the web probe publishes
## (`tools/web_smoke/phone_layout.py`).

const TEST_PATH := "user://phone_floor_test.cfg"
## 844 x 390 as a window (the native phone), and as a page at each ratio.
const CASES: Array = [
	[Vector2i(844, 390), 1.0],
	[Vector2i(1688, 780), 2.0],
	[Vector2i(2532, 1170), 3.0],
	[Vector2i(1864, 860), 2.0],
]

var _run: UiFitRun
var _saved_path: String
var _saved_touch: Variant


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	_saved_touch = TouchMode.device_is_touch
	await RouterFixture.clear(get_tree())
	_run = UiFitRun.new(get_tree())
	_run.begin()


func after_test() -> void:
	await _run.close()
	_run.restore()
	TouchMode.device_is_touch = _saved_touch
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _assert_none(problems: Array[String]) -> void:
	(
		assert_array(problems)
		. override_failure_message(
			"%d floor problems:\n%s" % [problems.size(), "\n".join(problems)]
		)
		. is_empty()
	)


func test_a_unit_is_the_same_size_to_a_person_on_every_phone_page() -> void:
	for entry: Array in CASES:
		await _run.set_window(entry[0], 1.0, entry[1])
		var window := get_tree().root
		var per_unit := MenuScale.css_per_unit(window.size, window.content_scale_factor)
		(
			assert_float(per_unit)
			. override_failure_message(
				"%s: %s" % [entry[0], MenuScale.describe(window.size, window.content_scale_factor)]
			)
			. is_equal_approx(MenuScale.PHONE_FACTOR * float(entry[0].y) / entry[1] / 1080.0, 0.01)
		)


func test_every_menu_tab_has_text_and_targets_a_person_can_use() -> void:
	var problems: Array[String] = []
	for entry: Array in CASES:
		await _run.set_window(entry[0], 1.0, entry[1])
		for tab: MenuTab.Id in MenuTab.ORDER:
			problems.append_array(_run.floor_problems(await _run.open_tab(tab)))
	_assert_none(problems)


func test_every_screen_has_text_and_targets_a_person_can_use() -> void:
	var problems: Array[String] = []
	for entry: Array in CASES:
		await _run.set_window(entry[0], 1.0, entry[1])
		for screen_name in UiFitRun.screen_names():
			problems.append_array(_run.floor_problems(await _run.open(screen_name)))
	_assert_none(problems)


func test_the_nights_pause_card_and_its_settings_have_text_and_targets_a_person_can_use() -> void:
	# A night runs at the interface size alone (its HUD is made for 1080 units); the card that opens
	# over it and the Settings inside it are laid out at the phone factor (#1205). Before, the card
	# was 12 px type and its Settings a desktop's, 0.36 CSS px to the unit.
	var screen := await _run.open_night()
	var problems: Array[String] = []
	for entry: Array in CASES:
		await _run.set_window(entry[0], 1.0, entry[1])
		# One night, a window that changes under it: the card follows the page it is on.
		await _run.frames()
		problems.append_array(_run.floor_problems(await _run.open_night_card(screen)))
		for tab: int in UiFitRun.SETTINGS_TABS:
			problems.append_array(_run.floor_problems(await _run.open_night_card(screen, tab)))
		await _run.close_night_card(screen)
	_assert_none(problems)
