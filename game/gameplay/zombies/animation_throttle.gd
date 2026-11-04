class_name AnimationThrottle
extends Node
## Animation throttle (the biggest single saving in the crowds spike: -55 % in the browser). Each
## ZombieView's tree runs in manual mode; far zombies advance it every Nth frame with the time they
## missed, so the animation speed stays right, and a zombie nobody can see is not advanced at all
## (`PERIOD_UNSEEN`) until it is back in view. An advance costs about 0.25 ms on a desktop (the
## tree's blend and the 50 bones' skin), so at the desktop's ceiling, where most of the 99 dead
## stand away from the player's camera, the dead that are out of view are most of the advances
## (Deadnight #949, `docs/research/crowd-engine-cost.md`).

const NEAR := 14.0
const MID := 24.0
## Past this many metres a zombie in view is a few dozen pixels tall, drawn as its far mesh.
const DISTANT := 40.0
const PERIOD_NEAR := 1
const PERIOD_MID := 3
const PERIOD_FAR := 6
const PERIOD_DISTANT := 12
## Out of the view (no point of its body is in the frustum): not advanced.
const PERIOD_UNSEEN := 0
## A zombie's tier is recomputed every Nth frame (staggered by its slot); one that is not advanced
## is looked at more often, so it has its pose back soon after it comes into view.
const RETIER_EVERY := 8
const RETIER_UNSEEN_EVERY := 4
## The most animation time a zombie spends at once when it comes back: a swing that began out of
## view still plays from its start, and a gait is a loop, so what is skipped is not seen.
const MAX_CATCH_UP := 0.25
## Heights above the zombie's feet at which it counts as in view (feet, chest, head with its reach).
const SEEN_HEIGHTS: Array[float] = [0.2, 1.0, 2.2]

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
	var began := PerfProbe.begin()
	_frame += 1
	advanced_last_frame = 0
	for i in _views.size():
		var view := _views[i]
		var slot := _frame + i
		var unseen := view.period == PERIOD_UNSEEN
		if not unseen:
			view.accumulated += delta
		elif view.accumulated < MAX_CATCH_UP:
			# Waiting out of view: time is kept up to a short catch-up (a starting phase, larger
			# than that, is kept as it is).
			view.accumulated = minf(view.accumulated + delta, MAX_CATCH_UP)
		var woke := false
		if slot % (RETIER_UNSEEN_EVERY if unseen else RETIER_EVERY) == 0:
			view.period = _period_for(view)
			woke = unseen and view.period != PERIOD_UNSEEN
		if view.period != PERIOD_UNSEEN and (woke or slot % view.period == 0):
			view.advance_animation()
			advanced_last_frame += 1
	PerfProbe.end(&"view.animation", began)


func _period_for(view: ZombieView) -> int:
	if camera == null:
		return PERIOD_NEAR
	var feet := view.global_position
	if not _seen(feet):
		return PERIOD_UNSEEN
	var distance := camera.global_position.distance_to(feet + Vector3(0.0, 1.0, 0.0))
	if distance < NEAR:
		return PERIOD_NEAR
	if distance < MID:
		return PERIOD_MID
	return PERIOD_FAR if distance < DISTANT else PERIOD_DISTANT


## Whether any of the heights above `feet` is in the camera's view.
func _seen(feet: Vector3) -> bool:
	for height in SEEN_HEIGHTS:
		if camera.is_position_in_frustum(feet + Vector3(0.0, height, 0.0)):
			return true
	return false
