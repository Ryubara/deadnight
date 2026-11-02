extends Node
## The movement soak of the bots plan (phase 2): a stand-in for a person (the old autopilot, seat 1,
## who shops, opens the doors and fights) and hosted bots (seats 2 on) play a night, and the numbers
## of how the bots got around are printed: seconds stuck against seconds walking, the longest stuck
## episode, how far from the nearest person they stood, the questions they put to the navigation
## server, what a tick cost. A local or nightly measurement, not a test: twenty minutes of play is a
## long run. Not part of the game.
##
## `godot --headless --path game res://tests/captures/bots_move_soak.tscn -- --seed=1 --minutes=20`
## Arguments after `--`: `--seed=N`, `--minutes=M` (game minutes), `--bots=N` (default 4),
## `--speed=N` (ticks per frame, default 40), `--count=X` (the dead's number, a fraction of the
## shipped), `--tough=X` (every player's health, a multiple of the shipped: the soak measures how
## bots walk, not whether they live), `--episodes` (print each bot's stuck episodes) and
## `--trace=FILE` (write every bot's position twice a second, one line each, to FILE).
## Prints `SOAK {json}` at the end: one object per bot and one for the whole run.

## The distance from the nearest person that counts as staying with them (metres).
const NEAR := 12.0
## Frames waited for a navigation bake a door started before quitting.
const BAKE_WAIT_FRAMES := 600
## Ticks between two trace lines.
const TRACE_EVERY := 30

var _args := {}
var _night: Night
var _host := BotHost.new()
var _probe: WorldProbe
var _seats: Array[int] = []
var _ticks := 0
var _limit := 0
var _near_ticks := 0
var _sampled_ticks := 0
var _per_round: Dictionary = {}
var _trace: FileAccess
var _closing := false
var _started_at := 0
var _was_stuck: Dictionary = {}
var _causes: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	_started_at = Time.get_ticks_msec()
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	_night = Night.new()
	_night.hud = hud
	_night.match_settings = _match_settings()
	add_child(_night)
	_night.ticks_per_frame = int(_args.get("speed", 40))
	_limit = int(float(_args.get("minutes", 20)) * 60.0 * 60.0)
	await _night.start(Night.Mode.AUTOPILOT, int(_args.get("seed", 1)), _tuning())
	var count := int(_args.get("bots", 4))
	for i in count:
		var id := 2 + i
		_seats.append(id)
		_night.link.send({"type": NightServer.JOIN, "player_id": id, "local": false})
	await _wait(3)
	_seat_the_bots()
	if _args.has("trace"):
		_trace = FileAccess.open(String(_args["trace"]), FileAccess.WRITE)
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)


func _match_settings() -> MatchSettings:
	var settings := MatchSettings.new()
	settings.count_multiplier = float(_args.get("count", 1.0))
	return settings.clamped()


func _tuning() -> RulesTuning:
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 1.0))
	return tuning


func _seat_the_bots() -> void:
	_probe = WorldProbe.new(_night.get_world_3d().direct_space_state)
	var level := BotLevel.new(
		_probe.callable(), _night.world.is_lit, _night.rules_tuning.rounds, _night.world.map()
	)
	LotBotData.fill(level, _night.world)
	var profiles: Array[BotProfile] = [
		BotProfile.regular(), BotProfile.veteran(), BotProfile.rookie(), BotProfile.regular()
	]
	for i in _seats.size():
		var state := ClientState.new()
		state.player_id = _seats[i]
		_host.add(
			BotClient.new(
				state,
				profiles[i % profiles.size()],
				1000 + _seats[i] + 100 * int(_args.get("seed", 1)),
				Callable(self, &"_send").bind(_seats[i]),
				level
			)
		)


func _send(action: Dictionary, id: int) -> void:
	_night.server.apply(bytes_to_var(var_to_bytes(action)), id)


func _on_event(event: Dictionary) -> void:
	_host.hear([event])


