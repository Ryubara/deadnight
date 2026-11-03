extends Node
## A bot raises a downed person (bots plan, phase 5), filmed through the downed person's shoulder
## camera with the real HUD: the person (seat 1, standing idle) goes down in the avenue, two hosted
## bots (seats 2 and 3) come. Three scenes, chosen with `--scenario=`:
##
## - `clear`: nobody is near the body; one bot walks up and holds the revive while the other stands
##   by it (the claim table gives one reviver and one covering bot).
## - `pack`: three of the dead stand by the body (the rest of the round is far off); the bots
##   shoot them first (the ones nearest the body first), and only then does one kneel and hold.
## - `flare` (#646): eight of the dead stand about the body, and the one bot (seat 2) has three
##   rounds, no grenade and the flare gun: it fires the flare far from the body, the dead walk to
##   it, and the bot kneels and holds. The camera looks across the lot, east of the person.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`, so no window takes the
## person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_revive.tscn --fixed-fps 10
## --write-movie out.png --quit-after 300 -- --scenario=pack`.

const SEATS: Array[int] = [2, 3]
## Metres in front of the field's home where the person falls, and the bots' places behind.
const BODY := Vector3(0.0, 0.1, -8.0)
const BOT_SPOTS := [Vector3(3.0, 0.1, 6.0), Vector3(-3.0, 0.1, 6.0)]
## Seconds the person stands before the fall.
const STAND_SECONDS := 1.0
## The dead put by the body in the `pack` scene; the rest of the round walks in from the gates.
const PACK := 3
## The `flare` scene: where the person falls, where the bot stands (the same as the scenario test
## `tests/night/test_bot_flare.gd`), the dead about the body, the rounds the bot has, and the yaw
## the person's camera is turned to (east, across the lane the flare flies down).
const FLARE_BODY := Vector3(-12.0, 0.1, -4.0)
const FLARE_BOT := Vector3(2.0, 0.1, 6.0)
const FLARE_PACK := 8
const FLARE_ROUNDS := 3
const FLARE_CAMERA_YAW := -1.5

var _night: Night
var _host := BotHost.new()
var _probe: WorldProbe
var _scenario := "clear"
var _staged := {}
var _ticks_run := 0
var _fell := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_scenario = _arg("scenario", "clear")
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, _tuning())
	for id: int in _seats():
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	await _ticks(3)
	_seat_the_hosted_bots()
	_night.server.body_of(Night.PLAYER_ID).teleport(Autopilot.HOME + _body())
	for i in _seats().size():
		_night.server.body_of(_seats()[i]).teleport(Autopilot.HOME + _bot_spots()[i])
	_host.hear(_night.server.rules.apply(RulesAction.skip_break()))
	if _scenario == "flare":
		_arm_the_flare_bot()
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


func _seats() -> Array[int]:
	return [SEATS[0]] if _scenario == "flare" else SEATS


func _body() -> Vector3:
	return FLARE_BODY if _scenario == "flare" else BODY


func _bot_spots() -> Array[Vector3]:
	if _scenario == "flare":
		return [FLARE_BOT]
	return [BOT_SPOTS[0], BOT_SPOTS[1]]


## The one bot has three rounds in its pistol, no grenade and the flare gun beside it.
func _arm_the_flare_bot() -> void:
	var id: int = _seats()[0]
	_night.server.combat.apply(CombatAction.give_weapon(id, &"flare_gun"))
	_night.server.combat.apply(CombatAction.equip(id, &"pistol"))
	var pistol := _night.server.combat.state_of(id, &"pistol")
	pistol.ammo = FLARE_ROUNDS
	pistol.reserve = 0
	_host.bots[0].perception.beliefs.grenades = 0
	var rig := _night.player().camera_rig
	rig.yaw = FLARE_CAMERA_YAW
	rig.snap_to(_night.player().global_position)


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	if _scenario == "pack" or _scenario == "flare":
		tuning.rounds.count_base = float(FLARE_PACK if _scenario == "flare" else 12)
		tuning.rounds.count_linear = 0.0
		tuning.rounds.count_quadratic = 0.0
		tuning.rounds.first_spawn_delay = 0.2
		tuning.rounds.spawn_interval_start = 0.2
		tuning.rounds.spawn_interval_min = 0.2
		tuning.rounds.spawn_interval_floor = 0.2
		tuning.rounds.speed_base = 1.3
		tuning.rounds.speed_step = 0.0
		tuning.rounds.speed_jitter = 0.0
	else:
		tuning.rounds.first_spawn_delay = 600.0
	return tuning


func _seat_the_hosted_bots() -> void:
	_probe = WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		_probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world)
	for i in _seats().size():
		var state := ClientState.new()
		state.player_id = _seats()[i]
		var profile := BotProfile.regular()
		profile.follows = false
		_host.add(
			BotClient.new(
				state, profile, 100 + _seats()[i], Callable(self, &"_send").bind(_seats()[i]), level
			)
		)


func _send(action: Dictionary, id: int) -> void:
	# What the server answers (a bot's line, a mark) goes to the screen as a broadcast would.
	var shown: Array[Dictionary] = []
	for event in _night.server.apply(bytes_to_var(var_to_bytes(action)), id):
		if event["type"] == &"bot_say":
			shown.append(event)
	if not shown.is_empty():
		_night.state.apply_events(shown)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	match event["type"]:
		&"revive_started", &"revive_stopped", &"player_revived", &"player_downed", &"bot_say":
			print("REVIVE_EVENT t=%.1f %s" % [float(_ticks_run) / 60.0, event])
		&"zombie_removed":
			if event["cause"] == &"killed":
				print("REVIVE_EVENT t=%.1f zombie killed" % [float(_ticks_run) / 60.0])


func _on_tick() -> void:
	_ticks_run += 1
	if not _fell and _ticks_run >= int(STAND_SECONDS * 60.0):
		_fell = true
		var events := _night.server.rules.apply(RulesAction.blow(Night.PLAYER_ID, 99999.0))
		_host.hear(events)
		_night.state.apply_events(events)
	_stage()
	_host.tick(Night.STEP)


## The pack and flare scenes: the dead that appear are put close to the body (in a ring about it
## in the flare scene).
func _stage() -> void:
	if _scenario == "flare":
		_stage_ring()
	if _scenario != "pack":
		return
	for id: int in _night.server.sim.zombies:
		var zombie: ZombieBody = _night.server.sim.zombies[id]
		if _staged.has(id) or zombie.mode == ZombieBody.Mode.DYING or _staged.size() >= PACK:
			continue
		_staged[id] = true
		var side := 1.0 if id % 2 == 0 else -1.0
		zombie.position = NavigationServer3D.map_get_closest_point(
			_night.world.map(),
			Autopilot.HOME + BODY + Vector3(side * (2.5 + float(id % 3)), 0.0, -2.0)
		)
		zombie.gate_id = &""
		zombie.enter(ZombieBody.Mode.CHASE)


func _stage_ring() -> void:
	for id: int in _night.server.sim.zombies:
		var zombie: ZombieBody = _night.server.sim.zombies[id]
		if _staged.has(id) or zombie.mode == ZombieBody.Mode.DYING or _staged.size() >= FLARE_PACK:
			continue
		var around := TAU * float(_staged.size()) / float(FLARE_PACK)
		var out := 2.5 + float(_staged.size() % 3)
		_staged[id] = true
		zombie.position = Autopilot.HOME + FLARE_BODY + Vector3(sin(around), 0.0, cos(around)) * out
		zombie.gate_id = &""
		zombie.enter(ZombieBody.Mode.CHASE)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return fallback
