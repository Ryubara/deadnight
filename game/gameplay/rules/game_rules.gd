class_name GameRules
extends RefCounted
## The night's rules: rounds, spawn pacing, points, the shop and the generator. Server-first and
## headless.
##
## All state lives in this one object (its fields, its PlayerState and GeneratorState parts, two
## seeded random generators) and nothing else: no scene-tree node, no Godot multiplayer, no clock,
## no global random. It changes only through `apply(action)`, a plain dictionary from `RulesAction`,
## and answers with the events that action caused, a list of plain dictionaries `{"type":
## StringName, ...fields}`. The same events are also sent through `event_emitted`, after the state
## has settled. A server calls `apply`, broadcasts the events, and a client mirrors them; single-
## player runs the same object in-process. `to_dict()` / `from_dict()` snapshot and restore
## everything, including the random streams, so a restored copy continues exactly as the original
## would.
##
## The rules own every zombie's health: a `hit` takes damage off it, pays only while the zombie
## lives, and the hit that empties it is the kill. Nothing but the rules decides a kill.
##
## Time passes only through `RulesAction.tick(delta)`, a fixed step the caller owns.
##
## Events (fields besides `type`):
##   phase_changed: phase
##   break_started: next_round, seconds
##   special_round_announced: round (the coming one), special_id, title, kind (boss or only),
##     boss_type, boss_count, seconds (until it starts); right after the break_started of the break
##     before a special round
##   round_started: round, zombie_count, special_id (&"" for a normal round), boss_count
##   special_round_cleared: round, special_id, reward (paid to each player on their feet)
##   round_ended: round, special_id
##   zombie_spawn_requested: zombie_id, zombie_type, look, boss, health, speed, point_roll (spawn
##     point = point_roll % count), damage, knockback, telegraph_seconds, barrier_speed, hit_chance
##   zombie_damaged: zombie_id, zombie_type, player_id, zone, damage (what was taken off), health
##     (left), max_health
##   zombie_removed: zombie_id, zombie_type, boss, cause (killed or gone), killer_id (-1 when no
##     player), zone, melee
##   zombie_crippled: zombie_id, zombie_type (the crawler it became), player_id, cause (legs or
##     wounded), health, speed_scale
##   grenade_count_changed: player_id, count, reason (thrown, refill, purchase)
##   player_added: player_id, grenades (the count they start with), health, max_health
##   player_hurt: player_id, damage, health (left), max_health, bearing (radians clockwise from -z,
##     seen from above, where the blow came from), source_id (the zombie, -1 for none)
##   player_healed: player_id, health, max_health, reason (regen or revive); regen sends one when
##     the whole-unit health changes, about once per unit mended
##   player_downed: player_id, cause (blow or forced), bearing (0 unless a blow)
##   player_removed, player_revived: player_id
##   points_changed: player_id, total, delta, reason
##   purchase_made: player_id, item_id, price, detail (a weapon: `weapon`; ammunition: `ammo`, the
##     catalogue weapon, and `rounds` into its reserve; a crane play: `crane_spot`, see CranePlay)
##   purchase_denied: player_id, item_id, result (a BuyResult)
##   crane_*: the prize crane's play, see `CranePlay`
##   door_opened: door_id
##   board_torn: barricade_id, boards (left), zombie_id (the one that pulled it off)
##   board_repaired: barricade_id, boards (now up), player_id
##   fuel_changed: fuel (exact), delta (whole units since the last one); only when the whole-unit
##     value changes, so about once per unit burnt or bought, not once per tick
##   fuel_low, fuel_empty, fuel_restored
##   circuit_changed: circuit_id, on
##   game_over: reason (all_down or no_players), round_reached
##   action_rejected: reason, action (the type), field (when one field is to blame)

signal event_emitted(event: Dictionary)

enum Phase { IDLE, BREAK, ACTIVE, OVER }
enum BuyResult {
	OK,
	UNKNOWN_ITEM,
	UNKNOWN_PLAYER,
	WRONG_PHASE,
	NOT_ENOUGH_POINTS,
	ALREADY_OWNED,
	LOCKED,
	LIMIT_REACHED,
	TANK_FULL,
	AMMO_FULL,
	CRANE_BUSY,
}

