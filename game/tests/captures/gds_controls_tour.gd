extends Control
## Scripted capture for #9: the form controls sheet at rest, then driven with real events (typing in
## the text field, ticking a box, walking the list, scrolling the area). One PNG per beat at the
## window's real pixels. Run it through the no-focus launcher, not headless:
## `godot --path game res://tests/captures/gds_controls_tour.tscn --windowed
## --resolution 1280x720 -- --out=<folder>`.
## Input is virtual (`Input.parse_input_event`); the real mouse is never captured.

const SHEET := "res://addons/gds_ui/demo/controls_sheet.tscn"
const SETTLE := 1.2

var _out := "user://gds_controls"
var _shots := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	UIRouter.reset(SHEET, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(SETTLE)
	var sheet := UIRouter.top() as ControlsSheet
	await _shot("rest")

	await _click(sheet.fields[0])
	for letter in "Ruby":
		await _type(letter)
	await _wait(0.4)
	await _shot("typing")

	await _click(sheet.check_boxes[0])
	await _wait(0.5)
	await _shot("ticked")

	sheet.lists[0].grab_focus()
	for _i in 2:
		await _tap(KEY_DOWN)
	await _wait(0.5)
	await _shot("list_down")

	sheet.lists[1].grab_focus()
	for _i in 4:
		await _tap(KEY_DOWN)
	await _wait(0.6)
	await _shot("long_list_scrolled")

	sheet.scroll.grab_focus()
	for _i in 6:
		await _tap(KEY_DOWN)
	await _wait(0.6)
	await _shot("scroll_area")
	get_tree().quit()


func _shot(beat: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var file := "%s/%02d_%s.png" % [_out, _shots, beat]
	get_viewport().get_texture().get_image().save_png(file)
	print("[gds-controls] ", file)


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


func _type(letter: String) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = letter.unicode_at(0) as Key
		event.unicode = letter.unicode_at(0)
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _click(control: Control) -> void:
	# Window pixels: the canvas position, scaled by the stretch the window applies.
	var at := (
		get_viewport().get_final_transform()
		* (control.get_global_transform_with_canvas() * (control.size * 0.5))
	)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
		await get_tree().process_frame
