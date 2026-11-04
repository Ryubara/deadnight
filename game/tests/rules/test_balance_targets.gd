extends GdUnitTestSuite
## The balance gate: seeded nights through the real rules with modelled players, held against the
## ranges of `BalanceTargets`. If a tuning change moves the game out of range this fails and says
## which number, so balance is a build result and not an opinion. Read docs/design/rounds.md
## ("Balance targets") before changing a range.

## Nights per cell in CI. Seeds are fixed, so the result is the same every run on every machine.
const NIGHTS := 60
const SEED := 4000
## How many rounds further the re-cut and the tonic must carry the good and the many nights. It
## was a whole round at 1,500 and a step; at 5,000 flat (#909) the average nights of 4 and 8 players
## gain 0.95 and 1.0, because the re-cut comes later. 0.3 since the House Pistol start (#898): the
## strong solo night gains 0.38 (14.08 with, 13.70 without; 60 nights a cell reads a mean to about
## 0.3 either way) because the opening is slower and the re-cut comes later still; the two party
## cells still gain more than 0.5.
const CLIMB_CARRIED := 0.3
## Nights a cell is read again with when its climb gap misses at NIGHTS. The gap is a difference of
## two means of 60 seeded nights, each a few tenths of a round loose, so a change that only shifts
## the random draws (the perk drink, #912) moved average:4 from 0.82 to 0.43 where 300 nights say
## 0.72 and 0.66. A miss is judged again on the longer read; a cell that passes at 60 is not.
const CLIMB_CONFIRM_NIGHTS := 300
const CELLS := [
	["weak", 1],
	["average", 1],
	["average", 2],
	["average", 4],
	["average", 8],
	["strong", 1],
]

## The cells a test that only needs to see the gate fail (or a climb carried) runs, not all six.
## A night costs about what its players cost, so the 8 and 4 player cells are most of a batch (at 20
## nights: 9.1 s and 4.1 s of the 18.6 s of the six cells; the solo and duo cells 0.4 to 2.0 s).
## The small cells miss their ranges by whole rounds when the game drifts, which is all a "the gate
## can fail" test needs to see (at 20 nights the harsh game's solo median is 6 against 8 to 14).
const SOLO_CELLS := [["average", 1], ["average", 2]]
const WEAK_AND_SOLO_CELLS := [["weak", 1], ["average", 1]]
## The cells the inert-upgrade test reads: the 4 player night and the strong solo night, where the
## upgrade carries the least of the climb (0.53 and 0.80 rounds against the 0.3 asked). The 8 player
## night carries 1.70, the most of the three, and costs half as much again as the other two.
const CLIMB_CELLS := [["average", 4], ["strong", 1]]

## The shipped tuning's cells, run once for the suite: the tests that read it share them.
var _shipped: Dictionary = {}


func before() -> void:
	_shipped = _batch(RulesFixture.tuning())


## Runs every cell of the gate, one per worker thread. The cells share nothing: each has its own
## copy of the tuning and its own seeded nights, and the weapon cache is filled before the threads
## start, so the result is the same as running them one after another (a test below says so).
func _batch(tuning: RulesTuning, nights: int = NIGHTS, specs: Array = CELLS) -> Dictionary:
	SimWeapons.warm()
	var tunings: Array[RulesTuning] = []
	for _i in specs.size():
		tunings.append(tuning.duplicate(true) as RulesTuning)
	var results: Array[Dictionary] = []
	results.resize(specs.size())
	var run := func(index: int) -> void:
		var spec: Array = specs[index]
		results[index] = BalanceBatch.run_cell(
			tunings[index], StringName(spec[0]), spec[1], nights, SEED
		)
	var task := WorkerThreadPool.add_group_task(run, specs.size(), -1, true, "balance gate cells")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var cells := {}
	for index in specs.size():
		cells["%s:%d" % specs[index]] = results[index]
	return cells


