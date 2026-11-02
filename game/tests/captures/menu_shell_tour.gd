extends Control
## Capture for #397: the tab shell with its panels over the live stage, every tab, with sample
## account and challenge data. Run it through the no-focus launcher at the window's real pixels:
## `gds godot -- --path game res://tests/captures/menu_shell_tour.tscn --windowed --resolution
## 1920x1080 -- --out=<folder> [--label=name] [--phone] [--tabs=0,3] [--pad]`
## One PNG per tab, taken when the camera has settled.

const STEP := 1.0 / 30.0
const SETTLE := 2.0

var _out := "user://menu_shell"
var _label := "shell"
var _phone := false
var _pad := false
var _tabs: Array[int] = [0, 1, 2, 3, 4]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
		elif arg == "--phone":
			_phone = true
		elif arg == "--pad":
			_pad = true
		elif arg.begins_with("--tabs="):
			_tabs.clear()
			for part in arg.get_slice("=", 1).split(","):
				_tabs.append(int(part))
	DirAccess.make_dir_recursive_absolute(_out)
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 1 if _phone else 0
	shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json("Ryubara", MenuProfile.xp_at(14) + 212, 485, {"rifle": 900})
	)
	shell.context.board = FakeChallengeBoard.new()
	add_child(shell)
	UIInputMode.pointer = not _pad
	UIInputMode.gamepad = _pad
	await get_tree().process_frame
	for tab: int in _tabs:
		shell.show_tab(tab as MenuTab.Id, false)
		if _pad:
			shell.focus_panel()
		for _i in int(SETTLE / STEP):
			shell.view.stage.advance(STEP)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := (
			"%s/%s_%d_%s.png" % [_out, _label, tab, MenuTab.label(tab as MenuTab.Id).to_lower()]
		)
		get_viewport().get_texture().get_image().save_png(file)
		print("[menu-shell] ", file)
	get_tree().quit()
