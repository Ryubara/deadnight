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
##   shot_fired: shooter_id, weapon_id, seq, hand (0 the right, 1 the left: a dual weapon's shots
##     alternate), muzzle, ends (one point per pellet), flesh (the point of every zombie the shot
##     hit, for the view's impacts), ammo, reserve, rewound_by
##   quick_melee: shooter_id, seq, muzzle, ends (one point: the blow's reach), flesh (the point of
##     every zombie it hit); the damage follows as `damage_dealt` and `target_killed` with `melee`
##   fire_rejected: shooter_id, seq, reason (`reloading`, `cooldown`, `empty`, `no_weapon`,
##     `bad_aim`); a quick melee in its cooldown is one with reason `cooldown`
##   damage_dealt: shooter_id, target_id, zone, damage, headshot, melee, pellets, health, point,
##     weapon_id, dir (the unit way the shot or blow travelled, ZERO for a burst: the view sprays
##     blood along it and looks for a wall behind the zombie, `BloodFx`), element (the id of the
##     element that made the damage, empty for the weapon's own hit), shattered (the hit broke a
##     frozen zombie: no blood, the pieces are `zombie_shattered`)
##   target_killed: shooter_id, target_id, zone, headshot, melee, shattered
##   status_applied: target_id, status (a `StatusDef` id), seconds (left), then what the target is
##     under now: wire, halts, speed_scale (`StatusBoard.summary_of`)
##   status_ended: target_id, status, then the same summary
##   reload_started: shooter_id, weapon_id, seconds, rounds (how many it will load: all of them at
##     the end for a magazine, one at a time for a `reload_by_round` weapon)
##   reload_round: shooter_id, weapon_id, ammo, reserve (a by-round reload put one more round in)
##   reload_interrupted: shooter_id, weapon_id, ammo, reserve (a shot ended a by-round reload)
##   reload_finished: shooter_id, weapon_id, ammo, reserve
##   reload_rejected: shooter_id, reason
##   weapon_replaced: player_id, dropped (the weapon that was in hand), weapon_id (the new one, or
##     empty when a weapon is given up and nothing takes its place: the third-weapon perk is lost);
##     a third weapon replaces the one in hand (`PerkEffects.carry_limit`); sent before the new
##     weapon's weapon_equipped
##   weapon_equipped: player_id, weapon_id, ammo, reserve
##   ammo_added: player_id, weapon_id, added (rounds that fitted), ammo, reserve
##   weapon_upgraded: player_id, weapon_id, tier, display_name, ammo, reserve, magazine, damage,
##     fire_interval, element (the id of the element it carries, empty for none)
##   element_burst: shooter_id, weapon_id, element, point, radius (a re-cut weapon's blast: the view
##     draws the burst; the damage follows as `damage_dealt` with `element`)
##   element_arc: shooter_id, weapon_id, element, from, to (a point for each zombie the arc reached)
##   fire_patch_started: patch_id, shooter_id, weapon_id, element, point, radius, seconds (the
##     ground a re-cut flare gun's burst sets burning; its hits are `damage_dealt` with `element`)
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
## The status effects the zombies are under (`StatusBoard`). The rules read it to know that a hit on
## a zombie shatters (`GameRules.statuses`); this server puts them on and runs them down.
var statuses := StatusBoard.new()

var _defs: Dictionary[StringName, WeaponDef] = {}
var _loadouts: Dictionary[int, Dictionary] = {}
var _current: Dictionary[int, StringName] = {}
var _targets: Dictionary[int, Dictionary] = {}
## The `CombatAction.targets` revision `_targets` was read at (-1: none, or a list without one).
var _targets_revision := -1
var _alive: Dictionary[int, bool] = {}
var _projectiles: Array[ProjectileState] = []
## Seconds until each player's quick melee is ready again (`WeaponCatalog.quick_melee`'s interval).
var _quick_wait: Dictionary[int, float] = {}
var _quick_def: WeaponDef
var _next_projectile: int = 1
## The fire patches a re-cut flare gun leaves, and the numbers of the blast and the arc.
var _elements := ElementPlay.new()
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
		rules.statuses = statuses


