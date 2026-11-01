extends Control
## An unattended tour for captures: walks the menu with the keyboard, opens every transition
## with Enter, goes back with Esc, then shows the component sheet and quits.

const MENU := "res://addons/gds_ui/demo/demo_menu.tscn"
const HOLD := 0.45
const KINDS := 4


func _ready() -> void:
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(HOLD)
	for i in KINDS:
		await _tap(KEY_ENTER)
		await UIRouter.idle
		await _wait(HOLD)
		await _tap(KEY_ESCAPE)
		await UIRouter.idle
		await _wait(HOLD)
		await _tap(KEY_DOWN)
		await _wait(HOLD * 0.6)
	await _tap(KEY_ENTER)
	await UIRouter.idle
	await _wait(1.2)
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
