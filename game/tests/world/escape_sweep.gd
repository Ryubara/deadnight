class_name EscapeSweep
extends RefCounted
## Runs the real player body (`PlayerSimulation`, the rules the night ticks) at the props beside a
## map's walls and reports every standing place beyond the map, inside a closed area, or on top of a
## wall (#848). It is `tools/world/map_escape_probe.gd`'s method, trimmed to run in a test:
##
## - The starts are the props near a barrier (a perimeter wall, a closed door's slab, a closed
##   area's wall, all given by the map's test): every top within `BAND` metres of one that the body
##   climbs from the floor (`CameraProbe.BODY_REACH` or less over the floor) is a standing place,
##   and the floor beside a top a little over the reach (`CORNER_REACH`: two such blocks in an L
##   are climbed at their inside corner) is a launch cell. Bare floor is never a start: no wall a
##   player must not cross is within the reach of the floor, so a way out always begins on a prop;
##   a taller prop (a car roof, a dumpster) is reached from a lower one beside it.
## - From each start the body sprints at whatever is solid ahead (a ray at the start's feet and at
##   its knees, every 45 degrees, 22.5 from a prop's top) and jumps at three moments, or walks and
##   jumps. Where it settles off the floor is a new standing place, and it tries again from there,
##   up to `depth` hops, while it is within `BAND` of a barrier.
## - Where it settles is judged by the map's areas (boxes, with the floor's height and whether the
##   area is open with the doors as they are): in no area is beyond the map, in a closed one is
##   inside a closed area, `ON_A_WALL` over the area's floor is on a wall.
##
## A hop's landing depends only on what is near its start, so it is kept in `cache` with the door
## slabs within `SLAB_CLEAR` of its start that are there, and is not run again for another set of
## doors that leaves the same slabs near it.

## A standing place counts within this many metres of a barrier.
const BAND := 6.0
## Metres between the cells a map's tops and floor are read on.
const CELL := 0.5
## A top this high over the floor is a prop's (a step is lower), and this high is a wall's.
const RAISED := 0.3
const ON_A_WALL := 2.0
## Floor cells this near a top over the reach and up to `CORNER_REACH` over the floor are launch
## cells.
const FLOOR_NEAR := 1.5
const CORNER_REACH := 1.5
## Ticks of a hop (running at a thing, jumping), then of settling; the jump moments when sprinting.
const HOP_TICKS := 54
const SETTLE_TICKS := 24
const JUMP_TICKS := [0, 9, 20]
## A hop runs at something solid this far ahead: from the floor, and from a prop's top.
const AHEAD_FROM_FLOOR := 3.0
const AHEAD_FROM_TOP := 6.0
const HEADINGS := 8
## A hop that ends this near where it began learned nothing.
const NO_MOVE := 0.6
## The farthest a hop's body goes from its start (7 m/s for the 54 ticks of the hop, the settle and
## the body's radius, rounded up): a door slab farther away cannot change where it lands.
const SLAB_CLEAR := 7.5
const MASK := PhysicsLayers.WORLD | PhysicsLayers.BOARDS
## The map's solid boxes are kept in squares this many metres wide.
const SOLID_CELL := 4.0

## The hops run (not read from the cache), the starts, and the standing places found.
var hops := 0
var starts := 0
var places := 0

var _root: Node3D
var _space: PhysicsDirectSpaceState3D
var _tuning: PlayerTuning
var _body: CharacterBody3D
## Each {name, boxes: Array[AABB], floor: float, open: bool}; the first area holding a point is its.
var _areas: Array
var _barriers: Array[AABB]
var _slabs: Array[AABB]
var _present: Array[bool]
var _cache: Dictionary
## Vector2i square -> the bounds of the collidable CSG boxes over it.
var _solids := {}


## `areas` and `barriers` are the map's, with the doors as they are in `root`; `slabs` every door
## slab of the map, open or closed, and `present` whether each is still there; `cache` is shared by
## the sweeps of one map's sets of doors.
func _init(
	root: Node3D,
	areas: Array,
	barriers: Array[AABB],
	slabs: Array[AABB],
	present: Array[bool],
	cache: Dictionary
) -> void:
	_root = root
	_areas = areas
	_barriers = barriers
	_slabs = slabs
	_present = present
	_cache = cache
	_tuning = CameraProbe.tuning()
	_space = root.get_world_3d().direct_space_state
	for node in root.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if not box.use_collision:
			continue
		var bounds := bounds_of(box)
		for x in range(
			floori(bounds.position.x / SOLID_CELL), floori(bounds.end.x / SOLID_CELL) + 1
		):
			for z in range(
				floori(bounds.position.z / SOLID_CELL), floori(bounds.end.z / SOLID_CELL) + 1
			):
				var square := Vector2i(x, z)
				if not _solids.has(square):
					_solids[square] = []
				_solids[square].append(bounds)
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _tuning.radius
	capsule.height = _tuning.height
	shape.shape = capsule
	shape.position.y = _tuning.height * 0.5
	_body.add_child(shape)
	_body.collision_layer = PhysicsLayers.BODY
	_body.collision_mask = MASK
	_body.floor_snap_length = 0.3
	root.add_child(_body)


