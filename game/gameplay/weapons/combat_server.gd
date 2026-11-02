class_name CombatServer
extends RefCounted
## The server's side of shooting: who may fire, what a shot hits, how much it hurts, who dies, and
## what the rules hear about it. A plain `RefCounted` like `GameRules`: it changes only through
## `apply(action)` (a dictionary from `CombatAction`) and answers with the events that caused,
## plain dictionaries. No node, no peer, no clock of its own, no global random. Single-player
## runs this same object behind a loopback.
##
## Time is `CombatAction.tick`; the world is a `world_ray` Callable (see `AimResolver`).
## Every damaged zombie is one `RulesAction.hit` (target, zone, damage): the rules own the zombie's
## health, pay the points and decide the kill. Their events are appended to the answer after the
## combat events that caused them.
##
## Events (fields besides `type`):
##   shot_fired: shooter_id, weapon_id, seq, muzzle, ends (one point per pellet), flesh (the point
##     of every zombie the shot hit, for the view's impacts), ammo, reserve, rewound_by
##   fire_rejected: shooter_id, seq, reason (`reloading`, `cooldown`, `empty`, `no_weapon`,
##     `bad_aim`)
##   damage_dealt: shooter_id, target_id, zone, damage, headshot, melee, pellets, health, point
##   target_killed: shooter_id, target_id, zone, headshot, melee
##   reload_started: shooter_id, weapon_id, seconds
##   reload_finished: shooter_id, weapon_id, ammo, reserve
##   reload_rejected: shooter_id, reason
##   weapon_replaced: player_id, dropped (the weapon that was in hand), weapon_id (the new one); a
##     third weapon replaces the one in hand (`WeaponCatalog.CARRY_LIMIT`); sent before the new
##     weapon's weapon_equipped
##   weapon_equipped: player_id, weapon_id, ammo, reserve
##   ammo_added: player_id, weapon_id, added (rounds that fitted), ammo, reserve
##   weapon_upgraded: player_id, weapon_id, tier, display_name, ammo, reserve, magazine, damage
##   projectile_spawned: projectile_id, shooter_id, weapon_id, position, velocity
##   projectile_burst: projectile_id, shooter_id, weapon_id, point, radius, kind
##   action_rejected: reason

signal event_emitted(event: Dictionary)

## Clock, seconds. Only `tick` moves it.
var now: float = 0.0
var rng_seed: int = 0
var world_ray: Callable
var rules: GameRules
var lag: LagCompensator

var _defs: Dictionary[StringName, WeaponDef] = {}
var _loadouts: Dictionary[int, Dictionary] = {}
var _current: Dictionary[int, StringName] = {}
var _targets: Dictionary[int, Dictionary] = {}
var _alive: Dictionary[int, bool] = {}
var _projectiles: Array[ProjectileState] = []
var _next_projectile: int = 1
var _events: Array[Dictionary] = []


func _init(
	p_defs: Array[WeaponDef],
	p_rules: GameRules = null,
	p_world_ray: Callable = Callable(),
	p_seed: int = 0,
	max_rewind: float = LagCompensator.DEFAULT_MAX_REWIND
) -> void:
	for def in p_defs:
		_defs[def.id] = def
	rules = p_rules
	world_ray = p_world_ray
	rng_seed = p_seed
	lag = LagCompensator.new(max_rewind)
	if rules != null:
		rules.event_emitted.connect(_on_rules_event)


## Stops listening to the rules. Call when the night is over.
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


## Whether the server counts a target as alive: tracked, and not yet removed.
func is_target_alive(target_id: int) -> bool:
	return _alive.has(target_id)


func weapon_of(player_id: int) -> WeaponState:
	var held: Dictionary = _loadouts.get(player_id, {})
	return held.get(_current.get(player_id, &""))


## One carried weapon's state, or null when the player does not carry it.
func state_of(player_id: int, weapon_id: StringName) -> WeaponState:
	return _loadouts.get(player_id, {}).get(weapon_id)


## The ids of the weapons a player carries.
func carried(player_id: int) -> Array:
	return _loadouts.get(player_id, {}).keys()


func projectiles_in_flight() -> int:
	return _projectiles.size()


# --- Actions ---


