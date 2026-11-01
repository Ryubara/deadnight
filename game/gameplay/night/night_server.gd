class_name NightServer
extends RefCounted
## The authority of one night: the rules, the zombies, the weapons and the players' bodies, joined
## and stepped together. Everything that decides anything lives here; a client only sends
## `NightCommand`s and draws the events and frames that come back.
##
## Messages in (`apply`, plain dictionaries): `join` {player_id, local}, `leave` {player_id},
## `start_night`, and one `command` (a `NightCommand`) per player per tick; the latest one is
## used. `step(delta)` runs one fixed tick and returns the events for every client: the rules
## events (a zombie's blow is a `blow` action, answered by the rules' `player_hurt`), the weapons
## events (`CombatServer`), `player_damaged` (the blow as the world saw it: `from`, where it came
## from, and the zombie's id, type and `knockback`: metres the blow throws the player, recorded
## for the player's own motion to apply), and last a `frame`. A frame carries the whole picture a
## client or a HUD draws from.
##
## Frame fields: tick, phase, round, remaining, fuel, doors (open ids), barricades ({id: boards
## up}), zombies (`ZombieCodec` bytes), players {id: {pos, facing, health, downed, weapon, ammo,
## reserve, reloading, points, prompt}}.
##
## Single-player runs this beside the client, joined by a `LoopbackLink`.

const COMMAND := &"command"
const JOIN := &"join"
const LEAVE := &"leave"
const START_NIGHT := &"start_night"
## The weapons events worth sending on (the rules events ride the rules signal; the weapons
## answer repeats them).
const COMBAT_EVENTS: Array[StringName] = [
	&"shot_fired",
	&"damage_dealt",
	&"target_killed",
	&"reload_started",
	&"reload_finished",
	&"reload_rejected",
	&"weapon_equipped",
	&"projectile_spawned",
	&"projectile_burst",
	&"fire_rejected",
]
## A held trigger meets these every tick; they are not news.
const QUIET_REJECTIONS: Array[StringName] = [&"cooldown", &"reloading"]

var rules: GameRules
var combat: CombatServer
var sim: ZombieSim
var director: ZombieDirector
var world: NightWorld
var tuning: NightTuning
var tick_count := 0

var _pending: Dictionary[int, NightCommand] = {}
var _bodies: Dictionary[int, Player] = {}
var _shot_seq: Dictionary[int, int] = {}
var _repair_wait: Dictionary[int, float] = {}
var _outbox: Array[Dictionary] = []
var _probe: WorldProbe


func _init(
	p_world: NightWorld,
	p_seed: int = 1,
	p_tuning: NightTuning = null,
	p_rules_tuning: RulesTuning = null
) -> void:
	world = p_world
	tuning = p_tuning if p_tuning != null else NightTuning.new()
	rules = GameRules.new(p_rules_tuning, p_seed)
	_probe = WorldProbe.new(world.get_world_3d().direct_space_state)
	combat = CombatServer.new(WeaponCatalog.all(), rules, _probe.callable(), p_seed)
	sim = ZombieSim.new(null, p_seed)
	sim.rounds = rules.tuning.rounds
	sim.pathing = NavmeshPathing.new(world.map())
	sim.lit_probe = world.is_lit
	sim.gates = world.gates()
	sim.barricades = rules.barricades
	sim.board_seconds = rules.tuning.barricades.seconds_per_board
	director = ZombieDirector.new(rules, sim, world.spawn_points())
	director.spawn_gates = world.spawn_gates()
	director.player_struck.connect(_on_player_struck)
	world.bind(rules)
	world.doors.door_opened.connect(_on_door_opened)
	rules.event_emitted.connect(_on_rules_event)


## Stops listening to the rules and the doors, so nothing calls into a finished night. Call when
## the night is over.
func close() -> void:
	combat.detach()
	director.close()
	if rules.event_emitted.is_connected(_on_rules_event):
		rules.event_emitted.disconnect(_on_rules_event)
	if world.doors.door_opened.is_connected(_on_door_opened):
		world.doors.door_opened.disconnect(_on_door_opened)


## The one way in. Returns the events the message caused.
func apply(action: Dictionary) -> Array[Dictionary]:
	_outbox = []
	match action.get("type"):
		JOIN:
			_join(action["player_id"], action.get("local", false))
		LEAVE:
			_leave(action["player_id"])
		START_NIGHT:
			rules.apply(RulesAction.start())
		COMMAND:
			_pending[action.get("player_id", 1)] = NightCommand.from_dict(action)
	return _outbox