func _on_tick() -> void:
	if _closing or not _night.running:
		if _night.state.over and not _closing:
			_finish("game over in round %d" % _night.state.round_number())
		return
	_ticks += 1
	_host.tick(Night.STEP)
	_sample_distances()
	_classify_stuck()
	if _trace != null and _ticks % TRACE_EVERY == 0:
		_write_trace()
	if _ticks >= _limit:
		_finish("time")


## How far each bot is from the nearest person (seat 1, while that person is up), by the server's
## truth, every tick.
func _sample_distances() -> void:
	var human := _night.server.body_of(Night.PLAYER_ID)
	var frame_me := _night.state.me()
	if human == null or frame_me.is_empty() or frame_me.get("downed", false):
		return
	var round_number := _night.state.round_number()
	var tally: Array = _per_round.get(round_number, [0, 0])
	for id in _seats:
		var body := _night.server.body_of(id)
		if body == null:
			continue
		var apart := (
			Vector2(
				body.global_position.x - human.global_position.x,
				body.global_position.z - human.global_position.z
			)
			. length()
		)
		_sampled_ticks += 1
		tally[1] += 1
		if apart <= NEAR:
			_near_ticks += 1
			tally[0] += 1
	_per_round[round_number] = tally


## What each stuck episode ran into when it began, by the physics engine's word: another player (a
## bot or the person) or a part of the lot (named), counted for the report.
func _classify_stuck() -> void:
	for bot in _host.bots:
		var id := bot.state.player_id
		var now: bool = bot.legs.stuck.stuck
		if now and not _was_stuck.get(id, false):
			var cause := _what_it_ran_into(id)
			if _args.has("causes"):
				var body := _night.server.body_of(id)
				print(
					(
						"CAUSE %s seat %d at %s wish %s vel %s goal %s note %s"
						% [
							cause,
							id,
							body.global_position.snappedf(0.1),
							bot.intent.wish.snappedf(0.1),
							body.velocity.snappedf(0.1),
							bot.intent.goal.snappedf(0.1),
							bot.intent.note
						]
					)
				)
				if cause == "bot":
					for other in _host.bots:
						var ob := _night.server.body_of(other.state.player_id)
						if (
							other.state.player_id != id
							and ob.global_position.distance_to(body.global_position) < 2.0
						):
							print(
								(
									"   PARTNER seat %d at %s wish %s vel %s goal %s note %s"
									% [
										other.state.player_id,
										ob.global_position.snappedf(0.1),
										other.intent.wish.snappedf(0.1),
										ob.velocity.snappedf(0.1),
										other.intent.goal.snappedf(0.1),
										other.intent.note
									]
								)
							)
			_causes[cause] = int(_causes.get(cause, 0)) + 1
		_was_stuck[id] = now


func _what_it_ran_into(id: int) -> String:
	var body := _night.server.body_of(id)
	var cause := "none"
	for i in body.get_slide_collision_count():
		# The floor is under every body: only what stands in the way counts.
		if body.get_slide_collision(i).get_normal().y > 0.5:
			continue
		var collider := body.get_slide_collision(i).get_collider()
		if collider is CharacterBody3D:
			for other_id in [Night.PLAYER_ID] + _seats:
				if other_id != id and _night.server.body_of(other_id) == collider:
					return "human" if other_id == Night.PLAYER_ID else "bot"
			return "player"
		if collider is Node:
			cause = "world:%s" % (collider as Node).name
	return cause


func _write_trace() -> void:
	var line := PackedStringArray()
	var human := _night.server.body_of(Night.PLAYER_ID)
	line.append("%d h %.2f %.2f" % [_ticks, human.global_position.x, human.global_position.z])
	for id in _seats:
		var body := _night.server.body_of(id)
		line.append("b%d %.2f %.2f" % [id, body.global_position.x, body.global_position.z])
	_trace.store_line(" | ".join(line))