func _dispatch(action: Dictionary) -> void:
	match action.get("type"):
		CombatAction.FIRE:
			_fire(action)
		CombatAction.RELOAD:
			_reload(action["shooter_id"])
		CombatAction.GIVE_WEAPON:
			_give(action["player_id"], action["weapon_id"], StringName(action.get("replace", &"")))
		CombatAction.EQUIP:
			_equip(action["player_id"], action["weapon_id"])
		CombatAction.SWAP:
			_swap(action["player_id"])
		CombatAction.ADD_AMMO:
			_add_ammo(action["player_id"], action["weapon_id"], action["rounds"])
		CombatAction.UPGRADE_WEAPON:
			_upgrade(action["player_id"], action["weapon_id"])
		CombatAction.TICK:
			_tick(action["delta"])
		CombatAction.TARGETS:
			_set_targets(action["list"])
		CombatAction.TRACK_TARGET:
			_alive[action["target_id"]] = true
		CombatAction.UNTRACK_TARGET:
			_alive.erase(action["target_id"])
		_:
			_emit(&"action_rejected", {"reason": &"unknown_action"})


func _on_rules_event(event: Dictionary) -> void:
	var action := CombatAction.from_rules_event(event)
	if not action.is_empty():
		_dispatch(action)


func _give(player_id: int, weapon_id: StringName, replace: StringName = &"") -> void:
	if not _defs.has(weapon_id):
		_emit(&"action_rejected", {"reason": &"unknown_weapon"})
		return
	var held: Dictionary = _loadouts.get_or_add(player_id, {})
	if held.has(weapon_id):
		var owned: WeaponState = held[weapon_id]
		owned.add_reserve(owned.def.magazine_size)
	else:
		if held.size() >= WeaponCatalog.CARRY_LIMIT:
			_replace(player_id, held, weapon_id, replace)
		held[weapon_id] = WeaponState.new(_defs[weapon_id])
	_equip(player_id, weapon_id)


## Hands full: `replace` (the weapon in hand when it is not carried, the first carried when none is)
## is gone, with its rounds. It is not dropped on the ground; the rules put it back in the pool.
func _replace(player_id: int, held: Dictionary, taken: StringName, replace: StringName) -> void:
	var dropped := replace
	if not held.has(dropped):
		dropped = _current.get(player_id, &"")
	if not held.has(dropped):
		dropped = held.keys()[0]
	held.erase(dropped)
	if _current.get(player_id, &"") == dropped:
		_current.erase(player_id)
	_emit(&"weapon_replaced", {"player_id": player_id, "dropped": dropped, "weapon_id": taken})


func _equip(player_id: int, weapon_id: StringName) -> void:
	var held: Dictionary = _loadouts.get(player_id, {})
	if not held.has(weapon_id):
		_emit(&"action_rejected", {"reason": &"not_carried"})
		return
	var previous := weapon_of(player_id)
	if previous != null:
		previous.cancel_reload()
	_current[player_id] = weapon_id
	var state: WeaponState = held[weapon_id]
	_emit(
		&"weapon_equipped",
		{
			"player_id": player_id,
			"weapon_id": weapon_id,
			"ammo": state.ammo,
			"reserve": state.reserve,
		}
	)


func _swap(player_id: int) -> void:
	var held: Dictionary = _loadouts.get(player_id, {})
	if held.size() < 2:
		return
	var ids := held.keys()
	var at := ids.find(_current.get(player_id, &""))
	_equip(player_id, ids[(at + 1) % ids.size()])


## Rounds into a carried weapon's reserve; says how many fitted (maybe none).
func _add_ammo(player_id: int, weapon_id: StringName, rounds: int) -> void:
	var held: Dictionary = _loadouts.get(player_id, {})
	if not held.has(weapon_id):
		_emit(&"action_rejected", {"reason": &"not_carried"})
		return
	var state: WeaponState = held[weapon_id]
	var added := state.add_reserve(rounds) if state.uses_ammo() else 0
	_emit(
		&"ammo_added",
		{
			"player_id": player_id,
			"weapon_id": weapon_id,
			"added": added,
			"ammo": state.ammo,
			"reserve": state.reserve,
		}
	)


## Re-cuts a carried weapon once (the numbers are the rules' `upgrade` tuning, the defaults without
## rules). The rules have already charged; a weapon that is not carried, can not be re-cut or
## already is, is refused.
func _upgrade(player_id: int, weapon_id: StringName) -> void:
	var spec := rules.tuning.upgrade if rules != null else UpgradeTuning.new()
	var state := state_of(player_id, weapon_id)
	if state == null:
		_emit(&"action_rejected", {"reason": &"not_carried"})
		return
	if state.tier() > 0 or not spec.allows(weapon_id):
		_emit(&"action_rejected", {"reason": &"not_upgradable"})
		return
	state.upgrade(spec)
	_emit(
		&"weapon_upgraded",
		{
			"player_id": player_id,
			"weapon_id": weapon_id,
			"tier": state.tier(),
			"display_name": state.def.display_name,
			"ammo": state.ammo,
			"reserve": state.reserve,
			"magazine": state.def.magazine_size,
			"damage": state.def.damage,
		}
	)


