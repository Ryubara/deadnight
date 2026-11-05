extends Node
## Scripted capture of the Touch tab's aim assist toggle (#1279) at a phone's page: On by default,
## then Off, then On again. A phone's page of 844 x 390 CSS px is a 1688 x 780 window at pixel ratio
## 2: run it through the no-focus launcher with `--resolution 1688x780` and, after `--`,
## `--out=<folder>` (a PNG of the window for each state). Settings go to a throwaway file so the
## player's real ones are never touched.

const PIXEL_RATIO := 2.0

const SCREEN := "res://ui/screens/settings_screen.tscn"
const FILE := "user://settings_touch_assist_capture.cfg"
const TOUCH_TAB := 4
const ASSIST_ROW := 5

var _screen: SettingsScreen


func _ready() -> void:
	TouchMode.device_is_touch = true
	MenuScale.pixel_ratio = PIXEL_RATIO
	PageSize.css_override = Vector2(get_window().size) / PIXEL_RATIO
	Settings.path = FILE
	Settings.reset_defaults()
	UIRouter.reset(SCREEN)
	await UIRouter.idle
	_screen = UIRouter.top() as SettingsScreen
	_screen.select_tab(TOUCH_TAB, false)
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	await _beat("touch-tab", 1.5, out)
	var toggle := _toggle()
	UIInputMode.pointer = false
	toggle.grab_focus()
	await _beat("on-by-default", 1.5, out)
	toggle.button_pressed = false
	await _beat("off", 1.5, out)
	toggle.button_pressed = true
	await _beat("on-again", 1.5, out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _beat(label: String, seconds: float, out := "") -> void:
	await get_tree().create_timer(seconds).timeout
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, label])
	print(
		"beat ",
		label,
		" frame ",
		Engine.get_process_frames(),
		" assist ",
		Settings.get_value(SettingsService.TOUCH_AIM_ASSIST)
	)


func _toggle() -> UIToggle:
	return (_screen._pages[TOUCH_TAB].get_child(ASSIST_ROW) as UIRow).control as UIToggle
