extends Node
## The scoreboard over a night, for captures: bots play for a while (alone, or with up to three
## more on a game server of this process), a couple of players are taken down, and the board is
## held up the way a player does it. Not part of the game.
##
##     godot --path game res://tests/captures/scoreboard_tour.tscn --resolution 1920x1080
##         -- --out=<abs>/scoreboard.png [--players=N] [--play=SECONDS] [--touch [--notch]]
##
## `--play` is the seconds of night the bots play first (60 alone, where the night is sped up, and
## 45 in real time with others). `--touch` shows the touch controls and holds the scoreboard button
## with a touch; `--notch` leaves room for a notch. The picture is the window's.

const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const SETTLE_FRAMES := 12

var _out := ""
var _players := 1
var _touch := false
var _hud: Hud
var _controls: TouchControls
var _night: Night
var _host: NightHost
var _bots: Array[Night] = []


func _ready() -> void:
	var args := NetArgs.new()
	_out = args.get_string("out")
	_players = clampi(args.get_int("players", 1), 1, 4)
	_touch = args.has("touch")
	var play := args.get_float("play", 60.0 if _players == 1 else 45.0)
	TouchMode.device_is_touch = _touch
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(_hud)
	if _touch:
		_controls = TouchControls.new()
		_controls.state = _hud.state
		if args.has("notch"):
			_controls.insets_override = NOTCH
		_controls.safe_insets_changed.connect(_fit_hud)
		layer.add_child(_controls)
	if _players == 1:
		await _play_alone(play)
	else:
		await _play_together(play)
	await _show_the_board()
	if _out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out)
		print("SAVED ", _out)
	get_tree().quit()


func _play_alone(seconds: float) -> void:
	_night = Night.new()
	_night.hud = _hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT)
	_night.ticks_per_frame = 20
	var rules := _night.server.rules
	while rules.night_time < seconds and not _night.state.over:
		await get_tree().physics_frame
	_night.ticks_per_frame = 1
	# Back to real time: the HUD reads the next frames.
	await _settle()


func _play_together(seconds: float) -> void:
	var server_world := _world()
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	server_world.add_child(_host)
	while not _host.serving:
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _host.listener.port()
	_night = Night.new()
	_night.hud = _hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start_remote(url, Night.Mode.AUTOPILOT, 30.0)
	for _i in _players - 1:
		var bot := Night.new()
		_world().add_child(bot)
		await bot.start_remote(url, Night.Mode.AUTOPILOT, 30.0)
		_bots.append(bot)
	_host._collect(_host.server.rules.apply(RulesAction.skip_break()))
	while _host.server.rules.night_time < seconds and not _night.state.over:
		await get_tree().physics_frame
	_take_down(2, true)
	if _players >= 3:
		_take_down(3, false)
	await _settle()


## A private world for a node that has its own physics and navigation.
func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


## A blow that downs the player, sent to everyone like any event of the night; `up` gets them on
## their feet again (the board then shows the down in the count only).
func _take_down(player_id: int, up: bool) -> void:
	var rules := _host.server.rules
	_host._collect(rules.apply(RulesAction.blow(player_id, 99999.0)))
	if up:
		_host._collect(rules.apply(RulesAction.set_downed(player_id, false)))


func _settle() -> void:
	for _i in 90:
		await get_tree().physics_frame


func _show_the_board() -> void:
	if _touch:
		var circle := _controls.button_circle(TouchLayout.SCOREBOARD)
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = get_viewport().get_final_transform() * (circle[&"centre"] as Vector2)
		touch.pressed = true
		Input.parse_input_event(touch)
	else:
		Input.action_press(Hud.SCOREBOARD_ACTION)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	print(
		"board shown: ",
		_hud.scoreboard.visible,
		" rows ",
		_hud.scoreboard.rows_text,
		" clock ",
		_hud.scoreboard.clock_text
	)


func _fit_hud(insets: Vector4) -> void:
	_hud.offset_left = insets.x
	_hud.offset_top = insets.y
	_hud.offset_right = -insets.z
	_hud.offset_bottom = -insets.w
