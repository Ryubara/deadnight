class_name HudState
extends RefCounted
## Everything the HUD shows, as plain data. Network-first: it is fed rules events (plain
## dictionaries), a snapshot for a late joiner, and the local player's own readings (health, ammo,
## the prompt); it never touches a game object, a node or the rules engine itself, so a client
## builds it from what the server replicates.
##
## `changed` fires once per applied event or setter; `event_applied` carries the event after the
## state has settled, for the one-shot treatments (a point popup, a banner, a hit marker).

signal changed
signal event_applied(event: Dictionary)

## Events that exist only for the HUD, sent beside the rules' own: the network layer turns a
## zombie's blow into this (`direction` is radians clockwise from straight ahead of the player).
const PLAYER_HURT := &"player_hurt"

## The tank counts as low at or under this fraction (the fuel tuning's `low_fraction`).
const LOW_FRACTION := 0.25
const PHASE_IDLE := 0
const PHASE_BREAK := 1
const PHASE_ACTIVE := 2
const PHASE_OVER := 3

var local_player_id := 1
var health := 100.0
var max_health := 100.0
var weapon_name := ""
var ammo_magazine := 0
var ammo_reserve := 0
var points := 0
var round_number := 0
var phase := PHASE_IDLE
## Seconds left of the break (counted down by `tick`), and zombies left in the round.
var break_left := 0.0
var zombies_total := 0
var zombies_left := 0
var fuel := 100.0
var fuel_capacity := 100.0
var fuel_low := false
var fuel_empty := false
## Circuit id -> lit, in the order the generator lists them.
var circuits: Dictionary[StringName, bool] = {}
## Player id -> {"name": String, "downed": bool, "points": int}, the local player included.
var team: Dictionary[int, Dictionary] = {}
## The interaction in reach: {} for none, else {"kind", "label", "cost"} (see `set_prompt`).
var prompt: Dictionary = {}
var game_over_reason := &""
## The name of the player who left last (their entry is gone from `team` by the time you hear).
var left_name := ""
## A small piece of equipment (a flare, a trap) and how many are left; "" for none.
var equipment_name := ""
var equipment_count := 0
## Where the player is, and what to do next, as two lines under the round.
var area_name := ""
var objective := ""
## Markers in the world, projected by the client: each {"id", "kind" (objective or ally), "x", "y"
## (0..1 of the screen, outside that range when off-screen), "distance" in metres, "label",
## "important" (pinned to the screen edge with an arrow when off-screen)}.
var markers: Array[Dictionary] = []


## Circuit ids and the tank size, which both sides know from the shared tuning.
func configure(capacity: float, circuit_ids: Array[StringName], lit: Array[StringName]) -> void:
	fuel_capacity = capacity
	fuel = capacity
	circuits.clear()
	for circuit_id in circuit_ids:
		circuits[circuit_id] = lit.has(circuit_id)
	changed.emit()


func is_local_downed() -> bool:
	return bool(team.get(local_player_id, {}).get("downed", false))


func fuel_fraction() -> float:
	return clampf(fuel / fuel_capacity, 0.0, 1.0) if fuel_capacity > 0.0 else 0.0


func can_afford(cost: int) -> bool:
	return points >= cost


# --- The local player's own readings ---


func set_health(value: float, maximum: float = -1.0) -> void:
	if maximum > 0.0:
		max_health = maximum
	health = clampf(value, 0.0, max_health)
	changed.emit()


func set_ammo(magazine: int, reserve: int, weapon := "") -> void:
	ammo_magazine = magazine
	ammo_reserve = reserve
	if weapon != "":
		weapon_name = weapon
	changed.emit()


func set_equipment(equipment: String, count: int) -> void:
	equipment_name = equipment
	equipment_count = count
	changed.emit()


## Entering a new area names it (the HUD announces a change); the objective line stays put.
func set_area(area: String, next_objective := "") -> void:
	var entered := area != area_name
	area_name = area
	objective = next_objective
	changed.emit()
	if entered:
		event_applied.emit({"type": &"area_entered", "area": area})


func set_markers(list: Array[Dictionary]) -> void:
	markers = list
	changed.emit()


func local_name() -> String:
	return str(team.get(local_player_id, {}).get("name", ""))


func set_player_name(player_id: int, display_name: String) -> void:
	_member(player_id)["name"] = display_name
	changed.emit()


## An interaction the player stands at. `kind` is `buy_door`, `buy_weapon`, `fill_fuel`, `repair` or
## `revive`; `cost` is points (0 for free); `label` names the thing and `detail` is the one line
## on what it does (a default per kind when empty).
func set_prompt(kind: StringName, label: String, cost := 0, detail := "") -> void:
	prompt = {"kind": kind, "label": label, "cost": cost, "detail": detail}
	changed.emit()


