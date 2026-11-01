extends Control
## An unattended tour for the restyle captures: the demo menu, one shader transition (the film
## burn, closing over the menu and opening on the detail screen) and the component sheet. Pass
## `--tokens=res://path.tres` after `--` to restyle everything with that UITokens resource before
## the first screen, or add `--live` to swap it while the menu is already showing; no screen is
## edited either way. The log prints the frame each beat starts on (Movie Maker names the files by
## frame number).

const MENU := "res://addons/gds_ui/demo/demo_menu.tscn"
const HOLD := 1.2
## Menu entries before "Film burn": Fade, Slide.
const BURN_AT := 2
## Entries from "Film burn" down to "Component sheet": Iris, Component sheet.
const SHEET_AT := 2


func _ready() -> void:
	var restyle: UITokens
	var live := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tokens="):
			restyle = load(arg.get_slice("=", 1)) as UITokens
		live = live or arg == "--live"
	if restyle != null and not live:
		UITokens.set_active(restyle)
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(HOLD)
	_beat("menu")
	if restyle != null and live:
		UITokens.set_active(restyle)
		await _wait(HOLD)
		_beat("restyled live")
	for i in BURN_AT:
		await _tap(KEY_DOWN)
	await _wait(HOLD * 0.5)
	_beat("burn pressed")
	await _tap(KEY_ENTER)
	await UIRouter.idle
	await _wait(HOLD)
	_beat("detail")
	await _tap(KEY_ESCAPE)
	await UIRouter.idle
	await _wait(HOLD)
	for i in SHEET_AT:
		await _tap(KEY_DOWN)
	await _tap(KEY_ENTER)
	await UIRouter.idle
	await _wait(HOLD)
	_beat("sheet")
	get_tree().quit()


func _beat(label: String) -> void:
	print("BEAT %s frame %d" % [label, Engine.get_frames_drawn()])


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
