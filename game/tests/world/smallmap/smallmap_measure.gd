class_name SmallMapMeasure
extends RefCounted
## Measures the second map's greybox against the hard targets of
## `docs/research/maps/small-map-formula.md` ("The formula: hard targets for our map"), rows 1 to 19
## and 27 to 29. `run` builds the map in worlds of its own, bakes the meshes it needs and fills
## `rows`: one entry a target, with the measured value, the tolerance and whether it holds. The
## suites (`test_smallmap_formula.gd`) assert each row; `smallmap_report.gd` prints the table.
##
## How each is measured:
## - Floor areas: the floor mesh (no agent radius, 0.05 m cells) with the windows shut, the polygons
##   joined to the players' start; a polygon counts to the room whose rectangle holds its middle on
##   its floor (a stair's lower half to its ground room, its upper half upstairs).
## - Reachability, the ring and the loops: the zombies' mesh (the night's sizes) with the windows
##   shut, one bake for each set of sold links; path lengths along the mesh.
## - Windows, directions, distances: the sockets (`Windows/*`), the spawns (`ZombieSpawns/*`), the
##   players' spawns and the room rectangles; each window's spawn walks to its own room only, on a
##   mesh with the windows open and the links shut.
## - Sight lines and ceilings: rays at eye height between standing points of every room, and up
##   from the floor, in the map with every link open.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const EYE := 1.55
const SETTLE_FRAMES := 4
## The rooms' groups in the scene and the room each belongs to.
const GROUPS := ["Start", "Side", "UpperA", "UpperB"]
const ROOM_OF := {"Start": "start", "Side": "side", "UpperA": "upstairs", "UpperB": "upstairs"}
## The building's box: the floor mesh is baked inside it.
const BUILDING := AABB(Vector3(-7.0, -0.5, -9.0), Vector3(24.0, 8.0, 24.5))
## Row 15's windows a room, the maintainer's rule for this map (#917): one window a wall on the
## ground floor (the hall's west wall is the shop wall), a few upstairs, both in the half over the
## hall (two halves' windows on one deck would join the halves outside by a shorter way than the
## opening); the side room's two are a window and the breach, one at each end (#994: a second
## window in its south-west corner shared the breach's corner and the perk alcove's ground).
const WINDOWS := {"start": 2, "side": 2, "upstairs": 2}
## Row 18: how far inside a window its dead must reach by it (metres, along the window's +Z).
const INSIDE := 1.5
## Words that are Nacht der Untoten's, or of its setting, and never in ours (row 29).
const NOT_OURS := [
	"nacht", "untoten", "help", "cave", "bunker", "bomber", "verruckt", "nazi", "1945"
]

## One entry a target: {row, name, value, lo, hi, unit, ok, detail}.
var rows: Array[Dictionary] = []
## Measured facts the rows are made of, for the report and the tests' messages.
var facts := {}

var _host: Node
var _rects := {}
var _floors := {}
var _links: Array[StringName] = []


## Measures everything. `host` is a node in the tree; the worlds are made under it and freed.
func run(host: Node) -> void:
	_host = host
	_read_layout()
	var open := await _world(_links, false)
	var lot := open.get_node("Map") as Node3D
	await _measure_floor(lot)
	await _measure_links()
	await _measure_entries()
	_measure_sight_and_ceilings(lot)
	_measure_camera(lot)
	_measure_setting(lot)
	open.queue_free()
	await host.get_tree().process_frame
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["row"] < b["row"])


## A row by number.
func row(number: int) -> Dictionary:
	for entry in rows:
		if entry["row"] == number:
			return entry
	return {}


# --- Building the worlds -----------------------------------------------------------------------


## The greybox in a world of its own with `sold` links open; `shut_windows` fills every window's gap
## with a box the bakers read, so a mesh baked from it is the inside only.
func _world(sold: Array, shut_windows: bool) -> SubViewport:
	var world := SubViewport.new()
	world.own_world_3d = true
	world.size = Vector2i(4, 4)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_host.add_child(world)
	var lot := (load(SCENE) as PackedScene).instantiate() as Node3D
	lot.name = "Map"
	world.add_child(lot)
	if shut_windows:
		for socket: Node3D in lot.get_node("Windows").get_children():
			var gap: Vector3 = socket.get_meta(&"gap")
			var plug := CSGBox3D.new()
			plug.name = "Plug"
			plug.use_collision = true
			plug.size = gap
			plug.position = Vector3(0.0, gap.y / 2.0, 0.0)
			socket.add_child(plug)
	var doors := lot.get_node("Doors") as LotDoors
	for id: StringName in sold:
		doors.open(id)
	for _i in SETTLE_FRAMES:
		await _host.get_tree().physics_frame
	return world


