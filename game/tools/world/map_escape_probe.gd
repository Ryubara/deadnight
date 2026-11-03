extends SceneTree
## Looks for ways out of a map and ways past a closed door, by moving the real player body
## (`PlayerSimulation`, the same rules the night ticks) and never by eye (#833).
##
## 1. The ground a player can walk (a navigation mesh with the doors in the state asked for) gives
##    the launch cells: ground near something to climb or squeeze past.
## 2. From each launch cell the body sprints at the thing ahead and jumps at different moments, or
##    crouch-walks at it. Where it settles, off the walkable ground, is a new standing place; from
##    each standing place the body tries again (a chain of hops, up to `--depth`).
## 3. A standing place is a violation when it is beyond the map (far from any ground of the map
##    with every door open), inside an area that is still closed (on ground that belongs to the open
##    map only), or very high (on top of a wall).
##
##   godot --headless --path game -s res://tools/world/map_escape_probe.gd -- \
##     --scene=res://world/drive_in_greybox.tscn --start=0,0,-43 --doors=none --out=<abs>.json
##
## `--doors` is `none`, `all`, or door ids separated by commas (opened before the walk).
## `--region=x0,z0,x1,z1[;x0,z0,x1,z1...]` keeps only the launch cells inside those rectangles (a
## stretch swept finer than the whole map). The report lists every standing place 0.9 m or more up
## (`raised`, with the hops that got there), the tops a roost check starts from.

const HOP_TICKS := 54
const SETTLE_TICKS := 24
const SURFACE_STEP := 0.05
const TOP := 9.0
const JUMP_TICKS := [0, 9, 20]
const NAV_CELL := 0.2
## A start this high (the walkable ground is 0.2 up) is on a prop.
const PERCH_FROM := 0.3

var _cell := 1.5
var _scene_path := ""
var _start := Vector3.ZERO
var _doors := "none"
var _out := ""
var _depth := 3
var _headings := 8
var _limit := 0
var _replay := ""
var _shard := 0
var _shards := 1
var _regions: Array[Rect2] = []
var _raised: Array = []

var _tuning: PlayerTuning
var _scene: Node3D
var _body: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _allowed_map: RID  # walkable ground with the doors as asked
var _open_map: RID  # walkable ground with every door open
var _nodes := {}  # key -> {pos, via, depth}
var _violations: Array = []
var _hops := 0
var _last_vertices := PackedVector3Array()


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--start="):
			var parts := argument.trim_prefix("--start=").split(",")
			_start = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		elif argument.begins_with("--doors="):
			_doors = argument.trim_prefix("--doors=")
		elif argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--depth="):
			_depth = int(argument.trim_prefix("--depth="))
		elif argument.begins_with("--headings="):
			_headings = int(argument.trim_prefix("--headings="))
		elif argument.begins_with("--replay="):
			_replay = argument.trim_prefix("--replay=")
		elif argument.begins_with("--cell="):
			_cell = float(argument.trim_prefix("--cell="))
		elif argument.begins_with("--shard="):
			var parts := argument.trim_prefix("--shard=").split("/")
			_shard = int(parts[0])
			_shards = int(parts[1])
		elif argument.begins_with("--region="):
			for rect in argument.trim_prefix("--region=").split(";"):
				var c := rect.split(",")
				_regions.append(
					Rect2(
						float(c[0]),
						float(c[1]),
						float(c[2]) - float(c[0]),
						float(c[3]) - float(c[1])
					)
				)
		elif argument.begins_with("--limit="):
			_limit = int(argument.trim_prefix("--limit="))
	_tuning = CameraProbe.tuning()
	await _run()
	quit()


