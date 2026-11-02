class_name RulesAction
extends RefCounted
## Everything that can change the night, as plain dictionaries: `{"type": StringName, ...fields}`.
##
## A client sends one of these to the server; the server hands it to `GameRules.apply`. A dictionary
## of numbers, strings and booleans needs no node, no object and no Godot multiplayer to travel.

const START := &"start"
const CONFIGURE := &"configure"
const TICK := &"tick"
const SKIP_BREAK := &"skip_break"
const ADD_PLAYER := &"add_player"
const REMOVE_PLAYER := &"remove_player"
const SET_DOWNED := &"set_downed"
const BLOW := &"blow"
const HIT := &"hit"
const ZOMBIE_GONE := &"zombie_gone"
const REPAIR := &"repair"
const TEAR_BOARD := &"tear_board"
const BUY := &"buy"
const CRANE_TAKE := &"crane_take"
const SET_CIRCUIT := &"set_circuit"
const GRANT_POINTS := &"grant_points"
const USE_GRENADE := &"use_grenade"
const EXPLOSION := &"explosion"

## Where a hit landed. `ZONE_HEAD` and `ZONE_WEAK` change what the rules pay; the weapon has already
## applied its zone multiplier to the damage, and the rules add the type's own `weak_multiplier` for
## `ZONE_WEAK` (the boss's lit bulb). A `ZONE_LIMB` hit can bring a walker to the ground.
const ZONE_HEAD := &"head"
const ZONE_BODY := &"body"
const ZONE_LIMB := &"limb"
const ZONE_WEAK := &"weak"
const ZONES: Array[StringName] = [ZONE_HEAD, ZONE_BODY, ZONE_LIMB, ZONE_WEAK]

## The longest step one tick may take, seconds. A caller with more time to pass sends more ticks.
const MAX_TICK := 1.0
## The most damage one hit may carry (a sanity bound, far above any weapon and any zombie).
const MAX_DAMAGE := 100000.0
## The most one `grant_points` may carry.
const MAX_GRANT := 100000
## The most rounds one ammunition purchase may name.
const MAX_ROUNDS := 1000
## The most zombies one `explosion` may name.
const MAX_VICTIMS := 128
## The zone a blast reports (`zombie_damaged`, `zombie_removed`): a blast is not a head or a limb.
const ZONE_BLAST := &"blast"

## Required fields of every action type, with the type each must have. `TYPE_FLOAT` also takes an
## int and `TYPE_STRING_NAME` also takes a String (JSON has no StringName). Extra fields are
## ignored.
const REQUIRED := {
	START: {},
	CONFIGURE: {"settings": TYPE_DICTIONARY},
	TICK: {"delta": TYPE_FLOAT},
	SKIP_BREAK: {},
	ADD_PLAYER: {"player_id": TYPE_INT},
	REMOVE_PLAYER: {"player_id": TYPE_INT},
	SET_DOWNED: {"player_id": TYPE_INT, "downed": TYPE_BOOL},
	BLOW: {"player_id": TYPE_INT, "damage": TYPE_FLOAT},
	HIT:
	{"player_id": TYPE_INT, "zombie_id": TYPE_INT, "zone": TYPE_STRING_NAME, "damage": TYPE_FLOAT},
	ZOMBIE_GONE: {"zombie_id": TYPE_INT},
	REPAIR: {"player_id": TYPE_INT, "barricade_id": TYPE_STRING_NAME},
	TEAR_BOARD: {"barricade_id": TYPE_STRING_NAME, "zombie_id": TYPE_INT},
	BUY: {"player_id": TYPE_INT, "item_id": TYPE_STRING_NAME},
	CRANE_TAKE: {"player_id": TYPE_INT},
	SET_CIRCUIT: {"circuit_id": TYPE_STRING_NAME, "on": TYPE_BOOL},
	GRANT_POINTS: {"player_id": TYPE_INT, "amount": TYPE_INT},
	USE_GRENADE: {"player_id": TYPE_INT},
	EXPLOSION: {"player_id": TYPE_INT, "victims": TYPE_ARRAY},
}
## Fields that may be left out; when present they must have the type.
const OPTIONAL := {
	HIT: {"melee": TYPE_BOOL},
	BLOW: {"bearing": TYPE_FLOAT, "source_id": TYPE_INT},
	GRANT_POINTS: {"reason": TYPE_STRING_NAME},
	BUY: {"rounds": TYPE_INT, "weapon": TYPE_STRING_NAME},
	CRANE_TAKE: {"held": TYPE_STRING_NAME},
}


