class_name ShippedCells
extends RefCounted
## The balance cells of the shipped tuning, run once per process and shared by the suites that read
## them (the balance gate and the XP pace), so a second reader costs nothing. A cell is
## `[skill, players]` or `[skill, players, count_multiplier]`; its key is "average:4" or
## "average:4:x2".
## Cells run one per worker thread; each has its own copy of the tuning and its own seeded nights,
## and one night of every cell is played on this thread first (`warm`), so what the nights load is
## loaded before the threads start and the result is what one after another would give.

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
	warm(specs)
	var warmed := Time.get_ticks_msec()
	var results := play(specs, NIGHTS)
	for index in specs.size():
		_done[key_of(specs[index])] = results[index]
	var keys: Array[String] = []
	for spec: Array in specs:
		keys.append(key_of(spec))
	print(
		(
			"ShippedCells: %d cells of %d nights in %.1f s, %.1f s of it warming (%s)"
			% [
				specs.size(),
				NIGHTS,
				(Time.get_ticks_msec() - began) / 1000.0,
				(warmed - began) / 1000.0,
				", ".join(keys)
			]
		)
	)


## What a night loads or fills the first time it is asked for (the weapon definitions, the maps'
## table, the zombie tuning, the scripts and enums a rule reaches) is not safe to start from several
## threads at once: two workers filling the maps' table, or loading the tuning, together crashed
## the engine (#1149). So one night of every cell is played here, on this thread, before `play`
## starts the workers; from then on they only read.
static func warm(specs: Array) -> void:
	SimWeapons.warm()
	for spec: Array in specs:
		cell(spec, RulesFixture.tuning(), 1)


## The cells of `specs`, `nights` nights each, one per worker thread, each with a tuning of its own;
## `warm` first.
static func play(specs: Array, nights: int) -> Array[Dictionary]:
	var tunings: Array[RulesTuning] = []
	for _i in specs.size():
		tunings.append(RulesFixture.tuning())
	var results: Array[Dictionary] = []
	results.resize(specs.size())
	var run := func(index: int) -> void: results[index] = cell(specs[index], tunings[index], nights)
	var task := WorkerThreadPool.add_group_task(run, specs.size(), -1, true, "shipped cells")
	WorkerThreadPool.wait_for_group_task_completion(task)
	return results


## One cell of `nights` nights of `spec` for `tuning`.
static func cell(spec: Array, tuning: RulesTuning, nights: int) -> Dictionary:
	var settings: MatchSettings = null
	if spec.size() > 2:
		settings = MatchSettings.new()
		settings.count_multiplier = float(spec[2])
	return BalanceBatch.run_cell(
		tuning,
		StringName(spec[0]),
		spec[1],
		nights,
		SEED,
		BalanceBatch.DEFAULT_STEP,
		BalanceBatch.DEFAULT_MAX_ROUNDS,
		[],
		0.0,
		{},
		settings
	)
