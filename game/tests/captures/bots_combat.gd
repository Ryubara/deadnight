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
## - `stampede`: Midnight Stampede, runners only: the bots hold where they are and do not run.
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
	if _scenario == "boss":
		_night.server.rules.round_number = 4
	_host.hear(_night.server.rules.apply(RulesAction.skip_break()))
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


func _tuning() -> RulesTuning:
	var tuning: RulesTuning
	match _scenario:
		"stampede":
			tuning = NightFixture.special_tuning(&"stampede")
			tuning.rounds.count_base = 14.0
			tuning.rounds.speed_base = 2.2
		"grenade":
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


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])


func _on_tick() -> void:
	_stage()
	_host.tick(Night.STEP)


## Puts the dead where the scene wants them.
func _stage() -> void:
	if _scenario == "grenade":
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
