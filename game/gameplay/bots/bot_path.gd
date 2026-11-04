class_name BotPath
extends RefCounted
## A bot's way over the navigation mesh: one cached path, followed with a look-ahead point, asked
## for again only when it has to be and never more than `QUERY_BUDGET` times a second.
##
## - A goal is snapped to the mesh first (`map_get_closest_point`); a goal the mesh does not reach
##   (too far from it, or a path that ends short of it) is *unreachable* for `UNREACHABLE_SECONDS`
##   and the bot is told so, to take another errand, instead of asking again.
## - A door bought changes the mesh: the cached path is dropped and no question is asked until the
##   map has taken the new mesh in (its iteration id moved) or `DOOR_HOLD_MAX` seconds are over.
##   A question before the map's first synchronisation prints an error, so none is asked then.
## - The look-ahead is the first path point farther than `LOOK_AHEAD` metres: the path's end is
##   never read past (Godot's navigation guide warns against that).
##
## With no map (a rig, a test) the way is the straight line to the goal. Time is the clock the
## caller gives (`now`, seconds on the bot's own clock), never the engine's.

enum Status { NONE, OK, WAITING, HOLD, UNREACHABLE, NO_GOAL }

## Path queries a second at the most, per bot.
const QUERY_BUDGET := 3.0
## Metres past which a path point counts as the one to walk to.
const LOOK_AHEAD := 0.8
## Metres short of a look-ahead point at which a wall still lets the bot walk to it.
const OPEN_SLACK := 0.35
## Metres a path point may lie off the straight line to the look-ahead point and still be skipped.
const CORNER := 0.15
## Metres the bot may be off its path before a new one is asked for, and the goal may move.
const OFF_PATH := 1.5
const GOAL_MOVED := 1.5
## Metres a path may end short of its goal and still reach it.
const REACHED_SHORT := 2.5
## Metres a goal may lie off the mesh and still be snapped onto it.
const SNAP_LIMIT := 3.0
## Metres above a path point at which the way is tested for what a body cannot walk through (low
## enough for the lowest board of a barricade); the metres of path past such a thing, at the most,
## that are cut off (the bot stops short of it: the posts and boards at the mesh's edge) before the
## goal counts as unreachable; and the metres short of it the bot stops (its body's radius).
const WALK_HEIGHT := 0.15
const WALLED_SLACK := 1.0
const BODY_STANDOFF := 0.45
## Seconds a goal the mesh does not reach is not tried again.
const UNREACHABLE_SECONDS := 5.0
## Seconds, at the least and at the most, the bot waits after a door for the map to take the mesh
## in.
const DOOR_HOLD_MIN := 0.2
const DOOR_HOLD_MAX := 3.0
## Seconds after which a path is asked for again whatever happened.
const MAX_AGE := 8.0

var map: RID
## The path in force (empty for none) and the goal it was made for.
var points := PackedVector3Array()
var goal := Vector3.INF
## How far along `points` the bot has got (the index of the next point to reach).
var index := 0
## Questions put to the navigation server: paths, and the cheaper snaps of a goal onto the mesh.
var queries := 0
var snaps := 0
## Paths that came back empty for a goal on the mesh (a fault, or a map not yet in step).
var empty_answers := 0
## Goals marked unreachable, and doors that dropped the cache.
var unreachable_marks := 0
var door_drops := 0
## Goals marked unreachable because a body cannot walk the path (the mesh runs through a barricade's
## boards into the pocket the dead break in from).
var walled_marks := 0
## Paths made so far: a new one is a new number, so a caller can tell a path from the one before.
var generation := 0
## What the last `ask` came to.
var last_status := Status.NONE

var _level: BotLevel
var _last_query := -INF
var _made_at := -INF
var _blocked: Dictionary = {}
var _doors := -1
var _hold_since := -INF
var _hold_iteration := 0


func _init(p_map: RID = RID(), p_level: BotLevel = null) -> void:
	map = p_map
	_level = p_level


func has_map() -> bool:
	return map.is_valid()


## Puts the cache away: the next ask makes a new path.
func forget() -> void:
	points = PackedVector3Array()
	index = 0
	goal = Vector3.INF


## The number of doors open, from the frame. A change drops the cache and holds the questions until
## the map has the new mesh.
func note_doors(count: int, now: float) -> void:
	if _doors >= 0 and count != _doors:
		forget()
		_blocked.clear()
		door_drops += 1
		_hold_since = now
		_hold_iteration = _iteration()
	_doors = count


## Whether the questions are held for a door's new mesh at `now`.
func holding(now: float) -> bool:
	if _hold_since == -INF:
		return false
	var waited := now - _hold_since
	if waited >= DOOR_HOLD_MAX:
		_hold_since = -INF
		return false
	if waited >= DOOR_HOLD_MIN and (not has_map() or _iteration() != _hold_iteration):
		_hold_since = -INF
		return false
	return true


