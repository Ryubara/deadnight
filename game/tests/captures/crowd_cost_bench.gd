extends "res://tests/captures/zombie_chase.gd"
## What a crowd costs, system by system (issue #105). The zombie chase (a crowd of N running the
## lot, the shipped code, no HUD) with a clock round each stage of a frame: the director's tick (the
## zombies' brains and bodies), the navigation paths inside it, the wire format's encode, decode and
## the views' update, the animation throttle (the trees' poses), the bench's own scenery (the rules'
## tick and the shots), and the rest of the frame (the drawing and the engine). Not part of the
## game. In a browser `tools/web_smoke/crowd_cost.py` exports a copy of the project that starts on
## this scene, reads `window.__bench` and prints the numbers; the page's query takes the same
## arguments as the command line (`?zombies=40&ablate=draw`). Arguments after `--`: `--outline=N`
## (the N zombies nearest the camera wear the outline through walls, `Outline`), `--zombies=N` (the
## cap), `--frames=N` (measured, default 400), `--warmup=SECONDS` (simulated before the first
## frame), `--ablate=draw|animation|navigation|views` (leave one system out to read what it cost
## from the frame: `draw` hides the views, `animation` stops the throttle, `navigation` walks in
## straight lines, `views` stops updating them), `--unpaced` (a desktop run: no vertical sync and no
## frame limit, so a frame's time is its work, not the display's refresh).

## Frames let go by before the first one counts: the shaders and the crowd settle.
const SETTLE_FRAMES := 240
## The page's query is read as the arguments of the command line.
const QUERY := "location.search.replace(/^\\?/, '')"

var _timed: TimedPathing
var _ablate := ""
var _outline := 0
var _marked_any := false
var _ticks: Array[float] = []
var _frame_rows: Array[Dictionary] = []
var _stage := {}
var _frame_seen := 0
var _last_frame_usec := 0
var _reported := false


## Paths through the navigation map, with the time they took.
class TimedPathing:
	extends NavmeshPathing

	var usec := 0
	var calls := 0

	func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var started := Time.get_ticks_usec()
		var way := super.find_path(from, to)
		usec += Time.get_ticks_usec() - started
		calls += 1
		return way


func _init() -> void:
	_reset_stage()


func _ready() -> void:
	await super._ready()
	if _args.has("unpaced"):
		# The display's refresh does not hold the frame: its time is the work (a desktop run).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	_ablate = String(_args.get("ablate", ""))
	_outline = int(_args.get("outline", 0))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var sim := _horde.director.sim
	if _ablate == "navigation":
		sim.pathing = ZombiePathing.new()
	else:
		_timed = TimedPathing.new(get_world_3d().navigation_map)
		sim.pathing = _timed
	# The throttle is driven from `_process` below, so its time can be told from the rest.
	_horde.throttle.set_process(false)
	if _ablate == "draw":
		_horde.visible = false
	_label.visible = false
	_reset_stage()
	_last_frame_usec = Time.get_ticks_usec()


## One server tick, stage by stage: what `ZombieHorde.step` does, with a clock between the parts.
func _sim_step() -> void:
	_clock += ZombieSim.STEP
	var started := Time.get_ticks_usec()
	_move_player()
	_rules.apply(RulesAction.tick(ZombieSim.STEP))
	_shoot()
	var targets: Dictionary = {}
	for id in _positions:
		targets[id] = _positions[id]
	var t_scenery := Time.get_ticks_usec()
	_stage["scenery"] += t_scenery - started
	var path_before := _timed.usec if _timed != null else 0
	_horde.director.tick(ZombieSim.STEP, targets)
	var t_tick := Time.get_ticks_usec()
	_stage["director"] += t_tick - t_scenery
	if _timed != null:
		_stage["navigation"] += _timed.usec - path_before
	var bytes := ZombieCodec.encode(_horde.director.sim.zombies)
	var t_encode := Time.get_ticks_usec()
	_stage["encode"] += t_encode - t_tick
	if _ablate != "views":
		_horde.apply_snapshot(bytes, ZombieSim.STEP)
	var t_apply := Time.get_ticks_usec()
	_stage["apply"] += t_apply - t_encode
	# The same bytes read once more, alone, to tell the decode from the views' update inside `apply`.
	ZombieCodec.decode(bytes)
	_stage["decode_probe"] += Time.get_ticks_usec() - t_apply
	_stage["ticks"] += 1


func _process(delta: float) -> void:
	if _horde == null:
		return
	var started := Time.get_ticks_usec()
	if _ablate != "animation":
		_horde.throttle._process(delta)
	_stage["animation"] += Time.get_ticks_usec() - started
	_place_camera()
	_mark_outlined()
	var now := Time.get_ticks_usec()
	_frame_seen += 1
	if _frame_seen > SETTLE_FRAMES:
		_stage["frame"] = (now - _last_frame_usec) / 1000.0
		_record_row()
		if _frame_rows.size() >= int(_args.get("frames", 400)) and not _reported:
			_reported = true
			_report.call_deferred()
	_last_frame_usec = now
	_reset_stage()