func free_body() -> void:
	_body.free()


## Every violation found, described with the hops that got there (each from where the last landed).
func run(depth: int = 3) -> Array[String]:
	var found: Array[String] = []
	var seen := {}
	var frontier: Array = []
	var tops: Array[Vector3] = []
	var floors: Array[Vector3] = []
	_starts(tops, floors)
	starts = tops.size() + floors.size()
	for top in tops:
		# A top the body climbs from the floor is a standing place of its own.
		_file({"pos": top, "via": []}, seen, found, frontier, depth)
	for cell in floors:
		for hop in _hops_from(cell, HEADINGS, AHEAD_FROM_FLOOR, []):
			_file(hop, seen, found, frontier, depth)
	var level := 0
	while not frontier.is_empty() and level < depth:
		var next: Array = []
		for place: Dictionary in frontier:
			for hop in _hops_from(place["pos"], HEADINGS, AHEAD_FROM_TOP, place["via"]):
				_file(hop, seen, found, next, depth)
		frontier = next
		level += 1
	places = seen.size()
	return found


## The first area one of whose boxes holds `pos`; {} when none.
func area_at(pos: Vector3) -> Dictionary:
	for area: Dictionary in _areas:
		for box: AABB in area["boxes"]:
			if (
				pos.x >= box.position.x
				and pos.x <= box.end.x
				and pos.z >= box.position.z
				and pos.z <= box.end.z
				and pos.y >= box.position.y
				and pos.y <= box.end.y
			):
				return area
	return {}


## What is wrong with a body standing at `pos`: "" when nothing.
func judge(pos: Vector3) -> String:
	var area := area_at(pos)
	if area.is_empty():
		return "beyond the map"
	if not area["open"]:
		return "inside the closed %s" % area["name"]
	if not is_nan(area["floor"]) and pos.y - float(area["floor"]) >= ON_A_WALL:
		return "on a wall in the %s" % area["name"]
	return ""


## The tops a body climbs from the floor and the floor cells beside the taller tops, in the open
## areas within `BAND` of a barrier.
func _starts(tops: Array[Vector3], floors: Array[Vector3]) -> void:
	var tall: Array[Vector3] = []
	var floor_cells: Array[Vector3] = []
	var reach := CameraProbe.BODY_REACH
	for area: Dictionary in _areas:
		if not area["open"] or is_nan(area["floor"]):
			continue
		var floor_y: float = area["floor"]
		for box: AABB in area["boxes"]:
			var x := box.position.x + CELL * 0.5
			while x < box.end.x:
				var z := box.position.z + CELL * 0.5
				while z < box.end.z:
					var cell := Vector3(x, floor_y, z)
					z += CELL
					var holder := area_at(cell + Vector3(0, 0.1, 0))
					if holder.get("name") != area["name"] or not _near_barrier(cell):
						continue
					var hit := _surface(cell)
					if hit == Vector3.INF or not _fits(hit):
						continue
					var rise := hit.y - floor_y
					if rise < RAISED:
						floor_cells.append(hit)
					elif rise <= reach + 0.01:
						tops.append(hit)
					elif rise <= CORNER_REACH:
						tall.append(hit)
				x += CELL
	for cell in floor_cells:
		for top in tall:
			if Vector2(cell.x - top.x, cell.z - top.z).length() <= FLOOR_NEAR:
				floors.append(cell)
				break


func _near_barrier(at: Vector3) -> bool:
	for box in _barriers:
		if _flat_distance(at, box) <= BAND:
			return true
	return false