func _read_layout() -> void:
	var lot := (load(SCENE) as PackedScene).instantiate()
	for group: String in GROUPS:
		var node := lot.get_node(group)
		_rects[group] = node.get_meta(&"rect")
		_floors[group] = float(node.get_meta(&"floor"))
	for door in lot.get_node("Doors").get_children():
		_links.append(StringName(door.get_meta(&"shop_id")))
	lot.free()


## The room group whose rectangle holds `point` on its floor (a point below half a storey is on
## the ground floor), or "".
func group_at(point: Vector3) -> String:
	var storey: float = _floors["UpperA"]
	for group: String in GROUPS:
		var on_floor: bool = (point.y >= storey * 0.5) == (_floors[group] > 0.0)
		if on_floor and (_rects[group] as Rect2).has_point(Vector2(point.x, point.z)):
			return group
	return ""


func _middle(lot: Node, group: String) -> Vector3:
	return (lot.get_node("Measure/Middles/" + group) as Node3D).global_position


func _add(
	number: int,
	name: String,
	value: Variant,
	lo: float,
	hi: float,
	unit: String,
	ok: bool,
	detail: String = ""
) -> void:
	rows.append(
		{
			"row": number,
			"name": name,
			"value": value,
			"lo": lo,
			"hi": hi,
			"unit": unit,
			"ok": ok,
			"detail": detail
		}
	)


func _within(value: float, lo: float, hi: float) -> bool:
	return value >= lo - 1e-3 and value <= hi + 1e-3


# --- Rows 1 to 7: floors, rooms and areas ------------------------------------------------------


func _measure_floor(lot: Node3D) -> void:
	var shut := await _world(_links, true)
	var nav := SmallMapNavigation.new(
		shut.get_node("Map") as Node3D, SmallMapNavigation.floor_mesh(BUILDING)
	)
	var start := _spawn_centre(lot)
	var inside := nav.connected_polygons(start + Vector3(0.0, 0.2, 0.0))
	var by_group := {}
	var total := 0.0
	for group: String in GROUPS:
		by_group[group] = 0.0
	for i in inside:
		var area := nav.polygon_area(i)
		total += area
		var group := group_at(nav.polygon_centre(i))
		if group != "":
			by_group[group] += area
	var upstairs: float = by_group["UpperA"] + by_group["UpperB"]
	facts["area"] = by_group.merged({"upstairs": upstairs, "total": total})
	_add(1, "Total floor inside, all links open", total, 540, 660, "m²", _within(total, 540, 660))
	var levels := {}
	for group: String in GROUPS:
		levels[_floors[group]] = true
	_add(2, "Floors", levels.size(), 2, 2, "", levels.size() == 2)
	_add(
		4,
		"Start room floor",
		by_group["Start"],
		188,
		230,
		"m²",
		_within(by_group["Start"], 188, 230)
	)
	_add(
		5, "Side room floor", by_group["Side"], 138, 168, "m²", _within(by_group["Side"], 138, 168)
	)
	var largest: bool = upstairs > by_group["Start"] and upstairs > by_group["Side"]
	_add(
		6,
		"Upstairs floor, the largest",
		upstairs,
		197,
		241,
		"m²",
		_within(upstairs, 197, 241) and largest,
		"halves %.0f + %.0f m²" % [by_group["UpperA"], by_group["UpperB"]]
	)
	var side: Rect2 = _rects["Side"]
	var width := minf(side.size.x, side.size.y)
	var length := maxf(side.size.x, side.size.y)
	_add(
		7,
		"Side room width (length at least 2.5 widths)",
		width,
		6,
		8,
		"m",
		_within(width, 6, 8) and length >= 2.5 * width,
		"%.1f x %.1f m, %.2f widths long" % [length, width, length / width]
	)
	nav.free_map()
	shut.queue_free()