const DEFAULT_TUNING_PATH := "res://gameplay/rules/default_tuning.tres"
## 8 added the prize crane (`crane`, `crane_rng_state`), 7 the fence's `barricades`, 6 each player's
## health, 5 the plan, special round and a zombie's type, health, speed. Two older layouts both
## called themselves 4; every older snapshot is refused as `bad_version`.
const SNAPSHOT_VERSION := 8
## A snapshot restore answers with one of these (`&""` when it worked).
const RESTORE_BAD_VERSION := &"bad_version"
const RESTORE_WRONG_TUNING := &"wrong_tuning"
const RESTORE_MALFORMED := &"malformed"
## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"version": TYPE_INT,
	"tuning_id": TYPE_STRING,
	"seed": TYPE_INT,
	"phase": TYPE_INT,
	"round": TYPE_INT,
	"break_left": TYPE_FLOAT,
	"plan": TYPE_ARRAY,
	"special_id": TYPE_STRING,
	"round_total": TYPE_INT,
	"spawn_timer": TYPE_FLOAT,
	"round_players": TYPE_INT,
	"next_zombie_id": TYPE_INT,
	"zombies": TYPE_DICTIONARY,
	"players": TYPE_DICTIONARY,
	"doors_open": TYPE_ARRAY,
	"generator": TYPE_DICTIONARY,
	"barricades": TYPE_DICTIONARY,
	"crane": TYPE_DICTIONARY,
	"spawn_rng_state": TYPE_INT,
	"shop_rng_state": TYPE_INT,
	"cripple_rng_state": TYPE_INT,
	"crane_rng_state": TYPE_INT,
}
## A fuel purchase needs at least this much room in the tank.
const MIN_FUEL_SPACE := 1.0
## Offsets so the spawn and shop generators never share a stream.
const SPAWN_STREAM := 0x5A17
const SHOP_STREAM := 0x70C3
const CRIPPLE_STREAM := 0xC21B
const CRANE_STREAM := 0xC4A7

var tuning: RulesTuning
var rng_seed: int = 0
var phase: Phase = Phase.IDLE
var round_number: int = 0
var generator: GeneratorState
var barricades: BarricadeState
var crane: CraneState
var players: Dictionary[int, PlayerState] = {}
var doors_open: Array[StringName] = []

var _break_left: float = 0.0
## The types still to spawn this round, in order.
var _plan: Array[StringName] = []
## The special round now running, or null.
var _special: SpecialRound = null
## Zombies the round began with (`round_started`'s `zombie_count`); kept after it ends.
var _round_total: int = 0
var _spawn_timer: float = 0.0
var _round_players: int = 1
var _next_zombie_id: int = 1
var _zombies: Dictionary[int, ZombieState] = {}
var _spawn_rng := RandomNumberGenerator.new()
var _shop_rng := RandomNumberGenerator.new()
var _cripple_rng := RandomNumberGenerator.new()
var _crane_rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
## The whole-unit fuel value the last `fuel_changed` event announced.
var _fuel_announced: int = 0


## A fresh night. `p_tuning` defaults to the shipped table.
func _init(p_tuning: RulesTuning = null, p_seed: int = 0) -> void:
	tuning = p_tuning if p_tuning != null else load(DEFAULT_TUNING_PATH)
	rng_seed = p_seed
	_spawn_rng.seed = p_seed ^ SPAWN_STREAM
	_shop_rng.seed = p_seed ^ SHOP_STREAM
	_cripple_rng.seed = p_seed ^ CRIPPLE_STREAM
	_crane_rng.seed = p_seed ^ CRANE_STREAM
	crane = CraneState.new(tuning.crane.start_spot)
	generator = GeneratorState.new(tuning.fuel)
	barricades = BarricadeState.new(tuning.barricades)
	_fuel_announced = floori(generator.fuel)
	# Methods and `bind`, never a lambda: a lambda that uses `self` holds a strong reference to
	# the rules, the rules hold the generator, and the generator holds the lambda, so none of
	# them is ever freed (the "resources still in use at exit" error).
	generator.fuel_changed.connect(_on_fuel_changed)
	generator.fuel_low.connect(_emit.bind(&"fuel_low"))
	generator.fuel_empty.connect(_emit.bind(&"fuel_empty"))
	generator.fuel_restored.connect(_emit.bind(&"fuel_restored"))
	generator.circuit_changed.connect(_on_circuit_changed)


## The one way in. Returns the events the action caused, in order.
func apply(action: Dictionary) -> Array[Dictionary]:
	_events = []
	var problem := RulesAction.validate(action)
	if problem.is_empty():
		_dispatch(action)
	else:
		_reject(problem["reason"], action.get("type"), problem["field"])
	var caused := _events
	for event in caused:
		event_emitted.emit(event)
	return caused


# --- Queries (read-only) ---


func points_of(player_id: int) -> int:
	var player := players.get(player_id) as PlayerState
	return player.points if player != null else 0


func is_door_open(door_id: StringName) -> bool:
	return doors_open.has(door_id)


## What an item costs right now, or -1 when there is no such item.
func price_of(item_id: StringName) -> int:
	var item := tuning.economy.item(item_id)
	return item.price_at(round_number) if item != null else -1


## A player's health (0 when they are down or unknown).
func health_of(player_id: int) -> float:
	var player := players.get(player_id) as PlayerState
	return player.health if player != null else 0.0


