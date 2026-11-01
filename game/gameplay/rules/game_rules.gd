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
##   round_started: round, zombie_count
##   round_ended: round
##   zombie_spawn_requested: zombie_id, health, speed, point_roll (spawn point = point_roll % count)
##   zombie_damaged: zombie_id, player_id, zone, damage (what was taken off), health (left)
##   zombie_removed: zombie_id, cause (killed or gone), killer_id (-1 when no player), zone, melee
##   player_added, player_removed, player_downed, player_revived: player_id
##   points_changed: player_id, total, delta, reason
##   purchase_made: player_id, item_id, price, detail
##   purchase_denied: player_id, item_id, result (a BuyResult)
##   door_opened: door_id
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
}

const DEFAULT_TUNING_PATH := "res://gameplay/rules/default_tuning.tres"
const SNAPSHOT_VERSION := 2
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
	"spawn_left": TYPE_INT,
	"spawn_timer": TYPE_FLOAT,
	"round_players": TYPE_INT,
	"next_zombie_id": TYPE_INT,
	"zombies": TYPE_DICTIONARY,
	"players": TYPE_DICTIONARY,
	"doors_open": TYPE_ARRAY,
	"generator": TYPE_DICTIONARY,
	"spawn_rng_state": TYPE_INT,
	"shop_rng_state": TYPE_INT,
}
## A fuel purchase needs at least this much room in the tank.
const MIN_FUEL_SPACE := 1.0
## Offsets so the spawn and shop generators never share a stream.
const SPAWN_STREAM := 0x5A17
const SHOP_STREAM := 0x70C3

var tuning: RulesTuning
var rng_seed: int = 0
var phase: Phase = Phase.IDLE
var round_number: int = 0
var generator: GeneratorState
var players: Dictionary[int, PlayerState] = {}
var doors_open: Array[StringName] = []

var _break_left: float = 0.0
var _spawn_left: int = 0
var _spawn_timer: float = 0.0
var _round_players: int = 1
var _next_zombie_id: int = 1
var _zombies: Dictionary[int, ZombieState] = {}
var _spawn_rng := RandomNumberGenerator.new()
var _shop_rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
## The whole-unit fuel value the last `fuel_changed` event announced.
var _fuel_announced: int = 0


## A fresh night. `p_tuning` defaults to the shipped table.
func _init(p_tuning: RulesTuning = null, p_seed: int = 0) -> void:
	tuning = p_tuning if p_tuning != null else load(DEFAULT_TUNING_PATH)
	rng_seed = p_seed
	_spawn_rng.seed = p_seed ^ SPAWN_STREAM
	_shop_rng.seed = p_seed ^ SHOP_STREAM
	generator = GeneratorState.new(tuning.fuel)
	_fuel_announced = floori(generator.fuel)
	generator.fuel_changed.connect(_on_fuel_changed)
	generator.fuel_low.connect(func() -> void: _emit(&"fuel_low"))
	generator.fuel_empty.connect(func() -> void: _emit(&"fuel_empty"))
	generator.fuel_restored.connect(func() -> void: _emit(&"fuel_restored"))
	generator.circuit_changed.connect(
		func(circuit_id: StringName, on: bool) -> void:
			_emit(&"circuit_changed", {"circuit_id": circuit_id, "on": on})
	)


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


## Zombies still to spawn plus those alive: the round ends at zero.
func zombies_remaining() -> int:
	return _spawn_left + _zombies.size()


# --- Snapshot ---