func body_of(player_id: int) -> Player:
	return _bodies.get(player_id)


func health_of(player_id: int) -> float:
	return rules.health_of(player_id)


## One fixed tick. Returns every event of it, the frame last.
func step(delta: float) -> Array[Dictionary]:
	_outbox = []
	tick_count += 1
	_move_players()
	director.tick(delta, _chase_targets())
	rules.apply(RulesAction.tick(delta))
	_combat(CombatAction.targets(_target_list()))
	_combat(CombatAction.tick(delta))
	for player_id in _bodies:
		_act(player_id, delta)
	_outbox.append(_frame())
	return _outbox


# --- Players ---


func _join(player_id: int, local: bool) -> void:
	if _bodies.has(player_id):
		return
	_bodies[player_id] = world.add_body(world.player_spawn(_bodies.size()), local)
	_shot_seq[player_id] = 0
	_repair_wait[player_id] = 0.0
	rules.apply(RulesAction.add_player(player_id))
	_combat(CombatAction.give_weapon(player_id, tuning.start_weapon))


func _leave(player_id: int) -> void:
	if _bodies.has(player_id):
		_bodies[player_id].queue_free()
		_bodies.erase(player_id)
		_pending.erase(player_id)
		rules.apply(RulesAction.remove_player(player_id))


func _is_downed(player_id: int) -> bool:
	var state: PlayerState = rules.players.get(player_id)
	return state == null or state.downed


func _move_players() -> void:
	for player_id in _bodies:
		var command := _pending.get(player_id) as NightCommand
		var motion := PlayerCommand.new()
		if command != null:
			motion.yaw = command.motion.yaw
			motion.pitch = command.motion.pitch
			if not _is_downed(player_id):
				motion = command.motion
		_bodies[player_id].tick(motion)


func _chase_targets() -> Dictionary:
	var targets := {}
	for player_id in _bodies:
		if not _is_downed(player_id):
			targets[player_id] = _bodies[player_id].global_position
	return targets


func _on_player_struck(player_id: int, zombie_id: int, damage: float) -> void:
	if not _bodies.has(player_id) or _is_downed(player_id):
		return
	var zombie: ZombieBody = sim.zombies.get(zombie_id)
	var from := _position_of_zombie(zombie_id)
	rules.apply(RulesAction.blow(player_id, damage, _bearing(player_id, from), zombie_id))
	(
		_outbox
		. append(
			{
				"type": &"player_damaged",
				"player_id": player_id,
				"damage": damage,
				"health": rules.health_of(player_id),
				"from": from,
				"zombie_id": zombie_id,
				"zombie_type": zombie.profile.type if zombie != null else &"",
				"knockback": zombie.profile.knockback if zombie != null else 0.0,
			}
		)
	)


## Radians clockwise from -z (seen from above) from the player to `from`: the bearing the rules
## carry, so a client can turn it toward where its own player faces.
func _bearing(player_id: int, from: Vector3) -> float:
	var offset := from - _bodies[player_id].global_position
	return atan2(offset.x, -offset.z)


## Where a zombie stands (the bearing of a blow); the player's own spot when it is gone.
func _position_of_zombie(zombie_id: int) -> Vector3:
	var zombie: ZombieBody = sim.zombies.get(zombie_id)
	return zombie.position if zombie != null else Vector3.ZERO


# --- What the rules decided ---


## The lot has opened a door (it follows the rules itself): the area behind it joins the spawns.
func _on_door_opened(_door_id: StringName) -> void:
	director.spawn_points = world.spawn_points()


func _on_rules_event(event: Dictionary) -> void:
	_outbox.append(event)
	match event["type"]:
		&"purchase_made":
			var weapon: StringName = event["detail"].get("weapon", &"")
			if weapon != &"":
				_combat(CombatAction.give_weapon(event["player_id"], weapon))
		&"round_ended":
			_resupply()


# --- Weapons and hands ---


func _combat(action: Dictionary) -> void:
	for event in combat.apply(action):
		if not COMBAT_EVENTS.has(event["type"]):
			continue
		if event["type"] == &"fire_rejected" and QUIET_REJECTIONS.has(event["reason"]):
			continue
		_outbox.append(event)