func max_health_of(player_id: int) -> float:
	var player := players.get(player_id) as PlayerState
	return player.max_health if player != null else 0.0


func grenades_of(player_id: int) -> int:
	var player := players.get(player_id) as PlayerState
	return player.grenades if player != null else 0


## Whether a living zombie has lost its legs (false for one that is gone).
func is_crippled(zombie_id: int) -> bool:
	var zombie := _zombies.get(zombie_id) as ZombieState
	return zombie != null and zombie.crippled


## Whether this zombie is alive right now (spawned and not yet gone).
func has_zombie(zombie_id: int) -> bool:
	return _zombies.has(zombie_id)


## Zombies still to spawn plus those alive: the round ends at zero.
func zombies_remaining() -> int:
	return _plan.size() + _zombies.size()


## The ids of the zombies alive now, in the order they spawned.
func zombie_ids() -> Array[int]:
	return _zombies.keys()


## What type a living zombie is, or `&""` when there is no such zombie.
func zombie_type(zombie_id: int) -> StringName:
	var zombie := _zombies.get(zombie_id) as ZombieState
	return zombie.type if zombie != null else &""


## A living zombie's health, or 0 when there is none.
func zombie_health(zombie_id: int) -> float:
	var zombie := _zombies.get(zombie_id) as ZombieState
	return zombie.health if zombie != null else 0.0


## The special round now running (a kind's id), or `&""` in a normal round and in breaks.
func special_id() -> StringName:
	return _special.id if _special != null else &""


# --- Snapshot ---


## Everything, as plain Variant data. The tuning table itself is not included (both sides load the
## same one) but its fingerprint is, and a restore refuses a different table. This dictionary is
## exact only as Variant data: through JSON the integer keys, the 64-bit random states and some
## floats change. For a save file or the wire use `to_bytes()` or `to_wire()`.
func to_dict() -> Dictionary:
	return RulesSnapshot.take(self)


## The snapshot as bytes (`var_to_bytes`), exact in every number and key. Store these, or send
## them as a binary message.
func to_bytes() -> PackedByteArray:
	return var_to_bytes(to_dict())


## The snapshot as a base64 string: the form to put inside JSON (a save, an HTTP body), exact too.
func to_wire() -> String:
	return Marshalls.raw_to_base64(to_bytes())


## Restores from `to_bytes()`. Returns what `from_dict` returns.
func from_bytes(bytes: PackedByteArray) -> StringName:
	var data: Variant = bytes_to_var(bytes)
	if typeof(data) != TYPE_DICTIONARY:
		return RESTORE_MALFORMED
	return from_dict(data)


## Restores from `to_wire()`. Returns what `from_dict` returns.
func from_wire(wire: String) -> StringName:
	return from_bytes(Marshalls.base64_to_raw(wire))


## Replaces this night's state with a snapshot. Emits no events: a restore is not a change.
## Returns `&""` when it worked, else why it did not (`RESTORE_*`) with this night left untouched:
## a snapshot of another version (any older layout too), of another tuning table, or one that is
## not a snapshot, or whose insides do not fit (a zombie without a type, a plan naming no type).
func from_dict(data: Dictionary) -> StringName:
	return RulesSnapshot.restore(self, data)


# --- Actions ---


func _dispatch(action: Dictionary) -> void:
	match action.get("type", &""):
		RulesAction.START:
			if players.is_empty():
				_reject(&"no_players", RulesAction.START)
			elif phase == Phase.IDLE:
				_enter_break(tuning.rounds.intro_seconds)
		RulesAction.TICK:
			_tick(action["delta"])
		RulesAction.SKIP_BREAK:
			if phase == Phase.BREAK:
				_begin_round()
		RulesAction.ADD_PLAYER:
			_add_player(action["player_id"])
		RulesAction.REMOVE_PLAYER:
			if players.erase(action["player_id"]):
				CranePlay.buyer_left(self, action["player_id"])
				_emit(&"player_removed", {"player_id": action["player_id"]})
				_check_game_over()
		RulesAction.SET_DOWNED:
			_set_downed(action["player_id"], action["downed"])
		RulesAction.BLOW:
			_blow(action)
		RulesAction.HIT:
			_hit(action)
		RulesAction.ZOMBIE_GONE:
			if _zombies.has(action["zombie_id"]):
				_remove_zombie(action["zombie_id"], &"gone", -1)
			else:
				_reject(&"unknown_zombie", RulesAction.ZOMBIE_GONE)
		RulesAction.REPAIR:
			_repair(action["player_id"], StringName(action["barricade_id"]))
		RulesAction.TEAR_BOARD:
			_tear_board(StringName(action["barricade_id"]), action["zombie_id"])
		RulesAction.BUY:
			_buy(action["player_id"], action["item_id"], action.get("rounds", -1))
		RulesAction.CRANE_TAKE:
			CranePlay.take(self, action["player_id"])
		RulesAction.SET_CIRCUIT:
			if not generator.set_circuit(action["circuit_id"], action["on"]):
				_reject(&"unknown_circuit", RulesAction.SET_CIRCUIT)
		RulesAction.USE_GRENADE:
			_use_grenade(action["player_id"])
		RulesAction.EXPLOSION:
			_explosion(action["player_id"], action["victims"])
		RulesAction.GRANT_POINTS:
			if players.has(action["player_id"]):
				_award(action["player_id"], action["amount"], action.get("reason", &"grant"))
			else:
				_reject(&"unknown_player", RulesAction.GRANT_POINTS)


