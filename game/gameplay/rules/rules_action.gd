class_name RulesAction
extends RefCounted
## Everything that can change the night, as plain dictionaries: `{"type": StringName, ...fields}`.
##
## A client sends one of these to the server; the server hands it to `GameRules.apply`. A dictionary
## of numbers, strings and booleans needs no node, no object and no Godot multiplayer to travel.

const START := &"start"
const TICK := &"tick"
const SKIP_BREAK := &"skip_break"
const ADD_PLAYER := &"add_player"
const REMOVE_PLAYER := &"remove_player"
const SET_DOWNED := &"set_downed"
const HIT := &"hit"
const KILL := &"kill"
const ZOMBIE_GONE := &"zombie_gone"
const REPAIR := &"repair"
const BUY := &"buy"
const SET_CIRCUIT := &"set_circuit"
const GRANT_POINTS := &"grant_points"


static func start() -> Dictionary:
	return {"type": START}


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


## A hit that did not kill.
static func hit(player_id: int, zombie_id: int, headshot: bool) -> Dictionary:
	return {"type": HIT, "player_id": player_id, "zombie_id": zombie_id, "headshot": headshot}


## The killing blow.
static func kill(player_id: int, zombie_id: int, headshot: bool, melee: bool) -> Dictionary:
	return {
		"type": KILL,
		"player_id": player_id,
		"zombie_id": zombie_id,
		"headshot": headshot,
		"melee": melee,
	}


## A zombie died to something that is not a player (a trap, a fall): no points.
static func zombie_gone(zombie_id: int) -> Dictionary:
	return {"type": ZOMBIE_GONE, "zombie_id": zombie_id}


## One barricade board put back.
static func repair(player_id: int) -> Dictionary:
	return {"type": REPAIR, "player_id": player_id}


static func buy(player_id: int, item_id: StringName) -> Dictionary:
	return {"type": BUY, "player_id": player_id, "item_id": item_id}


static func set_circuit(circuit_id: StringName, on: bool) -> Dictionary:
	return {"type": SET_CIRCUIT, "circuit_id": circuit_id, "on": on}


## Points from outside the rules (a pickup, a scripted reward).
static func grant_points(player_id: int, amount: int, reason: StringName = &"grant") -> Dictionary:
	return {"type": GRANT_POINTS, "player_id": player_id, "amount": amount, "reason": reason}
