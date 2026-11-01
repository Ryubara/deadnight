extends Control
## An unattended tour for captures: from the main menu, Play starts the night, the player walks and
## fires with the real input actions, Esc pauses, Resume goes on, and Back to the menu leaves.
## Not part of the game.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTLE := 2.4
const LOOK := 1.5
const WALK := 2.0
const STEP_KEYS := 0.4
## Seconds of play after the first round is called, so the dead have time to show.
const FIGHT := 1.0

var _night: Night


func _ready() -> void:
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(SETTLE)
	await _tap(KEY_ENTER)
	await UIRouter.idle
	_night = (UIRouter.top() as NightScreen).night
	await _night.ready_to_play
	await _wait(LOOK)
	Input.action_press(&"move_forward")
	await _wait(WALK)
	Input.action_release(&"move_forward")
	Input.action_press(&"sprint")
	Input.action_press(&"move_left")
	await _wait(WALK)
	Input.action_release(&"sprint")
	Input.action_release(&"move_left")
	_night.server.rules.apply(RulesAction.skip_break())
	Input.action_press(&"fire")
	await _wait(FIGHT)
	Input.action_release(&"fire")
	await _wait(LOOK)
	await _tap(KEY_ESCAPE)
	await _wait(LOOK)
	await _tap(KEY_ENTER)
	await _wait(LOOK)
	await _tap(KEY_ESCAPE)
	await _wait(STEP_KEYS)
	await _tap(KEY_DOWN)
	await _wait(STEP_KEYS)
	await _tap(KEY_ENTER)
	await UIRouter.idle
	await _wait(LOOK)
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
