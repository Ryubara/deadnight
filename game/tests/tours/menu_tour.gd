extends Control
## An unattended tour for captures: the main menu catches, then each item is opened with Enter and
## left with Esc, the way a player with a keyboard would.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTLE := 2.4
const HOLD := 0.9
## Items to open, top to bottom (Play, Settings, Credits).
const OPENED := 3


func _ready() -> void:
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(SETTLE)
	for i in OPENED:
		await _tap(KEY_ENTER)
		await UIRouter.idle
		await _wait(HOLD)
		await _tap(KEY_ESCAPE)
		await UIRouter.idle
		await _wait(HOLD)
		await _tap(KEY_DOWN)
		await _wait(HOLD * 0.5)
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
