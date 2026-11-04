class_name ZombieHorde
extends Node3D
## The client's view of the zombies, and in single-player the server beside it. `step` is one
## fixed tick of the server side (director and simulation); `publish` sends the state through the
## wire format (`ZombieCodec`) and updates the views from what comes out, so what is drawn is
## exactly what a remote client would draw.

## Views kept for each look; a view past it is freed.
const PARKED_PER_LOOK := 12
## Looks that keep more: a blast that takes the legs of a crowd turns that many walkers into
## crawlers in one tick, and each needs a crawler's body in that frame (`_redress`), not one made in
## it.
const PARKED_FOR_LOOK := {&"crawler": 20}

## Every zombie wears the body its `look` names (`ZombieModels`), as the snapshot says; setting
## `model_scene` puts every zombie in that one body instead (a test or a capture).
@export var model_scene: PackedScene

var director: ZombieDirector
var throttle: AnimationThrottle
## The map's windows (`NightWorld.gates`): a climbing zombie's clip follows its way over one.
var gates: Array[ZombieGate] = []
## Size in bytes of the last snapshot.
var last_snapshot_bytes: int = 0

var _views: Dictionary[int, ZombieView] = {}
## Views of zombies that left, kept by look for the ones that come (a body is a model, a skeleton
## and an animation tree with its state machine: not made again at every spawn nor freed at every
## kill).
var _parked: Dictionary[StringName, Array] = {}
var _emerge_seconds: float = 0.0
## The bytes the views follow now, and the seconds of the snapshots since that held the same.
var _applied := false
var _applied_bytes := PackedByteArray()
var _unspent := 0.0
## Seconds each look's wind-up lasts, for the looks whose attack is timed to it (the boss's).
var _telegraphs: Dictionary[StringName, float] = {}
## Seconds one board takes each look's type, for the tear clip (`ZombieView.setup`).
var _board_seconds: Dictionary[StringName, float] = {}
## The pace of a look missing from `_board_seconds`: a walker's.
var _default_board_seconds := 1.2


## `p_emerge_seconds` is the one number the client needs from the zombies' tuning: how long a
## zombie takes to rise. The server owns the tuning; the views are told what they need.
func setup(p_director: ZombieDirector, camera: Camera3D, p_emerge_seconds: float) -> void:
	director = p_director
	setup_client(camera, p_emerge_seconds)


## A horde that only draws, with no director: it is fed with `apply_snapshot`. `p_telegraphs` maps
## a look to the seconds its blow takes to land, like the emerge time a number from the rules the
## server owns.
func setup_client(
	camera: Camera3D,
	p_emerge_seconds: float,
	p_telegraphs: Dictionary[StringName, float] = {},
	p_board_seconds: Dictionary[StringName, float] = {},
	default_board_seconds: float = 1.2
) -> void:
	_emerge_seconds = p_emerge_seconds
	_telegraphs = p_telegraphs
	_board_seconds = p_board_seconds
	_default_board_seconds = default_board_seconds
	throttle = AnimationThrottle.new()
	throttle.camera = camera
	add_child(throttle)
	ZombieRig.warm_up()


func _exit_tree() -> void:
	ZombieRig.release()
	if director != null:
		director.close()


func view_count() -> int:
	return _views.size()


## The views of the zombies drawn now.
func views() -> Array[ZombieView]:
	var found: Array[ZombieView] = []
	found.assign(_views.values())
	return found


## The view of a zombie, or null when none is drawn.
func view_of(zombie_id: int) -> ZombieView:
	return _views.get(zombie_id)


## One server tick of the zombies; then the views follow.
func step(delta: float, targets: Dictionary) -> void:
	director.tick(delta, targets)
	publish(delta)


## The server side sends its zombies through the wire format and the client side draws them.
func publish(delta: float) -> void:
	apply_snapshot(ZombieCodec.encode(director.sim.zombies), delta)


## The client side: the views follow one snapshot's bytes and nothing else. `delta` is the time
## since the previous snapshot.
##
## The dead move at the simulation's 30 Hz and a snapshot comes at 60 Hz, so every other one holds
## the bytes of the last: nothing in a view could differ, and the loop over the crowd is not run.
## The time of the skipped snapshots is kept and given to the next one, which walks the views to
## their new place over the ticks since the last (`ZombieView._move_to`). Returns whether the
## crowd was applied (false when the bytes were the last ones).
func apply_snapshot(bytes: PackedByteArray, delta: float) -> bool:
	last_snapshot_bytes = bytes.size()
	if _applied and bytes == _applied_bytes:
		_unspent += delta
		return false
	_applied = true
	_applied_bytes = bytes
	delta += _unspent
	_unspent = 0.0
	var seen: Dictionary[int, bool] = {}
	var began := PerfProbe.begin()
	var entries := ZombieCodec.decode_shared(bytes)
	PerfProbe.end(&"horde.decode", began)
	for entry in entries:
		var zombie_id: int = entry["id"]
		seen[zombie_id] = true
		if not _views.has(zombie_id):
			_add_view(zombie_id, entry["look"])
		var view := _views[zombie_id]
		if view.look != entry["look"]:
			view = _redress(zombie_id, view, entry["look"])
		if not entry["climbing"]:
			view.climb_gate = null
		elif view.climb_gate == null:
			view.climb_gate = _gate_at(entry["position"])
		view.apply(entry, delta)
	for zombie_id in _views.keys():
		if not seen.has(zombie_id):
			_remove_view(zombie_id)
	return true


