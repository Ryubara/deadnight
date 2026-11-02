extends Node
## Scripted capture of the Play screen: the usual rules, then each control moved with the keyboard
## the way a player does. Run it with Movie Maker (`--write-movie out.png --fixed-fps 10
## --quit-after 80`). Not part of the game. The mouse is never captured or moved.

const SCREEN := "res://ui/screens/play_screen.tscn"
const FILE := "user://match_settings_capture.cfg"

var _screen: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(SCREEN, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top()
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _run() -> void:
	await _beat("rest", 1.0)
	var panel = _screen.get("panel")
	if panel == null:
		# The screen before the match settings: a card with two buttons.
		return
	UIInputMode.pointer = false
	panel.count_selector.grab_focus()
	_press(&"ui_right")
	_press(&"ui_right")
	await _beat("count-3x", 0.8)
	panel.alive_slider.grab_focus()
	for _i in 12:
		_press(&"ui_right")
	await _beat("alive-12", 0.8)
	panel.break_slider.grab_focus()
	for _i in 5:
		_press(&"ui_right")
	await _beat("break-10", 1.0)


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _beat(label: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	print(
		(
			"beat %s: %s"
			% [label, _screen.get("panel").settings().to_dict() if _screen.get("panel") else "-"]
		)
	)