## The middle of the players' start: the first eight markers, the places of the room's people. The
## seven after them (#1193) are where a night's bots stand round them, and do not move the start.
func _spawn_centre(lot: Node) -> Vector3:
	var centre := Vector3.ZERO
	var spawns := lot.get_node("PlayerSpawns").get_children().slice(0, NightHost.MAX_PLAYERS)
	for spawn: Node3D in spawns:
		centre += spawn.global_position
	return centre / spawns.size()


# --- Rows 3, 8, 11 to 14 and 19: links, ring, loops ----------------------------------------------


func _measure_links() -> void:
	var tree := _host.get_tree()
	# Which rooms each set of sold links joins, on the zombies' mesh with the windows shut.
	var joined := {}
	var lengths := {}
	for mask in 1 << _links.size():
		var sold: Array[StringName] = []
		for i in _links.size():
			if mask & (1 << i):
				sold.append(_links[i])
		var world := await _world(sold, true)
		var lot := world.get_node("Map")
		var nav := SmallMapNavigation.new(lot as Node3D, SmallMapNavigation.zombie_mesh())
		await nav.settle(tree)
		var pairs := {}
		for a: String in GROUPS:
			for b: String in GROUPS:
				if a < b and nav.can_reach(_middle(lot, a), _middle(lot, b)):
					pairs["%s-%s" % [a, b]] = true
		joined[mask] = pairs
		if mask == (1 << _links.size()) - 1:
			lengths = _ring_and_loops(lot, nav)
		nav.free_map()
		world.queue_free()
		await tree.process_frame
	facts["joined"] = joined
	# Row 3: three rooms, the upstairs two halves joined with no link sold.
	var halves: bool = joined[0].has("UpperA-UpperB")
	var rooms := {}
	for group: String in GROUPS:
		rooms[ROOM_OF[group]] = true
	_add(
		3,
		"Rooms (upstairs in two halves joined by an opening)",
		rooms.size(),
		3,
		3,
		"",
		rooms.size() == 3 and halves
	)
	# Row 11 and 12: each link alone joins one pair of rooms; together the three pairs are a triangle.
	var edges := {}
	for i in _links.size():
		var pairs: Dictionary = joined[1 << i]
		var rooms_joined := _room_pairs(pairs)
		edges[_links[i]] = rooms_joined
	facts["edges"] = edges
	var triangle := {}
	for id: StringName in edges:
		for pair: String in edges[id]:
			triangle[pair] = true
	var one_each: bool = edges.values().all(func(p: Array) -> bool: return p.size() == 1)
	_add(
		11,
		"Paid links, each joining two rooms",
		_links.size(),
		3,
		3,
		"",
		_links.size() == 3 and one_each and triangle.size() == 3,
		str(edges)
	)
	var ring_ok := true
	var notes: Array[String] = []
	for mask in 1 << _links.size():
		var bits := 0
		for i in _links.size():
			bits += 1 if mask & (1 << i) else 0
		var reached := _rooms_from_start(joined[mask])
		var expect := 1
		if bits == 1:
			expect = 2 if (edges[_links[_bit(mask)]] as Array)[0].contains("start") else 1
		elif bits >= 2:
			expect = 3
		if reached.size() != expect:
			ring_ok = false
			notes.append("%s: %s" % [_names(mask), reached])
		# Two links make a chain (a room with one way in: a dead end); three close the ring.
		if bits >= 2:
			var degree := {}
			for i in _links.size():
				if mask & (1 << i):
					var pair: String = (edges[_links[i]] as Array)[0]
					for room: String in pair.split("-"):
						degree[room] = degree.get(room, 0) + 1
			var ends := degree.values().count(1)
			if (bits == 2 and ends != 2) or (bits == 3 and ends != 0):
				ring_ok = false
				notes.append("%s: ends %d" % [_names(mask), ends])
	_add(
		12,
		"One ring, closed only by the third link",
		"yes" if ring_ok else "no",
		0,
		0,
		"",
		ring_ok,
		", ".join(notes)
	)
	var lap: float = lengths.get("ring", INF)
	_add(13, "The ring's lap", lap, 48, 72, "m", _within(lap, 48, 72))
	var loop_start: float = lengths.get("loop_start", INF)
	_add(
		8,
		"Loop round the start room's counter and pillars",
		loop_start,
		25,
		36,
		"m",
		_within(loop_start, 25, 36)
	)
	var loop_side: float = lengths.get("loop_side", INF)
	_add(
		14,
		"Loop round the side room's rack row",
		loop_side,
		25,
		36,
		"m",
		_within(loop_side, 25, 36)
	)
	facts["legs"] = lengths.get("legs", [])


