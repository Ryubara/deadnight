extends Node
## The HUD of a full room, for captures (#690): one person on a game server of this process and
## seven of the server's bots in the other seats, a couple of them downed, the dead about, and the
## picture taken of the window, with the scoreboard held up or not. Not part of the game.
##
##     godot --path game res://tests/captures/players8_hud.tscn --resolution 1280x720
##         -- --out=<abs>/hud8.png [--board] [--touch [--notch]] [--play=SECONDS] [--people=N]
##
## `--people` is how many of the eight seats are people (default 1; they are autopilots, so more
## than one is heavier). `--play` is the seconds of night first (default 25, real time).

const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const SETTLE_FRAMES := 12

var _hud: Hud
var _controls: TouchControls
var _night: Night
var _host: NightHost
var _extra: Array[Night] = []


func _ready() -> void:
	var args := NetArgs.new()
	var out := args.get_string("out")
	var touch := args.has("touch")
	TouchMode.device_is_touch = touch
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(_hud)
	if touch:
		_controls = TouchControls.new()
		_controls.state = _hud.state
		if args.has("notch"):
			_controls.insets_override = NOTCH
		_controls.safe_insets_changed.connect(_fit_hud)
		layer.add_child(_controls)
	var people := clampi(args.get_int("people", 1), 1, NightHost.MAX_PLAYERS)
	await _play(people, args.get_float("play", 25.0))
	if args.has("board"):
		await _show_the_board(touch)
	else:
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
	print(
		"players ",
		_hud.state.team.size(),
		" boxes ",
		_hud.points.shown.size(),
		" column ",
		_hud.points.size,
		" rows ",
		_hud.scoreboard.rows_text.size()
	)
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()


func _play(people: int, seconds: float) -> void:
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	var settings := MatchSettings.new()
	settings.bots = NightHost.MAX_PLAYERS - people
	_host.match_settings = settings
	_world().add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	_night = Night.new()
	_night.hud = _hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start_remote(url, Night.Mode.AUTOPILOT, 30.0)
	for _i in people - 1:
		var other := Night.new()
		_world().add_child(other)
		await other.start_remote(url, Night.Mode.AUTOPILOT, 30.0)
		_extra.append(other)
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	while _host.server.rules.night_time < seconds and not _night.state.over:
		await get_tree().physics_frame
	# Two of the others are down, one of them for good, as in a bad moment.
	var rules := _host.server.rules
	_host._collect(rules.apply(RulesAction.blow(4, 99999.0)))
	_host._collect(rules.apply(RulesAction.blow(7, 99999.0)))
	for _i in 90:
		await get_tree().physics_frame


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _show_the_board(touch: bool) -> void:
	if touch:
		var circle := _controls.button_circle(TouchLayout.SCOREBOARD)
		var press := InputEventScreenTouch.new()
		press.index = 0
		press.position = get_viewport().get_final_transform() * (circle[&"centre"] as Vector2)
		press.pressed = true
		Input.parse_input_event(press)
	else:
		Input.action_press(Hud.SCOREBOARD_ACTION)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _fit_hud(insets: Vector4) -> void:
	_hud.offset_left = insets.x
	_hud.offset_top = insets.y
	_hud.offset_right = -insets.z
	_hud.offset_bottom = -insets.w
