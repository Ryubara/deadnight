class_name HudState
extends RefCounted
## Everything the HUD shows, as plain data. Network-first: it is fed rules events (plain
## dictionaries), a snapshot for a late joiner, and the local player's own readings (health, ammo,
## the prompt); it never touches a game object, a node or the rules engine itself, so a client
## builds it from what the server replicates.
##
## `changed` fires once per change (or once per batch: see `hold`), and only when something a part
## shows has changed; `is_dirty(topic)` says which part of the state did, so a part rebuilds only
## on the topics it reads. `event_applied` carries each event after the state has settled, for the
## one-shot treatments (a point popup, a banner, a hit marker).

signal changed
signal event_applied(event: Dictionary)

## The rules' event for a blow on a player (`health` left, `max_health`, `bearing` radians
## clockwise from -z where it came from); the arc turns the bearing toward where the local player
## faces (`facing`).
const PLAYER_HURT := &"player_hurt"

## The parts of the state a HUD part can depend on (see `HudPart.topics`).
const ROUND := &"round"
const OBJECTIVE := &"objective"
const TEAM := &"team"
const FUEL := &"fuel"
const HEALTH := &"health"
const AMMO := &"ammo"
const POINTS := &"points"
const PROMPT := &"prompt"
const MARKERS := &"markers"
const BOSS := &"boss"

## The tank counts as low at or under this fraction (the fuel tuning's `low_fraction`).
const LOW_FRACTION := 0.25
const PHASE_IDLE := 0
const PHASE_BREAK := 1
const PHASE_ACTIVE := 2
const PHASE_OVER := 3

var local_player_id := 1
## Which way the local player faces, radians (their yaw): the frame sets it, a blow's bearing is
## turned by it. Not a topic: nothing redraws for it.
var facing := 0.0
var health := 100.0
var max_health := 100.0
var weapon_name := ""
var ammo_magazine := 0
var ammo_reserve := 0
## The held weapon is being reloaded; false for a weapon that uses no ammunition.
var ammo_reloading := false
var ammo_used := true
## The weapon in hand and the one put away last, with the rounds of each weapon heard of (id ->
## {"ammo", "reserve"}), from the weapons' events (see `HudLoadout`). The names and the ids of the
## weapons that use no ammunition are known from the shared definitions: the client sets them.
var weapon_id: StringName = &""
var holstered_id: StringName = &""
var rounds: Dictionary[StringName, Dictionary] = {}
var weapon_names: Dictionary[StringName, String] = {}
var ammo_free: Array[StringName] = []
var points := 0
## The local player's grenades.
var grenades := 0
var round_number := 0
var phase := PHASE_IDLE
## Seconds left of the break (counted down by `tick`; parts hear of it once a second, when the
## whole second they show changes).
var break_left := 0.0
## The zombies the round began with, and those still to be killed.
var zombies_total := 0
var zombies_left := 0
var fuel := 100.0
var fuel_capacity := 100.0
var fuel_low := false
var fuel_empty := false
## Circuit id -> lit, in the order the generator lists them.
var circuits: Dictionary[StringName, bool] = {}
## Player id -> {"name": String, "downed": bool, "points": int, "grenades": int}, the local player
## included.
var team: Dictionary[int, Dictionary] = {}
## The interaction in reach: {} for none, else {"kind", "label", "cost"} (see `set_prompt`).
var prompt: Dictionary = {}
var game_over_reason := &""
## The name of the player who left last (their entry is gone from `team` by the time you hear).
var left_name := ""
## A small piece of equipment (a flare, a trap) and how many are left; "" for none. A negative
## count (`HudLoadout.NO_COUNT`) is a piece with nothing to count.
var equipment_name := ""
var equipment_count := 0
## Where the player is, and what to do next, as two lines under the round.
var area_name := ""
var objective := ""
## Markers in the world, projected by the client: each {"id", "kind" (objective or ally), "x", "y"
## (0..1 of the screen, outside that range when off-screen), "distance" in metres, "label",
## "important" (pinned to the screen edge with an arrow when off-screen)}.
var markers: Array[Dictionary] = []
## The bosses on the lot, each {"id", "type", "health", "max_health"}, in the order they came
## (from `zombie_spawn_requested` with `boss`, `zombie_damaged`, `zombie_removed`).
var bosses: Array[Dictionary] = []

## What changed since the parts last heard, and what they are being told about right now.
var _dirty: Dictionary[StringName, bool] = {}
var _current: Dictionary[StringName, bool] = {}
var _held := 0