static func start() -> Dictionary:
	return {"type": START}


## The match settings (`MatchSettings.to_dict`), before the night starts: refused as `wrong_phase`
## once it has, and with the field to blame as `settings` when a value is out of bounds.
static func configure(settings: MatchSettings) -> Dictionary:
	return {"type": CONFIGURE, "settings": settings.to_dict()}


## One fixed step of the clock. The only way time passes.
static func tick(delta: float) -> Dictionary:
	return {"type": TICK, "delta": delta}


static func skip_break() -> Dictionary:
	return {"type": SKIP_BREAK}


static func add_player(player_id: int) -> Dictionary:
	return {"type": ADD_PLAYER, "player_id": player_id}


static func remove_player(player_id: int) -> Dictionary:
	return {"type": REMOVE_PLAYER, "player_id": player_id}


static func set_downed(player_id: int, downed: bool) -> Dictionary:
	return {"type": SET_DOWNED, "player_id": player_id, "downed": downed}


## One blow on a player (a zombie's swing). `damage` is what it does; `bearing` is where it came
## from, radians clockwise from -z seen from above (0 when unknown), and `source_id` the zombie
## that dealt it (-1 for none). The rules take it off the player's health, restart the wait before
## health mends, and down the player at zero.
static func blow(
	player_id: int, damage: float, bearing: float = 0.0, source_id: int = -1
) -> Dictionary:
	return {
		"type": BLOW,
		"player_id": player_id,
		"damage": damage,
		"bearing": bearing,
		"source_id": source_id,
	}


## One hit on a zombie. `damage` is what the weapon dealt, zone multiplier included; the rules take
## it off the zombie's health, pay for it, and decide whether it killed.
static func hit(
	player_id: int, zombie_id: int, zone: StringName, damage: float, melee: bool = false
) -> Dictionary:
	return {
		"type": HIT,
		"player_id": player_id,
		"zombie_id": zombie_id,
		"zone": zone,
		"damage": damage,
		"melee": melee,
	}


## A zombie died to something that is not a player (a trap, a fall): no points.
static func zombie_gone(zombie_id: int) -> Dictionary:
	return {"type": ZOMBIE_GONE, "zombie_id": zombie_id}


## One board put back across the breach `barricade_id`. The rules refuse it for a breach that is
## unknown or already whole, so a client cannot be paid for boards that were never down.
static func repair(player_id: int, barricade_id: StringName) -> Dictionary:
	return {"type": REPAIR, "player_id": player_id, "barricade_id": barricade_id}


## A zombie has pulled one board off the breach `barricade_id`. Server only: the zombie simulation
## sends it when its work at the boards is done.
static func tear_board(barricade_id: StringName, zombie_id: int) -> Dictionary:
	return {"type": TEAR_BOARD, "barricade_id": barricade_id, "zombie_id": zombie_id}


## A purchase. `rounds` is only for ammunition: how many rounds the weapon's reserve has room for
## (the combat server counts them, the rules price them); left out, the whole purchase. `weapon` is
## the catalogue id of the weapon the server found in the buyer's hand: the one a re-cut is for, or
## the one a bought weapon replaces when the hands are full.
static func buy(
	player_id: int, item_id: StringName, rounds: int = -1, weapon: StringName = &""
) -> Dictionary:
	var action := {"type": BUY, "player_id": player_id, "item_id": item_id}
	if rounds >= 0:
		action["rounds"] = rounds
	if weapon != &"":
		action["weapon"] = weapon
	return action


## The buyer takes the weapon the crane is holding out. Anyone else, or nobody's, is answered with
## `crane_take_denied`.
## `held` is the catalogue id of the weapon in the taker's hand (the server finds it): the one a
## full carry gives up for the prize. Left out, the oldest carried goes.
static func crane_take(player_id: int, held: StringName = &"") -> Dictionary:
	var action := {"type": CRANE_TAKE, "player_id": player_id}
	if held != &"":
		action["held"] = held
	return action


static func set_circuit(circuit_id: StringName, on: bool) -> Dictionary:
	return {"type": SET_CIRCUIT, "circuit_id": circuit_id, "on": on}


## Points from outside the rules (a pickup, a scripted reward).
static func grant_points(player_id: int, amount: int, reason: StringName = &"grant") -> Dictionary:
	return {"type": GRANT_POINTS, "player_id": player_id, "amount": amount, "reason": reason}


