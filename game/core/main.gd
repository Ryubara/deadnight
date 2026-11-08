extends Control
## The game's root: starts the UI on the main menu. The film overlay lives beside it on a layer
## above the router, so grain and vignette cover every screen and every transition.
##
## Options after `--` on the command line (or in the page address on the web, `?connect=...`):
## `--server [--port N] [--seed N]` runs a game server instead of the game (headless, no menu),
## `--room CODE` (or `?room=CODE`) joins the night of an invite code, `--instance_id ID` (a Discord
## Activity) marks the run as an Activity: the same menu and screens as the website, signed in with
## Discord in the background and no lobby made until the player asks (#1178), `--dev`
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

## What this put in the router's layer, taken out again when it goes.
var _overlays: Array[Node] = []


func _ready() -> void:
	var args := NetArgs.new(launch_args)
	if args.has("server"):
		_serve(args)
		return
	NightScreen.challenge_path = ChallengeSave.DEFAULT_PATH
	if args.has("arrival") or args.has("noarrival"):
		NightScreen.arrival_enabled = args.has("arrival") and not args.has("noarrival")
	NightScreen.profile_path = ProfileSave.DEFAULT_PATH
	ProfileUplink.sync_path = ProfileSave.DEFAULT_PATH
	ChallengeUplink.sync_path = ChallengeSave.DEFAULT_PATH
	ProgressSeen.path = ProgressSeen.DEFAULT_PATH
	if args.has("look"):
		NightScreen.own_look = NightScreen.look_from_flag(args.get_string("look"))
	PhoneRender.apply(get_viewport())
	add_child(WebProbe.new())
	add_child(WebClipboard.new())  # copy and paste inside a Discord Activity's frame (#516)
	add_child(WebKeyboard.new())  # the phone's keyboard for a text field (#1183)
	add_child(KeyboardLift.new())  # and the field kept above it
	_add_overlays()
	await get_tree().process_frame
	TogetherApi.activity = args.has("instance_id")
	# A returning Guest, or an Activity (with Discord), signs in in the background, so a Solo night
	# earns XP (#1122) and Play together has its session; the menu does not wait for it.
	StartupSignIn.begin(self)
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


## The save is the real game's: leaving the root (a test frees it) puts the path away again, and the
## overlays it put in the router's layer go.
func _exit_tree() -> void:
	NightScreen.challenge_path = ""
	NightScreen.profile_path = ""
	ProfileUplink.sync_path = ""
	ChallengeUplink.sync_path = ""
	ProgressSeen.path = ""
	for overlay in _overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_overlays.clear()


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
	var settings := args.match_settings()
	var wrong := MatchSettings.problem(settings.to_dict())
	if not wrong.is_empty():
		# A value the game does not take stops the server; it never starts a night on other rules.
		push_error("game server: the option for '%s' is not one the game takes" % wrong)
		get_tree().quit(1)
		return
	var host := NightHost.new()
	host.port = port
	host.seed_value = args.get_int("seed", -1)
	host.match_settings = settings
	add_child(host)


## The controller hint, "turn your phone", the menu's popup lane and the film (grain and vignette
## over everything) go in the router's own canvas layer, after its screens and its transition, in
## that order. A canvas layer is a canvas pass of its own, empty or not, and the Compatibility
## renderer ends each pass with a fence sync whose WebGL id the web page keeps until it closes
## (#883): three layers of overlays were three fences a frame, a third of the page's remaining heap
## growth.
func _add_overlays() -> void:
	var film := FilmOverlay.new()
	film.name = "Film"
	for overlay: Node in [ControllerHint.new(), TouchRotatePrompt.new(), MenuPopups.new(), film]:
		UIRouter.add_child(overlay)
		_overlays.append(overlay)
