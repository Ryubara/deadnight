# A suite that puts a screen on the router takes it off again (#1039).
#
# The router is an autoload every suite in one run shares. `test_input_matrix.gd` reset it to the
# main menu and left it there: the next suites then ran under a full-rect menu that swallowed the
# mouse motion the world's look reads, and `test_look_window_size.gd` saw no turn at all. It only
# showed in a shard where no suite that clears the router ran between the two, so main stayed
# green while two pull requests (and a reshuffle of the shards) went red. This scan makes the rule
# a failure of its own: every suite that opens a screen or the game's root calls
# `RouterFixture.clear`.
extends GdUnitTestSuite

const TESTS_DIR := "res://tests/"
const CLEARS := "RouterFixture.clear("
## What puts a screen on the router: a call that shows one, or the game's own root (`main.tscn`),
## which resets the router to the main menu when it is ready.
const OPENS := "(UIRouter\\.(reset|push|replace)\\(|res://main\\.tscn)"
## The fixture and this scan name the calls without opening a screen.
const EXEMPT: Array[String] = ["router_fixture.gd", "test_suites_leave_the_router_empty.gd"]


func test_every_suite_that_opens_a_screen_clears_the_router() -> void:
	var suites := _suites(TESTS_DIR)
	assert_int(suites.size()).is_greater(300)
	var opening := 0
	var careless: Array[String] = []
	for path in suites:
		var text := FileAccess.get_file_as_string(path)
		if not _opens_a_screen(text):
			continue
		opening += 1
		if not text.contains(CLEARS):
			careless.append(path)
	assert_int(opening).is_greater(20)  # the scan finds the suites it is about
	(
		assert_array(careless)
		. override_failure_message(
			(
				(
					"These suites open a screen and never call %s...) after it: the next suite runs "
					+ "under the menu they left up, which swallows the mouse look. %s"
				)
				% [CLEARS, careless]
			)
		)
		. is_empty()
	)


## The scan bites: it tells a suite that opens a screen from one that does not.
func test_the_scan_tells_a_suite_that_opens_a_screen_from_one_that_does_not() -> void:
	assert_bool(_opens_a_screen("UIRouter.reset(MENU, UITransition.Kind.CUT)")).is_true()
	assert_bool(_opens_a_screen("UIRouter.push(NIGHT)")).is_true()
	assert_bool(_opens_a_screen('const MAIN := "res://main.tscn"')).is_true()
	assert_bool(_opens_a_screen("var screen := UIRouter.top()")).is_false()
	assert_bool(_opens_a_screen("await UIRouter.idle")).is_false()


func _opens_a_screen(text: String) -> bool:
	return RegEx.create_from_string(OPENS).search(text) != null


## Every `test_*.gd` under `dir`, folders included.
func _suites(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd") and not EXEMPT.has(file):
			found.append(dir + file)
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_suites(dir + sub + "/"))
	return found
