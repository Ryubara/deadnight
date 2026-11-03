extends Node
## A bot answers a person's ammunition ping (bots plan, phase 5), filmed through the person's
## shoulder camera with the real HUD: the person (seat 1, the old autopilot pinned where it is told,
## with every errand of its own turned off) stands by the midway locker and marks it; the bot
## (seat 2), short of pistol rounds and holding points, walks the field from home to that locker
## and buys there, though the locker at the field's home is the nearer one to it. Without the
## answer (the code on main before it) the bot buys at the home locker at once.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`, so no window takes the
## person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_ammo_ping.tscn --fixed-fps 10
## --write-movie out.png --quit-after 140`.

const BOT := 2
const DOOR := &"door_concession"
## Physics frames the navigation server is given to take the new mesh in.
const SETTLE_FRAMES := 60
## The midway locker, and where the person stands to mark it, looking up the field.
const LOCKER := Vector3(13.5, 0.0, 12.0)
const PERSON_AT := Vector3(10.0, 0.1, 19.0)
## The way the person looks, in radians (0 is toward the lot's north).
const FACING := -0.2
const BOT_AT := Vector3(0.0, 0.1, -34.0)
## Seconds the person waits before marking the locker, and the seconds more before the bot looks
## (it would otherwise buy at the near locker before the mark is up).
const MARK_AT := 0.1
const BOT_WAITS := 0.6
const SHORT_RESERVE := 4
const POINTS := 200

var _night: Night
var _host := BotHost.new()
var _ticks_run := 0
var _marked := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, 7, _tuning())
	_night.link.send({"type": NightServer.JOIN, "player_id": BOT, "local": false})
	await _ticks(3)
	# The concession is open, as the way to its locker is for anyone who marks it.
	_night.server.rules.apply(RulesAction.grant_points(Night.PLAYER_ID, 100000))
	RulesFixture.buy(_night.server.rules, Night.PLAYER_ID, DOOR)
	await _ticks(SETTLE_FRAMES)
	await NightFixture.settle_bake(_night)
	_quiet_the_person()
	# The body the bot got at its seat took the view; the picture is the person's.
	_night.player().camera_rig.camera().make_current()
	_seat_the_bot()
	_night.server.body_of(BOT).teleport(BOT_AT)
	_night.server.rules.players[BOT].points = POINTS
	_night.server.combat.state_of(BOT, &"pistol").reserve = SHORT_RESERVE
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


## The person does no errands of its own and stays where it was put.
func _quiet_the_person() -> void:
	var pilot := _night.autopilot
	pilot.order.clear()
	pilot.wanted.clear()
	pilot.spots.clear()
	pilot.recut_price = 0
	pilot.tonic_price = 0
	pilot.switches.goals.clear()
	pilot.fuel.goals.clear()
	pilot.repair_goals.clear()


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 3000.0
	tuning.rounds.break_seconds = 3000.0
	return tuning


func _seat_the_bot() -> void:
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world, _night.server.rules.tuning)
	var state := ClientState.new()
	state.player_id = BOT
	var profile := BotProfile.regular()
	profile.follows = false
	_host.add(BotClient.new(state, profile, 100 + BOT, Callable(self, &"_send").bind(BOT), level))


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	if event["type"] == &"purchase_made":
		var at := _night.server.body_of(BOT).global_position
		print("AMMO_PING t=%.1f at=%s %s" % [float(_ticks_run) / 60.0, at, event])
	if event["type"] == &"ping_placed":
		print("AMMO_PING t=%.1f %s" % [float(_ticks_run) / 60.0, event])


func _on_tick() -> void:
	_night.server.body_of(Night.PLAYER_ID).teleport(PERSON_AT)
	_night.autopilot._yaw = FACING
	_night.player().camera_rig.steer(FACING, 0.0)
	_ticks_run += 1
	if not _marked and _ticks_run >= int(MARK_AT * 60.0):
		_marked = true
		var events := _night.server.apply(
			{"type": NightServer.PING, "kind": PingBoard.AMMO, "pos": LOCKER, "subject": 0},
			Night.PLAYER_ID
		)
		_night.state.apply_events(events)
	if _ticks_run >= int((MARK_AT + BOT_WAITS) * 60.0):
		_host.tick(Night.STEP)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
