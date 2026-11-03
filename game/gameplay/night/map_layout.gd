class_name MapLayout
extends RefCounted
## Where a map scene keeps the things a night asks of it: the groups of spawn markers by area, the
## players' start, the areas a bought door opens, the height of a storey and the zombies' saved
## meshes. Two shapes of scene are read:
##
##   - the drive-in lot: spawns under `<Area>/ZombieSpawns` (`Field` is open at the start, the other
##     areas open with the door `DOOR_AREAS` names) and the players' start in `Field/PlayerSpawns`;
##   - a map that declares its own (the second map): `ZombieSpawns` and `PlayerSpawns` under the
##     root, each spawn marker naming its area in `metadata/room`; the root lists the areas open at
##     the start in `metadata/start_areas`, each door the areas it opens in `metadata/opens`, the
##     height of a storey in `metadata/storey`, the file of its saved meshes in
##     `metadata/navmeshes` and its rules overlay in `metadata/tuning`.
##
## It reads the scene once and decides nothing: `NightWorld` asks it.

## The areas whose zombie spawns open with a door of the lot (the field's are always open).
const DOOR_AREAS := {
	&"door_concession": ["Midway"],
	&"door_yard": ["GeneratorYard"],
	&"door_booth": ["ProjectionBooth"],
	&"door_back_lot": ["BackLot"],
	&"door_road": ["Road"],
}
const LOT_START_AREA := "Field"

var _root: Node3D
## True when the scene lists its spawns in flat groups under its root (the second map).
var _flat: bool
var _spawn_groups: Dictionary[String, Array] = {}
var _player_markers: Array[Marker3D] = []


func _init(root: Node3D) -> void:
	_root = root
	_flat = root.has_node("ZombieSpawns")
	if _flat:
		for marker in root.get_node("ZombieSpawns").get_children():
			var area := String(marker.get_meta(&"room"))
			if not _spawn_groups.has(area):
				_spawn_groups[area] = []
			_spawn_groups[area].append(marker)
		_collect_players(root.get_node("PlayerSpawns"))
	else:
		_collect_players(root.get_node("Field/PlayerSpawns"))


## The areas whose spawns are open before any door is bought.
func start_areas() -> Array[String]:
	var found: Array[String] = []
	if _flat:
		for area in _root.get_meta(&"start_areas", []):
			found.append(String(area))
	else:
		found.append(LOT_START_AREA)
	return found


## The areas the dead may come from once the door in `door_node` is open.
func door_areas(door_node: Node, door_id: StringName) -> Array[String]:
	var found: Array[String] = []
	var listed: Array = door_node.get_meta(&"opens", DOOR_AREAS.get(door_id, []))
	for area in listed:
		found.append(String(area))
	return found


## The markers where the dead rise in `area`, in the scene's order.
func spawn_markers(area: String) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	if _flat:
		markers.assign(_spawn_groups.get(area, []))
		return markers
	var group := _root.get_node_or_null(area + "/ZombieSpawns")
	if group != null:
		for marker in group.get_children():
			markers.append(marker as Marker3D)
	return markers


## The spawn markers of the areas open at the start, in the scene's order.
func start_spawns() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for area in start_areas():
		markers.append_array(spawn_markers(area))
	return markers


## Every spawn marker of the map.
func all_spawns() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	if _flat:
		markers.assign(_root.get_node("ZombieSpawns").get_children())
		return markers
	for group in _root.find_children("ZombieSpawns", "Node3D", true, false):
		for marker in group.get_children():
			markers.append(marker as Marker3D)
	return markers


## The markers the players start on, in the scene's order.
func player_markers() -> Array[Marker3D]:
	return _player_markers


## The height of one storey, or 0 for a map of one floor.
func storey() -> float:
	return float(_root.get_meta(&"storey", 0.0))


## The zombies' saved meshes for this map's sets of doors: the lot's when the scene names none.
func navmeshes() -> LotNavmeshes:
	var path := String(_root.get_meta(&"navmeshes", ""))
	if path.is_empty():
		return LotNavmeshes.shared()
	return load(path) as LotNavmeshes


## The map's overlay on the shared rules table (`metadata/tuning`), or null for a map that has none
## (the lot: the shared table is its own).
func map_tuning() -> MapTuning:
	var path := String(_root.get_meta(&"tuning", ""))
	return load(path) as MapTuning if not path.is_empty() else null


func _collect_players(group: Node) -> void:
	for marker in group.get_children():
		_player_markers.append(marker as Marker3D)
