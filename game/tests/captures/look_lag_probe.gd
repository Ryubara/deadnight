extends Node
## Replays one recorded mouse path through the real input path of a real night while the frame rate
## is held down or hitched, and writes what each drawn frame showed (#905). Not part of the game.
##
##     gds godot -- --path game res://tests/captures/look_lag_probe.tscn --headless
##         -- --mode=solo --fps=30 --hitch=120:20 --seconds=8 --out=<abs csv>
##
## Options after `--`:
##   --mode=solo|online   a local night, or a client of a game server on this machine (prediction)
##   --fps=N              `Engine.max_fps` (0 is as fast as it goes)
##   --hitch=MS:EVERY     a delay of MS milliseconds in every EVERY-th frame
##   --ticks=N            night ticks a physics frame runs (`Night.ticks_per_frame`)
##   --bots=N             bots beside the person
##   --seconds=S          how long the path is (it repeats nothing)
##   --out=FILE           the csv, one row per drawn frame
##
## The path is `PATH_FILE` (millisecond rows of whole mouse pixels, seeded and written once). Its
## events are posted after each drawn frame, every millisecond since the last post as a motion of
## its own, so the engine receives them as the operating system would: during the frame, and
## handled at the start of the next one.

const PATH_FILE := "res://tests/captures/look_path.txt"
const PATH_SEED := 905
const PATH_SECONDS := 12.0
const PLAYER_ID := 1

var _mode := "solo"
var _hitch_ms := 0
var _hitch_every := 0
var _seconds := 8.0
var _out := ""
var _night: Night
var _host: NightHost
var _player: Player
var _path: PackedVector2Array = PackedVector2Array()
var _origin_us := 0
var _posted_ms := 0
var _posted := Vector2.ZERO
var _frame := 0
var _ticks_this_frame := 0
var _last_us := 0
var _yaw0 := 0.0
var _pitch0 := 0.0
var _rows: Array[String] = []
var _recording := false
var _scale := 1.0
var _early: Node


func _ready() -> void:
	# Last of the frame's `_process` calls: the camera has been placed by then.
	process_priority = 100000
	var args := NetArgs.new()
	_mode = args.get_string("mode") if args.get_string("mode") != "" else "solo"
	_out = args.get_string("out")
	if args.get_string("seconds") != "":
		_seconds = float(args.get_string("seconds"))
	var hitch := args.get_string("hitch")
	if hitch != "":
		var parts := hitch.split(":")
		_hitch_ms = int(parts[0])
		_hitch_every = int(parts[1])
	_path = _load_path()
	await _build(args)
	Engine.max_fps = int(args.get_string("fps")) if args.get_string("fps") != "" else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var early := Node.new()
	early.process_priority = -100000
	early.set_script(load("res://tests/captures/look_lag_early.gd"))
	add_child(early)
	early.set(&"rig", _player.camera_rig)
	_early = early
	await get_tree().process_frame
	_calibrate()
	_yaw0 = _player.camera_rig.yaw
	_pitch0 = _player.camera_rig.pitch
	_origin_us = Time.get_ticks_usec()
	_last_us = _origin_us
	_recording = true


func _build(args: NetArgs) -> void:
	var bots := int(args.get_string("bots")) if args.get_string("bots") != "" else 0
	if _mode == "online":
		var world := SubViewport.new()
		world.own_world_3d = true
		world.size = Vector2i(64, 64)
		world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(world)
		_host = NightHost.new()
		_host.port = 0
		_host.log_enabled = false
		_host.seed_value = 5
		world.add_child(_host)
		while not _host.serving:
			await get_tree().physics_frame
		var url := "ws://127.0.0.1:%d" % _host.listener.port()
		_night = Night.new()
		add_child(_night)
		await _night.start_remote(url, Night.Mode.HUMAN, 30.0)
		_host.server.rules.apply(RulesAction.skip_break())
	else:
		_night = Night.new()
		if bots > 0:
			_night.match_settings.bots = bots
		add_child(_night)
		await _night.start(Night.Mode.HUMAN)
		_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	if args.get_string("ticks") != "":
		_night.ticks_per_frame = int(args.get_string("ticks"))
	_player = _night.player()
	_player.capture_mouse = false
	var spot := Vector3(0.0, 0.05, -28.0)
	if _mode == "online":
		_host.server.body_of(1).teleport(spot)
	else:
		_player.teleport(spot)
	for _i in 30:
		await get_tree().physics_frame
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.pitch = 0.0
	_player.camera_rig.sensitivity = 1.0


## The window's stretch scales a motion's `relative` (a 64 pixel headless window turns 30 times as
## far as a 1920 pixel one: `screen_relative` is the unscaled one). One motion of known size says by
## how much, and the path is posted divided by it, so a headless run turns what a 1920 x 1080 window
## does.
func _calibrate() -> void:
	var rig := _player.camera_rig
	var before := rig.yaw
	_post(Vector2(10.0, 0.0), 1.0)
	Input.flush_buffered_events()
	_scale = (
		absf(angle_difference(before, rig.yaw)) / (10.0 * _player.tuning.mouse_radians_per_pixel)
	)
	rig.yaw = 0.0
	rig.pitch = 0.0