## Stops listening to the rules. Call when the night is over.
func detach() -> void:
	if rules != null and rules.event_emitted.is_connected(_on_rules_event):
		rules.event_emitted.disconnect(_on_rules_event)
	if rules != null and rules.statuses == statuses:
		rules.statuses = null


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
		CombatAction.QUICK_MELEE:
			_quick_melee(action)
		CombatAction.GIVE_WEAPON:
			_give(action["player_id"], action["weapon_id"], StringName(action.get("replace", &"")))
		CombatAction.EQUIP:
			_equip(action["player_id"], action["weapon_id"])
		CombatAction.SWAP:
			_swap(action["player_id"])
		CombatAction.SELECT_SLOT:
			_select_slot(action["player_id"], int(action["slot"]))
		CombatAction.ADD_AMMO:
			_add_ammo(action["player_id"], action["weapon_id"], action["rounds"])
		CombatAction.UPGRADE_WEAPON:
			_upgrade(action["player_id"], action["weapon_id"])
		CombatAction.REMOVE_WEAPONS:
			_remove(action["player_id"], action["weapon_ids"])
		CombatAction.TICK:
			_tick(action["delta"])
		CombatAction.TARGETS:
			_set_targets(action["list"], action.get("revision", -1))
		CombatAction.TRACK_TARGET:
			_alive[action["target_id"]] = true
		CombatAction.UNTRACK_TARGET:
			_alive.erase(action["target_id"])
			statuses.forget(action["target_id"])
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
		var slot := -1
		if held.size() >= PerkEffects.carry_limit(rules, player_id):
			slot = _replace(player_id, held, weapon_id, replace)
		held[weapon_id] = WeaponState.new(_defs[weapon_id])
		if slot >= 0:
			_seat(held, weapon_id, slot)
	_equip(player_id, weapon_id)


## Hands full: `replace` (the weapon in hand when it is not carried, the first carried when none is)
## is gone, with its rounds. It is not dropped on the ground; the rules put it back in the pool.
## The weapon that takes its place takes its slot (`WeaponSlots`): `_give` puts it there, so the
## numbers a player has learned do not trade places.
func _replace(player_id: int, held: Dictionary, taken: StringName, replace: StringName) -> int:
	var dropped := replace
	if not held.has(dropped):
		dropped = _current.get(player_id, &"")
	if not held.has(dropped):
		dropped = held.keys()[0]
	var slot := held.keys().find(dropped)
	held.erase(dropped)
	if _current.get(player_id, &"") == dropped:
		_current.erase(player_id)
	_emit(&"weapon_replaced", {"player_id": player_id, "dropped": dropped, "weapon_id": taken})
	return slot


## Moves `weapon_id`, the newest entry of `held`, to place `slot` (0-based): a loadout's order is
## the order of its slots.
func _seat(held: Dictionary, weapon_id: StringName, slot: int) -> void:
	var order := held.keys()
	order.erase(weapon_id)
	order.insert(slot, weapon_id)
	var kept := held.duplicate()
	held.clear()
	for id: StringName in order:
		held[id] = kept[id]


## Weapons given up (`CombatAction.remove_weapons`): each goes with its rounds. When the one in hand
## is among them, the first that is left is taken in hand.
func _remove(player_id: int, weapon_ids: Array) -> void:
	var held: Dictionary = _loadouts.get(player_id, {})
	var in_hand := _current.get(player_id, &"") as StringName
	for weapon_id: StringName in weapon_ids:
		if not held.has(weapon_id):
			continue
		held.erase(weapon_id)
		_emit(&"weapon_replaced", {"player_id": player_id, "dropped": weapon_id, "weapon_id": &""})
	if not held.has(in_hand):
		_current.erase(player_id)
		if not held.is_empty():
			_equip(player_id, held.keys()[held.size() - 1])


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


