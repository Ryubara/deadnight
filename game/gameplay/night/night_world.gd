# gdlint: disable=max-public-methods
class_name NightWorld
extends Node3D
## The place a night happens in: the map's scene (the drive-in greybox, or another entry of
## `MapRegistry`), its navigation mesh, its doors and spawn markers, and the players' bodies. The
## server asks it where things are; it decides nothing itself. A door bought is the lot's own
## business: `LotDoors` follows the rules (`bind`) and `DoorNavigation` swaps in the zombies' mesh
## for the new set when one opens (`docs/research/zombies.md`, Doors).

const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
## Static bodies of CSG shapes reach the physics space after a few steps.
const SETTLE_FRAMES := 4
## Frames given to the first mesh before the lot is used anyway.
const NAV_WAIT_FRAMES := 600
## Metres a path may end from its goal and still reach it.
const NAV_REACHED := 1.0
## Metres into the field, from the boards, that a player puts them back from.
const REPAIR_SPOT := 1.4
## A scene to build instead of the map's own (`MapInfo.scene_path`): a test or a capture that plays
## a map the picker does not offer yet (the second map). Set before `build`. A map is a scene with
## the lot's nodes (`Doors`, `ShopSpots`, `Lighting`, the barricades) and either the lot's `Field/`
## spawn groups or the flat ones of the second map (`MapLayout`).
var scene: PackedScene

var greybox: Node3D
## The map this world was built from (`build`).
var map_info: MapInfo
## The lot's doors: they open when the rules sell them and tell the navigation (`door_opened`).
var doors: LotDoors
var navigation: DoorNavigation

## The lot's breaker posts, one for each circuit a player can switch.
var switches: LotSwitches
## The lot's fuel can spots, where a player buys fuel for the generator.
var fuel: LotFuel
## The prize crane's cabinet, solid in this world as in every other (`CraneBlock`).
var crane_block: CraneBlock

## Where the dead rise and the players start (`MapLayout`), read from the scene.
var layout: MapLayout
## The ground the map is played on: a player over none of it is out of the playable space
## (`PlayBounds`, read from the scene once the map is solid).
var bounds: PlayBounds

var _door_nodes: Dictionary[StringName, Node3D] = {}
## The open areas the map walks to (`_walkable`).
var _walkable_areas: Dictionary[String, bool] = {}
var _barricades: Dictionary[StringName, Barricade] = {}
var _lamps: LotLamps
## The rules' generator, which says which circuits are lit; without one every lamp is.
var _generator: GeneratorState
## `shop_spots`, read once the markers are in the scene.
var _shop_spots: Array[Dictionary] = []
var _shop_spots_built := false


## Builds the map (the default one when none is given) and waits until its collision and navigation
## are live.
func build(info: MapInfo = null) -> void:
	map_info = info if info != null and info.is_playable() else MapRegistry.default_map()
	WebProbe.mark("lot: instantiate")
	greybox = (scene if scene != null else map_info.load_scene()).instantiate()
	add_child(greybox)
	layout = MapLayout.new(greybox)
	WebProbe.mark("lot: in the tree")
	doors = greybox.get_node("Doors") as LotDoors
	for door in doors.get_children():
		_door_nodes[StringName(door.get_meta("shop_id"))] = door
	for node in greybox.find_children("*", "Barricade", true, false):
		var barricade := node as Barricade
		_barricades[StringName(barricade.get_meta(&"barricade_id"))] = barricade
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	WebProbe.mark("lot: settled")
	bounds = PlayBounds.of(greybox)
	if LotBatcher.wanted(map_info):
		var batched := LotBatcher.batch(greybox, MeshBatch.DEFAULT_CELL, LotBatcher.small_range)
		WebProbe.mark(
			(
				"lot: batched %d to %d surfaces"
				% [batched["surfaces_before"], batched["surfaces_after"]]
			)
		)
	# The map takes a new mesh in on the physics step, not on a worker thread: the server's dead
	# must path over the same map on every machine (#733, #736).
	NavigationServer3D.map_set_use_async_iterations(map(), false)
	navigation = DoorNavigation.new()
	navigation.saved = layout.navmeshes()
	add_child(navigation)
	navigation.setup(greybox, doors)
	for _i in NAV_WAIT_FRAMES:
		if _map_answers():
			break
		await get_tree().physics_frame
	WebProbe.mark("lot: navigation ready")
	_lamps = LotLamps.new(greybox)
	switches = LotSwitches.new(greybox)
	fuel = LotFuel.new(greybox)
	crane_block = CraneBlock.new()
	add_child(crane_block)
	crane_block.setup(shop_spots())


func map() -> RID:
	return get_world_3d().navigation_map


## The rules table the night on this map plays by: `base` (the shared table, the lot's) with the
## map's own overlay laid over it, or `base` itself for a map that has none.
func rules_for(base: RulesTuning) -> RulesTuning:
	var overlay := layout.map_tuning() if layout != null else null
	return overlay.apply(base) if overlay != null else base


