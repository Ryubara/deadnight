class_name GrenadeAction
extends RefCounted
## Everything a player or the world can ask of `GrenadeServer`, as plain dictionaries
## `{"type": StringName, ...fields}`: numbers, strings, vectors. The same shape as `CombatAction`
## and `RulesAction`, so whatever carries those carries these. `TICK` and `TARGETS` are spelled
## like the combat server's, so one host can send the same step and the same target list to both.

const COOK := &"cook"
const THROW := &"throw"
const TICK := &"tick"
const TARGETS := &"targets"
const PLAYERS := &"players"


## The pin is pulled: the fuse starts and one grenade leaves the player's count. Sent again while
## the grenade is still held, it only moves `hand` (so a grenade that goes off in the hand goes
## off where the hand is).
static func cook(player_id: int, seq: int, hand: Vector3) -> Dictionary:
	return {"type": COOK, "player_id": player_id, "seq": seq, "hand": hand}


## The release. `aim` is where the camera looks, `hand` where the grenade leaves from, `velocity`
## the thrower's own, `underarm` the short toss.
static func throw_grenade(
	player_id: int, seq: int, hand: Vector3, aim: Vector3, velocity: Vector3, underarm: bool
) -> Dictionary:
	return {
		"type": THROW,
		"player_id": player_id,
		"seq": seq,
		"hand": hand,
		"aim": aim,
		"velocity": velocity,
		"underarm": underarm,
	}


## One fixed step of the grenade clock: the fuse, the flight.
static func tick(delta: float) -> Dictionary:
	return {"type": TICK, "delta": delta}


## Where every zombie is this step: `[{"id": int, "pos": Vector3, "yaw": float}]`. `revision` (0 or
## more): the same number as the last action means the same list, and the server keeps its table
## (`CombatAction.targets`). -1 (the default) always reads the list.
static func targets(list: Array, revision: int = -1) -> Dictionary:
	return {"type": TARGETS, "list": list, "revision": revision}


## Where every player is this step: `[{"id": int, "pos": Vector3}]` (feet).
static func players(list: Array) -> Dictionary:
	return {"type": PLAYERS, "list": list}