## Circuit ids and the tank size, which both sides know from the shared tuning.
func configure(capacity: float, circuit_ids: Array[StringName], lit: Array[StringName]) -> void:
	fuel_capacity = capacity
	fuel = capacity
	circuits.clear()
	for circuit_id in circuit_ids:
		circuits[circuit_id] = lit.has(circuit_id)
	_mark(FUEL)
	_flush()


func is_local_downed() -> bool:
	return bool(team.get(local_player_id, {}).get("downed", false))


func fuel_fraction() -> float:
	return clampf(fuel / fuel_capacity, 0.0, 1.0) if fuel_capacity > 0.0 else 0.0


func can_afford(cost: int) -> bool:
	return points >= cost


## Whether `topic` is among what changed, for a part reacting to `changed`.
func is_dirty(topic: StringName) -> bool:
	return _current.has(topic)


## Holds `changed` back until the matching `release`: everything set in between reaches the parts as
## one change. Calls nest. `apply_events` does this for its batch; a network layer can hold a
## whole frame's events and readings.
func hold() -> void:
	_held += 1


func release() -> void:
	_held = maxi(_held - 1, 0)
	_flush()


# --- The local player's own readings ---


## Health is the rules' (`player_added`, `player_hurt`, `player_healed`, a snapshot); this sets it
## by hand for a tool or a capture.
func set_health(value: float, maximum: float = -1.0) -> void:
	if maximum > 0.0:
		_assign(&"max_health", maximum, HEALTH)
	_assign(&"health", clampf(value, 0.0, max_health), HEALTH)
	_flush()


func set_ammo(magazine: int, reserve: int, weapon := "", reloading := false, used := true) -> void:
	_assign(&"ammo_magazine", magazine, AMMO)
	_assign(&"ammo_reserve", reserve, AMMO)
	_assign(&"ammo_reloading", reloading, AMMO)
	_assign(&"ammo_used", used, AMMO)
	if weapon != "":
		_assign(&"weapon_name", weapon, AMMO)
	_flush()


func set_equipment(equipment: String, count: int) -> void:
	_assign(&"equipment_name", equipment, HEALTH)
	_assign(&"equipment_count", count, HEALTH)
	_flush()


## Entering a new area names it (the HUD announces a change); the objective line stays put.
func set_area(area: String, next_objective := "") -> void:
	var entered := area != area_name
	_assign(&"area_name", area, OBJECTIVE)
	_assign(&"objective", next_objective, OBJECTIVE)
	_flush()
	if entered:
		event_applied.emit({"type": &"area_entered", "area": area})


func set_markers(list: Array[Dictionary]) -> void:
	markers = list
	_mark(MARKERS)
	_flush()


func local_name() -> String:
	return str(team.get(local_player_id, {}).get("name", ""))


## A name is kept to `HudStyle.NAME_LIMIT` characters: what a part shows is a short name.
func set_player_name(player_id: int, display_name: String) -> void:
	var member := _member(player_id)
	var shown := display_name.strip_edges().left(HudStyle.NAME_LIMIT)
	if member["name"] != shown:
		member["name"] = shown
		_mark(TEAM)
		if player_id == local_player_id:
			_mark(POINTS)
	_flush()


## An interaction the player stands at. `kind` is `buy_door`, `buy_weapon`, `fill_fuel`, `repair`,
## `circuit` or `revive`; `cost` is points (0 for free); `label` names the thing and `detail` is the
## one line on what it does (a default per kind when empty).
func set_prompt(kind: StringName, label: String, cost := 0, detail := "") -> void:
	var next := {"kind": kind, "label": label, "cost": cost, "detail": detail}
	if prompt != next:
		prompt = next
		_mark(PROMPT)
	_flush()


func clear_prompt() -> void:
	if not prompt.is_empty():
		prompt = {}
		_mark(PROMPT)
		_flush()


## Counts the break down; the server's `break_started` sets it, this keeps it moving. The round
## part shows whole seconds, so it hears of the break only when the second it shows changes.
func tick(delta: float) -> void:
	if phase == PHASE_BREAK and break_left > 0.0:
		var shown := ceili(break_left)
		break_left = maxf(break_left - delta, 0.0)
		if ceili(break_left) != shown:
			_mark(ROUND)
			_flush()


# --- Rules events ---


## Mirrors one event. Unknown types are ignored: the rules grow events the HUD need not know.
func apply_event(event: Dictionary) -> void:
	var handler := _handler(StringName(event.get("type", &"")))
	if handler.is_valid():
		handler.call(event)
	_flush()
	event_applied.emit(event)