## Tells the sender its action did nothing. `action_rejected` is for that sender, not a broadcast.
func _reject(reason: StringName, action_type: Variant, field: StringName = &"") -> void:
	var fields := {"reason": reason, "action": action_type}
	if field != &"":
		fields["field"] = field
	_emit(&"action_rejected", fields)


func _emit(type: StringName, fields: Dictionary = {}) -> void:
	var event := {"type": type}
	event.merge(fields)
	_events.append(event)


## The generator reports every tick; the rules announce a change only when the whole-unit value
## moves (low, empty and restored are separate events and still fire at their exact moments).
func _on_fuel_changed(fuel: float, _delta: float) -> void:
	var whole := floori(fuel)
	if whole == _fuel_announced:
		return
	_emit(&"fuel_changed", {"fuel": fuel, "delta": float(whole - _fuel_announced)})
	_fuel_announced = whole


func _on_circuit_changed(circuit_id: StringName, on: bool) -> void:
	_emit(&"circuit_changed", {"circuit_id": circuit_id, "on": on})


# --- Rounds ---


func _tick(delta: float) -> void:
	match phase:
		Phase.BREAK:
			generator.tick(delta, round_number, true)
			CranePlay.tick(self, delta)
			_events.append_array(PlayerHealth.mend(players, tuning.health, delta))
			_break_left -= delta
			if _break_left <= 0.0:
				_begin_round()
		Phase.ACTIVE:
			generator.tick(delta, round_number, false)
			CranePlay.tick(self, delta)
			_events.append_array(PlayerHealth.mend(players, tuning.health, delta))
			_tick_spawning(delta)


func _enter_break(seconds: float) -> void:
	var coming := tuning.specials.special_for(round_number + 1)
	if coming != null:
		seconds += tuning.specials.break_bonus_seconds
	_break_left = seconds
	_set_phase(Phase.BREAK)
	_emit(&"break_started", {"next_round": round_number + 1, "seconds": seconds})
	if coming != null:
		_emit(
			&"special_round_announced",
			coming.announcement(round_number + 1, players.size(), seconds)
		)


func _begin_round() -> void:
	round_number += 1
	_round_players = maxi(players.size(), 1)
	_special = tuning.specials.special_for(round_number)
	_plan = _plan_round()
	_round_total = _plan.size()
	_spawn_timer = tuning.rounds.first_spawn_delay
	for player: PlayerState in players.values():
		_refill_grenades(player)
	_set_phase(Phase.ACTIVE)
	_emit(
		&"round_started",
		{
			"round": round_number,
			"zombie_count": _plan.size(),
			"special_id": special_id(),
			"boss_count": _boss_count(),
		}
	)


## The types of every zombie of the round, in the order they spawn.
func _plan_round() -> Array[StringName]:
	var normal := tuning.rounds.zombies_for_round(round_number, _round_players)
	if _special == null:
		return tuning.roster.plan_for_round(round_number, normal, _spawn_rng)
	return _special.plan(round_number, _round_players, normal, tuning.roster, _spawn_rng)


func _boss_count() -> int:
	if _special == null or _special.kind != SpecialRound.Kind.BOSS:
		return 0
	return _plan.count(_special.boss_type)


## The type table's entry, or the common one when a table names a type it does not hold.
func _type(type_id: StringName) -> ZombieType:
	var found := tuning.roster.type_of(type_id)
	return found if found != null else tuning.roster.type_of(tuning.roster.base_id)


func _tick_spawning(delta: float) -> void:
	_spawn_timer -= delta
	var cap := tuning.rounds.alive_cap(round_number, _round_players)
	var interval := tuning.rounds.spawn_interval(round_number, _round_players)
	if _special != null and _special.kind == SpecialRound.Kind.ONLY:
		interval /= _special.spawn_rate
	while _spawn_timer <= 0.0 and not _plan.is_empty() and _zombies.size() < cap:
		_spawn_one()
		_spawn_timer += interval
	# A full lot or an empty queue holds the next spawn ready instead of banking a burst.
	_spawn_timer = maxf(_spawn_timer, 0.0)


