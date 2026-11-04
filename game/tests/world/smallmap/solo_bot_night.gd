class_name SoloBotNight
extends RefCounted
## One bot alone on the second map for one seed: it plays until it has shown what the solo night
## asks for (and a grace after), until it is downed (a solo bot has no one to revive it, so the
## night is over) or until `SECONDS` have gone, and `failures()` says what it did not do. The suite
## `test_smallmap_bot_night.gd` plays it over seeds and holds a rate; `tests/captures/
## smallmap_solo_sweep.tscn` plays it over a wide range for the measurement behind that rate.

## Game seconds of a night. The solo bot buys the first link and then its first gun (the overlay
## saves for the shotgun, and a bot with only its start gun is offered nothing after a gun it can
## pay for), by 107 s on 12 of 14 seeds and by 225 s on all; a bot starts no errand with a dead
## within 12 m, so the night still runs past the breaks of rounds 5 and 6.
const SECONDS := 330.0
## A night that has shown everything its test asks for runs on this many game seconds more (the cap
## on the dead alive is read to the end) and stops: the asked-for things are events, and an event
## that has happened stays happened.
const GRACE_SECONDS := 30.0
## Ticks between the physics frames the engine is given (a bought link's mesh needs them).
const FRAME_EVERY := 30
const ROUNDS_WANTED := 4
const WINDOWS_TORN_WANTED := 4
const MOST_ALIVE_CAP := 24
## The bot's seed in the night, as the other suites of the map seat their first bot.
const BOT_SEED := 400

var seed_value := 0
var links: Array[StringName] = []
var tears: Dictionary = {}
var buys: Dictionary = {}
var rounds_started := 0
var most_alive := 0
## Game seconds of the first weapon bought, of round 4 beginning and of the bot being downed (-1:
## did not happen).
var weapon_at := -1.0
var round_4_at := -1.0
var over_at := -1.0
var ticks := 0

var _seated: SeatedNight


func _init(seed_in: int) -> void:
	seed_value = seed_in


## Plays the night under `parent` (a node in the tree, for the physics frames).
func play(parent: Node) -> void:
	_seated = await SmallMapNight.seat(parent, 1, null, seed_value)
	_seated.seat(1, BotProfile.regular(), BOT_SEED)
	_seated.on_event = _on_event
	_seated.start_round()
	var done_at := -1
	for tick in int(SECONDS * 60.0):
		ticks = tick
		_seated.tick()
		most_alive = maxi(most_alive, _seated.server.sim.standing_count())
		if _seated.server.rules.phase == GameRules.Phase.OVER:
			over_at = tick / 60.0
			break
		if done_at < 0 and _has_shown_it():
			done_at = tick
		if done_at >= 0 and tick - done_at >= int(GRACE_SECONDS * 60.0):
			break
		if tick % FRAME_EVERY == 0:
			await parent.get_tree().physics_frame
	_seated.dispose()
	_seated = null


## What the night did not show, one line each; empty when it showed all.
func failures() -> Array[String]:
	var out: Array[String] = []
	if rounds_started < ROUNDS_WANTED:
		out.append("round %d" % rounds_started)
	if not links.has(&"door_side"):
		out.append("no first link")
	if tears.size() < WINDOWS_TORN_WANTED:
		out.append("%d windows torn" % tears.size())
	if weapon_at < 0.0:
		out.append("no weapon, bought %s" % [buys.keys()])
	if most_alive > MOST_ALIVE_CAP:
		out.append("%d dead at once" % most_alive)
	if not out.is_empty() and over_at >= 0.0:
		out.append("downed at %.0f s" % over_at)
	return out


func summary() -> String:
	return (
		(
			"seed=%d ok=%s round=%d link=%s tears=%d weapon_s=%.0f round4_s=%.0f"
			+ " over_s=%.0f most=%d bought=%s"
		)
		% [
			seed_value,
			failures().is_empty(),
			rounds_started,
			links.has(&"door_side"),
			tears.size(),
			weapon_at,
			round_4_at,
			over_at,
			most_alive,
			buys.keys(),
		]
	)


func _has_shown_it() -> bool:
	return (
		rounds_started >= ROUNDS_WANTED
		and links.has(&"door_side")
		and tears.size() >= WINDOWS_TORN_WANTED
		and weapon_at >= 0.0
	)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"door_opened":
			links.append(event["door_id"])
		&"board_torn":
			tears[event["barricade_id"]] = int(tears.get(event["barricade_id"], 0)) + 1
		&"purchase_made":
			buys[event["item_id"]] = int(buys.get(event["item_id"], 0)) + 1
			var kind := _seated.server.rules.tuning.economy.item(event["item_id"]).kind
			if weapon_at < 0.0 and (kind == ShopItem.Kind.WEAPON or kind == ShopItem.Kind.CRANE):
				weapon_at = ticks / 60.0
		&"round_started":
			rounds_started = maxi(rounds_started, int(event["round"]))
			if rounds_started == ROUNDS_WANTED and round_4_at < 0.0:
				round_4_at = ticks / 60.0
