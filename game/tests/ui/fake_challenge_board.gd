class_name FakeChallengeBoard
extends RefCounted
## A challenge board with the shape of the real one (`ChallengeBoard`, #399): fixed sample rows
## and a swap that changes an order. For tests and captures of the menu; the menu itself reads
## only the methods below.

signal changed

var swaps: Array[int] = []
## Rows with the longest words and numbers a goal can have, to check nothing runs off the paper.
var extreme := false
var minutes_left := 372
## The feats the poster sets show as done (`poster_sets`): ids of `feats.json`.
var feats_done: Array[StringName] = []


func refresh() -> void:
	changed.emit()


func refresh_text() -> String:
	return "%d h %02d min" % [minutes_left / 60, minutes_left % 60]


func dailies() -> Array[Dictionary]:
	if extreme:
		return _extreme_rows()
	var list: Array[Dictionary] = [
		_row("Keep the projector lit through round 5", 3, 5, "short"),
		_row("Repair 20 boards on a gate", 14, 20, "medium"),
		_row("Rescue two downed players", 0, 2, "short"),
	]
	return list


func orders() -> Array[Dictionary]:
	if extreme:
		var rows := _extreme_rows()
		for slot in rows.size():
			rows[slot]["slot"] = slot
			rows[slot]["pillar"] = "light"
		return rows
	var list: Array[Dictionary] = [
		_row("Keep three circuits powered through round 6", 4, 6, "medium"),
		_row("Open every area before round 10", 3, 6, "medium"),
		_row("Earn 3,000 points with a crane weapon", 1850, 3000, "short"),
	]
	for slot in list.size():
		list[slot]["slot"] = slot
		list[slot]["pillar"] = "light"
	return list


func milestones() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if extreme:
		(
			list
			. append(
				{
					"id": "long",
					"text": "Reach 1,000,000 points and keep the generator running all night",
					"value": 999999,
					"target": 1000000,
					"rung": 4,
					"rungs": 5,
					"fraction": 1.0,
					"done": false,
				}
			)
		)
		return list
	for sample: Array in [
		["Work 50 nights", 23, 50],
		["Rescue 25 players", 12, 25],
		["Repair 500 boards", 310, 500],
		["Survive 200 rounds", 118, 200],
	]:
		(
			list
			. append(
				{
					"id": sample[0],
					"text": sample[0],
					"value": sample[1],
					"target": sample[2],
					"rung": 1,
					"rungs": 5,
					"fraction": float(sample[1]) / sample[2],
					"done": false,
				}
			)
		)
	return list


## The poster sets as the real board reads them, from a fresh profile with `feats_done` finished.
func poster_sets() -> Array[Dictionary]:
	var real := ChallengeBoard.new()
	real.catalog = ChallengeCatalog.load_default()
	real.profile = ChallengeProfile.fresh(5)
	for id in feats_done:
		real.profile.feats[id] = real.catalog.get_def(id).target
	return real.poster_sets()


func swap_order(slot: int) -> bool:
	swaps.append(slot)
	changed.emit()
	return true


func _extreme_rows() -> Array[Dictionary]:
	var long_text := "Keep every circuit powered and repair every board on every gate in the lot"
	var rows: Array[Dictionary] = [
		_row(long_text, 1000000, 1000000, "long"),
		_row("Earn points", 999999, 1000000, "long"),
	]
	return rows


func _row(text: String, progress: int, target: int, tier: String) -> Dictionary:
	return {
		"id": text,
		"text": text,
		"progress": progress,
		"target": target,
		"fraction": float(progress) / target,
		"done": progress >= target,
		"tier": tier,
		"reward": {},
	}
