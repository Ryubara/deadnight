extends Node
## The popup lane in a real fight: a game server night (an autopilot player seen over its shoulder,
## three bots, round 8 at count multiplier 5, the dead all over the lot) where the player's account
## earns XP the way a kill or a finished challenge does (`XpAward`), so the server tells the client
## `level_up`, `tier_up` and `unlock_earned` and the lane under the round banner shows them, live.
## Four moments, a few seconds apart: a tier up, a level up with its unlock, a stack (two levels,
## two unlocks and a finished challenge inside a few seconds) and a finished challenge alone. Not
## part of the game.
##
## Arguments after `--`: `--seconds=S` (game seconds to play from the first moment, default 34),
## `--reduced` (reduced motion), `--touch` (the phone's controls on), `--startround=N`.
## Record: `gds godot -- --path game res://tests/captures/popup_night.tscn --write-movie
## <abs>/n.avi --fixed-fps 30 --resolution 1280x720 -- --seconds=34`. Prints `POPUP <seconds>
## <cue>` whenever a card starts and `EVENT <seconds> <type>` for every progression event the
## client hears.

const SECRET := "capture-ticket-secret-of-32-chars!"
const SERVER_ID := "gs-capture"
const MATCH := "match-capture"
const POINTS := 20000
const HZ := 60.0
## The account's level when the seat sits down (a night's first XP moves it up a little before the
## first moment), and the moments: when, and how far the level goes (`"tier"`: to the next tier's
## first level, `"up"`: levels more).
const START_LEVEL := 9
const MOMENTS: Array[Dictionary] = [
	{"at": 2.0, "to": "tier", "what": "tier"},
	{"at": 10.0, "up": 1, "what": "level"},
	{"at": 18.0, "up": 2, "what": "stack", "challenge": true},
	{"at": 28.0, "what": "challenge"},
]

var _args: NetArgs
var _server: GameServer
var _screen: NightScreen
var _boosted := false
var _next := 0
var _started := -1.0
var _pid := 0


func _ready() -> void:
	_args = NetArgs.new()
	_run.call_deferred()


func _run() -> void:
	var seconds := _args.get_float("seconds", 34.0)
	var start_round := _args.get_int("startround", 8)
	UIMotion.reduced = _args.has("reduced")
	TouchMode.device_is_touch = _args.has("touch")
	_server = GameServer.new()
	_server.port = 0
	_server.capacity = 1
	_server.server_id = SERVER_ID
	_server.log_enabled = false
	_server.seed_value = _args.get_int("seed", 1)
	_server.clock = _game_seconds
	_server.rules_tuning = AutopilotRun.tuning()
	_server.verifier = TicketVerifier.new(SECRET, SERVER_ID)
	_server.report_sender = func(_path: String, _body: Dictionary) -> int: return 200
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
		SECRET,
		SERVER_ID,
		MATCH,
		"capture-1",
		"Ann",
		600,
		settings.to_dict(),
		null,
		{"xp": LevelCurve.xp_for(START_LEVEL) + 5}
	)
	NightScreen.join_as_bot = true
	NightScreen.join_map = "drive_in"
	Settings.path = "user://popup_night_capture.cfg"
	Settings.reset_defaults()
	Settings.set_value(SettingsService.REDUCED_MOTION, _args.has("reduced"))
	# The first-run touch hints ("DRAG TO LOOK") are a night's first minute: film the normal HUD.
	Settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 255)
	UIRouter.reset("res://ui/screens/night_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	while _server.room_of_match(MATCH) == null or _screen.night.state == null:
		await get_tree().physics_frame
	var room := _server.room_of_match(MATCH)
	var state := _screen.night.state
	_pid = state.player_id
	room.server.rules.round_number = maxi(start_round - 1, 0)
	state.event_received.connect(_on_event)
	_screen.night.hud.popups.cue.connect(
		func(sound: StringName) -> void: print("POPUP %.1f %s" % [_played(), sound])
	)
	var done := false
	while not done:
		await get_tree().physics_frame
		_boost(room)
		var rules := room.server.rules
		if (
			_started < 0.0
			and rules.round_number >= start_round
			and rules.phase == GameRules.Phase.ACTIVE
		):
			_started = _game_seconds()
			print("START level ", LevelCurve.level_of(room.server.xp.total_of(_pid)))
		if _started >= 0.0:
			_moments(room)
			done = _played() >= seconds
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	UIMotion.reduced = false
	get_tree().quit()


func _game_seconds() -> float:
	return Engine.get_physics_frames() / HZ


func _played() -> float:
	return _game_seconds() - _started if _started >= 0.0 else 0.0


## The local seat holds the account (a bot never has one) and the points a late round has bought
## its guns with.
func _boost(room: NightHost) -> void:
	if _boosted:
		return
	_boosted = true
	var rules := room.server.rules
	for id: int in rules.players:
		(rules.players[id] as PlayerState).points = POINTS
	room.register_account(_pid, "capture-%d" % _pid, {"xp": LevelCurve.xp_for(START_LEVEL) + 5})


## The next moment, when its time has come: XP enough to reach its level in one go, paid the way a
## finished challenge's reward is (`XpAward.add_xp`), and the challenge's own advance for the HUD.
func _moments(room: NightHost) -> void:
	if _next >= MOMENTS.size() or _played() < float(MOMENTS[_next]["at"]):
		return
	var moment := MOMENTS[_next]
	_next += 1
	var xp := room.server.xp
	var level := LevelCurve.level_of(xp.total_of(_pid))
	var target := level
	if moment.get("to", "") == "tier":
		target = (LevelCurve.tier_of(level) + 1) * LevelCurve.TIER_SIZE + 1
	elif moment.has("up"):
		target = level + int(moment["up"])
	if target > level:
		xp.add_xp(_pid, LevelCurve.xp_for(target) - xp.total_of(_pid), XpAward.CHALLENGE)
	if moment.has("challenge") or moment["what"] == "challenge":
		(
			_screen
			. night
			. hud
			. state
			. apply_event(
				{
					"type": HudChallenge.EVENT,
					"id": &"d_kills",
					"family": ChallengeDef.Family.DAILY,
					"text": "Put down 40 zombies",
					"before": 39,
					"after": 40,
					"target": 40,
					"checkpoint": 100,
					"completed": true,
					"rung": 0,
					"rungs": 0,
				}
			)
		)


func _on_event(event: Dictionary) -> void:
	var type: StringName = event["type"]
	if type in [&"level_up", &"tier_up", &"unlock_earned"] and int(event["player_id"]) == _pid:
		print("EVENT %.1f %s %s" % [_played(), type, str(event.get("level", ""))])
