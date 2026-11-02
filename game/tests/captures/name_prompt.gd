extends Node
## A still of the Play together name prompt, as a player with no name first sees it, at the window's
## real pixel size. Run through the no-focus launcher, not headless:
## `godot --path game res://tests/captures/name_prompt.tscn --windowed --resolution 960x540 --
## --out=<png> [--typed=<name>]`. Settings go to a throwaway file.

const SCREEN := "res://ui/screens/together_screen.tscn"
const FILE := "user://name_prompt_capture.cfg"
## Seconds a screen is left to bring its items in and settle its springs.
const SETTLE := 2.0


func _ready() -> void:
	Settings.path = FILE
	Settings.reset_defaults()
	Settings.set_value(SettingsService.PROFILE_CACHE, "")
	TogetherScreen.name_skipped = false
	UIRouter.reset(SCREEN)
	await UIRouter.idle
	var screen := UIRouter.top() as TogetherScreen
	screen.call("_ask_name")
	var args := _args()
	if args.has("typed"):
		screen.name_field.text = str(args["typed"])
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var out := str(args.get("out", "user://name_prompt.png"))
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " window ", get_window().size)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var text := arg.trim_prefix("--")
		var parts := text.split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
