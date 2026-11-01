class_name BalanceTargets
extends RefCounted
## The numbers the tuning must hold, as ranges, and the check that reports which ones it misses.
## docs/design/rounds.md explains each; a CI test runs `check` on a seeded batch of nights, so a
## tuning change that moves the game out of range fails the build and not a playtest.
##
## Every range is a statement about nights played by the modelled players of `SimSkill`, not about
## people: when the model or the weapons change, the report is read again and the ranges with it.

## Median round (the round half the nights reach), by skill and players: [low, high].
const MEDIAN_ROUND := {
	"weak:1": [4, 9],
	"average:1": [10, 14],
	"average:2": [11, 16],
	"average:4": [12, 17],
	"strong:1": [12, 18],
}
## The first rounds are a lesson, not a test: this share of average solo nights clears round 4.
const MIN_SURVIVE_ROUND_4 := 0.85
## A special round kills at most this share of the nights that reach it (a spike, not a wall). Only
## the first ones are held to it: by the third boss night the ordinary rounds are the wall for
## average players, and the median round ranges govern.
const MAX_SPECIAL_DEATH_RATE := 0.4
const LEARNING_ROUNDS := 10
## Even weak players are not walled by the first boss night: at most this share of them die in it.
const MAX_WEAK_FIRST_BOSS_DEATH := 0.85
## A boss night is at least this much harder than its neighbours (BalanceBatch.spike).
const MIN_BOSS_SPIKE := 1.5
## Time under fire to kill one, seconds, solo average: [low, high].
const TIME_TO_KILL := {
	"walker": [0.5, 3.0],
	"runner": [0.2, 2.0],
	"brute": [3.0, 12.0],
	"headliner": [8.0, 30.0],
}
## Points spent over points earned, solo average: players spend a good part, never all.
const SPEND_SHARE := [0.3, 0.9]


## `cells` maps "skill:players" to a cell of `BalanceBatch.run_cell`. Returns what is out of range,
## one sentence each; empty when all is well. A cell that is missing is a failure.
static func check(cells: Dictionary) -> PackedStringArray:
	var misses := PackedStringArray()
	for key: String in MEDIAN_ROUND:
		if not cells.has(key):
			misses.append("no cell %s" % key)
			continue
		var range: Array = MEDIAN_ROUND[key]
		var median := BalanceBatch.median_round(cells[key])
		if median < range[0] or median > range[1]:
			misses.append(
				"median round %s is %d, wanted %d to %d" % [key, median, range[0], range[1]]
			)
	if not cells.has("average:1"):
		return misses
	var solo: Dictionary = cells["average:1"]
	if BalanceBatch.survival(solo, 5) < MIN_SURVIVE_ROUND_4:
		misses.append(
			(
				"only %.0f%% of average solo nights clear round 4"
				% (BalanceBatch.survival(solo, 5) * 100.0)
			)
		)
	for key: String in cells:
		var cell: Dictionary = cells[key]
		if cell["skill"] != &"average":
			continue
		for r: int in cell["special"]:
			if (
				cell["special"][r] == ""
				or r > LEARNING_ROUNDS
				or BalanceBatch.survival(cell, r) < 0.1
			):
				continue
			var death := BalanceBatch.hazard(cell, r)
			if death > MAX_SPECIAL_DEATH_RATE:
				misses.append(
					(
						"%s round %d (%s) kills %.0f%%, wanted at most %.0f%%"
						% [
							key,
							r,
							cell["special"][r],
							death * 100.0,
							MAX_SPECIAL_DEATH_RATE * 100.0
						]
					)
				)
	var boss_round := 0
	for r: int in solo["special"]:
		if solo["special"][r].begins_with("double") and (boss_round == 0 or r < boss_round):
			boss_round = r
	if boss_round > 0 and BalanceBatch.spike(solo, boss_round) < MIN_BOSS_SPIKE:
		misses.append(
			(
				"the boss night (round %d) is only x%.2f its neighbours, wanted x%.1f"
				% [boss_round, BalanceBatch.spike(solo, boss_round), MIN_BOSS_SPIKE]
			)
		)
	if cells.has("weak:1") and boss_round > 0:
		var weak_death := BalanceBatch.hazard(cells["weak:1"], boss_round)
		if weak_death > MAX_WEAK_FIRST_BOSS_DEATH:
			misses.append(
				(
					"the boss night kills %.0f%% of weak solo nights, wanted at most %.0f%%"
					% [weak_death * 100.0, MAX_WEAK_FIRST_BOSS_DEATH * 100.0]
				)
			)
	for type_id: String in TIME_TO_KILL:
		var sums: Array = solo["ttk"].get(type_id, [0, 0.0, 0])
		if sums[0] == 0:
			misses.append("no %s was killed in the batch" % type_id)
			continue
		var seconds: float = sums[1] / sums[0]
		var bounds: Array = TIME_TO_KILL[type_id]
		if seconds < bounds[0] or seconds > bounds[1]:
			misses.append(
				(
					"time to kill a %s is %.2f s, wanted %.1f to %.1f"
					% [type_id, seconds, bounds[0], bounds[1]]
				)
			)
	var share: float = solo["spent_total"] / maxf(solo["earned_total"], 1.0)
	if share < SPEND_SHARE[0] or share > SPEND_SHARE[1]:
		misses.append(
			(
				"average solo spends %.0f%% of what it earns, wanted %.0f to %.0f%%"
				% [share * 100.0, SPEND_SHARE[0] * 100.0, SPEND_SHARE[1] * 100.0]
			)
		)
	return misses
