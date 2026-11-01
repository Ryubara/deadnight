extends Node
## Scripted capture of the settings screen driven by key and gamepad events only (no focus calls,
## no mouse): the arrow keys and PageUp/PageDown, then the d-pad and the shoulder buttons. Each
## beat prints the focused control so the log reads as a transcript. Run it with Movie Maker
## (`--write-movie out.png --fixed-fps 10 --quit-after 150`). Settings go to a throwaway file.

const SCREEN := "res://ui/screens/settings_screen.tscn"
const FILE := "user://settings_navigation_capture.cfg"
const BEAT := 0.7

var _screen: SettingsScreen


func _ready() -> void:
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(SCREEN)
	await UIRouter.idle
	_screen = UIRouter.top() as SettingsScreen
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _run() -> void:
	await _beat("start")
	# Keyboard: down into the rows, page through every tab, page back.
	await _key(KEY_DOWN, "key-down-into-the-rows")
	await _key(KEY_PAGEDOWN, "key-page-down-to-audio")
	await _key(KEY_DOWN, "key-down-into-audio")
	await _key(KEY_PAGEDOWN, "key-page-down-to-accessibility")
	await _key(KEY_PAGEDOWN, "key-page-down-to-controls")
	await _key(KEY_PAGEUP, "key-page-up-to-accessibility")
	await _key(KEY_PAGEUP, "key-page-up-to-audio")
	await _key(KEY_PAGEUP, "key-page-up-to-video")
	# Gamepad: right shoulder to the end of the strip, d-pad into the rows, left shoulder back.
	await _pad(JOY_BUTTON_RIGHT_SHOULDER, "pad-rb-to-audio")
	await _pad(JOY_BUTTON_DPAD_DOWN, "pad-down-into-audio")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER, "pad-rb-to-accessibility")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER, "pad-rb-to-controls")
	await _pad(JOY_BUTTON_DPAD_DOWN, "pad-down-into-controls")
	await _pad(JOY_BUTTON_LEFT_SHOULDER, "pad-lb-to-accessibility")
	await _pad(JOY_BUTTON_LEFT_SHOULDER, "pad-lb-to-audio")
	await _pad(JOY_BUTTON_LEFT_SHOULDER, "pad-lb-to-video")


func _key(keycode: Key, label: String) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _beat(label)


func _pad(button: JoyButton, label: String) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _beat(label)


func _beat(label: String) -> void:
	await get_tree().create_timer(BEAT).timeout
	var focus := get_viewport().gui_get_focus_owner()
	print(
		"beat ",
		label,
		" frame ",
		Engine.get_process_frames(),
		" tab ",
		_screen._current,
		" focus ",
		focus.name if focus != null else "NONE",
		" (",
		focus,
		")"
	)
