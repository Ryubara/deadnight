extends Node
## The prize crane as hosted bots play it (#1322): bots alone in the lot play a night and every
## crane play is counted per bot: plays bought, prizes offered, prizes taken, prizes lost (and why),
## breakdowns, takes denied and the points the plays cost. For each offer that was lost it prints
## what the bot held, where it stood and what it was doing. A local measurement, not a test.
##
## `godot --headless --path game res://tests/captures/bots_crane_soak.tscn -- --seed=1 --minutes=20`
## Arguments after `--`: `--seed=N`, `--minutes=M` (game minutes), `--bots=N` (default 4),
## `--profile=rookie|regular|veteran|mixed` (default mixed), `--tough=X` (every player's health, a
## multiple of the shipped: the soak measures the crane, not whether the bots live).
## Prints `CRANE {json}` at the end and `LOST {json}` for every offer that went unclaimed.

## Ticks between the physics frames the engine is given (a bought door needs one).
const FRAME_EVERY := 30
const TICKS_PER_SECOND := 60

var _args := {}
var _night: SeatedNight
var _per_bot: Dictionary = {}
var _lost: Array[Dictionary] = []
var _offer: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.health.max_health *= float(_args.get("tough", 1.0))
	var seed_value := int(_args.get("seed", 1))
	_night = await SeatedNight.start(self, int(_args.get("bots", 4)), tuning, seed_value, true)
	var profiles := _profiles()
	for i in profiles.size():
		_night.seat(i + 1, profiles[i], 1000 + 100 * seed_value + i)
	_night.on_event = _on_event
	_night.start_round()
	var limit := int(float(_args.get("minutes", 20)) * 60.0 * TICKS_PER_SECOND)
	var ticks := 0
	while ticks < limit and _night.server.rules.phase != GameRules.Phase.OVER:
		_night.tick()
		ticks += 1
		if ticks % TICKS_PER_SECOND == 0:
			_watch_offer()
		if _args.has("trace") and ticks % 30 == 0:
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


func _profiles() -> Array[BotProfile]:
	var found: Array[BotProfile] = []
	var kind := String(_args.get("profile", "mixed"))
	for i in int(_args.get("bots", 4)):
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


func _count(id: int, key: String, by := 1) -> void:
	var counts: Dictionary = _per_bot.get(id, {})
	counts[key] = int(counts.get(key, 0)) + by
	_per_bot[id] = counts


func _bot(id: int) -> BotClient:
	for bot in _night.host.bots:
		if bot.state.player_id == id:
			return bot
	return null


## Once a second while an offer floats: what the bot is doing, and how near it stands.
func _watch_offer() -> void:
	if _offer.is_empty():
		return
	var id: int = _offer["player"]
	var bot := _bot(id)
	var me: Dictionary = _night.frame["players"][id]
	var prompt: Dictionary = me.get("prompt", {})
	var kind := String(prompt.get("kind", ""))
	_offer["prompts"][kind] = int(_offer["prompts"].get(kind, 0)) + 1
	var note := String(bot.intent.note)
	_offer["notes"][note] = int(_offer["notes"].get(note, 0)) + 1
	_offer["use_seconds"] += 1 if bot.intent.use else 0
	_offer["apart"].append(snappedf(_apart_from_glass(id), 0.1))
	_offer["trail"].append("%s/%s" % [note, kind])


## Metres (flat) from the body to the crane's stand where it now is.
func _apart_from_glass(id: int) -> float:
	var here := _night.server.body_of(id).global_position
	var best := INF
	for spot in _night.server.world.shop_spots():
		if spot["kind"] == &"crane" and spot.get("crane_spot", 0) == _night.server.rules.crane.spot:
			best = minf(best, _night.server.world.reach_distance(here, spot["position"]))
	return best


func _on_event(event: Dictionary) -> void:
	var id := int(event.get("player_id", -1))
	match event["type"]:
		&"crane_spin_started":
			_count(id, "plays")
			var price := _night.server.rules.crane.price
			_count(id, "points_on_plays", price)
		&"crane_prize_ready":
			_count(id, "offers")
			var me: Dictionary = _night.frame["players"][id]
			var view := BotEconomy.View.new()
			view.arms = me.get("arms", {})
			view.held = me.get("weapon", &"")
			var errands := _errands(id)
			view.zombie_health = (
				errands._economy.zombie_health(int(_night.frame.get("round", 1)))
				if errands != null
				else 0.0
			)
			_offer = {
				"player": id,
				"round": _night.server.rules.round_number,
				"weapon": String(event["weapon"]),
				"arms": me.get("arms", {}).keys().map(func(k: Variant) -> String: return String(k)),
				"worth": BotEconomy.worth_taking(view, WeaponCatalog.catalog_id(event["weapon"])),
				"at": float(_night.server.tick_count) / TICKS_PER_SECOND,
				"prompts": {},
				"notes": {},
				"use_seconds": 0,
				"apart": [snappedf(_apart_from_glass(id), 0.1)],
				"trail": [],
			}
		&"crane_prize_taken":
			_count(id, "taken")
			if not _offer.is_empty():
				_offer["reason"] = "taken"
				print("TAKEN ", JSON.stringify(_offer))
			_offer = {}
		&"crane_prize_lost":
			_count(id, "lost_" + String(event["reason"]))
			if not _offer.is_empty():
				_offer["reason"] = String(event["reason"])
				_lost.append(_offer)
				print("LOST ", JSON.stringify(_offer))
			_offer = {}
		&"crane_breakdown":
			_count(id, "breakdowns")
		&"crane_take_denied":
			_count(id, "denied_" + String(event["reason"]))


func _errands(id: int) -> BotErrands:
	var bot := _bot(id)
	if bot == null:
		return null
	return (bot.brain as BotFightBrain).get(&"_errands")


func _report(ticks: int) -> void:
	var bots: Array[Dictionary] = []
	for bot in _night.host.bots:
		var id: int = bot.state.player_id
		var line: Dictionary = _per_bot.get(id, {}).duplicate()
		line["seat"] = id
		line["profile"] = bot.profile.title
		line["points"] = _night.server.rules.points_of(id)
		bots.append(line)
	var report := {
		"seed": int(_args.get("seed", 1)),
		"game_seconds": snappedf(float(ticks) / TICKS_PER_SECOND, 0.1),
		"round": _night.server.rules.round_number,
		"bots": bots,
	}
	print("CRANE ", JSON.stringify(report))


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed


## `--trace=A-B` prints, every half second between game seconds A and B, where each bot stands, what
## it is heading for and what its card says, and the crane's stage.
func _trace(ticks: int) -> void:
	var span := String(_args.get("trace", "")).split("-")
	if span.size() != 2:
		return
	var seconds := float(ticks) / TICKS_PER_SECOND
	if seconds < float(span[0]) or seconds > float(span[1]):
		return
	var crane := _night.server.rules.crane
	var line := (
		"TRACE t=%.1f crane=%d/%d buyer=%d left=%.1f"
		% [seconds, crane.spot, crane.stage, crane.buyer_id, crane.left]
	)
	for bot in _night.host.bots:
		var id: int = bot.state.player_id
		var at := _night.server.body_of(id).global_position
		var me: Dictionary = _night.frame["players"][id]
		line += (
			" | %d (%.1f,%.1f) goal=%s r=%.1f %s %s a=%.1f"
			% [
				id,
				at.x,
				at.z,
				str(bot.intent.goal),
				bot.intent.goal_radius,
				bot.intent.note,
				str(me.get("prompt", {}).get("kind", "")),
				_apart_from_glass(id)
			]
		)
	print(line)
