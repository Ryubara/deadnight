extends Node
## The end of a night, for a video (Deadnight #973): the real night screen over a solo night on a
## map, the dead let loose for a while, then everyone down, and the whole sequence saved frame by
## frame: the pull-back from the player's own camera, the cuts between the map's angles, the board
## with every player, the server's clock counting down, and the way back to the screen the night
## came from. The frames are fixed (`--fixed-fps 10`) and it quits itself:
##
## `gds godot -- --path game res://tests/captures/end_sequence_tour.tscn --resolution 1280x720
## --fixed-fps 10 --quit-after 700 -- --map=small_indoor --shots=<folder>`
##
## Arguments after `--`: `--map=ID` (default `drive_in`), `--bots=N` (default 3: a board with
## several players), `--touch` (a phone: use `--resolution 2340x1080`), `--play=S` (game seconds
## the dead are let loose before the end, default 40), `--keep=S` (seconds saved after the clock
## is out, default 1), `--shots=FOLDER` (the window's picture of each frame as a JPEG: a Movie
## Maker video is always the project's 1920 x 1080, whatever the window), `--probe` (print the
## canvas and the board and quit).

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const FILE := "user://end_sequence_capture.cfg"
const SEED := 11

var _args := {}
var _frames := 0
var _screen: NightScreen


func _ready() -> void:
	_args = _parse_args()
	Settings.path = FILE
	Settings.reset_defaults()
	TouchMode.device_is_touch = _args.has("touch")
	var settings := MatchSettings.new()
	settings.map = str(_args.get("map", "drive_in"))
	settings.bots = int(_args.get("bots", 3))
	settings.bot_skill = 2
	NightScreen.match_settings = settings.clamped()
	NightScreen.start_seed = SEED
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	var night := _screen.night
	await night.ready_to_play
	# The machine's real mouse must not turn the camera of a capture.
	night.player().local_input = false
	await get_tree().create_timer(2.5).timeout
	# The night goes on for a while: the dead come for the player and the bots.
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	var ticks := int(float(_args.get("play", 40.0)) / Night.STEP)
	for _i in ticks:
		night.tick()
	print("end: the night is at round ", night.state.round_number())
	# The end: everyone goes down, as the server's own events say.
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	await get_tree().process_frame
	print("end: the night is over ", night.state.over)
	var window := get_window()
	var board: Control = _screen.get_node("EndBoard")
	print(
		"end: canvas ",
		get_viewport().get_visible_rect().size,
		" window ",
		window.size,
		" scale ",
		window.content_scale_factor,
		" board ",
		board.get_global_rect()
	)
	if _args.has("probe"):
		get_tree().quit()
		return
	var began := Engine.get_process_frames()
	_save()
	while not night.state.closed:
		await get_tree().process_frame
		_save()
	print("end: closed after ", Engine.get_process_frames() - began, " frames")
	var after := int(float(_args.get("keep", 1.0)) * 10.0)
	for _i in after:
		await get_tree().process_frame
		_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


## With `--shots=FOLDER`: the window's picture as it is, one numbered JPEG a frame (the window is
## the size asked for with `--resolution`; a Movie Maker video is the project's size instead).
func _save() -> void:
	if not _args.has("shots"):
		return
	DirAccess.make_dir_recursive_absolute(str(_args["shots"]))
	var image := get_viewport().get_texture().get_image()
	image.save_jpg("%s/s%04d.jpg" % [_args["shots"], _frames], 0.92)
	_frames += 1


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
