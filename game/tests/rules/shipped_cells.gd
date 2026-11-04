class_name ShippedCells
extends RefCounted
## The balance cells of the shipped tuning, run once per process and shared by the suites that read
## them (the balance gate and the XP pace), so a second reader costs nothing. A cell is
## `[skill, players]` or `[skill, players, count_multiplier]`; its key is "average:4" or
## "average:4:x2".
## Cells run one per worker thread; each has its own copy of the tuning and its own seeded nights,
## and the weapon cache is filled before the threads start, so the result is what one after another
## would give.

const NIGHTS := 60
const SEED := 4000

static var _done: Dictionary = {}


static func key_of(spec: Array) -> String:
	var multiplier := float(spec[2]) if spec.size() > 2 else 1.0
	var text := "%s:%d" % [spec[0], spec[1]]
	return text if is_equal_approx(multiplier, 1.0) else "%s:x%s" % [text, str(multiplier)]


## The cells of `specs` for the shipped tuning, run now when they have not been.
static func get_cells(specs: Array) -> Dictionary:
	var missing: Array = []
	for spec: Array in specs:
		if not _done.has(key_of(spec)):
			missing.append(spec)
	if not missing.is_empty():
		_run(missing)
	var cells := {}
	for spec: Array in specs:
		cells[key_of(spec)] = _done[key_of(spec)]
	return cells


static func _run(specs: Array) -> void:
	var began := Time.get_ticks_msec()
	SimWeapons.warm()
	var tunings: Array[RulesTuning] = []
	for _i in specs.size():
		tunings.append(RulesFixture.tuning())
	var results: Array[Dictionary] = []
	results.resize(specs.size())
	var run := func(index: int) -> void:
		var spec: Array = specs[index]
		var settings: MatchSettings = null
		if spec.size() > 2:
			settings = MatchSettings.new()
			settings.count_multiplier = float(spec[2])
		results[index] = BalanceBatch.run_cell(
			tunings[index],
			StringName(spec[0]),
			spec[1],
			NIGHTS,
			SEED,
			BalanceBatch.DEFAULT_STEP,
			BalanceBatch.DEFAULT_MAX_ROUNDS,
			[],
			0.0,
			{},
			settings
		)
	var task := WorkerThreadPool.add_group_task(run, specs.size(), -1, true, "shipped cells")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for index in specs.size():
		_done[key_of(specs[index])] = results[index]
	var keys: Array[String] = []
	for spec: Array in specs:
		keys.append(key_of(spec))
	print(
		(
			"ShippedCells: %d cells of %d nights in %.1f s (%s)"
			% [specs.size(), NIGHTS, (Time.get_ticks_msec() - began) / 1000.0, ", ".join(keys)]
		)
	)
