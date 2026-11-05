# A suite that holds an input action must let it go before the next suite starts (#1220). GdUnit
# runs every suite of a shard in one process, so a held key stays held: the scoreboard key left
# down by one online suite made the next HUD suite's scoreboard rebuild 43 nodes in a break that
# should build none. This reads the suites' text (the leak shows only in a shard's order, so no
# run of one suite can see it). An action pressed by an event (`Input.parse_input_event` of an
# `InputEventAction` or a key with `pressed = true`) is held the same way (#1254).
extends GdUnitTestSuite

const SUITES := "res://tests"
## A call that holds an action.
const PRESS := "Input\\.action_press\\("
## An event that presses: a function that sends one and says `pressed = true`.
const SEND := "parse_input_event\\("
const EVENT_DOWN := "pressed = true"
## What counts in a hook: `pressed = false` there may be any node's property.
const HOOK_RELEASE := "Input\\.action_release\\(|InputFixture\\.release_all\\("
## What lets go of an action in the function that pressed it: a release, `InputFixture.release_all`,
## the same kind of event sent again as a release, or `TouchFixture.free_all` (its actions and the
## mouse buttons a finger made).
const RELEASE := HOOK_RELEASE + "|pressed = false|\\.free_all\\("
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


## Whether `text` matches `pattern`.
func _has(text: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null


## Whether `text` calls the release of an action at all (which one may come from a loop or a list).
func _releases(text: String) -> bool:
	return _has(text, RELEASE)


## Whether `text` holds an action: a call that presses it, or an event that presses it.
func _presses(text: String) -> bool:
	return _has(text, PRESS) or (_has(text, SEND) and text.contains(EVENT_DOWN))


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
		if _has(bodies[name], HOOK_RELEASE):
			return true
		for other: String in bodies:
			if String(bodies[name]).contains(other + "("):
				queue.append(other)
	return false


## "suite: function holds an action", for each function that holds one and neither lets one go
## itself nor leaves it to a hook that runs after each test.
func _leaks(path: String) -> Array[String]:
	return _leaks_in(FileAccess.get_file_as_string(path), path)


## The same for a suite's text.
func _leaks_in(text: String, path := "suite") -> Array[String]:
	var bodies := _functions(text)
	var hooked := _hooks_release(bodies)
	var found: Array[String] = []
	for function: String in bodies:
		if not _presses(bodies[function]):
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


func test_no_action_is_held_when_this_suite_runs() -> void:
	# Reads only: the suite that ran before this one in the shard's process left what is down now.
	assert_array(InputFixture.held()).is_empty()


func test_release_all_lets_go_of_a_pressed_action_and_of_one_an_event_pressed() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	Input.action_press(&"ui_cancel")
	InputFixture.release_all()
	assert_array(InputFixture.held()).is_empty()
	# The event had not reached the frame yet; releasing did not leave it to press afterwards.
	await get_tree().process_frame
	assert_array(InputFixture.held()).is_empty()


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


func test_the_scan_sees_an_action_pressed_by_an_event() -> void:
	var send := "Input." + "parse_input_event(event)"
	var down := "event.pressed" + " = true"
	var up := "event.pressed" + " = false"
	var presses := "func _press() -> void:\n\t%s\n\t%s\n" % [down, send]
	var taps := "func _tap() -> void:\n\t%s\n\t%s\n\t%s\n\t%s\n" % [down, send, up, send]
	assert_bool(_presses(presses)).is_true()
	# A function that sends the press and the release is not a leak by itself.
	assert_array(_leaks_in(taps)).is_empty()
	assert_array(_leaks_in(presses)).is_not_empty()
	# A hook that releases through the fixture clears it; `pressed = false` of a node does not.
	var node_off := "func after_test() -> void:\n\tbutton.pressed = false\n"
	var fixture := "func after_test() -> void:\n\tInputFixture." + "release_all()\n"
	assert_array(_leaks_in(presses + node_off)).is_not_empty()
	assert_array(_leaks_in(presses + fixture)).is_empty()
