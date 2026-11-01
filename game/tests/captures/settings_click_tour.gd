extends Node
## Capture of the settings screen being clicked through, tab by tab, with a real mouse click for
## each (`Input.parse_input_event`, so it reaches the screen before the frame's physics step the
## way a player's click does). The physics rate is lowered to one step a second, which is what a
## fast display gives most frames: no step, so a container has not sorted a page just shown. Run it
## with Movie Maker (`--write-movie out.png --fixed-fps 10 --quit-after 150`); each tab is held for
## a second after its click.

const SCREEN := "res://ui/screens/settings_screen.tscn"
const FILE := "user://settings_click_capture.cfg"
const ORDER: Array[int] = [4, 2, 3, 1, 4]

var _screen: SettingsScreen


func _ready() -> void:
	Engine.physics_ticks_per_second = 1
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(SCREEN)
	await UIRouter.idle
	_screen = UIRouter.top() as SettingsScreen
	await get_tree().create_timer(1.0).timeout
	for tab in ORDER:
		_click(_screen._tab_buttons[tab])
		await get_tree().create_timer(1.0).timeout
		print("tab ", tab, " rows at ", _row_ys(_screen._pages[_screen._current]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _click(button: Control) -> void:
	var canvas_point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var at := button.get_viewport().get_final_transform() * canvas_point
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)


func _row_ys(page: Control) -> Array[float]:
	var ys: Array[float] = []
	for row in page.get_children():
		ys.append(snappedf((row as Control).position.y, 0.1))
	return ys