func _bit(mask: int) -> int:
	for i in _links.size():
		if mask & (1 << i):
			return i
	return -1


func _names(mask: int) -> String:
	var names: Array[String] = []
	for i in _links.size():
		if mask & (1 << i):
			names.append(String(_links[i]))
	return "[%s]" % ", ".join(names)


## The pairs of rooms (not halves) a set of joined groups makes, as "a-b" sorted.
func _room_pairs(pairs: Dictionary) -> Array:
	var found := {}
	for pair: String in pairs:
		var parts := pair.split("-")
		var a: String = ROOM_OF[parts[0]]
		var b: String = ROOM_OF[parts[1]]
		if a != b:
			found["%s-%s" % [a if a < b else b, b if a < b else a]] = true
	return found.keys()


## The rooms the players' start reaches through the joined pairs.
func _rooms_from_start(pairs: Dictionary) -> Array:
	var reached := {"start": true}
	for pair: String in _room_pairs(pairs):
		var parts := pair.split("-")
		if parts[0] == "start" or parts[1] == "start":
			reached[parts[0]] = true
			reached[parts[1]] = true
	return reached.keys()


func _ring_and_loops(lot: Node, nav: SmallMapNavigation) -> Dictionary:
	var found := {}
	var legs: Array[float] = []
	found["ring"] = _lap(lot.get_node("Measure/Ring"), nav, legs)
	found["legs"] = legs
	found["loop_start"] = _lap(lot.get_node("Measure/LoopStart"), nav, [])
	found["loop_side"] = _lap(lot.get_node("Measure/LoopSide"), nav, [])
	return found


func _lap(points: Node, nav: SmallMapNavigation, legs: Array) -> float:
	var markers := points.get_children()
	var total := 0.0
	for i in markers.size():
		var a := (markers[i] as Node3D).global_position
		var b := (markers[(i + 1) % markers.size()] as Node3D).global_position
		var leg := nav.walk_length(a, b)
		legs.append(leg)
		total += leg
	return total


# --- Rows 15 to 19: windows, directions, spawns, stairs ------------------------------------------


