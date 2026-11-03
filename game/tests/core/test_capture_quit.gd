# A capture ends with exit code 0 (#667). A windowed tour exited with 139 (an access violation)
# after its frames were saved: it had put a lambda of its own script in a static variable of the
# game (`MainMenu.board_factory`), the engine frees the tour's script before the game's statics, and
# the variable then held a dead lambda at quit. The same crash shows in a headless child Godot, so
# the first test runs one and reads the exit code (the audio quit test does the same for leaks).
# The second keeps it from coming back: a capture or tour script that sets a hook to a lambda
# clears the same hook in the same file.
extends GdUnitTestSuite

const PROBE := "res://tests/core/static_hook_quit_probe.gd"
const SCRIPT_FOLDERS := ["res://tests/captures", "res://tests/tours"]
const HOOK_SET := "\\b([A-Z]\\w*)\\.(\\w+)\\s*=\\s*(?:func\\b|[\\w.]+\\.bind\\()"


func _exit_code(extra: PackedStringArray = []) -> int:
	var arguments := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", PROBE]
	)
	if not extra.is_empty():
		arguments.append("--")
		arguments.append_array(extra)
	return OS.execute(OS.get_executable_path(), arguments, [], true)


func _scripts() -> PackedStringArray:
	var found := PackedStringArray()
	for folder: String in SCRIPT_FOLDERS:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				found.append("%s/%s" % [folder, file])
	return found


func test_a_hook_cleared_before_quitting_ends_with_code_0() -> void:
	assert_int(_exit_code()).is_equal(0)


func test_every_lambda_a_capture_sets_on_a_class_is_cleared_in_the_same_file() -> void:
	var regex := RegEx.create_from_string(HOOK_SET)
	var missing := PackedStringArray()
	for path in _scripts():
		var text := FileAccess.get_file_as_string(path)
		for hit in regex.search_all(text):
			var target := "%s.%s" % [hit.get_string(1), hit.get_string(2)]
			var clear := RegEx.create_from_string(
				"\\b%s\\s*=\\s*Callable\\(\\)" % target.replace(".", "\\.")
			)
			if clear.search(text) == null:
				missing.append("%s sets %s to a lambda and never clears it" % [path, target])
	assert_array(missing).is_empty()