## What the gate says about the cells of `specs` only (the ones it was not given are not misses of
## the tuning): a "the gate can fail" test reads these.
func _misses_in(tuning: RulesTuning, nights: int, specs: Array) -> PackedStringArray:
	var said := PackedStringArray()
	for miss in BalanceTargets.check(_batch(tuning, nights, specs)):
		if not miss.begins_with("no cell "):
			said.append(miss)
	return said


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
	assert_float(BalanceBatch.mean_round(cells["average:8"])).is_greater(
		BalanceBatch.mean_round(cells["average:4"])
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
	assert_array(_misses_in(harsh, 20, SOLO_CELLS)).is_not_empty()
	var easy := RulesFixture.tuning()
	easy.rounds.health_base = 6.0
	easy.rounds.health_step = 1.0
	easy.rounds.count_base = 2.0
	easy.rounds.count_linear = 0.3
	easy.rounds.count_quadratic = 0.0
	assert_array(_misses_in(easy, 20, WEAK_AND_SOLO_CELLS)).is_not_empty()


func test_zombie_health_climbs_faster_than_it_used_to_because_weapons_can_be_re_cut() -> void:
	# Health compounded at 5% a round while weapons were flat (docs/research/round-scaling.md); the
	# re-cut is what lets it climb like the original's, so the gate holds at the faster rate.
	assert_float(RulesFixture.tuning().rounds.health_growth).is_greater_equal(1.06)
	assert_array(BalanceTargets.check(_shipped)).is_empty()


func test_the_same_climb_goes_less_far_when_the_re_cut_and_the_tonic_do_nothing() -> void:
	# The same shopping at the same price, but the bench changes nothing and the tonic gives no
	# health: the good and the many nights must end rounds sooner, so it is the upgrade that carries
	# part of the climb and not luck. (Before the hit zones followed the bodies, #745, this batch
	# fell outside the ranges; the bots now land most shots on the head and take fewer blows, so the
	# climb alone is no longer a wall, and the test reads how much of it the upgrade carries.)
	var inert := RulesFixture.tuning()
	for profile in inert.upgrade.profiles:
		profile.damage_multiplier = 1.0
		profile.magazine_multiplier = 1.0
		profile.reserve_multiplier = 1.0
		profile.fire_interval = 0.0
		profile.element = null
	inert.economy.item(&"upgrade_weapon").price = 1
	inert.economy.item(&"tonic_hearty").health_bonus = 0.0
	var without := _batch(inert, NIGHTS, CLIMB_CELLS)
	for key in ["average:4", "strong:1"]:
		var shipped_mean := BalanceBatch.mean_round(_shipped[key])
		var inert_mean := BalanceBatch.mean_round(without[key])
		if inert_mean >= shipped_mean - CLIMB_CARRIED:
			var cell: Array = _cell_of(key)
			var means := _confirm(inert, cell)
			shipped_mean = means[0]
			inert_mean = means[1]
		(
			assert_float(inert_mean)
			. override_failure_message(
				(
					"%s: %.2f rounds without the re-cut and the tonic, %.2f with"
					% [key, inert_mean, shipped_mean]
				)
			)
			. is_less(shipped_mean - CLIMB_CARRIED)
		)


## The mean round of one cell on the longer read, with the shipped tuning and with `inert`, the two
## arms side by side on worker threads.
func _confirm(inert: RulesTuning, cell: Array) -> Array[float]:
	SimWeapons.warm()
	var tunings: Array[RulesTuning] = [RulesFixture.tuning(), inert.duplicate(true) as RulesTuning]
	var means: Array[float] = [0.0, 0.0]
	var run := func(arm: int) -> void:
		var result := BalanceBatch.run_cell(
			tunings[arm], StringName(cell[0]), cell[1], CLIMB_CONFIRM_NIGHTS, SEED
		)
		means[arm] = BalanceBatch.mean_round(result)
	var task := WorkerThreadPool.add_group_task(run, 2, -1, true, "balance climb read")
	WorkerThreadPool.wait_for_group_task_completion(task)
	return means


## The CELLS entry a result key ("average:4") names.
func _cell_of(key: String) -> Array:
	for cell: Array in CELLS:
		if "%s:%d" % cell == key:
			return cell
	return []


func test_the_gate_fails_when_ammunition_is_out_of_reach() -> void:
	# Rounds nobody can pay for: players run dry, fight with the crowbar and spend nothing on ammo.
	var broke := RulesFixture.tuning()
	for item in broke.economy.items:
		if item.kind == ShopItem.Kind.AMMO:
			item.price = 1_000_000
	var misses := _misses_in(broke, 20, SOLO_CELLS)
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
