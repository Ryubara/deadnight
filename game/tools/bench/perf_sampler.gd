class_name PerfSampler
extends Node
## One row a second of what a running night costs and holds, for the performance profile (#906):
## the engine's monitors (frame, process, physics and navigation time, draw calls, objects, nodes,
## orphans, resources, memory, physics bodies), what the night has standing (zombies, lights,
## particles, decals, sounds playing) and what `PerfProbe` timed in the frames of the second (mean
## milliseconds a frame per label). Times that depend on the machine (`frame_ms`, `process_ms`,
## ...) are kept beside counts that do not (`nodes`, `objects`, `bodies`), so a run on a busy
## machine can still be read: the counts are the same on any machine at the same seed.
##
## Not part of the play: `AutopilotRun` adds one for `?sample=1`, and `PerfBudget` reads the rows.

## Seconds of game time a row covers.
const PERIOD := 1.0
## Classes counted in the scene every row (a walk of the tree, once a second).
const LIGHTS := "Light3D"

## The rows so far, each a Dictionary of numbers (see `_row`).
var rows: Array[Dictionary] = []
## Reads the zombies on the lot and the round: `() -> Dictionary` with `alive`, `round`.
var night_state := Callable()
## The milliseconds a fixed piece of GDScript takes on this machine now (`calibrate`): a budget in
## ratios of it holds on a slow runner and a busy machine, which a budget in milliseconds cannot.
var calibration_ms := 0.0

var _window_frames: Array[float] = []
var _window_process := 0.0
var _window_physics := 0.0
var _window_nav := 0.0
var _window_time := 0.0
var _usec: Dictionary = {}
var _counts: Dictionary = {}
var _clock := 0.0
var _started_msec := 0
var _last_usec := 0


func _init() -> void:
	# After every other node's `_process`, so the probes of a frame are whole when they are taken.
	process_priority = 1 << 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	PerfProbe.enabled = true
	PerfProbe.take()


func _exit_tree() -> void:
	PerfProbe.enabled = false


func _ready() -> void:
	calibration_ms = calibrate()


## The least of five runs of a fixed loop of arithmetic, array and dictionary work (what the night's
## scripts do), in milliseconds.
static func calibrate() -> float:
	var best := INF
	for _run in 5:
		var began := Time.get_ticks_usec()
		var table := {}
		var total := 0.0
		for i in 40000:
			table[i % 512] = float(i) * 0.5
			total += sqrt(float(table[(i * 7) % 512] if table.has((i * 7) % 512) else 1.0))
		best = minf(best, float(Time.get_ticks_usec() - began) / 1000.0)
		if total < 0.0:
			break
	return snappedf(best, 0.01)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _started_msec == 0:
		_started_msec = Time.get_ticks_msec()
		_last_usec = now
	# Wall time of the frame, so a run at a fixed frame step (`--fixed-fps`) still reads real cost;
	# the row's length is game time.
	_window_frames.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	_window_time += _window_frames[-1] / 1000.0
	_window_process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_window_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_window_nav += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var taken := PerfProbe.take()
	for label: StringName in taken["usec"]:
		_usec[label] = _usec.get(label, 0) + taken["usec"][label]
	for label: StringName in taken["counts"]:
		_counts[label] = _counts.get(label, 0) + taken["counts"][label]
	_clock += delta
	if _clock >= PERIOD:
		rows.append(_row())
		_reset_window()
		_clock = 0.0


func _reset_window() -> void:
	_window_frames.clear()
	_window_process = 0.0
	_window_physics = 0.0
	_window_nav = 0.0
	_window_time = 0.0
	_usec = {}
	_counts = {}


## The row of the second that just ended.
func _row() -> Dictionary:
	var frames := maxi(_window_frames.size(), 1)
	var sorted := _window_frames.duplicate()
	sorted.sort()
	var state: Dictionary = night_state.call() if night_state.is_valid() else {}
	var tree := get_tree()
	var scene := _scene_counts(tree.root)
	var row := {
		"t": snappedf(float(Time.get_ticks_msec() - _started_msec) / 1000.0, 0.1),
		"round": int(state.get("round", 0)),
		"alive": int(state.get("alive", 0)),
		"cap": int(state.get("cap", 0)),
		"players": int(state.get("players", 0)),
		"count_multiplier": float(state.get("count_multiplier", 0.0)),
		"frames": _window_frames.size(),
		"calibration_ms": calibration_ms,
		"frame_ms": snappedf(_window_time * 1000.0 / frames, 0.01),
		"frame_p95_ms": snappedf(sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], 0.01),
		"frame_max_ms": snappedf(sorted[sorted.size() - 1], 0.01),
		"process_ms": snappedf(_window_process / frames, 0.01),
		"physics_ms": snappedf(_window_physics / frames, 0.01),
		"navigation_ms": snappedf(_window_nav / frames, 0.01),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem_static_mb":
		snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"texture_mb":
		snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mb":
		snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"bodies": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"audio_started": Audio.started,
		"audio_culled": Audio.culled,
	}
	row.merge(scene)
	var labels := {}
	for label: StringName in _usec:
		labels[String(label)] = snappedf(float(_usec[label]) / 1000.0 / frames, 0.001)
	row["labels_ms"] = labels
	var counts := {}
	for label: StringName in _counts:
		counts[String(label)] = _counts[label]
	row["counts"] = counts
	return row


## What the tree holds that costs by its number: lights shining, particles emitting, decals, sounds
## playing, zombie views and skinned meshes. One walk of the tree; skipped nodes are not entered.
func _scene_counts(root: Node) -> Dictionary:
	var counts := {
		"lights": 0,
		"particles": 0,
		"decals": 0,
		"sounds_playing": 0,
		"skeletons": 0,
		"mesh_instances": 0,
		"timers": 0,
		"canvas_items": 0,
	}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Light3D and (node as Light3D).is_visible_in_tree():
			counts["lights"] += 1
		elif node is GPUParticles3D and (node as GPUParticles3D).emitting:
			counts["particles"] += 1
		elif node is CPUParticles3D and (node as CPUParticles3D).emitting:
			counts["particles"] += 1
		elif node is Decal:
			counts["decals"] += 1
		elif node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
			counts["sounds_playing"] += 1
		elif node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
			counts["sounds_playing"] += 1
		elif node is Skeleton3D:
			counts["skeletons"] += 1
		elif node is MeshInstance3D:
			counts["mesh_instances"] += 1
		elif node is Timer:
			counts["timers"] += 1
		elif node is CanvasItem:
			counts["canvas_items"] += 1
		stack.append_array(node.get_children())
	return counts
