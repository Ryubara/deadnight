class_name GrenadeServer
extends RefCounted
## The server's side of grenades: who may cook and throw, the fuse, the flight, the blast, and what
## the rules hear about it. A plain `RefCounted` like `GameRules` and `CombatServer`: it changes
## only through `apply(action)` (a dictionary from `GrenadeAction`) and answers with the events
## that action caused, plain dictionaries. No node, no peer, no clock of its own, no global random,
## so a replay of the same actions gives the same events. Single-player runs this same object.
##
## Time is `GrenadeAction.tick`. The world is two Callables: `world_cast` for the flight (see
## `GrenadeState`) and `world_ray` for the cover line checks (the weapons' `WorldProbe`, walls and
## props only: a person is no cover).
##
## The server believes itself, not the client. Where a player stands comes from the host
## (`GrenadeAction.players`); the grenade leaves from that player's hand height, and a hand the
## client reports is kept only within `GrenadeDef.hand_reach` of it (further out, it is pulled in).
## A client velocity is clamped to `max_carrier_speed`; a hand or velocity that is not a finite
## number is refused. Which zombies are alive is the rules' to say. A player who goes down (or
## leaves) with the pin out drops the grenade at their feet, fuse still running.
##
## The state (cooks, grenades in flight, the clock) is `to_dict` / `from_dict`, kept beside the
## rules' snapshot: restore the rules first, then this.
##
## A blast becomes ONE `RulesAction.explosion` for the thrower with every zombie it reached, in id
## order: the rules own the zombies' health, pay, kill and decide who is crippled. The rules'
## events follow the grenade's own in the answer.
##
## Events (fields besides `type`):
##   cook_started: player_id, seq, fuse
##   cook_rejected: player_id, seq, reason (`bad_hand`, `unknown_player`, or the rules' reason:
##     `no_grenades`, `wrong_phase`, `player_downed`, ...)
##   throw_rejected: player_id, seq, reason (`player_downed`, `unknown_player`, `not_cooking`,
##     `bad_aim`, `bad_hand`, `bad_velocity`)
##   grenade_thrown: grenade_id, thrower_id, seq, position, velocity, fuse_left, underarm, cooked
##   grenade_dropped: grenade_id, thrower_id, position, velocity (zero), fuse_left, cooked (the
##     grenade of a player who went down or left)
##   grenade_bounced: grenade_id, point, speed, wall, zombie_id (-1 off the world)
##   grenade_struck: grenade_id, zombie_id, state (the grenade's `to_dict` at the end of the step in
##     which a zombie stopped it: a client flies its copy without the dead, and takes this as truth)
##   grenade_exploded: grenade_id, thrower_id, point, core_radius, radius, in_hand
##   blast_hit: grenade_id, target_id, damage, leg_damage, exposure, distance, impulse, stun
##   player_blasted: grenade_id, thrower_id, player_id, damage (a share of the player's
##     `max_health`, `PlayerBlast`: all of it in the hand and within `player_full_radius`, less to
##     nothing at the blast radius, none behind a wall), share (0 to 1), distance, impulse, stun,
##     own (the thrower's), in_hand (the thrower's, and it went off in the hand)

signal event_emitted(event: Dictionary)

## What `_init` reports when there is no way to cast the flight: said once, not on every tick.
const NO_WORLD_CAST_ERROR := "GrenadeServer: no valid world_cast, grenades fly over open ground"
const SNAPSHOT_VERSION := 1
## The health bar a blast takes a share of when the rules do not say (a server with no rules).
const DEFAULT_MAX_HEALTH := 100.0
## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"version": TYPE_INT,
	"def_id": TYPE_STRING,
	"now": TYPE_FLOAT,
	"next_id": TYPE_INT,
	"cooks": TYPE_DICTIONARY,
	"grenades": TYPE_ARRAY,
	"targets": TYPE_DICTIONARY,
	"players": TYPE_DICTIONARY,
}
const COOK_KEYS := {
	"started": TYPE_FLOAT,
	"seq": TYPE_INT,
	"offset": TYPE_VECTOR3,
	"hand": TYPE_VECTOR3,
}
const TARGET_KEYS := {"pos": TYPE_VECTOR3, "yaw": TYPE_FLOAT}

