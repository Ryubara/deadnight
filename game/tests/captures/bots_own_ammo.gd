extends Node
## A bot that runs low on rounds fetches its own (#692), filmed through the person's shoulder camera
## with the real HUD. The person (seat 1, the old autopilot pinned where it is told, every errand of
## its own off) stands 23 m from the home locker looking at it; the bot (seat 2) carries the gun and
## the points. One case a run, `--case=` after the engine's own arguments:
##
## - `roam`: no order; a reserve under three magazines: it walks to the locker, buys, goes on;
## - `follow_low`: Follow, the same reserve, no locker near the person: it stays, says "I'M
##   RUNNING LOW ON ROUNDS", and when the person walks to within the leash of the locker it
##   goes, buys and comes back to the person;
## - `follow_empty`: Follow, an empty gun: it goes anyway, buys and comes back;
## - `hold_short`: Hold, a reserve under one magazine: it leaves the spot, buys and returns to it.
##
## The timeline (second, place, what the bot says it is doing, its reserve) is printed once a second
## as `OWN_AMMO ...`. Not part of the game. Run with Movie Maker through the kit's `gds godot`,
## so no window takes the person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_own_ammo.tscn --fixed-fps 10
## --write-movie out.png --quit-after 300 -- --case=follow_low`.

const BOT := 2
## Physics frames the navigation server is given to take the mesh in.
const SETTLE_FRAMES := 60
const HOME_LOCKER := Vector3(2.0, 0.0, -31.0)
## Where the person stands, looking down the field (yaw 0 is toward the lot's north, which is where
## the camera rig turns to the locker's side), and where it walks to in `follow_low`.
const PERSON_AT := Vector3(0.0, 0.1, -8.0)
const PERSON_NEARER := Vector3(0.0, 0.1, -22.0)
const FACING := 0.0
const BOT_AT := Vector3(3.0, 0.1, -10.0)
## Seconds into the film at which the person walks toward the locker (`follow_low`), and the speed.
const WALK_AT := 9.0
const WALK_SPEED := 3.5
const POINTS := 300
## The pistol's reserve under three magazines (magazine 10), and under one.
const LOW_RESERVE := 25
const SHORT_RESERVE := 6

var _night: Night
var _host := BotHost.new()
var _case := "roam"
var _label: Label
var _ticks_run := 0
var _person := PERSON_AT
var _person_goal := PERSON_AT


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	_label.text = _case.to_upper().replace("_", " ")
	layer.add_child(_label)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, 7, _tuning())
	_night.link.send({"type": NightServer.JOIN, "player_id": BOT, "local": false})
	await _ticks(3)
	await NightFixture.settle_bake(_night)
	_quiet_the_person()
	_night.player().camera_rig.camera().make_current()
	_seat_the_bot()
	_night.server.body_of(BOT).teleport(BOT_AT)
	_night.server.rules.players[BOT].points = POINTS
	var pistol := _night.server.combat.state_of(BOT, &"pistol")
	match _case:
		"follow_empty":
			pistol.ammo = 0
			pistol.reserve = 0
		"hold_short":
			pistol.reserve = SHORT_RESERVE
		_:
			pistol.reserve = LOW_RESERVE
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)
	match _case:
		"follow_low", "follow_empty":
			_night.bot_orders.issue(BotOrders.FOLLOW, Night.PLAYER_ID, PERSON_AT)
		"hold_short":
			_night.bot_orders.issue(BotOrders.HOLD, Night.PLAYER_ID, PERSON_AT)


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 3000.0
	tuning.rounds.break_seconds = 3000.0
	return tuning


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


func _seat_the_bot() -> void:
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world, _night.server.rules.tuning)
	var state := ClientState.new()
	state.player_id = BOT
	_host.add(
		BotClient.new(
			state, BotProfile.regular(), 100 + BOT, Callable(self, &"_send").bind(BOT), level
		)
	)


func _send(action: Dictionary, id: int) -> void:
	# What the server answers (a line the bot said) goes to the person's screen as a link's would.
	_night.state.apply_events(_night.server.apply(bytes_to_var(var_to_bytes(action)), id))


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	match event["type"]:
		&"purchase_made":
			print("OWN_AMMO t=%.1f BOUGHT %s" % [_seconds(), event])
		&"bot_say":
			print("OWN_AMMO t=%.1f SAID %s" % [_seconds(), event])


func _on_tick() -> void:
	_ticks_run += 1
	if _case == "follow_low" and _seconds() >= WALK_AT:
		_person_goal = PERSON_NEARER
	_person = _person.move_toward(_person_goal, WALK_SPEED * Night.STEP)
	_night.server.body_of(Night.PLAYER_ID).teleport(_person)
	_night.autopilot._yaw = FACING
	_night.player().camera_rig.steer(FACING, 0.0)
	_host.tick(Night.STEP)
	if _ticks_run % 60 == 0 and not _host.bots.is_empty():
		var bot: BotClient = _host.bots[0]
		var at := _night.server.body_of(BOT).global_position
		var reserve := _night.server.combat.state_of(BOT, &"pistol").reserve
		print(
			(
				"OWN_AMMO t=%d at=(%.1f, %.1f) person_z=%.1f note=%s reserve=%d"
				% [_seconds(), at.x, at.z, _person.z, bot.intent.note, reserve]
			)
		)


func _seconds() -> float:
	return float(_ticks_run) / 60.0


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