## Marks `at` unreachable (or just not worth trying) until `now + seconds`.
func block(at: Vector3, now: float, seconds: float = UNREACHABLE_SECONDS) -> void:
	_blocked[_key(at)] = now + seconds
	unreachable_marks += 1


func is_blocked(at: Vector3, now: float) -> bool:
	var key := _key(at)
	if not _blocked.has(key):
		return false
	if _blocked[key] <= now:
		_blocked.erase(key)
		return false
	return true


## Gets the cache ready for walking from `here` to `to`: asks for a path when there is none, the
## goal moved, the bot left it or it is old, within the budget (and not when `may_query` is off: the
## tick is a busy one). Returns what the caller should do.
func ask(
	here: Vector3, to: Vector3, now: float, force: bool = false, may_query: bool = true
) -> Status:
	last_status = _ask(here, to, now, force, may_query)
	return last_status


func _ask(here: Vector3, to: Vector3, now: float, force: bool, may_query: bool) -> Status:
	var gate := _gate(here, to, now)
	if gate != Status.NONE:
		return gate
	var fresh := not points.is_empty() and goal.distance_to(to) <= GOAL_MOVED
	fresh = fresh and now - _made_at < MAX_AGE and _off_path(here) <= OFF_PATH
	if fresh and not force:
		return Status.OK
	if not may_query or (not force and now - _last_query < 1.0 / QUERY_BUDGET):
		return Status.WAITING if points.is_empty() else Status.OK
	return _query(here, to, now)


## What stops a question before it starts: no goal, a goal marked unreachable, a door's new mesh
## on its way, a map that has not taken its first mesh in (a question then prints an error). With
## no map at all the way is the straight line. `NONE` when nothing does.
func _gate(here: Vector3, to: Vector3, now: float) -> Status:
	if to == Vector3.INF:
		return Status.NO_GOAL
	if is_blocked(to, now):
		return Status.UNREACHABLE
	if holding(now) or (has_map() and _iteration() < 1):
		return Status.HOLD
	if not has_map():
		points = PackedVector3Array([here, to])
		goal = to
		index = 1
		return Status.OK
	return Status.NONE


## The flat unit direction to walk, or zero at the end of the path. The point aimed at is the first
## one more than `LOOK_AHEAD` away, but never past a corner: a point the path bends round, more than
## `CORNER` metres off the straight line to that point, is walked to first (cutting it drags the
## body across the wall's corner).
func direction(here: Vector3) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	_advance(here)
	var last := points.size() - 1
	var chosen := last
	for i in range(index, points.size()):
		if _flat(here, points[i]) > LOOK_AHEAD:
			chosen = i
			break
	for j in range(index, chosen):
		if _distance_to_segment(points[j], here, points[chosen]) > CORNER:
			chosen = j
			break
	# And never straight at a point something solid stands in front of (a bot knocked off its path
	# by another player would walk into the car's side): the one before it, and so on back.
	while chosen > index and not _open_to(here, points[chosen]):
		chosen -= 1
	var flat := points[chosen] - here
	flat.y = 0.0
	return flat.normalized() if flat.length() > 0.01 else Vector3.ZERO


## Whether nothing solid (at knee height) stands between `here` and `to`.
func _open_to(here: Vector3, to: Vector3) -> bool:
	if _level == null:
		return true
	var flat := Vector3(to.x - here.x, 0.0, to.z - here.z)
	var length := flat.length()
	if length < 0.01:
		return true
	return _level.room(here, flat / length, length) >= length - OPEN_SLACK


## Metres of path left from `here` to its end.
func remaining(here: Vector3) -> float:
	if points.is_empty():
		return 0.0
	_advance(here)
	var left := _flat(here, points[mini(index, points.size() - 1)])
	for i in range(index, points.size() - 1):
		left += _flat(points[i], points[i + 1])
	return left


## Whether the bot is within `radius` of the end of its path.
func arrived(here: Vector3, radius: float) -> bool:
	return not points.is_empty() and _flat(here, points[points.size() - 1]) <= radius


## The goal snapped onto the mesh, or `Vector3.INF` when the mesh does not come within
## `SNAP_LIMIT` of it. Counts as a snap, not a path query.
func snap(at: Vector3) -> Vector3:
	if not has_map() or _iteration() < 1:
		return at
	snaps += 1
	var on_mesh := NavigationServer3D.map_get_closest_point(map, at)
	return on_mesh if _flat(on_mesh, at) <= SNAP_LIMIT else Vector3.INF