func _finish(why: String) -> void:
	_closing = true
	var bots: Array[Dictionary] = []
	for bot in _host.bots:
		bots.append(_bot_report(bot))
	var rounds := {}
	for round_number: int in _per_round:
		var tally: Array = _per_round[round_number]
		rounds[round_number] = snappedf(float(tally[0]) / maxf(float(tally[1]), 1.0), 0.001)
	var all := {
		"why": why,
		"seed": int(_args.get("seed", 1)),
		"game_minutes": snappedf(float(_ticks) / 3600.0, 0.01),
		"wall_seconds": snappedf(float(Time.get_ticks_msec() - _started_at) / 1000.0, 0.1),
		"round": _night.state.round_number(),
		"within_12m": snappedf(float(_near_ticks) / maxf(float(_sampled_ticks), 1.0), 0.0001),
		"within_12m_by_round": rounds,
		"stuck_causes": _causes,
		"bots": bots,
	}
	print("SOAK ", JSON.stringify(all))
	if _args.has("episodes"):
		for bot in _host.bots:
			for episode in bot.legs.episodes:
				print("EPISODE seat=%d %s" % [bot.state.player_id, JSON.stringify(episode)])
	if _trace != null:
		_trace.close()
	_close_down()


func _bot_report(bot: BotClient) -> Dictionary:
	var gauges := bot.telemetry.gauges
	var walking := float(gauges.get(&"walking_seconds", 0.0))
	var stuck := float(gauges.get(&"stuck_seconds", 0.0))
	var stuck_reports: Array[Dictionary] = []
	for entry in bot.telemetry.events:
		if entry["name"] == &"bot_stuck":
			(
				stuck_reports
				. append(
					{
						"tick": entry["tick"],
						"position": entry["position"],
						"goal": entry["goal"],
						"rungs": entry["rungs"],
					}
				)
			)
	return {
		"seat": bot.state.player_id,
		"profile": bot.profile.title,
		"walking_seconds": snappedf(walking, 0.1),
		"stuck_seconds": snappedf(stuck, 0.1),
		"stuck_share": snappedf(stuck / maxf(walking, 1.0), 0.0001),
		"longest_stuck": snappedf(float(gauges.get(&"longest_stuck", 0.0)), 0.1),
		"ladder_depth_max": int(gauges.get(&"ladder_depth_max", 0.0)),
		"yielded_seconds": snappedf(float(gauges.get(&"yielded_seconds", 0.0)), 0.1),
		"path_queries": int(gauges.get(&"path_queries", 0.0)),
		"path_queries_per_second":
		snappedf(float(gauges.get(&"path_queries", 0.0)) / maxf(float(_ticks) / 60.0, 1.0), 0.01),
		"path_empty": int(gauges.get(&"path_empty", 0.0)),
		"unreachable_marks": int(gauges.get(&"unreachable_goals", 0.0)),
		"distance_p50": snappedf(bot.telemetry.quantile(&"distance_to_human", 0.5), 0.1),
		"distance_p95": snappedf(bot.telemetry.quantile(&"distance_to_human", 0.95), 0.1),
		"think_us_p50": bot.telemetry.think_us(0.5),
		"think_us_p99": bot.telemetry.think_us(0.99),
		"legs_us_p50": snappedf(bot.telemetry.quantile(&"legs_us", 0.5), 1.0),
		"legs_us_p99": snappedf(bot.telemetry.quantile(&"legs_us", 0.99), 1.0),
		"bot_stuck_reports": stuck_reports,
		"brain_disabled": bot.telemetry.has_event(BotClient.BRAIN_DISABLED),
		"kills": bot.state.kills,
	}


func _close_down() -> void:
	_night.running = false
	# A bake the last door bought started runs on a worker thread; quitting under it kills the
	# engine: let it land first.
	for _i in BAKE_WAIT_FRAMES:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	_night.queue_free()
	await _night.tree_exited
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
