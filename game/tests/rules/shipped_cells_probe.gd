extends SceneTree
## Run by `test_shipped_cells_workers.gd` in a child Godot (not a test itself), so the process is
## cold: nothing a night loads has been loaded yet. It plays one night of each cell on the worker
## threads the way `ShippedCells` does, and prints which files the workers were first to load:
## `PROBE cells=<n> loaded=<n> <paths>`. `--cold` leaves out the warming and plays the cells one
## worker after another (together they crash the engine, which is what the warming is for), to show
## the probe sees a worker that loads. The cells are the pace suite's; `--gate` plays the balance
## gate's, `--touch` the touch assist suite's (with the assist on, #1156). The assist's tuning is
## loaded and copied on every call, so it is never cached for long and the probe cannot see it;
## the assist is warmed so the first call is not a worker's.

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
## The cells of the balance gate (`test_balance_targets.gd`).
const GATE_SPECS := [
	["weak", 1],
	["average", 1],
	["average", 2],
	["average", 4],
	["average", 8],
	["strong", 1],
]
## The cells of the touch assist suite (`test_balance_touch_assist.gd`), played with this assist.
const TOUCH_SPECS := [["weak", 1], ["average", 1], ["strong", 1]]
const TOUCH_ASSIST := 1.0
const KINDS := ["tres", "res", "gd", "tscn", "scn"]
const SKIPPED := ["res://addons", "res://.godot", "res://reports"]


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var cold := arguments.has("--cold")
	var specs: Array = SPECS
	var assist := 0.0
	if arguments.has("--gate"):
		specs = GATE_SPECS
	if arguments.has("--touch"):
		specs = TOUCH_SPECS
		assist = TOUCH_ASSIST
	if not cold:
		ShippedCells.warm(specs, assist)
	var before := _cached()
	var cells := _one_at_a_time(specs, assist) if cold else ShippedCells.play(specs, 1, assist)
	var loaded: Array[String] = []
	for path in _cached():
		if not before.has(path):
			loaded.append(path)
	loaded.sort()
	print("PROBE cells=%d loaded=%d %s" % [cells.size(), loaded.size(), ",".join(loaded)])
	quit()


## The cells, each in a worker of its own that has finished before the next starts.
func _one_at_a_time(specs: Array, assist: float) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.resize(specs.size())
	for index in specs.size():
		var run := func() -> void:
			results[index] = ShippedCells.cell(specs[index], RulesFixture.tuning(), 1, assist)
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
