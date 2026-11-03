extends Node
## The first boss night (round 5, Double Feature) played by four hosted Rookie bots on the drawn
## lot, filmed through the first Rookie's own shoulder camera: the capture that goes with
## `bots_boss_night.tscn`'s numbers. The round is begun the way `BossNight` begins it (the rules set
## to the end of round 4, the break skipped); the bots carry the starting pistol. Not part of the
## game. Run with Movie Maker through the kit's `gds godot`, so no window takes the keyboard:
## `gds godot -- --path game res://tests/captures/bots_boss_film.tscn --fixed-fps 10
## --write-movie out.png --quit-after 1200`.

const SEATS := [2, 3, 4]
const ROUND := 5

var _night: Night
var _host := BotHost.new()
var _probe: WorldProbe


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
	_night.shoulder_camera = true
	await _night.start(Night.Mode.AUTOPILOT, 7)
	for id: int in SEATS:
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	await _ticks(3)
	_seat_the_bots()
	_night.server.rules.round_number = ROUND - 1
	_night.server.rules.apply(RulesAction.skip_break())
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


func _seat_the_bots() -> void:
	_probe = WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		_probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world)
	# The night's own bot (seat 1, filmed) is a Rookie too, in place of the old autopilot.
	_night.bot = BotClient.new(_night.state, BotProfile.rookie(), 101, _night.link.send, level)
	for id: int in SEATS:
		var state := ClientState.new()
		state.player_id = id
		_host.add(
			BotClient.new(
				state, BotProfile.rookie(), 100 + id, Callable(self, &"_send").bind(id), level
			)
		)


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	if event["type"] == &"round_started":
		_night.bot.perception.beliefs.special = event.get("special_id", &"")


func _on_tick() -> void:
	_host.tick(Night.STEP)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
