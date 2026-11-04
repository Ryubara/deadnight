extends Node
## Bots in a fight (bots plan, phase 3), filmed through the shoulder camera of the old autopilot
## that stands in the line beside three hosted bots (a Rookie, a Regular and a Veteran). Three
## scenes, chosen with `--scenario=`:
##
## - `boss`: the first boss night (round 5, Double Feature): the headliners are put in front of the
##   line and walk at it; the bots keep their distance, step out of the telegraphed blow and shoot
##   the lit lens on the belly.
## - `grenade`: a pack of the dead stands ten metres off; a bot turns, lobs a grenade and the blast
##   takes the pack.
## - `grenade_beside` (#872): the same pack, with two of the bots standing 3.5 m to either side of
##   it (they stand idle, so they do not shoot the pack first) and the filmed bot back in the
##   line: the bots keep no distance from their teammates (only the thrower takes a grenade's
##   damage), so it throws, nobody beside the pack is hurt, and it stands and fights
##   until its grenade has gone off. Before #872 the bots held the throw while a teammate was
##   within 7.5 m of the pack.
## - `stampede`: Midnight Stampede, runners only: the bots hold where they are and do not run.
##
## `--rigs=run` runs the hosted bots' camera rigs in every drawn frame as before #938 (a rig no one
## looks through now rests and is told the look in each tick), for a before and after of the pose;
## the default is `--rigs=rest`. `--view=bot` films the bot of seat 2 from beside and behind it
## (its weapon's pose is what the rig change touches) instead of through the old autopilot's camera.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`, so no window takes the
## person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_combat.tscn --fixed-fps 10
## --write-movie out.png --quit-after 300 -- --scenario=boss`.

const SEATS := [2, 3, 4]
## Metres between the bodies in the line.
const SPACING := 3.0
## Metres ahead of the line the dead are put, and the boss's walking speed.
const AHEAD := 11.0
const BOSS_SPEED := 1.1

var _night: Node
var _host := BotHost.new()
var _probe: WorldProbe
var _scenario := "boss"
var _staged := {}
var _side_camera: Camera3D
var _pack_made := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_scenario = _arg("scenario", "boss")
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, 7, _tuning())
	for id: int in SEATS:
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	await _ticks(3)
	_seat_the_hosted_bots()
	_line_up()
	if _arg("rigs", "rest") == "rest":
		# The harness seats its bots without the `bot` flag a hosted bot joins with.
		for id: int in SEATS:
			_night.server.body_of(id).make_viewless()
	if _arg("view", "autopilot") == "bot":
		_side_camera = Camera3D.new()
		add_child(_side_camera)
		_side_camera.make_current()
	if _scenario == "boss":
		_night.server.rules.round_number = 4
	_host.hear(_night.server.rules.apply(RulesAction.skip_break()))
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


func _process(_delta: float) -> void:
	if _side_camera == null:
		return
	var body: Player = _night.server.body_of(SEATS[0])
	var chest := body.global_position + Vector3(0.0, 1.3, 0.0)
	_side_camera.global_position = chest + Vector3(1.9, 0.5, 2.6)
	_side_camera.look_at(chest + Vector3(-1.5, 0.0, -2.0))


func _tuning() -> RulesTuning:
	var tuning: RulesTuning
	match _scenario:
		"stampede":
			tuning = NightFixture.special_tuning(&"stampede")
			tuning.rounds.count_base = 14.0
			tuning.rounds.speed_base = 2.2
		"grenade", "grenade_beside":
			tuning = SeatedNight.one_a_round()
		_:
			tuning = RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 1.0
	return tuning


func _seat_the_hosted_bots() -> void:
	_probe = WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		_probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world)
	if _scenario == "grenade_beside":
		# The filmed seat is a hosted bot too, in place of the old autopilot; the others stand idle.
		var thrower := BotProfile.regular()
		thrower.follows = false
		_night.bot = BotClient.new(_night.state, thrower, 101, _night.link.send, level)
		return
	var profiles: Array[BotProfile] = [
		BotProfile.rookie(), BotProfile.regular(), BotProfile.veteran()
	]
	for i in SEATS.size():
		var state := ClientState.new()
		state.player_id = SEATS[i]
		var profile := profiles[i]
		profile.follows = false
		_host.add(
			BotClient.new(
				state, profile, 100 + SEATS[i], Callable(self, &"_send").bind(SEATS[i]), level
			)
		)


## The four bodies side by side on the open field in front of the screen.
func _line_up() -> void:
	var seats: Array = [Night.PLAYER_ID] + SEATS
	for i in seats.size():
		var at := Autopilot.HOME + Vector3(SPACING * (float(i) - 1.5), 0.1, 0.0)
		_night.server.body_of(seats[i]).teleport(at)
	if _scenario == "grenade_beside":
		# Seats 2 and 3 stand 3.5 m to either side of the pack's middle, a little short of it.
		_night.server.body_of(Night.PLAYER_ID).teleport(Autopilot.HOME + Vector3(0.0, 0.1, 0.0))
		var middle := Autopilot.HOME + Vector3(-1.35, 0.1, -11.65)
		_night.server.body_of(2).teleport(middle + Vector3(-3.5, 0.0, 2.5))
		_night.server.body_of(3).teleport(middle + Vector3(3.5, 0.0, 2.5))


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	if event["type"] in [&"grenade_thrown", &"grenade_exploded", &"player_blasted", &"player_hurt"]:
		print("movie frame %d: %s %s" % [Engine.get_frames_drawn(), event["type"], event])


func _on_tick() -> void:
	_stage()
	_host.tick(Night.STEP)


## Puts the dead where the scene wants them.
func _stage() -> void:
	if _scenario == "grenade" or _scenario == "grenade_beside":
		_stage_the_pack()
		return
	for id: int in _night.server.sim.zombies:
		var zombie: ZombieBody = _night.server.sim.zombies[id]
		if _staged.has(id) or zombie.mode == ZombieBody.Mode.DYING:
			continue
		_staged[id] = true
		var across := (float(id % 7) - 3.0) * 2.4
		var ahead := AHEAD + float(id % 4) * 1.5
		zombie.position = NavigationServer3D.map_get_closest_point(
			_night.world.map(), Autopilot.HOME + Vector3(across, 0.0, -ahead)
		)
		zombie.gate_id = &""
		if zombie.profile.boss:
			zombie.speed = BOSS_SPEED
		zombie.enter(ZombieBody.Mode.CHASE)


## Four of the dead that stand still, close together.
func _stage_the_pack() -> void:
	if _pack_made:
		return
	_pack_made = true
	for i in 4:
		var at := (
			Autopilot.HOME + Vector3(-2.0 + float(i % 2) * 1.3, 0.0, -11.0 - float(i / 2) * 1.3)
		)
		var zombie: ZombieBody = _night.server.sim.spawn(1000 + i, 0.0, at)
		zombie.enter(ZombieBody.Mode.CHASE)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return fallback
