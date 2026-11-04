class_name PingAim
extends RefCounted
## What a person's ping key marks: the thing the crosshair is on, else the place it lands. `pick` is
## a pure function of the camera ray and what the client knows, so a test needs no window. The
## result is the `ping` action the server validates (`NightServer.ping`), and it re-checks every
## claim.

## Metres from the camera ray that a zombie or a downed teammate counts as under the crosshair.
const RAY_RADIUS := 1.2
## Metres from the point the ray lands that a door or an ammunition spot counts as the target.
const SNAP := 4.0
## The ray's reach when it lands on nothing.
const REACH := 40.0


## What the ping key marks for `aim`: the ray cast through `space`, and what the client knows of the
## night (`world`, `state`), put to `pick`.
static func request(
	aim: NightCommand, world: NightWorld, state: ClientState, space: PhysicsDirectSpaceState3D
) -> Dictionary:
	var landed := Vector3.INF
	var cast := PhysicsRayQueryParameters3D.create(
		aim.origin, aim.origin + aim.dir * REACH, CameraProbe.PLAYER_MASK | PhysicsLayers.BODY
	)
	var hit := space.intersect_ray(cast)
	if not hit.is_empty():
		landed = hit["position"]
	var shut := {}
	var index := 0
	for door_id in world.door_ids():
		if not state.frame.get("doors", []).has(door_id):
			shut[index] = world.door_points(door_id)
		index += 1
	var ammo: Array[Vector3] = []
	for spot in world.shop_spots():
		if spot["kind"] == &"ammo":
			ammo.append(spot["position"])
	var players: Dictionary = state.frame.get("players", {})
	return pick(aim.origin, aim.dir, state.zombies, players, state.player_id, shut, ammo, landed)


## `door_points` is {door index: [points]} of the doors still shut; `ammo_spots` the spots that sell
## rounds; `players` is the frame's {id: {pos, downed}}; `landed` the point the ray hit, or
## `Vector3.INF` for none.
static func pick(
	origin: Vector3,
	dir: Vector3,
	zombies: Array[Dictionary],
	players: Dictionary,
	my_id: int,
	door_points: Dictionary,
	ammo_spots: Array[Vector3],
	landed: Vector3
) -> Dictionary:
	var ray := dir.normalized()
	var best := _nearest_on_ray(origin, ray, _zombie_points(zombies))
	if best != 0:
		return _action(PingBoard.ENEMY, _position_of(zombies, best), best)
	var downed: Dictionary = {}
	for id: int in players:
		if id != my_id and players[id].get("downed", false):
			downed[id] = players[id]["pos"]
	best = _nearest_on_ray(origin, ray, downed)
	if best != 0:
		return _action(PingBoard.DOWNED, downed[best], best)
	var point := landed if landed.is_finite() else origin + ray * REACH
	for index: int in door_points:
		for door_point: Vector3 in door_points[index]:
			if _flat(door_point, point) <= SNAP:
				return _action(PingBoard.DOOR, door_point, index)
	for spot in ammo_spots:
		if _flat(spot, point) <= SNAP:
			return _action(PingBoard.AMMO, spot, 0)
	return _action(PingBoard.HERE, point, 0)


static func _action(kind: StringName, at: Vector3, subject: int) -> Dictionary:
	return {"type": NightServer.PING, "kind": kind, "pos": at, "subject": subject}


## The id of the point nearest the ray within `RAY_RADIUS` and in front of the camera, or 0.
static func _nearest_on_ray(origin: Vector3, ray: Vector3, points: Dictionary) -> int:
	var best := 0
	var best_along := INF
	for id: int in points:
		var to: Vector3 = points[id] + Vector3(0.0, 1.0, 0.0) - origin
		var along := to.dot(ray)
		if along <= 0.0 or along > REACH * 1.75:
			continue
		if to.distance_to(ray * along) > RAY_RADIUS:
			continue
		if along < best_along:
			best_along = along
			best = id
	return best


static func _zombie_points(zombies: Array[Dictionary]) -> Dictionary:
	var out := {}
	for zombie in zombies:
		if zombie["mode"] != ZombieBody.Mode.DYING and zombie["mode"] != ZombieBody.Mode.EMERGING:
			out[zombie["id"]] = zombie["position"]
	return out


static func _position_of(zombies: Array[Dictionary], id: int) -> Vector3:
	for zombie in zombies:
		if zombie["id"] == id:
			return zombie["position"]
	return Vector3.ZERO


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
