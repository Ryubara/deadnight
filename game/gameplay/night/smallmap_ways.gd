class_name SmallMapWays
extends RefCounted
## How a sound outside the second map's walls reaches a listener inside them. The walls are thick
## and the windows are the only gaps: a listener in a room hears the yard from the room's windows,
## from the direction of the window, as loud as the sound would be after the way round (the
## distance listener to window and window to source) and the window's own cost (boarded or open).
## With no window of the room in line of sight of both, it comes through the wall: from where it is,
## much quieter and duller. Outside the building nothing stands in the way.
##
## The windows are read from the greybox (`Windows/Window_<id>`: the `room` and `kind` metadata, the
## foot of the opening, +Z into the room, a `Blocker` body in the opening that only players feel).

## The physics layers the walls, jambs and floors are on (the window blockers are on layer 2 alone
## and are let through: a window is a gap for sound).
const WALL_MASK := 3
## The most things outside the walls (fences, the ground) a ray goes through before it is a wall.
const MAX_SKIPS := 12


## What `route` finds.
class Way:
	extends RefCounted
	## Where the sound is played from: the window it comes in at, or its own place.
	var at := Vector3.ZERO
	## What to add to the sound's own level: the way round and the window or wall.
	var extra_db := 0.0
	var cutoff_hz := 6000.0
	## `outside`, `open`, `boarded` or `wall`.
	var kind := &"outside"
	## The id of the window it comes in at, `&""` for none.
	var window := &""


## `Callable(from: Vector3, to: Vector3) -> bool`: true when a wall stands between. The physics
## space of the greybox unless a test says.
var wall_between := Callable()

var _rooms: SmallMapRooms
var _t: SmallMapSoundTuning
var _greybox: Node3D
## The greybox's `Outside` group: the yards, the fence, the bank, the breach's pocket.
var _outside: Node
var _windows: Array[Dictionary] = []
var _blockers: Array[RID] = []
var _boards: Dictionary[StringName, int] = {}
## `bool` for each (window, source) pair: a window's outside is clear to a source. Both are fixed.
var _outer_clear: Dictionary[String, bool] = {}


func _init(greybox: Node3D, rooms: SmallMapRooms, tuning: SmallMapSoundTuning) -> void:
	_greybox = greybox
	_outside = greybox.get_node_or_null("Outside")
	_rooms = rooms
	_t = tuning
	var windows := greybox.get_node_or_null("Windows")
	if windows == null:
		return
	for window in windows.get_children():
		var node := window as Node3D
		if node == null or not node.has_meta(&"barricade_id"):
			continue
		var id := StringName(node.get_meta(&"barricade_id"))
		var blocker := node.get_node_or_null("Blocker") as CollisionObject3D
		if blocker != null:
			_blockers.append(blocker.get_rid())
		(
			_windows
			. append(
				{
					"id": id,
					"room": StringName(node.get_meta(&"room", "")),
					"breach": node.get_meta(&"kind", "window") == "breach",
					"floor": node.global_position.y,
					"point": node.global_position + Vector3(0.0, _t.window_lift, 0.0),
					"outward": -node.global_transform.basis.z,
				}
			)
		)
		_boards[id] = _t.boards_full


## The boards left on a window (`board_torn` and `board_repaired` say).
func set_boards(window_id: StringName, boards: int) -> void:
	if _boards.has(window_id):
		_boards[window_id] = boards


func window_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for window in _windows:
		ids.append(window["id"])
	return ids


## The middle of a window's opening in the world, null for an unknown window.
func window_point(window_id: StringName) -> Variant:
	for window in _windows:
		if window["id"] == window_id:
			return window["point"]
	return null


## `open` for a window with no boards (or a breach), `boarded` otherwise.
func state_of(window_id: StringName) -> StringName:
	for window in _windows:
		if window["id"] == window_id:
			return &"open" if window["breach"] or _boards[window_id] <= 0 else &"boarded"
	return &"wall"


## The way a sound at `source` (with the fall-off distance `unit_size`) reaches `from`.
func route(from: Vector3, source: Vector3, unit_size: float) -> Way:
	var way := Way.new()
	way.at = source
	way.cutoff_hz = _t.open_cutoff_hz
	var room := _rooms.room_at(from)
	if room == &"":
		return way
	var kind := _rooms.kind_of(room)
	var floor_y := _rooms.floor_of(room)
	var best := -INF
	for window in _windows:
		if window["room"] != kind or absf(window["floor"] - floor_y) > 0.5:
			continue
		var point: Vector3 = window["point"]
		var near := from.distance_to(point)
		var inner := point + (from - point).normalized() * minf(_t.window_inset, near * 0.5)
		if _blocked(from, inner) or not _outside_clear(window, source):
			continue
		var total := near + point.distance_to(source)
		# What the player's own fall-off at the window (`near` away) does not already give.
		var level := 20.0 * log((unit_size + near) / (unit_size + total)) / log(10.0)
		level += _window_db(window["id"])
		# The window that lets the most through is the one with the shortest way round and the
		# kindest state: the loudness of the whole way (not only what is left to add).
		var heard := level - 20.0 * log((unit_size + near) / unit_size) / log(10.0)
		if heard > best:
			best = heard
			way.at = inner
			way.extra_db = level
			way.window = window["id"]
			way.kind = state_of(window["id"])
	if way.window == &"":
		way.kind = &"wall"
		way.extra_db = _t.wall_db
	way.cutoff_hz = _cutoff(way.kind)
	return way


func _window_db(window_id: StringName) -> float:
	return _t.open_db if state_of(window_id) == &"open" else _t.boarded_db


func _cutoff(kind: StringName) -> float:
	match kind:
		&"open":
			return _t.open_cutoff_hz
		&"boarded":
			return _t.boarded_cutoff_hz
		_:
			return _t.wall_cutoff_hz


## True when the way from just outside the window to the source is clear of walls (a corner of the
## building, the fence). Fixed, so asked once.
func _outside_clear(window: Dictionary, source: Vector3) -> bool:
	var key := "%s|%s" % [window["id"], source]
	if not _outer_clear.has(key):
		var outer: Vector3 = window["point"] + window["outward"] * _t.window_inset
		_outer_clear[key] = not _blocked(outer, source)
	return _outer_clear[key]


func _blocked(from: Vector3, to: Vector3) -> bool:
	if wall_between.is_valid():
		return wall_between.call(from, to)
	if _greybox == null or not _greybox.is_inside_tree():
		return false
	var space := _greybox.get_world_3d().direct_space_state
	var skipped := _blockers.duplicate()
	# A fence or the ground outside is no wall to sound: ask again past it.
	for _i in MAX_SKIPS:
		var query := PhysicsRayQueryParameters3D.create(from, to, WALL_MASK)
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		if not (_outside != null and _outside.is_ancestor_of(hit["collider"] as Node)):
			return true
		skipped.append(hit["rid"])
	return true
