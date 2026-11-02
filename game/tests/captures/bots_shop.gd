extends Node
## Bots that shop and keep the lot running (bots plan, phase 4), filmed through the shoulder camera
## of the old autopilot that stands in for a person: it is pinned where it is told and looks the way
## it is told, with every errand of its own turned off, and one hosted bot goes about its business.
## Three scenes, chosen with `--scenario=`:
##
## - `door`: the bot holds the price of the concession door, walks to it and buys it; the camera is
##   inside, looking at the door.
## - `boards`: three boards are down at the north-west breach; in a break the bot walks there and
##   puts them back, one after another, and the points come.
## - `fuel`: the tank is at a fifth, the concession is open; the bot walks to the cans and buys one.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`, so no window takes the
## person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_shop.tscn --fixed-fps 10
## --write-movie out.png --quit-after 400 -- --scenario=door`.

const BOT := 2
## A break that does not end, so the scene is not rushed.
const LONG_BREAK := 3000.0
## Where the camera operator (the autopilot) stands, and the way it looks, for each scene.
const STAGE := {
	"door": [Vector3(0.0, 0.1, 3.0), 0.0],
	"boards": [Vector3(-36.0, 0.1, -38.0), 0.0],
	"fuel": [Vector3(2.5, 0.1, 12.0), 0.0],
}

var _night: Night
var _host := BotHost.new()
var _scenario := "door"
var _operator := Vector3.ZERO
var _facing := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_scenario = _arg("scenario", "door")
	_operator = STAGE[_scenario][0]
	_facing = STAGE[_scenario][1]
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	await _night.start(Night.Mode.AUTOPILOT, 7, tuning)
	_night.link.send({"type": NightServer.JOIN, "player_id": BOT, "local": false})
	await _ticks(3)
	_quiet_the_operator()
	_seat_the_bot()
	_stage()
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


## The operator does no errands of its own.
func _quiet_the_operator() -> void:
	var pilot := _night.autopilot
	pilot.order.clear()
	pilot.wanted.clear()
	pilot.spots.clear()
	pilot.recut_price = 0
	pilot.tonic_price = 0
	pilot.switches.goals.clear()
	pilot.fuel.goals.clear()
	pilot.repair_goals.clear()
	pilot._yaw = _facing


func _seat_the_bot() -> void:
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world, _night.rules_tuning)
	var state := ClientState.new()
	state.player_id = BOT
	_host.add(
		BotClient.new(
			state, BotProfile.regular(), 100 + BOT, Callable(self, &"_send").bind(BOT), level
		)
	)


func _stage() -> void:
	var rules := _night.server.rules
	match _scenario:
		"door":
			rules.players[BOT].points = 400
		"boards":
			for _i in 3:
				rules.barricades.tear(&"n")
		"fuel":
			rules.players[BOT].points = 300
			_night.server.rules.apply(RulesAction.grant_points(Night.PLAYER_ID, 100000))
			RulesFixture.buy(rules, Night.PLAYER_ID, &"door_concession")
			rules.players[Night.PLAYER_ID].points = 0
			rules.generator.fuel = 20.0


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])


func _on_tick() -> void:
	_night.server.body_of(Night.PLAYER_ID).teleport(_operator)
	_night.autopilot._yaw = _facing
	_night.player().camera_rig.steer(_facing, 0.0)
	_host.tick(Night.STEP)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _arg(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return fallback