func _measure_entries() -> void:
	var tree := _host.get_tree()
	var world := await _world([], false)
	var lot := world.get_node("Map")
	var counts := {"start": 0, "side": 0, "upstairs": 0}
	var breaches := {}
	var halves := {}
	var sockets := {}
	for socket: Node3D in lot.get_node("Windows").get_children():
		var inside := socket.global_position + socket.global_basis.z * 0.6 + Vector3.UP * 0.5
		var group := group_at(inside)
		if group == "":
			continue
		var room: String = ROOM_OF[group]
		counts[room] += 1
		if room == "upstairs":
			halves[group] = halves.get(group, 0) + 1
		if socket.get_meta(&"kind") == "breach":
			breaches[room] = breaches.get(room, 0) + 1
		sockets[socket.get_meta(&"barricade_id")] = [socket, group]
	facts["windows"] = counts.merged({"halves": halves, "breaches": breaches})
	var windows_ok: bool = (
		counts["start"] == WINDOWS["start"]
		and counts["side"] == WINDOWS["side"]
		and counts["upstairs"] == WINDOWS["upstairs"]
		and breaches.get("side", 0) == 1
		and breaches.size() == 1
		and halves.get("UpperA", 0) == WINDOWS["upstairs"]
	)
	_add(
		15,
		"Windows start / side (one a breach) / upstairs (over the hall)",
		"%d / %d / %d" % [counts["start"], counts["side"], counts["upstairs"]],
		0,
		0,
		"",
		windows_ok,
		"upstairs halves %s, breaches %s" % [halves, breaches]
	)

	# Row 16: the walls with an entry, from each room's middle (upstairs with its stairs shut).
	var sides := {"start": {}, "side": {}, "upstairs": {}}
	for id: String in sockets:
		var socket: Node3D = sockets[id][0]
		var group: String = sockets[id][1]
		sides[ROOM_OF[group]][_side_of(group, socket.global_position)] = true
	for door: Node3D in lot.get_node("Doors").get_children():
		var slab := door.get_node("Slab") as Node3D
		for group: String in ["Start", "Side"]:
			var at := slab.global_position
			var rect: Rect2 = (_rects[group] as Rect2).grow(0.5)
			if rect.has_point(Vector2(at.x, at.z)) and at.y < _floors["UpperA"]:
				sides[ROOM_OF[group]][_side_of(group, at)] = true
	facts["directions"] = sides
	var directions_ok: bool = (
		sides["start"].size() == 3 and sides["side"].size() == 3 and sides["upstairs"].size() == 2
	)
	_add(
		16,
		"Directions to watch start / side / upstairs",
		"%d / %d / %d" % [sides["start"].size(), sides["side"].size(), sides["upstairs"].size()],
		0,
		0,
		"",
		directions_ok,
		str(sides)
	)

	# Row 17: the players' start to the nearest window of the start room.
	var centre := _spawn_centre(lot)
	var nearest := INF
	for id: String in sockets:
		if sockets[id][1] == "Start":
			nearest = minf(nearest, SmallMapNavigation.flat(centre, sockets[id][0].global_position))
	_add(17, "Players' start to the nearest window", nearest, 4, 7, "m", _within(nearest, 4, 7))

	# Row 18: each spawn 5 to 15 m outside its window, in no room; the way from it to the floor
	# just inside its own window comes in by that window (not round to another: #824); and it walks
	# into its own room only (the links shut, the windows open): each room's dead have ground of
	# their own (the yard's walls, #917), so the walking mesh has no way round outside from one room
	# to another, which a bot would take and stop at the boards.
	var nav := SmallMapNavigation.new(lot as Node3D, SmallMapNavigation.zombie_mesh())
	await nav.settle(tree)
	var spawn_ok := true
	var shortest := INF
	var longest := 0.0
	var notes: Array[String] = []
	for spawn: Node3D in lot.get_node("ZombieSpawns").get_children():
		var id: String = spawn.get_meta(&"barricade_id")
		var socket: Node3D = sockets[id][0]
		var own: String = sockets[id][1]
		var distance := SmallMapNavigation.flat(spawn.global_position, socket.global_position)
		shortest = minf(shortest, distance)
		longest = maxf(longest, distance)
		if not _within(distance, 5, 15) or group_at(spawn.global_position) != "":
			spawn_ok = false
			notes.append("%s at %.1f m" % [id, distance])
		var inside := socket.global_position + socket.global_basis.z * INSIDE
		if not nav.can_reach(spawn.global_position, inside):
			spawn_ok = false
			notes.append("%s never reaches the floor inside its window" % id)
		elif nav.passes_within(spawn.global_position, inside, socket.global_position) > 1.0:
			spawn_ok = false
			notes.append("%s comes in by another window" % id)
		for group: String in GROUPS:
			var reaches := nav.can_reach(spawn.global_position, _middle(lot, group))
			var mine: bool = ROOM_OF[group] == ROOM_OF[own]
			if reaches != mine:
				spawn_ok = false
				notes.append("%s reaches %s: %s" % [id, group, reaches])
			if reaches and group == own:
				# In through one of its own room's windows (a yard can serve all of one room's).
				var by := INF
				for other: String in sockets:
					if ROOM_OF[sockets[other][1]] == ROOM_OF[own]:
						by = minf(
							by,
							nav.passes_within(
								spawn.global_position,
								_middle(lot, group),
								sockets[other][0].global_position
							)
						)
				if by > 1.0:
					spawn_ok = false
					notes.append("%s walks in %.1f m from a window of its room" % [id, by])
	_add(
		18,
		"A window's spawn outside it (in by its own window, its room only)",
		"%.1f to %.1f" % [shortest, longest],
		5,
		15,
		"m",
		spawn_ok,
		", ".join(notes)
	)
	nav.free_map()

	# Row 19: two stairs, one from each ground room, rising 3.3 to 4.0 m.
	var space := (lot as Node3D).get_world_3d().direct_space_state
	var stairs := 0
	var from := {}
	var rises: Array[float] = []
	for door: Node3D in lot.get_node("Doors").get_children():
		var foot := door.get_node_or_null("StandFoot") as Node3D
		if foot == null:
			continue
		stairs += 1
		from[group_at(foot.global_position + Vector3.UP * 0.2)] = true
		var top := _top_of_stair(lot, door)
		rises.append(_ground(space, top) - _ground(space, foot.global_position))
	var rise_ok := rises.all(func(r: float) -> bool: return _within(r, 3.3, 4.0))
	_add(
		19,
		"Stairs, one from each ground room, blocked until bought",
		stairs,
		2,
		2,
		"",
		stairs == 2 and from.has("Start") and from.has("Side") and rise_ok,
		"rises %s m" % [rises]
	)
	world.queue_free()


