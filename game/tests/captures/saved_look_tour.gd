extends Node
## Captures a look saved in the wardrobe twice: on the wardrobe's turntable, and on the player in
## the night from the shoulder camera, so the two can be set side by side (#301). Not part of the
## game.
## Settings go to a throwaway file. Run it with Movie Maker, 10 fps:
##
##     godot --path game res://tests/captures/saved_look_tour.tscn --write-movie <abs>/look.png \
##         --fixed-fps 10 --quit-after 300
##
## Prints `SHOT <name> <frame>` for the wardrobe seen from the front and the back and for the night:
## the frames to read. `-- --look=<spec>` dresses it in another look (`soldier_turntable.gd`'s form:
## `10:torso=usher,neck=lanyard/primary=7,accent=10`).

const MENU := "res://ui/screens/main_menu.tscn"
const WARDROBE := "res://ui/screens/customize_screen.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const FILE := "user://saved_look_capture.cfg"
## Frames the wardrobe and the night each stand before the shot.
const SETTLE_FRAMES := 25
const SHOT_FRAMES := 25
const LOOK_SPEC := preload("res://tests/captures/soldier_turntable.gd")


func _ready() -> void:
	Settings.path = FILE
	Settings.reset_defaults()
	LookStore.save_look(_look())
	await _wardrobe()
	await _night()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


## A look no preset has: a red letterman jacket, a cream cap and trousers, yellow trim.
func _look() -> CharacterLook:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--look="):
			return LOOK_SPEC.parse_look(arg.substr(7))
	var look := CharacterLook.from_preset(2)
	look.parts[&"torso"] = &"letterman"
	look.parts[&"headwear"] = &"ballcap"
	look.parts[&"hair"] = &"flattop"
	look.colours[&"primary"] = 7
	look.colours[&"secondary"] = 1
	look.colours[&"accent"] = 10
	return look


func _wardrobe() -> void:
	UIMotion.reduced = true  # the turntable stands still, so the shot is the angle set here
	UIRouter.reset(WARDROBE, UITransition.Kind.CUT, {"seed": 1958})
	await UIRouter.idle
	var screen := UIRouter.top() as CustomizeScreen
	for shot: Dictionary in [
		{"name": "wardrobe_front", "yaw": 0.0}, {"name": "wardrobe_back", "yaw": PI}
	]:
		screen.preview().angle = shot["yaw"]
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
		print("SHOT ", shot["name"], " ", Engine.get_process_frames())
		for _i in SHOT_FRAMES:
			await get_tree().process_frame
	UIMotion.reduced = false


func _night() -> void:
	NightScreen.arrival_enabled = false  # the shot is the player's camera, not the helicopter drop
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	print("SHOT night ", Engine.get_process_frames())
	for _i in SHOT_FRAMES:
		await get_tree().physics_frame
