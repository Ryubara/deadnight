class_name HumanWalker
extends RefCounted
## A person standing in for a human player in a bot test: it walks a path over the navigation mesh
## to a point, the way a person with a stick would, and sends the same `NightCommand` through the
## server's `apply`. Nothing else: no aiming, no shopping. The tests drive it by hand, one `tick` a
## step, so no clock is involved.

const STEP := Night.STEP
## Metres from a point at which the walker counts as there.
const ARRIVED := 0.8
## Metres ahead on the path the walker steers toward.
const LOOK_AHEAD := 1.0

var player_id: int
var server: NightServer
var map: RID
var goal := Vector3.INF
var yaw := 0.0
var sprint := false
## Seconds the walker has not moved while it has somewhere to go.
var stalled := 0.0

var _last := Vector3.INF


func _init(p_server: NightServer, p_map: RID, id: int) -> void:
	server = p_server
	map = p_map
	player_id = id


func position() -> Vector3:
	return server.body_of(player_id).global_position


func arrived() -> bool:
	return goal == Vector3.INF or _flat(position(), goal) <= ARRIVED


func goto(point: Vector3) -> void:
	goal = point


func stop() -> void:
	goal = Vector3.INF


## One step's command: along the path to the goal, or standing.
func tick() -> void:
	var command := NightCommand.new()
	command.player_id = player_id
	var here := position()
	command.origin = here + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	command.motion.yaw = yaw
	command.dir = Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3.FORWARD
	if goal != Vector3.INF and not arrived():
		var wish := _toward(here)
		if wish != Vector3.ZERO:
			yaw = atan2(-wish.x, -wish.z)
			command.motion.yaw = yaw
			command.dir = Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3.FORWARD
			command.motion.move = Vector2(0.0, -1.0)
			command.motion.sprint = sprint
	if _last != Vector3.INF and goal != Vector3.INF and not arrived():
		stalled = stalled + STEP if _flat(here, _last) < 0.005 else 0.0
	else:
		stalled = 0.0
	_last = here
	server.apply(bytes_to_var(var_to_bytes(command.to_dict())), player_id)


func _toward(here: Vector3) -> Vector3:
	var next := goal
	for point in NavigationServer3D.map_get_path(map, here, goal, true):
		if _flat(here, point) > LOOK_AHEAD:
			next = point
			break
	var flat := next - here
	flat.y = 0.0
	return flat.normalized()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
