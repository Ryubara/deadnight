extends Node
## The level and icon beside a name in the night (#1077): a game server of this process with the
## tickets the backend signs (`TicketMaker`: the level and the icon in the claims), the viewer and
## three allies standing in a row `--distance` metres in front of the viewer's camera, the HUD of
## the viewer drawn over the 3D and the picture taken of the window. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/level_tags_night.tscn --resolution 1280x720
##         -- --out=<abs>/tags.png [--distance=5] [--yaw=0] [--shift=0] [--touch [--notch]]
##         [--board] [--report] [--bot] [--off] [--down]
##
## `--yaw` is the way the viewer faces, radians (0 is toward the concession stand), `--shift` moves
## the row to the right, metres. `--bot` makes the third ally a bot (it has no level). `--board`
## holds the scoreboard up and `--report` shows the night report. `--off` turns the setting that
## shows levels off. `--down` knocks the second ally down. `--touch` draws the phone layout.

const SECRET := "test-ticket-secret-of-32-characters!"
const SERVER_ID := "gs-capture"
const MATCH := "tags"
const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
const SETTLE_FRAMES := 30
## Who stands where, in metres to the right of the camera's line.
const SIDES: Array[float] = [-2.2, 0.0, 2.2]
const NAMES: Array[String] = ["RUBY", "MOE", "DEE", "CAL"]
const LEVELS: Array[int] = [12, 7, 23, 48]

var _hud: Hud
var _controls: TouchControls
var _server: GameServer
var _night: Night
var _others: Array[Night] = []


func _ready() -> void:
	var args := NetArgs.new()
	var touch := args.has("touch")
	TouchMode.device_is_touch = touch
	if args.has("off"):
		Settings.set_value(SettingsService.SHOW_LEVELS, false)
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
	await _join(args.has("bot"))
	var room := _server.room_of_match(MATCH)
	_stand(
		room,
		args.get_float("distance", 5.0),
		args.get_float("yaw", 0.0),
		args.get_float("shift", 0.0),
		args.has("bot")
	)
	if args.has("down"):
		var ids: Array = room.server.rules.players.keys()
		ids.sort()
		room._collect(room.server.rules.apply(RulesAction.set_downed(ids[2], true)))
	if args.has("board"):
		Input.action_press(Hud.SCOREBOARD_ACTION)
	if args.has("report"):
		# The board of the end of a night over the picture, as the night screen shows it.
		var report := HudEndBoard.new()
		_hud.get_parent().add_child(report)
		report.set_anchors_preset(Control.PRESET_FULL_RECT)
		report.show_results(_hud.state, "BACK IN", "Leave")
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	await get_tree().process_frame
	var markers := _hud.markers
	for id: StringName in markers.tags:
		print("tag ", id, " ", markers.tags[id])
	print("levels the viewer's table holds: ", _night.state.levels)
	var out := args.get_string("out")
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()


func _join(with_bot: bool) -> void:
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 2
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = 7
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_world().add_child(_server)
	while not _server.listener.is_listening():
		await get_tree().physics_frame
	var url := "ws://127.0.0.1:%d" % _server.listener.port()
	var settings := MatchSettings.new()
	settings.bots = 1 if with_bot else 0
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	var viewer := WebSocketLink.new()
	viewer.ticket = _ticket(0, settings)
	if not await _night.start_remote(url, Night.Mode.HUMAN, 30.0, viewer):
		push_error("the viewer could not join")
		get_tree().quit(1)
		return
	for i in range(1, 4):
		if with_bot and i == 3:
			break
		var other := Night.new()
		_world().add_child(other)
		var link := WebSocketLink.new()
		link.ticket = _ticket(i, settings)
		await other.start_remote(url, Night.Mode.MANUAL, 30.0, link)
		_others.append(other)


func _ticket(index: int, settings: MatchSettings) -> String:
	var level := LEVELS[index]
	var claims := {"xp": LevelCurve.xp_for(level)}
	return TicketMaker.make(
		SECRET,
		SERVER_ID,
		MATCH,
		"user-%d" % index,
		NAMES[index].capitalize(),
		60,
		settings.to_dict(),
		null,
		claims
	)


## The viewer faces one way and the allies stand `distance` metres in front, in a row across.
func _stand(room: NightHost, distance: float, yaw: float, shift: float, with_bot: bool) -> void:
	var me := room.server.body_of(_night.state.player_id)
	var here := me.global_position
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_night.player().camera_rig.yaw = yaw
	var ids: Array = room.server.rules.players.keys()
	ids.sort()
	ids.erase(_night.state.player_id)
	for i in ids.size():
		var at: Vector3 = here + forward * distance + right * (SIDES[i % SIDES.size()] + shift)
		at.y = here.y
		room.server.body_of(ids[i]).teleport(at)
		print(
			"seat ",
			ids[i],
			" at ",
			snappedf(here.distance_to(at), 0.1),
			" m, bot ",
			with_bot and i == 2
		)


func _world() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	return viewport


func _fit_hud(insets: Vector4) -> void:
	_hud.offset_left = insets.x
	_hud.offset_top = insets.y
	_hud.offset_right = -insets.z
	_hud.offset_bottom = -insets.w
