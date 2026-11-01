# The affordability column of docs/design/map.md is computed from the tuning, not typed in: this
# recomputes it by the method the page states and fails when the page and the tuning disagree.
extends GdUnitTestSuite

const MAP_DOC := "../docs/design/map.md"
## The doors in opening order (the page's table order).
const DOORS: Array[StringName] = [
	&"door_concession", &"door_yard", &"door_booth", &"door_back_lot", &"door_road"
]
const PLAYER_COUNTS := [1, 2, 4]
## What a zombie is worth a player, on average (docs/design/rounds.md).
const POINTS_PER_ZOMBIE := 85.0
## The share of a player's points that goes on doors; the rest buys weapons, fuel and tonics.
const DOOR_SHARE := 0.5
const LAST_ROUND := 60


func test_the_affordability_column_is_what_the_tuning_gives() -> void:
	var tuning := RulesFixture.tuning()
	var rows := _table_rows()
	assert_int(rows.size()).is_equal(DOORS.size())
	var running_total := 0
	for door in DOORS:
		running_total += tuning.economy.item(door).price
		var computed: Array[String] = []
		for players: int in PLAYER_COUNTS:
			computed.append(str(_first_affordable_round(tuning.rounds, players, running_total)))
		assert_str(rows[door]).override_failure_message(String(door)).is_equal(" / ".join(computed))


## The first round at whose end one player's points, `DOOR_SHARE` of them spent on doors, cover
## `total`: the per-player share of every zombie so far at `POINTS_PER_ZOMBIE` each. No starting
## points and no round bonus.
func _first_affordable_round(rounds: RoundTuning, players: int, total: int) -> int:
	var points := 0.0
	for round_number in range(1, LAST_ROUND + 1):
		points += POINTS_PER_ZOMBIE * rounds.zombies_for_round(round_number, players) / players
		if points * DOOR_SHARE >= total:
			return round_number
	return -1


## Shop id -> the "1 / 2 / 4 players" cell of the page's table.
func _table_rows() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(MAP_DOC)
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).override_failure_message("cannot read %s" % path).is_not_null()
	var rows := {}
	for line in file.get_as_text().split("\n"):
		for door in DOORS:
			if line.begins_with("|") and line.contains("`%s`" % door):
				var cells := line.split("|")
				rows[door] = cells[cells.size() - 2].strip_edges()
	return rows
