extends GdUnitTestSuite
## The pace of the whole progression, read off the balance simulator: about 8 hours of nights to
## level 55, level 10 in the first half hour or so, the first level inside a few minutes and the
## last one slow. A retune of the rounds or the economy that moves the pace, or a curve that goes
## flat, fails here (docs/design/progression.md#xp-and-the-ladder-of-55).
##
## The cells are the gate's (average solo, strong solo and average four) at count multipliers 1, 2
## and 5, so "300 or more kills a night, modifiers raise the count" is measured and not assumed.
## The three at multiplier 1 are the balance gate's own cells (`ShippedCells`, run once and shared
## when both suites run in one process); only the six with a multiplier are added.

## The cells read, and the cells the 8-hour band holds for (those that count enough kills).
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
## A night counts at least this many kills (all players) to be a night of the kind the pace is set
## for: the maintainer's "assume 300+ kills a game" (2026-11-04), read as 250 because the model's
## strong solo night counts 290.
const KILLS_FLOOR := 250.0
## Hours of nights to level 55 for a night of that kind.
const HOURS_TO_55 := [7.0, 11.5]
## Minutes to level 10 (the second map opens), and the longest to the first level.
const MINUTES_TO_10 := [20.0, 40.0]
const MINUTES_TO_2_MAX := 3.0
## Minutes for the last level, 54 to 55: the slowest of the climb.
const MINUTES_LAST := [10.0, 30.0]

var _cells: Dictionary = {}
var _tuning: RulesTuning


func before() -> void:
	_tuning = RulesFixture.tuning()
	_cells = ShippedCells.get_cells(SPECS)


func _kind_of_night() -> Array[String]:
	var keys: Array[String] = []
	for spec: Array in SPECS:
		var key := ShippedCells.key_of(spec)
		if float(BalancePace.night(_cells[key], _tuning)["kills"]) >= KILLS_FLOOR:
			keys.append(key)
	return keys


func _report(key: String) -> String:
	var cell: Dictionary = _cells[key]
	var mean := BalancePace.night(cell, _tuning)
	return (
		(
			"%s: %.0f kills, %.1f rounds, %.0f xp, %.1f min a night with menus; "
			+ "level 2 %.1f min, level 10 %.1f min, level 55 %.2f h, last level %.1f min"
		)
		% [
			key,
			mean["kills"],
			mean["rounds"],
			mean["xp"],
			mean["total_seconds"] / 60.0,
			BalancePace.minutes_to(cell, _tuning, 2),
			BalancePace.minutes_to(cell, _tuning, 10),
			BalancePace.minutes_to(cell, _tuning, LevelCurve.MAX_LEVEL) / 60.0,
			BalancePace.minutes_for(cell, _tuning, LevelCurve.MAX_LEVEL - 1),
		]
	)


func test_the_report() -> void:
	for spec: Array in SPECS:
		print("PACE ", _report(ShippedCells.key_of(spec)))


func test_there_are_nights_of_the_kind_the_pace_is_set_for() -> void:
	# Without them the bands below would hold of nothing.
	assert_int(_kind_of_night().size()).is_greater_equal(2)


func test_level_55_comes_after_about_eight_hours_of_nights() -> void:
	for key in _kind_of_night():
		var hours := BalancePace.minutes_to(_cells[key], _tuning, LevelCurve.MAX_LEVEL) / 60.0
		(
			assert_float(hours)
			. override_failure_message(
				"%s: %.2f hours to level 55\n%s" % [key, hours, _report(key)]
			)
			. is_between(HOURS_TO_55[0], HOURS_TO_55[1])
		)


func test_level_10_comes_within_the_first_half_hour_or_so() -> void:
	for key in _kind_of_night():
		var minutes := BalancePace.minutes_to(_cells[key], _tuning, 10)
		(
			assert_float(minutes)
			. override_failure_message("%s: %.1f minutes to level 10" % [key, minutes])
			. is_between(MINUTES_TO_10[0], MINUTES_TO_10[1])
		)


func test_the_first_level_comes_within_minutes_in_every_cell() -> void:
	for spec: Array in SPECS:
		var key := ShippedCells.key_of(spec)
		var minutes := BalancePace.minutes_to(_cells[key], _tuning, 2)
		(
			assert_float(minutes)
			. override_failure_message("%s: %.1f minutes to level 2" % [key, minutes])
			. is_less(MINUTES_TO_2_MAX)
		)


func test_the_last_level_is_the_slowest_and_takes_a_while() -> void:
	for key in _kind_of_night():
		var cell: Dictionary = _cells[key]
		var last := BalancePace.minutes_for(cell, _tuning, LevelCurve.MAX_LEVEL - 1)
		var first := BalancePace.minutes_for(cell, _tuning, 1)
		(
			assert_float(last)
			. override_failure_message("%s: the last level takes %.1f minutes" % [key, last])
			. is_between(MINUTES_LAST[0], MINUTES_LAST[1])
		)
		assert_float(last).is_greater(first * 4.0)


func test_the_climb_never_goes_flat_in_time() -> void:
	# A level never takes less time than the one before it, at any pace.
	for key in _kind_of_night():
		var previous := 0.0
		for level in range(1, LevelCurve.MAX_LEVEL):
			var minutes := BalancePace.minutes_for(_cells[key], _tuning, level)
			assert_float(minutes).is_greater_equal(previous)
			previous = minutes
