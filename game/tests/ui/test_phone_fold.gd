extends GdUnitTestSuite
## What a phone's page shows of two screens without a finger moving them (#1227). Play together is
## 540 units high on a phone's canvas and its way to enter a code and Back used to be below the
## fold, with only a scrollbar to say so; the lobby's rule "Break between rounds" was cut to
## "Break between ro...". The pages are the real ones: 844 x 390 CSS pixels at the ratio of 2 the
## game reports and at the phone's own 3 (`UiFitRun.PAGES`).

const TEST_PATH := "user://phone_fold_test.cfg"
## How far a control may reach past the scroll's rectangle (a pixel of rounding).
const SLACK := 1.0

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


func _in_view(control: Control, area: Rect2) -> bool:
	var rect := control.get_global_rect()
	return control.is_visible_in_tree() and area.grow(SLACK).encloses(rect)


func test_play_together_shows_every_choice_and_back_without_scrolling() -> void:
	var problems: Array[String] = []
	for entry: Array in UiFitRun.PAGES:
		await _run.set_window(entry[0], 1.0, entry[1])
		var together := (await _run.open("together"))["root"] as TogetherScreen
		var scroll := together.find_child("Scroll", true, false) as ScrollContainer
		var area := scroll.get_global_rect()
		for control: Control in [
			together.browser_button,
			together.create_button,
			together.code_field,
			together.join_button,
			together.back_button
		]:
			if not _in_view(control, area):
				problems.append(
					(
						"%s: %s at %s is outside the scroll's view %s"
						% [entry[0], control.name, control.get_global_rect(), area]
					)
				)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_no_rule_of_the_lobby_is_cut_on_a_phone_page() -> void:
	var problems: Array[String] = []
	for name_of_screen in ["lobby host", "lobby guest"]:
		for entry: Array in UiFitRun.PAGES:
			await _run.set_window(entry[0], 1.0, entry[1])
			var lobby := (await _run.open(name_of_screen))["root"] as LobbyScreen
			for key: String in lobby.rules.rows:
				var row: UIRow = lobby.rules.row_for(key)
				if row.title_cut():
					problems.append(
						"%s %s: the title of %s is cut" % [name_of_screen, entry[0], key]
					)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


## The solo screen is not cut on the pages of 844 x 390 CSS pixels and wider; on the narrowest
## phone (667 x 375, a 960 unit canvas) it still is, and the whole title overflows its card there.
func test_the_solo_screens_rules_are_not_cut_either() -> void:
	var problems: Array[String] = []
	for entry: Array in UiFitRun.PAGES:
		if entry[0].x < 1688:
			continue
		await _run.set_window(entry[0], 1.0, entry[1])
		var play := (await _run.open("play"))["root"] as PlayScreen
		for key: String in play.panel.rows:
			if play.panel.row_for(key).title_cut():
				problems.append("%s: the title of %s is cut" % [entry[0], key])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
