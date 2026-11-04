class_name CrowdCensus
extends Node
## A line a second of where the dead stand against the camera and what the renderer says it spent
## (`census=1`): how many are in the view and in which throttle tier, how many animations the
## throttle advanced a frame, and the viewport's measured CPU and GPU render time. Not part of the
## play: `BenchAblation` adds one.

var horde: ZombieHorde
var camera: Camera3D
var _clock := 0.0
var _frames := 0
var _cpu := 0.0
var _gpu := 0.0
var _advanced := 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_advanced += horde.throttle.advanced_last_frame
	_frames += 1
	_clock += delta
	if _clock < 1.0:
		return
	var seen := 0
	var tiers := {}
	var bands := [0, 0, 0, 0]
	for view in horde.views():
		var point := view.global_position + Vector3(0.0, 1.0, 0.0)
		var distance := camera.global_position.distance_to(point)
		var in_view := camera.is_position_in_frustum(point)
		if in_view:
			seen += 1
		tiers[view.period] = int(tiers.get(view.period, 0)) + 1
		bands[0 if distance < 14.0 else (1 if distance < 24.0 else (2 if distance < 40.0 else 3))] += 1
	print(
		(
			"CENSUS views=%d in_view=%d bands(<14,<24,<40,more)=%s periods=%s"
			+ (
				" advanced=%.1f cpu=%.2f gpu=%.2f"
				% [
					horde.view_count(),
					seen,
					bands,
					tiers,
					float(_advanced) / _frames,
					_cpu / _frames,
					_gpu / _frames
				]
			)
		)
	)
	_clock = 0.0
	_frames = 0
	_cpu = 0.0
	_gpu = 0.0
	_advanced = 0


## The band of the metres from the camera: under 14, 24 and 40, and more (the throttle's tiers).
func _band(distance: float) -> int:
	if distance < AnimationThrottle.NEAR:
		return 0
	if distance < AnimationThrottle.MID:
		return 1
	return 2 if distance < AnimationThrottle.DISTANT else 3
