extends Control
## Scripted capture for #10: the button prompt sheet, then the live hint line as the player's device
## changes (keyboard, a gamepad, a PlayStation pad, a finger). One PNG per beat at the window's
## real pixels. Run it through the no-focus launcher, not headless:
## `godot --path game res://tests/captures/gds_glyphs_tour.tscn --windowed --resolution 1280x720 --
## --out=<folder>`. Input is virtual (`UIInputMode.track` is fed events); the real mouse and
## keyboard are never captured.

const SHEET := "res://addons/gds_ui/demo/glyph_sheet.tscn"
const SETTLE := 0.8

var _out := "user://gds_glyphs"
var _shots := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	UIInputMode.reset()
	await get_tree().process_frame
	UIRouter.reset(SHEET, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(SETTLE)
	await _shot("keyboard")

	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	UIInputMode.track(press)
	await _wait(SETTLE)
	await _shot("gamepad")

	UIInputMode.family = UIInputMode.Family.PLAYSTATION
	await _wait(SETTLE)
	await _shot("playstation")

	UIInputMode.family = UIInputMode.Family.NINTENDO
	await _wait(SETTLE)
	await _shot("nintendo")

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	UIInputMode.track(touch)
	await _wait(SETTLE)
	await _shot("touch")
	UIInputMode.reset()
	get_tree().quit()


func _shot(beat: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var file := "%s/%02d_%s.png" % [_out, _shots, beat]
	get_viewport().get_texture().get_image().save_png(file)
	print("[gds-glyphs] ", file)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
