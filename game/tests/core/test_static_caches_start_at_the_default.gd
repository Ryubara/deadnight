# A static cache says "not read yet" with the type's own default (#1323).
#
# The engine runs a static variable's initialiser when its script is loaded. Two scripts that refer
# to each other load one inside the other, and an initialiser of the first can call a static
# function of the second before the second's own initialisers have run. `WebProbe.asked()` was
# called that way by `NightScreen.arrival_enabled`; its cache was `static var _asked := -1`, so it
# held the int default 0 there, read 0 as "the page did not ask", and a page that asked for the
# probes played the helicopter drop, but only in the benches, whose typed members loaded the night
# first. A cache whose "not read" is `-1` (or any other number than 0) fails like that; one that has
# no initialiser (0, `false`, `null`) does not. This scan fails for a game script that declares a
# static variable with a number other than zero as its initial value.
extends GdUnitTestSuite

const GAME_DIR := "res://"
## Folders that are not the game's own scripts.
const SKIPPED: Array[String] = ["res://addons/", "res://tests/", "res://.godot/"]
## `static var name := -1`, `static var name: int = 5.0`, with an optional comment after it.
const NUMBER_INIT := (
	"^static var \\w+\\s*(?::\\s*\\w+)?\\s*:?=\\s*" + "(-?[0-9][0-9_]*(?:\\.[0-9]+)?)\\s*(?:#.*)?$"
)
## Scripts with a static variable that starts on a number other than zero on purpose, each with why
## it is safe: it is read by a function that runs once the game is up, and no static initialiser of
## any script reads it. A new entry says the same, or the variable loses its initialiser instead.
const ALLOWED := {
	"res://ui/hud/hud_level_cell.gd":
	"`_level_room`: measured in `level_room()`, called when a cell is built",
	"res://ui/menu/menu_scale.gd":
	"`pixel_ratio`: -1 asks the page; read in the scale functions, set by tests",
	"res://ui/screens/night_screen.gd":
	"`start_seed`: -1 is a fresh seed; read when a solo night starts",
}


func test_no_game_script_starts_a_static_variable_on_a_number_other_than_zero() -> void:
	var scripts := _scripts(GAME_DIR)
	assert_int(scripts.size()).is_greater(300)  # the scan finds the game's scripts
	var regex := RegEx.create_from_string(NUMBER_INIT)
	var found: Array[String] = []
	for path in scripts:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if _starts_off_zero(regex, line) and not ALLOWED.has(path):
				found.append("%s: %s" % [path, line.strip_edges()])
	(
		assert_array(found)
		. override_failure_message(
			(
				(
					"A static variable that begins on a number other than 0 reads 0 when a static "
					+ "initialiser of a script that refers back to this one runs first (#1323). Give it "
					+ 'no initialiser and let 0 mean "not read yet": %s'
				)
				% [found]
			)
		)
		. is_empty()
	)


func test_the_scan_tells_a_cache_that_starts_on_minus_one_from_one_that_starts_on_the_default(
) -> void:
	var regex := RegEx.create_from_string(NUMBER_INIT)
	assert_bool(_starts_off_zero(regex, "static var _asked := -1")).is_true()
	assert_bool(_starts_off_zero(regex, "static var _asked: int = -1  # not yet")).is_true()
	assert_bool(_starts_off_zero(regex, "static var gap := 0.5")).is_true()
	assert_bool(_starts_off_zero(regex, "static var _asked: int")).is_false()
	assert_bool(_starts_off_zero(regex, "static var _asked := 0")).is_false()
	assert_bool(_starts_off_zero(regex, "static var _asked := 0.0")).is_false()
	assert_bool(_starts_off_zero(regex, "static var enabled := true")).is_false()
	assert_bool(_starts_off_zero(regex, "var _asked := -1")).is_false()  # an instance variable


func test_the_two_probes_that_ask_the_page_once_start_unread() -> void:
	# Their caches have no initialiser: the unread state is the default of an int, 0. Read through
	# the script's constants, so a script without them fails here and does not stop the suite.
	var states: Dictionary = (load("res://core/web_probe.gd") as Script).get_script_constant_map()
	assert_int(int(states.get("UNREAD", -1))).is_equal(0)
	assert_int(int(states.get("NO", -1))).is_greater(0)
	assert_int(int(states.get("YES", -1))).is_greater(int(states.get("NO", -1)))
	# Off the web nothing is asked: the answer is no, whatever the cache holds.
	assert_bool(WebProbe.asked()).is_false()
	assert_bool(GamepadProbe.in_frame()).is_false()


func _starts_off_zero(regex: RegEx, line: String) -> bool:
	var hit := regex.search(line)
	return hit != null and float(hit.get_string(1).replace("_", "")) != 0.0


func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	if SKIPPED.has(dir):
		return found
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(sub) + "/"))
	return found
