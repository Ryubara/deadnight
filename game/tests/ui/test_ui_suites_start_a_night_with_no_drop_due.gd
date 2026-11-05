# A UI suite that starts a night says whether the helicopter drop is due (#1196).
#
# A headless run never plays the drop that opens a night (`NightScreen.arrival_enabled` is false
# there) and a window does. A suite that pushes the night screen without setting the switch runs one
# story in CI and another on a machine with a window: three suites passed headless for days and
# failed in a window (#1187), and three more did (#1195). This scan makes the rule a failure
# of its own: every suite under `tests/ui` that pushes the night screen scene assigns
# `NightScreen.arrival_enabled`, to false when it is not about the drop (as `--noarrival` does) and
# to true when it is.
#
# `main.tscn` is not scanned: the game's root opens the menu, and a night starts only when a suite
# pushes the night screen itself, which this scan sees.
extends GdUnitTestSuite

const UI_DIR := "res://tests/ui/"
## A suite chooses the drop with `= false` or `= true`; putting back what it found (`= _arrival`)
## is not a choice.
const SETS_THE_DROP := "NightScreen\\.arrival_enabled = (false|true)\\b"
## What puts the night screen on the router: a push, reset or replace (`UIRouter.push(`, or a
## suite's own `_push(` helper) of the scene's path or of a constant (`NIGHT`) that holds it.
const PUSHES_THE_NIGHT := '\\w*(push|reset|replace)\\w*\\(\\s*(NIGHT\\b|"[^"]*night_screen\\.tscn")'
## Another scan that names the calls in its own assertions without pushing a night.
const EXEMPT: Array[String] = ["test_suites_leave_the_router_empty.gd"]
## Suites that push the night and set nothing yet, each with the issue that fixes it: empty since
## #1195 and #1194 landed. A suite that another pull request is fixing is listed here, so this
## scan can merge first; an entry that sets the switch now fails the scan: delete it, so the list
## only shrinks.
const NOT_YET := {}


func test_every_ui_suite_that_pushes_the_night_says_whether_the_drop_is_due() -> void:
	var pushing := 0
	var careless: Array[String] = []
	var stale: Array[String] = []
	for file in _suites():
		var text := FileAccess.get_file_as_string(UI_DIR + file)
		if EXEMPT.has(file) or not _pushes_the_night(text):
			continue
		pushing += 1
		var sets := _sets_the_drop(text)
		if NOT_YET.has(file):
			if sets:
				stale.append(file)
		elif not sets:
			careless.append(file)
	assert_int(pushing).is_greater_equal(8)  # the scan finds the suites it is about
	(
		assert_array(careless)
		. override_failure_message(
			(
				(
					"These suites push the night screen and never set `NightScreen.arrival_enabled` "
					+ "(false: no drop, as headless always has it; true: the suite is about the "
					+ "drop). A window plays the drop and holds the look, the touch layer, the HUD "
					+ "and the reticle for it: %s"
				)
				% [careless]
			)
		)
		. is_empty()
	)
	(
		assert_array(stale)
		. override_failure_message(
			(
				"These suites set the switch now: remove them from NOT_YET in %s. %s"
				% [get_script().resource_path, stale]
			)
		)
		. is_empty()
	)


## Every entry of the list names a suite that exists and that pushes the night: a renamed suite
## cannot hide in it.
func test_the_not_yet_list_names_suites_that_push_the_night() -> void:
	for file in NOT_YET:
		var path: String = UI_DIR + file
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("%s is gone: remove it" % file)
			. is_true()
		)
		(
			assert_bool(_pushes_the_night(FileAccess.get_file_as_string(path)))
			. override_failure_message("%s no longer pushes the night: remove it" % file)
			. is_true()
		)


## The scan bites: it tells a suite that pushes the night from one that does not, and one that sets
## the switch from one that does not.
func test_the_scan_tells_the_suites_apart() -> void:
	assert_bool(_pushes_the_night("UIRouter.push(NIGHT, UITransition.Kind.CUT)")).is_true()
	assert_bool(_pushes_the_night("UIRouter.push( NIGHT )")).is_true()
	assert_bool(_pushes_the_night("await _push(NIGHT)")).is_true()
	# The scene's name is joined here: other scans of this folder read this file's text for it
	# (`test_window_fixture` wants a warm-up fixture from any suite that names it).
	var scene := "res://ui/screens/night_screen" + ".tscn"
	assert_bool(_pushes_the_night('UIRouter.replace("%s")' % scene)).is_true()
	assert_bool(_pushes_the_night("UIRouter.push(MENU, UITransition.Kind.CUT)")).is_false()
	assert_bool(_pushes_the_night("UIRouter.push(NIGHT_REPORT)")).is_false()
	assert_bool(_pushes_the_night('const NIGHT := "%s"' % scene)).is_false()
	assert_bool(_sets_the_drop("NightScreen.arrival_enabled = false")).is_true()
	# gdformat writes the spaces around `=`, so the scan looks for them.
	assert_bool(_sets_the_drop("NightScreen.arrival_enabled=false")).is_false()
	assert_bool(_sets_the_drop("NightScreen.arrival_enabled = true")).is_true()
	assert_bool(_sets_the_drop("var d := NightScreen.arrival_enabled")).is_false()
	assert_bool(_sets_the_drop("NightScreen.arrival_enabled = _arrival")).is_false()


func _pushes_the_night(text: String) -> bool:
	return RegEx.create_from_string(PUSHES_THE_NIGHT).search(text) != null


func _sets_the_drop(text: String) -> bool:
	return RegEx.create_from_string(SETS_THE_DROP).search(text) != null


## Every `test_*.gd` of the UI folder, this scan excluded (it names the call it looks for).
func _suites() -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(UI_DIR):
		if (
			file.begins_with("test_")
			and file.ends_with(".gd")
			and file != get_script().resource_path.get_file()
		):
			found.append(file)
	found.sort()
	return found
