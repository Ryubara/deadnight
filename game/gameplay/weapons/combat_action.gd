class_name CombatAction
extends RefCounted
## Everything a player or the world can ask of `CombatServer`, as plain dictionaries
## `{"type": StringName, ...fields}`: numbers, strings, vectors. The same shape as `RulesAction`, so
## whatever carries one carries the other. Nothing here knows the transport.

const FIRE := &"fire"
const RELOAD := &"reload"
const GIVE_WEAPON := &"give_weapon"
const EQUIP := &"equip"
const TICK := &"tick"
const TARGETS := &"targets"
const REGISTER_TARGET := &"register_target"
const REMOVE_TARGET := &"remove_target"


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


## One fixed step of the combat clock: cooldowns, reloads, projectiles in flight.
static func tick(delta: float) -> Dictionary:
	return {"type": TICK, "delta": delta}


## Where every target is this step: a list of `{"id": int, "pos": Vector3, "yaw": float}`. Also
## the frame the lag compensation remembers.
static func targets(list: Array) -> Dictionary:
	return {"type": TARGETS, "list": list}


static func register_target(target_id: int, health: float) -> Dictionary:
	return {"type": REGISTER_TARGET, "target_id": target_id, "health": health}


static func remove_target(target_id: int) -> Dictionary:
	return {"type": REMOVE_TARGET, "target_id": target_id}


## The combat action a rules event calls for (a zombie to shoot at, or one gone), or `{}`.
static func from_rules_event(event: Dictionary) -> Dictionary:
	match event.get("type"):
		&"zombie_spawn_requested":
			return register_target(event["zombie_id"], event["health"])
		&"zombie_removed":
			return remove_target(event["zombie_id"])
	return {}