func _flat_distance(at: Vector3, box: AABB) -> float:
	var dx := maxf(maxf(box.position.x - at.x, at.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - at.z, at.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()


## The first solid surface under a point a little over a wall's height above `cell`'s floor.
func _surface(cell: Vector3) -> Vector3:
	var from := cell + Vector3(0, ON_A_WALL + 0.3, 0)
	var query := PhysicsRayQueryParameters3D.create(from, cell - Vector3(0, 0.4, 0))
	query.collision_mask = MASK
	var hit := _space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## Whether a standing body fits with its feet at `at` (nothing solid in its capsule).
func _fits(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = _tuning.radius
	capsule.height = _tuning.height - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = MASK
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, _tuning.height * 0.5 + 0.05, 0))
	if not _space.intersect_shape(query, 1).is_empty():
		return false
	# A CSG box collides by its faces, one-sided: with its middle inside a thin wall, a capsule (or a
	# ray) meets none of them and the query above passes a cell inside the wall. So the boxes are
	# asked too, by their bounds.
	var key := Vector2i(floori(at.x / SOLID_CELL), floori(at.z / SOLID_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for box: AABB in _solids.get(key + Vector2i(dx, dz), []):
				if box.end.y <= at.y + 0.1 or box.position.y >= at.y + _tuning.height - 0.1:
					continue
				if _flat_distance(at, box) < _tuning.radius - 0.01:
					return false
	return true


## Files where a hop settled: a violation, or a new standing place off the floor to try again from.
func _file(
	hop: Dictionary, seen: Dictionary, found: Array[String], next: Array, depth: int
) -> void:
	var pos: Vector3 = hop["pos"]
	var key := Vector3i(roundi(pos.x / 0.5), roundi(pos.y / 0.25), roundi(pos.z / 0.5))
	if seen.has(key):
		return
	seen[key] = true
	var verdict := judge(pos)
	if verdict != "":
		found.append("%s at %s via %s" % [verdict, _rounded(pos), hop["via"]])
		return
	if hop["via"].size() >= depth or not _near_barrier(pos):
		return
	# A stair (an area with no one floor) is walked onto, not climbed: nothing new to try from.
	var area := area_at(pos)
	if not is_nan(area["floor"]) and pos.y - float(area["floor"]) >= RAISED:
		next.append(hop)


## Where the body settles from `from`, at each heading with something solid ahead: sprinting with
## the jump at each of `JUMP_TICKS`, and walking with the jump at once. Each is {pos, via}.
func _hops_from(from: Vector3, headings: int, ahead: float, via: Array) -> Array:
	var results: Array = []
	# Which slabs near the start are there: the hop's landing is the same for any set of doors that
	# leaves these the same.
	var near := ""
	for i in _slabs.size():
		if _flat_distance(from, _slabs[i]) <= SLAB_CLEAR:
			near += "%d%s" % [i, "+" if _present[i] else "-"]
	for i in headings:
		var angle := TAU * i / headings
		var direction := Vector3(sin(angle), 0, cos(angle))
		if not _solid_ahead(from, direction, ahead):
			continue
		var yaw := atan2(-direction.x, -direction.z)
		var plans: Array = []
		for jump_tick: int in JUMP_TICKS:
			plans.append([true, jump_tick])
		plans.append([false, 0])
		for plan: Array in plans:
			var key := (
				"%.2f,%.2f,%.2f|%d/%d|%s%d|%s"
				% [from.x, from.y, from.z, i, headings, "s" if plan[0] else "w", plan[1], near]
			)
			var landed: Vector3
			if _cache.has(key):
				landed = _cache[key]
			else:
				landed = _run_hop(from, yaw, plan[0], plan[1])
				_cache[key] = landed
			if landed != Vector3.INF:
				var step := [_rounded(from), snappedf(yaw, 0.0001), plan[0], plan[1]]
				results.append({"pos": landed, "via": via + [step]})
	return results


## Something solid within `ahead` metres of `at` along `direction`, at the feet or at the knees.
func _solid_ahead(at: Vector3, direction: Vector3, ahead: float) -> bool:
	for lift in [0.1, 0.55]:
		var start: Vector3 = at + Vector3(0, lift, 0)
		var query := PhysicsRayQueryParameters3D.create(start, start + direction * ahead)
		query.collision_mask = MASK
		if not _space.intersect_ray(query).is_empty():
			return true
	return false


## One hop replayed (a recorded chain): see `_run_hop`.
func hop(from: Vector3, yaw: float, sprint: bool, jump_tick: int) -> Vector3:
	return _run_hop(from, yaw, sprint, jump_tick)


## One run of the real body from feet at `from`: forward at `yaw`, the jump held for three ticks
## from `jump_tick`, then settling. Returns where it ended, or INF when it fell or did not move.
func _run_hop(from: Vector3, yaw: float, sprint: bool, jump_tick: int) -> Vector3:
	hops += 1
	var state := PlayerMotionState.new()
	state.position = from + Vector3(0, 0.02, 0)
	state.on_floor = true
	var command := PlayerCommand.new()
	command.move = Vector2(0, -1)
	command.yaw = yaw
	command.sprint = sprint
	var delta := 1.0 / Engine.physics_ticks_per_second
	for tick in HOP_TICKS:
		command.jump = tick >= jump_tick and tick < jump_tick + 3
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	command.move = Vector2.ZERO
	command.sprint = false
	command.jump = false
	for tick in SETTLE_TICKS:
		PlayerSimulation.simulate(_body, state, command, _tuning, delta)
	if not state.on_floor:
		return Vector3.INF
	if state.position.distance_to(from) < NO_MOVE and absf(state.position.y - from.y) < RAISED:
		return Vector3.INF
	return state.position


static func _rounded(at: Vector3) -> Vector3:
	return Vector3(snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01))


## A box's bounds in the world (CSG boxes are not rotated off the axes on these maps; a turned one
## gets the bounds of its turned corners).
static func bounds_of(box: CSGBox3D) -> AABB:
	return box.global_transform * AABB(-box.size * 0.5, box.size)
