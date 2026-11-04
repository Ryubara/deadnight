extends Node
## A four-player night on a game server (an autopilot player seen over its shoulder and three bots,
## all holding accounts) whose boards the backend hands over a few kills short of finishing, so the
## challenges finish while the capture runs (#1076). Under the round banner a list reads what this
## client has been told, event by event (`challenge_progress`, `challenge_done` with the reward and
## whose it is, and the backend writes); the card on the left edge is the game's own prompt, fed by
## the server's word. The list is this capture's own; it reads `ClientState` only. Run it through
## the no-focus launcher: `gds godot -- --path game
## res://tests/captures/challenge_award_capture.tscn --write-movie <folder>/x.avi --fixed-fps 30
## --resolution 1280x720 -- --seconds=40 --still=<folder>/still` (a PNG each time the player's own
## challenge is done).

const SECRET := "capture-ticket-secret-of-32-chars!"
const SERVER_ID := "gs-capture"
const MATCH := "match-capture"
const POINTS := 20000
const START_XP := 300
const HZ := 60.0
const LIST_WIDTH := 640.0
const LINES := 7

var _args: NetArgs
var _server: GameServer
var _screen: NightScreen
var _posts := 0
var _boards := 0
var _boosted: Dictionary[int, bool] = {}
var _list: Label
var _lines: Array[String] = []
var _done_heard := 0
var _own_done := 0
var _stills := 0
var _last_done_at := -10.0


func _ready() -> void:
	_args = NetArgs.new()
	_run.call_deferred()


func _catalog() -> ChallengeCatalog:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				_record("d_kills_8", "Put down {n} zombies", "kills", 8, "short", "kills"),
				_record("d_head_5", "Land {n} headshot kills", "kills:head", 5, "medium", "aim"),
				_record(
					"d_round_3",
					"Reach round {n} in one night",
					"round",
					3,
					"long",
					"survive",
					"night"
				),
			],
			ChallengeDef.Family.DAILY
		)
	)
	catalog.add_all(
		[
			_record(
				"o_points_800",
				"Earn {n} points",
				"points_earned",
				800,
				"short",
				"",
				"total",
				"night"
			)
		],
		ChallengeDef.Family.ORDER
	)
	return catalog


func _record(
	id: String,
	text: String,
	stat: String,
	target: int,
	tier: String,
	group: String,
	mode := "total",
	pillar := ""
) -> Dictionary:
	return {
		"id": id,
		"text": text,
		"stat": stat,
		"target": target,
		"tier": tier,
		"group": group,
		"mode": mode,
		"pillar": pillar,
		"reward": {"xp": 25},
	}


## The board the backend holds for an account: the night's dailies a few kills short.
func _held_board(catalog: ChallengeCatalog, clock: ChallengeClock) -> Dictionary:
	var held := ChallengeProfile.fresh()
	held.refresh(catalog, clock.day())
	held.apply(catalog, ChallengeStats.KILLS, 6, 6)
	held.apply(catalog, ChallengeStats.KILLS_HEAD, 3, 3)
	return JSON.parse_string(ChallengeSave.to_json(held))


func _run() -> void:
	var seconds := _args.get_float("seconds", 40.0)
	var catalog := _catalog()
	var clock := ChallengeClock.fixed(20401.0 * ChallengeClock.DAY_SECONDS + 60.0)
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 1
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = _args.get_int("seed", 1)
	_server.clock = _game_seconds
	_server.rules_tuning = AutopilotRun.tuning()
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.challenge_catalog = catalog
	_server.challenge_clock = clock
	_server.board_reader = func(_user: String) -> Dictionary:
		_boards += 1
		return {"status": 200, "json": _held_board(catalog, clock)}
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
	settings.count_multiplier = _args.get_float("count", 3.0)
	settings.bots = 3
	NightScreen.join_url = "ws://127.0.0.1:%d" % _server.listener.port()
	NightScreen.join_ticket = TicketMaker.make(
		SECRET,
		SERVER_ID,
		MATCH,
		"capture-1",
		"Ann",
		600,
		settings.to_dict(),
		null,
		{"xp": START_XP}
	)
	NightScreen.join_as_bot = true
	NightScreen.join_map = "drive_in"
	Settings.path = "user://challenge_award_capture.cfg"
	Settings.reset_defaults()
	NightScreen.challenge_path = "user://challenge_award_capture.json"
	UIRouter.reset("res://ui/screens/night_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	while _server.room_of_match(MATCH) == null or _screen.night.state == null:
		await get_tree().physics_frame
	var room := _server.room_of_match(MATCH)
	var state := _screen.night.state
	_build_list()
	room.server.rules.round_number = maxi(_args.get_int("startround", 6) - 1, 0)
	state.event_received.connect(_on_event)
	var started := _game_seconds()
	while _game_seconds() - started < seconds:
		await get_tree().physics_frame
		_seat_accounts(room)
		_update_list()
		if _args.has("still") and _own_done > _stills and _game_seconds() - _last_done_at > 0.5:
			_stills += 1
			await RenderingServer.frame_post_draw
			var path := "%s-%02d.png" % [_args.get_string("still"), _stills]
			get_viewport().get_texture().get_image().save_png(path)
	print(
		"CHALLENGE_AWARD_CAPTURE boards=",
		_boards,
		" posts=",
		_posts,
		" done_heard=",
		_done_heard,
		" own_done=",
		_own_done
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NightScreen.challenge_path))
	NightScreen.challenge_path = ""
	get_tree().quit()


func _game_seconds() -> float:
	return Engine.get_physics_frames() / HZ


## Every seat holds an account (the bots too, only here) and the points a night has bought its guns
## with.
func _seat_accounts(room: NightHost) -> void:
	var rules := room.server.rules
	for id: int in rules.players:
		if _boosted.has(id):
			continue
		_boosted[id] = true
		(rules.players[id] as PlayerState).points = POINTS
		room.register_account(id, "capture-%d" % id, {"xp": START_XP})


func _build_list() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var box := VBoxContainer.new()
	var width := get_viewport().get_visible_rect().size.x
	box.position = Vector2(width - LIST_WIDTH - 24.0, 150)
	box.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	layer.add_child(box)
	_list = Label.new()
	_list.add_theme_font_size_override(&"font_size", 18)
	_list.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_list.add_theme_constant_override(&"outline_size", 6)
	box.add_child(_list)


func _on_event(event: Dictionary) -> void:
	var own := _screen.night.state.player_id
	match event["type"]:
		&"challenge_progress":
			if event["completed"]:
				return
			_push(
				(
					"%s  %s  %d / %d"
					% [_who(event["player_id"]), event["text"], event["after"], event["target"]]
				)
			)
		&"challenge_done":
			_done_heard += 1
			if event["player_id"] == own:
				_own_done += 1
				_last_done_at = _game_seconds()
			_push(
				(
					"%s  DONE  %s  +%d XP"
					% [_who(event["player_id"]), event["text"], int(event["reward"].get("xp", 0))]
				)
			)


func _who(player_id: int) -> String:
	return String(_screen.night.state.names.get(player_id, "?")).to_upper()


func _push(line: String) -> void:
	_lines.append(line)
	while _lines.size() > LINES:
		_lines.pop_front()


func _update_list() -> void:
	var state := _screen.night.state
	_list.text = (
		"challenge events heard: %d done    backend reads: %d    reports: %d\n%s"
		% [_done_heard, _boards, _posts, "\n".join(_lines)]
	)
	_list.text += "\n(night +%d XP)" % state.night_xp