## Takes the weapon in carry slot `slot` (1-based) in hand. A slot with no weapon, or the one in
## hand, does nothing: no event, no rejection, no reload cancelled.
func _select_slot(player_id: int, slot: int) -> void:
	var picked := WeaponSlots.weapon_in(carried(player_id), slot)
	if picked == &"" or picked == _current.get(player_id, &""):
		return
	_equip(player_id, picked)


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
	var spec := rules.tuning.upgrade if rules != null else UpgradeTuning.shipped()
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
			"fire_interval": state.def.fire_interval,
			"element": state.def.element.id if state.def.has_element() else &"",
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
	state.start_reload(PerkEffects.reload_time_scale(rules, shooter_id))
	_emit(
		&"reload_started",
		{
			"shooter_id": shooter_id,
			"weapon_id": state.def.id,
			"seconds": state.reload_left,
			"rounds": state.rounds_to_load(),
		}
	)


func _set_targets(list: Array, revision: int) -> void:
	if revision >= 0 and revision == _targets_revision:
		lag.record_again(now)
		return
	_targets_revision = revision
	_targets.clear()
	for target in list:
		_targets[target["id"]] = LagCompensator.placed(target)
	lag.record(now, list)


func _tick(delta: float) -> void:
	now += delta
	for player_id in _quick_wait:
		_quick_wait[player_id] = maxf(_quick_wait[player_id] - delta, 0.0)
	for player_id in _loadouts:
		for state: WeaponState in _loadouts[player_id].values():
			var done := state.tick(delta)
			var fields := {
				"shooter_id": player_id,
				"weapon_id": state.def.id,
				"ammo": state.ammo,
				"reserve": state.reserve,
			}
			if state.loaded_last_tick > 0 and not done:
				_emit(&"reload_round", fields)
			if done:
				_emit(&"reload_finished", fields)
	_events.append_array(statuses.step(delta))
	_step_projectiles(delta)
	_burn_patches(delta)


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
	state.fire(PerkEffects.fire_interval_scale(rules, shooter_id))
	if state.interrupted:
		_emit(
			&"reload_interrupted",
			{
				"shooter_id": shooter_id,
				"weapon_id": state.def.id,
				"ammo": state.ammo,
				"reserve": state.reserve,
			}
		)
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
				def,
				origin,
				dir,
				muzzle,
				view["targets"],
				world_ray,
				seed_value,
				float(action.get("move", 0.0))
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
			"hand": state.hand,
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
		_hurt(shooter_id, target_id, total, def.is_melee(), def.id, dir, def)
	if def.has_element() and def.is_hitscan():
		_element_hits(shooter_id, def, damage)