## Gives the zombie simulation what it needs of this map: which ground is lit, the breaches, the
## storey (0 for one floor) and `sight`, the way it sees walls.
func equip(sim: ZombieSim, sight: Callable) -> void:
	sim.lit_probe = is_lit
	sim.gates = gates()
	sim.set_floors(storey(), sight)


## The height of one storey of the map, or 0 for a map of one floor (the lot).
func storey() -> float:
	return layout.storey() if layout != null else 0.0


## How far a press at `a` reaches `b`: the flat distance, or infinity when `b` is on another floor.
func reach_distance(a: Vector3, b: Vector3) -> float:
	if not on_level(a, b):
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()


## Whether `a` and `b` are on one floor: always on a map of one, else within half a storey in
## height. What a press reaches is judged by this as well as by the flat distance, so a player
## upstairs is not in reach of a door or a wall below.
func on_level(a: Vector3, b: Vector3) -> bool:
	var height := storey()
	return height <= 0.0 or absf(a.y - b.y) <= height * 0.5


## Where the lamps that light the ground hang, by the circuit each hangs on (a sign's glow lights
## none): a bot tells which circuit is lighting the ground people stand on.
func lamp_points() -> Dictionary:
	var found := {}
	for lamp in _lamps.lamps:
		if lamp.decor:
			continue
		if not found.has(lamp.circuit):
			found[lamp.circuit] = []
		found[lamp.circuit].append(lamp.position)
	return found


## True once the navigation map finds a way across the open ground the night starts on, between
## its first two spawn points (the field is never walled off; the second map's front yard neither).
## The map's iteration id is no sign of it: in the browser it stays at 1 while the map already
## answers, and waiting for a second one cost the full `NAV_WAIT_FRAMES` (10 s) before every night
## (#335).
func _map_answers() -> bool:
	var spawns := layout.start_spawns()
	var from := spawns[0].global_position
	var to := spawns[1].global_position
	var way := NavigationServer3D.map_get_path(map(), from, to, true, NavLayers.DEAD)
	return not way.is_empty() and way[way.size() - 1].distance_to(to) < NAV_REACHED


## Follows the rules: the lot opens the doors they sell (and any they already have open), the
## boards across each breach are as many as the rules say, and each breaker post shows its circuit.
func bind(rules: GameRules) -> void:
	doors.bind(rules)
	_generator = rules.generator
	switches.show_all(_generator)
	for id: StringName in _barricades:
		_barricades[id].set_boards(rules.barricades.boards_of(id), false)
	crane_block.place(rules.crane.spot)
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


