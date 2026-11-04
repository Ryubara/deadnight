extends Node
## Scripted capture of the customization screen: rest, a preset, keyboard and gamepad moves through
## the grid, a locked item, a random look and a save. Run it with Movie Maker
## (`--write-movie out.png --fixed-fps 10 --quit-after 220`). Settings go to a throwaway file.

const SCREEN := "res://ui/screens/customize_screen.tscn"
const FILE := "user://customize_capture.cfg"

var _screen: CustomizeScreen


func _ready() -> void:
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(SCREEN, UITransition.Kind.CUT, {"seed": 1958})
	await UIRouter.idle
	_screen = UIRouter.top() as CustomizeScreen
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _run() -> void:
	await _beat("rest", 1.0)
	UIInputMode.pointer = false
	# A preset, picked with the keyboard on the preset selector.
	_press(&"ui_right")
	await _beat("preset-usher", 0.8)
	_press(&"ui_right")
	await _beat("preset-mechanic", 0.8)
	# Headwear, then along the main colours as a gamepad would.
	_screen.show_tab(&"headwear")
	await _beat("headwear-tab", 0.6)
	_screen.cell_of(&"headwear", &"ballcap").grab_focus()
	_pad(JOY_BUTTON_A)
	await _beat("headwear", 0.8)
	_screen.show_tab(&"colours")
	_screen.cell("colour:primary", 8).grab_focus()
	for i in 2:
		_pad(JOY_BUTTON_DPAD_RIGHT)
		await _beat("primary-%d" % i, 0.5)
	# A locked swatch: the focus lands on it, the detail line says how to get it, the choice stays.
	var locked := _screen.first_locked_cell()
	if locked != null:
		locked.grab_focus()
		_pad(JOY_BUTTON_A)
		await _beat("locked", 1.0)
	_screen.show_tab(&"body")
	_screen.cell("colour:skin", 2).grab_focus()
	_pad(JOY_BUTTON_A)
	await _beat("skin", 0.6)
	_screen.randomize()
	await _beat("random", 1.0)
	_screen.save()
	await _beat("saved", 1.5)


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)


func _beat(label: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	print(
		"beat ",
		label,
		" frame ",
		Engine.get_process_frames(),
		" focus ",
		get_viewport().gui_get_focus_owner(),
		" pointer ",
		UIInputMode.pointer
	)
