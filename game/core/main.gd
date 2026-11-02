extends Control
## The game's root: starts the UI on the main menu. The film overlay lives beside it on a layer
## above the router, so grain and vignette cover every screen and every transition.
##
## Options after `--` on the command line (or in the page address on the web, `?connect=...`):
## `--server [--port N] [--seed N]` runs a game server instead of the game (headless, no menu), and
## `--connect [ws://host:port]` goes from the menu straight into the night of that server, and
## `--report [seconds]` prints a line of what the joined night looks like from here, and
## `--look N` (a preset) or `--look seed:N` (a random look) wears that look instead of the saved
## one, so two windows of one machine can differ.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"


func _ready() -> void:
	var args := NetArgs.new()
	if args.has("server"):
		_serve(args)
		return
	if args.has("look"):
		NightScreen.own_look = NightScreen.look_from_flag(args.get_string("look"))
	add_child(WebProbe.new())
	# Above the router, below the film: "turn your phone" when a touch device is held upright.
	var prompt_layer := CanvasLayer.new()
	prompt_layer.layer = TouchRotatePrompt.LAYER
	prompt_layer.add_child(TouchRotatePrompt.new())
	add_child(prompt_layer)
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
	if args.has("report"):
		var report := ClientReport.new()
		report.every = args.get_float("report", ClientReport.DEFAULT_EVERY)
		add_child(report)
	if args.has("connect"):
		var url := args.get_string("connect")
		NightScreen.join_url = JoinScreen.DEFAULT_URL if url == "true" else url
		NightScreen.join_as_bot = args.has("bot")
		UIRouter.push(NIGHT, UITransition.Kind.IRIS)


## A game server: one night for up to four players. The port is `--port`, else `$PORT` (Railway
## sets it), else the default.
func _serve(args: NetArgs) -> void:
	var host := NightHost.new()
	var from_environment := OS.get_environment("PORT")
	host.port = args.get_int(
		"port", int(from_environment) if from_environment != "" else NetWire.DEFAULT_PORT
	)
	host.seed_value = args.get_int("seed", -1)
	add_child(host)
