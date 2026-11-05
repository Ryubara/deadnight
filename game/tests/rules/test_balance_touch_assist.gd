extends GdUnitTestSuite
## The touch aim assist in the balance simulator (#286): a modelled touch player whose misses the
## assist wins back by what the thumb bot measured (`AimAssist.assisted_accuracy`). The help must
## be worth having and must not break co-op: a weak player with the full assist stays behind an
## average player without it, and an average player with it stays behind a strong one. The gate's
## own cells (`test_balance_targets.gd`) never use the assist, so the shipped targets do not move.

const NIGHTS := 60
const SEED := 4000
## [skill, assist strength]
const CELLS := [
	[&"weak", 0.0],
	[&"weak", 0.5],
	[&"weak", 1.0],
	[&"average", 0.0],
	[&"average", 1.0],
	[&"strong", 0.0],
]

var _rounds := {}


func before() -> void:
	var specs: Array = []
	for cell: Array in CELLS:
		if not specs.has([cell[0], 1]):
			specs.append([cell[0], 1])
	# The assist has a script of its own that a night without it never loads (#1156).
	ShippedCells.warm(specs, 1.0)
	var tuning := RulesFixture.tuning()
	var tunings: Array[RulesTuning] = []
	for _i in CELLS.size():
		tunings.append(tuning.duplicate(true) as RulesTuning)
	var results: Array[Dictionary] = []
	results.resize(CELLS.size())
	var run := func(index: int) -> void:
		var spec: Array = CELLS[index]
		results[index] = BalanceBatch.run_cell(
			tunings[index], spec[0], 1, NIGHTS, SEED, 0.25, 30, [], spec[1]
		)
	var task := WorkerThreadPool.add_group_task(run, CELLS.size(), -1, true, "touch assist cells")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var line: Array[String] = []
	for index in CELLS.size():
		var spec: Array = CELLS[index]
		_rounds["%s:%.1f" % spec] = BalanceBatch.mean_round(results[index])
		line.append("%s@%.1f=%.2f" % [spec[0], spec[1], _rounds["%s:%.1f" % spec]])
	print("SIM mean round reached: ", ", ".join(line))


func test_the_assist_takes_a_weak_player_further() -> void:
	assert_float(_rounds["weak:1.0"]).is_greater(_rounds["weak:0.5"])
	assert_float(_rounds["weak:0.5"]).is_greater(_rounds["weak:0.0"])


func test_a_weak_player_with_the_full_assist_stays_behind_an_average_one_without() -> void:
	assert_float(_rounds["weak:1.0"]).is_less(_rounds["average:0.0"])


func test_an_average_player_with_the_full_assist_stays_behind_a_strong_one_without() -> void:
	assert_float(_rounds["average:1.0"]).is_greater(_rounds["average:0.0"])
	assert_float(_rounds["average:1.0"]).is_less(_rounds["strong:0.0"])


func test_a_half_strength_assist_is_worth_less_than_half_the_full_assist() -> void:
	var gained: float = _rounds["weak:0.5"] - _rounds["weak:0.0"]
	var full: float = _rounds["weak:1.0"] - _rounds["weak:0.0"]
	assert_float(gained).is_less(full * 0.5)
