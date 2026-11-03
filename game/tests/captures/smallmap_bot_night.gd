extends Node
## A bot night on the second map: hosted bots alone in the small indoor map play until a round is
## reached (or they all fall, or the minutes run out), and what happened is printed: the round
## each link was bought in, the boards the dead tore at each window, what was bought and where,
## the box's plays, the most dead at once, the downs, and the balance numbers of the map.
## A local or nightly measurement; `test_smallmap_bot_night.gd` runs a short one.
##
## `godot --headless --path game res://tests/captures/smallmap_bot_night.tscn --
##   --bots=4 --rounds=10`
## Arguments after `--`: `--seed=N`, `--bots=N` (default 1), `--rounds=N` (stop after this round
## ends; default 10), `--minutes=M` (game minutes at most; default 60), `--profile=rookie|regular|
## veteran|mixed` (default mixed), `--tough=X` (every player's health as a multiple of the shipped),
## `--open=all` (or link ids, comma separated: sold before the night), `--trace` (a line every 15 s;
## with `--short` without what each bot wants, with `--zombies` with each standing zombie).
## Prints `SMALLMAP {json}` at the end.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
## Ticks between the physics frames the engine is given (a bought link needs one).
const FRAME_EVERY := 30
const TRACE_EVERY := 900

var _args := {}
var _night: SeatedNight
var _links: Dictionary = {}
var _tears: Dictionary = {}
var _repairs := 0
var _spent: Dictionary = {}
var _buys: Dictionary = {}
var _rounds: Dictionary = {}
var _ends: Dictionary = {}
var _downs := 0
var _revives := 0
var _kills := 0
var _box_plays := 0
var _most_alive := 0
var _box_spots: Dictionary = {}
var _entered: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 1.0))
	var seed_value := int(_args.get("seed", 1))
	var count := int(_args.get("bots", 1))
	_night = await SeatedNight.start(self, count, tuning, seed_value, true, load(SCENE))
	var profiles := _profiles(count)
	for i in profiles.size():
		_night.seat(i + 1, profiles[i], 1000 + 100 * seed_value + i)
	_night.on_event = _on_event
	if _args.has("open"):
		# The links sold before the night, as a team that bought them all would have: the whole map.
		# (`open_door` grants the points to pay with; they are taken back after.)
		var points_before := _night.server.rules.points_of(1)
		for link in String(_args["open"]).split(","):
			if link == "all":
				for item in _night.server.rules.tuning.economy.items:
					if item.kind == ShopItem.Kind.DOOR:
						_night.open_door(item.id)
			else:
				_night.open_door(StringName(link))
		_night.server.rules.players[1].points = points_before
		await _night.settle(10)
	_night.start_round()
	var target_round := int(_args.get("rounds", 10))
	var limit := int(float(_args.get("minutes", 60)) * 60.0 * 60.0)
	var ticks := 0
	var started := Time.get_ticks_msec()
	while ticks < limit and _night.server.rules.phase != GameRules.Phase.OVER:
		_night.tick()
		ticks += 1
		_most_alive = maxi(_most_alive, _night.server.sim.standing_count())
		if _args.has("trace") and ticks % TRACE_EVERY == 0:
			_trace(ticks)
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame
		if _ends.has(target_round):
			break
	_report(ticks, float(Time.get_ticks_msec() - started) / 1000.0)
	for _i in 600:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	_night.dispose()
	await get_tree().process_frame
	get_tree().quit()


func _profiles(count: int) -> Array[BotProfile]:
	var found: Array[BotProfile] = []
	var kind := String(_args.get("profile", "mixed"))
	for i in count:
		match kind:
			"rookie":
				found.append(BotProfile.rookie())
			"regular":
				found.append(BotProfile.regular())
			"veteran":
				found.append(BotProfile.veteran())
			_:
				found.append(
					[BotProfile.regular(), BotProfile.veteran(), BotProfile.rookie()][i % 3]
				)
	return found