func _spawn_one() -> void:
	var zombie_id := _next_zombie_id
	_next_zombie_id += 1
	var type := _type(_plan.pop_front())
	var health := (
		tuning.rounds.health_for_round(round_number)
		* type.health_multiplier
		* (1.0 + type.health_per_extra_player * float(_round_players - 1))
	)
	var speed := tuning.rounds.roll_speed(round_number, _spawn_rng, type.speed_multiplier)
	var point_roll := _spawn_rng.randi()
	_zombies[zombie_id] = ZombieState.new(zombie_id, health, type.id, speed)
	_emit(
		&"zombie_spawn_requested",
		{
			"zombie_id": zombie_id,
			"zombie_type": type.id,
			"look": type.look_for(point_roll),
			"boss": type.boss,
			"health": health,
			"speed": speed,
			"point_roll": point_roll,
			"damage": type.damage,
			"knockback": type.knockback,
			"telegraph_seconds": type.telegraph_seconds,
			"barrier_speed": type.barrier_speed,
			"hit_chance": type.hit_chance,
		}
	)


func _remove_zombie(
	zombie_id: int, cause: StringName, killer_id: int, zone: StringName = &"", melee: bool = false
) -> void:
	var type := _type(_zombies[zombie_id].type)
	_zombies.erase(zombie_id)
	_emit(
		&"zombie_removed",
		{
			"zombie_id": zombie_id,
			"zombie_type": type.id,
			"boss": type.boss,
			"cause": cause,
			"killer_id": killer_id,
			"zone": zone,
			"melee": melee,
		}
	)
	if phase == Phase.ACTIVE and _plan.is_empty() and _zombies.is_empty():
		_end_round()


func _end_round() -> void:
	var economy := tuning.economy
	for player: PlayerState in players.values():
		# The cap on repair pay runs from one round's end to the next: the break's repairs count.
		player.repair_points_this_round = 0
		if player.downed:
			var penalty := floori(player.points * economy.down_penalty_fraction)
			if penalty > 0:
				player.points -= penalty
				_emit(
					&"points_changed",
					{
						"player_id": player.id,
						"total": player.points,
						"delta": -penalty,
						"reason": &"down_penalty",
					}
				)
			_events.append_array(PlayerHealth.revive(player, tuning.health))
		else:
			_award(player.id, economy.round_bonus(round_number), &"round_bonus")
			if _special != null:
				_award(player.id, _special.reward_at(round_number), &"special_reward")
	if _special != null:
		_emit(&"special_round_cleared", _special.cleared(round_number))
	_emit(&"round_ended", {"round": round_number, "special_id": special_id()})
	_special = null
	_enter_break(tuning.rounds.break_seconds)


## The night ends when nobody is left in it (a break or a round) or, in a round, everyone is down.
func _check_game_over() -> void:
	if phase != Phase.ACTIVE and phase != Phase.BREAK:
		return
	if players.is_empty():
		_end_night(&"no_players")
		return
	if phase != Phase.ACTIVE:
		return
	for player: PlayerState in players.values():
		if not player.downed:
			return
	_end_night(&"all_down")


func _end_night(reason: StringName) -> void:
	_set_phase(Phase.OVER)
	_emit(&"game_over", {"reason": reason, "round_reached": round_number})


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	_emit(&"phase_changed", {"phase": new_phase})


# --- Players and points ---


func _add_player(player_id: int) -> void:
	if players.has(player_id):
		return
	var added := PlayerState.new(player_id, tuning.economy.start_points)
	added.grenades = tuning.explosives.start_grenades
	PlayerHealth.start(added, tuning.health)
	players[player_id] = added
	_emit(
		&"player_added",
		{
			"player_id": player_id,
			"grenades": added.grenades,
			"health": added.health,
			"max_health": added.max_health,
		}
	)
	_emit(
		&"points_changed",
		{
			"player_id": player_id,
			"total": tuning.economy.start_points,
			"delta": tuning.economy.start_points,
			"reason": &"start",
		}
	)


func _set_downed(player_id: int, downed: bool) -> void:
	var player := players.get(player_id) as PlayerState
	if player == null or player.downed == downed:
		return
	if downed:
		_events.append(PlayerHealth.down(player, &"forced", 0.0))
		_check_game_over()
	else:
		_events.append_array(PlayerHealth.revive(player, tuning.health))


## A blow takes health off, restarts the wait before it mends, and downs the player at zero.
func _blow(action: Dictionary) -> void:
	var player := players.get(action["player_id"]) as PlayerState
	if phase != Phase.ACTIVE:
		_reject(&"wrong_phase", RulesAction.BLOW)
	elif player == null:
		_reject(&"unknown_player", RulesAction.BLOW)
	elif player.downed:
		_reject(&"player_downed", RulesAction.BLOW)
	else:
		_events.append_array(
			PlayerHealth.hurt(
				player, action["damage"], action.get("bearing", 0.0), action.get("source_id", -1)
			)
		)
		if player.downed:
			_check_game_over()


