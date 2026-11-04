extends Node
## A four-player horde at count multiplier 5 on a game server (an autopilot player seen over its
## shoulder and three bots, all holding accounts), with a bar under the round banner that reads
## what the client has been told: the level, the bar toward the next, the last gain and where it
## came from, and how many `xp_gained` events and backend writes there have been. The bar is this
## capture's own (the game's level bar and popups are #1064 and #1068); it reads `ClientState`
## only, so it shows what a client of the game server hears and nothing else. Run it through the
## no-focus launcher: `gds godot -- --path game res://tests/captures/xp_horde_capture.tscn
## --write-movie <folder>/x.avi --fixed-fps 30 --resolution 1280x720 -- --seconds=40
## --still=<folder>/still` (a PNG every 10 s).

const SECRET := "capture-ticket-secret-of-32-chars!"
const SERVER_ID := "gs-capture"
const MATCH := "match-capture"
const POINTS := 20000
const START_XP := 300
const HZ := 60.0
const BAR_WIDTH := 520.0

var _args: NetArgs
var _server: GameServer
var _screen: NightScreen
var _posts := 0
var _boosted: Dictionary[int, bool] = {}
var _bar: ProgressBar
var _level: Label
var _gain: Label
var _counts: Label
var _last_gain := ""
var _last_gain_at := -10.0
var _next_still := 10.0
var _started := -1.0


func _ready() -> void:
	_args = NetArgs.new()
	_run.call_deferred()


func _run() -> void:
	var seconds := _args.get_float("seconds", 40.0)
	var start_round := _args.get_int("startround", 8)
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 1
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = _args.get_int("seed", 1)
	_server.clock = _game_seconds
	_server.rules_tuning = AutopilotRun.tuning()
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int:
		_posts += 1
		return 200
	var world := SubViewport.new()
	world.own_world_3d = true
	world.size = Vector2i(64, 64)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(world)
	world.add_child(_server)
	while not _server.listener.is_listening():
		await get_tree().physics_frame
	var settings := MatchSettings.new()
	settings.count_multiplier = _args.get_float("count", 5.0)
	settings.bots = 3
	NightScreen.join_url = "ws://127.0.0.1:%d" % _server.listener.port()
	NightScreen.join_ticket = TicketMaker.make(
		SECRET, SERVER_ID, MATCH, "capture-1", "Ann", 600, settings.to_dict(), {"xp": START_XP}
	)
	NightScreen.join_as_bot = true
	NightScreen.join_map = "drive_in"
	Settings.path = "user://xp_horde_capture.cfg"
	Settings.reset_defaults()
	UIRouter.reset("res://ui/screens/night_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	while _server.room_of_match(MATCH) == null or _screen.night.state == null:
		await get_tree().physics_frame
	var room := _server.room_of_match(MATCH)
	var state := _screen.night.state
	_build_bar()
	room.server.rules.round_number = maxi(start_round - 1, 0)
	state.event_received.connect(_on_event)
	var done := false
	while not done:
		await get_tree().physics_frame
		_seat_accounts(room)
		var rules := room.server.rules
		if (
			_started < 0.0
			and rules.round_number >= start_round
			and rules.phase == GameRules.Phase.ACTIVE
		):
			_started = _game_seconds()
		if _started >= 0.0:
			var played := _game_seconds() - _started
			_update_bar(state)
			if _args.has("still") and played >= _next_still:
				_next_still += 10.0
				await RenderingServer.frame_post_draw
				var path := "%s-%02d.png" % [_args.get_string("still"), int(played)]
				get_viewport().get_texture().get_image().save_png(path)
			done = played >= seconds
	print(
		"XP_HORDE_CAPTURE posts=",
		_posts,
		" xp_events=",
		state.xp_events,
		" total=",
		state.account_xp
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	get_tree().quit()


func _game_seconds() -> float:
	return Engine.get_physics_frames() / HZ


## Every seat holds an account (the bots too, only here) and the points a late round has bought its
## guns with.
func _seat_accounts(room: NightHost) -> void:
	var rules := room.server.rules
	for id: int in rules.players:
		if _boosted.has(id):
			continue
		_boosted[id] = true
		(rules.players[id] as PlayerState).points = POINTS
		room.register_account(id, "capture-%d" % id, {"xp": START_XP})


func _build_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var box := VBoxContainer.new()
	var width := get_viewport().get_visible_rect().size.x
	box.position = Vector2((width - BAR_WIDTH) / 2.0, 120)
	box.custom_minimum_size = Vector2(BAR_WIDTH, 0)
	layer.add_child(box)
	_level = _label(box, 26)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, 18)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	box.add_child(_bar)
	_gain = _label(box, 20)
	_counts = _label(box, 16)


func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	parent.add_child(label)
	return label


func _on_event(event: Dictionary) -> void:
	if event["type"] != &"xp_gained" or event["player_id"] != _screen.night.state.player_id:
		return
	var parts: Array[String] = []
	for stat: StringName in event["sources"]:
		parts.append("%s %.2f" % [stat, float(event["sources"][stat]) / XpRules.HUNDREDTHS])
	_last_gain = (
		"+%.2f XP  (%s)" % [float(event["hundredths"]) / XpRules.HUNDREDTHS, ", ".join(parts)]
	)
	_last_gain_at = _game_seconds()


func _update_bar(state: ClientState) -> void:
	var total := state.account_xp
	_level.text = (
		"LEVEL %d   %d XP   (night +%d)" % [LevelCurve.level_of(total), total, state.night_xp]
	)
	_bar.value = LevelCurve.fraction(total)
	_gain.text = _last_gain if _game_seconds() - _last_gain_at < 1.5 else " "
	_counts.text = (
		"xp_gained heard: %d    levels: %s    backend writes: %d"
		% [state.xp_events, str(state.levels), _posts]
	)