func _reload(shooter_id: int) -> void:
	var state := weapon_of(shooter_id)
	if state == null:
		_emit(&"reload_rejected", {"shooter_id": shooter_id, "reason": &"no_weapon"})
		return
	var block := state.reload_block()
	if block != &"":
		_emit(&"reload_rejected", {"shooter_id": shooter_id, "reason": block})
		return
	_begin_reload(shooter_id, state)


func _begin_reload(shooter_id: int, state: WeaponState) -> void:
	state.start_reload()
	_emit(
		&"reload_started",
		{"shooter_id": shooter_id, "weapon_id": state.def.id, "seconds": state.def.reload_time}
	)


func _set_targets(list: Array) -> void:
	_targets.clear()
	for target in list:
		_targets[target["id"]] = {
			"pos": target["pos"],
			"yaw": target.get("yaw", 0.0),
			"scale": target.get("scale", 1.0),
			"weak": target.get("weak", false),
		}
	lag.record(now, list)


func _tick(delta: float) -> void:
	now += delta
	for player_id in _loadouts:
		for state: WeaponState in _loadouts[player_id].values():
			if state.tick(delta):
				_emit(
					&"reload_finished",
					{
						"shooter_id": player_id,
						"weapon_id": state.def.id,
						"ammo": state.ammo,
						"reserve": state.reserve,
					}
				)
	_step_projectiles(delta)


# --- Firing ---


func _fire(action: Dictionary) -> void:
	var shooter_id: int = action["shooter_id"]
	var seq: int = action["seq"]
	var state := weapon_of(shooter_id)
	if state == null:
		_reject_fire(shooter_id, seq, &"no_weapon")
		return
	var dir: Vector3 = action["dir"]
	if not dir.is_finite() or dir.length_squared() < 0.5:
		_reject_fire(shooter_id, seq, &"bad_aim")
		return
	var block := state.fire_block()
	if block != &"":
		_reject_fire(shooter_id, seq, block)
		if block == &"empty" and state.reload_block() == &"":
			_begin_reload(shooter_id, state)
		return
	state.fire()
	var view := _view_at(action["view_time"])
	var origin: Vector3 = action["origin"]
	dir = dir.normalized()
	var muzzle: Vector3 = action["muzzle"]
	var def := state.def
	var ends: Array[Vector3] = []
	var flesh: Array[Vector3] = []
	var damage := {}
	match def.kind:
		WeaponDef.Kind.HITSCAN:
			var seed_value := AimResolver.shot_seed(rng_seed, shooter_id, seq)
			var shot := AimResolver.trace_hitscan(
				def, origin, dir, muzzle, view["targets"], world_ray, seed_value
			)
			for pellet: Dictionary in shot["pellets"]:
				ends.append(pellet["end"])
				_tally(damage, pellet["hits"])
				for hit: Dictionary in pellet["hits"]:
					flesh.append(hit["point"])
		WeaponDef.Kind.PROJECTILE:
			var mdir := AimResolver.aim_direction(
				def, origin, dir, muzzle, view["targets"], world_ray
			)
			_launch(shooter_id, def, muzzle, mdir)
			ends.append(muzzle + mdir * def.max_range)
		WeaponDef.Kind.MELEE:
			var hits := AimResolver.sweep_melee(def, origin, dir, view["targets"], world_ray)
			_tally(damage, hits)
			for hit: Dictionary in hits:
				flesh.append(hit["point"])
			ends.append(origin + dir * def.melee_range)
	_emit(
		&"shot_fired",
		{
			"shooter_id": shooter_id,
			"weapon_id": def.id,
			"seq": seq,
			"muzzle": muzzle,
			"ends": ends,
			"flesh": flesh,
			"ammo": state.ammo,
			"reserve": state.reserve,
			"rewound_by": view["rewound_by"],
		}
	)
	for target_id: int in damage:
		var total: Dictionary = damage[target_id]
		_hurt(shooter_id, target_id, total, def.is_melee())


## The targets as the shooter saw them, without the ones already dead.
func _view_at(view_time: float) -> Dictionary:
	var view := lag.rewind(view_time, now)
	if lag.frame_count() == 0:
		view["targets"] = _targets.duplicate()
	var alive := {}
	for id in view["targets"]:
		if _alive.has(id):
			alive[id] = view["targets"][id]
	view["targets"] = alive
	return view