func _award(player_id: int, amount: int, reason: StringName) -> void:
	if amount <= 0:
		return
	var player: PlayerState = players[player_id]
	player.points += amount
	player.points_earned += amount
	_emit(
		&"points_changed",
		{"player_id": player_id, "total": player.points, "delta": amount, "reason": reason}
	)


## A hit takes damage off the zombie's health. While health is left it pays a little (for the
## first few hits only); the hit that empties it is the kill and pays by how it was made. A hit on
## a zombie that is not alive (dead, gone, never spawned) is rejected and pays nothing.
func _hit(action: Dictionary) -> void:
	var player_id: int = action["player_id"]
	var zombie_id: int = action["zombie_id"]
	var problem := _hit_problem(player_id, zombie_id)
	if problem != &"":
		_reject(problem, RulesAction.HIT)
		return
	var player: PlayerState = players[player_id]
	var zombie: ZombieState = _zombies[zombie_id]
	var zone := StringName(action["zone"])
	var melee: bool = action.get("melee", false)
	var headshot := zone == RulesAction.ZONE_HEAD or zone == RulesAction.ZONE_WEAK
	var type := _type(zombie.type)
	var damage := float(action["damage"])
	if zone == RulesAction.ZONE_WEAK:
		damage *= type.weak_multiplier
	var dealt := minf(damage, zombie.health)
	zombie.health -= dealt
	_emit_damaged(zombie, player_id, zone, dealt)
	if zombie.health > 0.0:
		if zombie.paid_hits < _paid_hit_limit(type):
			zombie.paid_hits += 1
			var pay := tuning.economy.headshot_hit if headshot else tuning.economy.hit
			_award(player_id, _scaled(pay, type), &"headshot_hit" if headshot else &"hit")
		return
	player.kills += 1
	if melee:
		_award(player_id, _scaled(tuning.economy.melee_kill, type), &"melee_kill")
	elif headshot:
		player.headshot_kills += 1
		_award(player_id, _scaled(tuning.economy.headshot_kill, type), &"headshot_kill")
	else:
		_award(player_id, _scaled(tuning.economy.kill, type), &"kill")
	_remove_zombie(zombie_id, &"killed", player_id, zone, melee)


## The one `zombie_damaged` event, for a shot and a blast alike, so the two cannot drift apart.
func _emit_damaged(zombie: ZombieState, player_id: int, zone: StringName, dealt: float) -> void:
	_emit(
		&"zombie_damaged",
		{
			"zombie_id": zombie.id,
			"zombie_type": zombie.type,
			"player_id": player_id,
			"zone": zone,
			"damage": dealt,
			"health": zombie.health,
			"max_health": zombie.max_health,
		}
	)


## How many non-lethal hits on a zombie of this type pay.
func _paid_hit_limit(type: ZombieType) -> int:
	return type.max_paid_hits if type.max_paid_hits > 0 else tuning.economy.max_paid_hits


func _scaled(points: int, type: ZombieType) -> int:
	return roundi(float(points) * type.points_multiplier)


## Why this hit cannot land, or an empty name when it can.
func _hit_problem(player_id: int, zombie_id: int) -> StringName:
	var player := players.get(player_id) as PlayerState
	if phase != Phase.ACTIVE:
		return &"wrong_phase"
	if player == null:
		return &"unknown_player"
	if player.downed:
		return &"player_downed"
	if not _zombies.has(zombie_id):
		return &"unknown_zombie"
	return &""


# --- Grenades ---


## One grenade leaves the hand. Refused when the player has none (or the night is not on).
func _use_grenade(player_id: int) -> void:
	var player := players.get(player_id) as PlayerState
	if player == null:
		_reject(&"unknown_player", RulesAction.USE_GRENADE)
	elif phase != Phase.ACTIVE:
		_reject(&"wrong_phase", RulesAction.USE_GRENADE)
	elif player.downed:
		_reject(&"player_downed", RulesAction.USE_GRENADE)
	elif player.grenades <= 0:
		_reject(&"no_grenades", RulesAction.USE_GRENADE)
	else:
		_set_grenades(player, player.grenades - 1, &"thrown")


func _refill_grenades(player: PlayerState) -> void:
	var target := mini(tuning.explosives.refill_to, tuning.explosives.max_grenades)
	if player.grenades < target:
		_set_grenades(player, target, &"refill")


func _set_grenades(player: PlayerState, count: int, reason: StringName) -> void:
	player.grenades = clampi(count, 0, tuning.explosives.max_grenades)
	_emit(
		&"grenade_count_changed",
		{"player_id": player.id, "count": player.grenades, "reason": reason}
	)


