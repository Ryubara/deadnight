extends Node
## Every menu screen and tab at each window size, with the fit check the suite runs
## (`tests/ui/test_ui_fit.gd`, #980) and a still of each one. Run through the no-focus launcher:
## `gds godot -- --path game res://tests/captures/ui_fit_tour.tscn --windowed -- --out=<folder>
## --label=before --sizes=1280x720,844x390`. It resizes the window itself, prints every sentence of
## `UiFit` and saves `<out>/<label>-<size>-<subject>.png` when `--out` is given (`--only=<text>`
## keeps the subjects whose name has the text). With real fonts the heights are the player's.

const SETTLE := 0.5

var _out := ""
var _label := "run"
var _sizes: Array[Vector2i] = []
var _scales: Array[float] = [1.0]
var _only := ""
var _pages := false
var _run: UiFitRun
var _problems := 0
var _subjects := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--scales="):
			_scales.clear()
			for text in arg.trim_prefix("--scales=").split(","):
				_scales.append(float(text))
		elif arg == "--pages":
			_pages = true
		elif arg.begins_with("--sizes="):
			for text in arg.trim_prefix("--sizes=").split(","):
				var parts := text.split("x")
				_sizes.append(Vector2i(int(parts[0]), int(parts[1])))
	if _sizes.is_empty():
		_sizes.assign(UiFitRun.SIZES)
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://ui_fit_tour.cfg"
	Settings.reset_defaults()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run = UiFitRun.new(get_tree())
	_run.begin()
	for size in _sizes:
		for factor in _scales:
			await _run.set_window(size, factor)
			await _tour()
	if _pages:
		for page: Array in UiFitRun.PAGES:
			for factor in _scales:
				await _run.set_window(page[0], factor, page[1])
				await _tour()
	await _run.close()
	_run.restore()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	print("ui fit: %d subjects, %d problems" % [_subjects, _problems])
	get_tree().quit()


func _tour() -> void:
	for tab: MenuTab.Id in MenuTab.ORDER:
		for extreme in [false, true]:
			await _look(await _run.open_tab(tab, extreme))
	for screen_name in UiFitRun.screen_names():
		await _look(await _run.open(screen_name))


func _look(subject: Dictionary) -> void:
	if _only != "" and not String(subject["name"]).contains(_only):
		return
	_subjects += 1
	var lines := _run.problems(subject)
	lines.append_array(
		_run.chrome_problems(subject) if subject.has("shell") else [] as Array[String]
	)
	for line in lines:
		print("  ", line)
	_problems += lines.size()
	if _out == "":
		return
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var file := String(subject["name"]).replace("/", "-").replace(" ", "_").replace("@", "_")
	var path := "%s/%s-%s.png" % [_out, _label, file]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " ", "ok" if lines.is_empty() else "%d problems" % lines.size())
