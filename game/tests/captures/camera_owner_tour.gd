extends Node
## The view at the start of a night with 3 bots (#702), by the path the Play screen takes: the menu,
## Solo, 3 bots chosen, Start. One PNG into `--out=<folder>` named `<--label=>-<step>` at the
## window's real pixel size, and the line `view: <who owns the current camera>` with every body's
## camera (`current` flag and where it is), so a still that looks through a bot says so in words.
## The view is never turned toward anyone: it is what the person gets. Not part of the game. Run it
## through the no-focus launcher, not headless:
## `gds godot -- --path game res://tests/captures/camera_owner_tour.tscn --windowed
## --resolution 1280x720 -- --out=<folder> --label=after`. Never moves the real mouse.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTLE := 1.2
const NIGHT_WAIT := 6.0
const PLAY := 8.0

var _out := "user://camera_owner_tour"
var _label := "after"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://camera_owner_capture.cfg"
	Settings.reset_defaults()
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await get_tree().create_timer(SETTLE).timeout
	var menu := UIRouter.top() as MainMenu
	await _press((menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel).button(&"solo"))
	await get_tree().create_timer(SETTLE).timeout
	var screen := UIRouter.top()
	var panel: MatchSettingsPanel = screen.get("panel")
	panel.bots_selector.select(3, true)
	await _press(screen.get("start_button"))
	await get_tree().create_timer(NIGHT_WAIT).timeout
	var night: Night = (UIRouter.top() as NightScreen).night
	night.player().capture_mouse = false
	night.player().local_input = false
	night.state.apply_events(night.server.rules.apply(RulesAction.skip_break()))
	await get_tree().create_timer(PLAY).timeout
	_report(night)
	await _still("start-of-night")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	# A lambda of this script left in the menu's static variable crashes the quit (#667).
	MainMenu.board_factory = Callable()
	get_tree().quit()


## Prints who the viewport looks through, and each body's camera.
func _report(night: Night) -> void:
	var seen := night.get_viewport().get_camera_3d()
	var owner_id := 0
	for id: int in night.server._bodies:
		var camera: Camera3D = night.server.body_of(id).camera_rig.camera()
		print(
			"body ",
			id,
			" local ",
			night.server.body_of(id).local_input or id == Night.PLAYER_ID,
			" camera current ",
			camera.current,
			" at ",
			camera.global_position.snappedf(0.1)
		)
		if camera == seen:
			owner_id = id
	print("bots seated: ", night.bots.count())
	print("view: body ", owner_id, " (the person is body ", Night.PLAYER_ID, ")")


## A tap on `control`.
func _press(control: Control) -> void:
	var point := get_viewport().get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.global_position = point
		click.pressed = pressed
		Input.parse_input_event(click)
		await get_tree().create_timer(0.12).timeout


func _still(step: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%s.png" % [_out, _label, step]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size)
