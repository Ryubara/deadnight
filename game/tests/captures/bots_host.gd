extends Node
## Four bots on one night (bots plan, phase 1): the old autopilot, run by the bot host, is filmed
## through its own shoulder camera, and three hosted bots (a Rookie, a Regular and a Veteran) stand
## beside it and fight what comes, each reading only its allow-listed events and sending only
## commands. The dead are put in front of the line as they appear, so a short recording has a
## fight in it. Not part of the game. Run with Movie Maker, through the kit's `gds godot` so no
## window takes the person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_host.tscn --fixed-fps 10
## --write-movie out.png --quit-after 400`.

const SEATS := [2, 3, 4]
## Metres between the bots in the line, and how far ahead of it the dead are put.
const SPACING := 3.0
const AHEAD_MIN := 9.0
const AHEAD_STEP := 1.5

var _night: Night
var _host := BotHost.new()
var _probe: WorldProbe
var _staged := {}


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
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.0
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 1.0
	await _night.start(Night.Mode.AUTOPILOT, 7, tuning)
	for id: int in SEATS:
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	await _ticks(3)
	_seat_the_hosted_bots()
	_night.server.rules.apply(RulesAction.skip_break())
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)
	_line_up()


## One hosted bot to a seat, each with a client state of its own.
func _seat_the_hosted_bots() -> void:
	_probe = WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		_probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	level.home = Autopilot.HOME
	for i in SEATS.size():
		var state := ClientState.new()
		state.player_id = SEATS[i]
		var profile := (
			[BotProfile.rookie(), BotProfile.regular(), BotProfile.veteran()][i] as BotProfile
		)
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
	_stage_the_dead()
	_host.tick(Night.STEP)


## Each new zombie starts in front of the line, to walk at it.
func _stage_the_dead() -> void:
	for id: int in _night.server.sim.zombies:
		var zombie: ZombieBody = _night.server.sim.zombies[id]
		if _staged.has(id) or zombie.mode == ZombieBody.Mode.DYING:
			continue
		_staged[id] = true
		var across := (float(id % 7) - 3.0) * 2.4
		var ahead := AHEAD_MIN + float(id % 4) * AHEAD_STEP
		zombie.position = NavigationServer3D.map_get_closest_point(
			_night.world.map(), Autopilot.HOME + Vector3(across, 0.0, -ahead)
		)
		zombie.gate_id = &""
		zombie.enter(ZombieBody.Mode.CHASE)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
