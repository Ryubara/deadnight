class_name NightWorld
extends Node3D
## The place a night happens in: the drive-in greybox, its navigation mesh, its doors and spawn
## markers, and the players' bodies. The server asks it where things are; it decides nothing
## itself. A door bought is the lot's own business: `LotDoors` follows the rules (`bind`) and
## `DoorNavigation` rebakes the zombies' mesh when one opens (`docs/research/zombies.md`, Doors).

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
## Static bodies of CSG shapes reach the physics space after a few steps.
const SETTLE_FRAMES := 4
## A new navigation region is usable after the map's second iteration.
const NAV_ITERATIONS := 2
## Frames given to the first mesh before the lot is used anyway.
const NAV_WAIT_FRAMES := 600
## Metres into the field, from the boards, that a player puts them back from.
const REPAIR_SPOT := 1.4
## The areas whose zombie spawns open with a door (the field's are always open).
const DOOR_AREAS := {
	&"door_concession": ["Midway"],
	&"door_yard": ["GeneratorYard"],
	&"door_booth": ["ProjectionBooth"],
	&"door_back_lot": ["BackLot"],
	&"door_road": ["Road"],
}

var greybox: Node3D
## The lot's doors: they open when the rules sell them and tell the navigation (`door_opened`).
var doors: LotDoors
var navigation: DoorNavigation

## The lot's breaker posts, one for each circuit a player can switch.
var switches: LotSwitches
## The lot's fuel can spots, where a player buys fuel for the generator.
var fuel: LotFuel

var _door_nodes: Dictionary[StringName, Node3D] = {}
var _barricades: Dictionary[StringName, Barricade] = {}
var _lamps: LotLamps
## The rules' generator, which says which circuits are lit; without one every lamp is.
var _generator: GeneratorState


## Builds the lot and waits until its collision and navigation are live.
func build() -> void:
	greybox = GREYBOX.instantiate()
	add_child(greybox)
	doors = greybox.get_node("Doors") as LotDoors
	for door in doors.get_children():
		_door_nodes[StringName(door.get_meta("shop_id"))] = door
	for node in greybox.find_children("*", "Barricade", true, false):
		var barricade := node as Barricade
		_barricades[StringName(barricade.get_meta(&"barricade_id"))] = barricade
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	navigation = DoorNavigation.new()
	add_child(navigation)
	var before := NavigationServer3D.map_get_iteration_id(map())
	navigation.setup(greybox, doors)
	for _i in NAV_WAIT_FRAMES:
		if NavigationServer3D.map_get_iteration_id(map()) >= before + NAV_ITERATIONS:
			break
		await get_tree().physics_frame
	_lamps = LotLamps.new(greybox)
	switches = LotSwitches.new(greybox)
	fuel = LotFuel.new(greybox)


func map() -> RID:
	return get_world_3d().navigation_map


## Follows the rules: the lot opens the doors they sell (and any they already have open), the
## boards across each breach are as many as the rules say, and each breaker post shows its circuit.
func bind(rules: GameRules) -> void:
	doors.bind(rules)
	_generator = rules.generator
	switches.show_all(_generator)
	for id: StringName in _barricades:
		_barricades[id].set_boards(rules.barricades.boards_of(id), false)
	rules.event_emitted.connect(_on_rules_event)


func door_ids() -> Array[StringName]:
	return _door_nodes.keys()


func door_cost(door_id: StringName) -> int:
	return int(_door_nodes[door_id].get_meta("cost"))


## The points a door can be used from: the middle of each of its slabs.
func door_points(door_id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var door: Node3D = _door_nodes.get(door_id)
	if door != null:
		for slab in door.get_children():
			if slab is CSGShape3D and (slab as CSGShape3D).use_collision:
				points.append((slab as Node3D).global_position)
	return points


## The areas the dead can come from: the field, and the area behind each door that is open.
func open_areas() -> Array[String]:
	var areas: Array[String] = ["Field"]
	for door_id: StringName in _door_nodes:
		if _door_nodes[door_id].has_meta(&"open"):
			for area: String in DOOR_AREAS.get(door_id, []):
				areas.append(area)
	return areas


func spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for area in open_areas():
		var markers := greybox.get_node_or_null(area + "/ZombieSpawns")
		if markers != null:
			for marker in markers.get_children():
				points.append((marker as Marker3D).global_position)
	return points


## Where boards can be put back: the gaps in the field's fence.
func repair_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for barricade in _barricades.values():
		points.append(barricade.centre())
	return points


## The breaches' ids (the rules' `BarricadeTuning.ids`).
func barricade_ids() -> Array[StringName]:
	return _barricades.keys()


func barricade(id: StringName) -> Barricade:
	return _barricades.get(id)


## Where to stand in the field to put boards back across `id`.
func repair_spot(id: StringName) -> Vector3:
	return _barricades[id].standing_point(REPAIR_SPOT)


## The breaches as the zombie simulation sees them.
func gates() -> Dictionary[StringName, ZombieGate]:
	var found: Dictionary[StringName, ZombieGate] = {}
	for id: StringName in _barricades:
		var barricade := _barricades[id]
		found[id] = ZombieGate.new(id, barricade.centre(), barricade.inward())
	return found


## The breach each zombie spawn point lies outside, by point (the field's; the other areas'
## spawns are already inside).
func spawn_gates() -> Dictionary[Vector3, StringName]:
	var found: Dictionary[Vector3, StringName] = {}
	for marker in greybox.get_node("Field/ZombieSpawns").get_children():
		var id := StringName(marker.get_meta(&"barricade_id", ""))
		if id != &"":
			found[(marker as Marker3D).global_position] = id
	return found


func _on_rules_event(event: Dictionary) -> void:
	switches.follow(event)
	match event["type"]:
		&"board_torn", &"board_repaired":
			var barricade: Barricade = _barricades.get(StringName(event["barricade_id"]))
			if barricade != null:
				barricade.set_boards(event["boards"])  # torn or mended: the count says which


func player_spawn(index: int) -> Vector3:
	var markers := greybox.get_node("Field/PlayerSpawns").get_children()
	return (markers[index % markers.size()] as Marker3D).global_position


## Whether the ground at `point` is lit: a lamp within reach whose circuit the rules' generator
## has lit (switched on, and the tank not dry). Never reads a light node, so it is the same on a
## server that draws nothing.
func is_lit(point: Vector3) -> bool:
	return _lamps.lit_at(point, _generator)


## A body for one player, driven by the server (its own physics step is off).
func add_body(spawn: Vector3, local_input: bool) -> Player:
	var body := PLAYER_SCENE.instantiate() as Player
	body.local_input = local_input
	body.capture_mouse = local_input
	add_child(body)
	body.teleport(spawn)
	body.set_physics_process(false)
	return body