## The quick melee (#411): the same sweep as a melee weapon's, with the quick melee's own numbers,
## whatever the player holds, once in `fire_interval`. The weapon in hand is not touched: its
## rounds, its cooldown and its reload go on.
func _quick_melee(action: Dictionary) -> void:
	var shooter_id: int = action["shooter_id"]
	var seq: int = action["seq"]
	var dir: Vector3 = action["dir"]
	if not dir.is_finite() or dir.length_squared() < 0.5:
		_reject_fire(shooter_id, seq, &"bad_aim")
		return
	if _quick_wait.get(shooter_id, 0.0) > WeaponState.READY_EPSILON:
		_reject_fire(shooter_id, seq, &"cooldown")
		return
	if _quick_def == null:
		_quick_def = _defs.get(WeaponCatalog.QUICK_MELEE, WeaponCatalog.quick_melee())
	_quick_wait[shooter_id] = _quick_def.fire_interval
	var view := _view_at(action["view_time"])
	var origin: Vector3 = action["origin"]
	dir = dir.normalized()
	var hits := AimResolver.sweep_melee(_quick_def, origin, dir, view["targets"], world_ray)
	var damage := {}
	_tally(damage, hits)
	var flesh: Array[Vector3] = []
	for hit: Dictionary in hits:
		flesh.append(hit["point"])
	_emit(
		&"quick_melee",
		{
			"shooter_id": shooter_id,
			"seq": seq,
			"muzzle": action["muzzle"],
			"ends": [origin + dir * _quick_def.melee_range],
			"flesh": flesh,
			"rewound_by": view["rewound_by"],
		}
	)
	for target_id: int in damage:
		_hurt(shooter_id, target_id, damage[target_id], true, _quick_def.id, dir)


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
func _hurt(
	shooter_id: int,
	target_id: int,
	total: Dictionary,
	melee: bool,
	weapon_id: StringName,
	dir: Vector3 = Vector3.ZERO,
	def: WeaponDef = null
) -> void:
	if rules == null or not _alive.has(target_id):
		return
	var head: bool = total["head"]
	var zone: StringName = Hitbox.HEAD if head else total["zone"]
	# The weapon that puts a status on does not break it: its own bolt on a frozen zombie keeps it.
	var keeps: StringName = def.status if def != null and def.has_status() else &""
	var rules_events := rules.apply(
		RulesAction.hit(shooter_id, target_id, zone, total["damage"], melee, keeps)
	)
	var health := 0.0
	var dealt: float = total["damage"]
	var killed := false
	var shattered := false
	var applied := false
	for event in rules_events:
		if event["type"] == &"zombie_damaged":
			applied = true
			health = event["health"]
			dealt = event["damage"]
		elif event["type"] == &"zombie_removed" and event["cause"] == &"killed":
			killed = true
			shattered = event.get("shattered", false)
	if not applied:
		_events.append_array(rules_events)
		return
	_emit(
		&"damage_dealt",
		{
			"shooter_id": shooter_id,
			"target_id": target_id,
			"zone": zone,
			"damage": dealt if shattered else total["damage"],
			"headshot": head,
			"melee": melee,
			"pellets": total["pellets"],
			"health": health,
			"point": total["point"],
			"weapon_id": weapon_id,
			"dir": dir,
			"shattered": shattered,
			"element": total.get("element", &""),
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
				"shattered": shattered,
			}
		)
	_events.append_array(rules_events)
	if not killed and def != null and def.has_status():
		_put_status(target_id, def)


## The status `def` puts on a zombie its bolt reached. A status the zombie kind gates
## (`StatusDef.kind_gated`) goes on only if the kind can take it (`ZombieType.freezable`) and after
## as many bolts as it needs (`ZombieType.freeze_bolts`): a kind that cannot, and the bolts before
## the last, only get the lesser status (`StatusDef.for_boss`, a slow); the count is kept as long as
## that lasts. A zombie already under the status keeps it for the seconds again.
func _put_status(target_id: int, def: WeaponDef) -> void:
	var status := StatusCatalog.get_def(def.status)
	if status == null or not _alive.has(target_id):
		return
	if status.kind_gated and not statuses.has(target_id, status.id):
		var type := rules.tuning.roster.type_of(rules.zombie_type(target_id))
		var needed := type.freeze_bolts if type != null else 1
		var bolts := needed
		if type != null and not type.freezable:
			bolts = 0
		elif type != null:
			bolts = statuses.add_bolt(target_id, status.id, def.status_seconds)
		if bolts < needed:
			_put_lesser(target_id, status, def.status_seconds)
			return
		statuses.clear_bolts(target_id, status.id)
	_events.append(statuses.apply(target_id, status, def.status_seconds))


## The lesser status of a gated one (a slow), unless the status leaves that kind alone.
func _put_lesser(target_id: int, status: StatusDef, seconds: float) -> void:
	var lesser := status.for_boss()
	if lesser != StatusDef.IMMUNE_BOSS:
		_events.append(statuses.apply(target_id, StatusCatalog.get_def(lesser), seconds))


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
		_hurt(
			projectile.shooter_id,
			target_id,
			damage[target_id],
			false,
			projectile.def.id,
			Vector3.ZERO,
			projectile.def
		)
	if def.has_status() and def.splash_radius > 0.0:
		_bloom(projectile, point, alive, damage)
	_start_patch(projectile, point)


## The burst of a weapon that puts a status on reaches every zombie in its radius that the bolt did
## not already hurt (those got it in `_hurt`, or died).
func _bloom(
	projectile: ProjectileState, point: Vector3, alive: Dictionary, hurt: Dictionary
) -> void:
	for id: int in alive:
		if hurt.has(id) or not _alive.has(id):
			continue
		var reach := Hitbox.distance_from(point, alive[id]["pos"], alive[id]["yaw"])
		if reach <= projectile.def.splash_radius:
			_put_status(id, projectile.def)


