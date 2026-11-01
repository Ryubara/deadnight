class_name BalanceBatch
extends RefCounted
## Many seeded nights of one cell (one skill level, one player count), added up into the numbers
## the report and the CI targets read. Everything is by round, indexed from 1.

const DEFAULT_STEP := 0.25
const DEFAULT_MAX_ROUNDS := 30
## Added to both sides of a spike ratio, so a round whose neighbours were all but untouched does not
## make an enormous ratio out of nothing.
const SPIKE_FLOOR := 0.05


## Runs `nights` nights with seeds `seed_start`, `seed_start + 1`, ... and returns the cell.
## `reached[r]` is how many nights started round r; `died_in[r]` how many ended in it; the other
## per-round lists are sums over the nights that reached the round (divide by `reached`).
static func run_cell(
	tuning: RulesTuning,
	skill_id: StringName,
	players: int,
	nights: int,
	seed_start: int,
	step: float = DEFAULT_STEP,
	max_rounds: int = DEFAULT_MAX_ROUNDS
) -> Dictionary:
	var cell := {
		"skill": skill_id,
		"players": players,
		"nights": nights,
		"seed_start": seed_start,
		"step": step,
		"max_rounds": max_rounds,
		"reached": _zeros(max_rounds + 1),
		"died_in": _zeros(max_rounds + 1),
		"damage": _zeros(max_rounds + 1),
		"pressure": _zeros(max_rounds + 1),
		"earned": _zeros(max_rounds + 1),
		"duration": _zeros(max_rounds + 1),
		"special": {},
		"ttk": {},
		"spent_on": {},
		"spent_total": 0.0,
		"earned_total": 0.0,
	}
	var skill := SimSkill.named(skill_id)
	for n in nights:
		var sim := NightSim.new(tuning, skill, players, seed_start + n, step)
		_add(cell, sim.run(max_rounds), sim.rules)
	return cell


static func _add(cell: Dictionary, night: Dictionary, rules: GameRules) -> void:
	var rounds: Dictionary = night["rounds"]
	for r: int in rounds:
		var record: Dictionary = rounds[r]
		cell["reached"][r] += 1
		cell["damage"][r] += record.get("damage", 0.0)
		cell["pressure"][r] += record.get("pressure", 0.0)
		cell["earned"][r] += record.get("earned", 0.0)
		cell["duration"][r] += record.get("duration", 0.0)
		cell["special"][r] = String(record["special"])
	if night["died"]:
		cell["died_in"][night["rounds_reached"]] += 1
	for type_id: StringName in night["ttk"]:
		var sum: Array = cell["ttk"].get(String(type_id), [0, 0.0, 0])
		for i in 3:
			sum[i] += night["ttk"][type_id][i]
		cell["ttk"][String(type_id)] = sum
	for item_id: StringName in night["spent_on"]:
		cell["spent_on"][String(item_id)] = (
			cell["spent_on"].get(String(item_id), 0) + night["spent_on"][item_id]
		)
	var players := float(rules.players.size())
	for player: PlayerState in rules.players.values():
		cell["spent_total"] += float(player.points_spent) / players
		cell["earned_total"] += float(player.points_earned) / players


static func _zeros(count: int) -> Array:
	var zeros := []
	zeros.resize(count)
	zeros.fill(0.0)
	return zeros


# --- Reading a cell ---


## The share of nights that started round `r` (1 at round 1).
static func survival(cell: Dictionary, r: int) -> float:
	return float(cell["reached"][r]) / float(cell["nights"])


## Of the nights that started round `r`, the share that ended in it.
static func hazard(cell: Dictionary, r: int) -> float:
	var reached: float = cell["reached"][r]
	return float(cell["died_in"][r]) / reached if reached > 0.0 else 0.0


## How close the round came to downing a player: the mean, over the nights that reached it, of the
## health a player lost at their worst moment (0 untouched, 1 downed). The measure of difficulty.
static func threat(cell: Dictionary, r: int) -> float:
	var reached: float = cell["reached"][r]
	return float(cell["pressure"][r]) / reached if reached > 0.0 else 0.0


## The mean of the last round a night started (the round it ended in, or the cap).
static func mean_round(cell: Dictionary) -> float:
	var total := 0.0
	for r in range(1, cell["reached"].size()):
		total += float(cell["reached"][r])
	return total / float(cell["nights"])


## The round that half the nights reach.
static func median_round(cell: Dictionary) -> int:
	var best := 0
	for r in range(1, cell["reached"].size()):
		if survival(cell, r) >= 0.5:
			best = r
	return best


## How much harder round `r` is than its neighbours: its threat over the mean of the rounds
## either side (only the one before when it is the last round anyone reached), each with
## `SPIKE_FLOOR` added.
static func spike(cell: Dictionary, r: int) -> float:
	var before := threat(cell, r - 1)
	var after := threat(cell, r + 1) if r + 1 < cell["reached"].size() else 0.0
	var around := (before + after) / 2.0 if after > 0.0 else before
	return (threat(cell, r) + SPIKE_FLOOR) / (around + SPIKE_FLOOR)
