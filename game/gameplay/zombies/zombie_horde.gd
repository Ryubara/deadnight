class_name ZombieHorde
extends Node3D
## The client's view of the zombies, and in single-player the server beside it. `step` is one
## fixed tick of the server side (director and simulation); `publish` sends the state through the
## wire format (`ZombieCodec`) and updates the views from what comes out, so what is drawn is
## exactly what a remote client would draw.

## Every zombie wears the body its `look` names (`ZombieModels`), as the snapshot says; setting
## `model_scene` puts every zombie in that one body instead (a test or a capture).
@export var model_scene: PackedScene

var director: ZombieDirector
var throttle: AnimationThrottle
## Size in bytes of the last snapshot.
var last_snapshot_bytes: int = 0

var _views: Dictionary[int, ZombieView] = {}
var _emerge_seconds: float = 0.0


## `p_emerge_seconds` is the one number the client needs from the zombies' tuning: how long a
## zombie takes to rise. The server owns the tuning; the views are told what they need.
func setup(p_director: ZombieDirector, camera: Camera3D, p_emerge_seconds: float) -> void:
	director = p_director
	setup_client(camera, p_emerge_seconds)


## A horde that only draws, with no director: it is fed with `apply_snapshot`.
func setup_client(camera: Camera3D, p_emerge_seconds: float) -> void:
	_emerge_seconds = p_emerge_seconds
	throttle = AnimationThrottle.new()
	throttle.camera = camera
	add_child(throttle)


func _exit_tree() -> void:
	ZombieRig.release()
	if director != null:
		director.close()


func view_count() -> int:
	return _views.size()


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
func apply_snapshot(bytes: PackedByteArray, delta: float) -> void:
	last_snapshot_bytes = bytes.size()
	var seen: Dictionary[int, bool] = {}
	for entry in ZombieCodec.decode(bytes):
		var zombie_id: int = entry["id"]
		seen[zombie_id] = true
		if not _views.has(zombie_id):
			_add_view(zombie_id, entry["look"])
		var view := _views[zombie_id]
		if view.look != entry["look"]:
			view.dress(_scene_for(entry["look"]), entry["look"])
		view.apply(entry, delta)
	for zombie_id in _views.keys():
		if not seen.has(zombie_id):
			_remove_view(zombie_id)


func _scene_for(look: StringName) -> PackedScene:
	return model_scene if model_scene != null else ZombieModels.scene(look)


func _add_view(zombie_id: int, look: StringName) -> void:
	var view := ZombieView.new()
	add_child(view)
	# The same id always gives the same phase, so every client agrees without being told.
	var phase := fposmod(float(zombie_id) * 0.618034, 1.0)
	view.setup(_scene_for(look), zombie_id, phase, _emerge_seconds, look)
	_views[zombie_id] = view
	throttle.add_view(view)


func _remove_view(zombie_id: int) -> void:
	var view := _views[zombie_id]
	_views.erase(zombie_id)
	throttle.remove_view(view)
	view.queue_free()