func clear_prompt() -> void:
	if not prompt.is_empty():
		prompt = {}
		changed.emit()


## Counts the break down; the server's `break_started` sets it, this keeps it moving.
func tick(delta: float) -> void:
	if phase == PHASE_BREAK and break_left > 0.0:
		break_left = maxf(break_left - delta, 0.0)
		changed.emit()


# --- Rules events ---


## Mirrors one event. Unknown types are ignored: the rules grow events the HUD need not know.
func apply_event(event: Dictionary) -> void:
	var handler := _handler(StringName(event.get("type", &"")))
	if handler.is_valid():
		handler.call(event)
	changed.emit()
	event_applied.emit(event)


func apply_events(events: Array) -> void:
	for event in events:
		apply_event(event)


## Restores everything from `GameRules.to_dict()` (a late joiner, a reconnect); emits no events.
func load_snapshot(data: Dictionary) -> void:
	round_number = int(data.get("round", 0))
	phase = int(data.get("phase", PHASE_IDLE))
	break_left = float(data.get("break_left", 0.0))
	team.clear()
	var players: Dictionary = data.get("players", {})
	for player_id in players:
		var saved: Dictionary = players[player_id]
		var member := _member(int(player_id))
		member["downed"] = bool(saved.get("downed", false))
		member["points"] = int(saved.get("points", 0))
	points = int(team.get(local_player_id, {}).get("points", 0))
	var generator: Dictionary = data.get("generator", {})
	_set_fuel(float(generator.get("fuel", fuel)))
	for circuit_id in generator.get("circuits", {}):
		circuits[StringName(circuit_id)] = bool(generator["circuits"][circuit_id])
	changed.emit()


func _handler(type: StringName) -> Callable:
	var handler := Callable()
	match type:
		&"phase_changed":
			handler = _on_phase_changed
		&"break_started":
			handler = _on_break_started
		&"round_started":
			handler = _on_round_started
		&"round_ended":
			handler = _on_round_ended
		&"zombie_removed":
			handler = _on_zombie_removed
		&"player_added":
			handler = func(e: Dictionary) -> void: _member(int(e["player_id"]))
		&"player_removed":
			handler = _on_player_removed
		&"player_downed":
			handler = func(e: Dictionary) -> void: _set_downed(int(e["player_id"]), true)
		&"player_revived":
			handler = func(e: Dictionary) -> void: _set_downed(int(e["player_id"]), false)
		&"points_changed":
			handler = _on_points_changed
		&"fuel_changed":
			handler = func(e: Dictionary) -> void: _set_fuel(float(e["fuel"]))
		&"fuel_low":
			handler = func(_e: Dictionary) -> void: fuel_low = true
		&"fuel_empty":
			handler = func(_e: Dictionary) -> void: _set_fuel(0.0)
		&"circuit_changed":
			handler = func(e: Dictionary) -> void:
				circuits[StringName(e["circuit_id"])] = bool(e["on"])
		&"game_over":
			handler = func(e: Dictionary) -> void:
				game_over_reason = StringName(e.get("reason", ""))
		&"purchase_made":
			handler = _on_purchase_made
		&"player_hurt":
			handler = _on_player_hurt
	return handler


func _on_phase_changed(event: Dictionary) -> void:
	phase = int(event["phase"])


func _on_break_started(event: Dictionary) -> void:
	phase = PHASE_BREAK
	break_left = float(event["seconds"])


func _on_round_started(event: Dictionary) -> void:
	phase = PHASE_ACTIVE
	round_number = int(event["round"])
	zombies_total = int(event["zombie_count"])
	zombies_left = zombies_total


func _on_round_ended(_event: Dictionary) -> void:
	zombies_left = 0


func _on_zombie_removed(_event: Dictionary) -> void:
	zombies_left = maxi(zombies_left - 1, 0)


func _on_points_changed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_member(player_id)["points"] = int(event["total"])
	if player_id == local_player_id:
		points = int(event["total"])


func _on_purchase_made(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		clear_prompt()


func _on_player_hurt(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id and event.has("health"):
		health = clampf(float(event["health"]), 0.0, max_health)


func _on_player_removed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	left_name = str(team.get(player_id, {}).get("name", "PLAYER %d" % player_id))
	team.erase(player_id)


func _set_downed(player_id: int, downed: bool) -> void:
	_member(player_id)["downed"] = downed


func _set_fuel(value: float) -> void:
	fuel = value
	fuel_empty = fuel <= 0.0
	fuel_low = fuel > 0.0 and fuel_fraction() <= LOW_FRACTION


func _member(player_id: int) -> Dictionary:
	if not team.has(player_id):
		team[player_id] = {"name": "PLAYER %d" % player_id, "downed": false, "points": 0}
	return team[player_id]