## The `--outline` zombies nearest the camera wear the outline (they are the ones in view).
func _mark_outlined() -> void:
	if _outline <= 0 and not _marked_any:
		return
	var views := _horde.views()
	var eye := _camera.global_position
	views.sort_custom(
		func(a: ZombieView, b: ZombieView) -> bool:
			return (
				a.global_position.distance_squared_to(eye)
				< b.global_position.distance_squared_to(eye)
			)
	)
	for index in views.size():
		views[index].set_outlined(index < _outline)
	_marked_any = _outline > 0


func _count_outlined() -> int:
	var count := 0
	for view in _horde.views():
		if view.is_outlined():
			count += 1
	return count


func _reset_stage() -> void:
	_stage = {
		"scenery": 0,
		"director": 0,
		"navigation": 0,
		"encode": 0,
		"apply": 0,
		"decode_probe": 0,
		"animation": 0,
		"ticks": 0,
		"frame": 0.0,
	}


func _record_row() -> void:
	var row := {}
	for key in _stage:
		row[key] = _stage[key]
	row["physics_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	row["process_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	row["navigation_ms"] = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	row["draws"] = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	row["advanced"] = _horde.throttle.advanced_last_frame
	row["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(
		get_viewport().get_viewport_rid()
	)
	row["cpu_render_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(
		get_viewport().get_viewport_rid()
	)
	row["outlined"] = _count_outlined()
	row["alive"] = _horde.director.sim.standing_count()
	_frame_rows.append(row)


## Means over the measured frames, in milliseconds a frame, and the 95th percentile of the frame.
func _report() -> void:
	var n := float(_frame_rows.size())
	var mean := {}
	for key in _frame_rows[0]:
		var total := 0.0
		for row in _frame_rows:
			total += float(row[key])
		mean[key] = total / n
	var ms := {}
	for key in [
		"scenery", "director", "navigation", "encode", "apply", "decode_probe", "animation"
	]:
		ms[key] = snappedf(mean[key] / 1000.0, 0.001)
	var frames: Array[float] = []
	for row in _frame_rows:
		frames.append(row["frame"])
	frames.sort()
	# The wire format's decode is part of `apply`; the extra pass that timed it is not the game's.
	var decode: float = ms["decode_probe"]
	var script: float = (
		ms["director"] + ms["encode"] + ms["apply"] + ms["animation"] + ms["scenery"]
	)
	var out := {
		"ablate": _ablate,
		"zombies_asked": int(_args.get("zombies", 40)),
		"alive": snappedf(mean["alive"], 0.1),
		"frames": _frame_rows.size(),
		"frame_mean_ms": snappedf(mean["frame"], 0.01),
		"frame_p95_ms": snappedf(frames[int(frames.size() * 0.95)], 0.01),
		"ticks_per_frame": snappedf(mean["ticks"], 0.01),
		"ms_per_frame":
		{
			"director_brains_and_bodies": snappedf(ms["director"] - ms["navigation"], 0.001),
			"navigation_paths": ms["navigation"],
			"encode": ms["encode"],
			"decode": decode,
			"views_update": snappedf(ms["apply"] - decode, 0.001),
			"animation": ms["animation"],
			"scenery": ms["scenery"],
			"rest_drawing_and_engine": snappedf(mean["frame"] - script - decode, 0.001),
		},
		"engine_monitors_ms":
		{
			"physics_process": snappedf(mean["physics_ms"], 0.001),
			"process": snappedf(mean["process_ms"], 0.001),
			"navigation": snappedf(mean["navigation_ms"], 0.001),
		},
		"draw_calls": snappedf(mean["draws"], 0.1),
		"outline_asked": _outline,
		"outlined": snappedf(mean["outlined"], 0.1),
		"gpu_ms": snappedf(mean["gpu_ms"], 0.001),
		"cpu_render_ms": snappedf(mean["cpu_render_ms"], 0.001),
		"animations_advanced_per_frame": snappedf(mean["advanced"], 0.1),
		"navigation_calls_per_frame":
		snappedf(_timed.calls / (n + SETTLE_FRAMES), 0.1) if _timed != null else 0.0,
	}
	var json := JSON.stringify(out)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__bench = %s;" % json)
	print("CROWD_COST ", json)
	if not OS.has_feature("web"):
		get_tree().quit()


## The command line's arguments, and in a browser the page's query as well.
func _parse_args() -> Dictionary:
	var parsed := super._parse_args()
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval(QUERY))
		for pair in query.split("&", false):
			var parts := pair.split("=", true, 1)
			parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
