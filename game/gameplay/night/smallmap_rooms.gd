class_name SmallMapRooms
extends RefCounted
## The second map's rooms as the sound sees them, read from the greybox: each room is a node with
## `room` (a kind: `start`, `side`, `upstairs`), `rect` (x, z, width, depth inside the walls) and
## `floor` (the height of its floor) metadata. A point is in a room when it is inside the rectangle
## and at least `EYE_OVER_FLOOR` over the floor, and in the highest such room (the stairs rise
## through the lower rooms' rectangles to the floor of the one over them). Anywhere else is outside.

## A listener this far over a floor stands on it (the camera's lowest, crouching).
const EYE_OVER_FLOOR := 0.8

var _rooms: Array[Dictionary] = []


func _init(greybox: Node3D) -> void:
	for child in greybox.get_children():
		if child.has_meta(&"rect") and child.has_meta(&"floor"):
			(
				_rooms
				. append(
					{
						"name": child.name,
						"kind": StringName(child.get_meta(&"room", "")),
						"rect": child.get_meta(&"rect") as Rect2,
						"floor": float(child.get_meta(&"floor")),
					}
				)
			)


## The node name of the room `point` is in (`Start`, `Side`, `UpperA`, `UpperB`), or `&""` outside.
func room_at(point: Vector3) -> StringName:
	var found := &""
	var highest := -INF
	for room in _rooms:
		var floor_y: float = room["floor"]
		var rect: Rect2 = room["rect"]
		if (
			rect.has_point(Vector2(point.x, point.z))
			and point.y >= floor_y + EYE_OVER_FLOOR
			and floor_y > highest
		):
			highest = floor_y
			found = room["name"]
	return found


## The kind of a room by its node name (`start`, `side`, `upstairs`), `&""` for none.
func kind_of(room_name: StringName) -> StringName:
	for room in _rooms:
		if room["name"] == room_name:
			return room["kind"]
	return &""


## The height of a room's floor, 0 for none.
func floor_of(room_name: StringName) -> float:
	for room in _rooms:
		if room["name"] == room_name:
			return room["floor"]
	return 0.0


func names() -> Array[StringName]:
	var found: Array[StringName] = []
	for room in _rooms:
		found.append(room["name"])
	return found
