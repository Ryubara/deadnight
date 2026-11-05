# A suite that holds an input action must let it go before the next suite starts (#1220). GdUnit
# runs every suite of a shard in one process, so a held key stays held: the scoreboard key left
# down by one online suite made the next HUD suite's scoreboard rebuild 43 nodes in a break that
# should build none. This reads the suites' text (the leak shows only in a shard's order, so no
# run of one suite can see it).
extends GdUnitTestSuite

const SUITES := "res://tests"
## A call that holds an action, and one that lets it go.
const PRESS := "Input\\.action_press\\("
const RELEASE := "Input\\.action_release\\("
## The hooks GdUnit runs after each test and after the suite.
const CLEANUP_HOOKS := ["after_test", "after"]


## Every test script under `dir`, as resource paths.
func _suites(dir: String) -> Array[String]:
	var found: Array[String] = []
	for entry in DirAccess.get_directories_at(dir):
		found.append_array(_suites(dir.path_join(entry)))
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir.path_join(file))
	return found


## The functions of a script's text, name to body (comment lines left out).
func _functions(text: String) -> Dictionary:
	var bodies := {}
	var name := ""
	for line in text.split("\n"):
		if line.begins_with("func ") or line.begins_with("static func "):
			name = line.get_slice("func ", 1).get_slice("(", 0).strip_edges()
			bodies[name] = ""
		elif name != "" and not line.strip_edges().begins_with("#"):
			bodies[name] += line + "\n"
	return bodies


## Whether `text` calls the release of an action at all (which one may come from a loop or a list).
func _releases(text: String) -> bool:
	return RegEx.create_from_string(RELEASE).search(text) != null


## Whether the hooks that run after each test (and the helpers they call) let an action go.
func _hooks_release(bodies: Dictionary) -> bool:
	var reached: Array[String] = []
	var queue: Array[String] = []
	queue.assign(CLEANUP_HOOKS)
	while not queue.is_empty():
		var name: String = queue.pop_back()
		if reached.has(name) or not bodies.has(name):
			continue
		reached.append(name)
		if _releases(bodies[name]):
			return true
		for other: String in bodies:
			if String(bodies[name]).contains(other + "("):
				queue.append(other)
	return false


## "suite: function holds an action", for each function that holds one and neither lets one go
## itself nor leaves it to a hook that runs after each test.
func _leaks(path: String) -> Array[String]:
	var bodies := _functions(FileAccess.get_file_as_string(path))
	var hooked := _hooks_release(bodies)
	var found: Array[String] = []
	for function: String in bodies:
		if RegEx.create_from_string(PRESS).search(bodies[function]) == null:
			continue
		if not (hooked or _releases(bodies[function])):
			found.append("%s: %s holds an action" % [path, function])
	return found


func test_no_suite_leaves_an_action_held_for_the_next() -> void:
	var leaks: Array[String] = []
	var scanned := 0
	for path in _suites(SUITES):
		scanned += 1
		leaks.append_array(_leaks(path))
	assert_int(scanned).is_greater(100)
	assert_array(leaks).is_empty()


func test_the_scan_tells_a_held_action_from_one_let_go() -> void:
	# The calls are written in two parts so this file does not hold an action in the scan's eyes.
	var hold := "Input." + 'action_press(&"x")'
	var let_go := "Input." + 'action_release(&"x")'
	assert_bool(_releases("func _hold() -> void:\n\t%s\n" % hold)).is_false()
	assert_bool(_releases("func _free() -> void:\n\t%s\n" % let_go)).is_true()
	# A hook that calls a helper that lets go counts; a hook that does not call it does not.
	var helper := "func _free() -> void:\n\t%s\n" % let_go
	var calls := "func after_test() -> void:\n\t_free()\n" + helper
	var skips := "func after_test() -> void:\n\tpass\n" + helper
	assert_bool(_hooks_release(_functions(calls))).is_true()
	assert_bool(_hooks_release(_functions(skips))).is_false()
