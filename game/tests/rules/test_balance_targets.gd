extends GdUnitTestSuite
## The balance gate: seeded nights through the real rules with modelled players, held against the
## ranges of `BalanceTargets`. If a tuning change moves the game out of range this fails and says
## which number, so balance is a build result and not an opinion. Read docs/design/rounds.md
## ("Balance targets") before changing a range.

## Nights per cell in CI. Seeds are fixed, so the result is the same every run on every machine.
const NIGHTS := 60
const SEED := 4000
const CELLS := [
	["weak", 1],
	["average", 1],
	["average", 2],
	["average", 4],
	["strong", 1],
]

## The shipped tuning's cells, run once for the suite: the tests that read it share them.
var _shipped: Dictionary = {}


func before() -> void:
	_shipped = _batch(RulesFixture.tuning())


## Runs every cell of the gate, one per worker thread. The cells share nothing: each has its own
## copy of the tuning and its own seeded nights, and the weapon cache is filled before the threads
## start, so the result is the same as running them one after another (a test below says so).
func _batch(tuning: RulesTuning, nights: int = NIGHTS) -> Dictionary:
	SimWeapons.warm()
	var tunings: Array[RulesTuning] = []
	for _i in CELLS.size():
		tunings.append(tuning.duplicate(true) as RulesTuning)
	var results: Array[Dictionary] = []
	results.resize(CELLS.size())
	var run := func(index: int) -> void:
		var spec: Array = CELLS[index]
		results[index] = BalanceBatch.run_cell(
			tunings[index], StringName(spec[0]), spec[1], nights, SEED
		)
	var task := WorkerThreadPool.add_group_task(run, CELLS.size(), -1, true, "balance gate cells")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var cells := {}
	for index in CELLS.size():
		cells["%s:%d" % CELLS[index]] = results[index]
	return cells


func test_the_shipped_tuning_meets_every_balance_target() -> void:
	var misses := BalanceTargets.check(_shipped)
	assert_array(misses).override_failure_message("\n".join(misses)).is_empty()


func test_better_players_and_more_players_go_further() -> void:
	var cells := _shipped
	var weak := BalanceBatch.mean_round(cells["weak:1"])
	var average := BalanceBatch.mean_round(cells["average:1"])
	var strong := BalanceBatch.mean_round(cells["strong:1"])
	assert_float(weak).is_less(average)
	assert_float(average).is_less(strong)
	assert_float(BalanceBatch.mean_round(cells["average:2"])).is_greater(average)
	assert_float(BalanceBatch.mean_round(cells["average:4"])).is_greater(
		BalanceBatch.mean_round(cells["average:2"])
	)


func test_cells_on_threads_are_the_cells_one_after_another() -> void:
	var threaded := _batch(RulesFixture.tuning(), 2)
	for spec: Array in CELLS:
		var key := "%s:%d" % spec
		var serial := BalanceBatch.run_cell(
			RulesFixture.tuning(), StringName(spec[0]), spec[1], 2, SEED
		)
		for field in ["reached", "died_in", "pressure", "earned"]:
			assert_array(threaded[key][field]).override_failure_message(key + " " + field).is_equal(
				serial[field]
			)


func test_the_gate_fails_when_the_tuning_drifts() -> void:
	# Health that compounds at 25% a round is far out of any range: the gate must say so.
	var harsh := RulesFixture.tuning()
	harsh.rounds.health_growth = 1.25
	harsh.rounds.health_knee_round = 2
	var misses := BalanceTargets.check(_batch(harsh, 20))
	assert_array(misses).is_not_empty()
	var easy := RulesFixture.tuning()
	easy.rounds.health_base = 6.0
	easy.rounds.health_step = 1.0
	easy.rounds.count_base = 2.0
	easy.rounds.count_linear = 0.3
	easy.rounds.count_quadratic = 0.0
	assert_array(BalanceTargets.check(_batch(easy, 20))).is_not_empty()


func test_zombie_health_climbs_faster_than_it_used_to_because_weapons_can_be_re_cut() -> void:
	# Health compounded at 5% a round while weapons were flat (docs/research/round-scaling.md); the
	# re-cut is what lets it climb like the original's, so the gate holds at the faster rate.
	assert_float(RulesFixture.tuning().rounds.health_growth).is_greater_equal(1.06)
	assert_array(BalanceTargets.check(_shipped)).is_empty()


func test_the_same_climb_is_a_wall_when_the_re_cut_and_the_tonic_do_nothing() -> void:
	# The same shopping at the same price, but the bench changes nothing and the tonic gives no
	# health: the gate must fail, so it is the upgrade that carries the climb and not luck.
	var inert := RulesFixture.tuning()
	inert.upgrade.damage_multiplier = 1.0
	inert.upgrade.magazine_multiplier = 1.0
	inert.upgrade.reserve_multiplier = 1.0
	inert.upgrade.price_step = 0
	inert.economy.item(&"upgrade_weapon").price = 1
	inert.economy.item(&"tonic_hearty").health_bonus = 0.0
	assert_array(BalanceTargets.check(_batch(inert))).is_not_empty()


func test_the_gate_fails_when_ammunition_is_out_of_reach() -> void:
	# Rounds nobody can pay for: players run dry, fight with the crowbar and spend nothing on ammo.
	var broke := RulesFixture.tuning()
	for item in broke.economy.items:
		if item.kind == ShopItem.Kind.AMMO:
			item.price = 1_000_000
	var misses := BalanceTargets.check(_batch(broke, 20))
	assert_array(misses).is_not_empty()
	var said := ", ".join(misses)
	assert_bool(said.contains("ammunition")).override_failure_message(said).is_true()


func test_a_night_is_the_same_every_time() -> void:
	var tuning := RulesFixture.tuning()
	var first := BalanceBatch.run_cell(tuning, &"average", 2, 5, 77)
	var second := BalanceBatch.run_cell(tuning, &"average", 2, 5, 77)
	assert_array(first["reached"]).is_equal(second["reached"])
	assert_array(first["pressure"]).is_equal(second["pressure"])


func test_the_simulator_ends_nights_and_plays_a_boss_night_and_every_type() -> void:
	var cell := BalanceBatch.run_cell(RulesFixture.tuning(), &"strong", 1, 10, 3)
	assert_int(BalanceBatch.median_round(cell)).is_greater(5)
	assert_bool(cell["special"].values().has("double_feature")).is_true()
	for type_id in ["walker", "runner", "crawler", "brute", "headliner"]:
		assert_bool(cell["ttk"].has(type_id)).override_failure_message(type_id).is_true()
