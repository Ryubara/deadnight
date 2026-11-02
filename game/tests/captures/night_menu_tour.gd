extends Node
## The night's menu, for captures (#471): the night, the menu opened the way a player opens it, the
## settings inside it, and back to the night. Each beat saves a picture of the window, named for
## the beat, into the folder given as `--out=<folder>` (it loads a night first, so there is no
## frame count to guess): `gds godot -- --path game res://tests/captures/night_menu_tour.tscn
## --resolution 1280x720 -- --out=<folder>`. Add `--touch` (and `--resolution 2340x1080`) for a
## phone in landscape: the menu opens with a finger on the pause button. Settings go to a throwaway
## file.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const FILE := "user://night_menu_capture.cfg"
const BEAT_FRAMES := 15

var _touch := false
var _out := ""
var _count := 0
var _screen: NightScreen


func _ready() -> void:
	_touch = "--touch" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	Settings.path = FILE
	Settings.reset_defaults()
	TouchMode.device_is_touch = _touch
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	await _screen.night.ready_to_play
	# The machine's real mouse must not turn the camera of a capture.
	_screen.night.player().local_input = false
	# The loading card fades out for a moment after the night is ready.
	await get_tree().create_timer(2.5).timeout
	await _beat("night")
	if _touch:
		var touch := _screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
		_tap(touch.button_circle(TouchLayout.PAUSE)[&"centre"])
	else:
		_action(&"pause")
	await _beat("menu")
	_press("Settings")
	await _beat("settings")
	# (The menu before #471 has no Settings: the same tour films it for the Before picture.)
	var pages := _screen.find_children("*", "SettingsScreen", true, false)
	if not pages.is_empty():
		(pages[0] as SettingsScreen).select_tab(4 if _touch else 3)
	await _beat("settings-tab")
	_press("Back")
	await _beat("menu-again")
	_press("Resume")
	await _beat("night-again")
	await _beat("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _beat(label: String) -> void:
	for _i in BEAT_FRAMES:
		await get_tree().process_frame
	print("beat ", label)
	if _out != "":
		_count += 1
		DirAccess.make_dir_recursive_absolute(_out)
		get_viewport().get_texture().get_image().save_png("%s/%d_%s.png" % [_out, _count, label])


func _action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)


func _tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = get_viewport().get_final_transform() * point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _press(text: String) -> void:
	for candidate in _screen.find_children("*", "UIButton", true, false):
		var button := candidate as UIButton
		if button.text == text and button.is_visible_in_tree():
			button.pressed.emit()
			return
