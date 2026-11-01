class_name ZombieHorde
extends Node3D
## The client's view of the zombies, and in single-player the server beside it. `step` is one
## fixed tick of the server side (director and simulation); `publish` sends the state through the
## wire format (`ZombieCodec`) and updates the views from what comes out, so what is drawn is
## exactly what a remote client would draw.

@export var model_scene: PackedScene

var director: ZombieDirector
var throttle: AnimationThrottle
## Size in bytes of the last snapshot.
var last_snapshot_bytes: int = 0

var _views: Dictionary[int, ZombieView] = {}


func setup(p_director: ZombieDirector, camera: Camera3D) -> void:
	director = p_director
	throttle = AnimationThrottle.new()
	throttle.camera = camera
	add_child(throttle)


func _exit_tree() -> void:
	ZombieRig.release()
	if director != null:
		director.close()


func view_count() -> int:
	return _views.size()


## One server tick of the zombies; then the views follow.
func step(delta: float, targets: Dictionary) -> void:
	director.tick(delta, targets)
	publish(delta)


func publish(delta: float) -> void:
	var bytes := ZombieCodec.encode(director.sim.zombies)
	last_snapshot_bytes = bytes.size()
	var seen: Dictionary[int, bool] = {}
	for entry in ZombieCodec.decode(bytes):
		var zombie_id: int = entry["id"]
		seen[zombie_id] = true
		if not _views.has(zombie_id):
			_add_view(zombie_id)
		_views[zombie_id].apply(entry, delta)
	for zombie_id in _views.keys():
		if not seen.has(zombie_id):
			_remove_view(zombie_id)


func _add_view(zombie_id: int) -> void:
	var view := ZombieView.new()
	add_child(view)
	# The same id always gives the same phase, so every client agrees without being told.
	var phase := fposmod(float(zombie_id) * 0.618034, 1.0)
	view.setup(model_scene, zombie_id, phase, director.sim.tuning.emerge_seconds)
	_views[zombie_id] = view
	throttle.add_view(view)


func _remove_view(zombie_id: int) -> void:
	var view := _views[zombie_id]
	_views.erase(zombie_id)
	throttle.remove_view(view)
	view.queue_free()
