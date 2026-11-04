extends Node3D
## The frame in which a blast cripples a crowd (#932). Not part of the game. A pack of walkers
## stands in view; in one snapshot `CRIPPLED` of them change look to the crawler, as a blast that
## takes their legs does (`ZombieHorde.apply_snapshot`), and the time of that call and of the frames
## after it is recorded. Repeated on a fresh horde `reps` times (the first is thrown away: it builds
## the shaders), so the worst single frame is read off many blasts, not the mean of one.
##
## Measure (windowed, real time, vsync off; through the kit's launcher):
##   gds godot -- --path game res://tests/captures/cripple_hitch.tscn -- reps=12 prewarm=night
## `prewarm=none` skips the warm-up's parked bodies. Capture (Movie Maker, one blast, with frames
## named by what they show): add `--fixed-fps 10 --write-movie <folder>/crowd.png --quit-after 60`
## and `-- reps=1 capture`. The last line printed is `RESULT {...}`, times in microseconds.

const CROWD := 30
const CRIPPLED := 20
## Frames the crowd stands before the blast, and the frames recorded after it.
const SETTLE_FRAMES := 30
const AFTER_FRAMES := 8
const COLUMNS := 6
const SPACING := 1.7
const STEP := 1.0 / 30.0

var _reps := 12
var _prewarm := "night"
var _capture := false
var _rep := 0
var _frame := 0
var _horde: ZombieHorde
var _sim: ZombieSim
var _zombies: Array[ZombieBody] = []
var _last_us := 0
var _intervals: Array[int] = []
var _apply_us := 0
var _quiet: Array[int] = []
var _worst_after: Array[int] = []
## Each recorded frame after the blast, by position, over the repetitions.
var _by_position: Array[Array] = []
var _apply_calls: Array[int] = []
var _crawler_profile: ZombieProfile
var _camera: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("reps="):
			_reps = int(arg.get_slice("=", 1))
		elif arg.begins_with("prewarm="):
			_prewarm = arg.get_slice("=", 1)
		elif arg == "capture":
			_capture = true
	if not _capture:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	_build_stage()
	_begin_rep()


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.7)
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.2, 0.18)
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 7.5, 9.5)
	_camera.rotation_degrees = Vector3(-38, 0, 0)
	_camera.current = true
	add_child(_camera)


func _begin_rep() -> void:
	if _horde != null:
		_horde.free()
	_horde = ZombieHorde.new()
	add_child(_horde)
	_horde.setup_client(_camera, 0.7)
	if _prewarm == "night":
		_horde.prewarm(NightWarmup.PARKED_BODIES)
	_sim = ZombieFixture.sim()
	_zombies.clear()
	for index in CROWD:
		var column := index % COLUMNS
		var row := index / COLUMNS
		var at := Vector3((column - (COLUMNS - 1) * 0.5) * SPACING, 0, -float(row) * SPACING + 1.0)
		_zombies.append(ZombieFixture.standing(_sim, index + 1, at, 1.0))
	_crawler_profile = ZombieProfile.from_type(
		RulesFixture.tuning().roster.type_of(&"crawler"), &"crawler", _sim.tuning
	)
	_frame = 0
	_intervals.clear()
	_last_us = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_intervals.append(now - _last_us)
	_last_us = now
	_frame += 1
	if _frame == SETTLE_FRAMES + 1:
		for index in CRIPPLED:
			_zombies[index].profile = _crawler_profile
		var began := Time.get_ticks_usec()
		_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), STEP)
		_apply_us = Time.get_ticks_usec() - began
	else:
		_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), STEP)
	if _capture and _frame % 10 == 0:
		print("frame ", _frame, " looks ", _look_counts())
	if _frame >= SETTLE_FRAMES + 1 + AFTER_FRAMES:
		_end_rep()


func _end_rep() -> void:
	if _rep > 0 or _reps == 1:
		var settled: Array[int] = _intervals.slice(10, SETTLE_FRAMES)
		settled.sort()
		_quiet.append(settled[settled.size() / 2])
		var after: Array[int] = _intervals.slice(
			SETTLE_FRAMES + 1, SETTLE_FRAMES + 1 + AFTER_FRAMES
		)
		_worst_after.append(after.max())
		for position in after.size():
			if _by_position.size() <= position:
				_by_position.append([])
			_by_position[position].append(after[position])
		_apply_calls.append(_apply_us)
	_rep += 1
	if _rep >= _reps + (1 if _reps > 1 else 0):
		_report()
		return
	_begin_rep()


func _look_counts() -> Dictionary:
	var counts := {}
	for view in _horde.views():
		counts[view.look] = int(counts.get(view.look, 0)) + 1
	return counts


func _median(values: Array) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _report() -> void:
	var result := {
		"reps": _quiet.size(),
		"prewarm": _prewarm,
		"crippled": CRIPPLED,
		"apply_us_median": _median(_apply_calls),
		"apply_us_max": _apply_calls.max(),
		"worst_frame_us_median": _median(_worst_after),
		"worst_frame_us_max": _worst_after.max(),
		"quiet_frame_us_median": _median(_quiet),
		"frames_after_us_median":
		_by_position.map(func(values: Array) -> int: return _median(values)),
		"looks": _look_counts(),
	}
	print("RESULT ", JSON.stringify(result))
	get_tree().quit()