func _trace(ticks: int) -> void:
	var rules := _night.server.rules
	var line := (
		"TRACE t=%ds round=%d phase=%d remaining=%d alive=%d links=%s"
		% [
			ticks / 60,
			rules.round_number,
			rules.phase,
			rules.zombies_remaining(),
			_night.server.sim.standing_count(),
			str(_links.keys())
		]
	)
	for bot in _night.host.bots:
		var at := _night.server.body_of(bot.state.player_id).global_position
		line += (
			" | %d pts=%d %s (%d,%d,%d) goal=%s"
			% [
				bot.state.player_id,
				rules.points_of(bot.state.player_id),
				bot.intent.note,
				at.x,
				at.y,
				at.z,
				str(bot.intent.goal)
			]
		)
		if _args.has("short"):
			line += " arms=%s" % str(_night.frame["players"][bot.state.player_id]["arms"])
		var errands: BotErrands = (bot.brain as BotFightBrain).get(&"_errands")
		if errands != null and not _args.has("short"):
			line += " wants=%s" % str(errands.wants_now())
	if _args.has("zombies"):
		for zombie: ZombieBody in _night.server.sim.zombies.values():
			if zombie.is_alive():
				line += (
					" Z%d(%.0f,%.1f,%.0f m%d g=%s t=%d)"
					% [
						zombie.id,
						zombie.position.x,
						zombie.position.y,
						zombie.position.z,
						zombie.mode,
						zombie.gate_id,
						zombie.target_id
					]
				)
	print(line)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"purchase_made":
			var item := _night.server.rules.tuning.economy.item(event["item_id"])
			var key := String(event["item_id"])
			_buys[key] = int(_buys.get(key, 0)) + 1
			_spent[item.kind] = int(_spent.get(item.kind, 0)) + int(event["price"])
			if item.kind == ShopItem.Kind.CRANE:
				_box_plays += 1
				_box_spots[_night.server.rules.crane.spot] = true
		&"door_opened":
			_links[String(event["door_id"])] = _night.server.rules.round_number
		&"player_hurt":
			if _args.has("trace") and _args.has("hurts"):
				_print_hurt(event)
		&"board_torn":
			var id := String(event["barricade_id"])
			_tears[id] = int(_tears.get(id, 0)) + 1
		&"board_repaired":
			_repairs += 1
		&"round_started":
			_rounds[event["round"]] = snappedf(float(_night.server.tick_count) / 60.0, 0.1)
		&"round_ended":
			_ends[event["round"]] = snappedf(float(_night.server.tick_count) / 60.0, 0.1)
		&"player_downed":
			_downs += 1
			if _args.has("trace"):
				var at := _night.server.body_of(event["player_id"]).global_position
				print(
					(
						"DOWN t=%.1f seat=%d at (%.1f, %.1f, %.1f) round=%d alive=%d"
						% [
							float(_night.server.tick_count) / 60.0,
							event["player_id"],
							at.x,
							at.y,
							at.z,
							_night.server.rules.round_number,
							_night.server.sim.standing_count()
						]
					)
				)
		&"player_revived":
			_revives += 1
		&"zombie_removed":
			if event["cause"] == &"killed":
				_kills += 1


func _print_hurt(event: Dictionary) -> void:
	var me := _night.server.body_of(event["player_id"]).global_position
	var line := (
		"HURT t=%.1f seat=%d dmg=%d left=%d at (%.1f,%.1f,%.1f)"
		% [
			float(_night.server.tick_count) / 60.0,
			event["player_id"],
			event["damage"],
			event["health"],
			me.x,
			me.y,
			me.z
		]
	)
	for bot in _night.host.bots:
		if bot.state.player_id == event["player_id"]:
			line += " note=%s goal=%s" % [bot.intent.note, str(bot.intent.goal)]
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		var apart := Vector2(zombie.position.x - me.x, zombie.position.z - me.z).length()
		if apart < 3.5 and zombie.is_alive():
			line += (
				" Z%d(d=%.1f dy=%.1f m%d)"
				% [zombie.id, apart, zombie.position.y - me.y, zombie.mode]
			)
	print(line)


func _report(ticks: int, wall_seconds: float) -> void:
	var rules := _night.server.rules
	var bots: Array[Dictionary] = []
	for bot in _night.host.bots:
		var id: int = bot.state.player_id
		(
			bots
			. append(
				{
					"seat": id,
					"profile": bot.profile.title,
					"points": rules.points_of(id),
					"earned": rules.players[id].points_earned,
					"spent": rules.players[id].points_spent,
					"carries": _night.frame["players"][id]["arms"].keys(),
					"buys": int(bot.telemetry.counters.get(&"buys", 0)),
					"rejected": int(bot.telemetry.counters.get(&"rejected_buys", 0)),
					"stuck_longest": snappedf(bot.legs.stuck.longest(), 0.1),
				}
			)
		)
	var report := {
		"seed": int(_args.get("seed", 1)),
		"bots": bots.size(),
		"game_seconds": snappedf(float(ticks) / 60.0, 0.1),
		"wall_seconds": snappedf(wall_seconds, 0.1),
		"round": rules.round_number,
		"over": rules.phase == GameRules.Phase.OVER,
		"links": _links,
		"windows_torn": _tears,
		"boards_back": _repairs,
		"buys": _buys,
		"box_plays": _box_plays,
		"box_places": _box_spots.keys(),
		"most_alive": _most_alive,
		"downs": _downs,
		"revives": _revives,
		"kills": _kills,
		"round_starts": _rounds,
		"round_ends": _ends,
		"players": bots,
	}
	print("SMALLMAP ", JSON.stringify(report))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
