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


## The scripts under `folder` (not the add-ons) that start worker tasks and do not warm first,
## as a list of paths. A script is `{path: source}`. Starting workers is `WorkerThreadPool.add_`
## and warming is `ShippedCells.warm(` (or the function itself, in `shipped_cells.gd`).
func _unwarmed(sources: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	for path: String in sources:
		var text: String = sources[path]
		if (
			text.contains("WorkerThreadPool." + "add_")
			and not text.contains("ShippedCells." + "warm(")
			and not text.contains("static func " + "warm(")
		):
			found.append(path)
	return found


func _sources(folder: String) -> Dictionary:
	var found := {}
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found[folder.path_join(file)] = FileAccess.get_file_as_string(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		found.merge(_sources(folder.path_join(sub)))
	return found


func test_every_script_in_the_tests_that_starts_workers_warms_first() -> void:
	var sources := _sources("res://tests")
	assert_bool(sources.has("res://tests/rules/test_balance_touch_assist.gd")).is_true()
	var found := _unwarmed(sources)
	(
		assert_array(found)
		. override_failure_message(
			(
				"these start worker tasks without `ShippedCells.warm` first (#1149): %s"
				% ", ".join(found)
			)
		)
		. is_empty()
	)


func test_the_scan_sees_a_group_task_that_skips_the_warming() -> void:
	var cold := "var task := WorkerThreadPool." + "add_group_task(run, 2)"
	var found := _unwarmed(
		{"res://tests/a.gd": cold, "res://tests/b.gd": "ShippedCells." + "warm(x)\n" + cold}
	)
	assert_array(found).is_equal(PackedStringArray(["res://tests/a.gd"]))


func test_the_touch_assist_cells_load_nothing_the_warming_left_out() -> void:
	var text := _run_probe(["--touch"])
	assert_str(text).override_failure_message("the probe said: " + text).contains(
		"PROBE cells=3 loaded=0 "
	)


func test_the_gate_cells_load_nothing_the_warming_left_out() -> void:
	var text := _run_probe(["--gate"])
	assert_str(text).override_failure_message("the probe said: " + text).contains(
		"PROBE cells=6 loaded=0 "
	)