## Where to walk to use a door: a point on the open ground in front of each of its slabs, 1.5 m out
## (`Stand*` markers, `DOOR_STAND_DISTANCE` in tools/world/build_greybox.py). The slab's middle
## (`door_points`) is where the hand reaches from, not a place to walk to: the walking mesh is cut
## back from a wall on both sides alike, so a goal in a slab snaps to the shut area behind it as
## often as to the open ground in front (the booth's door did, #590). A stand is on the mesh the
## moment the door before it is open, and within `NightTuning.use_reach` of the slab.
func door_stands(door_id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var door: Node3D = _door_nodes.get(door_id)
	if door != null:
		for part in door.get_children():
			if part is Marker3D:
				points.append((part as Marker3D).global_position)
	return points


## The areas the dead can come from: the field, and the area behind each door that is open.
func open_areas() -> Array[String]:
	var areas: Array[String] = layout.start_areas()
	for door_id: StringName in _door_nodes:
		if _door_nodes[door_id].has_meta(&"open"):
			for area: String in layout.door_areas(_door_nodes[door_id], door_id):
				if not areas.has(area):
					areas.append(area)
	return areas


## Where the dead may rise: the markers of the field and of each open area whose ground the map
## already walks out of (`_walkable`). A door opened a moment ago has its area in `open_areas` at
## once but in the map a few physics ticks later (and for a lot nothing was saved for, a bake
## later): a dead one risen there walks to the nearest point of the island it stands on, the wall
## of the door's room, and stays (#591). The area joins here when the map takes it in, so the night
## asks again every `NightServer.SPAWN_RETRY_TICKS` (the answer is kept for an area once it is yes).
func spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for area in open_areas():
		if not _walkable(area):
			continue
		for marker in layout.spawn_markers(area):
			points.append(marker.global_position)
	return points


## Whether the map walks from the field to every spawn point of `area`. An area stays walkable once
## it has been (a door never closes again), so each is asked until it answers, then never again.
func _walkable(area: String) -> bool:
	if layout.start_areas().has(area) or _walkable_areas.has(area):
		return true
	var start := layout.start_spawns()[0].global_position
	for marker in layout.spawn_markers(area):
		var to := marker.global_position
		var id := StringName(marker.get_meta(&"barricade_id", ""))
		if _barricades.has(id):
			# A breach's dead rise outside it and must walk in: from where they rise to the inside of
			# the boards, and the map must walk from the field to that inside too (before a door's
			# mesh is in, the area is an island of its own that the bay or apron is on, #849).
			var inside := _barricades[id].standing_point(REPAIR_SPOT)
			if not _reaches(to, inside):
				return false
			to = inside
		if not _reaches(start, to):
			return false
	_walkable_areas[area] = true
	return true


## Whether the map walks from `from` to `to` (a path that ends within `NAV_REACHED` of it).
func _reaches(from: Vector3, to: Vector3) -> bool:
	var way := NavigationServer3D.map_get_path(map(), from, to, true, NavLayers.DEAD)
	return not way.is_empty() and _flat(way[way.size() - 1], to) < NAV_REACHED


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Where a player buys without a door: the weapons on the walls, the prize crane and the ammunition
## lockers, as `{kind, shop_id, position}` (`kind` is `wall`, `crane` or `ammo`; a locker has no
## shop id and sells the rounds of the weapon in hand). A crane spot also has `crane_spot`: its
## place in the rules' list of crane places (metadata `crane_spot`, 0 when not set).
func shop_spots() -> Array[Dictionary]:
	if _shop_spots_built:
		return _shop_spots
	var group := greybox.get_node_or_null("ShopSpots")
	if group == null:
		var none: Array[Dictionary] = []
		return none
	for marker in group.get_children():
		(
			_shop_spots
			. append(
				{
					"kind": StringName(marker.get_meta("kind")),
					"shop_id": StringName(marker.get_meta("shop_id")),
					"position": (marker as Node3D).global_position,
					"crane_spot": int(marker.get_meta("crane_spot", 0)),
					"yaw": _yaw_of(marker as Node3D),
				}
			)
		)
	# The markers do not move and the list is asked for by every player on every tick: it is read
	# once and shared, and read-only so a caller cannot change what the next one sees (#931).
	for spot in _shop_spots:
		spot.make_read_only()
	_shop_spots.make_read_only()
	_shop_spots_built = true
	return _shop_spots


## The turn of a marker about the up axis, from where its +Z axis points (an Euler angle is not
## reliable at a quarter turn).
func _yaw_of(marker: Node3D) -> float:
	var forward := marker.global_basis.z
	return atan2(forward.x, forward.z)


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
		found[id] = ZombieGate.new(id, barricade.centre(), barricade.inward(), barricade.board_half)
	return found


## The breach each zombie spawn point lies outside, by point (the lot's other areas' spawns are
## already inside and name none).
func spawn_gates() -> Dictionary[Vector3, StringName]:
	var found: Dictionary[Vector3, StringName] = {}
	for marker in layout.all_spawns():
		var id := StringName(marker.get_meta(&"barricade_id", ""))
		if id != &"":
			found[(marker as Marker3D).global_position] = id
	return found


func _on_rules_event(event: Dictionary) -> void:
	switches.follow(event)
	match event["type"]:
		&"crane_moved":
			crane_block.place(event["to_spot"])
		&"board_torn", &"board_repaired":
			var barricade: Barricade = _barricades.get(StringName(event["barricade_id"]))
			if barricade != null:
				barricade.set_boards(event["boards"])  # torn or mended: the count says which


func player_spawn(index: int) -> Vector3:
	var markers := layout.player_markers()
	return markers[index % markers.size()].global_position


## Whether the ground at `point` is lit: a lamp within reach whose circuit the rules' generator
## has lit (switched on, and the tank not dry). Never reads a light node, so it is the same on a
## server that draws nothing.
func is_lit(point: Vector3) -> bool:
	return _lamps.lit_at(point, _generator)


## A body for one player, driven by the server (its own physics step is off). `drawn` false makes
## a body that is only physics (a game server draws nothing): the Soldier's model, skeleton and
## animation are left out, which is most of a body's nodes and all of its per-frame work.
## `viewless` makes a body no one looks through (a bot's, one that draws nothing): its camera rig is
## not run in every drawn frame (`Player.make_viewless`).
func add_body(
	spawn: Vector3, local_input: bool, drawn: bool = true, viewless: bool = false
) -> Player:
	var body := PLAYER_SCENE.instantiate() as Player
	body.local_input = local_input
	body.capture_mouse = local_input
	body.dead = DeadField.new()
	if not drawn:
		body.strip_model()
	if not local_input:
		# Only the person's own body owns the current camera: a bot's, which enters the tree after
		# it, would take the view (#702).
		body.release_view()
	if viewless:
		# No one looks through it (a bot's, a body that draws nothing): its rig is not run either.
		body.make_viewless()
	add_child(body)
	body.teleport(spawn)
	body.set_physics_process(false)
	return body
