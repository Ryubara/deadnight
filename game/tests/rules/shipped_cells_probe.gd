extends SceneTree
## Run by `test_shipped_cells_workers.gd` in a child Godot (not a test itself), so the process is
## cold: nothing a night loads has been loaded yet. It plays one night of each cell on the worker
## threads the way `ShippedCells` does, and prints which files the workers were first to load:
## `PROBE cells=<n> loaded=<n> <paths>`. `--cold` leaves out the warming and plays the cells one
## worker after another (together they crash the engine, which is what the warming is for), to show
## the probe sees a worker that loads.

## The cells of the pace suite: both ends of the count multiplier, the maps and the match settings
## only they build.
const SPECS := [
	["average", 1],
	["strong", 1],
	["average", 4],
	["average", 1, 2.0],
	["strong", 1, 2.0],
	["average", 4, 2.0],
	["average", 1, 5.0],
	["strong", 1, 5.0],
	["average", 4, 5.0],
]
const KINDS := ["tres", "res", "gd", "tscn", "scn"]
const SKIPPED := ["res://addons", "res://.godot", "res://reports"]


func _initialize() -> void:
	var cold := OS.get_cmdline_user_args().has("--cold")
	if not cold:
		ShippedCells.warm(SPECS)
	var before := _cached()
	var cells := _one_at_a_time(SPECS) if cold else ShippedCells.play(SPECS, 1)
	var loaded: Array[String] = []
	for path in _cached():
		if not before.has(path):
			loaded.append(path)
	loaded.sort()
	print("PROBE cells=%d loaded=%d %s" % [cells.size(), loaded.size(), ",".join(loaded)])
	quit()


## The cells, each in a worker of its own that has finished before the next starts.
func _one_at_a_time(specs: Array) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.resize(specs.size())
	for index in specs.size():
		var run := func() -> void:
			results[index] = ShippedCells.cell(specs[index], RulesFixture.tuning(), 1)
		WorkerThreadPool.wait_for_task_completion(WorkerThreadPool.add_task(run))
	return results


## The project files the loader holds now.
func _cached(folder: String = "res://") -> Dictionary:
	var found := {}
	for file in DirAccess.get_files_at(folder):
		var path := folder.path_join(file)
		if KINDS.has(file.get_extension()) and ResourceLoader.has_cached(path):
			found[path] = true
	for sub in DirAccess.get_directories_at(folder):
		var path := folder.path_join(sub)
		if not SKIPPED.has(path):
			found.merge(_cached(path))
	return found
