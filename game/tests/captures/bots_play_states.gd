extends Node
## A bot's play state filmed through the person's shoulder camera (#693): the person (the old
## autopilot) stands with one hosted bot (a Regular) beside the lot's home spot while the dead come
## slowly. At first the bot is healthy and plays aggressive: it stands and shoots. A blow takes most
## of its health, it turns safe and backs away from the dead (a wide margin, open ground), and when
## its health has come back it goes through careful to aggressive again. A label names the bot's
## state and health. With `--hold` the person gives the Hold order first, so the bot is a holder
## that steps back from its spot. Not part of the game. Run with Movie Maker through the kit's
## `gds godot` so no window takes the person's keyboard:
## `gds godot -- --path game res://tests/captures/bots_play_states.tscn --fixed-fps 10
## --write-movie out.png --quit-after 600 -- --hold`. `--trace` prints the bot's state, health and
## the metres to the nearest zombie every half second.

const SEAT := 2
## Frames (at the recording's 10 a second) before the bot may be hurt, and how much of its health
## the blow takes (a share of full).
const HURT_AT := 60
## The blow comes once a zombie is this near the bot (metres), so the film shows it backing away.
const HURT_WHEN_NEAR := 9.0
const HURT_SHARE := 0.75
## The bot's health is three times the shipped, so the film shows the states and not a down.
const TOUGH := 1.0
## Metres in front of the person the bot is put.
## Frames traced with `--trace` (one line every five).
const TRACE_FRAMES := 3000
const BOT_AHEAD := 3.0

var _args := {}
var _night: Night
var _host := BotHost.new()
var _label: Label
var _frames := 0
var _hurt := false


func _ready() -> void:
	_args = _parse_args()
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
	tuning.rounds.speed_base = 1.0
	tuning.rounds.first_spawn_delay = 3.0
	tuning.rounds.intro_seconds = 1.0
	tuning.health.max_health *= TOUGH
	await _night.start(Night.Mode.AUTOPILOT, 7, tuning)
	_night.link.send({"type": NightServer.JOIN, "player_id": SEAT, "local": false})
	for _i in 3:
		await get_tree().physics_frame
	_seat_the_bot()
	_night.server.rules.apply(RulesAction.skip_break())
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)
	var person := _night.server.body_of(Night.PLAYER_ID)
	var bot := _night.server.body_of(SEAT)
	var at := Autopilot.HOME + Vector3(0.0, 0.1, 6.0)
	person.teleport(at)
	bot.teleport(at + Vector3(2.0, 0.0, -BOT_AHEAD))
	if _args.has("hold"):
		_night.bot_orders.issue(BotOrders.HOLD, Night.PLAYER_ID, bot.global_position)


func _seat_the_bot() -> void:
	var probe := WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world)
	var state := ClientState.new()
	state.player_id = SEAT
	_host.add(
		BotClient.new(
			state, BotProfile.veteran(), 100 + SEAT, Callable(self, &"_send").bind(SEAT), level
		)
	)


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])


func _on_tick() -> void:
	_host.tick(Night.STEP)


func _process(_delta: float) -> void:
	_frames += 1
	if _night == null or not _night.running or _host.bots.is_empty():
		return
	var bot := _host.bots[0]
	var me := bot.state.me()
	if not _hurt and _frames >= HURT_AT and _dead_near(SEAT, HURT_WHEN_NEAR):
		_hurt = true
		var max_health := _night.server.rules.max_health_of(SEAT)
		_night.server.rules.apply(RulesAction.blow(SEAT, max_health * HURT_SHARE))
	var share := float(me.get("health", 0.0)) / bot.perception.beliefs.max_health
	var brain := bot.brain as BotFightBrain
	if _args.has("trace") and _frames % 5 == 0 and _frames < TRACE_FRAMES:
		print(
			(
				"TRACE frame %d state %s health %d%% nearest_dead %.1f m note %s"
				% [
					_frames,
					brain.play_state_name(),
					roundi(share * 100.0),
					_nearest_dead(SEAT),
					bot.intent.note,
				]
			)
		)
	_label.text = (
		"BOT  %s  %d%%  (%s)"
		% [
			String(brain.play_state_name()).to_upper(),
			roundi(share * 100.0),
			"HOLD" if _args.has("hold") else "ROAM",
		]
	)


func _dead_near(seat: int, metres: float) -> bool:
	return _nearest_dead(seat) <= metres


## Metres from the bot to the nearest zombie (INF for none).
func _nearest_dead(seat: int) -> float:
	var body := _night.server.body_of(seat)
	var best := INF
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		var apart := Vector2(
			zombie.position.x - body.global_position.x, zombie.position.z - body.global_position.z
		)
		best = minf(best, apart.length())
	return best


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
