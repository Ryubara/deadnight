extends Node
## Scripted capture of the menu with sound: keyboard focus moving over the items, a screen pushed
## and popped, a slider stepped. Every sound comes from the `UIAudio` hook the `Audio` service
## installs; nothing here plays a sound itself. Run with Movie Maker (`--write-movie out.png
## --fixed-fps 10`), which writes the mix to `out.wav` beside the frames.

const MENU := "res://ui/screens/main_menu.tscn"
const FILE := "user://audio_capture.cfg"


func _ready() -> void:
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	await UIRouter.idle
	await _beat("menu in", 1.8)
	UIInputMode.pointer = false
	await _focus("Settings")
	await _focus("Credits")
	await _focus("Settings")
	await _focus("Play")
	await _focus("Settings")
	_press("Settings")
	await _beat("settings pushed", 1.6)
	var screen := UIRouter.top() as SettingsScreen
	screen.select_tab(1)
	await _beat("audio tab", 0.8)
	var slider := screen._pages[1].get_child(1).control as UISlider
	slider.grab_focus()
	for value in [60, 50, 40, 60, 80]:
		slider.value = value
		await _beat("slider %d" % value, 0.35)
	await _beat("settle", 0.5)
	UIRouter.pop()
	await UIRouter.idle
	await _beat("back at the menu", 1.2)
	await _focus("Credits")
	_press("Credits")
	await _beat("credits burn in", 2.0)
	UIRouter.pop()
	await UIRouter.idle
	await _beat("end", 1.2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	print("voices started: ", Audio.started)
	get_tree().quit()


func _item(item_name: String) -> UIButton:
	return UIRouter.top().find_child(item_name, true, false) as UIButton


func _focus(item_name: String) -> void:
	_item(item_name).grab_focus()
	await _beat("focus " + item_name, 0.55)


func _press(item_name: String) -> void:
	_item(item_name).pressed.emit()


func _beat(label: String, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	print("beat ", label, " frame ", Engine.get_process_frames(), " voices ", Audio.active_voices())