## The side of `group`'s rectangle nearest `point`: "N", "S", "W" or "E".
func _side_of(group: String, point: Vector3) -> String:
	var rect: Rect2 = _rects[group]
	var gaps := {
		"N": absf(point.z - rect.position.y),
		"S": absf(point.z - rect.end.y),
		"W": absf(point.x - rect.position.x),
		"E": absf(point.x - rect.end.x),
	}
	var best := "N"
	for side: String in gaps:
		if gaps[side] < gaps[best]:
			best = side
	return best


func _top_of_stair(lot: Node, door: Node3D) -> Vector3:
	var slab := (door.get_node("Slab") as Node3D).global_position
	var best := Vector3.ZERO
	var best_distance := INF
	for marker: Node3D in lot.get_node("Measure/Ring").get_children():
		var at := marker.global_position
		if at.y > 1.0 and absf(at.z - slab.z) < 1.5:
			var distance := SmallMapNavigation.flat(at, slab)
			if distance < best_distance:
				best_distance = distance
				best = at
	return best


func _ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 2.0)
	)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


# --- Rows 9 and 10: ceilings and sight lines ---------------------------------------------------


## Whether `node` is a slab of the ceilings or roof, not a stair, lamp or prop hanging under one.
func _is_ceiling(node: Node) -> bool:
	if String(node.name).begins_with("Stair"):
		return false
	var parent := node.get_parent()
	while parent != null:
		if parent.name == &"Ceilings" or parent.name == &"Roof":
			return true
		parent = parent.get_parent()
	return false


func _measure_sight_and_ceilings(lot: Node3D) -> void:
	var space := lot.get_world_3d().direct_space_state
	var points: Array[Vector3] = []
	var heights := {}
	for group: String in GROUPS:
		var rect: Rect2 = _rects[group]
		var floor_y: float = _floors[group]
		var low := INF
		var high := 0.0
		for p in _samples(rect):
			var at := Vector3(p.x, floor_y, p.y)
			var ground := _ground(space, at)
			if is_nan(ground) or absf(ground - floor_y) > 0.1:
				continue
			var up := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(
					Vector3(p.x, ground + 0.1, p.y), Vector3(p.x, ground + 12.0, p.y)
				)
			)
			# A stair overhead, a lamp or a machine's hidden block is no ceiling: the room's ceiling
			# is the slab over its floor (`Ceilings` over the ground floor, `Roof` over the upper).
			if not up.is_empty() and _is_ceiling(up["collider"] as Node):
				var clear: float = (up["position"] as Vector3).y - ground
				low = minf(low, clear)
				high = maxf(high, clear)
			var eye := Vector3(p.x, ground + EYE, p.y)
			if _clear_point(space, eye) and _clear_point(space, Vector3(p.x, ground + 0.5, p.y)):
				points.append(eye)
		heights[group] = [low, high]
	facts["ceilings"] = heights
	var ceiling_ok := true
	var lowest := INF
	var highest := 0.0
	for group: String in heights:
		lowest = minf(lowest, heights[group][0])
		highest = maxf(highest, heights[group][1])
		ceiling_ok = ceiling_ok and _within(heights[group][0], 3.0, 3.6)
		ceiling_ok = ceiling_ok and _within(heights[group][1], 3.0, 3.6)
	_add(
		9,
		"Ceiling, floor to ceiling in every room",
		"%.2f to %.2f" % [lowest, highest],
		3.0,
		3.6,
		"m",
		ceiling_ok,
		str(heights)
	)
	var longest := longest_clear(space, points)
	facts["sight"] = longest
	_add(
		10,
		"Longest sight line indoors at eye height",
		longest["length"],
		16,
		24,
		"m",
		_within(longest["length"], 16, 24),
		"from %s to %s, %d points" % [longest["from"], longest["to"], points.size()]
	)