## Clock, seconds. Only `tick` moves it.
var now: float = 0.0
var def: GrenadeDef
var rules: GameRules
var world_cast: Callable
var world_ray: Callable
var _cooks: Dictionary[int, Dictionary] = {}
var _grenades: Array[GrenadeState] = []
var _next_id: int = 1
var _targets: Dictionary[int, Dictionary] = {}
var _players: Dictionary[int, Vector3] = {}
var _events: Array[Dictionary] = []


func _init(
	p_def: GrenadeDef,
	p_rules: GameRules = null,
	p_world_cast: Callable = Callable(),
	p_world_ray: Callable = Callable()
) -> void:
	def = p_def
	rules = p_rules
	world_cast = p_world_cast
	world_ray = p_world_ray
	if not world_cast.is_valid():
		push_error(NO_WORLD_CAST_ERROR)


## The one way in. Returns the events the action caused, in order.
func apply(action: Dictionary) -> Array[Dictionary]:
	_events = []
	_dispatch(action)
	var caused := _events
	for event in caused:
		event_emitted.emit(event)
	return caused


# --- Queries (read-only) ---


func grenades_in_flight() -> int:
	return _grenades.size()


func is_cooking(player_id: int) -> bool:
	return _cooks.has(player_id)


## Seconds a player has held the pin, or -1.0 when not cooking.
func cooked_for(player_id: int) -> float:
	return now - _cooks[player_id]["started"] if _cooks.has(player_id) else -1.0


## The grenade with this id, or null once it has gone off.
func grenade(grenade_id: int) -> GrenadeState:
	for candidate in _grenades:
		if candidate.id == grenade_id:
			return candidate
	return null


# --- Snapshot ---


## Everything the server holds, as plain Variant data (exact as bytes, see `to_bytes`). The def
## and the rules are not in it: both sides load the same def (its id is checked), and the rules
## have their own snapshot, which also says which zombies are alive.
func to_dict() -> Dictionary:
	var cooks := {}
	for player_id in _cooks:
		cooks[player_id] = _cooks[player_id].duplicate()
	var flying: Array[Dictionary] = []
	for grenade_state in _grenades:
		flying.append(grenade_state.to_dict())
	var targets := {}
	for target_id in _targets:
		targets[target_id] = _targets[target_id].duplicate()
	return {
		"version": SNAPSHOT_VERSION,
		"def_id": String(def.id),
		"now": now,
		"next_id": _next_id,
		"cooks": cooks,
		"grenades": flying,
		"targets": targets,
		"players": _players.duplicate(),
	}


## The snapshot as bytes (`var_to_bytes`), exact in every number and key.
func to_bytes() -> PackedByteArray:
	return var_to_bytes(to_dict())


## The snapshot as a base64 string, the form to put inside JSON.
func to_wire() -> String:
	return Marshalls.raw_to_base64(to_bytes())


## Restores from `to_bytes()`. Returns what `from_dict` returns.
func from_bytes(bytes: PackedByteArray) -> StringName:
	var data: Variant = bytes_to_var(bytes)
	if typeof(data) != TYPE_DICTIONARY:
		return GameRules.RESTORE_MALFORMED
	return from_dict(data)


## Restores from `to_wire()`. Returns what `from_dict` returns.
func from_wire(wire: String) -> StringName:
	return from_bytes(Marshalls.base64_to_raw(wire))


## Replaces the server's state with a snapshot. Emits no events. Returns `&""` when it worked, else
## why it did not (`GameRules.RESTORE_*`) with the server left untouched.
func from_dict(data: Dictionary) -> StringName:
	if not _has_keys(data, SNAPSHOT_KEYS):
		return GameRules.RESTORE_MALFORMED
	if data["version"] != SNAPSHOT_VERSION:
		return GameRules.RESTORE_BAD_VERSION
	if data["def_id"] != String(def.id):
		return GameRules.RESTORE_WRONG_TUNING
	if not _snapshot_parts_fit(data):
		return GameRules.RESTORE_MALFORMED
	now = data["now"]
	_next_id = data["next_id"]
	_cooks.clear()
	for player_id: int in data["cooks"]:
		_cooks[player_id] = (data["cooks"][player_id] as Dictionary).duplicate()
	_grenades.clear()
	for entry: Dictionary in data["grenades"]:
		_grenades.append(GrenadeState.from_dict(def, entry))
	_targets.clear()
	for target_id: int in data["targets"]:
		_targets[target_id] = (data["targets"][target_id] as Dictionary).duplicate()
	_players.clear()
	for player_id: int in data["players"]:
		_players[player_id] = data["players"][player_id]
	return &""