## One blast: what it did to each zombie, in the order given. Each takes its damage off its health
## and pays like a hit (the blast that kills pays `explosion_kill`); a zombie that lives may then
## lose its legs. A zombie already gone is skipped, so a blast racing a gunshot is harmless.
func _explosion(player_id: int, victims: Array) -> void:
	if phase != Phase.ACTIVE:
		_reject(&"wrong_phase", RulesAction.EXPLOSION)
		return
	if not players.has(player_id):
		_reject(&"unknown_player", RulesAction.EXPLOSION)
		return
	for victim: Dictionary in victims:
		var zombie := _zombies.get(int(victim["zombie_id"])) as ZombieState
		if zombie != null:
			_blast_one(player_id, zombie, float(victim["damage"]), float(victim["leg_damage"]))


func _blast_one(player_id: int, zombie: ZombieState, damage: float, leg_damage: float) -> void:
	var type := _type(zombie.type)
	var dealt := minf(damage, zombie.health)
	zombie.health -= dealt
	zombie.leg_damage += minf(leg_damage, dealt)
	_emit_damaged(zombie, player_id, RulesAction.ZONE_BLAST, dealt)
	if zombie.health <= 0.0:
		_award(player_id, _scaled(tuning.explosives.explosion_kill, type), &"explosion_kill")
		players[player_id].kills += 1
		_remove_zombie(zombie.id, &"killed", player_id, RulesAction.ZONE_BLAST, false)
		return
	if zombie.paid_hits < _paid_hit_limit(type):
		zombie.paid_hits += 1
		_award(player_id, _scaled(tuning.economy.hit, type), &"hit")
	var cause := _cripple_cause(zombie)
	if cause != &"":
		zombie.crippled = true
		var crawler := tuning.roster.type_of(_type(zombie.type).crawls_into)
		if crawler != null:
			zombie.type = crawler.id
		_emit(
			&"zombie_crippled",
			{
				"zombie_id": zombie.id,
				"zombie_type": zombie.type,
				"look": _type(zombie.type).look_for(zombie.id << 8),
				"player_id": player_id,
				"cause": cause,
				"health": zombie.health,
				"speed_scale": tuning.explosives.crawler_speed_fraction,
			}
		)


## Why a zombie that survived a blast loses its legs, or an empty name. Its legs go when enough of
## the blast landed on them; failing that, a zombie left badly hurt (inside the band) may lose them
## on a seeded roll. The roll is drawn only for a zombie in the band, so the stream is a function
## of the blasts alone.
func _cripple_cause(zombie: ZombieState) -> StringName:
	if zombie.crippled:
		return &""
	var x := tuning.explosives
	if zombie.leg_damage >= x.leg_fraction * zombie.max_health:
		return &"legs"
	var fraction := zombie.health / zombie.max_health
	if fraction >= x.band_low and fraction <= x.band_high:
		if _cripple_rng.randf() < x.band_chance:
			return &"wounded"
	return &""


## A player puts one board back, in a break or a round; the board goes up whatever the cap says.
func _repair(player_id: int, id: StringName) -> void:
	var player := players.get(player_id) as PlayerState
	var refusal := &""
	if player == null:
		refusal = &"unknown_player"
	elif player.downed:
		refusal = &"player_downed"
	elif phase != Phase.ACTIVE and phase != Phase.BREAK:
		refusal = &"wrong_phase"
	else:
		refusal = barricades.repair(id)
	if refusal != &"":
		_reject(refusal, RulesAction.REPAIR, BarricadeState.field_for(refusal))
		return
	var boards := barricades.boards_of(id)
	_emit(&"board_repaired", {"barricade_id": id, "boards": boards, "player_id": player_id})
	_award(player_id, player.repair_pay(tuning.economy), &"repair")


## A zombie pulled a board off (the zombie simulation's work, sent by the server).
func _tear_board(id: StringName, zombie_id: int) -> void:
	var refusal := barricades.tear(id) if _zombies.has(zombie_id) else &"unknown_zombie"
	if refusal != &"":
		_reject(refusal, RulesAction.TEAR_BOARD, BarricadeState.field_for(refusal, &"zombie_id"))
		return
	var boards := barricades.boards_of(id)
	_emit(&"board_torn", {"barricade_id": id, "boards": boards, "zombie_id": zombie_id})


# --- The shop ---


func _buy(player_id: int, item_id: StringName, rounds: int = -1) -> void:
	var quote := _quote(player_id, item_id, rounds)
	if quote.result != BuyResult.OK:
		_emit(
			&"purchase_denied", {"player_id": player_id, "item_id": item_id, "result": quote.result}
		)
		return
	var player: PlayerState = players[player_id]
	player.points -= quote.price
	player.points_spent += quote.price
	_emit(
		&"points_changed",
		{
			"player_id": player_id,
			"total": player.points,
			"delta": -quote.price,
			"reason": &"purchase",
		}
	)
	var detail := _grant(player, quote)
	_emit(
		&"purchase_made",
		{"player_id": player_id, "item_id": item_id, "price": quote.price, "detail": detail}
	)
	if quote.item.kind == ShopItem.Kind.CRANE:
		_emit(
			&"crane_spin_started",
			{
				"player_id": player_id,
				"spot": crane.spot,
				"seconds": tuning.crane.spin_seconds,
				"plays": crane.plays,
			}
		)


