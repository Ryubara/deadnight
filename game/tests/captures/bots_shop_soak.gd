extends Node
## The shopping soak of the bots plan (phase 4): hosted bots alone in the lot (no person) play a
## night, and what they bought is printed: points spent by category per bot, the order the doors
## opened in, every refused buy, the longest time each held more than twice the price of the next
## thing on its list, and the boards put back. A local or nightly measurement, not a test.
##
## `godot --headless --path game res://tests/captures/bots_shop_soak.tscn -- --seed=1 --minutes=20`
## Arguments after `--`: `--seed=N`, `--minutes=M` (game minutes), `--bots=N` (default 4),
## `--profile=rookie|regular|veteran|mixed` (default mixed), `--tough=X` (every player's health, a
## multiple of the shipped: the soak measures what the bots buy, not whether they live), `--break=S`
## (seconds of the break between rounds, 0 for the tuned 5), `--noerrands` (the bots do none:
## the cost of a think without them), `--trace` (a line every 15 s).
## Prints `SHOP {json}` at the end.

## Ticks between the physics frames the engine is given (a bought door needs one).
const FRAME_EVERY := 30
## The categories points are counted in.
const CATEGORIES := {
	ShopItem.Kind.DOOR: "door",
	ShopItem.Kind.WEAPON: "weapon",
	ShopItem.Kind.CRANE: "crane",
	ShopItem.Kind.TONIC: "tonic",
	ShopItem.Kind.FUEL: "fuel",
	ShopItem.Kind.GRENADES: "grenades",
	ShopItem.Kind.AMMO: "ammo",
	ShopItem.Kind.UPGRADE: "upgrade",
}
## Seconds within which the same item refused again counts as a loop.
const LOOP_WINDOW := 30.0

var _args := {}
var _night: SeatedNight
var _spent: Dictionary = {}
var _doors: Array[StringName] = []
var _denials: Array[Dictionary] = []
var _rounds: Dictionary = {}
var _ends: Dictionary = {}
var _boards := 0


func _ready() -> void:
	_args = _parse_args()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 1.0))
	var break_seconds := float(_args.get("break", 0.0))
	var seed_value := int(_args.get("seed", 1))
	if break_seconds > 0.0:
		tuning.rounds.break_seconds = break_seconds
	_night = await SeatedNight.start(self, int(_args.get("bots", 4)), tuning, seed_value, true)
	var profiles := _profiles()
	for profile in profiles:
		profile.errands = not _args.has("noerrands")
	for i in profiles.size():
		_night.seat(i + 1, profiles[i], 1000 + 100 * seed_value + i)
	_night.on_event = _on_event
	_night.start_round()
	var limit := int(float(_args.get("minutes", 20)) * 60.0 * 60.0)
	var ticks := 0
	while ticks < limit and _night.server.rules.phase != GameRules.Phase.OVER:
		_night.tick()
		ticks += 1
		if _args.has("trace") and ticks % 900 == 0:
			_trace(ticks)
		# The navigation server takes a bought door's mesh in only on a physics frame.
		if ticks % FRAME_EVERY == 0:
			await get_tree().physics_frame
	_report(ticks)
	for _i in 600:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().process_frame
	_night.dispose()
	await get_tree().process_frame
	get_tree().quit()


func _trace(ticks: int) -> void:
	var line := (
		"TRACE t=%d round=%d phase=%d remaining=%d"
		% [
			ticks / 60,
			_night.server.rules.round_number,
			_night.server.rules.phase,
			_night.server.rules.zombies_remaining()
		]
	)
	for bot in _night.host.bots:
		var at := _night.server.body_of(bot.state.player_id).global_position
		line += (
			" | %d pts=%d %s (%d,%d) goal=%s prompt=%s unreach=%d"
			% [
				bot.state.player_id,
				_night.server.rules.points_of(bot.state.player_id),
				bot.intent.note,
				at.x,
				at.z,
				str(bot.intent.goal),
				str(bot.state.me().get("prompt", {}).get("kind", "")),
				bot.legs.path.unreachable_marks
			]
		)
	var ids: Array = _night.server.sim.zombies.keys()
	ids.sort()
	for id in ids:
		var zombie: ZombieBody = _night.server.sim.zombies[id]
		if zombie.is_alive():
			line += (
				" Z%d(%d,%d m%d g=%s)"
				% [id, zombie.position.x, zombie.position.z, zombie.mode, zombie.gate_id]
			)
	print(line)


func _profiles() -> Array[BotProfile]:
	var count := int(_args.get("bots", 4))
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


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"purchase_made":
			var item := _night.server.rules.tuning.economy.item(event["item_id"])
			var category: String = CATEGORIES.get(item.kind, "other")
			var by_player: Dictionary = _spent.get(event["player_id"], {})
			by_player[category] = int(by_player.get(category, 0)) + int(event["price"])
			_spent[event["player_id"]] = by_player
		&"purchase_denied":
			(
				_denials
				. append(
					{
						"player": event["player_id"],
						"item": String(event["item_id"]),
						"at": float(_night.server.tick_count) / 60.0,
						"result": event["result"],
					}
				)
			)
		&"door_opened":
			_doors.append(event["door_id"])
		&"board_repaired":
			_boards += 1
		&"round_started":
			_rounds[event["round"]] = float(_night.server.tick_count) / 60.0
		&"round_ended":
			_ends[event["round"]] = float(_night.server.tick_count) / 60.0


func _report(ticks: int) -> void:
	var rounds: int = _night.server.rules.round_number
	var bots: Array[Dictionary] = []
	for bot in _night.host.bots:
		var errands: BotErrands = (bot.brain as BotFightBrain).get(&"_errands")
		if errands == null:
			errands = BotErrands.new(BotShop.new(), bot.profile)
		(
			bots
			. append(
				{
					"seat": bot.state.player_id,
					"profile": bot.profile.title,
					"spent": _spent.get(bot.state.player_id, {}),
					"points": _night.server.rules.points_of(bot.state.player_id),
					"earned": _night.server.rules.players[bot.state.player_id].points_earned,
					"spent_total": _night.server.rules.players[bot.state.player_id].points_spent,
					"longest_glut": snappedf(errands.longest_glut, 0.1),
					"glut_by_round": errands.glut_by_round,
					"wants": errands.wants_now(),
					"carries": _night.frame["players"][bot.state.player_id]["arms"].keys(),
					"errands": errands.counts,
					"rejected": int(bot.telemetry.counters.get(&"rejected_buys", 0)),
					"buys": int(bot.telemetry.counters.get(&"buys", 0)),
					"stuck_longest": snappedf(bot.legs.stuck.longest(), 0.1),
					"think_us_p99": bot.telemetry.think_us(0.99),
				}
			)
		)
	var loops := 0
	var last: Dictionary = {}
	for denial in _denials:
		var key := "%s:%s" % [denial["player"], denial["item"]]
		if last.has(key) and denial["at"] - last[key] < LOOP_WINDOW - 1.0:
			loops += 1
		last[key] = denial["at"]
	var report := {
		"seed": int(_args.get("seed", 1)),
		"game_seconds": snappedf(float(ticks) / 60.0, 0.1),
		"round": rounds,
		"over": _night.server.rules.phase == GameRules.Phase.OVER,
		"doors": _doors,
		"denials": _denials.size(),
		"denial_loops": loops,
		"boards": _boards,
		"round_starts": _rounds,
		"round_ends": _ends,
		"bots": bots,
	}
	print("SHOP ", JSON.stringify(report))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
