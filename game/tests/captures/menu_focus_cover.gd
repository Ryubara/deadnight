extends Control
## Scripted capture for #190: the main menu entered normally takes the gamepad focus on Play, and a
## screen pushed over the menu before its items have risen keeps its own focus, so A presses the
## screen's button rather than the covered menu's Play. Run it with Movie Maker
## (`--write-movie out.png --fixed-fps 10 --quit-after 160 -- --label=before|after`); a caption
## names the top screen and the focused control, and the log prints them at each beat.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
## A click that lands before the 0.55 s entrance has ended.
const EARLY_PUSH := 0.15
const BEAT := 1.1

var _caption := Label.new()
var _name := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			_name = arg.get_slice("=", 1)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_caption.position = Vector2(24, 24)
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(_caption)
	await get_tree().process_frame
	await _normal_entry()
	await _covered_entry()
	get_tree().quit()


func _normal_entry() -> void:
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _wait(BEAT)
	_note("normal entry")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _wait(0.3)
	_note("normal entry, d-pad down")


func _covered_entry() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(EARLY_PUSH)
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(BEAT)
	_note("settings pushed at %.2f s" % EARLY_PUSH)
	await _pad(JOY_BUTTON_A)
	await _wait(BEAT)
	_note("after A")


func _note(beat: String) -> void:
	var owner := get_viewport().gui_get_focus_owner()
	var text := "%s | %s | top %s | focus %s" % [_name, beat, UIRouter.top().name, _describe(owner)]
	_caption.text = text
	print("[menu-focus] ", text)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _describe(control: Control) -> String:
	if control == null:
		return "none"
	return control.text if control is Button else control.name
