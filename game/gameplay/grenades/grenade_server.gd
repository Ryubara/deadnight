class_name GrenadeServer
extends RefCounted
## The server's side of grenades: who may cook and throw, the fuse, the flight, the blast, and what
## the rules hear about it. A plain `RefCounted` like `GameRules` and `CombatServer`: it changes
## only through `apply(action)` (a dictionary from `GrenadeAction`) and answers with the events
## that action caused, plain dictionaries. No node, no peer, no clock of its own, no global random,
## so a replay of the same actions gives the same events. Single-player runs this same object.
##
## Time is `GrenadeAction.tick`. The world is two Callables: `world_cast` for the flight (see
## `GrenadeState`) and `world_ray` for the cover line checks (the weapons' `WorldProbe`).
##
## A blast becomes ONE `RulesAction.explosion` for the thrower with every zombie it reached, in id
## order: the rules own the zombies' health, pay, kill and decide who is crippled. The rules'
## events follow the grenade's own in the answer.
##
## Events (fields besides `type`):
##   cook_started: player_id, seq, fuse
##   cook_rejected: player_id, seq, reason (the rules' reason: `no_grenades`, `wrong_phase`, ...)
##   throw_rejected: player_id, seq, reason (`not_cooking`, `bad_aim`)
##   grenade_thrown: grenade_id, thrower_id, seq, position, velocity, fuse_left, underarm, cooked
##   grenade_bounced: grenade_id, point, speed, wall
##   grenade_exploded: grenade_id, thrower_id, point, core_radius, radius, in_hand
##   blast_hit: grenade_id, target_id, damage, leg_damage, exposure, distance, impulse, stun
##   player_blasted: grenade_id, player_id, damage, distance, impulse, stun, own (the thrower's)

signal event_emitted(event: Dictionary)

## Clock, seconds. Only `tick` moves it.
var now: float = 0.0
var def: GrenadeDef
var rules: GameRules
var world_cast: Callable
var world_ray: Callable
## Whether a blast hurts the other players too (off in co-op: only the thrower takes it).
var friendly_fire: bool = false

var _cooks: Dictionary[int, Dictionary] = {}
var _grenades: Array[GrenadeState] = []
var _next_id: int = 1
var _targets: Dictionary[int, Dictionary] = {}
var _alive: Dictionary[int, bool] = {}
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
	if rules != null:
		rules.event_emitted.connect(_on_rules_event)


## Lets go of the rules (they hold a connection back to this server, a reference cycle). Call
## when the night is over.
func detach() -> void:
	if rules != null and rules.event_emitted.is_connected(_on_rules_event):
		rules.event_emitted.disconnect(_on_rules_event)


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
				_targets[target["id"]] = {"pos": target["pos"], "yaw": target.get("yaw", 0.0)}
		GrenadeAction.PLAYERS:
			_players.clear()
			for player: Dictionary in action["list"]:
				_players[player["id"]] = player["pos"]
		_:
			_emit(&"action_rejected", {"reason": &"unknown_action"})


func _on_rules_event(event: Dictionary) -> void:
	match event.get("type"):
		&"zombie_spawn_requested":
			_alive[event["zombie_id"]] = true
		&"zombie_removed":
			_alive.erase(event["zombie_id"])


func _cook(action: Dictionary) -> void:
	var player_id: int = action["player_id"]
	var hand: Vector3 = action["hand"]
	if _cooks.has(player_id):
		_cooks[player_id]["hand"] = hand
		return
	if rules != null:
		var rules_events := rules.apply(RulesAction.use_grenade(player_id))
		for event in rules_events:
			if event["type"] == &"action_rejected":
				_emit(
					&"cook_rejected",
					{"player_id": player_id, "seq": action["seq"], "reason": event["reason"]}
				)
				return
		_events.append_array(rules_events)
	_cooks[player_id] = {"started": now, "hand": hand, "seq": action["seq"]}
	_emit(&"cook_started", {"player_id": player_id, "seq": action["seq"], "fuse": def.fuse})


func _throw(action: Dictionary) -> void:
	var player_id: int = action["player_id"]
	var seq: int = action["seq"]
	var aim: Vector3 = action["aim"]
	if not _cooks.has(player_id):
		_emit(&"throw_rejected", {"player_id": player_id, "seq": seq, "reason": &"not_cooking"})
		return
	if not aim.is_finite() or aim.length_squared() < 0.5:
		_emit(&"throw_rejected", {"player_id": player_id, "seq": seq, "reason": &"bad_aim"})
		return
	var cooked := now - _cooks[player_id]["started"]
	_cooks.erase(player_id)
	var underarm: bool = action["underarm"]
	var velocity := def.launch_velocity(aim, underarm, action["velocity"])
	var grenade_state := GrenadeState.new(
		_next_id,
		player_id,
		def,
		action["hand"],
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


func _tick(delta: float) -> void:
	now += delta
	for player_id in _cooks.keys():
		var cook: Dictionary = _cooks[player_id]
		if now - cook["started"] >= def.fuse:
			_cooks.erase(player_id)
			_explode(0, player_id, cook["hand"], true)
	var flying: Array[GrenadeState] = []
	for grenade_state in _grenades:
		grenade_state.step(delta, world_cast)
		for contact in grenade_state.contacts:
			_emit(
				&"grenade_bounced",
				{
					"grenade_id": grenade_state.id,
					"point": contact["point"],
					"speed": contact["speed"],
					"wall": contact["wall"],
				}
			)
		if grenade_state.is_spent():
			_explode(grenade_state.id, grenade_state.thrower_id, grenade_state.position, false)
		else:
			flying.append(grenade_state)
	_grenades = flying


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
		if rules != null and not _alive.has(target_id):
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
	_blast_players(grenade_id, thrower_id, point)
	if rules != null and not victims.is_empty():
		_events.append_array(rules.apply(RulesAction.explosion(thrower_id, victims)))


func _blast_players(grenade_id: int, thrower_id: int, point: Vector3) -> void:
	var ids := _players.keys()
	ids.sort()
	for player_id: int in ids:
		var own: bool = player_id == thrower_id
		if not own and not friendly_fire:
			continue
		var chest: Vector3 = _players[player_id] + Vector3.UP * def.player_chest
		var hurt := BlastModel.against_point(def, point, chest, world_ray)
		if hurt["damage"] <= 0.0:
			continue
		var reach := def.falloff(hurt["distance"])
		_emit(
			&"player_blasted",
			{
				"grenade_id": grenade_id,
				"player_id": player_id,
				"damage": hurt["damage"] * (def.self_damage_fraction if own else 1.0),
				"distance": hurt["distance"],
				"impulse": BlastModel.impulse(def, point, chest, reach),
				"stun": def.stun_seconds * reach,
				"own": own,
			}
		)


func _emit(type: StringName, fields: Dictionary = {}) -> void:
	var event := {"type": type}
	event.merge(fields)
	_events.append(event)
