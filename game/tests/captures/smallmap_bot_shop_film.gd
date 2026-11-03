extends Node
## Four Regular bots shopping on the second map, filmed through the first one's own shoulder camera:
## with the links open and points to spend they walk to the soda fountain, the re-cut bench upstairs
## and the coolers (#811). The capture that goes with `test_smallmap_bot_machines.gd`. Not part of
## the game.
## Run with Movie Maker through the kit's `gds godot`, so no window takes the keyboard:
## `gds godot -- --path game res://tests/captures/smallmap_bot_shop_film.tscn --fixed-fps 10
## --write-movie out.png --quit-after 1500`.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const POINTS := 12000
const SEATS := [2, 3, 4]
const TOUGH := 20.0

var _night: Night
var _host := BotHost.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	_night.scene = load(SCENE) as PackedScene
	add_child(_night)
	# Tough bodies, so the film is of the shopping and not of the first round's end.
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= TOUGH
	await _night.start(Night.Mode.AUTOPILOT, 7, tuning)
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world, _night.rules_tuning)
	_night.bot = BotClient.new(_night.state, BotProfile.regular(), 101, _night.link.send, level)
	var rules := _night.server.rules
	for id: int in SEATS:
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	await get_tree().physics_frame
	for id: int in SEATS:
		var state := ClientState.new()
		state.player_id = id
		_host.add(
			BotClient.new(
				state, BotProfile.regular(), 100 + id, Callable(self, &"_send").bind(id), level
			)
		)
	for item in rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			RulesFixture.buy(rules, 1, item.id)
	for id: int in rules.players:
		rules.players[id].points = POINTS
	_night.ticked.connect(_on_tick)
	_night.state.event_received.connect(_on_event)


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])
	if event["type"] == &"purchase_made":
		print("BOUGHT ", event["item_id"], " at ", Time.get_ticks_msec())


func _on_tick() -> void:
	_host.tick(Night.STEP)
