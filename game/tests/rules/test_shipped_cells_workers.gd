extends GdUnitTestSuite
## `ShippedCells` runs the balance cells on the worker threads, and a worker that loads a file or
## fills a shared table for the first time while others do the same crashes the engine (signal 11
## in CI, #1149): the maps' table and the zombie tuning were the two the nights reached first. The
## cells are played in a child Godot, which starts cold whatever the suites before this one
## loaded, and the files the workers were first to load are counted (`shipped_cells_probe.gd`).

const PROBE := "res://tests/rules/shipped_cells_probe.gd"


func _run_probe(extra: PackedStringArray = []) -> String:
	var output := []
	var arguments := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", PROBE]
	)
	if not extra.is_empty():
		arguments.append("--")
		arguments.append_array(extra)
	OS.execute(OS.get_executable_path(), arguments, output, true)
	return "\n".join(PackedStringArray(output))


func test_the_workers_load_nothing_the_warming_left_out() -> void:
	var text := _run_probe()
	assert_str(text).override_failure_message("the probe said: " + text).contains(
		"PROBE cells=9 loaded=0 "
	)


func test_the_probe_sees_a_worker_that_loads() -> void:
	var text := _run_probe(["--cold"])
	assert_str(text).override_failure_message("the probe said: " + text).contains(
		ZombieTuning.SHIPPED_PATH
	)
	assert_str(text).contains(MapRegistry.PATHS[0])
