extends GdUnitTestSuite
## On a phone's web page every menu screen has text of at least 14 CSS pixels and every control a
## finger presses is at least 44 CSS pixels high (#1197). The page is 844 x 390 CSS pixels: the
## window is its canvas, 1688 x 780 at the pixel ratio of 2 the game reports (`PhoneRender`) and
## 2532 x 1170 at the phone's own 3. A unit must be 0.72 CSS pixels on all of them (0.8 on the
## taller 932 x 430 page, 0.69 on the narrowest, 667 x 375: 1334 x 750 at the ratio of 2); before
## the test for a phone read the page, it was 0.36 and the type 7.9 px.
##
## The measuring is `UiAudit`, the numbers the web probe publishes
## (`tools/web_smoke/phone_layout.py`).

const TEST_PATH := "user://phone_floor_test.cfg"
## 844 x 390 as a window (the native phone), and as a page at each ratio, and the narrowest page.
const CASES: Array = [
	[Vector2i(844, 390), 1.0],
	[Vector2i(1688, 780), 2.0],
	[Vector2i(2532, 1170), 3.0],
	[Vector2i(1864, 860), 2.0],
	[Vector2i(1334, 750), 2.0],
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