func _run() -> void:
	# Reference ground with every door open.
	var open_scene := await _make_scene("all")
	_open_map = _bake_map(open_scene)
	await _settle(_open_map)
	var bounds := _nav_bounds()
	print("open bounds ", bounds, " vertices ", _last_vertices.size())
	open_scene.free()
	await physics_frame
	_scene = await _make_scene(_doors)
	_allowed_map = _bake_map(_scene)
	await _settle(_allowed_map)
	_space = _scene.get_world_3d().direct_space_state
	_make_body()
	if _replay != "":
		_replay_chain()
		return
	var started := Time.get_ticks_msec()
	var all_launches := _launch_cells(bounds)
	var launches: Array = []
	for i in all_launches.size():
		if i % _shards == _shard:
			launches.append(all_launches[i])
	print("launch cells: ", launches.size(), " (", Time.get_ticks_msec() - started, " ms)")
	var frontier: Array = []
	var done_cells := 0
	for cell: Vector3 in launches:
		for heading in _headings_for(cell):
			for hop in _hops_from(cell, heading, []):
				_consider(hop, 1, frontier)
		done_cells += 1
		if done_cells % 500 == 0:
			print(
				"  cells ",
				done_cells,
				"/",
				launches.size(),
				" nodes ",
				_nodes.size(),
				" hops ",
				_hops
			)
		if _limit > 0 and done_cells >= _limit:
			break
	var level := 1
	while not frontier.is_empty() and level < _depth:
		var next: Array = []
		print("depth ", level, ": ", frontier.size(), " standing places, hops so far ", _hops)
		for entry: Dictionary in frontier:
			for heading in _headings_for(entry["pos"], 16):
				for hop in _hops_from(entry["pos"], heading, entry["via"]):
					_consider(hop, level + 1, next)
		frontier = next
		level += 1
	var report := {
		"scene": _scene_path,
		"doors": _doors,
		"hops": _hops,
		"standing_places": _nodes.size(),
		"violations": _violations,
		"raised": _raised,
		"seconds": (Time.get_ticks_msec() - started) / 1000.0,
	}
	var file := FileAccess.open(_out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(
		"hops ",
		_hops,
		" standing places ",
		_nodes.size(),
		" violations ",
		_violations.size(),
		" -> ",
		_out
	)


func _make_scene(doors: String) -> Node3D:
	var scene := (load(_scene_path) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	for _i in 5:
		await physics_frame
	var door_node := scene.get_node_or_null("Doors") as LotDoors
	if door_node != null and doors != "none":
		var ids: Array[StringName] = []
		for door in door_node.get_children():
			ids.append(StringName(door.get_meta(&"shop_id")))
		for id in ids:
			if doors == "all" or doors.split(",").has(String(id)):
				door_node.open(id)
		for _i in 5:
			await physics_frame
	return scene


func _bake_map(scene: Node3D) -> RID:
	var mesh := NavigationMesh.new()
	mesh.cell_size = NAV_CELL
	mesh.cell_height = 0.1
	mesh.agent_radius = 0.4
	mesh.agent_height = 1.8
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 45.0
	var data := NavigationMeshSourceGeometryData3D.new()
	for node in scene.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if not shape.use_collision:
			continue
		if String(shape.name) == "Outskirts":
			continue
		if shape.get_parent() is CSGShape3D:
			continue
		data.add_faces(
			NavmeshBaker._box_faces(NavmeshBaker._size_of(shape)), shape.global_transform
		)
	# The boards of a breach and the windows' players-only blockers stop a player but are bodies,
	# not CSG: without them the walkable ground runs out through every window.
	for node in scene.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body.collision_layer & PhysicsLayers.BOARDS == 0:
			continue
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				var box := child as CollisionShape3D
				data.add_faces(
					NavmeshBaker._box_faces((box.shape as BoxShape3D).size), box.global_transform
				)
	NavigationServer3D.bake_from_source_geometry_data(mesh, data)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.map_force_update(map)
	_last_vertices = mesh.get_vertices()
	return map


func _settle(map: RID) -> void:
	var vertices := _last_vertices
	for _i in 240:
		await physics_frame
		if vertices.is_empty():
			return
		if (
			NavigationServer3D.map_get_closest_point(map, vertices[0]).distance_to(vertices[0])
			< 0.5
		):
			return
	push_error("navigation map never took the mesh")


func _nav_bounds() -> AABB:
	var found := AABB()
	var first := true
	for vertex in _last_vertices:
		if first:
			found = AABB(vertex, Vector3.ZERO)
			first = false
		else:
			found = found.expand(vertex)
	if first:
		push_error("no walkable ground baked")
	return found


func _make_body() -> void:
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _tuning.radius
	capsule.height = _tuning.height
	shape.shape = capsule
	shape.position.y = _tuning.height * 0.5
	_body.add_child(shape)
	_body.collision_layer = PhysicsLayers.BODY
	_body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	_body.floor_snap_length = 0.3
	_scene.add_child(_body)


## Ground cells (on the allowed walkable ground) with something taller than a step within two
## metres: where a hop is worth trying.
func _launch_cells(bounds: AABB) -> Array:
	var cells: Array = []
	var probe := BoxShape3D.new()
	probe.size = Vector3(4.4, 1.2, 4.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	var x := bounds.position.x
	while x <= bounds.end.x:
		var z := bounds.position.z
		while z <= bounds.end.z:
			for level in _levels(x, z):
				var ground := _ground(Vector3(x, level, z))
				if not _in_regions(ground):
					continue
				if ground != Vector3.INF and _reachable(ground):
					query.transform = Transform3D(Basis.IDENTITY, ground + Vector3(0, 0.95, 0))
					if not _space.intersect_shape(query, 1).is_empty():
						cells.append(ground)
			z += _cell
		x += _cell
	return cells


## The heights of walkable ground over (x, z): found by closest-point queries at a few heights.
func _levels(x: float, z: float) -> Array:
	var found: Array = []
	for height in [0.0, 3.4, 6.8]:
		var closest := NavigationServer3D.map_get_closest_point(_allowed_map, Vector3(x, height, z))
		if Vector2(closest.x - x, closest.z - z).length() < 0.12:
			var seen := false
			for level: float in found:
				if absf(level - closest.y) < 0.3:
					seen = true
			if not seen:
				found.append(closest.y)
	return found


func _ground(at: Vector3) -> Vector3:
	var closest := NavigationServer3D.map_get_closest_point(_allowed_map, at)
	if Vector2(closest.x - at.x, closest.z - at.z).length() < 0.12 and absf(closest.y - at.y) < 0.3:
		return closest
	return Vector3.INF


## Directions with something solid ahead at knee height within three metres.
func _headings_for(at: Vector3, count: int = -1) -> Array:
	var directions: Array = []
	var total := _headings if count < 0 else count
	for i in total:
		var angle := TAU * i / total
		var direction := Vector3(sin(angle), 0, cos(angle))
		var query := PhysicsRayQueryParameters3D.create(
			at + Vector3(0, 0.55, 0), at + Vector3(0, 0.55, 0) + direction * 3.0
		)
		query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
		if not _space.intersect_ray(query).is_empty():
			directions.append(direction)
	return directions


## Every settled position the body reaches from `from`, sprint-jumping at `direction` with the jump
## pressed at several moments, and crouch-walking at it. Each is {pos, via}.
func _hops_from(from: Vector3, direction: Vector3, via: Array) -> Array:
	var results: Array = []
	var plans: Array = []
	for jump_tick: int in JUMP_TICKS:
		plans.append(["sprint_jump", true, jump_tick, false])
	plans.append(["walk_jump", false, 0, false])
	plans.append(["crouch_walk", false, -1, true])
	for plan: Array in plans:
		var landed := _run_hop(from, direction, plan[1], plan[2], plan[3])
		if landed != Vector3.INF:
			results.append({"pos": landed, "via": via + [_step(from, direction, plan[0], plan[2])]})
	return results


func _step(from: Vector3, direction: Vector3, mode: String, jump_tick: int) -> Dictionary:
	return {
		"from": [snappedf(from.x, 0.001), snappedf(from.y, 0.001), snappedf(from.z, 0.001)],
		"yaw": snappedf(atan2(-direction.x, -direction.z), 0.0001),
		"mode": mode,
		"jump_tick": jump_tick,
	}


## One run of the real body. Returns where it settled, or INF when it settled back where it
## began (nothing learned).
func _run_hop(
	from: Vector3, direction: Vector3, sprint: bool, jump_tick: int, crouch: bool
) -> Vector3:
	_hops += 1
	var state := PlayerMotionState.new()
	# A standing place on a prop is where the body stood: start there exactly. The floor under a
	# capsule that rests on a rim is the ground, inside the prop, and a hop from there is not one a
	# player can make (it tunnelled through a 0.4 m fence, #846).
	if from.y > PERCH_FROM:
		state.position = from
	else:
		state.position = Vector3(from.x, _floor_under(from) + 0.02, from.z)
	state.on_floor = true
	var command := PlayerCommand.new()
	command.move = Vector2(0, -1)
	command.yaw = atan2(-direction.x, -direction.z)
	command.sprint = sprint
	command.crouch = crouch
	var delta := 1.0 / Engine.physics_ticks_per_second
	for tick in HOP_TICKS:
		command.jump = jump_tick >= 0 and tick >= jump_tick and tick < jump_tick + 3
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	command.move = Vector2.ZERO
	command.sprint = false
	command.jump = false
	command.crouch = false
	for tick in SETTLE_TICKS:
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	if not state.on_floor and state.position.y > -0.5:
		return Vector3.INF
	if state.position.distance_to(from) < 0.6 and absf(state.position.y - from.y) < 0.3:
		return Vector3.INF
	return state.position


## The height of the solid floor under `at` (the walkable mesh floats a little above it).
func _floor_under(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3(0, 0.6, 0), at - Vector3(0, 1.0, 0)
	)
	query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BOARDS
	var hit := _space.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else at.y


## Files a settled position: ground of the allowed map is nothing new, anywhere else is a standing
## place (and a violation when it is beyond the map, inside a closed area, or very high).
func _consider(hop: Dictionary, depth: int, frontier: Array) -> void:
	var pos: Vector3 = hop["pos"]
	var allowed := _distance(_allowed_map, pos)
	var on_ground := allowed.x < 0.5 and absf(allowed.y) < 0.4
	var unreachable := false
	if on_ground:
		if _reachable(pos):
			return
		unreachable = true
	var key := Vector3i(roundi(pos.x / 0.5), roundi(pos.y / 0.25), roundi(pos.z / 0.5))
	if _nodes.has(key):
		return
	_nodes[key] = true
	var open := _distance(_open_map, pos)
	if pos.y >= 0.9:
		(
			_raised
			. append(
				{
					"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
					"depth": depth,
					"via": hop["via"],
				}
			)
		)
	var kind := ""
	if pos.y < -0.6:
		kind = "fell_off_the_map"
	elif open.x > 3.0:
		kind = "beyond_the_map"
	elif unreachable:
		kind = "inside_a_closed_area" if open.x < 0.6 else "beyond_the_map"
	elif open.x < 0.6 and absf(open.y) < 0.5 and (allowed.x > 1.5 or absf(allowed.y) > 1.0):
		kind = "inside_a_closed_area"
	elif pos.y >= 2.4:
		kind = "high"
	if kind != "":
		(
			_violations
			. append(
				{
					"kind": kind,
					"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
					"depth": depth,
					"open_gap": [snappedf(open.x, 0.01), snappedf(open.y, 0.01)],
					"via": hop["via"],
				}
			)
		)
	if depth < _depth and pos.y > -0.5:
		frontier.append(hop)


## Whether the walkable ground at `pos` can be walked to from the start, with the doors as asked.
func _reachable(pos: Vector3) -> bool:
	var query := NavigationPathQueryParameters3D.new()
	query.map = _allowed_map
	query.start_position = _start
	query.target_position = pos
	query.path_search_max_polygons = 1000000
	query.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_EDGECENTERED
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	var path := result.path
	if path.is_empty():
		return false
	var closest := NavigationServer3D.map_get_closest_point(_allowed_map, pos)
	return path[path.size() - 1].distance_to(closest) < 0.8


## (horizontal distance, height above) of `pos` against the nearest point of a walkable map.
func _distance(map: RID, pos: Vector3) -> Vector2:
	var closest := NavigationServer3D.map_get_closest_point(map, pos)
	return Vector2(Vector2(closest.x - pos.x, closest.z - pos.z).length(), pos.y - closest.y)


## Runs a recorded chain of hops again (`--replay=<file>` holds `{"via": [...]}`), printing where
## each one lands, then tries every hop from the end and prints where those land.
func _replay_chain() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_replay))
	var via: Array = data["via"]
	var at := Vector3.INF
	for step: Dictionary in via:
		var from := Vector3(step["from"][0], step["from"][1], step["from"][2])
		if at != Vector3.INF:
			from = at
		var yaw: float = step["yaw"]
		var direction := Vector3(-sin(yaw), 0, -cos(yaw))
		var sprint: bool = step["mode"] == "sprint_jump"
		var crouch: bool = step["mode"] == "crouch_walk"
		var landed := _run_hop(from, direction, sprint, int(step["jump_tick"]), crouch)
		print(
			"STEP ",
			step["mode"],
			" jump@",
			step["jump_tick"],
			" yaw ",
			step["yaw"],
			" from ",
			from,
			" -> ",
			landed
		)
		at = landed
	print("AT END ", at)
	for hop: Dictionary in _hops_from_all(at):
		var landing: Vector3 = hop["pos"]
		print(
			"  from end: ",
			hop["via"][0]["mode"],
			" jump@",
			hop["via"][0]["jump_tick"],
			" yaw ",
			hop["via"][0]["yaw"],
			" -> ",
			landing,
			" open ",
			_distance(_open_map, landing),
			" allowed ",
			_distance(_allowed_map, landing)
		)


func _hops_from_all(at: Vector3) -> Array:
	var results: Array = []
	for i in 16:
		var angle := TAU * i / 16
		results.append_array(_hops_from(at, Vector3(sin(angle), 0, cos(angle)), []))
	return results


func _in_regions(at: Vector3) -> bool:
	if _regions.is_empty() or at == Vector3.INF:
		return true
	for rect in _regions:
		if rect.has_point(Vector2(at.x, at.z)):
			return true
	return false
