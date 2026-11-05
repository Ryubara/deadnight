# A run of GdUnit leaves nothing in use at exit whatever suites it holds (Deadnight #1231). A suite
# that names a class (`HeldWeapon`, the lot's silhouettes) made Godot read that class's scripts as
# the suite's dependencies and leave them in use at exit: 243 objects for the re-cut skin suite
# alone, 257 for the greybox suite, 996 for the mix a CI shard held, and CI failed on the two leak
# lines with every test green. Which shards leaked changed with every new test file. `ScriptWarmup`
# loads every game script as itself first (`tools/ci/warm_GdUnitCmdTool.gd`, what CI runs). A child
# Godot runs the two suites that leaked alone, through that tool, and its output is read for the
# lines.
extends GdUnitTestSuite

const RUNNER := "res://tools/ci/warm_GdUnitCmdTool.gd"
const SUITES := [
	"res://tests/weapons/test_recut_skin.gd",
	"res://tests/world/test_drive_in_greybox.gd",
]
const LEAK_LINES := ["leaked at exit", "still in use", "Leaked instance", "Resource still in use"]


## What the child Godot printed running `suites` through `runner`, errors included.
func _run(runner: String, suites: Array) -> String:
	var arguments := PackedStringArray(
		[
			"--headless",
			"--verbose",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"-s",
			runner
		]
	)
	for suite: String in suites:
		arguments.append_array(["-a", suite])
	arguments.append_array(["-c", "--ignoreHeadlessMode"])
	var output := []
	OS.execute(OS.get_executable_path(), arguments, output, true)
	return "\n".join(PackedStringArray(output))


func _leak_lines(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in text.split("\n"):
		for needle: String in LEAK_LINES:
			if line.contains(needle):
				found.append(line.strip_edges())
				break
	return found


func test_suites_that_leaked_alone_leave_nothing_in_use_through_the_ci_runner() -> void:
	var text := _run(RUNNER, SUITES)
	assert_str(text).contains("ScriptWarmup: ")
	assert_str(text).contains("Executed test suites: (2/2)")
	assert_array(_leak_lines(text).slice(0, 5)).is_empty()


func test_the_warm_up_loads_every_script_of_the_game_folders() -> void:
	# The folders it names exist and hold scripts; a folder renamed away would shrink the warm-up
	# without a word.
	for root in ScriptWarmup.ROOTS:
		assert_bool(DirAccess.dir_exists_absolute(root)).override_failure_message(root).is_true()
	assert_int(ScriptWarmup.load_all(["res://core"])).is_greater(10)