## Standing points of a room: its edge every 0.5 m and its inside every metre, 0.4 m in.
func _samples(rect: Rect2) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var inner := rect.grow(-0.4)
	var x := inner.position.x
	while x <= inner.end.x + 1e-3:
		found.append(Vector2(x, inner.position.y))
		found.append(Vector2(x, inner.end.y))
		x += 0.5
	var z := inner.position.y + 0.5
	while z < inner.end.y - 1e-3:
		found.append(Vector2(inner.position.x, z))
		found.append(Vector2(inner.end.x, z))
		z += 0.5
	x = inner.position.x + 1.0
	while x < inner.end.x:
		z = inner.position.y + 1.0
		while z < inner.end.y:
			found.append(Vector2(x, z))
			z += 1.0
		x += 1.0
	return found


func _clear_point(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = at
	query.collision_mask = CameraProbe.PLAYER_MASK
	return space.intersect_point(query, 1).is_empty()


## The longest pair of points with nothing between them (walls, frames and the windows' blockers).
func longest_clear(space: PhysicsDirectSpaceState3D, points: Array[Vector3]) -> Dictionary:
	var pairs: Array[Vector3i] = []
	for i in points.size():
		for j in range(i + 1, points.size()):
			pairs.append(Vector3i(i, j, int(points[i].distance_to(points[j]) * 1000.0)))
	pairs.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z > b.z)
	for pair in pairs:
		var ray := PhysicsRayQueryParameters3D.create(points[pair.x], points[pair.y])
		ray.collision_mask = CameraProbe.PLAYER_MASK
		if space.intersect_ray(ray).is_empty():
			return {"length": pair.z / 1000.0, "from": points[pair.x], "to": points[pair.y]}
	return {"length": 0.0, "from": Vector3.ZERO, "to": Vector3.ZERO}


# --- Rows 27 and 28: the camera ------------------------------------------------------------------


func _measure_camera(lot: Node3D) -> void:
	var space := lot.get_world_3d().direct_space_state
	var narrowest := INF
	var widths := {}
	var width_ok := true
	for probe: Node3D in lot.get_node("CameraProbes").get_children():
		var width := passage_width(space, probe)
		widths[String(probe.name)] = snappedf(width, 0.01)
		narrowest = minf(narrowest, width)
		var door := String(probe.name).begins_with("Door") or probe.name == &"Opening"
		if width < (2.0 if door else 1.8) - 0.01:
			width_ok = false
	facts["widths"] = widths
	_add(
		27,
		"Narrowest camera passage (doors 2.0 m)",
		narrowest,
		1.8,
		INF,
		"m",
		width_ok,
		str(widths)
	)
	var failures := {}
	var samples := 0
	var swept := {}
	var squeezes := {}
	for probe: Node3D in lot.get_node("CameraProbes").get_children():
		var result := sweep(space, probe)
		samples += result["samples"]
		swept[String(probe.name)] = result["samples"]
		if result["squeezed"] > 0:
			squeezes[String(probe.name)] = result["squeezed"]
		if not (result["failures"] as Array).is_empty():
			failures[String(probe.name)] = result["failures"]
	facts["swept"] = swept
	facts["squeezed"] = squeezes
	var names := lot.get_node("CameraProbes").get_children().map(
		func(p: Node) -> String: return String(p.name)
	)
	var covered: bool = (
		names.has("Door_Side")
		and names.has("Opening")
		and names.any(func(n: String) -> bool: return n.begins_with("StairA"))
		and names.any(func(n: String) -> bool: return n.begins_with("StairB"))
		and names.any(func(n: String) -> bool: return n.begins_with("Corner"))
	)
	facts["sweep"] = failures
	# Every probe is swept somewhere: a probe whose samples were all skipped proves nothing.
	var empty: bool = swept.values().has(0)
	_add(
		28,
		"Camera probes at every door, stair and corner, the lens never in a wall",
		"%d probes, %d samples" % [names.size(), samples],
		0,
		0,
		"",
		covered and failures.is_empty() and not empty,
		"%s; samples %s" % [failures, swept]
	)