## Everything, as plain Variant data. The tuning table itself is not included (both sides load the
## same one) but its fingerprint is, and a restore refuses a different table. This dictionary is
## exact only as Variant data: through JSON the integer keys, the 64-bit random states and some
## floats change. For a save file or the wire use `to_bytes()` or `to_wire()`.
func to_dict() -> Dictionary:
	var player_data := {}
	for player_id in players:
		player_data[player_id] = players[player_id].to_dict()
	var zombie_data := {}
	for zombie_id in _zombies:
		zombie_data[zombie_id] = _zombies[zombie_id].to_dict()
	return {
		"version": SNAPSHOT_VERSION,
		"tuning_id": tuning.fingerprint(),
		"seed": rng_seed,
		"phase": phase,
		"round": round_number,
		"break_left": _break_left,
		"spawn_left": _spawn_left,
		"spawn_timer": _spawn_timer,
		"round_players": _round_players,
		"next_zombie_id": _next_zombie_id,
		"zombies": zombie_data,
		"players": player_data,
		"doors_open": doors_open.duplicate(),
		"generator": generator.to_dict(),
		"spawn_rng_state": _spawn_rng.state,
		"shop_rng_state": _shop_rng.state,
	}


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
## a snapshot of another version, of another tuning table, or one that is not a snapshot.
func from_dict(data: Dictionary) -> StringName:
	for key: String in SNAPSHOT_KEYS:
		if not data.has(key) or not _fits(data[key], SNAPSHOT_KEYS[key]):
			return RESTORE_MALFORMED
	if data["version"] != SNAPSHOT_VERSION:
		return RESTORE_BAD_VERSION
	if data["tuning_id"] != tuning.fingerprint():
		return RESTORE_WRONG_TUNING
	rng_seed = data["seed"]
	phase = data["phase"]
	round_number = data["round"]
	_break_left = data["break_left"]
	_spawn_left = data["spawn_left"]
	_spawn_timer = data["spawn_timer"]
	_round_players = data["round_players"]
	_next_zombie_id = data["next_zombie_id"]
	_zombies.clear()
	for zombie_id in data["zombies"]:
		_zombies[zombie_id] = ZombieState.from_dict(data["zombies"][zombie_id])
	players.clear()
	for player_id in data["players"]:
		players[player_id] = PlayerState.from_dict(data["players"][player_id])
	doors_open.assign(data["doors_open"])
	generator.restore(data["generator"])
	_fuel_announced = floori(generator.fuel)
	_spawn_rng.seed = rng_seed ^ SPAWN_STREAM
	_spawn_rng.state = data["spawn_rng_state"]
	_shop_rng.seed = rng_seed ^ SHOP_STREAM
	_shop_rng.state = data["shop_rng_state"]
	return &""


func _fits(value: Variant, expected: int) -> bool:
	return typeof(value) == expected or (expected == TYPE_FLOAT and typeof(value) == TYPE_INT)


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
				_emit(&"player_removed", {"player_id": action["player_id"]})
				_check_game_over()
		RulesAction.SET_DOWNED:
			_set_downed(action["player_id"], action["downed"])
		RulesAction.HIT:
			_hit(action)
		RulesAction.ZOMBIE_GONE:
			if _zombies.has(action["zombie_id"]):
				_remove_zombie(action["zombie_id"], &"gone", -1)
			else:
				_reject(&"unknown_zombie", RulesAction.ZOMBIE_GONE)
		RulesAction.REPAIR:
			_repair(action["player_id"])
		RulesAction.BUY:
			_buy(action["player_id"], action["item_id"])
		RulesAction.SET_CIRCUIT:
			if not generator.set_circuit(action["circuit_id"], action["on"]):
				_reject(&"unknown_circuit", RulesAction.SET_CIRCUIT)
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


# --- Rounds ---


func _tick(delta: float) -> void:
	match phase:
		Phase.BREAK:
			generator.tick(delta, round_number, true)
			_break_left -= delta
			if _break_left <= 0.0:
				_begin_round()
		Phase.ACTIVE:
			generator.tick(delta, round_number, false)
			_tick_spawning(delta)


func _enter_break(seconds: float) -> void:
	_break_left = seconds
	_set_phase(Phase.BREAK)
	_emit(&"break_started", {"next_round": round_number + 1, "seconds": seconds})


func _begin_round() -> void:
	round_number += 1
	_round_players = maxi(players.size(), 1)
	_spawn_left = tuning.rounds.zombies_for_round(round_number, _round_players)
	_spawn_timer = tuning.rounds.first_spawn_delay
	for player: PlayerState in players.values():
		player.repair_points_this_round = 0
	_set_phase(Phase.ACTIVE)
	_emit(&"round_started", {"round": round_number, "zombie_count": _spawn_left})


func _tick_spawning(delta: float) -> void:
	_spawn_timer -= delta
	var cap := tuning.rounds.alive_cap(round_number, _round_players)
	while _spawn_timer <= 0.0 and _spawn_left > 0 and _zombies.size() < cap:
		_spawn_one()
		_spawn_timer += tuning.rounds.spawn_interval(round_number, _round_players)
	# A full lot or an empty queue holds the next spawn ready instead of banking a burst.
	_spawn_timer = maxf(_spawn_timer, 0.0)


func _spawn_one() -> void:
	var zombie_id := _next_zombie_id
	_next_zombie_id += 1
	_spawn_left -= 1
	var health := tuning.rounds.health_for_round(round_number)
	_zombies[zombie_id] = ZombieState.new(zombie_id, health)
	var speed := tuning.rounds.roll_speed(round_number, _spawn_rng)
	var point_roll := _spawn_rng.randi()
	_emit(
		&"zombie_spawn_requested",
		{
			"zombie_id": zombie_id,
			"health": health,
			"speed": speed,
			"point_roll": point_roll,
		}
	)