func _post(step: Vector2, divide: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = step / divide
	event.screen_relative = step / divide
	event.position = Vector2(640.0, 360.0)
	event.global_position = event.position
	Input.parse_input_event(event)


func _physics_process(_delta: float) -> void:
	_ticks_this_frame += 1


func _process(_delta: float) -> void:
	if not _recording:
		return
	_frame += 1
	if _hitch_every > 0 and _frame % _hitch_every == 0:
		OS.delay_msec(_hitch_ms)
	_after_draw()


## The end of a frame: write what it shows, then post the path up to now (a headless run draws
## nothing, and the camera is placed in `_process`).
func _after_draw() -> void:
	var now_us := Time.get_ticks_usec()
	var rig := _player.camera_rig
	var drawn := rig.camera().global_transform
	var euler := drawn.basis.get_euler(EULER_ORDER_YXZ)
	var aim := rig.aim_transform().basis.get_euler(EULER_ORDER_YXZ)
	var body := _player.get_node("Model") as Node3D
	var body_yaw := body.get_global_transform_interpolated().basis.get_euler(EULER_ORDER_YXZ).y
	var early_yaw: float = _early.get("yaw_seen") if _early != null else 0.0
	_rows.append(
		(
			"%d,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.3f,%.3f,%.3f,%d,%.1f,%.1f,%.4f,%.6f"
			% [
				_frame,
				now_us - _origin_us,
				now_us - _last_us,
				rig.yaw,
				rig.pitch,
				euler.y,
				aim.y,
				body_yaw,
				drawn.origin.x,
				drawn.origin.y,
				drawn.origin.z,
				_ticks_this_frame,
				_posted.x,
				_posted.y,
				Engine.get_physics_interpolation_fraction(),
				early_yaw
			]
		)
	)
	_ticks_this_frame = 0
	_last_us = now_us
	var until_ms := int((now_us - _origin_us) / 1000)
	while _posted_ms < until_ms and _posted_ms < _path.size():
		var step := _path[_posted_ms]
		_posted_ms += 1
		if step == Vector2.ZERO:
			continue
		_posted += step
		_post(step, _scale)
	# Handled at once, as the engine handles what the system queued during the frame at the start
	# of the next one; the view shows it from that frame on.
	Input.flush_buffered_events()
	if (now_us - _origin_us) > int((_seconds + 0.5) * 1_000_000.0):
		_finish()


func _finish() -> void:
	_recording = false
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
		var file := FileAccess.open(_out, FileAccess.WRITE)
		var header := "frame,t_us,dt_us,yaw,pitch,cam_yaw,aim_yaw,body_yaw,cam_x,cam_y,cam_z,ticks,"
		header += "posted_x,posted_y,frac,early_yaw"
		file.store_line(header)
		file.store_line(
			(
				"# yaw0=%.6f pitch0=%.6f rpp=%.8f scale=%.4f"
				% [_yaw0, _pitch0, _player.tuning.mouse_radians_per_pixel, _scale]
			)
		)
		for row in _rows:
			file.store_line(row)
		file.close()
	print("LOOK_LAG_DONE frames=%d" % _rows.size())
	get_tree().quit()


## One recorded path: bursts of flicks and slow tracking with pauses, at 1000 Hz in whole pixels
## (what a gaming mouse reports). Written to `PATH_FILE` the first time.
func _load_path() -> PackedVector2Array:
	var path := PackedVector2Array()
	if FileAccess.file_exists(PATH_FILE):
		var file := FileAccess.open(PATH_FILE, FileAccess.READ)
		while not file.eof_reached():
			var line := file.get_line()
			if line == "":
				continue
			var parts := line.split(",")
			path.append(Vector2(float(parts[0]), float(parts[1])))
		return path
	var random := RandomNumberGenerator.new()
	random.seed = PATH_SEED
	var total := int(PATH_SECONDS * 1000.0)
	path.resize(total)
	var carry := Vector2.ZERO
	var ms := 0
	while ms < total:
		var kind := random.randi_range(0, 2)
		var length := 0
		var velocity := Vector2.ZERO
		match kind:
			0:
				# A flick: 300 to 1200 px in 80 to 200 ms, a bell of speed.
				length = random.randi_range(80, 200)
				var size := (
					random.randf_range(300.0, 1200.0) * (1.0 if random.randf() < 0.5 else -1.0)
				)
				velocity = Vector2(size, random.randf_range(-80.0, 80.0)) / float(length)
			1:
				# Tracking: 150 to 400 px a second for half a second to 1.2 s, with a wobble.
				length = random.randi_range(500, 1200)
				velocity = (
					Vector2(random.randf_range(-400.0, 400.0), random.randf_range(-60.0, 60.0))
					/ 1000.0
				)
			_:
				length = random.randi_range(100, 400)
		for i in length:
			if ms >= total:
				break
			var bell := 1.0
			if kind == 0:
				bell = 1.5 * sin(PI * float(i) / float(length))
			var wobble := (
				Vector2(random.randfn(0.0, 0.15), random.randfn(0.0, 0.08))
				if kind == 1
				else Vector2.ZERO
			)
			var want := velocity * bell + wobble + carry
			var whole := Vector2(roundf(want.x), roundf(want.y))
			carry = want - whole
			path[ms] = whole
			ms += 1
	var out := FileAccess.open(PATH_FILE, FileAccess.WRITE)
	for step in path:
		out.store_line("%d,%d" % [int(step.x), int(step.y)])
	out.close()
	return path