## The supply drop between rounds: every carried weapon gets magazines, and the hand keeps
## what it held.
func _resupply() -> void:
	for player_id in _bodies:
		var held := combat.weapon_of(player_id)
		if held == null:
			continue
		for weapon_id in combat.carried(player_id):
			for _i in tuning.resupply_magazines:
				_combat(CombatAction.give_weapon(player_id, weapon_id))
		_combat(CombatAction.equip(player_id, held.def.id))


func _target_list() -> Array:
	var list: Array = []
	for zombie: ZombieBody in sim.zombies.values():
		if zombie.is_alive():
			(
				list
				. append(
					{
						"id": zombie.id,
						"pos": zombie.position,
						"yaw": zombie.yaw,
						"scale": zombie.profile.hit_scale(),
						"weak": zombie.profile.weak,
					}
				)
			)
	return list


func _act(player_id: int, delta: float) -> void:
	_repair_wait[player_id] = maxf(_repair_wait[player_id] - delta, 0.0)
	var command := _pending.get(player_id) as NightCommand
	if command == null or _is_downed(player_id):
		return
	if command.reload:
		_combat(CombatAction.reload_weapon(player_id))
	if command.fire:
		_shoot(player_id, command)
	if command.use:
		_use(player_id)
	# Edges are used once.
	command.reload = false
	command.use = false


func _shoot(player_id: int, command: NightCommand) -> void:
	var body := _bodies[player_id]
	var head := body.global_position + Vector3(0.0, tuning.eye_height, 0.0)
	var origin := command.origin
	if origin.distance_to(head) > tuning.origin_slack:
		origin = head + (origin - head).normalized() * tuning.origin_slack
	var muzzle := body.global_position + Basis(Vector3.UP, body.state.facing) * tuning.muzzle_offset
	_shot_seq[player_id] += 1
	_combat(
		CombatAction.fire(player_id, _shot_seq[player_id], origin, command.dir, muzzle, combat.now)
	)


## What `use` would do for a player right now: `{}`, a door to buy or `{"kind": &"repair", "id",
## "boards"}` for a breach with a board down that the player stands inside, in reach of.
func use_target(player_id: int) -> Dictionary:
	var body := _bodies.get(player_id) as Player
	if body == null:
		return {}
	var here := body.global_position
	for door_id in world.door_ids():
		if rules.is_door_open(door_id):
			continue
		var item := rules.tuning.economy.item(door_id)
		if item.requires != &"" and not rules.is_door_open(item.requires):
			continue
		for point in world.door_points(door_id):
			if _flat(here, point) <= tuning.use_reach:
				return {"kind": &"door", "id": door_id, "price": rules.price_of(door_id)}
	for id in world.barricade_ids():
		var boards := rules.barricades.boards_of(id)
		if boards >= rules.tuning.barricades.boards:
			continue
		var barricade := world.barricade(id)
		if barricade.depth_of(here) > 0.0 and _flat(here, barricade.centre()) <= tuning.use_reach:
			return {"kind": &"repair", "id": id, "boards": boards}
	return {}


func _use(player_id: int) -> void:
	var target := use_target(player_id)
	match target.get("kind"):
		&"door":
			rules.apply(RulesAction.buy(player_id, target["id"]))
		&"repair":
			if _repair_wait[player_id] <= 0.0:
				_repair_wait[player_id] = tuning.repair_interval
				rules.apply(RulesAction.repair(player_id, target["id"]))


# --- The picture clients draw ---


func _frame() -> Dictionary:
	var players := {}
	for player_id in _bodies:
		var body := _bodies[player_id]
		var weapon := combat.weapon_of(player_id)
		players[player_id] = {
			"pos": body.global_position,
			"facing": body.state.facing,
			"health": rules.health_of(player_id),
			"downed": _is_downed(player_id),
			"weapon": weapon.def.id if weapon != null else &"",
			"ammo": weapon.ammo if weapon != null else 0,
			"reserve": weapon.reserve if weapon != null else 0,
			"reloading": weapon != null and weapon.is_reloading(),
			"points": rules.points_of(player_id),
			"prompt": use_target(player_id),
		}
	return {
		"type": &"frame",
		"tick": tick_count,
		"phase": rules.phase,
		"round": rules.round_number,
		"remaining": rules.zombies_remaining(),
		"fuel": rules.generator.fuel,
		"doors": rules.doors_open.duplicate(),
		"barricades": rules.barricades.to_dict(),
		"zombies": ZombieCodec.encode(sim.zombies),
		"players": players,
	}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
