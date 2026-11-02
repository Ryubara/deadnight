extends Control
## Scripted capture for #85: the main menu pressed during its entrance, then settled, and the
## credits with forty lines, at the window's real 1280 x 720 pixels (Movie Maker always records the
## project's 1920 x 1080). Run it through the no-focus launcher, not headless:
## `godot --path game res://tests/captures/menu_polish_tour.tscn --windowed --resolution 1280x720 --
## --label=before|after --out=<folder>`. One PNG per beat, with a caption that names the beat and
## the focused control.

const MENU := "res://ui/screens/main_menu.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const LINES := 40
## A key press and a click that land inside the 0.55 s entrance.
const EARLY := 0.2

var _caption := Label.new()
var _label := ""
var _out := "user://menu_polish"
var _shots := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_caption.position = Vector2(16, 12)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)
	await get_tree().process_frame
	await _menu()
	await _credits()
	get_tree().quit()


func _menu() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(EARLY)
	await _tap(KEY_DOWN)
	await _tap(KEY_ENTER)
	var play := UIRouter.top().find_child("Play", true, false) as Control
	await _click(play)
	await _wait(0.1)
	await _note("menu, a key press and a click at %.1f s" % EARLY)
	await _wait(1.4)
	await _note("menu, entrance over")
	await _tap(KEY_DOWN)
	await _wait(0.4)
	await _note("menu, Down pressed")


func _credits() -> void:
	# The credits at the window's real pixels: 720 rows, not the stretched 1080 the menu has, which
	# is the tighter case.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var list := CreditsList.new()
	var lines := PackedStringArray(["# Made by"])
	for i in LINES - 1:
		lines.append("Credit line %d - what they did" % (i + 1))
	list.lines = lines
	var screen := (load(CREDITS) as PackedScene).instantiate() as CreditsScreen
	screen.credits = list
	UIRouter.reset(screen, UITransition.Kind.CUT)
	await UIRouter.idle
	await _wait(1.0)
	await _note("credits, %d lines" % LINES)
	for _i in 6:
		await _tap(KEY_UP)
	await _wait(0.4)
	await _note("credits, Up pressed")
	for _i in 12:
		await _tap(KEY_DOWN)
	await _wait(0.4)
	await _note("credits, scrolled down")


func _note(beat: String) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var text := "%s | %s | focus %s" % [_label, beat, _describe(focus)]
	_caption.text = text
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shots += 1
	var file := "%s/%s_%02d.png" % [_out, _label, _shots]
	get_viewport().get_texture().get_image().save_png(file)
	print("[menu-polish] %s: %s" % [file, text])


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


func _click(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
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


func _describe(control: Control) -> String:
	if control == null:
		return "none"
	return control.text if control is Button else str(control.name)
