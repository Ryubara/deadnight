class_name CombatAction
extends RefCounted
## Everything a player or the world can ask of `CombatServer`, as plain dictionaries
## `{"type": StringName, ...fields}`: numbers, strings, vectors. The same shape as `RulesAction`, so
## whatever carries one carries the other. Nothing here knows the transport.

const FIRE := &"fire"
const RELOAD := &"reload"
const GIVE_WEAPON := &"give_weapon"
const EQUIP := &"equip"
const SWAP := &"swap"
const ADD_AMMO := &"add_ammo"
const TICK := &"tick"
const TARGETS := &"targets"
const TRACK_TARGET := &"track_target"
const UNTRACK_TARGET := &"untrack_target"


## The trigger. `origin` and `dir` are the camera ray, `muzzle` where the barrel is, `view_time`
## the server time of the world the shooter was looking at (the lag compensation rewinds to it).
## It also swings a melee weapon: `dir` is then the facing and `origin` the chest.
static func fire(
	shooter_id: int, seq: int, origin: Vector3, dir: Vector3, muzzle: Vector3, view_time: float
) -> Dictionary:
	return {
		"type": FIRE,
		"shooter_id": shooter_id,
		"seq": seq,
		"origin": origin,
		"dir": dir,
		"muzzle": muzzle,
		"view_time": view_time,
	}


static func reload_weapon(shooter_id: int) -> Dictionary:
	return {"type": RELOAD, "shooter_id": shooter_id}


## Adds a weapon to the player (or tops up its reserve if carried) and takes it in hand.
static func give_weapon(player_id: int, weapon_id: StringName) -> Dictionary:
	return {"type": GIVE_WEAPON, "player_id": player_id, "weapon_id": weapon_id}


static func equip(player_id: int, weapon_id: StringName) -> Dictionary:
	return {"type": EQUIP, "player_id": player_id, "weapon_id": weapon_id}


## Puts away the weapon in hand and takes the next one the player carries (in the order they were
## given; the last goes round to the first).
static func swap(player_id: int) -> Dictionary:
	return {"type": SWAP, "player_id": player_id}


## Puts up to `rounds` into the reserve of a weapon the player carries (never past its limit).
static func add_ammo(player_id: int, weapon_id: StringName, rounds: int) -> Dictionary:
	return {"type": ADD_AMMO, "player_id": player_id, "weapon_id": weapon_id, "rounds": rounds}


## One fixed step of the combat clock: cooldowns, reloads, projectiles in flight.
static func tick(delta: float) -> Dictionary:
	return {"type": TICK, "delta": delta}


## Where every target is this step: a list of `{"id": int, "pos": Vector3, "yaw": float}` and,
## for a target whose hit zones are not the walker's size, `"scale"`, and for one with a weak spot,
## `"weak": true`. Also the
## frame the lag compensation remembers.
static func targets(list: Array) -> Dictionary:
	return {"type": TARGETS, "list": list}


## A zombie that may be shot. The rules own its health; the server only needs to know it is alive.
static func track_target(target_id: int) -> Dictionary:
	return {"type": TRACK_TARGET, "target_id": target_id}


static func untrack_target(target_id: int) -> Dictionary:
	return {"type": UNTRACK_TARGET, "target_id": target_id}


## The combat action a rules event calls for (a zombie to shoot at, or one gone), or `{}`.
static func from_rules_event(event: Dictionary) -> Dictionary:
	match event.get("type"):
		&"zombie_spawn_requested":
			return track_target(event["zombie_id"])
		&"zombie_removed":
			return untrack_target(event["zombie_id"])
	return {}