## A grenade leaves the player's hand (or goes off in it): one fewer. The rules refuse it when the
## player has none, so a client cannot throw what it does not carry.
static func use_grenade(player_id: int) -> Dictionary:
	return {"type": USE_GRENADE, "player_id": player_id}


## One blast, already turned into what it did to each zombie: `victims` is a list of
## `{"zombie_id": int, "damage": float, "leg_damage": float}` (total blast damage, and the part of
## it that landed on the legs), in a fixed order (the server sorts by id). The rules take the
## damage off each, pay, kill, and decide who loses their legs.
static func explosion(player_id: int, victims: Array) -> Dictionary:
	return {"type": EXPLOSION, "player_id": player_id, "victims": victims}


## Checks an action against `REQUIRED` and `OPTIONAL` and the value bounds. Returns `{}` when it is
## well formed, else `{"reason": StringName, "field": StringName}` with the reason one of
## `unknown_action`, `missing_field`, `wrong_type`, `out_of_range`. Whether the ids it names exist
## is for `GameRules`. The server and the tests share this one definition.
static func validate(action: Dictionary) -> Dictionary:
	var type: Variant = action.get("type")
	if (
		(typeof(type) != TYPE_STRING_NAME and typeof(type) != TYPE_STRING)
		or not REQUIRED.has(StringName(type))
	):
		return {"reason": &"unknown_action", "field": &"type"}
	var key := StringName(type)
	for field: String in REQUIRED[key]:
		if not action.has(field):
			return {"reason": &"missing_field", "field": StringName(field)}
		if not _has_type(action[field], REQUIRED[key][field]):
			return {"reason": &"wrong_type", "field": StringName(field)}
	for field: String in OPTIONAL.get(key, {}):
		if action.has(field) and not _has_type(action[field], OPTIONAL[key][field]):
			return {"reason": &"wrong_type", "field": StringName(field)}
	var bad_field := _out_of_range_field(key, action)
	if bad_field != &"":
		return {"reason": &"out_of_range", "field": bad_field}
	return {}


static func _has_type(value: Variant, expected: int) -> bool:
	var actual := typeof(value)
	match expected:
		TYPE_FLOAT:
			return actual == TYPE_FLOAT or actual == TYPE_INT
		TYPE_STRING_NAME:
			return actual == TYPE_STRING_NAME or actual == TYPE_STRING
	return actual == expected


## The first field whose value is outside its bounds, or an empty name.
static func _out_of_range_field(type: StringName, action: Dictionary) -> StringName:
	match type:
		TICK:
			if not _within(action["delta"], 0.0, MAX_TICK):
				return &"delta"
		HIT:
			if not _within(action["damage"], 0.0, MAX_DAMAGE) or action["damage"] <= 0.0:
				return &"damage"
			if not ZONES.has(StringName(action["zone"])):
				return &"zone"
		BLOW:
			if not _within(action["damage"], 0.0, MAX_DAMAGE) or action["damage"] <= 0.0:
				return &"damage"
			if action.has("bearing") and not is_finite(action["bearing"]):
				return &"bearing"
		GRANT_POINTS:
			if action["amount"] <= 0 or action["amount"] > MAX_GRANT:
				return &"amount"
		BUY:
			if action.has("rounds") and (action["rounds"] < 0 or action["rounds"] > MAX_ROUNDS):
				return &"rounds"
		EXPLOSION:
			return _bad_victims(action["victims"])
		CONFIGURE:
			return &"settings" if not MatchSettings.problem(action["settings"]).is_empty() else &""
	return &""


static func _bad_victims(victims: Array) -> StringName:
	if victims.size() > MAX_VICTIMS:
		return &"victims"
	for victim: Variant in victims:
		if typeof(victim) != TYPE_DICTIONARY:
			return &"victims"
		var entry: Dictionary = victim
		for field: String in ["zombie_id", "damage", "leg_damage"]:
			if not entry.has(field):
				return &"victims"
		if not _has_type(entry["zombie_id"], TYPE_INT):
			return &"victims"
		if (
			not _has_type(entry["damage"], TYPE_FLOAT)
			or not _has_type(entry["leg_damage"], TYPE_FLOAT)
		):
			return &"victims"
		var damage := float(entry["damage"])
		var legs := float(entry["leg_damage"])
		if not _within(damage, 0.0, MAX_DAMAGE) or damage <= 0.0:
			return &"victims"
		if not _within(legs, 0.0, damage):
			return &"victims"
	return &""


## Finite and between the bounds (NaN and infinity are not).
static func _within(value: float, low: float, high: float) -> bool:
	return is_finite(value) and value >= low and value <= high