func _query(here: Vector3, to: Vector3, now: float) -> Status:
	var target := snap(to)
	if target == Vector3.INF:
		block(to, now)
		forget()
		return Status.UNREACHABLE
	_last_query = now
	_made_at = now
	queries += 1
	var start := NavigationServer3D.map_get_closest_point(map, here)
	var found := NavigationServer3D.map_get_path(map, start, target, true, NavLayers.WALK)
	if found.is_empty():
		empty_answers += 1
		block(to, now)
		forget()
		return Status.UNREACHABLE
	found = walkable(found)
	if found.is_empty():
		walled_marks += 1
		block(to, now)
		forget()
		return Status.UNREACHABLE
	if _flat(found[found.size() - 1], target) > REACHED_SHORT:
		block(to, now)
		forget()
		return Status.UNREACHABLE
	points = found
	goal = to
	index = 0
	generation += 1
	return Status.OK


## The path as a body can walk it. The mesh runs through what a body is stopped by (the boards
## across a breach, the fence's posts at its edge). A path stopped by something with more than
## `WALLED_SLACK` metres of it left is empty: the goal is unreachable, and the bot does not walk to
## it and wedge against it. One stopped with less left is cut short `BODY_STANDOFF` metres before
## the thing, the nearest point the bot can reach. A level without the check passes the path as it
## is.
func walkable(found: PackedVector3Array) -> PackedVector3Array:
	if _level == null or not _level.walk.is_valid() or found.size() < 2:
		return found
	var low := Vector3(0.0, WALK_HEIGHT, 0.0)
	for i in found.size() - 1:
		var hit := _level.walk_hit(found[i] + low, found[i + 1] + low)
		if hit < 0.0:
			continue
		var length := found[i].distance_to(found[i + 1])
		var beyond := length - hit
		for k in range(i + 1, found.size() - 1):
			beyond += found[k].distance_to(found[k + 1])
		if beyond > WALLED_SLACK:
			return PackedVector3Array()
		var cut := found.slice(0, i + 1)
		var stop := maxf(hit - BODY_STANDOFF, 0.0)
		cut.append(found[i].lerp(found[i + 1], stop / maxf(length, 0.0001)))
		return cut
	return found


## Moves `index` past the points the bot has reached or run past (a corner cut at speed is passed
## without ever being within reach of its point: the bot is nearer the next point than this one is).
func _advance(here: Vector3) -> void:
	while index < points.size() - 1:
		var reached := _flat(here, points[index]) <= LOOK_AHEAD * 0.5
		var passed := _flat(here, points[index + 1]) < _flat(points[index], points[index + 1])
		if not reached and not passed:
			break
		index += 1


## Metres from `here` to the nearest stretch of the path from the point before `index` on.
func _off_path(here: Vector3) -> float:
	if points.size() < 2:
		return 0.0 if points.size() == 1 and _flat(here, points[0]) < OFF_PATH else INF
	var best := INF
	for i in range(maxi(index - 1, 0), points.size() - 1):
		best = minf(best, _distance_to_segment(here, points[i], points[i + 1]))
		# The path leaves a bot behind as it goes: only the next few stretches can be near.
		if i > index + 3:
			break
	return best


## Whether a walk from `here` to `to` ends within `short` (`REACHED_SHORT` by default) of it on the
## mesh as it is now. A question the mesh cannot answer yet (none, or a door's new mesh on its way)
## is taken as yes. Counts as a path query. The errands use it to tell a stand behind a shut door
## from one a bot can walk to; the flank passes a smaller `short`, for a place that must be on the
## ground it can walk and not a few metres past the edge of it.
func probe(here: Vector3, to: Vector3, now: float, short := REACHED_SHORT) -> bool:
	if not has_map() or _iteration() < 1 or holding(now):
		return true
	var target := snap(to)
	if target == Vector3.INF:
		return false
	queries += 1
	var start := NavigationServer3D.map_get_closest_point(map, here)
	var found := walkable(NavigationServer3D.map_get_path(map, start, target, true, NavLayers.WALK))
	return not found.is_empty() and _flat(found[found.size() - 1], target) <= short


## The metres of walk from `here` to `to` on the mesh as it is now, or `INF` when it does not get
## there (as `probe` judges it). With no map, or a mesh on its way, the straight line. Counts as a
## path query: the errands ask once for a few stands and keep the answer for a while.
func walk_length(here: Vector3, to: Vector3, now: float) -> float:
	if not has_map() or _iteration() < 1 or holding(now):
		return _flat(here, to)
	var target := snap(to)
	if target == Vector3.INF:
		return INF
	queries += 1
	var start := NavigationServer3D.map_get_closest_point(map, here)
	var found := NavigationServer3D.map_get_path(map, start, target, true, NavLayers.WALK)
	if found.is_empty() or _flat(found[found.size() - 1], target) > REACHED_SHORT:
		return INF
	var length := 0.0
	for i in range(found.size() - 1):
		length += found[i].distance_to(found[i + 1])
	return length


## The navigation map's iteration (it counts each new mesh).
func iteration() -> int:
	return _iteration()


func _iteration() -> int:
	return NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0


static func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var along := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * along).length()


static func _key(at: Vector3) -> Vector2i:
	return Vector2i(roundi(at.x / 2.0), roundi(at.z / 2.0))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
