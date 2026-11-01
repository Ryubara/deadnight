extends Node
## Scripted capture of the settings screen: each tab at rest, then a control in keyboard focus and a
## value changed. Run it with Movie Maker (`--write-movie out.png --fixed-fps 10 --quit-after 200`).
## Settings go to a throwaway file so the player's real ones are never touched.

const SCREEN := "res://ui/screens/settings_screen.tscn"
const FILE := "user://settings_capture.cfg"

var _screen: SettingsScreen


func _ready() -> void:
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(SCREEN)
	await UIRouter.idle
	_screen = UIRouter.top() as SettingsScreen
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _run() -> void:
	# Video
	await _beat("video-rest", 1.2)
	UIInputMode.pointer = false
	_focus(0, 1)
	await _beat("video-focus", 1.0)
	_slider(0, 1).value = 65
	await _beat("video-changed", 1.2)
	# Audio
	_screen.select_tab(1)
	await _beat("audio-rest", 1.4)
	_focus(1, 1)
	await _beat("audio-focus", 1.0)
	_slider(1, 1).value = 35
	_slider(1, 2).value = 70
	await _beat("audio-changed", 1.2)
	# Accessibility
	_screen.select_tab(2)
	await _beat("access-rest", 1.4)
	_focus(2, 0)
	await _beat("access-focus", 1.0)
	_toggle(2, 0).button_pressed = true
	await _beat("access-on", 1.0)
	_toggle(2, 0).button_pressed = false
	_selector(2, 1).step(1)
	_focus(2, 1)
	await _beat("access-large", 1.4)
	_selector(2, 1).step(-1)
	# Controls
	_screen.select_tab(3)
	await _beat("controls-rest", 1.4)
	_focus(3, 0)
	_slider(3, 0).value = 1.8
	await _beat("controls-focus", 1.0)
	_toggle(3, 1).button_pressed = true
	_focus(3, 1)
	await _beat("controls-invert", 1.2)
	await _click_slider(_slider(3, 0), 0.6)


## Clicks the track at `ratio` of the thumb's travel, with a real mouse event, to prove that the
## engine's hit-testing and the drawn thumb agree: the value should land on the same ratio.
func _click_slider(slider: UISlider, ratio: float) -> void:
	var thumb := float(slider.get_theme_icon(&"grabber").get_width())
	var at := slider.get_global_rect().position
	at += Vector2(thumb * 0.5 + ratio * (slider.size.x - thumb), slider.size.y * 0.5)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
		await get_tree().process_frame
	var expected := slider.min_value + ratio * (slider.max_value - slider.min_value)
	print("click at ", ratio, " gives ", slider.value, " (expected about ", expected, ")")
	await _beat("controls-clicked", 1.0)


func _beat(label: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	print("beat ", label, " frame ", Engine.get_process_frames())


func _row(tab: int, row: int) -> UIRow:
	return _screen._pages[tab].get_child(row) as UIRow


func _focus(tab: int, row: int) -> void:
	_row(tab, row).control.grab_focus()


func _slider(tab: int, row: int) -> UISlider:
	return _row(tab, row).control as UISlider


func _toggle(tab: int, row: int) -> UIToggle:
	return _row(tab, row).control as UIToggle


func _selector(tab: int, row: int) -> UIOptionSelector:
	return _row(tab, row).control as UIOptionSelector
