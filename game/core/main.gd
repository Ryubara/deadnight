extends Control
## The game's root: starts the UI on the main menu. The film overlay lives beside it on a layer
## above the router, so grain and vignette cover every screen and every transition.
##
## Options after `--` on the command line (or in the page address on the web, `?connect=...`):
## `--server [--port N] [--seed N]` runs a game server instead of the game (headless, no menu),
## `--room CODE` (or `?room=CODE`) joins the night of an invite code, `--instance_id ID` (a Discord
## Activity) opens the menu and makes the voice channel's night ready for Play together, `--dev`
## shows the server address setting, `--stage` (`?stage`) opens only the menu's 3D stage for a
## frame-time run, `--stage=still` (`?stage=still`) its still level and `--stage=live`
## (`?stage=live`) its live level whatever the renderer (software ones start as a still),
## `--connect [ws://host:port]` goes from the menu straight into the night of that server,
## `--report [seconds]` prints a line of what the joined night looks like from here, and
## `--look N` (a preset) or `--look seed:N` (a random look) wears that look instead of the saved
## one, so two windows of one machine can differ.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const STAGE := "res://ui/screens/menu_stage_screen.tscn"

## The options the page or the command line gave; a test sets them before the node enters the tree.
var launch_args: PackedStringArray = OS.get_cmdline_user_args()


func _ready() -> void:
	var args := NetArgs.new(launch_args)
	if args.has("server"):
		_serve(args)
		return
	NightScreen.challenge_path = ChallengeSave.DEFAULT_PATH
	if args.has("look"):
		NightScreen.own_look = NightScreen.look_from_flag(args.get_string("look"))
	PhoneRender.apply(get_viewport())
	add_child(WebProbe.new())
	add_child(WebClipboard.new())  # copy and paste inside a Discord Activity's frame (#516)
	# Above the router, below the film: "turn your phone" when a touch device is held upright.
	var prompt_layer := CanvasLayer.new()
	prompt_layer.layer = TouchRotatePrompt.LAYER
	prompt_layer.add_child(TouchRotatePrompt.new())
	add_child(prompt_layer)
	# The same for a game in a frame without the focus: "click once to use a controller".
	var hint_layer := CanvasLayer.new()
	hint_layer.layer = ControllerHint.LAYER
	hint_layer.add_child(ControllerHint.new())
	add_child(hint_layer)
	await get_tree().process_frame
	if KillBench.requested():
		add_child(KillBench.new())
		return
	if args.has(AutopilotRun.KEY):
		add_child(AutopilotRun.new(args))
		return
	if args.has("stage"):
		var level := args.get_string("stage")
		var params := {"still": level == "still", "live": level == "live"}
		UIRouter.reset(STAGE, UITransition.Kind.CUT, params)
		return
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	TogetherScreen.dev_enabled = TogetherScreen.dev_enabled or args.has("dev")
	if args.has("room"):
		# An invite link (`?room=CODE`): the Play together screen joins that night at once.
		TogetherScreen.auto_code = args.get_string("room")
		UIRouter.push(TogetherScreen.SCREEN, UITransition.Kind.SLIDE)
	elif args.has("instance_id"):
		# Inside a Discord Activity: the menu first, like every platform. The night of the voice
		# channel is made ready in the background; Play together shows it at once.
		var room := ActivityRoom.new(args.get_string("instance_id"), TogetherScreen.backend_url())
		add_child(room)
		room.prepare()
	# `--bot` (or `?bot`) lets the autopilot play a night entered from a lobby: a browser probe with
	# several pages needs players that stay alive while the others load.
	LobbyScreen.play_as_bot = args.has("bot")
	if args.has("report"):
		var report := ClientReport.new()
		report.every = args.get_float("report", ClientReport.DEFAULT_EVERY)
		add_child(report)
	if args.has("connect"):
		var url := args.get_string("connect")
		NightScreen.join_url = JoinScreen.DEFAULT_URL if url == "true" else url
		NightScreen.join_as_bot = args.has("bot")
		UIRouter.push(NIGHT, UITransition.Kind.IRIS)


## The save is the real game's: leaving the root (a test frees it) puts the path away again.
func _exit_tree() -> void:
	NightScreen.challenge_path = ""


## A game server: with a backend (`ServerConfig`) the nights of its matches, else one night for
## up to eight players. The port is `--port`, else `$PORT` (Railway sets it), else the default.
func _serve(args: NetArgs) -> void:
	var from_environment := OS.get_environment("PORT")
	var port := args.get_int(
		"port", int(from_environment) if from_environment != "" else NetWire.DEFAULT_PORT
	)
	var config := ServerConfig.from_environment()
	if config.problem() != "":
		push_error("game server: " + config.problem())
		get_tree().quit(1)
		return
	if config.uses_backend():
		add_child(GameServer.make(config, port, args.get_int("seed", -1)))
		return
	var host := NightHost.new()
	host.port = port
	host.seed_value = args.get_int("seed", -1)
	host.match_settings = _match_from(args)
	add_child(host)


## The match settings a game server is started with: `--count 2`, `--max-alive 12`, `--break 10`,
## `--bots 2` (each left out is the default), pulled into their bounds.
func _match_from(args: NetArgs) -> MatchSettings:
	var settings := MatchSettings.new()
	settings.count_multiplier = args.get_float("count", settings.count_multiplier)
	settings.max_alive = args.get_int("max-alive", settings.max_alive)
	settings.break_seconds = args.get_float("break", settings.break_seconds)
	settings.bots = args.get_int("bots", settings.bots)
	return settings.clamped()
