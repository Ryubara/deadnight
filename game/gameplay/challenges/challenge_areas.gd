class_name ChallengeAreas
extends RefCounted
## What the challenges know of a map that is a data line (`data/areas.json`): the rectangles of the
## places a challenge asks about, `[x0, z0, x1, z1]` in metres on the ground (the booth, the stand),
## and the id of the map's second door. A map with no line has none of them, and a challenge that
## needs one is not counted there (the back rooms have no booth, no stand and no second door).

const PATH := "res://gameplay/challenges/data/areas.json"
const BOOTH := &"booth"
const STAND := &"stand"
const SECOND_DOOR := "second_door"

static var _data: Dictionary = {}


## The rectangle of `area` on `map_id` (four numbers), or an empty array for none.
static func rect(map_id: String, area: StringName) -> PackedFloat32Array:
	var value: Variant = _map(map_id).get(String(area), [])
	if value is Array and (value as Array).size() == 4:
		return PackedFloat32Array(value)
	return PackedFloat32Array()


## The id of the shop door that is the map's second (`&""` for a map with none).
static func second_door(map_id: String) -> StringName:
	return StringName(str(_map(map_id).get(SECOND_DOOR, "")))


## Whether the ground point (`x`, `z`) is inside a rectangle from `rect`.
static func contains(area: PackedFloat32Array, at: Vector3) -> bool:
	return (
		area.size() == 4
		and at.x >= area[0]
		and at.z >= area[1]
		and at.x <= area[2]
		and at.z <= area[3]
	)


static func _map(map_id: String) -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_data = parsed if parsed is Dictionary else {"": {}}
	return _data.get(map_id, {})
