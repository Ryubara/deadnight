extends Control
## The game's root: starts the UI on the main menu. The film overlay lives beside it on a layer
## above the router, so grain and vignette cover every screen and every transition.
##
## Options after `--` on the command line (or in the page address on the web, `?connect=...`):
## `--server [--port N] [--seed N]` runs a game server instead of the game (headless, no menu), and
## `--connect [ws://host:port]` goes from the menu straight into the night of that server.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"


func _ready() -> void:
	var args := NetArgs.new()
	if args.has("server"):
		_serve(args)
		return
	add_child(WebProbe.new())
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)
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
