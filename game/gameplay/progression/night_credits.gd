class_name NightCredits
extends RefCounted
## Who gets which crew title at the end of a night, a pure function of what `NightTally` counted
## (docs/design/progression.md#the-night-report-and-credits). The titles are handed out in the
## order of `CrewTitles`: each goes to the player with the most of its stat among those still
## without a title; a stat of zero names no one, a tie goes to the lower seat, and a player has at
## most one title. Whoever is left is an Extra, so every player is in the credits (a solo night
## too).


## One credit per player: `{player_id, id, title, reason, count}` (`count` is the stat's value, 0
## for an Extra), titled players in billing order, then the Extras in seat order.
##
## `counts` is `{player_id: {stat: count}}` (a player missing from it counted nothing) and `seats`
## `{player_id: seat}` (a missing seat is the id), for every player of the night.
static func award(
	counts: Dictionary, seats: Dictionary, crew: CrewTitles = null
) -> Array[Dictionary]:
	var list := crew if crew != null else CrewTitles.shipped()
	var order := _by_seat(counts, seats)
	var taken: Dictionary[int, bool] = {}
	var credits: Array[Dictionary] = []
	for row in list.titles:
		var winner := -1
		var best := 0
		for id in order:
			if taken.has(id):
				continue
			var mine: int = _count(counts, id, row["stat"])
			if mine > best:
				best = mine
				winner = id
		if winner >= 0:
			taken[winner] = true
			credits.append(_credit(winner, row, best))
	for id in order:
		if not taken.has(id):
			credits.append(_credit(id, list.extra, 0))
	return credits


## The players of the night, lowest seat first (then lowest id).
static func _by_seat(counts: Dictionary, seats: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for id: int in seats:
		ids.append(id)
	for id: int in counts:
		if not ids.has(id):
			ids.append(id)
	ids.sort_custom(
		func(a: int, b: int) -> bool:
			var sa := int(seats.get(a, a))
			var sb := int(seats.get(b, b))
			return a < b if sa == sb else sa < sb
	)
	return ids


static func _count(counts: Dictionary, id: int, stat: StringName) -> int:
	var mine: Dictionary = counts.get(id, {})
	return int(mine.get(stat, 0))


static func _credit(id: int, row: Dictionary, count: int) -> Dictionary:
	return {
		"player_id": id,
		"id": row["id"],
		"title": row["title"],
		"reason": row["reason"],
		"count": count,
	}