## The clear width across a probe's passage: rays to each side at four heights, the narrowest.
static func passage_width(space: PhysicsDirectSpaceState3D, probe: Node3D) -> float:
	var side := probe.global_basis.x
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			probe.global_position + Vector3.UP * 1.0, probe.global_position + Vector3.DOWN * 1.0
		)
	)
	var feet: Vector3 = probe.global_position if hit.is_empty() else hit["position"]
	var narrowest := INF
	for height: float in [0.3, 1.0, 1.6, 2.2]:
		var at := feet + Vector3.UP * height
		var across := 0.0
		for way: float in [-1.0, 1.0]:
			var ray := PhysicsRayQueryParameters3D.create(at, at + side * way * 6.0)
			ray.collision_mask = CameraProbe.PLAYER_MASK
			var found := space.intersect_ray(ray)
			across += 6.0 if found.is_empty() else at.distance_to(found["position"])
		narrowest = minf(narrowest, across)
	return narrowest


## The shoulder camera swept through a probe's passage, both ways and both shoulders, the player
## at every half metre within 2.5 m of the marker: the samples where the lens ends inside a wall or
## loses sight of the player. A sample where the body itself cannot stand is skipped. Returns
## {failures, samples, squeezed}: `squeezed` counts the level views whose shoulder offset a wall cut
## short (allowed, as on the lot: the camera slides in behind the player).
static func sweep(space: PhysicsDirectSpaceState3D, probe: Node3D) -> Dictionary:
	var failures := []
	var samples := 0
	var squeezed := 0
	var forward := -probe.global_basis.z
	var yaw := probe.global_basis.get_euler().y
	for turn: float in [0.0, PI]:
		for step in range(-5, 6):
			var offset := step * 0.5
			var along := forward * offset * (1.0 if turn == 0.0 else -1.0)
			var top := probe.global_position + along + Vector3.UP * 2.0
			var ground := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 4.0)
			)
			if ground.is_empty():
				continue
			var feet: Vector3 = ground["position"]
			# Lifted over a stair's slope, and a little wider than the body: a sample against a wall
			# is a place nobody stands.
			if not _stands(space, feet):
				continue
			for side: float in [1.0, -1.0]:
				for pitch: float in [0.0, 0.4, -0.4]:
					samples += 1
					var rig := CameraProbe.rig(space, feet, yaw + turn, side, pitch)
					if pitch == 0.0 and rig["shoulder"] < CameraProbe.shoulder_offset() - 0.01:
						squeezed += 1
					if not rig["free"]:
						failures.append(
							(
								"%s%+.1f %s %s"
								% [
									"fwd" if turn == 0.0 else "rev",
									offset,
									"R" if side > 0 else "L",
									"level" if pitch == 0.0 else ("up" if pitch > 0.0 else "down")
								]
							)
						)
	return {"failures": failures, "samples": samples, "squeezed": squeezed}


## True when a body can stand at `feet`: lifted over a stair's slope, and tried a little to each
## side, since a capsule centred on a wall's face is not reported inside the wall's (concave) shape.
static func _stands(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	for nudge: Vector3 in [
		Vector3.ZERO,
		Vector3(0.1, 0, 0),
		Vector3(-0.1, 0, 0),
		Vector3(0, 0, 0.1),
		Vector3(0, 0, -0.1)
	]:
		if not CameraProbe.body_fits(space, feet + nudge + Vector3.UP * 0.25):
			return false
	return true


# --- Row 29: the setting -------------------------------------------------------------------------


func _measure_setting(lot: Node3D) -> void:
	var found: Array[String] = []
	for node in lot.find_children("*", "", true, false):
		var words := setting_words(node)
		for word: String in NOT_OURS:
			if words.contains(word):
				found.append("%s (%s)" % [node.name, word])
	_add(
		29,
		"No names, writing or props from Nacht der Untoten",
		found.size(),
		0,
		0,
		"",
		found.is_empty(),
		", ".join(found)
	)


## The words row 29 reads on a node: its name, unless the engine made it up (`@MeshInstance3D@31945`
## is a counter, and once it reads "1945"), and a label's text.
static func setting_words(node: Node) -> String:
	var named := String(node.name)
	var words := "" if named.begins_with("@") else named.to_lower()
	if node is Label3D:
		words += " " + (node as Label3D).text.to_lower()
	return words