func _remove_zombie(
	zombie_id: int, cause: StringName, killer_id: int, zone: StringName = &"", melee: bool = false
) -> void:
	_zombies.erase(zombie_id)
	_emit(
		&"zombie_removed",
		{
			"zombie_id": zombie_id,
			"cause": cause,
			"killer_id": killer_id,
			"zone": zone,
			"melee": melee,
		}
	)
	if phase == Phase.ACTIVE and _spawn_left == 0 and _zombies.is_empty():
		_end_round()


func _end_round() -> void:
	var economy := tuning.economy
	for player: PlayerState in players.values():
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
			player.downed = false
			_emit(&"player_revived", {"player_id": player.id})
		else:
			_award(player.id, economy.round_bonus(round_number), &"round_bonus")
	_emit(&"round_ended", {"round": round_number})
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
	players[player_id] = PlayerState.new(player_id, tuning.economy.start_points)
	_emit(&"player_added", {"player_id": player_id})
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
	player.downed = downed
	if downed:
		_emit(&"player_downed", {"player_id": player_id})
		_check_game_over()
	else:
		_emit(&"player_revived", {"player_id": player_id})


func _can_earn(player_id: int) -> bool:
	var player := players.get(player_id) as PlayerState
	return phase == Phase.ACTIVE and player != null and not player.downed


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
	var headshot := zone == RulesAction.ZONE_HEAD
	var dealt := minf(float(action["damage"]), zombie.health)
	zombie.health -= dealt
	_emit(
		&"zombie_damaged",
		{
			"zombie_id": zombie_id,
			"player_id": player_id,
			"zone": zone,
			"damage": dealt,
			"health": zombie.health,
		}
	)
	if zombie.health > 0.0:
		if zombie.paid_hits < tuning.economy.max_paid_hits:
			zombie.paid_hits += 1
			var pay := tuning.economy.headshot_hit if headshot else tuning.economy.hit
			_award(player_id, pay, &"headshot_hit" if headshot else &"hit")
		return
	player.kills += 1
	if melee:
		_award(player_id, tuning.economy.melee_kill, &"melee_kill")
	elif headshot:
		player.headshot_kills += 1
		_award(player_id, tuning.economy.headshot_kill, &"headshot_kill")
	else:
		_award(player_id, tuning.economy.kill, &"kill")
	_remove_zombie(zombie_id, &"killed", player_id, zone, melee)


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


func _repair(player_id: int) -> void:
	if not _can_earn(player_id):
		return
	var player: PlayerState = players[player_id]
	var room := tuning.economy.repair_cap_per_round - player.repair_points_this_round
	var pay := mini(tuning.economy.repair, room)
	if pay > 0:
		player.repair_points_this_round += pay
		_award(player_id, pay, &"repair")


# --- The shop ---


func _buy(player_id: int, item_id: StringName) -> void:
	var quote := _quote(player_id, item_id)
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


func _quote(player_id: int, item_id: StringName) -> Quote:
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
			if _crane_pool(player, item).is_empty():
				result = BuyResult.ALREADY_OWNED
		ShopItem.Kind.TONIC:
			if player.tonics.has(item.id):
				result = BuyResult.ALREADY_OWNED
			elif player.tonics.size() >= tuning.economy.max_tonics:
				result = BuyResult.LIMIT_REACHED
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
			var won := _roll_crane(player, item)
			player.weapons.append(won)
			return {"weapon": won}
		ShopItem.Kind.TONIC:
			player.tonics.append(item.id)
		ShopItem.Kind.FUEL:
			return {"fuel": generator.add_fuel(quote.fuel_added)}
	return {}


## The crane's weapons this player does not own yet.
func _crane_pool(player: PlayerState, item: ShopItem) -> Array[StringName]:
	var pool: Array[StringName] = []
	for weapon_id in item.pool:
		if not player.weapons.has(weapon_id):
			pool.append(weapon_id)
	return pool


func _roll_crane(player: PlayerState, item: ShopItem) -> StringName:
	var pool := _crane_pool(player, item)
	var total := 0.0
	for weapon_id in pool:
		total += _weight(item, weapon_id)
	var pick := _shop_rng.randf() * total
	for weapon_id in pool:
		pick -= _weight(item, weapon_id)
		if pick < 0.0:
			return weapon_id
	return pool[pool.size() - 1]


func _weight(item: ShopItem, weapon_id: StringName) -> float:
	var index := item.pool.find(weapon_id)
	return item.pool_weights[index] if index < item.pool_weights.size() else 1.0


## A priced, checked purchase that has not happened yet.
class Quote:
	extends RefCounted
	var result: BuyResult = BuyResult.OK
	var item: ShopItem
	var price: int = 0
	var fuel_added: float = 0.0