func _snapshot_parts_fit(data: Dictionary) -> bool:
	if not _all_fit(data["cooks"], COOK_KEYS) or not _all_fit(data["targets"], TARGET_KEYS):
		return false
	for entry: Variant in data["grenades"]:
		if typeof(entry) != TYPE_DICTIONARY or not _has_keys(entry, GrenadeState.SNAPSHOT_KEYS):
			return false
	for player_id: Variant in data["players"]:
		if typeof(player_id) != TYPE_INT or typeof(data["players"][player_id]) != TYPE_VECTOR3:
			return false
	return true


## Whether every key of `entries` is a player or zombie id and every value a dictionary with `keys`.
static func _all_fit(entries: Dictionary, keys: Dictionary) -> bool:
	for id: Variant in entries:
		var entry: Variant = entries[id]
		if typeof(id) != TYPE_INT or typeof(entry) != TYPE_DICTIONARY or not _has_keys(entry, keys):
			return false
	return true


## Whether `data` has every key of `keys` with its type (an int is good enough for a float).
static func _has_keys(data: Dictionary, keys: Dictionary) -> bool:
	for key: String in keys:
		if not data.has(key):
			return false
		var expected: int = keys[key]
		var actual := typeof(data[key])
		if actual != expected and not (expected == TYPE_FLOAT and actual == TYPE_INT):
			return false
	return true


# --- Actions ---


func _dispatch(action: Dictionary) -> void:
	match action.get("type"):
		GrenadeAction.COOK:
			_cook(action)
		GrenadeAction.THROW:
			_throw(action)
		GrenadeAction.TICK:
			_tick(action["delta"])
		GrenadeAction.TARGETS:
			_targets.clear()
			for target: Dictionary in action["list"]:
				_targets[target["id"]] = {
					"pos": target["pos"],
					"yaw": target.get("yaw", 0.0),
					"scale": target.get("scale", 1.0),
				}
		GrenadeAction.PLAYERS:
			_players.clear()
			for player: Dictionary in action["list"]:
				_players[player["id"]] = player["pos"]
		_:
			_emit(&"action_rejected", {"reason": &"unknown_action"})


func _cook(action: Dictionary) -> void:
	var player_id: int = action["player_id"]
	var seq: int = action["seq"]
	var problem := _hand_problem(player_id, action["hand"])
	if problem != &"":
		_emit(&"cook_rejected", {"player_id": player_id, "seq": seq, "reason": problem})
		return
	if _cooks.has(player_id):
		_hold(_cooks[player_id], player_id, action["hand"])
		return
	if rules != null:
		var rules_events := rules.apply(RulesAction.use_grenade(player_id))
		for event in rules_events:
			if event["type"] == &"action_rejected":
				_emit(
					&"cook_rejected",
					{"player_id": player_id, "seq": seq, "reason": event["reason"]}
				)
				return
		_events.append_array(rules_events)
	var cook := {"started": now, "seq": seq}
	_hold(cook, player_id, action["hand"])
	_cooks[player_id] = cook
	_emit(&"cook_started", {"player_id": player_id, "seq": seq, "fuse": def.fuse})


