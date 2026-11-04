extends Control
## Capture for #893: how sharp the menu's stage reads. Run through the no-focus launcher at the
## window's real pixels:
## `gds godot -- --path game res://tests/captures/menu_stage_sharp.tscn --windowed --resolution
## 1920x1080 -- --out=<folder> --label=name [--level=live|half|still|auto] [--msaa=0|1|2|3]
## [--seconds=8] [--tab=0] [--grain] [--load=ms] [--load_for=seconds] [--bench=seconds]
## [--novsync] [--compact]` (msaa: the engine's enum, 0 off, 1 2x, 2 4x, 3 8x).
## Fixed levels step the stage by hand (the same pose every run) and write one PNG. `auto` runs
## the real governor on the wall clock for `--seconds`, logging each second's mean frame and the
## level, then writes a PNG. `--load=ms` busies the main thread that long every frame, to stand in
## for a loaded machine. `--bench=N` keeps a fixed level drawing for N seconds after the shot and
## prints the frame time (use `--novsync`, or every frame reads the display's interval).
## `--grain` puts the film overlay on top, as the game does.

const STEP := 1.0 / 30.0
const SETTLE := 2.0

var _out := "user://menu_stage_sharp"
var _label := "sharp"
var _level := "live"
var _msaa := -1
var _seconds := 8.0
var _tab := 0
var _grain := false
var _compact := false
var _bench := 0.0
var _times: Array[float] = []
var _benching := false
var _load_ms := 0.0
var _load_for := INF
var _view: MenuStageView
var _clock := 0.0
var _second := 0.0
var _frames := 0
var _sum := 0.0
var _last_level := -1
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
		elif arg.begins_with("--level="):
			_level = arg.get_slice("=", 1)
		elif arg.begins_with("--msaa="):
			_msaa = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.get_slice("=", 1))
		elif arg.begins_with("--tab="):
			_tab = int(arg.get_slice("=", 1))
		elif arg.begins_with("--load_for="):
			_load_for = float(arg.get_slice("=", 1))
		elif arg.begins_with("--load="):
			_load_ms = float(arg.get_slice("=", 1))
		elif arg.begins_with("--bench="):
			_bench = float(arg.get_slice("=", 1))
		elif arg == "--novsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif arg == "--compact":
			_compact = true
		elif arg == "--grain":
			_grain = true
	DirAccess.make_dir_recursive_absolute(_out)
	_view = MenuStageView.new()
	_view.manual = _level != "auto"
	_view.level_changed.connect(func(l: int) -> void: print("[sharp] level -> ", l))
	add_child(_view)
	_view.set_compact(_compact)
	if _grain:
		var layer := CanvasLayer.new()
		layer.layer = 110
		var film := ColorRect.new()
		film.set_script(load("res://ui/skin/film_overlay.gd"))
		film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		film.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(film)
		add_child(layer)
	await get_tree().process_frame
	if _msaa >= 0:
		_view.viewport().msaa_3d = _msaa as Viewport.MSAA
	_view.show_tab(_tab as MenuTab.Id)
	if _level == "auto":
		return
	match _level:
		"half":
			_view.set_level(StageGovernor.Level.HALF)
		"still":
			_view.set_level(StageGovernor.Level.STILL)
		_:
			_view.set_level(StageGovernor.Level.LIVE)
	for _i in int(SETTLE / STEP):
		_view.stage.advance(STEP)
		await get_tree().process_frame
	_view.refresh()
	await get_tree().process_frame
	await _shoot()
	if _bench > 0.0:
		_benching = true
		await get_tree().create_timer(_bench).timeout
		_benching = false
		_times = _times.slice(30)
		_times.sort()
		var total := 0.0
		for t in _times:
			total += t
		print(
			(
				"[sharp] bench level=%s msaa=%d render=%s mean=%.2f p50=%.2f p95=%.2f ms n=%d"
				% [
					_level,
					_view.viewport().msaa_3d,
					_view.viewport().size,
					total / _times.size() * 1000.0,
					_times[_times.size() / 2] * 1000.0,
					_times[int(_times.size() * 0.95)] * 1000.0,
					_times.size()
				]
			)
		)
	get_tree().quit()


func _process(delta: float) -> void:
	if _benching:
		_times.append(delta)
	if _level != "auto" or _done:
		return
	if _load_ms > 0.0 and _clock < _load_for:
		var until := Time.get_ticks_usec() + int(_load_ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass
	_clock += delta
	_second += delta
	_frames += 1
	_sum += delta
	var lv: int = _view.level
	if _second >= 1.0:
		print(
			(
				"[sharp] t=%.1f mean=%.1f ms level=%d vp=%s"
				% [_clock, _sum / _frames * 1000.0, lv, _view.viewport().size]
			)
		)
		_second = 0.0
		_frames = 0
		_sum = 0.0
	_last_level = lv
	if _clock >= _seconds:
		_done = true
		await _shoot()
		get_tree().quit()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var vp := _view.viewport()
	print(
		(
			"[sharp] window=%s root=%s scale=%s view=%s viewport=%s msaa=%d level=%d adapter=%s"
			% [
				DisplayServer.window_get_size(),
				get_tree().root.size,
				get_window().content_scale_factor,
				_view.size,
				vp.size,
				vp.msaa_3d,
				_view.level,
				_view.adapter_name
			]
		)
	)
	print(
		(
			"[sharp] final=%s canvas=%s render=%s"
			% [
				get_viewport().get_final_transform(),
				get_viewport().canvas_transform,
				_view.render_size() if _view.has_method("render_size") else Vector2i.ZERO
			]
		)
	)
	var file := "%s/%s.png" % [_out, _label]
	get_viewport().get_texture().get_image().save_png(file)
	print("[sharp] ", file)
