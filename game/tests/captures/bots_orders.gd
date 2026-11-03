extends Node
## The three orders filmed through the person's own shoulder camera (#641): the old autopilot is the
## person, three hosted bots (a Rookie, a Regular and a Veteran) are lined up beside them, and the
## person gives the orders the way the command wheel does, through `BotOrders.issue` on
## `Night.bot_orders`: nothing at first (the bots roam off across the lot), then Follow (they come
## and stay by the person), then Hold (they stay where the order was given while the person goes
## on). A label names the order in force. Not part of the game. Run with Movie Maker through the
## kit's `gds godot` so no window takes the person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_orders.tscn --fixed-fps 10
## --write-movie out.png --quit-after 450`.

const SEATS := [2, 3, 4]
## Metres between the bodies in the line-up.
const SPACING := 3.0
## Frames (at the recording's 10 a second) at which the orders are given.
const FOLLOW_AT := 150
const HOLD_AT := 300

var _night: Night
var _host := BotHost.new()
var _label: Label
var _frames := 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)
	_night = Night.new()
	_night.hud = hud
	_night.shoulder_camera = true
	add_child(_night)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.0
	tuning.rounds.first_spawn_delay = 6.0
	tuning.rounds.intro_seconds = 1.0
	tuning.health.max_health *= 3.0
	await _night.start(Night.Mode.AUTOPILOT, 7, tuning)
	for id: int in SEATS:
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	for _i in 3:
		await get_tree().physics_frame
	_seat_the_hosted_bots()
	_night.server.rules.apply(RulesAction.skip_break())
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)
	_line_up()
	_say("ROAM (default)")


func _seat_the_hosted_bots() -> void:
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world)
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


func _line_up() -> void:
	var seats: Array = [Night.PLAYER_ID] + SEATS
	for i in seats.size():
		var at := Autopilot.HOME + Vector3(SPACING * (float(i) - 1.5), 0.1, 6.0)
		_night.server.body_of(seats[i]).teleport(at)


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])


func _on_tick() -> void:
	_host.tick(Night.STEP)


func _process(_delta: float) -> void:
	_frames += 1
	if _night == null or not _night.running:
		return
	var body := _night.server.body_of(Night.PLAYER_ID)
	if _frames == FOLLOW_AT:
		_night.bot_orders.issue(BotOrders.FOLLOW, Night.PLAYER_ID, body.global_position)
		_say("FOLLOW")
	elif _frames == HOLD_AT:
		_night.bot_orders.issue(BotOrders.HOLD, Night.PLAYER_ID, body.global_position)
		_say("HOLD")


func _say(text: String) -> void:
	_label.text = "ORDER  %s" % text
