extends Control
## Capture for #397: the menu's live stage at each tab's camera. The stage is stepped by hand at a
## fixed 30 steps a second (no wall clock), so the picture repeats. Run it through the no-focus
## launcher at the window's real pixels:
## `gds godot -- --path game res://tests/captures/menu_stage_tour.tscn --windowed --resolution
## 1280x720 -- --out=<folder> [--label=name] [--look=3] [--weapon=shotgun] [--still] [--tabs=0,1]`.
## It writes one PNG per tab, taken when the camera has settled.

const STEP := 1.0 / 30.0
## Seconds of stage time shown before each shot (the camera needs about a second to settle).
const SETTLE := 2.0

var _out := "user://menu_stage"
var _label := "stage"
var _tabs: Array[int] = [0, 1, 2, 3, 4]
var _look := -1
var _weapon := &""
var _still := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
		elif arg.begins_with("--look="):
			_look = int(arg.get_slice("=", 1))
		elif arg.begins_with("--weapon="):
			_weapon = StringName(arg.get_slice("=", 1))
		elif arg == "--still":
			_still = true
		elif arg.begins_with("--tabs="):
			_tabs.clear()
			for part in arg.get_slice("=", 1).split(","):
				_tabs.append(int(part))
	DirAccess.make_dir_recursive_absolute(_out)
	var view := MenuStageView.new()
	if _still:
		view.forced_mode = MenuStageView.MODE_STILL
	view.manual = true
	add_child(view)
	await get_tree().process_frame
	if _look >= 0:
		view.stage.show_look(
			CharacterLook.from_preset(_look), _weapon if _weapon != &"" else MenuHero.saved_weapon()
		)
	elif _weapon != &"":
		view.stage.hero.hold(_weapon)
	for tab: int in _tabs:
		view.show_tab(tab as MenuTab.Id)
		for _i in int(SETTLE / STEP):
			view.stage.advance(STEP)
			await get_tree().process_frame
		view.refresh()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := (
			"%s/%s_%d_%s.png" % [_out, _label, tab, MenuTab.label(tab as MenuTab.Id).to_lower()]
		)
		get_viewport().get_texture().get_image().save_png(file)
		print("[menu-stage] ", file)
	get_tree().quit()