func _throw(action: Dictionary) -> void:
	var player_id: int = action["player_id"]
	var seq: int = action["seq"]
	var aim: Vector3 = action["aim"]
	var carrier: Vector3 = action["velocity"]
	var blocked := _rules_problem(player_id)
	if blocked != &"":
		_emit(&"throw_rejected", {"player_id": player_id, "seq": seq, "reason": blocked})
		return
	if not _cooks.has(player_id):
		_emit(&"throw_rejected", {"player_id": player_id, "seq": seq, "reason": &"not_cooking"})
		return
	if not aim.is_finite() or aim.length_squared() < 0.5:
		_emit(&"throw_rejected", {"player_id": player_id, "seq": seq, "reason": &"bad_aim"})
		return
	var problem := _hand_problem(player_id, action["hand"])
	if problem == &"" and not carrier.is_finite():
		problem = &"bad_velocity"
	if problem != &"":
		_emit(&"throw_rejected", {"player_id": player_id, "seq": seq, "reason": problem})
		return
	var cooked: float = now - _cooks[player_id]["started"]
	_cooks.erase(player_id)
	var underarm: bool = action["underarm"]
	var velocity := def.launch_velocity(aim, underarm, carrier.limit_length(def.max_carrier_speed))
	var grenade_state := GrenadeState.new(
		_next_id,
		player_id,
		def,
		_anchor(player_id) + _reach(player_id, action["hand"]),
		velocity,
		maxf(def.fuse - cooked, def.min_fuse_left)
	)
	_next_id += 1
	_grenades.append(grenade_state)
	_emit(
		&"grenade_thrown",
		{
			"grenade_id": grenade_state.id,
			"thrower_id": player_id,
			"seq": seq,
			"position": grenade_state.position,
			"velocity": velocity,
			"fuse_left": grenade_state.fuse_left,
			"underarm": underarm,
			"cooked": cooked,
		}
	)


## Why a hand the client sent cannot be used, or an empty name when it can: it is not a finite
## point, or the server has not been told where that player is.
func _hand_problem(player_id: int, claimed: Vector3) -> StringName:
	if not claimed.is_finite():
		return &"bad_hand"
	if not _players.has(player_id):
		return &"unknown_player"
	return &""


## Where the server puts the hand of a player: the hand height above their feet.
func _anchor(player_id: int) -> Vector3:
	return _players[player_id] + Vector3.UP * def.hand_height


## The client's hand as an offset from the server's, no further than `hand_reach` away.
func _reach(player_id: int, claimed: Vector3) -> Vector3:
	return (claimed - _anchor(player_id)).limit_length(def.hand_reach)


## Keeps a cook's hand as an offset from the player, so a grenade held while walking goes with them.
func _hold(cook: Dictionary, player_id: int, claimed: Vector3) -> void:
	cook["offset"] = _reach(player_id, claimed)
	cook["hand"] = _anchor(player_id) + (cook["offset"] as Vector3)


## `&"player_downed"` or `&"unknown_player"` when the rules say this player cannot throw.
func _rules_problem(player_id: int) -> StringName:
	if rules == null:
		return &""
	var player := rules.players.get(player_id) as PlayerState
	if player == null:
		return &"unknown_player"
	return &"player_downed" if player.downed else &""


## A cooked grenade whose player can no longer hold it falls at their feet, fuse still running.
func _drop(player_id: int, cook: Dictionary) -> void:
	var cooked: float = now - cook["started"]
	var feet: Vector3 = _players.get(player_id, cook["hand"])
	var grenade_state := GrenadeState.new(
		_next_id,
		player_id,
		def,
		feet + Vector3.UP * def.drop_height,
		Vector3.ZERO,
		maxf(def.fuse - cooked, def.min_fuse_left)
	)
	_next_id += 1
	_grenades.append(grenade_state)
	_emit(
		&"grenade_dropped",
		{
			"grenade_id": grenade_state.id,
			"thrower_id": player_id,
			"position": grenade_state.position,
			"velocity": grenade_state.velocity,
			"fuse_left": grenade_state.fuse_left,
			"cooked": cooked,
		}
	)


func _tick(delta: float) -> void:
	now += delta
	for player_id in _cooks.keys():
		var cook: Dictionary = _cooks[player_id]
		if _rules_problem(player_id) != &"":
			_cooks.erase(player_id)
			_drop(player_id, cook)
			continue
		if _players.has(player_id):
			cook["hand"] = _anchor(player_id) + (cook["offset"] as Vector3)
		if now - cook["started"] >= def.fuse:
			_cooks.erase(player_id)
			_explode(0, player_id, cook["hand"], true)
	var flying: Array[GrenadeState] = []
	var cast := world_cast if world_cast.is_valid() else _open_ground
	var bodies := _bodies_in_the_way
	for grenade_state in _grenades:
		grenade_state.step(delta, cast, bodies)
		var struck := -1
		for contact in grenade_state.contacts:
			_emit(
				&"grenade_bounced",
				{
					"grenade_id": grenade_state.id,
					"point": contact["point"],
					"speed": contact["speed"],
					"wall": contact["wall"],
					"zombie_id": contact["zombie_id"],
				}
			)
			if contact["zombie_id"] >= 0:
				struck = contact["zombie_id"]
		if struck >= 0:
			_emit(
				&"grenade_struck",
				{
					"grenade_id": grenade_state.id,
					"zombie_id": struck,
					"state": grenade_state.to_dict(),
				}
			)
		if grenade_state.is_spent():
			_explode(grenade_state.id, grenade_state.thrower_id, grenade_state.position, false)
		else:
			flying.append(grenade_state)
	_grenades = flying