## Adds a list of hits into one entry per target: total damage, best zone, any head hit.
func _tally(damage: Dictionary, hits: Array) -> void:
	for hit: Dictionary in hits:
		var entry: Dictionary = damage.get_or_add(
			hit["target_id"],
			{
				"damage": 0.0,
				"zone": hit["zone"],
				"best": 0.0,
				"pellets": 0,
				"head": false,
				"point": hit["point"]
			}
		)
		entry["damage"] += hit["damage"]
		entry["pellets"] += 1
		entry["head"] = entry["head"] or hit["zone"] == Hitbox.HEAD
		if hit["damage"] > entry["best"]:
			entry["best"] = hit["damage"]
			entry["zone"] = hit["zone"]
			entry["point"] = hit["point"]


## Applies one target's share of a shot: one `hit` action to the rules, which own the zombie's
## health, pay the points and decide the kill. A head pellet makes the whole hit a headshot.
func _hurt(shooter_id: int, target_id: int, total: Dictionary, melee: bool) -> void:
	if rules == null or not _alive.has(target_id):
		return
	var head: bool = total["head"]
	var zone: StringName = Hitbox.HEAD if head else total["zone"]
	var rules_events := rules.apply(
		RulesAction.hit(shooter_id, target_id, zone, total["damage"], melee)
	)
	var health := 0.0
	var killed := false
	var applied := false
	for event in rules_events:
		if event["type"] == &"zombie_damaged":
			applied = true
			health = event["health"]
		elif event["type"] == &"zombie_removed" and event["cause"] == &"killed":
			killed = true
	if not applied:
		_events.append_array(rules_events)
		return
	_emit(
		&"damage_dealt",
		{
			"shooter_id": shooter_id,
			"target_id": target_id,
			"zone": zone,
			"damage": total["damage"],
			"headshot": head,
			"melee": melee,
			"pellets": total["pellets"],
			"health": health,
			"point": total["point"],
		}
	)
	if killed:
		_emit(
			&"target_killed",
			{
				"shooter_id": shooter_id,
				"target_id": target_id,
				"zone": zone,
				"headshot": head,
				"melee": melee,
			}
		)
	_events.append_array(rules_events)


func _reject_fire(shooter_id: int, seq: int, reason: StringName) -> void:
	_emit(&"fire_rejected", {"shooter_id": shooter_id, "seq": seq, "reason": reason})


# --- Projectiles ---


func _launch(shooter_id: int, def: WeaponDef, muzzle: Vector3, dir: Vector3) -> void:
	var projectile := ProjectileState.new(
		_next_projectile, shooter_id, def, muzzle, dir * def.projectile_speed
	)
	_next_projectile += 1
	_projectiles.append(projectile)
	_emit(
		&"projectile_spawned",
		{
			"projectile_id": projectile.id,
			"shooter_id": shooter_id,
			"weapon_id": def.id,
			"position": muzzle,
			"velocity": projectile.velocity,
		}
	)


func _step_projectiles(delta: float) -> void:
	var alive_targets := {}
	for id in _targets:
		if _alive.has(id):
			alive_targets[id] = _targets[id]
	var flying: Array[ProjectileState] = []
	for projectile in _projectiles:
		var result := projectile.step(delta, alive_targets, world_ray)
		if result.is_empty():
			flying.append(projectile)
		else:
			_burst(projectile, result, alive_targets)
	_projectiles = flying


func _burst(projectile: ProjectileState, result: Dictionary, alive: Dictionary) -> void:
	var def := projectile.def
	var point: Vector3 = result["point"]
	_emit(
		&"projectile_burst",
		{
			"projectile_id": projectile.id,
			"shooter_id": projectile.shooter_id,
			"weapon_id": def.id,
			"point": point,
			"radius": def.splash_radius,
			"kind": result["kind"],
		}
	)
	if def.is_lure():
		_emit(
			&"lure_started",
			{
				"lure_id": projectile.id,
				"shooter_id": projectile.shooter_id,
				"weapon_id": def.id,
				"point": point,
				"radius": def.lure_radius,
				"seconds": def.lure_seconds,
			}
		)
	var damage := {}
	var direct := -1
	if result["kind"] == &"target" and def.damage > 0.0:
		direct = result["target_id"]
		var zone: StringName = result["zone"]
		_tally(
			damage,
			[
				{
					"target_id": direct,
					"zone": zone,
					"damage": DamageModel.damage(def, 0.0, zone),
					"point": point,
				}
			]
		)
	for id in alive:
		if id == direct:
			continue
		var blast := DamageModel.splash(
			def, Hitbox.distance_from(point, alive[id]["pos"], alive[id]["yaw"])
		)
		if blast > 0.0:
			_tally(
				damage, [{"target_id": id, "zone": Hitbox.BODY, "damage": blast, "point": point}]
			)
	for target_id: int in damage:
		_hurt(projectile.shooter_id, target_id, damage[target_id], false)


func _emit(type: StringName, fields: Dictionary = {}) -> void:
	var event := {"type": type}
	event.merge(fields)
	_events.append(event)
