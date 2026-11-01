extends Control
## Capture: the main menu with Customize in keyboard focus, then opened with Enter and left with
## Esc.
## Run it with Movie Maker (`--write-movie out.png --fixed-fps 10 --quit-after 120`).

const MENU := "res://ui/screens/main_menu.tscn"


func _ready() -> void:
	Settings.path = "user://menu_customize_capture.cfg"
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(2.4)
	await _tap(KEY_DOWN)
	await _wait(0.8)
	print("beat menu frame ", Engine.get_process_frames())
	await _tap(KEY_ENTER)
	await _wait(0.25)
	print("beat sliding frame ", Engine.get_process_frames())
	await UIRouter.idle
	await _wait(1.5)
	print("beat wardrobe frame ", Engine.get_process_frames())
	await _tap(KEY_ESCAPE)
	await UIRouter.idle
	await _wait(1.0)
	print("beat back frame ", Engine.get_process_frames())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _tap(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