## The window whose sill lifts a zombie at `point`, or null.
func _gate_at(point: Vector3) -> ZombieGate:
	for gate in gates:
		if gate.climbs(point):
			return gate
	return null


## Makes `counts[look]` bodies of each look ahead of the night and parks them, so its first zombies
## do not each build one in the middle of a frame (`NightWarmup`).
func prewarm(counts: Dictionary) -> void:
	for look: StringName in counts:
		var parked: Array = _parked.get_or_add(look, [])
		while parked.size() < mini(int(counts[look]), parked_limit(look)):
			var view := ZombieView.new()
			add_child(view)
			var telegraph: float = _telegraphs.get(look, ZombieRig.BOSS_HIT_SECONDS)
			var board: float = _board_seconds.get(look, _default_board_seconds)
			view.setup(_scene_for(look), -1, 0.0, _emerge_seconds, look, telegraph, board)
			# One pose, so the tree has resolved its tracks: the first advance of a tree
			# does, and 20 of them in one frame are 2 ms.
			view.advance_animation()
			view.park()
			parked.append(view)


## A zombie tore a board off (the rules' `board_torn`): its tear clip is put on the yank.
func tore(zombie_id: int) -> void:
	var view: ZombieView = _views.get(zombie_id)
	if view != null:
		view.tore()


## How many views of `look` are kept.
func parked_limit(look: StringName) -> int:
	return PARKED_FOR_LOOK.get(look, PARKED_PER_LOOK)


func _scene_for(look: StringName) -> PackedScene:
	return model_scene if model_scene != null else ZombieModels.scene(look)


func _add_view(zombie_id: int, look: StringName) -> void:
	var began := PerfProbe.begin()
	PerfProbe.count(&"view_added")
	_views[zombie_id] = _take_view(zombie_id, look)
	PerfProbe.end(&"horde.add_view", began)


## A view of `look` set going for the zombie `zombie_id`: a parked one when there is one, else made.
## It is in the throttle.
func _take_view(zombie_id: int, look: StringName) -> ZombieView:
	# A parked body has its model already, so the scene is not looked up (`load` of a file already
	# loaded still costs about a millisecond, which is a frame's tenth for each of twenty crawlers).
	var view := _take_parked(look)
	var scene: PackedScene = null
	if view == null:
		view = ZombieView.new()
		add_child(view)
		scene = _scene_for(look)
	# The same id always gives the same phase, so every client agrees without being told.
	var phase := fposmod(float(zombie_id) * 0.618034, 1.0)
	var telegraph: float = _telegraphs.get(look, ZombieRig.BOSS_HIT_SECONDS)
	var board: float = _board_seconds.get(look, _default_board_seconds)
	view.setup(scene, zombie_id, phase, _emerge_seconds, look, telegraph, board)
	throttle.add_view(view)
	return view


## The zombie's look changed (a blast took its legs): it moves to a view of the new look, a parked
## one as a spawn takes (a model is not instanced nor a tree built in the frame of the blast), and
## its old body is parked for the next zombie of that look. The animation time the old view had
## saved up and the outline it wore go with the zombie; the next entry places and poses the new
## view.
func _redress(zombie_id: int, old: ZombieView, look: StringName) -> ZombieView:
	var began := PerfProbe.begin()
	PerfProbe.count(&"view_redressed")
	var view := _take_view(zombie_id, look)
	view.accumulated = old.accumulated
	view.period = old.period
	view.set_outlined(old.is_outlined(), old.outline_style())
	_views[zombie_id] = view
	throttle.remove_view(old)
	_park_or_free(old)
	PerfProbe.end(&"horde.redress", began)
	return view


## A parked view of `look`, or null.
func _take_parked(look: StringName) -> ZombieView:
	var parked: Array = _parked.get(look, [])
	return parked.pop_back() if not parked.is_empty() else null


func _remove_view(zombie_id: int) -> void:
	var began := PerfProbe.begin()
	PerfProbe.count(&"view_removed")
	var view := _views[zombie_id]
	_views.erase(zombie_id)
	throttle.remove_view(view)
	_park_or_free(view)
	PerfProbe.end(&"horde.remove_view", began)


## Keeps a view that left for the next zombie of its look, or frees it when enough are kept.
func _park_or_free(view: ZombieView) -> void:
	var parked: Array = _parked.get_or_add(view.look, [])
	if parked.size() < parked_limit(view.look):
		view.park()
		parked.append(view)
	else:
		view.queue_free()
