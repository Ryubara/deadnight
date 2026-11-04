class_name NightTally
extends RefCounted
## Counts a night's events into stats, for every player in it. It hears the events a client hears
## (the rules' and the weapons') and nothing else, and reads no game object, so a server, a client
## and a test all count the same night the same way. Solo and co-op differ only in how many
## players the events name; each is counted from the events that name them.
##
## `observe(event)` answers the stats it changed as `{player_id, stat, value, delta}`: `value` is
## the night's count after the event, `delta` what it added.
##
## What a kill is credited to: the zombie's `killer_id`; its weapon is the one the shooter held
## when it died (the last `weapon_equipped`, `shot_fired` or frame reading), a blast being a
## grenade's and so no weapon's. A headshot is a kill in the `head` or `weak` zone.

var _counts: Dictionary[int, Dictionary] = {}
var _present: Dictionary[int, bool] = {}
var _held: Dictionary[int, StringName] = {}
var _fuel_items: Array[StringName]
var _changes: Array[Dictionary] = []


## The shop ids that sell fuel in `tuning` (`fuel_can` when it has none), for `_init`.
static func fuel_items_of(tuning: RulesTuning) -> Array[StringName]:
	var fuel: Array[StringName] = []
	if tuning != null:
		for item in tuning.economy.items:
			if item.kind == ShopItem.Kind.FUEL:
				fuel.append(item.id)
	if fuel.is_empty():
		fuel.append(&"fuel_can")
	return fuel


## `fuel_items` are the shop ids that sell fuel (the tuning's, so a rename needs no edit here).
func _init(fuel_items: Array[StringName] = [&"fuel_can"]) -> void:
	_fuel_items = fuel_items


## What `stat` stands at for this player this night (0 for one never seen).
func count(player_id: int, stat: StringName) -> int:
	var mine: Dictionary = _counts.get(player_id, {})
	return int(mine.get(stat, 0))


## Everyone seen this night.
func players() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_counts.keys())
	return ids


func is_present(player_id: int) -> bool:
	return _present.get(player_id, false)


## A new night: counts and who is present are forgotten; who holds what is kept (a frame says it).
func reset() -> void:
	_counts.clear()
	_present.clear()


func observe(event: Dictionary) -> Array[Dictionary]:
	_changes = []
	match event["type"]:
		&"frame":
			_on_frame(event)
		&"player_added":
			_join(int(event["player_id"]))
		&"player_removed":
			_present[int(event["player_id"])] = false
		&"weapon_equipped":
			_held[int(event["player_id"])] = StringName(event["weapon_id"])
		&"shot_fired":
			_held[int(event["shooter_id"])] = StringName(event["weapon_id"])
		&"zombie_removed":
			_on_removed(event)
		&"board_repaired":
			_add(int(event["player_id"]), ChallengeStats.BOARDS)
		&"purchase_made":
			_on_purchase(event)
		&"player_revived":
			_on_revived(event)
		&"points_changed":
			_on_points(event)
		&"round_started":
			_on_round_started(int(event["round"]))
		&"round_ended":
			for id in _present_ids():
				_add(id, ChallengeStats.ROUNDS)
		&"game_over":
			_on_game_over(int(event["round_reached"]))
	return _changes


func _on_frame(event: Dictionary) -> void:
	var players: Dictionary = event.get("players", {})
	for id: int in players:
		_join(id)
		var weapon := StringName(players[id].get("weapon", &""))
		if weapon != &"":
			_held[id] = weapon


func _join(player_id: int) -> void:
	_present[player_id] = true
	if not _counts.has(player_id):
		_counts[player_id] = {}


func _on_removed(event: Dictionary) -> void:
	var killer := int(event["killer_id"])
	if event["cause"] != &"killed" or killer < 0:
		return
	_join(killer)
	_add(killer, ChallengeStats.KILLS)
	_add(killer, ChallengeStats.type_kills(event["zombie_type"]))
	if event["boss"]:
		_add(killer, ChallengeStats.KILLS_BOSS)
	var zone: StringName = event["zone"]
	if zone == RulesAction.ZONE_HEAD or zone == RulesAction.ZONE_WEAK:
		_add(killer, ChallengeStats.KILLS_HEAD)
	if zone == RulesAction.ZONE_BLAST:
		_add(killer, ChallengeStats.KILLS_BLAST)
		return
	if event["melee"]:
		_add(killer, ChallengeStats.KILLS_MELEE)
	if _held.has(killer):
		_add(killer, ChallengeStats.weapon_kills(_held[killer]))


func _on_purchase(event: Dictionary) -> void:
	var id := int(event["player_id"])
	var item: StringName = event["item_id"]
	_add(id, ChallengeStats.BUYS)
	if String(item).begins_with("door_"):
		_add(id, ChallengeStats.DOORS)
	if _fuel_items.has(item):
		_add(id, ChallengeStats.FUEL_CANS)


func _on_revived(event: Dictionary) -> void:
	var reviver := int(event.get("reviver_id", 0))
	if reviver > 0 and reviver != int(event["player_id"]):
		_join(reviver)
		_add(reviver, ChallengeStats.REVIVES)


func _on_points(event: Dictionary) -> void:
	if int(event["delta"]) > 0 and event["reason"] != &"start":
		_add(int(event["player_id"]), ChallengeStats.POINTS, int(event["delta"]))


func _on_round_started(round_number: int) -> void:
	for id in _present_ids():
		_best(id, ChallengeStats.ROUND, round_number)


func _on_game_over(round_reached: int) -> void:
	for id in _present_ids():
		_best(id, ChallengeStats.ROUND, round_reached)
		_add(id, ChallengeStats.NIGHTS)


func _present_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _present:
		if _present[id]:
			ids.append(id)
	return ids


func _add(player_id: int, stat: StringName, amount: int = 1) -> void:
	if amount == 0:
		return
	var mine: Dictionary = _counts.get(player_id, {})
	mine[stat] = int(mine.get(stat, 0)) + amount
	_counts[player_id] = mine
	_changes.append({"player_id": player_id, "stat": stat, "value": mine[stat], "delta": amount})


func _best(player_id: int, stat: StringName, value: int) -> void:
	var before := count(player_id, stat)
	if value > before:
		var mine: Dictionary = _counts.get(player_id, {})
		mine[stat] = value
		_counts[player_id] = mine
		_changes.append(
			{"player_id": player_id, "stat": stat, "value": value, "delta": value - before}
		)
