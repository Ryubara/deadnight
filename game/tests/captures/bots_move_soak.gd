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
## `--speed=N` (ticks per frame, default 40), `--doors` (the stand-in is given the points and buys
## every door at the start, so the whole lot is walked, the ticket plaza too), `--count=X` (the
## dead's number, a fraction of the shipped), `--tough=X` (every player's health, a multiple of the
## shipped: the soak measures how bots walk, not whether they live), `--episodes` (print each
## bot's stuck episodes) and
## `--trace=FILE` (write every bot's position twice a second, one line each, to FILE),
## `--shop` (the bots do errands too: shopping, boards, the generator), `--idle` (print each time a
## bot has stood with nothing to do for six seconds), `--map=FILE` (write the footprints of the
## lot's solid things above the ground, one polygon a line, and the roam spots, for the top-down
## picture of a trace) and `--order=roam|follow|hold` (the standing order the person gives the bots
## through the same `BotOrders` the command wheel calls, once, at the start: default `follow`, which
## is what this soak was written to measure and what the #564 numbers are; the game's own default is
## `roam`. The within-12 m gate is Follow's, Roam and Hold have their own numbers below).
##
## Per bot the report also has `idle_longest` (the longest seconds standing with nothing to do),
## `cells` (10 m squares walked through), `kills`, `buys`, and `mean_distance`; for the run
## `spread` (the mean distance between two bots) and, for a hold, `within_hold_3m` (the share of the
## ticks a bot that is up stood within 3 m of the spot) and `within_hold_3m_on_the_spot` (the same
## of the ticks it was not on a trip for a revive, a ping or a dodge).
## For the play states (#693) the report also has, per bot, `downs` (the times it went down) and
## `states` (the seconds up in each play state, `BotPlayState`), and for the run `downs`,
## `rounds` (the rounds the night reached, the last one whole) and `downs_per_bot_per_round`:
## run it with `--tough=1` (the shipped health), since a tough night has no downs to count, and
## `--no-states` for the bots as they were before the play states (the state is still read),
## `--downs` (print the health before each down) and `--profile=name:value,...` (set numbers of the
## bots' profiles, for tuning).
## Prints `SOAK {json}` at the end: one object per bot and one for the whole run.

## The distance from the nearest person that counts as staying with them (metres).
const NEAR := 12.0
## Frames waited for a navigation bake a door started before quitting.
const BAKE_WAIT_FRAMES := 600
## Ticks between two trace lines.
const TRACE_EVERY := 30
## Metres from the held spot that the order promises, and the speed (m/s) under which a bot stands.
const HOLD_RADIUS := 3.0
const STANDING := 0.05
## Ticks of health kept before a down (four seconds), for `--downs`.
const HISTORY_TICKS := 240

var _args := {}
var _night: Night
var _host := BotHost.new()
var _probe: WorldProbe
var _seats: Array[int] = []
var _ticks := 0
var _limit := 0
var _near_ticks := 0
var _sampled_ticks := 0
## Of those, the ticks a bot was down or dead (it cannot follow), and the ones it was up and near.
var _down_ticks := 0
var _up_near_ticks := 0
var _per_round: Dictionary = {}
var _trace: FileAccess
var _closing := false
var _started_at := 0
var _was_stuck: Dictionary = {}
var _causes: Dictionary = {}
## Ticks spent farther than `NEAR` from the nearest person, by what the bot was doing.
var _far_notes: Dictionary = {}
## The standing order of the run, and the spot a hold keeps.
var _order: StringName = BotOrders.ROAM
var _hold_spot := Vector3.INF
## By seat: ticks standing with nothing to do in a row, the longest such run, the 10 m squares
## walked through, the sum of the distances to the nearest person and its count, the ticks up and
## the ticks up within the hold's radius of the spot.
var _still: Dictionary = {}
var _idle_longest: Dictionary = {}
var _cells: Dictionary = {}
var _distance_sum: Dictionary = {}
var _distance_n: Dictionary = {}
var _up_ticks := 0
var _held_ticks := 0
## Of the ticks up, the ones the bot was under the stance itself (not on a trip for a revive, a
## ping, a dodge or an errand), and of those the ones within the hold's radius.
var _stance_ticks := 0
var _stance_held := 0
var _spread_sum := 0.0
var _spread_n := 0
## By seat: whether the bot was down last tick, and how many times it went down, in all and by
## round (`{round: {seat: downs}}`).
var _was_down: Dictionary = {}
var _downs: Dictionary = {}
var _downs_by_round: Dictionary = {}
## By seat: the ticks up in each play state (`{seat: {state name: ticks}}`).
var _state_ticks: Dictionary = {}
## By seat: the bot's health share on each of the last `HISTORY_TICKS` ticks.
var _health_history: Dictionary = {}


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
	_give_the_order()
	if _args.has("no-states"):
		for bot in _host.bots:
			(bot.brain as BotFightBrain).play.enabled = false
	_tune_profiles()
	if _args.has("map"):
		_write_map(String(_args["map"]))
	if _args.has("trace"):
		_trace = FileAccess.open(String(_args["trace"]), FileAccess.WRITE)
	_night.state.event_received.connect(_on_event)
	_night.ticked.connect(_on_tick)
	if _args.has("doors"):
		_buy_every_door()


