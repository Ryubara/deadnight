extends Control
## Capture for #1065: the Loadout tab's wardrobe, a PNG per step, as the player sees it. The level
## the account stands at, the layout (desktop or phone) and the tabs to visit come from the command
## line; the same tour runs on the list the grid replaced (it has no tabs, so it takes one shot).
## Run it through the no-focus launcher, with a window the size of the layout:
## `gds godot -- --path game res://tests/captures/wardrobe_grid_tour.tscn --windowed
## --resolution 1920x1080 -- --out=<folder> --label=<name> --level=12 [--phone] [--tabs=a,b,c]
## [--hover] [--wear=<costume index>]`. `--hover` moves a real mouse over the first locked cell of
## each tab; `--wear` puts a costume on first (#1066: the Costumes tab and the Default colours).

const STEP := 1.0 / 30.0
const SETTLE := 0.9
const FILE := "user://wardrobe_grid_capture.cfg"

var _out := "user://wardrobe_grid"
var _label := "grid"
var _level := 1
var _phone := false
var _tabs: PackedStringArray = []
var _hover := false
var _wear := -1
var _shell: MenuShell


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
		elif arg.begins_with("--level="):
			_level = int(arg.get_slice("=", 1))
		elif arg.begins_with("--tabs="):
			_tabs = arg.get_slice("=", 1).split(",")
		elif arg == "--phone":
			_phone = true
		elif arg == "--hover":
			_hover = true
		elif arg.begins_with("--wear="):
			_wear = int(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = FILE
	Settings.reset_defaults()
	MenuProfile.profile_path = "user://wardrobe_grid_profile.json"
	LookUnlocks.profile_path = MenuProfile.profile_path
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(_level)
	ProfileSave.write(profile, [], 1, MenuProfile.profile_path)
	LookStore.save_look(CharacterLook.from_preset(0))
	UIMotion.reduced = true
	UIInputMode.pointer = true
	_shell = MenuShell.new()
	_shell.manual_stage = true
	_shell.phone_mode = 1 if _phone else 0
	_shell.context.profile = MenuProfile.load_saved()
	_shell.context.board = FakeChallengeBoard.new()
	add_child(_shell)
	await get_tree().process_frame
	_shell.tab_bar.button(MenuTab.Id.LOADOUT).pressed.emit()
	var panel := _shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	if _wear >= 0:
		panel.wardrobe.wear_costume(_wear)
	if _tabs.is_empty() or not panel.wardrobe.has_method("show_tab"):
		await _snap("loadout")
	else:
		for tab in _tabs:
			panel.wardrobe.call("show_tab", tab)
			await _snap(tab)
			if _hover:
				await _hover_locked(panel.wardrobe)
				await _snap(tab + "_hover")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuProfile.profile_path))
	get_tree().quit()


## Puts the real pointer over the first locked cell of the tab on show: the pointer moves, the
## cell hears it, the detail line reads the instructions.
func _hover_locked(wardrobe: Control) -> void:
	var cell: Control = wardrobe.call("first_locked_cell")
	if cell == null:
		return
	wardrobe.call("reveal", cell)
	await get_tree().process_frame
	await get_tree().process_frame
	var at := cell.get_global_transform_with_canvas() * (cell.size * 0.5)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame


func _snap(step: String) -> void:
	for _i in int(SETTLE / STEP):
		_shell.view.stage.advance(STEP)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "%s/%s_%s.png" % [_out, _label, step]
	get_viewport().get_texture().get_image().save_png(file)
	print("[wardrobe-grid] ", file)