## Mirrors a batch of events, announcing one change for all of them (`event_applied` still comes
## once per event, with the state as that event left it).
func apply_events(events: Array) -> void:
	hold()
	for event in events:
		apply_event(event)
	release()


## Restores everything from `GameRules.to_dict()` (a late joiner, a reconnect); emits no events.
## Names are not in the rules, so the ones already set stay with their players.
func load_snapshot(data: Dictionary) -> void:
	hold()
	round_number = int(data.get("round", 0))
	phase = int(data.get("phase", PHASE_IDLE))
	break_left = float(data.get("break_left", 0.0))
	zombies_total = int(data.get("round_total", 0))
	var alive: Dictionary = data.get("zombies", {})
	zombies_left = alive.size() + int(data.get("spawn_left", 0))
	var names := {}
	for player_id in team:
		names[player_id] = team[player_id]["name"]
	team.clear()
	var players: Dictionary = data.get("players", {})
	for player_id in players:
		var saved: Dictionary = players[player_id]
		var member := _member(int(player_id))
		if names.has(int(player_id)):
			member["name"] = names[int(player_id)]
		member["downed"] = bool(saved.get("downed", false))
		member["points"] = int(saved.get("points", 0))
		member["grenades"] = int(saved.get("grenades", 0))
	var local: Dictionary = team.get(local_player_id, {})
	points = int(local.get("points", 0))
	grenades = int(local.get("grenades", 0))
	var mine: Dictionary = players.get(local_player_id, {})
	if mine.has("max_health"):
		_assign(&"max_health", float(mine["max_health"]), HEALTH)
		_assign(&"health", float(mine.get("health", max_health)), HEALTH)
	var generator: Dictionary = data.get("generator", {})
	_set_fuel(float(generator.get("fuel", fuel)))
	for circuit_id in generator.get("circuits", {}):
		circuits[StringName(circuit_id)] = bool(generator["circuits"][circuit_id])
	for topic in [ROUND, TEAM, FUEL, HEALTH, POINTS, PROMPT]:
		_mark(topic)
	release()


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
		&"zombie_spawn_requested":
			handler = _on_zombie_spawn_requested
		&"zombie_damaged":
			handler = _on_zombie_damaged
		&"zombie_removed":
			handler = _on_zombie_removed
		&"player_added":
			handler = _on_player_added
		&"grenade_count_changed":
			handler = _on_grenade_count_changed
		&"player_removed":
			handler = _on_player_removed
		&"player_downed":
			handler = _on_player_downed
		&"player_healed":
			handler = _on_player_healed
		&"player_revived":
			handler = func(e: Dictionary) -> void: _set_downed(int(e["player_id"]), false)
		&"points_changed":
			handler = _on_points_changed
		&"fuel_changed":
			handler = func(e: Dictionary) -> void: _set_fuel(float(e["fuel"]))
		&"fuel_low":
			handler = func(_e: Dictionary) -> void: _assign(&"fuel_low", true, FUEL)
		&"fuel_empty":
			handler = func(_e: Dictionary) -> void: _set_fuel(0.0)
		&"circuit_changed":
			handler = func(e: Dictionary) -> void:
				_set_circuit(StringName(e["circuit_id"]), bool(e["on"]))
		&"game_over":
			handler = func(e: Dictionary) -> void:
				game_over_reason = StringName(e.get("reason", ""))
		&"purchase_made":
			handler = _on_purchase_made
		&"player_hurt":
			handler = _on_player_hurt
		&"weapon_equipped", &"shot_fired", &"reload_started", &"reload_finished":
			handler = func(e: Dictionary) -> void: HudLoadout.apply(e, self)
	return handler


func _on_phase_changed(event: Dictionary) -> void:
	_assign(&"phase", int(event["phase"]), ROUND)


func _on_break_started(event: Dictionary) -> void:
	_assign(&"phase", PHASE_BREAK, ROUND)
	_assign(&"break_left", float(event["seconds"]), ROUND)


func _on_round_started(event: Dictionary) -> void:
	_assign(&"phase", PHASE_ACTIVE, ROUND)
	_assign(&"round_number", int(event["round"]), ROUND)
	_assign(&"zombies_total", int(event["zombie_count"]), ROUND)
	_assign(&"zombies_left", zombies_total, ROUND)