## `--profile=name:value,name:value` sets those numbers of every bot's profile (tuning the play
## states: `careful_below:0.7,safe_below:0.5`).
func _tune_profiles() -> void:
	for pair in String(_args.get("profile", "")).split(",", false):
		var parts := pair.split(":")
		for bot in _host.bots:
			bot.profile.set(parts[0], float(parts[1]))


## The person's word, once, as the wheel gives it. A roam is the game's default and sends nothing.
func _give_the_order() -> void:
	_order = StringName(String(_args.get("order", "follow")))
	var body := _night.server.body_of(Night.PLAYER_ID)
	_night.bot_orders.issue(_order, Night.PLAYER_ID, body.global_position)


## The lot seen from above: `box x1 z1 x2 z2 x3 z3 x4 z4` for every solid box that rises above the
## ground, `spot x z` for every place a roaming bot may go.
func _write_map(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	for node in _night.world.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.disabled or not (shape.shape is BoxShape3D):
			continue
		if not (shape.get_parent() is StaticBody3D):
			continue
		var size := (shape.shape as BoxShape3D).size
		var top := shape.global_transform * Vector3(0.0, size.y * 0.5, 0.0)
		if top.y < 0.4:
			continue
		var line := PackedStringArray(["box"])
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var at := (
				shape.global_transform
				* Vector3(corner.x * size.x * 0.5, 0.0, corner.y * size.z * 0.5)
			)
			line.append("%.2f %.2f" % [at.x, at.z])
		file.store_line(" ".join(line))
	for spot in _seats_level_spots():
		file.store_line("spot %.2f %.2f" % [spot.x, spot.z])
	file.close()


func _seats_level_spots() -> Array[Vector3]:
	return _host.bots[0].level.roam_spots if not _host.bots.is_empty() else []


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
	# The shop (errands: doors, boards, the generator, what to buy) only with `--shop`.
	LotBotData.fill(level, _night.world, _night.rules_tuning if _args.has("shop") else null)
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


## Every door, in the shop's order, bought for the stand-in with points it was given.
func _buy_every_door() -> void:
	for item: StringName in [
		&"door_concession", &"door_yard", &"door_booth", &"door_back_lot", &"door_road"
	]:
		_night.server.rules.apply(RulesAction.grant_points(Night.PLAYER_ID, 100000))
		_night.server.apply(RulesAction.buy(Night.PLAYER_ID, item), Night.PLAYER_ID)


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
	_sample_orders()
	_sample_downs()
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
		var down := false
		for bot in _host.bots:
			if bot.state.player_id == id:
				var me := bot.state.me()
				down = me.is_empty() or me.get("downed", false) or me.get("dead", false)
		if down:
			_down_ticks += 1
		if apart <= NEAR:
			_near_ticks += 1
			tally[0] += 1
			if not down:
				_up_near_ticks += 1
		elif not down:
			for bot in _host.bots:
				if bot.state.player_id == id:
					var note: String = bot.intent.note
					_far_notes[note] = int(_far_notes.get(note, 0)) + 1
	_per_round[round_number] = tally


## Per tick, per bot that is up: standing with nothing to do, the squares walked through, the
## distance to the person, the share within the hold's radius, and the spread of the team.
func _sample_orders() -> void:
	if _hold_spot == Vector3.INF and _order == BotOrders.HOLD:
		var held: Dictionary = _night.state.frame.get(BotOrders.FRAME_KEY, {})
		var team: Dictionary = held.get("team", {})
		if not team.is_empty():
			_hold_spot = team["at"]
	var human := _night.server.body_of(Night.PLAYER_ID)
	var places: Array[Vector3] = []
	for bot in _host.bots:
		var id := bot.state.player_id
		var me := bot.state.me()
		var body := _night.server.body_of(id)
		if body == null or me.is_empty() or me.get("downed", false) or me.get("dead", false):
			_still[id] = 0
			continue
		places.append(body.global_position)
		_up_ticks += 1
		var note: String = bot.intent.note
		# Idle is standing with nothing to do: a fight, a revive, an errand, a look about and a held
		# place are all something; a bot that says it roams (or holds, or nothing) and does not move is
		# waiting for no reason.
		var idle_note := note == "" or note == "hold" or note == "roam"
		var standing := body.velocity.length() < STANDING and idle_note
		_still[id] = int(_still.get(id, 0)) + 1 if standing else 0
		_idle_longest[id] = maxi(int(_idle_longest.get(id, 0)), int(_still[id]))
		if _args.has("idle") and int(_still[id]) == 360:
			print(
				(
					"IDLE seat %d note %s goal %s at %s tick %d status %s wish %s stuck %s"
					% [
						id,
						note,
						bot.intent.goal.snappedf(0.1),
						body.global_position.snappedf(0.1),
						_ticks,
						bot.legs.path.last_status,
						bot.legs.wish.snappedf(0.1),
						bot.legs.stuck.stuck
					]
				)
			)
		var cells: Dictionary = _cells.get(id, {})
		var at := body.global_position
		cells[Vector2i(floori(at.x / 10.0), floori(at.z / 10.0))] = true
		_cells[id] = cells
		if human != null:
			_distance_sum[id] = float(_distance_sum.get(id, 0.0)) + _flat_apart(body, human)
			_distance_n[id] = int(_distance_n.get(id, 0)) + 1
		if _hold_spot != Vector3.INF:
			var off := Vector2(
				body.global_position.x - _hold_spot.x, body.global_position.z - _hold_spot.z
			)
			if off.length() <= HOLD_RADIUS:
				_held_ticks += 1
			if note == "hold_order" or note == "fight" or note == "throw":
				_stance_ticks += 1
				if off.length() <= HOLD_RADIUS:
					_stance_held += 1
	for i in places.size():
		for j in range(i + 1, places.size()):
			_spread_sum += Vector2(places[i].x - places[j].x, places[i].z - places[j].z).length()
			_spread_n += 1


## What the bot's health did over the last seconds before it went down, and where it stood
## (`--downs`).
func _print_down(bot: BotClient, history: Array, round_number: int) -> void:
	var samples: Array[String] = []
	for i in range(0, history.size(), 30):
		samples.append("%.2f" % history[i])
	var body := _night.server.body_of(bot.state.player_id)
	print(
		(
			"DOWN seat %d round %d tick %d state %s note %s health_every_half_second [%s] at %s"
			% [
				bot.state.player_id,
				round_number,
				_ticks,
				(bot.brain as BotFightBrain).play_state_name(),
				bot.intent.note,
				", ".join(samples),
				body.global_position.snappedf(0.1) if body != null else Vector3.ZERO,
			]
		)
	)


## Per tick, per bot: a fall from up to down is a down, and the play state of a bot that is up.
func _sample_downs() -> void:
	var round_number := _night.state.round_number()
	for bot in _host.bots:
		var id := bot.state.player_id
		var me := bot.state.me()
		var down: bool = me.is_empty() or me.get("downed", false) or me.get("dead", false)
		var history: Array = _health_history.get(id, [])
		history.append(float(me.get("health", 0.0)) / bot.perception.beliefs.max_health)
		if history.size() > HISTORY_TICKS:
			history.pop_front()
		_health_history[id] = history
		if down and not _was_down.get(id, false):
			if _args.has("downs"):
				_print_down(bot, history, round_number)
			_downs[id] = int(_downs.get(id, 0)) + 1
			var by_seat: Dictionary = _downs_by_round.get(round_number, {})
			by_seat[id] = int(by_seat.get(id, 0)) + 1
			_downs_by_round[round_number] = by_seat
		_was_down[id] = down
		if not down:
			var label := String((bot.brain as BotFightBrain).play_state_name())
			var ticks: Dictionary = _state_ticks.get(id, {})
			ticks[label] = int(ticks.get(label, 0)) + 1
			_state_ticks[id] = ticks


func _flat_apart(a: Node3D, b: Node3D) -> float:
	return (
		Vector2(
			a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z
		)
		. length()
	)


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
	var total_downs := 0
	for id: int in _downs:
		total_downs += int(_downs[id])
	var rounds_reached := _night.state.round_number()
	var downs_by_round := {}
	for round_number: int in _downs_by_round:
		var sum := 0
		for id: int in _downs_by_round[round_number]:
			sum += int(_downs_by_round[round_number][id])
		downs_by_round[round_number] = sum
	var all := {
		"why": why,
		"downs": total_downs,
		"rounds": rounds_reached,
		"downs_per_bot_per_round":
		snappedf(float(total_downs) / maxf(float(_seats.size() * rounds_reached), 1.0), 0.001),
		"downs_by_round": downs_by_round,
		"seed": int(_args.get("seed", 1)),
		"game_minutes": snappedf(float(_ticks) / 3600.0, 0.01),
		"wall_seconds": snappedf(float(Time.get_ticks_msec() - _started_at) / 1000.0, 0.1),
		"round": _night.state.round_number(),
		"within_12m": snappedf(float(_near_ticks) / maxf(float(_sampled_ticks), 1.0), 0.0001),
		"down_ticks": _down_ticks,
		"within_12m_up":
		snappedf(float(_up_near_ticks) / maxf(float(_sampled_ticks - _down_ticks), 1.0), 0.0001),
		"within_12m_by_round": rounds,
		"order": String(_order),
		"spread": snappedf(_spread_sum / maxf(float(_spread_n), 1.0), 0.1),
		"within_hold_3m": snappedf(float(_held_ticks) / maxf(float(_up_ticks), 1.0), 0.0001),
		"within_hold_3m_on_the_spot":
		snappedf(float(_stance_held) / maxf(float(_stance_ticks), 1.0), 0.0001),
		"stuck_causes": _causes,
		"far_ticks_by_note": _far_notes,
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
		"downs": int(_downs.get(bot.state.player_id, 0)),
		"state_changes": int(bot.telemetry.counters.get(&"play_state_changes", 0)),
		"states": _state_seconds(bot.state.player_id),
		"buys": int(bot.telemetry.counters.get(&"buys", 0)),
		"idle_longest": snappedf(float(_idle_longest.get(bot.state.player_id, 0)) / 60.0, 0.1),
		"cells": (_cells.get(bot.state.player_id, {}) as Dictionary).size(),
		"mean_distance":
		snappedf(
			(
				float(_distance_sum.get(bot.state.player_id, 0.0))
				/ maxf(float(_distance_n.get(bot.state.player_id, 0)), 1.0)
			),
			0.1
		),
	}


## The seconds a bot was up in each play state.
func _state_seconds(id: int) -> Dictionary:
	var seconds := {}
	var ticks: Dictionary = _state_ticks.get(id, {})
	for label: String in ticks:
		seconds[label] = snappedf(float(ticks[label]) / 60.0, 0.1)
	return seconds


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
