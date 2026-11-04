extends Node
## The end of a night, for a video (Deadnight #973): the real night screen over a solo night on a
## map, the dead let loose for a few seconds, then everyone down, and the whole sequence recorded:
## the pull-back from the player's own camera, the cuts between the map's angles, the board with
## every player, the server's clock counting down, and the way back to the screen the night came
## from. Run it in Movie Maker so the frames are fixed (`--fixed-fps 10`); it quits itself,
## `--quit-after` is only a bound:
##
## `gds godot -- --path game res://tests/captures/end_sequence_tour.tscn --resolution 1280x720
## --write-movie <folder>/frame.png --fixed-fps 10 --quit-after 400 -- --map=small_indoor`
##
## Arguments after `--`: `--map=ID` (default `drive_in`), `--bots=N` (default 3: a board with
## several players), `--touch` (a phone: use `--resolution 1688x780`), `--play=S` (game seconds
## the dead are let loose before the end, default 10), `--keep=S` (seconds filmed after the clock
## is out, default 1).

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const FILE := "user://end_sequence_capture.cfg"
const SEED := 11

var _args := {}
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
	night.server.rules.apply(RulesAction.skip_break())
	var ticks := int(float(_args.get("play", 10.0)) / Night.STEP)
	for _i in ticks:
		night.tick()
	print("end: the night is at round ", night.state.round_number())
	# The end: everyone goes down, as the server's own events say.
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	await get_tree().process_frame
	print("end: the night is over ", night.state.over)
	var began := Engine.get_process_frames()
	while not night.state.closed:
		await get_tree().process_frame
	print("end: closed after ", Engine.get_process_frames() - began, " frames")
	var after := int(float(_args.get("keep", 1.0)) * 10.0)
	for _i in after:
		await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _parse_args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
