class_name NightWorld
extends Node3D
## The place a night happens in: the drive-in greybox, its navigation mesh, its doors and spawn
## markers, and the players' bodies. The server asks it where things are and tells it what the
## rules decided (a door bought); it decides nothing itself.

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
## Static bodies of CSG shapes reach the physics space after a few steps.
const SETTLE_FRAMES := 4
## A new navigation region is usable after the map's second iteration.
const NAV_ITERATIONS := 2
## Metres within which a lamp lights the ground.
const LAMP_REACH := 6.0
## The areas whose zombie spawns open with a door (the field's are always open).
const DOOR_AREAS := {
	&"door_concession": ["Midway"],
	&"door_yard": ["GeneratorYard"],
	&"door_booth": ["ProjectionBooth"],
	&"door_back_lot": ["BackLot"],
	&"door_road": ["Road"],
}

var greybox: Node3D
var region: NavigationRegion3D

var _doors: Dictionary[StringName, Node3D] = {}
var _open_areas: Array[String] = ["Field"]
var _lamps: Array[Node] = []


## Builds the lot and waits until its collision and navigation are live.
func build() -> void:
	greybox = GREYBOX.instantiate()
	add_child(greybox)
	for door in greybox.get_node("Doors").get_children():
		_doors[StringName(door.get_meta("shop_id"))] = door
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	region = NavigationRegion3D.new()
	add_child(region)
	await _rebake()
	_lamps = get_tree().get_nodes_in_group("powered_light")


func map() -> RID:
	return get_world_3d().navigation_map


## Opens a door for good: the slabs go, the area behind it joins the spawns, the paths follow.
func open_door(door_id: StringName) -> void:
	var door: Node3D = _doors.get(door_id)
	if door == null:
		return
	for slab in door.get_children():
		if slab is CSGShape3D:
			(slab as CSGShape3D).use_collision = false
			(slab as CSGShape3D).hide()
	for area: String in DOOR_AREAS.get(door_id, []):
		_open_areas.append(area)
	_rebake()


func door_ids() -> Array[StringName]:
	return _doors.keys()


func door_cost(door_id: StringName) -> int:
	return int(_doors[door_id].get_meta("cost"))


## The points a door can be used from: the middle of each of its slabs.
func door_points(door_id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var door: Node3D = _doors.get(door_id)
	if door != null:
		for slab in door.get_children():
			if slab is CSGShape3D and (slab as CSGShape3D).use_collision:
				points.append((slab as Node3D).global_position)
	return points


func spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for area in _open_areas:
		var markers := greybox.get_node_or_null(area + "/ZombieSpawns")
		if markers != null:
			for marker in markers.get_children():
				points.append((marker as Marker3D).global_position)
	return points


## Where boards can be put back: the gaps in the field's fence.
func repair_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for node in greybox.get_node("Field").get_children():
		if node.name.begins_with("Breach"):
			points.append((node as Node3D).global_position)
	return points


func player_spawn(index: int) -> Vector3:
	var markers := greybox.get_node("Field/PlayerSpawns").get_children()
	return (markers[index % markers.size()] as Marker3D).global_position


func is_lit(point: Vector3) -> bool:
	for lamp: Light3D in _lamps:
		if lamp.visible and _flat(point, lamp.global_position) < LAMP_REACH:
			return true
	return false


## A body for one player, driven by the server (its own physics step is off).
func add_body(spawn: Vector3, local_input: bool) -> Player:
	var body := PLAYER_SCENE.instantiate() as Player
	body.local_input = local_input
	body.capture_mouse = local_input
	add_child(body)
	body.teleport(spawn)
	body.set_physics_process(false)
	return body


func _rebake() -> void:
	var before := NavigationServer3D.map_get_iteration_id(map())
	region.navigation_mesh = NavmeshBaker.bake(greybox)
	for _i in 600:
		if NavigationServer3D.map_get_iteration_id(map()) >= before + NAV_ITERATIONS:
			break
		await get_tree().physics_frame


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