# --- Elements ---


## The zombies the server counts as alive, with where they stand now.
func _alive_targets() -> Dictionary:
	var alive := {}
	for id in _targets:
		if _alive.has(id):
			alive[id] = _targets[id]
	return alive


## What a re-cut weapon's element does for the hits of one shot (`damage`, one entry for each zombie
## it hit): every hit bursts (`ElementDef.blast_radius`) and arcs (`arc_targets`) from the point
## where it landed. Each blast and arc is one more hit for the zombies it reaches, for the shooter,
## so the rules pay and kill as for any hit.
func _element_hits(shooter_id: int, def: WeaponDef, damage: Dictionary) -> void:
	var element := def.element
	var hit_ids := damage.keys()
	for target_id: int in damage:
		var point: Vector3 = damage[target_id]["point"]
		if element.has_blast():
			_blast(shooter_id, def, point, target_id)
		if element.has_arc():
			_arc(shooter_id, def, point, hit_ids)


func _blast(shooter_id: int, def: WeaponDef, point: Vector3, hit_id: int) -> void:
	var alive := _alive_targets()
	_emit(
		&"element_burst",
		{
			"shooter_id": shooter_id,
			"weapon_id": def.id,
			"element": def.element.id,
			"point": point,
			"radius": def.element.blast_radius,
		}
	)
	for victim in ElementPlay.blast_victims(def, point, alive, hit_id):
		_hurt_by_element(shooter_id, def, victim["target_id"], victim["damage"], point)


func _arc(shooter_id: int, def: WeaponDef, point: Vector3, hit_ids: Array) -> void:
	var alive := _alive_targets()
	var victims := ElementPlay.arc_victims(def, point, alive, hit_ids)
	if victims.is_empty():
		return
	var ends: Array[Vector3] = []
	for victim in victims:
		ends.append(ElementPlay.arc_end(alive[victim["target_id"]]))
	_emit(
		&"element_arc",
		{
			"shooter_id": shooter_id,
			"weapon_id": def.id,
			"element": def.element.id,
			"from": point,
			"to": ends,
		}
	)
	for victim in victims:
		_hurt_by_element(shooter_id, def, victim["target_id"], victim["damage"], point)


## One hit the element makes: a body hit of `damage` for the weapon's shooter.
func _hurt_by_element(
	shooter_id: int, def: WeaponDef, target_id: int, damage: float, point: Vector3
) -> void:
	var total := {
		"damage": damage,
		"zone": Hitbox.BODY,
		"pellets": 1,
		"head": false,
		"point": point,
		"element": def.element.id,
	}
	_hurt(shooter_id, target_id, total, false, def.id)


## A burst of a weapon whose element burns the ground sets the ground alight for the weapon's lure
## seconds (the dead stay in the fire while the lure holds them).
func _start_patch(projectile: ProjectileState, point: Vector3) -> void:
	var def := projectile.def
	var patch := _elements.start_patch(
		projectile.id, projectile.shooter_id, def, point, def.lure_seconds
	)
	if patch == null:
		return
	_emit(
		&"fire_patch_started",
		{
			"patch_id": patch.id,
			"shooter_id": patch.shooter_id,
			"weapon_id": def.id,
			"element": def.element.id,
			"point": point,
			"radius": patch.radius(),
			"seconds": def.lure_seconds,
		}
	)


func _burn_patches(delta: float) -> void:
	var alive := _alive_targets()
	for tick in _elements.step(delta, alive):
		var patch: ElementPlay.Patch = tick["patch"]
		var total := {
			"damage": tick["damage"],
			"zone": Hitbox.BODY,
			"pellets": 1,
			"head": false,
			"point": ElementPlay.arc_end(alive[tick["target_id"]]),
			"element": patch.element.id,
		}
		_hurt(patch.shooter_id, tick["target_id"], total, false, patch.weapon_id)


func _emit(type: StringName, fields: Dictionary = {}) -> void:
	var event := {"type": type}
	event.merge(fields)
	_events.append(event)
