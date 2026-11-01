class_name AnimationThrottle
extends Node
## Animation throttle (the biggest single saving in the crowds spike: -55 % in the browser). Each
## ZombieView's tree runs in manual mode; far zombies, and those outside the camera's view, advance
## it every Nth frame with the time they missed, so the animation speed stays right.

const NEAR := 14.0
const MID := 24.0
const PERIOD_NEAR := 1
const PERIOD_MID := 3
const PERIOD_FAR := 6
const PERIOD_OFFSCREEN := 12
## A zombie's tier is recomputed every Nth frame (staggered by its slot).
const RETIER_EVERY := 8

var camera: Camera3D
## Animation updates done in the last frame, for the stats line.
var advanced_last_frame: int = 0

var _views: Array[ZombieView] = []
var _frame := 0


func add_view(view: ZombieView) -> void:
	_views.append(view)


func remove_view(view: ZombieView) -> void:
	_views.erase(view)


func _process(delta: float) -> void:
	_frame += 1
	advanced_last_frame = 0
	for i in _views.size():
		var view := _views[i]
		if (_frame + i) % RETIER_EVERY == 0:
			view.period = _period_for(view)
		view.accumulated += delta
		if (_frame + i) % view.period == 0:
			view.advance_animation()
			advanced_last_frame += 1


func _period_for(view: ZombieView) -> int:
	if camera == null:
		return PERIOD_NEAR
	var point := view.global_position + Vector3(0.0, 1.0, 0.0)
	if not camera.is_position_in_frustum(point):
		return PERIOD_OFFSCREEN
	var distance := camera.global_position.distance_to(point)
	if distance < NEAR:
		return PERIOD_NEAR
	return PERIOD_MID if distance < MID else PERIOD_FAR