func _on_round_ended(_event: Dictionary) -> void:
	_assign(&"zombies_left", 0, ROUND)
	if not bosses.is_empty():
		bosses.clear()
		_mark(BOSS)


func _on_zombie_removed(event: Dictionary) -> void:
	_assign(&"zombies_left", maxi(zombies_left - 1, 0), ROUND)
	var index := _boss_index(int(event.get("zombie_id", -1)))
	if index != -1:
		bosses.remove_at(index)
		_mark(BOSS)


func _on_zombie_spawn_requested(event: Dictionary) -> void:
	if bool(event.get("boss", false)):
		(
			bosses
			. append(
				{
					"id": int(event.get("zombie_id", -1)),
					"type": StringName(event.get("zombie_type", &"")),
					"health": float(event["health"]),
					"max_health": float(event["health"]),
				}
			)
		)
		_mark(BOSS)


func _on_zombie_damaged(event: Dictionary) -> void:
	var index := _boss_index(int(event.get("zombie_id", -1)))
	if index != -1:
		bosses[index]["health"] = float(event["health"])
		if event.has("max_health"):
			bosses[index]["max_health"] = float(event["max_health"])
		_mark(BOSS)


func _boss_index(zombie_id: int) -> int:
	for index in bosses.size():
		if bosses[index]["id"] == zombie_id:
			return index
	return -1


func _on_player_added(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	var member := _member(player_id)
	if player_id == local_player_id:
		_set_local_health(event)
	if event.has("grenades"):
		member["grenades"] = int(event["grenades"])
		if player_id == local_player_id:
			_assign(&"grenades", int(event["grenades"]), HEALTH)


func _on_grenade_count_changed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_member(player_id)["grenades"] = int(event["count"])
	if player_id == local_player_id:
		_assign(&"grenades", int(event["count"]), HEALTH)


func _on_points_changed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_member(player_id)["points"] = int(event["total"])
	if player_id == local_player_id:
		_assign(&"points", int(event["total"]), POINTS)


func _on_purchase_made(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		clear_prompt()


func _on_player_hurt(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		_set_local_health(event)


func _on_player_healed(event: Dictionary) -> void:
	if int(event.get("player_id", -1)) == local_player_id:
		_set_local_health(event)


func _on_player_downed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	_set_downed(player_id, true)
	if player_id == local_player_id:
		_assign(&"health", 0.0, HEALTH)


## Takes the local player's `health` (and `max_health`, when the event has it) off an event.
func _set_local_health(event: Dictionary) -> void:
	if event.has("max_health"):
		_assign(&"max_health", float(event["max_health"]), HEALTH)
	if event.has("health"):
		_assign(&"health", clampf(float(event["health"]), 0.0, max_health), HEALTH)


func _on_player_removed(event: Dictionary) -> void:
	var player_id := int(event["player_id"])
	left_name = str(team.get(player_id, {}).get("name", "PLAYER %d" % player_id))
	if team.erase(player_id):
		_mark(TEAM)


func _set_downed(player_id: int, downed: bool) -> void:
	var member := _member(player_id)
	if member["downed"] != downed:
		member["downed"] = downed
		_mark(TEAM)


func _set_fuel(value: float) -> void:
	var was := [fuel, fuel_empty, fuel_low]
	fuel = value
	fuel_empty = fuel <= 0.0
	fuel_low = fuel > 0.0 and fuel_fraction() <= LOW_FRACTION
	if was != [fuel, fuel_empty, fuel_low]:
		_mark(FUEL)


func _set_circuit(circuit_id: StringName, on: bool) -> void:
	if not circuits.has(circuit_id) or circuits[circuit_id] != on:
		circuits[circuit_id] = on
		_mark(FUEL)


## A player's entry, made (and the party told) when there is none.
func _member(player_id: int) -> Dictionary:
	if not team.has(player_id):
		team[player_id] = {
			"name": "PLAYER %d" % player_id, "downed": false, "points": 0, "grenades": 0
		}
		_mark(TEAM)
	return team[player_id]


## Sets a field and marks `topic`, only when the value is not the one already held.
func _assign(property: StringName, value: Variant, topic: StringName) -> void:
	if get(property) != value:
		set(property, value)
		_mark(topic)


func _mark(topic: StringName) -> void:
	_dirty[topic] = true


## Tells the parts what changed, once, unless a batch is held.
func _flush() -> void:
	if _held > 0 or _dirty.is_empty():
		return
	var outer := _current
	_current = _dirty
	_dirty = {}
	changed.emit()
	_current = outer