## The zombies on a segment of a flight, as the grenade's `bodies` (`ZombieBump`).
func _bodies_in_the_way(from: Vector3, to: Vector3) -> Dictionary:
	return ZombieBump.nearest(from, to, _targets)


## The flight's world when none was given: nothing is ever in the way.
func _open_ground(_from: Vector3, _to: Vector3) -> Dictionary:
	return {}


# --- The blast ---


func _explode(grenade_id: int, thrower_id: int, where: Vector3, in_hand: bool) -> void:
	var point := where + Vector3.UP * def.blast_lift
	_emit(
		&"grenade_exploded",
		{
			"grenade_id": grenade_id,
			"thrower_id": thrower_id,
			"point": point,
			"core_radius": def.core_radius,
			"radius": def.blast_radius,
			"in_hand": in_hand,
		}
	)
	var victims: Array[Dictionary] = []
	var ids := _targets.keys()
	ids.sort()
	for target_id: int in ids:
		if rules != null and not rules.has_zombie(target_id):
			continue
		var target: Dictionary = _targets[target_id]
		var body := BlastModel.against_zombie(def, point, target["pos"], target["yaw"], world_ray)
		if body["damage"] <= 0.0:
			continue
		var reach := def.falloff(body["distance"])
		var impulse := BlastModel.impulse(def, point, target["pos"], reach)
		_emit(
			&"blast_hit",
			{
				"grenade_id": grenade_id,
				"target_id": target_id,
				"damage": body["damage"],
				"leg_damage": body["leg_damage"],
				"exposure": body["exposure"],
				"distance": body["distance"],
				"impulse": impulse,
				"stun": def.stun_seconds * reach,
			}
		)
		(
			victims
			. append(
				{
					"zombie_id": target_id,
					"damage": body["damage"],
					"leg_damage": body["leg_damage"],
				}
			)
		)
	_blast_players(grenade_id, thrower_id, point, in_hand)
	if rules != null and not victims.is_empty():
		_events.append_array(rules.apply(RulesAction.explosion(thrower_id, victims)))


## Every player the blast reaches takes it, the thrower and the team alike (`PlayerBlast`): the same
## rule for all, all of the health in the hand that holds the grenade.
func _blast_players(grenade_id: int, thrower_id: int, point: Vector3, in_hand: bool) -> void:
	var ids := _players.keys()
	ids.sort()
	for player_id: int in ids:
		if _is_downed(player_id):
			continue
		var own: bool = player_id == thrower_id
		var chest: Vector3 = _players[player_id] + Vector3.UP * def.player_chest
		var hurt := BlastModel.against_player(
			def, point, chest, _max_health_of(player_id), own and in_hand, world_ray
		)
		if hurt["damage"] <= 0.0:
			continue
		var reach := def.falloff(hurt["distance"])
		_emit(
			&"player_blasted",
			{
				"grenade_id": grenade_id,
				"thrower_id": thrower_id,
				"player_id": player_id,
				"damage": hurt["damage"],
				"share": hurt["share"],
				"distance": hurt["distance"],
				"impulse": BlastModel.impulse(def, point, chest, reach),
				"stun": def.stun_seconds * reach,
				"own": own,
				"in_hand": own and in_hand,
			}
		)


## A player on the ground takes no blow (the rules refuse it): the blast does not count them.
func _is_downed(player_id: int) -> bool:
	var player := rules.players.get(player_id) as PlayerState if rules != null else null
	return player != null and player.downed


## The most health this player can have (the bar a blast takes a share of).
func _max_health_of(player_id: int) -> float:
	var player := rules.players.get(player_id) as PlayerState if rules != null else null
	return player.max_health if player != null else DEFAULT_MAX_HEALTH


func _emit(type: StringName, fields: Dictionary = {}) -> void:
	var event := {"type": type}
	event.merge(fields)
	_events.append(event)