func _quote(player_id: int, item_id: StringName, rounds: int = -1) -> Quote:
	var quote := Quote.new()
	var player := players.get(player_id) as PlayerState
	var item := tuning.economy.item(item_id)
	if phase != Phase.BREAK and phase != Phase.ACTIVE:
		quote.result = BuyResult.WRONG_PHASE
	elif player == null:
		quote.result = BuyResult.UNKNOWN_PLAYER
	elif item == null:
		quote.result = BuyResult.UNKNOWN_ITEM
	else:
		quote.item = item
		quote.price = item.price_at(round_number)
		quote.rounds_offered = rounds
		quote.result = _check_item(player, quote)
	if quote.result == BuyResult.OK and player.points < quote.price:
		quote.result = BuyResult.NOT_ENOUGH_POINTS
	return quote


## Whether the item can be sold to this player at all, ignoring their points. A fuel quote also gets
## its real price: you pay only for the room in the tank.
func _check_item(player: PlayerState, quote: Quote) -> BuyResult:
	var item := quote.item
	var result := BuyResult.OK
	match item.kind:
		ShopItem.Kind.DOOR:
			if doors_open.has(item.id):
				result = BuyResult.ALREADY_OWNED
			elif item.requires != &"" and not doors_open.has(item.requires):
				result = BuyResult.LOCKED
		ShopItem.Kind.WEAPON:
			if player.weapons.has(item.id):
				result = BuyResult.ALREADY_OWNED
		ShopItem.Kind.CRANE:
			if item.pool_without(player.weapons).is_empty():
				result = BuyResult.ALREADY_OWNED
			elif not crane.is_ready():
				result = BuyResult.CRANE_BUSY
		ShopItem.Kind.TONIC:
			if player.tonics.has(item.id):
				result = BuyResult.ALREADY_OWNED
			elif player.tonics.size() >= tuning.economy.max_tonics:
				result = BuyResult.LIMIT_REACHED
		ShopItem.Kind.GRENADES:
			var room := tuning.explosives.max_grenades - player.grenades
			if room <= 0:
				result = BuyResult.LIMIT_REACHED
			else:
				quote.grenades_added = mini(int(item.amount), room)
				quote.price = ceili(float(quote.price) * quote.grenades_added / item.amount)
		ShopItem.Kind.AMMO:
			# The weapon's reserve is the combat server's: the buyer says how many rounds fit
			# (none given: all of them) and the rules price exactly those.
			var fit := int(item.amount)
			if quote.rounds_offered >= 0:
				fit = mini(quote.rounds_offered, fit)
			if fit <= 0:
				result = BuyResult.AMMO_FULL
			else:
				quote.ammo_added = fit
				quote.price = item.ammo_price(round_number, fit)
		ShopItem.Kind.FUEL:
			if generator.space() < MIN_FUEL_SPACE:
				result = BuyResult.TANK_FULL
			else:
				quote.fuel_added = minf(item.amount, generator.space())
				quote.price = ceili(float(quote.price) * quote.fuel_added / item.amount)
	return result


## Hands over what was bought; returns what the event's `detail` should say.
func _grant(player: PlayerState, quote: Quote) -> Dictionary:
	var item := quote.item
	match item.kind:
		ShopItem.Kind.DOOR:
			doors_open.append(item.id)
			_emit(&"door_opened", {"door_id": item.id})
		ShopItem.Kind.WEAPON:
			player.weapons.append(item.id)
			return {"weapon": item.id}
		ShopItem.Kind.CRANE:
			return CranePlay.start(self, player, quote.price)
		ShopItem.Kind.TONIC:
			player.tonics.append(item.id)
		ShopItem.Kind.FUEL:
			return {"fuel": generator.add_fuel(quote.fuel_added)}
		ShopItem.Kind.GRENADES:
			_set_grenades(player, player.grenades + quote.grenades_added, &"purchase")
			return {"grenades": quote.grenades_added}
		ShopItem.Kind.AMMO:
			return {"ammo": item.weapon, "rounds": quote.ammo_added}
	return {}


## A priced, checked purchase that has not happened yet.
class Quote:
	extends RefCounted
	var result: BuyResult = BuyResult.OK
	var item: ShopItem
	var price: int = 0
	var fuel_added: float = 0.0
	var grenades_added: int = 0
	var rounds_offered: int = -1
	var ammo_added: int = 0
