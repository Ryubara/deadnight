class_name PingJudge
extends RefCounted
## Decides whether a player's ping is true before it goes up (`PingBoard` keeps the marks): the
## place is within reach, the door is shut, the ammunition spot is there, the zombie is alive, the
## teammate is down. A mark snaps to the thing it names, so a client cannot mark what is not there.
## The answer is `&""` when the mark went up, else the reason.

## Set by the server, and again when a test swaps its tuning.
var tuning: NightTuning

var _board: PingBoard
var _rules: GameRules
var _world: NightWorld
var _sim: ZombieSim
## Player id to body, the server's own dictionary.
var _bodies: Dictionary
var _announce: Callable


func _init(
	p_tuning: NightTuning,
	p_board: PingBoard,
	p_rules: GameRules,
	p_world: NightWorld,
	p_sim: ZombieSim,
	p_bodies: Dictionary,
	p_announce: Callable
) -> void:
	tuning = p_tuning
	_board = p_board
	_rules = p_rules
	_world = p_world
	_sim = p_sim
	_bodies = p_bodies
	_announce = p_announce


## `action` is `{kind, pos, subject}`; anyone may place one every `ping_gap` seconds.
func place(player_id: int, action: Dictionary) -> StringName:
	var body := _bodies.get(player_id) as Player
	if body == null:
		return &"unknown_player"
	if not _board.ready_for(player_id):
		return &"too_soon"
	var at: Variant = action.get("pos", Vector3.ZERO)
	if typeof(at) != TYPE_VECTOR3 or not (at as Vector3).is_finite():
		return &"bad_position"
	var here := body.global_position
	var kind := StringName(action.get("kind", &""))
	var found := _target(player_id, kind, action, at, here)
	if found.has("error"):
		return found["error"]
	if _flat(here, found["point"]) > tuning.ping_range:
		return &"too_far"
	_announce.call(_board.place(player_id, kind, found["point"], found["subject"]))
	return &""


## What a ping of `kind` marks: `{point, subject}`, or `{error}` when the claim is false.
func _target(
	player_id: int, kind: StringName, action: Dictionary, at: Vector3, here: Vector3
) -> Dictionary:
	match kind:
		PingBoard.HERE:
			return {"point": at, "subject": 0}
		PingBoard.DOOR:
			return _door(action, here)
		PingBoard.AMMO:
			var spot := _ammo_spot_near(at)
			return (
				{"point": spot, "subject": 0} if spot != Vector3.INF else {"error": &"no_such_spot"}
			)
		PingBoard.ENEMY:
			return _enemy(action)
		PingBoard.DOWNED:
			return _downed(player_id, action)
	return {"error": &"unknown_kind"}


func _door(action: Dictionary, here: Vector3) -> Dictionary:
	var ids := _world.door_ids()
	var index := int(action.get("subject", -1))
	if index < 0 or index >= ids.size() or _rules.is_door_open(ids[index]):
		return {"error": &"no_such_door"}
	return {"point": _nearest_to(_world.door_points(ids[index]), here), "subject": ids[index]}


func _enemy(action: Dictionary) -> Dictionary:
	var zombie: ZombieBody = _sim.zombies.get(int(action.get("subject", -1)))
	if zombie == null or not zombie.is_alive():
		return {"error": &"no_such_zombie"}
	return {"point": zombie.position, "subject": zombie.id}


func _downed(player_id: int, action: Dictionary) -> Dictionary:
	var other := int(action.get("subject", -1))
	var state: PlayerState = _rules.players.get(other)
	if other == player_id or not _bodies.has(other) or state == null or not state.downed:
		return {"error": &"not_downed"}
	return {"point": _bodies[other].global_position, "subject": other}


func _nearest_to(points: Array, here: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_apart := INF
	for point: Vector3 in points:
		var apart := _flat(here, point)
		if apart < best_apart:
			best = point
			best_apart = apart
	return best


## The ammunition spot within `ping_snap` of a point (its own position), or `Vector3.INF`.
func _ammo_spot_near(point: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_apart := tuning.ping_snap
	for spot in _world.shop_spots():
		if spot["kind"] != &"ammo":
			continue
		var apart := _flat(point, spot["position"])
		if apart <= best_apart:
			best = spot["position"]
			best_apart = apart
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
